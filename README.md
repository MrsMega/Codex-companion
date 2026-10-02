# Codex Promenade

## Télécharger et recevoir les mises à jour

Le dépôt public est **[MrsMega/Codex-companion](https://github.com/MrsMega/Codex-companion)**.
La [page Releases](https://github.com/MrsMega/Codex-companion/releases)
regroupe les téléchargements. La version 2.9.0 est publiée pour Linux et
Windows à partir du même code Electron. Un paquet macOS sera ajouté après la
mise en place de la signature et de la notarisation Apple.

| Système | Premier téléchargement | Mises à jour suivantes |
| --- | --- | --- |
| Windows | Installateur `.exe` par utilisateur | Téléchargées en arrière-plan, installées à la fermeture ou via le menu |
| Linux X11/Xwayland | Fichier `.AppImage` à rendre exécutable | Téléchargées en arrière-plan, installées à la fermeture ou via le menu |
| macOS | `.dmg` signé et notarisé | Téléchargées en arrière-plan, installées à la fermeture ou via le menu |

Les mises à jour sont vérifiées peu après le démarrage puis toutes les six heures.
Elles viennent des releases publiques GitHub et utilisent les empreintes
fournies par `electron-builder`. Il faut conserver le même dépôt GitHub après
la première publication : son adresse est enregistrée dans l'application.
Sous Fedora Wayland, l'application utilise Xwayland et le rendu logiciel pour
éviter les plantages du processus GPU. Si la version 2.8.0 reste invisible,
télécharger et lancer manuellement une version plus récente une fois.

La distribution utilise le code partagé dans `desktop/` avec Electron. La
version Swift décrite ci-dessous reste le build macOS local. Une installation
de l'ancienne version Swift ne se transforme pas automatiquement en version
Electron : il faut installer une fois la première release macOS.

### Préparer une publication

1. Installer Node.js 24 et exécuter `cd desktop && npm ci && npm run check`.
   Pour voir l'application localement, lancer `npm start` dans ce dossier.
2. Pousser `main` sur le dépôt public `MrsMega/Codex-companion`. La
   vérification GitHub Actions contrôle le code, les paquets et les sprites.
3. Pour publier une version, mettre à jour `desktop/package.json` et son
   `package-lock.json`, puis pousser le tag correspondant, par exemple
   `v2.9.0`. GitHub Actions construit Linux et Windows, crée une release
   brouillon puis la rend publique après vérification des deux paquets et des
   fichiers de mise à jour.
4. Pour ajouter macOS aux releases, configurer un certificat Apple Developer
   ID, la notarisation et les secrets GitHub `MAC_CSC_LINK`,
   `MAC_CSC_KEY_PASSWORD`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD` et
   `APPLE_TEAM_ID`. Définir ensuite la variable GitHub Actions
   `MAC_RELEASE_READY=true`. Sans ces éléments, le build macOS de publication
   est ignoré afin de ne pas distribuer une application bloquée par Gatekeeper.
   Un certificat Windows facultatif se configure avec `WIN_CSC_LINK` et
   `WIN_CSC_KEY_PASSWORD` ; sans lui Windows peut afficher un avertissement.

La version distribuée reprend les animations, la promenade, le portage, les
menus et l'ouverture de ChatGPT. Les réactions aux clics, frappes et
sélections **dans les autres applications** restent propres à la version
Swift macOS pour l'instant. Sur Linux, le compagnon doit fonctionner sous X11
ou Xwayland : Wayland interdit aux applications de placer librement leurs
fenêtres sur le bureau.

Les sprites sont intégrés aux releases avec les droits de redistribution
confirmés par le propriétaire du dépôt. Aucun certificat ni secret de
publication ne doit être ajouté aux fichiers Git.

Projet source de l'application macOS **Codex Promenade**. Il ne s'agit pas d'un
projet Xcode : le code de l'application tient dans `CodexPromenade.swift` et
se compile avec `swiftc` et les frameworks fournis par macOS.

## Contenu

- `CodexPromenade.swift` : fenêtre transparente, animation, déplacements,
  interactions et menu contextuel.
- `Resources/` : feuille de sprites Codex présente dans l'application ChatGPT
  installée sur le Mac de création (dont les poses de marche), plus les poses
  ajoutées pour le salto, les émotions, le clic droit, la sélection de texte,
  le portage, l'atterrissage, le repos et le sommeil, ainsi que l'icône de
  l'application.
- `harmonize-sprites.swift` : outil de maintenance qui ajuste les bleus, les
  dégradés et l'échelle des poses assises à partir de la pose d'origine.
- `sprite-manifest.json` : liste des planches et de leurs nombres de cases.
- `validate-sprites.swift` : vérification des dimensions, couleurs et tailles
  avant chaque reconstruction de l'application.
- `AGENTS.md` : consignes pour conserver la cohérence des prochains sprites.
- `make-icon.swift` : dessin vectoriel de l'icône et génération des fichiers `.icns`, `.ico` et `.png` pour macOS, Windows et Linux.
- `Info.plist` : nom, version, identifiant et configuration de l'application.
- `build.sh` : reconstruction locale de l'application.

## Fonctionnement

`PetController` crée une petite fenêtre transparente qui flotte sur le bureau.
`PetView` dessine un sprite à la fois. Un minuteur d'environ 60 images par
seconde met à jour les positions et choisit la pose correspondant à l'action.
Les actions sont des états : marche, pause, réflexion, choc, salut, salto,
émotions, regard, repos, sommeil, portage et chute. Les trajets, durées et actions sont choisis
avec une part d'aléatoire. La pose de marche dépend de la distance parcourue
pour limiter le glissement des pieds. Les trajets restent parfois horizontaux
et peuvent aussi monter et descendre dans la zone visible de l'écran. Le
compagnon garde son animation de marche pendant ces déplacements et sa
position en hauteur à l'arrêt.

Le compagnon s'assoit de temps à autre pendant quelques secondes. Plus rarement,
il ferme les yeux et dort un peu plus longtemps, avec une légère respiration.
Une nouvelle interaction peut le réveiller. Le menu contextuel permet aussi de
déclencher immédiatement les poses « Se reposer » et « Dormir ».

Le menu contextuel permet d'ajouter jusqu'à six compagnons et de retirer celui
sur lequel on clique. Deux compagnons proches, à la même hauteur, peuvent se
saluer en se touchant les mains puis danser, discuter à tour de rôle, faire des
saltos alternés ou rire ensemble. La commande « Faire une activité à deux »
déclenche une de ces nouvelles scènes avec un voisin. Leurs animations commencent
au même moment, puis une pause évite que la scène se répète sans arrêt. Porter
ou commander l'un des deux interrompt leur interaction commune.

Un clic droit, y compris dans une autre application, déclenche une courte
réaction de curiosité. Un clic droit sur la mascotte ouvre aussi ses commandes.
Un double-clic dans une autre application la fait rire.
La sélection de texte déclenche une animation dédiée lorsque l'accès
Accessibilité est déjà autorisé. Seule la position et la longueur de la
sélection sont consultées : son contenu n'est pas lu.
Sans cet accès, un glisser de souris assez long déclenche la même animation.
Il s'agit alors d'une réaction au geste, qui peut aussi se produire lorsque
l'utilisateur déplace autre chose que du texte.

Le glisser-déposer porte la mascotte :
elle suit le pointeur avec un léger retard amorti. Au lâcher, elle garde
la vitesse du geste, suit une trajectoire soumise à la gravité, rebondit
contre les bords et le sol, puis joue une séquence d'atterrissage avant de repartir.
L'application observe les clics et les changements d'application pour orienter
son regard. Si macOS a déjà accordé les accès nécessaires, elle peut aussi
repérer le contrôle actif et réagir au moment des frappes. Elle n'utilise pas
les caractères saisis. Elle ne demande pas automatiquement ces accès.

## Construire

Sur un Mac équipé des outils de développement Swift, ouvrir Terminal dans ce
dossier puis exécuter :

```sh
zsh build.sh
```

L'application construite se trouve dans `../Codex Promenade.app`. Le script
recrée l'icône, compile et signe une copie temporaire avant de remplacer
l'application existante. Si la validation ou la compilation échoue, celle-ci
reste utilisable. Il utilise une signature locale ad hoc et ne modifie pas la quarantaine macOS,
Gatekeeper ou les autorisations du système. Une politique d'entreprise peut
empêcher l'ouverture d'une application construite localement.

Pour ajouter une animation, enregistrer son nom, son nombre de cases et son
type de pose dans `sprite-manifest.json`, puis l'harmoniser avant de lancer
`build.sh`. Le script de construction valide automatiquement toutes les
planches ; en cas d'échec, l'application déjà construite est conservée.

Le double-clic sur la mascotte ouvre ChatGPT à l'emplacement enregistré par
macOS. Les dossiers Applications du système et de l'utilisateur servent de
secours si l'application n'est pas enregistrée. Une erreur visible est
affichée si ChatGPT est absent ou ne peut pas être lancé.
