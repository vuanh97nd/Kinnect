import AudioToolbox
import UIKit
import WebKit

final class NativeBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "kinnect"

    weak var viewController: UIViewController?
    weak var webView: WKWebView?

    static var bootstrapUserScript: WKUserScript {
        let js = """
        (function() {
            window.KinnectIOSNative = true;
            window.KinnectAppVersion = "\(ServerConfig.appVersion)";
            try {
                Object.defineProperty(navigator, 'standalone', { get: function() { return true; } });
            } catch (e) {}

            function postNative(payload) {
                try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.kinnect) {
                        window.webkit.messageHandlers.kinnect.postMessage(payload);
                    }
                } catch (e) {}
            }

            window.KinnectNative = {
                post: postNative,
                haptic: function(style) { postNative({ type: 'haptic', style: style || 'medium' }); },
                share: function(title, text, url) { postNative({ type: 'share', title: title || '', text: text || '', url: url || location.href }); }
            };

            if (!navigator.vibrate) {
                navigator.vibrate = function(pattern) {
                    if (!pattern || pattern === 0 || (Array.isArray(pattern) && pattern.length === 0)) {
                        return true;
                    }
                    postNative({ type: 'vibrate', pattern: pattern });
                    return true;
                };
            }

            var OrigWebSocket = window.WebSocket;
            if (OrigWebSocket && !OrigWebSocket.__kinnectWrapped) {
                function KinnectWS(url, protocols) {
                    var ws = protocols ? new OrigWebSocket(url, protocols) : new OrigWebSocket(url);
                    ws.addEventListener('message', function(ev) {
                        if (typeof ev.data === 'string' && ev.data.indexOf('"call-') !== -1) {
                            try {
                                var msg = JSON.parse(ev.data);
                                if (msg && (msg.type === 'call-incoming' || msg.type === 'call-ended' || msg.type === 'call-accepted')) {
                                    postNative({
                                        type: msg.type,
                                        callId: msg.callId || '',
                                        mode: msg.mode || 'video',
                                        callerName: (msg.from && msg.from.name) ? msg.from.name : 'Kinnect'
                                    });
                                }
                            } catch (e) {}
                        }
                    });
                    return ws;
                }
                KinnectWS.prototype = OrigWebSocket.prototype;
                KinnectWS.CONNECTING = OrigWebSocket.CONNECTING;
                KinnectWS.OPEN = OrigWebSocket.OPEN;
                KinnectWS.CLOSING = OrigWebSocket.CLOSING;
                KinnectWS.CLOSED = OrigWebSocket.CLOSED;
                KinnectWS.__kinnectWrapped = true;
                window.WebSocket = KinnectWS;
            }

            document.addEventListener('DOMContentLoaded', function() {
                document.documentElement.setAttribute('data-native-ios', 'true');
                postNative({ type: 'dom-ready' });
            });
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "dom-ready":
            if let store = webView?.configuration.websiteDataStore.httpCookieStore {
                NativeSocketClient.shared.syncCookiesAndConnect(from: store)
            }
        case "vibrate":
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        case "haptic":
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        case "call-incoming":
            let callId = body["callId"] as? String ?? ""
            let callerName = body["callerName"] as? String ?? "Kinnect"
            let mode = body["mode"] as? String ?? "video"
            MediaPermissionHandler.shared.configureAudioSessionForCall()
            if UIApplication.shared.applicationState != .active {
                CallKitManager.shared.reportIncomingCall(callId: callId, callerName: callerName, isVideo: mode != "audio")
            }
        case "call-accepted":
            let callId = body["callId"] as? String ?? ""
            MediaPermissionHandler.shared.configureAudioSessionForCall()
            CallKitManager.shared.reportCallConnected(callId: callId)
        case "call-ended":
            let callId = body["callId"] as? String ?? ""
            CallKitManager.shared.reportCallEnded(callId: callId, reason: .remoteEnded)
            MediaPermissionHandler.shared.configureAudioSessionForMedia()
        case "share":
            let text = body["text"] as? String ?? ""
            let urlStr = body["url"] as? String ?? ServerConfig.currentOrigin
            var items: [Any] = []
            if !text.isEmpty { items.append(text) }
            if let url = URL(string: urlStr) { items.append(url) }
            guard !items.isEmpty, let vc = viewController else { return }
            let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = vc.view
                popover.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.midY, width: 1, height: 1)
            }
            vc.present(activityVC, animated: true)
        default:
            break
        }
    }
}
