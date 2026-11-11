import Foundation
import Network
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
/// ⚠️ EN VEILLE, la télé ne répond pas : on tente de la RÉVEILLER (`reveiller`, un paquet « Wake-on-LAN » adressé
/// à elle seule), avec l'adresse matérielle qu'elle a donnée lors d'un lancement allumée (`reseau_0`). La forme
/// habituelle du paquet — diffusée à tout le réseau — demande sur iOS un droit qu'Apple accorde au cas par cas.
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
        debut = Date()
        reveils = 0
        lancee = false
        dire("connexion", "Connexion à la télé…")
        ouvrir()
    }

    /// ⚠️ UN ESSAI DE CONNEXION, et l'on en fait plusieurs (11/11/2026 : « télé en veille, cela ne fonctionne
    /// pas », Bruno). En veille, la télé ne répond pas ; et tant qu'on n'a pas répondu à la question d'iOS sur le
    /// réseau local, iOS fait comme s'il n'y avait pas de réseau. Dans les deux cas l'essai reste muet : au bout
    /// de `patience` secondes sans un mot de la télé on l'abandonne, on la RÉVEILLE si l'on sait comment, et l'on
    /// recommence — pendant `duree` secondes en tout. Seulement `wss://…:3001` : c'est la porte des télés de 2020
    /// et après.
    private let patience: TimeInterval = 5
    private let duree: TimeInterval = 40
    private var debut = Date()
    private var reveils = 0

    private func ouvrir() {
        guard let url = URL(string: "wss://" + hote + ":3001") else { return }
        entendu = false
        let reglage = URLSessionConfiguration.ephemeral
        reglage.waitsForConnectivity = true
        let session = URLSession(configuration: reglage, delegate: self, delegateQueue: .main)
        let tache = session.webSocketTask(with: url)
        self.session = session
        self.tache = tache
        tache.resume()
        envoyer(inscription(), sur: tache)
        ecouter(tache)
        armer(patience) { [weak self] in
            guard let self = self, self.tache === tache, !self.entendu else { return }
            self.muet("elle ne répond pas")
        }
    }

    /// Une seule échéance à la fois : la poser annule la précédente.
    private func armer(_ secondes: TimeInterval, _ suite: @escaping () -> Void) {
        garde?.cancel()
        let garde = DispatchWorkItem(block: suite)
        self.garde = garde
        DispatchQueue.main.asyncAfter(deadline: .now() + secondes, execute: garde)
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
    private var macsGardees: String { "juclairianTeleMac-" + hote }

    /// La télé n'a rien dit : on la réveille si l'on connaît son adresse matérielle, et l'on recommence.
    private func muet(_ raison: String) {
        fermer()
        let macs = UserDefaults.standard.stringArray(forKey: macsGardees) ?? []
        if Date().timeIntervalSince(debut) > duree {
            var texte = "La télé ne s'est pas réveillée (" + raison + "). L'allumer à la télécommande, puis relancer."
            if macs.isEmpty {
                texte = "La télé ne répond pas (" + raison + "). Si elle est en veille : la lancer une fois allumée, "
                texte += "pour que l'app apprenne à la réveiller. Sinon : Réglages de l'iPhone → Confidentialité et "
                texte += "sécurité → Réseau local, y autoriser cette app."
            }
            return dire("erreur", texte)
        }
        if !macs.isEmpty {
            reveiller(macs)
            reveils += 1
            if reveils == 1 { dire("connexion", "La télé est en veille : réveil en cours…") }
        }
        armer(2) { [weak self] in self?.ouvrir() }
    }

    /// ⚠️ LE PAQUET DE RÉVEIL (« Wake-on-LAN ») : six octets FF puis seize fois l'adresse matérielle, en UDP. On
    /// l'adresse à la télé SEULE (et à l'adresse de diffusion de son réseau, au cas où) : la diffusion à tout le
    /// réseau, sa forme habituelle, demande sur iOS un droit qu'Apple accorde au cas par cas — sans lui cet envoi-là
    /// est simplement ignoré. Il faut que la télé ait « Activer via Wi-Fi » allumé, et qu'elle réponde encore en veille.
    private func reveiller(_ macs: [String]) {
        var cibles = [hote]
        var morceaux = hote.split(separator: ".").map(String.init)
        if morceaux.count == 4 {
            morceaux[3] = "255"
            cibles.append(morceaux.joined(separator: "."))
        }
        for mac in macs {
            let octets = mac.split(separator: ":").compactMap { UInt8($0, radix: 16) }
            guard octets.count == 6 else { continue }
            var paquet = Data(repeating: 0xFF, count: 6)
            for _ in 0..<16 { paquet.append(contentsOf: octets) }
            for cible in cibles {
                let ports: [NWEndpoint.Port] = [9, 7]
                for port in ports {
                    let envoi = NWConnection(host: NWEndpoint.Host(cible), port: port, using: .udp)
                    envoi.start(queue: .main)
                    envoi.send(content: paquet, completion: .contentProcessed { _ in })
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { envoi.cancel() }
                }
            }
        }
    }

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

    private func demander(_ id: String, _ uri: String, _ charge: [String: Any], sur tache: URLSessionWebSocketTask) {
        let demande: [String: Any] = ["id": id, "type": "request", "uri": uri, "payload": charge]
        if let sortie = try? JSONSerialization.data(withJSONObject: demande),
           let ligne = String(data: sortie, encoding: .utf8) { envoyer(ligne, sur: tache) }
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
                    if !self.entendu {
                        self.entendu = true
                        // La télé parle : on lui laisse une minute, le temps de l'accord à la télécommande.
                        self.armer(60) { [weak self] in
                            guard let self = self, self.tache === tache else { return }
                            self.fermer()
                            self.dire("erreur", "La télé n'a pas fini de répondre.")
                        }
                    }
                    if case .string(let texte) = message { self.lire(texte, de: tache) }
                    if self.tache === tache { self.ecouter(tache) }
                }
            }
        }
    }

    /// La connexion est tombée. Avant tout mot de la télé : c'est un essai muet, on recommence ; après : on le dit.
    private func rompu(_ tache: URLSessionWebSocketTask, _ raison: String) {
        guard self.tache === tache else { return }
        if !entendu { return muet(raison) }
        fermer()
        dire("erreur", "La connexion à la télé s'est interrompue (" + raison + ").")
    }

    private func lire(_ texte: String, de tache: URLSessionWebSocketTask) {
        guard let donnees = texte.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any] else { return }
        let type = message["type"] as? String ?? ""
        let id = message["id"] as? String ?? ""
        let charge = message["payload"] as? [String: Any] ?? [:]
        if type == "registered" {
            if let cle = charge["client-key"] as? String { UserDefaults.standard.set(cle, forKey: cleGardee) }
            // D'abord son adresse matérielle (pour la réveiller une autre fois), puis le lancement.
            demander("reseau_0", "ssap://com.webos.service.connectionmanager/getinfo", [:], sur: tache)
            demander("lancer_0", "ssap://system.launcher/launch", ["id": app], sur: tache)
        } else if type == "response" && id == "register_0" {
            if charge["pairingType"] as? String == "PROMPT" {
                dire("accord", "Sur la télé : accepter la demande de connexion, à la télécommande.")
            }
        } else if id == "reseau_0" {
            // Refusée ou non : on n'en dit rien, le lancement ne dépend pas d'elle.
            var macs: [String] = []
            for bloc in ["wifiInfo", "wiredInfo"] {
                if let mac = (charge[bloc] as? [String: Any])?["macAddress"] as? String,
                   mac.split(separator: ":").count == 6, !macs.contains(mac) { macs.append(mac) }
            }
            if !macs.isEmpty { UserDefaults.standard.set(macs, forKey: macsGardees) }
            if lancee { fermer() }
        } else if type == "response" && id == "lancer_0" {
            if charge["returnValue"] as? Bool == false {
                fermer()
                dire("erreur", "La télé a refusé de lancer l'app : "
                    + (charge["errorText"] as? String ?? "raison non donnée") + ".")
            } else {
                dire("lancee", "Lancée sur la télé.")
                // On attend encore un instant la réponse sur son adresse matérielle, si elle n'est pas venue.
                lancee = true
                armer(3) { [weak self] in self?.fermer() }
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
    private var lancee = false

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
