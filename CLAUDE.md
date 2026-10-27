# juclairian-ios — les apps iPhone, iPad et Mac

Les apps natives des outils Juclairian, distribuées en **TestFlight interne** (pas d'App Store, donc
pas de revue d'Apple à chaque version). Chacune est une **coquille** qui ouvre le site, plus une
**extension de partage**. Le code de l'app (écrans, logique, données) **n'est pas ici** : il est sur le
site, dans `juclairian` (Vela, Orla, Hora…) et `juclairian-app` (Patrimonia, Numeria, Livria). Un push
sur le site est dans l'app aussitôt ; ce dépôt ne change que quand l'enveloppe change.

## Ce qui vit ici

| Où | Quoi |
|---|---|
| `project.yml` | Le projet, décrit pour **XcodeGen**. Le `.xcodeproj` est généré, jamais commité. |
| `Commun/Coquille` | L'app : une vue web sur `JuclairianDepart` (Info.plist), liens externes dehors, dialogues du site. |
| `Commun/Partage` | L'extension de partage : ouvre `JuclairianPartage` (Info.plist), `{url}` = le lien partagé. |
| `Commun/Web` | Ce que les deux partagent. ⚠️ Rien qui appelle `UIApplication.shared` : interdit dans une extension. |
| `Apps/<App>` | Ce qui est propre à une app : son icône (1024 px, **sans canal alpha** — App Store refuse). Ses réglages (adresses, permissions) sont dans `project.yml` ; les `Info.plist` en sont générés dans `Plists/`, jamais commités. |
| `.github/workflows/construire.yml` | Compile à chaque push ; signe et envoie dans TestFlight si la clé d'API est posée. |

**Une app de plus** = une cible et son extension dans `project.yml`, un dossier `Apps/<App>` avec son
icône. Rien dans `Commun/` ne doit nommer une app.

## Consignes

- **Pas de Mac ici** : on ne compile pas dans la session. La seule preuve qu'un changement se construit
  est le passage de `construire.yml` sur GitHub — on ne dit pas « ça marche » avant de l'avoir lu.
- **On ne pousse que sur demande de Bruno** (« push »), comme dans les autres dépôts : un push
  construit et, la clé posée, **livre** une version dans TestFlight. Et les minutes macOS de GitHub
  comptent dix fois sur un dépôt privé.
- **La session de l'extension est la sienne** : on s'y connecte une fois, au premier partage ; la page
  de connexion du site la reprend seule ensuite. Partager la session de l'app viendra si ça gêne.
- Le reste de la doctrine (proposer avant de faire, ne pas supposer, mesurer) est celle des autres
  dépôts : `juclairian-app/AGENTS.md`, `juclairian/CLAUDE.md`.
