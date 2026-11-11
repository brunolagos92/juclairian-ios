import Foundation
import WebKit

/// LANCER UNE APP SUR LA TÉLÉ (LG webOS), pour l'app qui le demande : `JuclairianTele` à vrai dans son Info.plist
/// (11/11/2026 — « aucun moyen de lancer l'app de la TV depuis l'iPhone ? », Bruno). Une page web n'a pas le droit
/// de parler à un appareil de la maison : la télé n'écoute qu'en `wss://<adresse>:3001`, avec un certificat signé
/// par elle-même, que Safari refuse. Du code natif, lui, le peut. La coquille ne décide RIEN : la page donne
/// l'adresse de la télé et l'identifiant de l'app à lancer, et reçoit en retour ce qui se passe.
///
/// **Le contrat avec la page** :
/// - elle voit le canal `window.webkit.messageHandlers.juclairianTele` (absent : on n'est pas dans l'app) et y
///   envoie `{ action: "lancer", adresse: "192.168.1.20", app: "com.exemple.app" }` ;
/// - elle reçoit l'évènement `juclairian:tele`, dont `detail` vaut `{ etat, message }` — `etat` : « connexion »,
///   « accord » (la télé demande, à l'écran, d'accepter cet iPhone : une seule fois), « lancee », « erreur ».
///
/// **Le protocole de la télé** (lu dans aiowebostv 1.0.2, la bibliothèque de Home Assistant) : on s'inscrit par un
/// message `register` ; la première fois la télé affiche une question, puis rend une clé (`client-key`) qu'on
/// garde pour ne plus rien redemander ; ensuite `ssap://system.launcher/launch` avec l'identifiant de l'app.
/// ⚠️ La télé doit être ALLUMÉE et sur le même réseau : la réveiller demanderait une diffusion sur le réseau,
/// qu'iOS ne permet qu'avec un droit accordé par Apple au cas par cas.
final class Tele: NSObject, WKScriptMessageHandler, URLSessionDelegate {
    static let canal = "juclairianTele"
    static var active: Bool {
        Bundle.main.object(forInfoDictionaryKey: "JuclairianTele") as? Bool ?? false
    }

    private weak var vue: WKWebView?
    private var site: String?
    private var session: URLSession?
    private var tache: URLSessionWebSocketTask?
    private var hote = ""
    private var app = ""
    private var chiffre = true
    private var entendu = false
    private var garde: DispatchWorkItem?

    /// Branche le canal sur la vue. `site` : le domaine dont les pages ont le droit de demander.
    func brancher(_ vue: WKWebView, site: String?) {
        self.vue = vue
        self.site = site
        vue.configuration.userContentController.add(self, name: Tele.canal)
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        // ⚠️ Seule une page du site, dans le cadre principal, peut demander : pas un cadre venu d'ailleurs.
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.host == site,
              let corps = message.body as? [String: Any], corps["action"] as? String == "lancer" else { return }
        let adresse = (corps["adresse"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let app = corps["app"] as? String ?? ""
        guard Tele.estDeLaMaison(adresse) else {
            return dire("erreur", "L'adresse de la télé n'est pas une adresse du réseau de la maison.")
        }
        guard app.range(of: "^[A-Za-z0-9._-]{3,80}$", options: .regularExpression) != nil else {
            return dire("erreur", "L'identifiant de l'app à lancer est illisible.")
        }
        lancer(adresse: adresse, app: app)
    }

    /// Une adresse IPv4 PRIVÉE (10.x, 172.16–31.x, 192.168.x) : l'app ne se connecte à rien d'autre.
    static func estDeLaMaison(_ adresse: String) -> Bool {
        let morceaux = adresse.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard morceaux.count == 4, !morceaux.contains(where: { $0 == nil || $0! < 0 || $0! > 255 }) else { return false }
        let a = morceaux[0]!, b = morceaux[1]!
        return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168)
    }

    private func lancer(adresse: String, app: String) {
        fermer()
        hote = adresse
        self.app = app
        chiffre = true
        dire("connexion", "Connexion à la télé…")
        ouvrir()
    }

    /// `wss://…:3001` d'abord ; si rien ne répond, `ws://…:3000` (les télés d'avant 2020).
    private func ouvrir() {
        guard let url = URL(string: (chiffre ? "wss://" : "ws://") + hote + (chiffre ? ":3001" : ":3000")) else { return }
        entendu = false
        let reglage = URLSessionConfiguration.ephemeral
        reglage.timeoutIntervalForRequest = 8
        // ⚠️ LA QUESTION D'iOS (« … souhaite rechercher des appareils sur votre réseau local ») ne se pose qu'à la
        // première connexion, et tant qu'on n'y a pas répondu iOS dit « pas d'Internet » (-1009) : sans attendre,
        // le premier essai échouait pendant que la question était à l'écran (capture de Bruno, 11/11/2026).
        reglage.waitsForConnectivity = true
        let session = URLSession(configuration: reglage, delegate: self, delegateQueue: .main)
        let tache = session.webSocketTask(with: url)
        self.session = session
        self.tache = tache
        tache.resume()
        envoyer(inscription(), sur: tache)
        ecouter(tache)
        // La question posée sur la télé attend qu'on y réponde à la télécommande : on laisse une minute.
        let garde = DispatchWorkItem { [weak self] in
            guard let self = self, self.tache === tache else { return }
            self.fermer()
            self.dire("erreur", "La télé n'a pas répondu. Si iOS n'a rien demandé : Réglages de l'iPhone → "
                + "Confidentialité et sécurité → Réseau local, et y autoriser cette app.")
        }
        self.garde = garde
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: garde)
    }

    private func fermer() {
        garde?.cancel()
        garde = nil
        tache?.cancel(with: .goingAway, reason: nil)
        tache = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private var cleGardee: String { "juclairianTeleCle-" + hote }

    /// Le message d'inscription, avec la clé déjà reçue de cette télé s'il y en a une.
    private func inscription() -> String {
        guard let cle = UserDefaults.standard.string(forKey: cleGardee),
              let donnees = Tele.inscriptionNue.data(using: .utf8),
              var message = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any],
              var charge = message["payload"] as? [String: Any] else { return Tele.inscriptionNue }
        charge["client-key"] = cle
        message["payload"] = charge
        guard let sortie = try? JSONSerialization.data(withJSONObject: message),
              let texte = String(data: sortie, encoding: .utf8) else { return Tele.inscriptionNue }
        return texte
    }

    private func envoyer(_ texte: String, sur tache: URLSessionWebSocketTask) {
        tache.send(.string(texte)) { [weak self] erreur in
            guard let erreur = erreur else { return }
            DispatchQueue.main.async { self?.rompu(tache, erreur.localizedDescription) }
        }
    }

    private func ecouter(_ tache: URLSessionWebSocketTask) {
        tache.receive { [weak self] resultat in
            DispatchQueue.main.async {
                guard let self = self, self.tache === tache else { return }
                switch resultat {
                case .failure(let erreur):
                    self.rompu(tache, erreur.localizedDescription)
                case .success(let message):
                    self.entendu = true
                    if case .string(let texte) = message { self.lire(texte, de: tache) }
                    if self.tache === tache { self.ecouter(tache) }
                }
            }
        }
    }

    /// La connexion est tombée. Avant tout message : on essaie l'autre porte, une fois ; sinon on le dit.
    private func rompu(_ tache: URLSessionWebSocketTask, _ raison: String) {
        guard self.tache === tache else { return }
        fermer()
        if chiffre && !entendu {
            chiffre = false
            return ouvrir()
        }
        dire("erreur", "La télé ne répond pas (" + raison + "). Est-elle allumée, et sur le même Wi-Fi ? "
            + "Sinon : Réglages de l'iPhone → Confidentialité et sécurité → Réseau local, y autoriser cette app.")
    }

    private func lire(_ texte: String, de tache: URLSessionWebSocketTask) {
        guard let donnees = texte.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any] else { return }
        let type = message["type"] as? String ?? ""
        let id = message["id"] as? String ?? ""
        let charge = message["payload"] as? [String: Any] ?? [:]
        if type == "registered" {
            if let cle = charge["client-key"] as? String { UserDefaults.standard.set(cle, forKey: cleGardee) }
            let demande: [String: Any] = ["id": "lancer_0", "type": "request",
                                          "uri": "ssap://system.launcher/launch", "payload": ["id": app]]
            if let sortie = try? JSONSerialization.data(withJSONObject: demande),
               let ligne = String(data: sortie, encoding: .utf8) { envoyer(ligne, sur: tache) }
        } else if type == "response" && id == "register_0" {
            if charge["pairingType"] as? String == "PROMPT" {
                dire("accord", "Sur la télé : accepter la demande de connexion, à la télécommande.")
            }
        } else if type == "response" && id == "lancer_0" {
            fermer()
            if charge["returnValue"] as? Bool == false {
                dire("erreur", "La télé a refusé de lancer l'app : "
                    + (charge["errorText"] as? String ?? "raison non donnée") + ".")
            } else {
                dire("lancee", "Lancée sur la télé.")
            }
        } else if type == "error" {
            let raison = message["error"] as? String ?? "raison non donnée"
            fermer()
            if id == "register_0" {
                // Une clé que la télé ne reconnaît plus (télé réinitialisée) : on l'oublie, le prochain essai redemande.
                UserDefaults.standard.removeObject(forKey: cleGardee)
                dire("erreur", "La télé a refusé la connexion (" + raison + "). Réessayer : elle redemandera l'accord.")
            } else {
                dire("erreur", "La télé a refusé de lancer l'app (" + raison + ").")
            }
        }
    }

    /// Ce qui se passe, rendu à la page : l'évènement `juclairian:tele`.
    private func dire(_ etat: String, _ message: String) {
        guard let json = try? JSONSerialization.data(withJSONObject: ["etat": etat, "message": message]),
              let objet = String(data: json, encoding: .utf8) else { return }
        vue?.evaluateJavaScript("dispatchEvent(new CustomEvent('juclairian:tele', { detail: \(objet) }));",
                                completionHandler: nil)
    }

    /// ⚠️ Le certificat de la télé est signé par elle-même : on l'accepte pour ELLE seule — l'adresse privée
    /// qu'on vient de demander —, jamais pour un autre hôte.
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let espace = challenge.protectionSpace
        if espace.authenticationMethod == NSURLAuthenticationMethodServerTrust, espace.host == hote,
           let confiance = espace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: confiance))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    /// Le message d'inscription de la télé, tel que le publie aiowebostv 1.0.2 (`handshake.py`) : la liste des
    /// droits demandés, et le manifeste signé de l'app de télécommande de LG, que toutes les télécommandes
    /// tierces présentent. Recopié sans retouche : la signature couvre le bloc `signed`.
    static let inscriptionNue = #"""
{"type":"register","id":"register_0","payload":{"forcePairing":false,"manifest":{"appVersion":"1.1","manifestVersion":1,"permissions":["LAUNCH","LAUNCH_WEBAPP","APP_TO_APP","CLOSE","TEST_OPEN","TEST_PROTECTED","CONTROL_AUDIO","CONTROL_DISPLAY","CONTROL_INPUT_JOYSTICK","CONTROL_INPUT_MEDIA_RECORDING","CONTROL_INPUT_MEDIA_PLAYBACK","CONTROL_INPUT_TV","CONTROL_POWER","CONTROL_TV_SCREEN","READ_APP_STATUS","READ_CURRENT_CHANNEL","READ_INPUT_DEVICE_LIST","READ_NETWORK_STATE","READ_RUNNING_APPS","READ_TV_CHANNEL_LIST","WRITE_NOTIFICATION_TOAST","READ_POWER_STATE","READ_COUNTRY_INFO","CONTROL_INPUT_TEXT","CONTROL_MOUSE_AND_KEYBOARD","READ_INSTALLED_APPS","READ_SETTINGS"],"signatures":[{"signature":"eyJhbGdvcml0aG0iOiJSU0EtU0hBMjU2Iiwia2V5SWQiOiJ0ZXN0LXNpZ25pbmctY2VydCIsInNpZ25hdHVyZVZlcnNpb24iOjF9.hrVRgjCwXVvE2OOSpDZ58hR+59aFNwYDyjQgKk3auukd7pcegmE2CzPCa0bJ0ZsRAcKkCTJrWo5iDzNhMBWRyaMOv5zWSrthlf7G128qvIlpMT0YNY+n/FaOHE73uLrS/g7swl3/qH/BGFG2Hu4RlL48eb3lLKqTt2xKHdCs6Cd4RMfJPYnzgvI4BNrFUKsjkcu+WD4OO2A27Pq1n50cMchmcaXadJhGrOqH5YmHdOCj5NSHzJYrsW0HPlpuAx/ECMeIZYDh6RMqaFM2DXzdKX9NmmyqzJ3o/0lkk/N97gfVRLW5hA29yeAwaCViZNCP8iC9aO0q9fQojoa7NQnAtw==","signatureVersion":1}],"signed":{"appId":"com.lge.test","created":"20140509","localizedAppNames":{"":"LG Remote App","ko-KR":"리모컨 앱","zxx-XX":"ЛГ Rэмotэ AПП"},"localizedVendorNames":{"":"LG Electronics"},"permissions":["TEST_SECURE","CONTROL_INPUT_TEXT","CONTROL_MOUSE_AND_KEYBOARD","READ_INSTALLED_APPS","READ_LGE_SDX","READ_NOTIFICATIONS","SEARCH","WRITE_SETTINGS","WRITE_NOTIFICATION_ALERT","CONTROL_POWER","READ_CURRENT_CHANNEL","READ_RUNNING_APPS","READ_UPDATE_INFO","UPDATE_FROM_REMOTE_APP","READ_LGE_TV_INPUT_EVENTS","READ_TV_CURRENT_TIME"],"serial":"2f930e2d2cfe083771f68e4fe7bb07","vendorId":"com.lge"}},"pairingType":"PROMPT"}}
"""#
}
