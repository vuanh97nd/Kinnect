package app.kinnect.live;

import android.content.Context;
import android.util.Log;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;
import org.webrtc.DataChannel;
import org.webrtc.IceCandidate;
import org.webrtc.MediaConstraints;
import org.webrtc.MediaStream;
import org.webrtc.PeerConnection;
import org.webrtc.PeerConnectionFactory;
import org.webrtc.RtpReceiver;
import org.webrtc.SdpObserver;
import org.webrtc.SessionDescription;

/**
 * Debug-only proof that the bundled native WebRTC stack performs real SDP negotiation,
 * ICE and DTLS/SCTP DataChannel delivery between two local PeerConnections.
 * It does not exercise camera/microphone capture or remote TURN relays.
 */
final class QaWebRtcSelfTest {
  private static final String TAG = "KinnectQA";
  private static void log(String line) { Log.i(TAG, "QA_WEBRTC: " + line); }

  static void run(Context context) {
    final Context app = context.getApplicationContext();
    Thread thread = new Thread(() -> new QaWebRtcSelfTest().execute(app), "qa-webrtc-selftest");
    thread.setDaemon(true);
    thread.start();
  }

  private final Object lock = new Object();
  private final List<IceCandidate> queuedForA = new ArrayList<>();
  private final List<IceCandidate> queuedForB = new ArrayList<>();
  private PeerConnection pcA;
  private PeerConnection pcB;
  private SessionDescription remoteForA;
  private SessionDescription remoteForB;
  private int gatheredA;
  private int gatheredB;
  private int offerBytes;
  private int answerBytes;
  private volatile boolean finished;

  private void execute(Context context) {
    PeerConnectionFactory factory = null;
    try {
      log("start");
      PeerConnectionFactory.initialize(PeerConnectionFactory.InitializationOptions.builder(context).createInitializationOptions());
      factory = PeerConnectionFactory.builder().createPeerConnectionFactory();
      final PeerConnectionFactory f = factory;
      PeerConnection.RTCConfiguration config = new PeerConnection.RTCConfiguration(new ArrayList<PeerConnection.IceServer>());
      config.sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN;
      pcA = f.createPeerConnection(config, observer(true));
      pcB = f.createPeerConnection(config, observer(false));
      if (pcA == null || pcB == null) throw new IllegalStateException("PeerConnection creation failed");

      DataChannel.Init init = new DataChannel.Init();
      init.ordered = true;
      DataChannel outbound = pcA.createDataChannel("qa-selftest", init);
      outbound.registerObserver(new DataChannel.Observer() {
        private boolean sent;
        @Override public void onBufferedAmountChange(long previousAmount) {}
        @Override public void onStateChange() {
          log("datachannel-state " + outbound.state());
          if (outbound.state() == DataChannel.State.OPEN && !sent) {
            sent = true;
            byte[] ping = "kinnect-webrtc-ping".getBytes();
            log("datachannel-open sending-ping");
            outbound.send(new DataChannel.Buffer(ByteBuffer.wrap(ping), false));
          }
        }
        @Override public void onMessage(DataChannel.Buffer buffer) {
          byte[] bytes = new byte[buffer.data.remaining()];
          buffer.data.get(bytes);
          String text = new String(bytes);
          synchronized (lock) { finished = true; }
          log("PASS echo='" + text + "' sdpOfferBytes=" + offerBytes + " sdpAnswerBytes=" + answerBytes
              + " candidatesA=" + gatheredA + " candidatesB=" + gatheredB + " datachannel=open");
          if (!"kinnect-webrtc-pong".equals(text)) log("FAIL unexpected echo payload");
        }
      });

      pcA.createOffer(new SdpObserver() {
        @Override public void onCreateSuccess(final SessionDescription offer) {
          offerBytes = offer.description.length();
          pcA.setLocalDescription(new SdpObserver() {
            @Override public void onCreateSuccess(SessionDescription sdp) {}
            @Override public void onSetSuccess() {
              synchronized (lock) { remoteForB = offer; }
              log("offer-set-bytes=" + offerBytes);
              pcB.setRemoteDescription(new SdpObserver() {
                @Override public void onCreateSuccess(SessionDescription sdp) {}
                @Override public void onSetSuccess() { flush(true); }
                @Override public void onCreateFailure(String error) { log("FAIL answer-remote " + error); }
                @Override public void onSetFailure(String error) { log("FAIL answer-remote " + error); }
              }, offer);
              pcB.createAnswer(new SdpObserver() {
                @Override public void onCreateSuccess(final SessionDescription answer) {
                  answerBytes = answer.description.length();
                  pcB.setLocalDescription(new SdpObserver() {
                    @Override public void onCreateSuccess(SessionDescription sdp) {}
                    @Override public void onSetSuccess() {
                      synchronized (lock) { remoteForA = answer; }
                      log("answer-set-bytes=" + answerBytes);
                      pcA.setRemoteDescription(new SdpObserver() {
                        @Override public void onCreateSuccess(SessionDescription sdp) {}
                        @Override public void onSetSuccess() { flush(false); }
                        @Override public void onCreateFailure(String error) { log("FAIL offer-remote " + error); }
                        @Override public void onSetFailure(String error) { log("FAIL offer-remote " + error); }
                      }, answer);
                    }
                    @Override public void onCreateFailure(String error) { log("FAIL answer-local " + error); }
                    @Override public void onSetFailure(String error) { log("FAIL answer-local " + error); }
                  }, answer);
                }
                @Override public void onSetSuccess() {}
                @Override public void onCreateFailure(String error) { log("FAIL create-answer " + error); }
                @Override public void onSetFailure(String error) { log("FAIL create-answer " + error); }
              }, new MediaConstraints());
            }
            @Override public void onCreateFailure(String error) { log("FAIL offer-local " + error); }
            @Override public void onSetFailure(String error) { log("FAIL offer-local " + error); }
          }, offer);
        }
        @Override public void onSetSuccess() {}
        @Override public void onCreateFailure(String error) { log("FAIL create-offer " + error); }
        @Override public void onSetFailure(String error) { log("FAIL create-offer " + error); }
      }, new MediaConstraints());

      long deadline = System.currentTimeMillis() + 25000;
      while (System.currentTimeMillis() < deadline) {
        synchronized (lock) { if (finished) break; }
        Thread.sleep(200);
      }
      if (!finished) {
        log("FAIL timeout after 25000ms candidatesA=" + gatheredA + " candidatesB=" + gatheredB
            + " offerBytes=" + offerBytes + " answerBytes=" + answerBytes);
      }
    } catch (Throwable error) {
      log("FAIL " + error.getClass().getSimpleName() + ": " + String.valueOf(error.getMessage()).replace('\n', ' '));
    } finally {
      try { if (pcA != null) pcA.dispose(); } catch (Throwable ignored) {}
      try { if (pcB != null) pcB.dispose(); } catch (Throwable ignored) {}
      try { if (factory != null) factory.dispose(); } catch (Throwable ignored) {}
    }
  }

  private void flush(boolean forB) {
    List<IceCandidate> copy;
    synchronized (lock) {
      copy = new ArrayList<>(forB ? queuedForB : queuedForA);
      (forB ? queuedForB : queuedForA).clear();
    }
    PeerConnection target = forB ? pcB : pcA;
    for (IceCandidate candidate : copy) {
      try { target.addIceCandidate(candidate); } catch (Throwable error) { log("FAIL add-ice " + error.getMessage()); }
    }
  }

  private PeerConnection.Observer observer(final boolean isA) {
    return new PeerConnection.Observer() {
      @Override public void onSignalingChange(PeerConnection.SignalingState state) {}
      @Override public void onIceConnectionChange(PeerConnection.IceConnectionState state) { log((isA ? "A" : "B") + "-ice " + state); }
      @Override public void onIceConnectionReceivingChange(boolean receiving) {}
      @Override public void onIceGatheringChange(PeerConnection.IceGatheringState state) { log((isA ? "A" : "B") + "-gathering " + state); }
      @Override public void onIceCandidatesRemoved(IceCandidate[] candidates) {}
      @Override public void onAddStream(MediaStream stream) {}
      @Override public void onRemoveStream(MediaStream stream) {}
      @Override public void onDataChannel(DataChannel channel) {
        log("B-datachannel-received label=" + channel.label());
        channel.registerObserver(new DataChannel.Observer() {
          @Override public void onBufferedAmountChange(long previousAmount) {}
          @Override public void onStateChange() { log("B-datachannel-state " + channel.state()); }
          @Override public void onMessage(DataChannel.Buffer buffer) {
            byte[] bytes = new byte[buffer.data.remaining()];
            buffer.data.get(bytes);
            log("B-received '" + new String(bytes) + "'");
            channel.send(new DataChannel.Buffer(ByteBuffer.wrap("kinnect-webrtc-pong".getBytes()), false));
          }
        });
      }
      @Override public void onRenegotiationNeeded() {}
      @Override public void onAddTrack(RtpReceiver receiver, MediaStream[] streams) {}
      @Override public void onIceCandidate(IceCandidate candidate) {
        log((isA ? "A" : "B") + "-candidate tcp=" + candidate.sdp.contains(" tcp ") + " len=" + candidate.sdp.length());
        synchronized (lock) {
          if (isA) gatheredA++; else gatheredB++;
          PeerConnection target = isA ? pcB : pcA;
          SessionDescription remote = isA ? remoteForB : remoteForA;
          if (remote == null) { (isA ? queuedForB : queuedForA).add(candidate); return; }
          try { target.addIceCandidate(candidate); } catch (Throwable error) { log("FAIL add-ice " + error.getMessage()); }
        }
      }
    };
  }
}
