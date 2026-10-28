import UIKit
import UserNotifications

/// Les notifications, pour l'app qui les demande : `JuclairianNotifications` à vrai dans son Info.plist (Electra,
/// le 28/10/2026 — « je veux juste les notifs », Bruno). La coquille ne décide RIEN de ce qui se notifie : elle
/// demande l'autorisation, s'inscrit auprès d'Apple et garde le jeton de cet iPhone ; la page le reçoit
/// (`CoquilleController.donnerJeton`), le site le garde et envoie lui-même, par Apple (APNs). Toucher une
/// notification ouvre l'app, rien de plus. Sans la clé, rien ne se passe : ni question, ni inscription.
final class Notifications: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Le jeton de cet iPhone pour cette app, en hexadécimal — nil tant qu'Apple ne l'a pas donné.
    static private(set) var jeton: String?
    /// Dit à la coquille que le jeton est arrivé (il vient après l'ouverture de la page, d'ordinaire).
    static let recu = Notification.Name("juclairianJetonRecu")

    static var actives: Bool {
        Bundle.main.object(forInfoDictionaryKey: "JuclairianNotifications") as? Bool ?? false
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        guard Notifications.actives else { return true }
        let centre = UNUserNotificationCenter.current()
        centre.delegate = self
        // La question n'est posée qu'une fois ; ensuite iOS répond seul, et l'inscription se refait à chaque
        // lancement (Apple peut changer le jeton).
        centre.requestAuthorization(options: [.alert, .sound, .badge]) { accorde, _ in
            guard accorde else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Notifications.jeton = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: Notifications.recu, object: nil)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Notifications : inscription refusée par Apple — \(error.localizedDescription)")
    }

    /// L'app au premier plan : la notification s'affiche quand même — sans ceci, iOS la tait.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
