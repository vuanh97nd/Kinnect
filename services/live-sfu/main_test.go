package main

import (
	"bytes"
	"fmt"
	"github.com/gorilla/websocket"
	"github.com/pion/rtp"
	"github.com/pion/webrtc/v4"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

type testReceiver struct {
	pc      *webrtc.PeerConnection
	mu      sync.Mutex
	remote  bool
	pending []webrtc.ICECandidateInit
	packets chan []byte
}

func TestControlAuth(t *testing.T) {
	api, _ := newAPI()
	server := httptest.NewServer(handler(strings.Repeat("s", 32), api))
	defer server.Close()
	response, e := http.Get(server.URL + "/health")
	if e != nil {
		t.Fatal(e)
	}
	defer response.Body.Close()
	if response.StatusCode != 401 {
		t.Fatal("public control health should require authentication")
	}
	_, response, e = websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(server.URL, "http")+"/control", nil)
	if e == nil || response.StatusCode != 401 {
		t.Fatal("unauthenticated control accepted")
	}
}
func TestSingleUplinkFansOutAndRevocationStopsDelivery(t *testing.T) {
	api, e := newAPI()
	if e != nil {
		t.Fatal(e)
	}
	secret := strings.Repeat("s", 32)
	server := httptest.NewServer(handler(secret, api))
	defer server.Close()
	ws, _, e := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(server.URL, "http")+"/control", http.Header{"Authorization": []string{"Bearer " + secret}})
	if e != nil {
		t.Fatal(e)
	}
	defer ws.Close()
	var ready message
	if e = ws.ReadJSON(&ready); e != nil || ready.Type != "ready" {
		t.Fatal("control not ready")
	}
	var write sync.Mutex
	send := func(m message) { write.Lock(); defer write.Unlock(); _ = ws.WriteJSON(m) }
	receivers := map[string]*testReceiver{}
	var peers sync.Mutex
	ack := make(chan int, 8)
	problems := make(chan string, 8)
	quit := make(chan struct{})
	upstream, e := webrtc.NewPeerConnection(webrtc.Configuration{})
	if e != nil {
		t.Fatal(e)
	}
	defer upstream.Close()
	upState := &testReceiver{pc: upstream, packets: make(chan []byte, 128)}
	receivers["host/@sfu"] = upState
	defer func() {
		peers.Lock()
		defer peers.Unlock()
		for _, p := range receivers {
			_ = p.pc.Close()
		}
	}()
	candidate := func(member, pub string, pc *webrtc.PeerConnection) {
		pc.OnICECandidate(func(ice *webrtc.ICECandidate) {
			if ice == nil {
				return
			}
			v := ice.ToJSON()
			send(message{Type: "signal", Room: "test-room", Revision: 1, From: member, To: pub, Candidate: &v})
		})
	}
	candidate("host", "@sfu", upstream)
	go func() {
		defer close(quit)
		for {
			var m message
			if ws.ReadJSON(&m) != nil {
				return
			}
			if m.Type == "synced" {
				ack <- m.Revision
				continue
			}
			if m.Type == "media-error" {
				problems <- m.Error
				continue
			}
			if m.Type != "signal" {
				continue
			}
			id := key(m.To, m.From)
			peers.Lock()
			p := receivers[id]
			if p == nil {
				pc, err := webrtc.NewPeerConnection(webrtc.Configuration{})
				if err != nil {
					peers.Unlock()
					problems <- err.Error()
					return
				}
				p = &testReceiver{pc: pc, packets: make(chan []byte, 128)}
				receivers[id] = p
				candidate(m.To, m.From, pc)
				target := p
				pc.OnTrack(func(track *webrtc.TrackRemote, _ *webrtc.RTPReceiver) {
					for {
						packet, _, err := track.ReadRTP()
						if err != nil {
							return
						}
						select {
						case target.packets <- append([]byte(nil), packet.Payload...):
						default:
						}
					}
				})
			}
			peers.Unlock()
			p.mu.Lock()
			if m.Candidate != nil {
				if p.remote {
					_ = p.pc.AddICECandidate(*m.Candidate)
				} else {
					p.pending = append(p.pending, *m.Candidate)
				}
			}
			if m.Description != nil {
				if err := p.pc.SetRemoteDescription(*m.Description); err != nil {
					problems <- err.Error()
					p.mu.Unlock()
					return
				}
				p.remote = true
				for _, ice := range p.pending {
					_ = p.pc.AddICECandidate(ice)
				}
				p.pending = nil
				if m.Description.Type == webrtc.SDPTypeOffer {
					answer, err := p.pc.CreateAnswer(nil)
					if err == nil {
						err = p.pc.SetLocalDescription(answer)
					}
					if err != nil {
						problems <- err.Error()
						p.mu.Unlock()
						return
					}
					send(message{Type: "signal", Room: "test-room", Revision: 1, From: m.To, To: m.From, Description: &answer})
				}
			}
			p.mu.Unlock()
		}
	}()
	members := []memberSpec{{ID: "host", Publisher: true}, {ID: "viewer-one", Subscriptions: []string{"host"}}, {ID: "viewer-two", Subscriptions: []string{"host"}}}
	viewerCount := 2
	if value := os.Getenv("KINNECT_SFU_TEST_VIEWERS"); value != "" {
		viewerCount, _ = strconv.Atoi(value)
		if viewerCount < 2 || viewerCount > 200 {
			t.Fatal("invalid viewer audit count")
		}
	}
	for i := 2; i < viewerCount; i++ {
		members = append(members, memberSpec{ID: fmt.Sprintf("viewer-%d", i), Subscriptions: []string{"host"}})
	}
	send(message{Type: "sync", Room: "test-room", Revision: 1, Publishers: []publisherSpec{{ID: "host", Mode: "video"}}, Members: members})
	select {
	case <-ack:
	case <-time.After(8 * time.Second):
		t.Fatal("sync timeout")
	}
	video, e := webrtc.NewTrackLocalStaticRTP(webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeVP8, ClockRate: 90000}, "video", "kinnect")
	if e != nil {
		t.Fatal(e)
	}
	sender, e := upstream.AddTrack(video)
	if e != nil {
		t.Fatal(e)
	}
	go func() {
		for {
			if _, _, err := sender.ReadRTCP(); err != nil {
				return
			}
		}
	}()
	offer, e := upstream.CreateOffer(nil)
	if e != nil {
		t.Fatal(e)
	}
	if e = upstream.SetLocalDescription(offer); e != nil {
		t.Fatal(e)
	}
	send(message{Type: "signal", Room: "test-room", Revision: 1, From: "host", To: "@sfu", Description: &offer})
	stop := make(chan struct{})
	defer close(stop)
	payload := []byte{0x10, 0x00, 0x00, 0x00, 0x9d, 0x01, 0x2a, 0x10}
	go func() {
		tick := time.NewTicker(20 * time.Millisecond)
		defer tick.Stop()
		var sequence uint16
		for {
			select {
			case <-stop:
				return
			case <-tick.C:
				sequence++
				_ = video.WriteRTP(&rtp.Packet{Header: rtp.Header{Version: 2, SequenceNumber: sequence, Timestamp: uint32(sequence) * 1800, SSRC: 1234, PayloadType: 96, Marker: true}, Payload: payload})
			}
		}
	}()
	get := func(id string) *testReceiver {
		deadline := time.Now().Add(10 * time.Second)
		for time.Now().Before(deadline) {
			peers.Lock()
			p := receivers[id]
			peers.Unlock()
			if p != nil {
				return p
			}
			time.Sleep(10 * time.Millisecond)
		}
		t.Fatal("receiver missing ", id)
		return nil
	}
	one := get("viewer-one/host")
	two := get("viewer-two/host")
	receive := func(p *testReceiver) {
		select {
		case data := <-p.packets:
			if !bytes.Equal(data, payload) {
				t.Fatal("RTP payload changed")
			}
		case problem := <-problems:
			t.Fatal(problem)
		case <-time.After(15 * time.Second):
			t.Fatal("no forwarded RTP")
		}
	}
	receive(one)
	receive(two)
	for _, member := range members[3:] {
		receive(get(key(member.ID, "host")))
	}
	t.Logf("Actual RTP fanout verified for%d receivers from one uplink (synthetic low bitrate; not a capacity benchmark)", viewerCount)
	send(message{Type: "sync", Room: "test-room", Revision: 1, Publishers: []publisherSpec{{ID: "host", Mode: "video"}}, Members: []memberSpec{members[0], members[2]}})
	select {
	case <-ack:
	case <-time.After(3 * time.Second):
		t.Fatal("revoke timeout")
	}
	time.Sleep(100 * time.Millisecond)
	for len(one.packets) > 0 {
		<-one.packets
	}
	select {
	case <-one.packets:
		t.Fatal("removed subscriber still receives media")
	case <-time.After(200 * time.Millisecond):
	}
	receive(two)
	peers.Lock()
	count := 0
	for id := range receivers {
		if strings.HasPrefix(id, "host/") {
			count++
		}
	}
	peers.Unlock()
	if count != 1 {
		t.Fatal("publisher needs exactly one uplink")
	}
	send(message{Type: "signal", Room: "test-room", Revision: 1, From: "viewer-two", To: "@sfu", Description: &offer})
	select {
	case <-problems:
	case <-time.After(3 * time.Second):
		t.Fatal("viewer publishing was not rejected")
	}
	_ = ws.Close()
	select {
	case <-quit:
	case <-time.After(2 * time.Second):
		t.Fatal("control shutdown stuck")
	}
}
