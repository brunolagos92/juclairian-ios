import SwiftUI
import UIKit
import WebKit

/// L'app : une coquille qui ouvre le site. Les écrans, la logique et les données viennent du site —
/// un push sur le site est dans l'app aussitôt, sans nouvelle version. L'adresse de départ est la
/// clé `JuclairianDepart` de l'Info.plist de chaque app.
@main
struct CoquilleApp: App {
    /// Les notifications de l'app qui les demande (`Notifications.swift`) ; pour les autres, il ne fait rien.
    @UIApplicationDelegateAdaptor(Notifications.self) private var notifications
    /// La page demandée de l'extérieur — un widget touché (`Apps/<App>Widgets`) : l'app s'ouvre dessus.
    @State private var demande: Demande?
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(uiColor: Site.fond).ignoresSafeArea()
                Coquille(demande: demande)
            }
            .onOpenURL { demande = Demande(url: $0) }
        }
    }
}

/// Une adresse reçue par l'app. Chaque demande est neuve (son `id`) : toucher deux fois le même widget ramène
/// deux fois à sa page, même si l'on a navigué entre-temps.
struct Demande: Equatable {
    let url: URL
    let id = UUID()
}

struct Coquille: UIViewControllerRepresentable {
    let demande: Demande?
    func makeUIViewController(context: Context) -> CoquilleController {
        CoquilleController(depart: URL(string: Site.reglage("JuclairianDepart"))!)
    }
    func updateUIViewController(_ controleur: CoquilleController, context: Context) {
        if let demande = demande { controleur.ouvrir(demande) }
    }
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
        NotificationCenter.default.addObserver(self, selector: #selector(donnerJeton),
                                               name: Notifications.recu, object: nil)
        donnerJeton()
        vue.load(URLRequest(url: enAttente ?? depart))
    }

    /// ⚠️ UNE ADRESSE REÇUE (un widget) : `<schéma de l'app>://<domaine du site>/<chemin>` — le schéma que
    /// déclare l'Info.plist (`CFBundleURLTypes`) — est la page du site au même chemin. Une adresse d'un autre
    /// domaine ne s'ouvre pas. L'app lancée par le widget n'a pas encore sa vue : la page attend `viewDidLoad`.
    private var servie: UUID?
    private var enAttente: URL?
    func ouvrir(_ demande: Demande) {
        guard demande.id != servie else { return }
        servie = demande.id
        var morceaux = URLComponents(url: demande.url, resolvingAgainstBaseURL: false)
        morceaux?.scheme = depart.scheme
        guard let page = morceaux?.url, estDuSite(page) else { return }
        if isViewLoaded { vue.load(URLRequest(url: page)) } else { enAttente = page }
    }

    /// ⚠️ LE JETON DES NOTIFICATIONS, REMIS À LA PAGE (`Notifications.swift`) : `window.juclairianNotifications`
    /// = `{ jeton, sujet, environnement }` et l'évènement `juclairian:notifications`. Posé au début de CHAQUE page
    /// (elle le lit en s'ouvrant), et tout de suite dans celle qui est là quand il arrive (elle écoute
    /// l'évènement). `sujet` est l'identifiant de l'app, que l'envoi à Apple nomme ; `environnement` vaut
    /// « production » : TestFlight passe par le serveur de production d'Apple.
    private var jetonDonne: String?
    @objc private func donnerJeton() {
        guard let jeton = Notifications.jeton, jeton != jetonDonne else { return }
        jetonDonne = jeton
        let valeur = ["jeton": jeton, "sujet": Bundle.main.bundleIdentifier ?? "", "environnement": "production"]
        guard let json = try? JSONSerialization.data(withJSONObject: valeur),
              let objet = String(data: json, encoding: .utf8) else { return }
        let js = "window.juclairianNotifications = \(objet); dispatchEvent(new Event('juclairian:notifications'));"
        vue.configuration.userContentController.addUserScript(
            WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        vue.evaluateJavaScript(js, completionHandler: nil)
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
