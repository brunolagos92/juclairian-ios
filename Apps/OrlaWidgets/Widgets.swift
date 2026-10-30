import SwiftUI
import WidgetKit

/// LES WIDGETS D'ORLA : un petit carré par onglet, qui ouvre Orla sur cet onglet — « un petit widget par
/// onglet », « pas les 7 : Repas, Recettes, Séries », « seulement l'icône et le nom » (Bruno, 30/10/2026).
/// Ils ne lisent aucune donnée : un tap ouvre l'app sur `JuclairianOrla` + le chemin de l'onglet, que la
/// coquille charge (`Coquille.swift`, `ouvrir`). L'icône et le nom sont ceux du menu du site (`nav.html`).
struct Onglet {
    /// Ce qui désigne le widget chez iOS : un widget posé le garde, il ne change donc jamais.
    let genre: String
    let nom: String
    let icone: String
    /// La page, sous `JuclairianOrla` (Info.plist).
    let chemin: String

    var adresse: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "JuclairianOrla") as? String).flatMap { URL(string: $0 + chemin) }
    }

    static let repas = Onglet(genre: "OrlaRepas", nom: "Repas", icone: "🍽", chemin: "repas/")
    static let recettes = Onglet(genre: "OrlaRecettes", nom: "Recettes", icone: "🥘", chemin: "recettes/")
    static let series = Onglet(genre: "OrlaSeries", nom: "Séries", icone: "📺", chemin: "series/")
}

@main
struct OrlaWidgets: WidgetBundle {
    var body: some Widget {
        RepasWidget()
        RecettesWidget()
        SeriesWidget()
    }
}

// Un type par widget : iOS les recense ainsi dans la galerie (Widget exige un `init()` sans argument).
struct RepasWidget: Widget { var body: some WidgetConfiguration { configuration(.repas) } }
struct RecettesWidget: Widget { var body: some WidgetConfiguration { configuration(.recettes) } }
struct SeriesWidget: Widget { var body: some WidgetConfiguration { configuration(.series) } }

private func configuration(_ onglet: Onglet) -> some WidgetConfiguration {
    // ⚠️ Une chaîne TOUTE FAITE, jamais un littéral à trou : `"… \(x)"` devient un texte formaté, que WidgetKit
    // refuse (« Formatted text for `description` is not supported ») — l'extension plantait quand iOS lui
    // demandait ses widgets, et Orla manquait à la galerie (build 25, lu par `diagnostic.yml`, 30/10/2026).
    let phrase = "Ouvre Orla sur les " + onglet.nom.lowercased() + "."
    return StaticConfiguration(kind: onglet.genre, provider: Fixe()) { _ in Carre(onglet: onglet) }
        .configurationDisplayName(onglet.nom)
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

/// Les couleurs des pages d'Orla : le papier (#faf7f2) et l'encre (#2a2622).
private let papier = Color(red: 250 / 255, green: 247 / 255, blue: 242 / 255)
private let encre = Color(red: 42 / 255, green: 38 / 255, blue: 34 / 255)

struct Carre: View {
    let onglet: Onglet
    var body: some View {
        VStack(spacing: 8) {
            Text(onglet.icone).font(.system(size: 52))
            Text(onglet.nom).font(.system(size: 17, weight: .semibold)).foregroundColor(encre)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(onglet.adresse)
        .fond(papier)
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
