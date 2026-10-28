# juclairian-ios — les apps iPhone, iPad et Mac

Les apps natives des outils Juclairian, distribuées en **TestFlight interne** (pas d'App Store, donc
pas de revue d'Apple à chaque version). Chacune est une **coquille** qui ouvre le site, plus une
**extension de partage** quand quelque chose se partage vers elle (Hora n'en a pas). Le code de l'app (écrans, logique, données) **n'est pas ici** : il est sur le
site, dans `juclairian` (Vela, Orla, Hora…) et `juclairian-app` (Patrimonia, Numeria, Livria). Un push
sur le site est dans l'app aussitôt ; ce dépôt ne change que quand l'enveloppe change.

## Ce qui vit ici

| Où | Quoi |
|---|---|
| `project.yml` | Le projet, décrit pour **XcodeGen**. Le `.xcodeproj` est généré, jamais commité. |
| `Commun/Coquille` | L'app : une vue web sur `JuclairianDepart` (Info.plist), liens externes dehors, dialogues du site. |
| `Commun/Partage` | L'extension de partage : ouvre `JuclairianPartage` (Info.plist), `{url}` = le lien partagé. Elle pose le canal **`juclairianPartage`** : le site y voit qu'il est dans la feuille (il retire son menu) et y envoie `{ fini: true, texte }` quand tout est écrit — la fenêtre le montre, puis se ferme ; ou `{ titre: true }` pour DEMANDER le titre de la page partagée, que la fenêtre lit depuis le téléphone (Amazon refuse sa page aux serveurs, pas à un iPhone) et rend dans `window.juclairianTitrePartage`. `{texte}` dans l'adresse reçoit le texte joint au lien, sans ses adresses. Contrat avec le site : `nav.html` (`partageFini`) et `orla-lectures.html` (`titreParLApp`) dans `juclairian`. |
| `Commun/Web` | Ce que les deux partagent. ⚠️ Rien qui appelle `UIApplication.shared` : interdit dans une extension. |
| `Apps/<App>` | Ce qui est propre à une app : son icône (1024 px, **sans canal alpha** — App Store refuse). Ses réglages (adresses, permissions) sont dans `project.yml` ; les `Info.plist` en sont générés dans `Plists/`, jamais commités. |
| `.github/workflows/construire.yml` | Compile à chaque push ; signe et envoie dans TestFlight si la clé d'API est posée. |
| `fastlane/Fastfile` | La signature et l'envoi. `match` crée une fois le certificat de distribution et les profils App Store, et les garde **chiffrés dans la branche `signature`** — jamais à la main, jamais fusionnée dans `main`. |

**Une app de plus** = une cible et son extension dans `project.yml`, un dossier `Apps/<App>` avec son
icône (1024 px, RGB sans alpha — tirée de celle du site, `scripts/suivi.mjs` de `juclairian`), une ligne
dans `APPS` du `Fastfile`, son schéma dans l'étape « Compiler » de `construire.yml` — et **sa fiche App
Store Connect créée à la main par Bruno** (Apps → + → Nouvelle app, nom « <App> Juclairian », identifiant
`com.juclairian.<app>`), une fois que la construction a déclaré l'identifiant. D'ici là, la construction
envoie les autres et dit laquelle attend. Rien dans `Commun/` ne doit nommer une app.

**Les apps** : **Orla** (`/orla/`, partage → `/orla/ajouter-lieu/`), **Vela** (`/voyages/`, partage →
`/ajouter-lieu/`, le choix du voyage puis de la Réserve ou de la journée), **Hora** (`/echeances/`, sans
extension : aucune page de Hora ne reçoit un lien ; ni photo ni position, donc aucune phrase de permission)
et **Numeria** (`https://numeria.juclairian.com/`, son propre site, dépôt `juclairian-app` ; sans extension ;
son import CSV passe par le sélecteur de fichiers, sans appareil photo) et **Electra**
(`http://100.112.244.82:8321/` — elle ne tourne que sur le Mac de Bruno, que l'iPhone joint par **Tailscale** ;
d'où l'exception ATS `NSAllowsArbitraryLoadsInWebContent`, propre à sa cible ; son code n'est dans aucun dépôt).
Leur icône vient de `scripts/suivi.mjs` (`icone`, `iconeOrla`, `iconeHora`) : celle de Hora sort en RGBA
opaque, l'alpha s'ôte sans rien changer à l'image. Celle de Numeria vient de `numeria/assets/icon.svg`
(`juclairian-app`), rendue en 1024 px par Chromium **sans son arrondi** (`rx="40"` ôté du fond) : iOS pose
son propre masque, un arrondi dessiné laisserait ses coins. Celle d'Electra est la sienne (la maison et l'éclair,
servie par Electra à `/icone.svg`, que Bruno a collée) : gardée dans `Apps/Electra/icone.svg`, sans l'arrondi de
son fond, car son code n'est dans aucun dépôt.

## Consignes

- **Pas de Mac ici** : on ne compile pas dans la session. La seule preuve qu'un changement se construit
  est le passage de `construire.yml` sur GitHub — on ne dit pas « ça marche » avant de l'avoir lu.
- **Ici, on pousse SANS demander** : « oui, pousse sans me demander sur juclairian-ios » (Bruno,
  27/10/2026), après six allers-retours pour mettre la construction au point. C'est propre à CE dépôt
  — les autres gardent leur règle. Mais on ne revient vers Bruno qu'avec un résultat : l'app dans
  TestFlight, ou ce qui bloque vraiment et ce qu'il doit faire. Et on pousse peu : les minutes macOS
  de GitHub comptent dix fois sur un dépôt privé — un essai doit être sûr avant de partir.
- **La signature est manuelle en Release, et c'est voulu.** La signature automatique de Xcode a
  échoué six fois sur la machine de GitHub (profil de développement exigé, profils recréés à chaque
  passage, l'app et son extension qui se disputent leur création). Une app de plus = ses identifiants
  dans `APPS` du `Fastfile`, et `PROVISIONING_PROFILE_SPECIFIER: match AppStore <identifiant>` en
  Release dans `project.yml`. Le mot de passe de `signature` est tiré de la clé d'API : changer de
  clé = supprimer la branche, la construction suivante recrée tout.
- **Ce qui a fait passer le premier envoi** (Orla, build 10, 27/10/2026 — dix essais) :
  - **Xcode 26 obligatoire** : Apple refuse tout envoi construit avec un SDK plus ancien. D'où
    `runs-on: macos-26` ; macos-15 donnait Xcode 16.4 (essai 9, signé puis rejeté).
  - **Les identifiants (bundle ID) doivent exister chez Apple** : le `Fastfile` déclare ceux qui
    manquent. La signature automatique se contentait du joker « XC Wildcard ».
  - **La fiche de l'app dans App Store Connect se crée À LA MAIN**, une fois par app : l'API d'Apple
    ne le permet pas. Orla y porte le nom « Orla Juclairian » (le nom public doit être unique sur
    tout l'App Store ; sous l'icône, c'est `CFBundleDisplayName` qui s'affiche). Une app de plus =
    demander à Bruno de la créer, avec son identifiant, AVANT le premier envoi.
  - **TestFlight interne** : être propriétaire du compte ne suffit pas, il faut un groupe interne
    avec Bruno dedans (fait pour Orla, distribution automatique).
- ⚠️ **Ce que Bruno fait dans App Store Connect, il le fait** — la fiche, puis son groupe de test
  interne. Le lui rappeler une fois qu'il a dit « fait » suppose qu'il ne l'a pas fait (« évidemment
  c'est fait. Pourquoi toujours supposer ce genre de choses ? », 28/10/2026). On ne lui dit que ce
  qu'on ne peut pas faire soi-même, une fois.
- **La session de l'extension est la sienne** : on s'y connecte une fois, au premier partage ; la page
  de connexion du site la reprend seule ensuite. Partager la session de l'app viendra si ça gêne.
- Le reste de la doctrine (proposer avant de faire, ne pas supposer, mesurer) est celle des autres
  dépôts : `juclairian-app/AGENTS.md`, `juclairian/CLAUDE.md`.
