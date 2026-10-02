# Règles du projet Codex Promenade

## Identité visuelle des sprites

- La première case de `Resources/codex-spritesheet-v6.webp` est la référence
  visuelle : même personnage, mêmes proportions de tête et de corps, même
  bleu, même dégradé et mêmes ombres bleu marine.
- Chaque image d'animation est une planche PNG transparente de cases
  `192 × 208` pixels. Garder le cadrage, les marges, la netteté et l'ordre des
  images ; ne pas déformer une pose pour remplir la case.
- Garder la tête et le corps à la même échelle d'une animation à l'autre.
  Aligner les pieds des poses debout sur la ligne de sol de la référence.
  Une pose assise ou en rotation peut être plus courte, mais sa tête ne doit
  pas devenir visiblement plus petite.
- Ne pas altérer les yeux cyan, le symbole blanc du torse ou la transparence
  en corrigeant les bleus. Vérifier le rendu sur fond clair et foncé.

## À chaque ajout ou remplacement de sprite

1. Ajouter la planche à `Resources/` et l'enregistrer dans
   `sprite-manifest.json` avec son nom, son nombre de cases et son type de pose
   (`standing`, `seated`, `carried` ou `rotating`). Mettre à jour
   `CodexPromenade.swift` pour charger exactement ce nom et ce nombre de cases.
2. Harmoniser la nouvelle planche avec `harmonize-sprites.swift`. Écrire le
   résultat dans un dossier temporaire distinct de `Resources/`, puis copier
   la planche retenue dans `Resources/`. L'outil accepte un ou plusieurs noms
   de fichiers après les deux dossiers ; sans noms, il traite tout le manifeste.
3. Inspecter les images et l'animation : identité du personnage, dégradé
   tête/corps, contour, taille, sol et absence de sauts visuels entre cases.
   Corriger les défauts visibles même si le contrôle automatique passe.
4. Exécuter `zsh build.sh`. La construction lance
   `validate-sprites.swift` avant de remplacer l'application et s'arrête si
   une planche manque, est mal dimensionnée ou s'écarte trop de la référence.
   Corriger le sprite plutôt que d'augmenter les tolérances pour contourner
   un échec. Vérifier ensuite l'application et sa signature.

## Livraison

`build.sh` écrit l'unique application dans `../Codex Promenade.app`. Mettre à
jour ce projet et cette application en place. Ne pas créer de projet `2.x`,
de seconde `.app` ou d'archive de version dans `r/outputs/`.
