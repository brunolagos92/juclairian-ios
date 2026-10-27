import UIKit
import WebKit

/// Ce qui vaut pour toute page du site, dans l'app comme dans le partage.
enum Site {
    /// Le fond des pages (#faf7f2) : ce qui se voit autour de la page et pendant son chargement.
    static let fond = UIColor(red: 250 / 255, green: 247 / 255, blue: 242 / 255, alpha: 1)

    /// Une adresse lue dans l'Info.plist de la cible.
    static func reglage(_ cle: String) -> String {
        guard let texte = Bundle.main.object(forInfoDictionaryKey: cle) as? String, !texte.isEmpty else {
            fatalError("Info.plist : la clé \(cle) manque")
        }
        return texte
    }

    /// Une vue web qui garde ses cookies et sa mémoire d'une ouverture à l'autre : la session du
    /// site (le cookie `sb-jeton` et le jeton de renouvellement) y survit, et la page de connexion
    /// la reprend seule quand le cookie a expiré.
    static func vue(delegue: WKNavigationDelegate & WKUIDelegate) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        let vue = WKWebView(frame: .zero, configuration: configuration)
        vue.navigationDelegate = delegue
        vue.uiDelegate = delegue
        vue.isOpaque = false
        vue.backgroundColor = fond
        vue.scrollView.backgroundColor = fond
        return vue
    }
}

/// ⚠️ Une vue web n'affiche AUCUNE boîte `alert`, `confirm` ou `prompt` d'elle-même : sans ceci,
/// « Supprimer ? » ne s'afficherait pas et la page croirait qu'on a répondu non.
extension UIViewController {
    func dialogueAlerte(_ message: String, termine: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in termine() })
        present(a, animated: true)
    }

    func dialogueConfirmation(_ message: String, termine: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Annuler", style: .cancel) { _ in termine(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in termine(true) })
        present(a, animated: true)
    }

    func dialogueSaisie(_ message: String, defaut: String?, termine: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addTextField { $0.text = defaut }
        a.addAction(UIAlertAction(title: "Annuler", style: .cancel) { _ in termine(nil) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in termine(a.textFields?.first?.text) })
        present(a, animated: true)
    }
}
