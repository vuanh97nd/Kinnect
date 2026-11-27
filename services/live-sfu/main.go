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
func (c *control) dropLocked(id string) []*webrtc.PeerConnection {
	r := c.rooms[id]
	delete(c.rooms, id)
	if r == nil {
		return nil
	}
	for _, pub := range r.publishers {
		pub.upstream = nil
	}
	pcs := make([]*webrtc.PeerConnection, 0, len(r.peers))
	for _, p := range r.peers {
		pcs = append(pcs, p.pc)
	}
	return pcs
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
func samePublishers(existing map[string]*publisher, specs []publisherSpec) bool {
	if len(existing) != len(specs) {
		return false
	}
	seen := make(map[string]bool, len(specs))
	for _, s := range specs {
		if seen[s.ID] {
			return false
		}
		seen[s.ID] = true
		pub, ok := existing[s.ID]
		if !ok || pub.withVideo != (s.Mode != "audio") {
			return false
		}
	}
	return true
}
func (c *control) newPeer(roomID, memberID, pubID string, r *room, up bool) (*peer, error) {
	pub := r.publishers[pubID]
	if pub == nil {
		return nil, errors.New("publisher missing")
	}
	pc, e := c.api.NewPeerConnection(webrtc.Configuration{ICEServers: r.ice})
	if e != nil {
		return nil, e
	}
	p := &peer{pc: pc, publisher: pubID, member: memberID, upstream: up}
	revision := r.revision
	peerKey := key(memberID, pubID)
	if up {
		peerKey = key(memberID, "@sfu")
	}
	pc.OnICECandidate(func(ice *webrtc.ICECandidate) {
		if ice == nil {
			return
		}
		value := ice.ToJSON()
		from := pubID
		if up {
			from = "@sfu"
		}
		c.mu.Lock()
		curRev := revision
		if cur := c.rooms[roomID]; cur == r {
			curRev = cur.revision
		}
		c.mu.Unlock()
		c.send(message{Type: "signal", Room: roomID, Revision: curRev, From: from, To: memberID, Candidate: &value})
	})
	pc.OnConnectionStateChange(func(s webrtc.PeerConnectionState) {
		if s == webrtc.PeerConnectionStateFailed {
			c.mu.Lock()
			curRev := revision
			if cur := c.rooms[roomID]; cur == r {
				curRev = cur.revision
				if r.peers[peerKey] == p {
					delete(r.peers, peerKey)
				}
				if up && pub.upstream == p {
					pub.upstream = nil
				}
			}
			c.mu.Unlock()
			c.send(message{Type: "media-error", Room: roomID, Revision: curRev, To: memberID, Error: "Media connection failed"})
			_ = pc.Close()
		}
	})
	if up {
		if _, e = pc.AddTransceiverFromKind(webrtc.RTPCodecTypeAudio, webrtc.RTPTransceiverInit{Direction: webrtc.RTPTransceiverDirectionRecvonly}); e != nil {
			_ = pc.Close()
			return nil, e
		}
		if pub.withVideo {
			if _, e = pc.AddTransceiverFromKind(webrtc.RTPCodecTypeVideo, webrtc.RTPTransceiverInit{Direction: webrtc.RTPTransceiverDirectionRecvonly}); e != nil {
				_ = pc.Close()
				return nil, e
			}
		}
		pub.upstream = p
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
	type pendingSub struct {
		member string
		pub    string
		id     string
	}
	var toClose []*webrtc.PeerConnection
	var errMsgs []message
	var toCreate []pendingSub
	c.mu.Lock()
	r := c.rooms[m.Room]
	if r != nil && m.Revision < r.revision {
		c.mu.Unlock()
		return errors.New("stale room")
	}
	if r != nil && m.Revision != r.revision && samePublishers(r.publishers, m.Publishers) {
		// Subscription-only revision bump (e.g. viewer block/unblock): preserve active uplinks & unchanged viewer downlinks.
		r.revision = m.Revision
	} else if r == nil || m.Revision != r.revision {
		toClose = append(toClose, c.dropLocked(m.Room)...)
		r = &room{revision: m.Revision, publishers: map[string]*publisher{}, members: map[string]memberSpec{}, peers: map[string]*peer{}, ice: m.ICE}
		c.rooms[m.Room] = r
		for _, s := range m.Publishers {
			p, e := newPublisher(s.Mode)
			if e != nil {
				delete(c.rooms, m.Room)
				c.mu.Unlock()
				for _, pc := range toClose {
					_ = pc.Close()
				}
				return e
			}
			r.publishers[s.ID] = p
		}
	}
	if len(m.ICE) > 0 {
		r.ice = m.ICE
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
			if p.upstream {
				if pub := r.publishers[p.publisher]; pub != nil && pub.upstream == p {
					pub.upstream = nil
				}
			}
			toClose = append(toClose, p.pc)
			delete(r.peers, id)
		}
	}
	seen := map[string]bool{}
	rev := r.revision
	for member, spec := range next {
		for _, pub := range spec.Subscriptions {
			if _, ok := r.publishers[pub]; !ok {
				errMsgs = append(errMsgs, message{Type: "media-error", Room: m.Room, Revision: rev, To: member, Error: "Unknown publisher"})
				continue
			}
			id := key(member, pub)
			if r.peers[id] != nil || seen[id] {
				continue
			}
			seen[id] = true
			toCreate = append(toCreate, pendingSub{member: member, pub: pub, id: id})
		}
	}
	c.mu.Unlock()
	for _, pc := range toClose {
		_ = pc.Close()
	}
	for _, msg := range errMsgs {
		c.send(msg)
	}
	for _, sub := range toCreate {
		c.mu.Lock()
		if c.rooms[m.Room] != r || r.peers[sub.id] != nil {
			c.mu.Unlock()
			continue
		}
		p, e := c.newPeer(m.Room, sub.member, sub.pub, r, false)
		if e != nil {
			c.mu.Unlock()
			c.send(message{Type: "media-error", Room: m.Room, Revision: rev, To: sub.member, Error: "Media setup failed"})
			continue
		}
		r.peers[sub.id] = p
		c.mu.Unlock()
		offer, e := p.pc.CreateOffer(nil)
		if e == nil {
			e = p.pc.SetLocalDescription(offer)
		}
		if e != nil {
			c.mu.Lock()
			if c.rooms[m.Room] == r && r.peers[sub.id] == p {
				delete(r.peers, sub.id)
			}
			c.mu.Unlock()
			_ = p.pc.Close()
			c.send(message{Type: "media-error", Room: m.Room, Revision: rev, To: sub.member, Error: "Media setup failed"})
			continue
		}
		c.send(message{Type: "signal", Room: m.Room, Revision: rev, From: sub.pub, To: sub.member, Description: &offer})
	}
	return nil
}
func (c *control) signalPeer(m message) error {
	c.mu.Lock()
	r := c.rooms[m.Room]
	if r == nil || m.Revision != r.revision {
		c.mu.Unlock()
		return errors.New("stale room")
	}
	member, ok := r.members[m.From]
	if !ok {
		c.mu.Unlock()
		return errors.New("unknown member")
	}
	up := m.To == "@sfu"
	id := key(m.From, m.To)
	p := r.peers[id]
	if up && !member.Publisher {
		c.mu.Unlock()
		return errors.New("viewer cannot publish")
	}
	if !up && !contains(member.Subscriptions, m.To) {
		c.mu.Unlock()
		return errors.New("subscription denied")
	}
	created := false
	if p == nil {
		if !up {
			c.mu.Unlock()
			return errors.New("peer not ready")
		}
		var e error
		p, e = c.newPeer(m.Room, m.From, m.From, r, true)
		if e != nil {
			c.mu.Unlock()
			return e
		}
		r.peers[id] = p
		created = true
	}
	rev := r.revision
	p.mu.Lock()
	failPeer := func(err error) error {
		if created {
			if r.peers[id] == p {
				delete(r.peers, id)
			}
			if pub := r.publishers[p.publisher]; pub != nil && pub.upstream == p {
				pub.upstream = nil
			}
		}
		p.mu.Unlock()
		c.mu.Unlock()
		if created {
			_ = p.pc.Close()
		}
		return err
	}
	if m.Candidate != nil {
		if !p.remote {
			if len(p.pending) >= 100 {
				return failPeer(errors.New("too many candidates"))
			}
			p.pending = append(p.pending, *m.Candidate)
			p.mu.Unlock()
			c.mu.Unlock()
			return nil
		}
		e := p.pc.AddICECandidate(*m.Candidate)
		if e != nil {
			return failPeer(e)
		}
		p.mu.Unlock()
		c.mu.Unlock()
		return nil
	}
	if m.Description == nil {
		return failPeer(errors.New("missing signal"))
	}
	if up && m.Description.Type != webrtc.SDPTypeOffer || !up && m.Description.Type != webrtc.SDPTypeAnswer {
		return failPeer(errors.New("invalid description"))
	}
	if e := p.pc.SetRemoteDescription(*m.Description); e != nil {
		return failPeer(e)
	}
	p.remote = true
	for _, ice := range p.pending {
		_ = p.pc.AddICECandidate(ice)
	}
	p.pending = nil
	var reply *message
	if up {
		answer, e := p.pc.CreateAnswer(nil)
		if e != nil {
			return failPeer(e)
		}
		if e = p.pc.SetLocalDescription(answer); e != nil {
			return failPeer(e)
		}
		reply = &message{Type: "signal", Room: m.Room, Revision: rev, From: "@sfu", To: m.From, Description: &answer}
	}
	p.mu.Unlock()
	c.mu.Unlock()
	if reply != nil {
		c.send(*reply)
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
			var toClose []*webrtc.PeerConnection
			c.mu.Lock()
			for id := range c.rooms {
				toClose = append(toClose, c.dropLocked(id)...)
			}
			c.mu.Unlock()
			for _, pc := range toClose {
				_ = pc.Close()
			}
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
				toClose := c.dropLocked(m.Room)
				c.mu.Unlock()
				for _, pc := range toClose {
					_ = pc.Close()
				}
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
