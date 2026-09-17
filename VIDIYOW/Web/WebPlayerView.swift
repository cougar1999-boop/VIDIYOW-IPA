import SwiftUI
import WebKit

struct WebPlayerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WebPlayerViewController {
        WebPlayerViewController()
    }

    func updateUIViewController(_ uiViewController: WebPlayerViewController, context: Context) {}
}

final class WebPlayerViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!
    private let deviceID = DeviceIdentity.shared.id

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureWebView()
        loadPlayer()
    }

    private func configureWebView() {
        let controller = WKUserContentController()
        controller.add(self, name: "vidiyowNative")

        let bridge = """
        (function(){
          if (window.__vidiyowBridgeInstalled) return;
          window.__vidiyowBridgeInstalled = true;
          var deviceId = \(jsQuote(deviceID));
          function enrichMeta(meta, action){
            var m={};
            try { m=JSON.parse(String(meta||'{}'))||{}; } catch(e) { m={}; }
            try {
              var activeId=localStorage.getItem('nova_active_source')||'';
              var sources=JSON.parse(localStorage.getItem('nova_sources')||'[]');
              if(Array.isArray(sources)){
                var source=sources.find(function(x){return String(x&&x.id||'')===String(activeId);});
                if(!source && sources.length===1) source=sources[0];
                if(source){
                  if(!m.portal) m.portal=String(source.portal||source.server||'');
                  if(!m.server) m.server=String(source.server||source.portal||'');
                  if(!m.mac) m.mac=String(source.mac||'');
                  if(!m.model) m.model=String(source.model||'MAG254');
                  if(!m.session_id) m.session_id=String(source.session_id||'');
                  if(!m.source_type) m.source_type=String(source.type||source.kind||'');
                }
              }
            } catch(e) {}
            if(!m.user_agent) m.user_agent='Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG250';
            if(action==='stalker') m.media_type='live';
            return JSON.stringify(m);
          }
          window.VidiyowNativePlayer = {
            getDeviceId: function(){ return deviceId; },
            playVod: function(url, meta){
              try { window.webkit.messageHandlers.vidiyowNative.postMessage({action:'vod',url:String(url||''),meta:enrichMeta(meta,'vod')}); } catch(e) {}
              return Promise.resolve();
            },
            playStalker: function(url, meta){
              try { window.webkit.messageHandlers.vidiyowNative.postMessage({action:'stalker',url:String(url||''),meta:enrichMeta(meta,'stalker')}); } catch(e) {}
              return Promise.resolve();
            }
          };
          // Compatibility for the existing webplayer. Internally it may still call this name.
          window.NovaNativePlayer = window.VidiyowNativePlayer;
          try {
            if (!localStorage.getItem('nova_device_id')) localStorage.setItem('nova_device_id', deviceId);
          } catch(e) {}
        })();
        """
        controller.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let wrapper = """
        (function(){
          function install(){
            try {
              if (typeof window.start !== 'function') return false;
              if (window.start.__vidiyowWrapped) return true;
              var original = window.start;
              function wrapped(url, source, item){
                try {
                  var type = String((item && (item.mediaType || item.type)) || '').toLowerCase();
                  if ((type === 'movie' || type === 'episode') && window.VidiyowNativePlayer) {
                    var meta = {
                      title: String((item && (item.name || item.title)) || 'Video'),
                      media_type: type,
                      year: String((item && item.year) || ''),
                      portal: String((source && (source.portal || source.server)) || ''),
                      server: String((source && source.server) || ''),
                      user_agent: \(jsQuote(VIDIYOWConstants.defaultUserAgent))
                    };
                    window.VidiyowNativePlayer.playVod(String(url || ''), JSON.stringify(meta));
                    return Promise.resolve();
                  }
                  if (type === 'live' && window.VidiyowNativePlayer) {
                    var sourceType = String((source && (source.type || source.kind)) || '').toLowerCase();
                    if (sourceType === 'stalker' || sourceType === 'mag') {
                      var liveMeta = { title: String((item && (item.name || item.title)) || 'Live TV'), media_type: 'live', channel_id: String((item && item.id) || ''), portal: String((source && (source.portal || source.server)) || ''), server: String((source && source.server) || '') };
                      window.VidiyowNativePlayer.playStalker(String(url || ''), JSON.stringify(liveMeta));
                      return Promise.resolve();
                    }
                  }
                } catch(e) { console.error('VIDIYOW native VOD bridge', e); }
                return original.apply(this, arguments);
              }
              wrapped.__vidiyowWrapped = true;
              window.start = wrapped;
              return true;
            } catch(e) { return false; }
          }
          var n=0;
          function boot(){ if(install()) return; if(n++ < 120) setTimeout(boot,250); }
          boot();
        })();
        """
        controller.addUserScript(WKUserScript(source: wrapper, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.backgroundColor = .black
        webView.isOpaque = true
        webView.scrollView.backgroundColor = .black
        webView.allowsBackForwardNavigationGestures = false
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadPlayer() {
        webView.load(URLRequest(url: VIDIYOWConstants.webPlayerURL, cachePolicy: .useProtocolCachePolicy))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "vidiyowNative", let body = message.body as? [String: Any], let action = body["action"] as? String, let url = body["url"] as? String, !url.isEmpty else { return }
        let metaString = body["meta"] as? String ?? "{}"
        var meta: [String: Any] = [:]
        if let data = metaString.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { meta = object }

        let title = meta["title"] as? String ?? (action == "stalker" ? "Live TV" : "Video")
        let mediaType = meta["media_type"] as? String ?? "live"
        let year = meta["year"] as? String ?? ""
        let portal = meta["portal"] as? String ?? meta["server"] as? String ?? ""
        let server = meta["server"] as? String ?? portal
        let userAgent = meta["user_agent"] as? String ?? VIDIYOWConstants.defaultUserAgent
        let sourceType = meta["source_type"] as? String ?? (action == "stalker" ? "stalker" : "")
        let sessionId = meta["session_id"] as? String ?? ""
        let mac = meta["mac"] as? String ?? ""
        let model = meta["model"] as? String ?? "MAG254"

        let player = NativePlayerViewController(
            url: url,
            title: title,
            mediaType: action == "stalker" ? "live" : mediaType,
            year: year,
            portal: portal,
            referer: server.isEmpty ? portal : server,
            userAgent: userAgent,
            sourceType: sourceType,
            sessionId: sessionId,
            mac: mac,
            model: model
        )
        player.modalPresentationStyle = .fullScreen
        present(player, animated: true)
    }

    private func jsQuote(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value], options: [])
        let array = String(data: data, encoding: .utf8)!
        return String(array.dropFirst().dropLast())
    }

    override var prefersStatusBarHidden: Bool { true }
}

final class DeviceIdentity {
    static let shared = DeviceIdentity()
    let id: String
    private init() {
        if let existing = UserDefaults.standard.string(forKey: VIDIYOWConstants.deviceIDKey), !existing.isEmpty {
            id = existing
        } else {
            let value = "vidiyow-" + UUID().uuidString.lowercased()
            UserDefaults.standard.set(value, forKey: VIDIYOWConstants.deviceIDKey)
            id = value
        }
    }
}
