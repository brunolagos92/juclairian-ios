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
| `fastlane/Fastfile` | La signature et l'envoi. `match` crée une fois le certificat de distribution et les profils App Store, et les garde **chiffrés dans la branche `signature`** — jamais à la main, jamais fusionnée dans `main`. |

**Une app de plus** = une cible et son extension dans `project.yml`, un dossier `Apps/<App>` avec son
icône. Rien dans `Commun/` ne doit nommer une app.

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
- **La session de l'extension est la sienne** : on s'y connecte une fois, au premier partage ; la page
  de connexion du site la reprend seule ensuite. Partager la session de l'app viendra si ça gêne.
- Le reste de la doctrine (proposer avant de faire, ne pas supposer, mesurer) est celle des autres
  dépôts : `juclairian-app/AGENTS.md`, `juclairian/CLAUDE.md`.
