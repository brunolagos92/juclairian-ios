import SwiftUI
import WidgetKit

/// LE WIDGET D'IMAGO : un petit carré qui ouvre Imago ET lance les photos sur la télé — « on n'a pas plus simple
/// que ouvrir l'app, cliquer sur télé, lancer sur la télé ? » (Bruno, 11/11/2026). Sur le modèle des widgets d'Orla
/// (`Apps/OrlaWidgets`) : il ne lit aucune donnée, un tap ouvre l'app sur `JuclairianImago` + `?lancer=tele`, que
/// la coquille charge (`Coquille.swift`, `ouvrir`) ; c'est la PAGE qui lance alors la télé, par le canal de l'app
/// (`Tele.swift`). ⚠️ La télé doit être allumée, et l'iPhone sur le même Wi-Fi.
@main
struct ImagoWidgets: WidgetBundle {
    var body: some Widget {
        TeleWidget()
    }
}

struct TeleWidget: Widget { var body: some WidgetConfiguration { configuration() } }

private func configuration() -> some WidgetConfiguration {
    // ⚠️ Des chaînes TOUTES FAITES, jamais un littéral à trou : WidgetKit plante sur un texte formaté, et l'app
    // manque alors à la galerie sans autre signe (Orla, build 25).
    let nom: String = "Sur la télé"
    let phrase: String = "Ouvre Imago et lance les photos sur la télé."
    // `kind` désigne le widget chez iOS : un widget posé le garde, il ne change donc jamais.
    return StaticConfiguration(kind: "ImagoTele", provider: Fixe()) { _ in Carre(nom: nom) }
        .configurationDisplayName(nom)
        .description(Text(verbatim: phrase))
        .supportedFamilies([.systemSmall])
}

/// Rien ne change jamais dans le carré : une seule entrée, jamais renouvelée.
struct Fixe: TimelineProvider {
    struct Entree: TimelineEntry { let date: Date }
    func placeholder(in context: Context) -> Entree { Entree(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (Entree) -> Void) { completion(Entree(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entree>) -> Void) {
        completion(Timeline(entries: [Entree(date: Date())], policy: .never))
    }
}

/// Les couleurs de l'icône d'Imago : l'ocre du fond et la crème du tirage.
private let ocre = Color(red: 201 / 255, green: 146 / 255, blue: 62 / 255)
private let creme = Color(red: 246 / 255, green: 241 / 255, blue: 233 / 255)

struct Carre: View {
    let nom: String

    /// La page qui lance : `JuclairianImago` (Info.plist) + ce que la page attend pour lancer en arrivant.
    private var adresse: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "JuclairianImago") as? String).flatMap { URL(string: $0 + "?lancer=tele") }
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.tv").font(.system(size: 46, weight: .medium)).foregroundColor(creme)
            Text(nom).font(.system(size: 17, weight: .semibold)).foregroundColor(creme)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(adresse)
        .fond(ocre)
    }
}

private extension View {
    /// ⚠️ Depuis iOS 17, un widget sans `containerBackground` n'affiche qu'un message d'erreur à la place du
    /// carré ; avant, ce modificateur n'existe pas.
    @ViewBuilder func fond(_ couleur: Color) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(couleur, for: .widget)
        } else {
            background(couleur)
        }
    }
}
