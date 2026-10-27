import UIKit
import WebKit
import UniformTypeIdentifiers

/// L'extension de partage : la fenêtre qui s'ouvre quand on choisit l'app dans la feuille
/// « Partager » (de Google Maps, de Safari…). Elle n'écrit RIEN elle-même : elle ouvre la page du
/// site qui range ce qu'on partage — la même que celle de l'app, donc une seule règle d'écriture.
/// L'adresse est la clé `JuclairianPartage` de son Info.plist, où `{url}` reçoit le lien partagé et
/// `{texte}` le texte qui l'accompagne (sans ses adresses) — il porte souvent le titre de ce qu'on partage.
///
/// La session est celle de cette fenêtre : on s'y connecte une fois, au premier partage, et la page
/// de connexion la reprend seule ensuite (le cookie expire, le jeton de renouvellement reste).
///
/// ⚠️ LE CANAL `juclairianPartage` est le contrat avec le site. Sa seule présence dit à la page
/// qu'elle est dans la feuille de partage (le site y retire son menu) ; quand tout est écrit, elle y
/// envoie `{ fini: true, texte }` (`partageFini`, nav.html du site) : la fenêtre montre ce texte, puis
/// se ferme. Sur une erreur, la page n'envoie rien et la fenêtre reste ouverte.
/// La page peut aussi y DEMANDER le titre de la page partagée (`{ titre: true }`) : la fenêtre la lit
/// depuis le téléphone et le rend dans `window.juclairianTitrePartage` (évènement `juclairian:titre`).
final class PartageController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var vue: WKWebView!
    private var lienPartage: URL?
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

        // Jamais un écran blanc : on dit qu'on lit, le temps que l'app d'origine remette ce qu'elle partage.
        vue.loadHTMLString(Self.message("Lecture du partage…"), baseURL: nil)
        lirePartage { [weak self] lien, texte in self?.ouvrir(lien, texte: texte) }
    }

    @objc private func fermer() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    /// La page a tout écrit : on montre ce qu'elle dit, le temps de le lire, puis on rend la main.
    fileprivate func recu(_ corps: Any) {
        guard let d = corps as? [String: Any] else { return }
        if d["titre"] as? Bool == true { return lireTitre() }
        guard d["fini"] as? Bool == true else { return }
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

    private func ouvrir(_ lien: URL?, texte: String?) {
        guard let lien else {
            vue.loadHTMLString(Self.message("Rien à partager : aucun lien n'a été reçu."), baseURL: nil)
            return
        }
        lienPartage = lien
        // Le lien voyage tout entier dans un seul paramètre : on encode aussi & = ? + #.
        var permis = CharacterSet.urlQueryAllowed
        permis.remove(charactersIn: "&=?+#")
        let encode = { (x: String) in x.addingPercentEncoding(withAllowedCharacters: permis) ?? "" }
        let adresse = Site.reglage("JuclairianPartage")
            .replacingOccurrences(of: "{url}", with: encode(lien.absoluteString))
            .replacingOccurrences(of: "{texte}", with: encode(texte ?? ""))
        guard let url = URL(string: adresse) else {
            vue.loadHTMLString(Self.message("Adresse de partage invalide."), baseURL: nil)
            return
        }
        vue.load(URLRequest(url: url))
    }

    /// Le lien partagé : une URL si l'app d'origine en donne une, sinon la première adresse trouvée
    /// dans le texte partagé (Google Maps envoie souvent « Nom du lieu\nhttps://maps.app.goo.gl/… »).
    /// Et le TEXTE qui l'accompagne, sans ses adresses — le titre de ce qu'on partage, souvent.
    private func lirePartage(_ rendre: @escaping (URL?, String?) -> Void) {
        let pieces = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        let typeURL = UTType.url.identifier, typeTexte = UTType.plainText.identifier
        let recu = Recu(), groupe = DispatchGroup()
        if let piece = pieces.first(where: { $0.hasItemConformingToTypeIdentifier(typeURL) }) {
            groupe.enter()
            piece.loadItem(forTypeIdentifier: typeURL, options: nil) { objet, _ in
                var u: URL?
                if let x = objet as? URL, x.scheme?.hasPrefix("http") == true { u = x }
                else if let data = objet as? Data, let x = URL(dataRepresentation: data, relativeTo: nil) { u = x }
                recu.poser { $0.url = u }
                groupe.leave()
            }
        }
        if let piece = pieces.first(where: { $0.hasItemConformingToTypeIdentifier(typeTexte) }) {
            groupe.enter()
            piece.loadItem(forTypeIdentifier: typeTexte, options: nil) { objet, _ in
                let t = (objet as? String) ?? (objet as? Data).map { String(decoding: $0, as: UTF8.self) }
                recu.poser { $0.texte = t }
                groupe.leave()
            }
        }
        /* ⚠️⚠️ L'ATTENTE EST BORNÉE (27 octobre 2026 — partage depuis l'app Amazon : « ça n'affiche rien »). La
           fenêtre attendait le lien ET le texte avant de rien ouvrir : une app d'origine qui ne remet jamais
           l'un des deux la laissait blanche pour toujours. Au bout de trois secondes, on part avec ce qu'on a ;
           et l'on ne part qu'UNE fois. */
        let partir = {
            guard let pris = recu.prendre() else { return }
            let (url, texte) = pris
            let reste = texte.map(Self.sansAdresses).flatMap { $0.isEmpty ? nil : $0 }
            rendre(url ?? texte.flatMap(Self.premiereAdresse), reste)
        }
        groupe.notify(queue: .main) { partir() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { partir() }
    }

    /// ⚠️⚠️ LE TITRE DE LA PAGE PARTAGÉE, LU DEPUIS LE TÉLÉPHONE — sur DEMANDE de la page seulement
    /// (`{ titre: true }`, 27 octobre 2026). Un Kindle partagé depuis l'app Amazon n'a ni ISBN ni titre
    /// dans son adresse, et Amazon refuse souvent sa page à un serveur — pas à un iPhone. On lit sa balise
    /// `<title>` et on la rend à la page ; la page suivante la trouve aussi (script posé au chargement).
    private func lireTitre() {
        guard let lien = lienPartage else { return donnerTitre("") }
        var requete = URLRequest(url: lien, timeoutInterval: 7)
        requete.setValue("fr-FR,fr;q=0.9", forHTTPHeaderField: "Accept-Language")
        // Comme Safari sur l'iPhone : Amazon sert sa vraie page à un navigateur, pas toujours à une app.
        requete.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: requete) { [weak self] data, _, _ in
            let titre = data.flatMap(Self.titreHTML) ?? ""
            DispatchQueue.main.async { self?.donnerTitre(titre) }
        }.resume()
    }

    private func donnerTitre(_ titre: String) {
        guard let json = try? JSONSerialization.data(withJSONObject: [titre]),
              let tableau = String(data: json, encoding: .utf8) else { return }
        let js = "window.juclairianTitrePartage = \(tableau)[0];"
            + " window.dispatchEvent(new Event('juclairian:titre'));"
        vue.configuration.userContentController.addUserScript(
            WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        vue.evaluateJavaScript(js, completionHandler: nil)
    }

    private static func titreHTML(_ data: Data) -> String? {
        let html = String(decoding: data.prefix(600_000), as: UTF8.self)
        guard let motif = try? NSRegularExpression(pattern: "<title[^>]*>([\\s\\S]*?)</title>",
                                                   options: .caseInsensitive),
              let trouve = motif.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let plage = Range(trouve.range(at: 1), in: html) else { return nil }
        return String(html[plage])
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Le texte partagé, sans ses adresses : ce qui reste est d'ordinaire le titre.
    private static func sansAdresses(_ texte: String) -> String {
        guard let detecteur = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return texte }
        var reste = texte
        let plage = NSRange(texte.startIndex..., in: texte)
        for m in detecteur.matches(in: texte, options: [], range: plage).reversed() {
            if let r = Range(m.range, in: reste) { reste.removeSubrange(r) }
        }
        return String(reste.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
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

/// Ce que la feuille de partage a remis — rempli depuis plusieurs fils, d'où le verrou.
private final class Recu: @unchecked Sendable {
    fileprivate var url: URL?
    fileprivate var texte: String?
    private let verrou = NSLock()
    func poser(_ faire: (Recu) -> Void) { verrou.lock(); faire(self); verrou.unlock() }
    private var pris = false
    /// Ce qu'on a reçu — la PREMIÈRE fois seulement (la fin des chargements ou les trois secondes).
    func prendre() -> (URL?, String?)? {
        verrou.lock(); defer { verrou.unlock() }
        if pris { return nil }
        pris = true
        return (url, texte)
    }
}
