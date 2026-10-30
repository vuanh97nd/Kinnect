// Kinnect SFU: trusted backend control socket, one uplink per publisher,
// independent receive-only downlinks. No accounts, chat or media recording here.
package main

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"github.com/pion/ice/v4"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
 "runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/gorilla/websocket"
	"github.com/pion/rtcp"
	"github.com/pion/webrtc/v4"
)

type publisherSpec struct {
	ID   string `json:"id"`
	Mode string `json:"mode"`
}
type memberSpec struct {
	ID            string   `json:"id"`
	Publisher     bool     `json:"publisher"`
	Subscriptions []string `json:"subscriptions"`
}
type message struct {
	Type        string                     `json:"type"`
	Room        string                     `json:"room"`
	Revision    int                        `json:"revision"`
	From        string                     `json:"from,omitempty"`
	To          string                     `json:"to,omitempty"`
	Publishers  []publisherSpec            `json:"publishers,omitempty"`
	Members     []memberSpec               `json:"members,omitempty"`
	ICE         []webrtc.ICEServer         `json:"iceServers,omitempty"`
	Description *webrtc.SessionDescription `json:"description,omitempty"`
	Candidate   *webrtc.ICECandidateInit   `json:"candidate,omitempty"`
	Error       string                     `json:"error,omitempty"`
}
type publisher struct {
	audio, video *webrtc.TrackLocalStaticRTP
	upstream     *peer
	videoSSRC    uint32
	withVideo    bool
	lastPLI      time.Time
}
type peer struct {
	pc        *webrtc.PeerConnection
	remote    bool
	pending   []webrtc.ICECandidateInit
	publisher string
	member    string
	upstream  bool
	mu        sync.Mutex
}
type room struct {
	revision   int
	publishers map[string]*publisher
	members    map[string]memberSpec
	peers      map[string]*peer
	ice        []webrtc.ICEServer
}
type control struct {
	ws    *websocket.Conn
	write sync.Mutex
	mu    sync.Mutex
	rooms map[string]*room
	api   *webrtc.API
}

func (c *control) send(m message) {
	c.write.Lock()
	defer c.write.Unlock()
	_ = c.ws.SetWriteDeadline(time.Now().Add(5 * time.Second))
	_ = c.ws.WriteJSON(m)
}
func (c *control) drop(id string) {
	r := c.rooms[id]
	delete(c.rooms, id)
	if r != nil {
		for _, p := range r.peers {
			_ = p.pc.Close()
		}
	}
}
func newPublisher(mode string) (*publisher, error) {
	a, e := webrtc.NewTrackLocalStaticRTP(webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeOpus, ClockRate: 48000, Channels: 2, SDPFmtpLine: "minptime=10;useinbandfec=1"}, "audio", "kinnect")
	if e != nil {
		return nil, e
	}
	v, e := webrtc.NewTrackLocalStaticRTP(webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeVP8, ClockRate: 90000, RTCPFeedback: []webrtc.RTCPFeedback{{Type: "nack"}, {Type: "nack", Parameter: "pli"}, {Type: "ccm", Parameter: "fir"}, {Type: "goog-remb"}}}, "video", "kinnect")
	return &publisher{audio: a, video: v, withVideo: mode != "audio"}, e
}
func key(member, pub string) string { return member + "/" + pub }
func contains(ids []string, id string) bool {
	for _, v := range ids {
		if v == id {
			return true
		}
	}
	return false
}
func (c *control) newPeer(roomID, memberID, pubID string, r *room, up bool) (*peer, error) {
	pc, e := c.api.NewPeerConnection(webrtc.Configuration{ICEServers: r.ice})
	if e != nil {
		return nil, e
	}
	p := &peer{pc: pc, publisher: pubID, member: memberID, upstream: up}
	revision := r.revision
	pc.OnICECandidate(func(ice *webrtc.ICECandidate) {
		if ice == nil {
			return
		}
		value := ice.ToJSON()
		from := pubID
		if up {
			from = "@sfu"
		}
		c.send(message{Type: "signal", Room: roomID, Revision: revision, From: from, To: memberID, Candidate: &value})
	})
	pc.OnConnectionStateChange(func(s webrtc.PeerConnectionState) {
		if s == webrtc.PeerConnectionStateFailed {
			c.send(message{Type: "media-error", Room: roomID, Revision: revision, To: memberID, Error: "Media connection failed"})
			_ = pc.Close()
		}
	})
	pub := r.publishers[pubID]
	if pub == nil {
		_ = pc.Close()
		return nil, errors.New("publisher missing")
	}
	if up {
		pub.upstream = p
		if _, e = pc.AddTransceiverFromKind(webrtc.RTPCodecTypeAudio, webrtc.RTPTransceiverInit{Direction: webrtc.RTPTransceiverDirectionRecvonly}); e != nil {
			return nil, e
		}
		if pub.withVideo {
			if _, e = pc.AddTransceiverFromKind(webrtc.RTPCodecTypeVideo, webrtc.RTPTransceiverInit{Direction: webrtc.RTPTransceiverDirectionRecvonly}); e != nil {
				return nil, e
			}
		}
		pc.OnTrack(func(track *webrtc.TrackRemote, _ *webrtc.RTPReceiver) {
			output := pub.audio
			if track.Kind() == webrtc.RTPCodecTypeVideo {
				output = pub.video
				c.mu.Lock()
				pub.videoSSRC = uint32(track.SSRC())
				c.mu.Unlock()
			}
			done := make(chan struct{})
			defer close(done)
			if track.Kind() == webrtc.RTPCodecTypeVideo {
				go func() {
					tick := time.NewTicker(2 * time.Second)
					defer tick.Stop()
					for {
						select {
						case <-done:
							return
						case <-tick.C:
							_ = pc.WriteRTCP([]rtcp.Packet{&rtcp.ReceiverEstimatedMaximumBitrate{Bitrate: 1500000, SSRCs: []uint32{uint32(track.SSRC())}}})
						}
					}
				}()
			}
			for {
				packet, _, err := track.ReadRTP()
				if err != nil {
					return
				}
				_ = output.WriteRTP(packet)
			}
		})
	} else {
		tracks := []*webrtc.TrackLocalStaticRTP{pub.audio}
		if pub.withVideo {
			tracks = append(tracks, pub.video)
		}
		for _, track := range tracks {
			transceiver, err := pc.AddTransceiverFromTrack(track, webrtc.RTPTransceiverInit{Direction: webrtc.RTPTransceiverDirectionSendonly})
			var sender *webrtc.RTPSender
			if err == nil {
				sender = transceiver.Sender()
			}
			if err != nil {
				_ = pc.Close()
				return nil, err
			}
			go func(s *webrtc.RTPSender) {
				for {
					packets, _, err := s.ReadRTCP()
					if err != nil {
						return
					}
					for _, feedback := range packets {
						switch feedback.(type) {
						case *rtcp.PictureLossIndication, *rtcp.FullIntraRequest:
							c.mu.Lock()
							source := pub.upstream
							ssrc := pub.videoSSRC
							allow := time.Since(pub.lastPLI) > 250*time.Millisecond
							if allow {
								pub.lastPLI = time.Now()
							}
							c.mu.Unlock()
							if source != nil && ssrc != 0 && allow {
								_ = source.pc.WriteRTCP([]rtcp.Packet{&rtcp.PictureLossIndication{MediaSSRC: ssrc}})
							}
						}
					}
				}
			}(sender)
		}
	}
	return p, nil
}
func (c *control) syncRoom(m message) error {
	if m.Room == "" || len(m.Members) > 5001 || len(m.Publishers) > 4 || m.Revision < 1 {
		return errors.New("invalid room")
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	r := c.rooms[m.Room]
	if r != nil && m.Revision < r.revision {
		return errors.New("stale room")
	}
	if r == nil || m.Revision != r.revision {
		c.drop(m.Room)
		r = &room{revision: m.Revision, publishers: map[string]*publisher{}, members: map[string]memberSpec{}, peers: map[string]*peer{}, ice: m.ICE}
		c.rooms[m.Room] = r
		for _, s := range m.Publishers {
			p, e := newPublisher(s.Mode)
			if e != nil {
				return e
			}
			r.publishers[s.ID] = p
		}
	}
	next := map[string]memberSpec{}
	for _, s := range m.Members {
		next[s.ID] = s
	}
	r.members = next
	for id, p := range r.peers {
		spec, ok := next[p.member]
		keep := ok && ((p.upstream && spec.Publisher) || (!p.upstream && contains(spec.Subscriptions, p.publisher)))
		if !keep {
			_ = p.pc.Close()
			delete(r.peers, id)
		}
	}
	for member, spec := range next {
		for _, pub := range spec.Subscriptions {
			if _, ok := r.publishers[pub]; !ok {
				return errors.New("unknown publisher")
			}
			id := key(member, pub)
			if r.peers[id] != nil {
				continue
			}
			p, e := c.newPeer(m.Room, member, pub, r, false)
			if e != nil {
				return e
			}
			r.peers[id] = p
			offer, e := p.pc.CreateOffer(nil)
			if e != nil {
				return e
			}
			if e = p.pc.SetLocalDescription(offer); e != nil {
				return e
			}
			c.send(message{Type: "signal", Room: m.Room, Revision: r.revision, From: pub, To: member, Description: &offer})
		}
	}
	return nil
}
func (c *control) signalPeer(m message) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	r := c.rooms[m.Room]
	if r == nil || m.Revision != r.revision {
		return errors.New("stale room")
	}
	member, ok := r.members[m.From]
	if !ok {
		return errors.New("unknown member")
	}
	up := m.To == "@sfu"
	id := key(m.From, m.To)
	p := r.peers[id]
	if up && !member.Publisher {
		return errors.New("viewer cannot publish")
	}
	if !up && !contains(member.Subscriptions, m.To) {
		return errors.New("subscription denied")
	}
	if p == nil {
		if !up {
			return errors.New("peer not ready")
		}
		var e error
		p, e = c.newPeer(m.Room, m.From, m.From, r, true)
		if e != nil {
			return e
		}
		r.peers[id] = p
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	if m.Candidate != nil {
		if !p.remote {
			if len(p.pending) >= 100 {
				return errors.New("too many candidates")
			}
			p.pending = append(p.pending, *m.Candidate)
			return nil
		}
		return p.pc.AddICECandidate(*m.Candidate)
	}
	if m.Description == nil {
		return errors.New("missing signal")
	}
	if up && m.Description.Type != webrtc.SDPTypeOffer || !up && m.Description.Type != webrtc.SDPTypeAnswer {
		return errors.New("invalid description")
	}
	if e := p.pc.SetRemoteDescription(*m.Description); e != nil {
		return e
	}
	p.remote = true
	for _, ice := range p.pending {
		_ = p.pc.AddICECandidate(ice)
	}
	p.pending = nil
	if up {
		answer, e := p.pc.CreateAnswer(nil)
		if e != nil {
			return e
		}
		if e = p.pc.SetLocalDescription(answer); e != nil {
			return e
		}
		c.send(message{Type: "signal", Room: m.Room, Revision: r.revision, From: "@sfu", To: m.From, Description: &answer})
	}
	return nil
}
func newAPI(settings ...webrtc.SettingEngine) (*webrtc.API, error) {
	m := &webrtc.MediaEngine{}
	if e := m.RegisterCodec(webrtc.RTPCodecParameters{RTPCodecCapability: webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeOpus, ClockRate: 48000, Channels: 2, SDPFmtpLine: "minptime=10;useinbandfec=1"}, PayloadType: 111}, webrtc.RTPCodecTypeAudio); e != nil {
		return nil, e
	}
	if e := m.RegisterCodec(webrtc.RTPCodecParameters{RTPCodecCapability: webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeVP8, ClockRate: 90000, RTCPFeedback: []webrtc.RTCPFeedback{{Type: "nack"}, {Type: "nack", Parameter: "pli"}, {Type: "ccm", Parameter: "fir"}, {Type: "goog-remb"}}}, PayloadType: 96}, webrtc.RTPCodecTypeVideo); e != nil {
		return nil, e
	}
	if len(settings) > 0 {
		return webrtc.NewAPI(webrtc.WithMediaEngine(m), webrtc.WithSettingEngine(settings[0])), nil
	}
	return webrtc.NewAPI(webrtc.WithMediaEngine(m)), nil
}
func handler(secret string, api *webrtc.API) http.Handler {
	mux := http.NewServeMux()
 var active sync.Map
	authorized := func(r *http.Request) bool {
		return subtle.ConstantTimeCompare([]byte(r.Header.Get("Authorization")), []byte("Bearer "+secret)) == 1
	}
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		if !authorized(r) {
			http.Error(w, "unauthorized", 401)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"ok":true,"service":"kinnect-sfu","protocol":1}`))
	})
 mux.HandleFunc("/metrics",func(w http.ResponseWriter,r *http.Request){if !authorized(r){http.Error(w,"unauthorized",401);return};rooms,uplinks,downlinks:=0,0,0;active.Range(func(k,v any)bool{c:=k.(*control);c.mu.Lock();rooms+=len(c.rooms);for _,room:=range c.rooms{for _,peer:=range room.peers{if peer.upstream{uplinks++}else{downlinks++}}};c.mu.Unlock();return true});var memory runtime.MemStats;runtime.ReadMemStats(&memory);w.Header().Set("Content-Type","application/json");_ = json.NewEncoder(w).Encode(map[string]any{"rooms":rooms,"publisherUplinks":uplinks,"subscriberDownlinks":downlinks,"heapBytes":memory.HeapAlloc})})
	mux.HandleFunc("/control", func(w http.ResponseWriter, r *http.Request) {
		if !authorized(r) {
			http.Error(w, "unauthorized", 401)
			return
		}
		upgrader := websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return r.Header.Get("Origin") == "" }}
		ws, e := upgrader.Upgrade(w, r, nil)
		if e != nil {
			return
		}
		c := &control{ws: ws, rooms: map[string]*room{}, api: api}
 active.Store(c,true)
 defer active.Delete(c)
		defer func() {
			c.mu.Lock()
			for id := range c.rooms {
				c.drop(id)
			}
			c.mu.Unlock()
			_ = ws.Close()
		}()
		ws.SetReadLimit(4 << 20)
		c.send(message{Type: "ready"})
		for {
			_ = ws.SetReadDeadline(time.Now().Add(35 * time.Second))
			_, data, e := ws.ReadMessage()
			if e != nil {
				return
			}
			var m message
			if json.Unmarshal(data, &m) != nil {
				continue
			}
			switch m.Type {
			case "sync":
				e = c.syncRoom(m)
				if e == nil {
					c.send(message{Type: "synced", Room: m.Room, Revision: m.Revision})
				}
			case "signal":
				e = c.signalPeer(m)
			case "delete":
				c.mu.Lock()
				c.drop(m.Room)
				c.mu.Unlock()
			case "ping":
				c.send(message{Type: "pong"})
			}
			if e != nil {
				c.send(message{Type: "media-error", Room: m.Room, Revision: m.Revision, To: m.From, Error: "Media setup failed"})
			}
		}
	})
	return mux
}
func main() {
	secret := os.Getenv("KINNECT_SFU_SECRET")
	if len(secret) < 32 {
		log.Fatal("KINNECT_SFU_SECRET must contain at least32 characters")
	}
	addr := os.Getenv("KINNECT_SFU_LISTEN")
	if addr == "" {
		addr = "127.0.0.1:7885"
	}
	port := 7886
	if value := os.Getenv("KINNECT_SFU_UDP_PORT"); value != "" {
		var err error
		port, err = strconv.Atoi(value)
		if err != nil || port < 1 || port > 65535 {
			log.Fatal("Invalid SFU UDP port")
		}
	}
	udp, e := net.ListenUDP("udp4", &net.UDPAddr{Port: port})
	if e != nil {
		log.Fatal(e)
	}
	defer udp.Close()
	settings := webrtc.SettingEngine{}
	settings.SetICEUDPMux(ice.NewUDPMuxDefault(ice.UDPMuxParams{UDPConn: udp}))
	if public := os.Getenv("KINNECT_SFU_PUBLIC_IPS"); public != "" {
		ips := strings.Split(public, ",")
		for i, ip := range ips {
			ips[i] = strings.TrimSpace(ip)
			if net.ParseIP(ips[i]) == nil {
				log.Fatal("Invalid SFU public IP")
			}
		}
		settings.SetNAT1To1IPs(ips, webrtc.ICECandidateTypeHost)
	}
	api, e := newAPI(settings)
	if e != nil {
		log.Fatal(e)
	}
	server := &http.Server{Addr: addr, Handler: handler(secret, api), ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 60 * time.Second}
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-stop
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = server.Shutdown(ctx)
	}()
	log.Print("Kinnect SFU control listening on ", addr)
	if e = server.ListenAndServe(); e != nil && e != http.ErrServerClosed {
		log.Fatal(e)
	}
}
