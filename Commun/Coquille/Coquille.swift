import SwiftUI
import UIKit
import WebKit

/// L'app : une coquille qui ouvre le site. Les écrans, la logique et les données viennent du site —
/// un push sur le site est dans l'app aussitôt, sans nouvelle version. L'adresse de départ est la
/// clé `JuclairianDepart` de l'Info.plist de chaque app.
@main
struct CoquilleApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(uiColor: Site.fond).ignoresSafeArea()
                Coquille()
            }
        }
    }
}

struct Coquille: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CoquilleController {
        CoquilleController(depart: URL(string: Site.reglage("JuclairianDepart"))!)
    }
    func updateUIViewController(_ controleur: CoquilleController, context: Context) {}
}

final class CoquilleController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let depart: URL
    private var vue: WKWebView!

    init(depart: URL) {
        self.depart = depart
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas utilisé") }

    override func loadView() {
        vue = Site.vue(delegue: self)
        vue.allowsBackForwardNavigationGestures = true
        let rafraichir = UIRefreshControl()
        rafraichir.addTarget(self, action: #selector(recharger(_:)), for: .valueChanged)
        vue.scrollView.refreshControl = rafraichir
        view = vue
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        vue.load(URLRequest(url: depart))
    }

    @objc private func recharger(_ controle: UIRefreshControl) {
        vue.reload()
        controle.endRefreshing()
    }

    /// Une page du site — même domaine — s'ouvre dans l'app ; tout le reste (Google Maps, TMDb,
    /// un téléphone, un e-mail) s'ouvre dans son app ou dans Safari. Ce qui se charge DANS une page
    /// (un cadre, une carte intégrée) n'est pas une navigation : on le laisse.
    private func estDuSite(_ url: URL) -> Bool {
        (url.scheme == "https" || url.scheme == "http") && url.host == depart.host
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.allow) }
        if estDuSite(url) || url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" {
            return decisionHandler(.allow)
        }
        if let cadre = action.targetFrame, !cadre.isMainFrame {
            return decisionHandler(.allow)
        }
        UIApplication.shared.open(url)
        decisionHandler(.cancel)
    }

    /// `target="_blank"` : une page du site s'ouvre ici, le reste dehors.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            if estDuSite(url) { webView.load(action.request) } else { UIApplication.shared.open(url) }
        }
        return nil
    }

    /// iOS a fermé la page pour libérer de la mémoire : on la rouvre plutôt que de laisser un écran blanc.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        dialogueAlerte(message, termine: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        dialogueConfirmation(message, termine: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        dialogueSaisie(prompt, defaut: defaultText, termine: completionHandler)
    }
}
