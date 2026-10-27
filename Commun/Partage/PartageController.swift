import UIKit
import WebKit
import UniformTypeIdentifiers

/// L'extension de partage : la fenêtre qui s'ouvre quand on choisit l'app dans la feuille
/// « Partager » (de Google Maps, de Safari…). Elle n'écrit RIEN elle-même : elle ouvre la page du
/// site qui range ce qu'on partage — la même que celle de l'app, donc une seule règle d'écriture.
/// L'adresse est la clé `JuclairianPartage` de son Info.plist, où `{url}` reçoit le lien partagé.
///
/// La session est celle de cette fenêtre : on s'y connecte une fois, au premier partage, et la page
/// de connexion la reprend seule ensuite (le cookie expire, le jeton de renouvellement reste).
///
/// ⚠️ LE CANAL `juclairianPartage` est le contrat avec le site. Sa seule présence dit à la page
/// qu'elle est dans la feuille de partage (le site y retire son menu) ; quand tout est écrit, elle y
/// envoie `{ fini: true, texte }` (`partageFini`, nav.html du site) : la fenêtre montre ce texte, puis
/// se ferme. Sur une erreur, la page n'envoie rien et la fenêtre reste ouverte.
final class PartageController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var vue: WKWebView!
    private static let canal = "juclairianPartage"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Site.fond

        let barre = UINavigationBar()
        barre.translatesAutoresizingMaskIntoConstraints = false
        let titre = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
        let element = UINavigationItem(title: titre)
        element.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self,
                                                     action: #selector(fermer))
        barre.setItems([element], animated: false)

        vue = Site.vue(delegue: self)
        vue.translatesAutoresizingMaskIntoConstraints = false
        vue.configuration.userContentController.add(Canal(self), name: Self.canal)

        view.addSubview(barre)
        view.addSubview(vue)
        NSLayoutConstraint.activate([
            barre.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            barre.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            barre.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            vue.topAnchor.constraint(equalTo: barre.bottomAnchor),
            vue.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            vue.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            vue.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        lirePartage { [weak self] lien in
            DispatchQueue.main.async { self?.ouvrir(lien) }
        }
    }

    @objc private func fermer() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    /// La page a tout écrit : on montre ce qu'elle dit, le temps de le lire, puis on rend la main.
    fileprivate func recu(_ corps: Any) {
        guard let d = corps as? [String: Any], d["fini"] as? Bool == true else { return }
        let fin = UIView()
        fin.translatesAutoresizingMaskIntoConstraints = false
        fin.backgroundColor = Site.fond
        let coche = UILabel()
        coche.text = "✓"
        coche.font = .systemFont(ofSize: 52, weight: .semibold)
        coche.textColor = UIColor(red: 47 / 255, green: 98 / 255, blue: 116 / 255, alpha: 1)
        let texte = UILabel()
        texte.text = (d["texte"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "C'est rangé."
        texte.font = .systemFont(ofSize: 17)
        texte.textColor = UIColor(red: 42 / 255, green: 38 / 255, blue: 34 / 255, alpha: 1)
        texte.numberOfLines = 0
        texte.textAlignment = .center
        let pile = UIStackView(arrangedSubviews: [coche, texte])
        pile.axis = .vertical
        pile.alignment = .center
        pile.spacing = 12
        pile.translatesAutoresizingMaskIntoConstraints = false
        fin.addSubview(pile)
        view.addSubview(fin)
        NSLayoutConstraint.activate([
            fin.topAnchor.constraint(equalTo: vue.topAnchor),
            fin.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fin.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fin.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pile.centerYAnchor.constraint(equalTo: fin.centerYAnchor, constant: -40),
            pile.leadingAnchor.constraint(equalTo: fin.leadingAnchor, constant: 28),
            pile.trailingAnchor.constraint(equalTo: fin.trailingAnchor, constant: -28),
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in self?.fermer() }
    }

    private func ouvrir(_ lien: URL?) {
        guard let lien else {
            vue.loadHTMLString(Self.message("Rien à partager : aucun lien n'a été reçu."), baseURL: nil)
            return
        }
        // Le lien voyage tout entier dans un seul paramètre : on encode aussi & = ? + #.
        var permis = CharacterSet.urlQueryAllowed
        permis.remove(charactersIn: "&=?+#")
        let encode = lien.absoluteString.addingPercentEncoding(withAllowedCharacters: permis) ?? ""
        let adresse = Site.reglage("JuclairianPartage").replacingOccurrences(of: "{url}", with: encode)
        guard let url = URL(string: adresse) else {
            vue.loadHTMLString(Self.message("Adresse de partage invalide."), baseURL: nil)
            return
        }
        vue.load(URLRequest(url: url))
    }

    /// Le lien partagé : une URL si l'app d'origine en donne une, sinon la première adresse trouvée
    /// dans le texte partagé (Google Maps envoie souvent « Nom du lieu\nhttps://maps.app.goo.gl/… »).
    private func lirePartage(_ rendre: @escaping (URL?) -> Void) {
        let pieces = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        let typeURL = UTType.url.identifier, typeTexte = UTType.plainText.identifier
        if let piece = pieces.first(where: { $0.hasItemConformingToTypeIdentifier(typeURL) }) {
            piece.loadItem(forTypeIdentifier: typeURL, options: nil) { objet, _ in
                if let url = objet as? URL, url.scheme?.hasPrefix("http") == true { return rendre(url) }
                if let data = objet as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    return rendre(url)
                }
                rendre(nil)
            }
            return
        }
        if let piece = pieces.first(where: { $0.hasItemConformingToTypeIdentifier(typeTexte) }) {
            piece.loadItem(forTypeIdentifier: typeTexte, options: nil) { objet, _ in
                rendre((objet as? String).flatMap(Self.premiereAdresse))
            }
            return
        }
        rendre(nil)
    }

    private static func premiereAdresse(_ texte: String) -> URL? {
        guard let detecteur = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let plage = NSRange(texte.startIndex..., in: texte)
        return detecteur.matches(in: texte, options: [], range: plage)
            .compactMap { $0.url }
            .first { $0.scheme?.hasPrefix("http") == true }
    }

    private static func message(_ texte: String) -> String {
        "<meta name=viewport content='width=device-width'><body style='font:17px -apple-system;"
            + "padding:24px;background:#faf7f2;color:#2a2622'>\(texte)</body>"
    }

    // Une extension ne peut pas ouvrir une autre app : un lien hors du site ne mène nulle part ici.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.allow) }
        let duSite = (url.scheme == "https" || url.scheme == "http")
            && url.host == URL(string: Site.reglage("JuclairianPartage"))?.host
        if duSite || url.scheme == "about" || action.targetFrame?.isMainFrame == false {
            return decisionHandler(.allow)
        }
        decisionHandler(.cancel)
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

/// Le relais du canal : la vue web garde son destinataire en mémoire ; en passant par un relais qui
/// ne le retient pas, la fenêtre et sa vue ne se retiennent pas l'une l'autre.
private final class Canal: NSObject, WKScriptMessageHandler {
    private weak var cible: PartageController?
    init(_ cible: PartageController) { self.cible = cible }
    func userContentController(_ controleur: WKUserContentController, didReceive message: WKScriptMessage) {
        cible?.recu(message.body)
    }
}
