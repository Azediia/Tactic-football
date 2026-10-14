# Tactic Football

Jeu de football tactique en 3D (Godot 4.3). On ne pilote pas les joueurs : on leur donne des ordres pendant des pauses, et le résultat de chaque action est décidé par un jet de d100 lié aux notes du joueur, avec un vrai ballon physique.

Toutes les règles de conception sont dans [`docs/GDD.md`](docs/GDD.md).

## Lancer le jeu

1. Installer [Godot 4.3](https://godotengine.org/download) (version standard, pas .NET).
2. Cloner ce dépôt : `git clone https://github.com/Azediia/Tactic-football`
3. Ouvrir Godot, cliquer sur **Importer**, choisir le fichier `project.godot` de ce dossier.
4. Appuyer sur **F5** (ou le bouton ▶) pour lancer.

Pour récupérer la dernière version : `git pull`, puis relancer dans Godot.

## Comment jouer

Un match de 10 minutes (2 mi-temps de 5), 5 contre 5. Tu diriges les **bleus** (à gauche, ils attaquent vers la droite). Les rouges sont gérés par l'IA, et tes joueurs sans ordre jouent en autonomie.

- **Pause tactique** (`Espace`) : le temps s'arrête, tu donnes tous les ordres que tu veux, puis tu reprends. Après une pause, il faut attendre 15 s de jeu avant la suivante. Les arrêts de jeu (coup d'envoi, touche, corner, sortie de but) offrent une pause gratuite.
- **Choisir un joueur** : clic sur un joueur bleu. Le menu à gauche affiche ses ordres possibles.
  - **Courir** : clics sur le terrain pour tracer sa course (points de passage). Choix de l'allure (marche, trot, sprint). Avec le ballon, le menu indique la sûreté de la conduite.
  - **Passer** : clic sur un coéquipier (passe dans les pieds) ou sur le terrain (passe en profondeur). Au sol ou aérienne, force réglable, effet à la molette.
  - **Tirer** : clic dans le but adverse pour viser. Hauteur (ras du sol, mi-hauteur, lucarne), puissance réglable, effet à la molette.
  - **Tacler** : clic sur l'adversaire qui a le ballon.
- Les ordres s'enchaînent. Un ordre de passe ou de tir attend que le joueur ait le ballon. Si le ballon change de camp, **tous les ordres sont annulés**.
- Avant de valider une passe, un tir ou un tacle, une **infobulle** donne le pourcentage de réussite, les chances de critique et les risques (ex. adversaire sur la trajectoire).
- Le **journal des jets** (en haut à droite) explique chaque résultat : `jet 34 / 74 : réussie`.

Touches : `Espace` pause / reprise · `Échap` annuler la visée · `1 2 3` allures · `Molette` effet · `T` vitesse du temps (x1, x2, x4) · `Clic droit` effacer les ordres du joueur.

## Règles de dés (résumé)

d100 contre une chance de réussite (stat du joueur − difficulté − fatigue − pression). Réussite critique : jet ≤ chance / 10. Échec critique : jet au-delà de chance + 50. Plus l'échec est grand, plus la frappe s'écarte de ton ordre. L'effet est limité par la technique du joueur.

## Tests

```
godot --headless --fixed-fps 120 --path . -s tests/smoke_test.gd      # tests automatiques
godot --headless --fixed-fps 120 --path . -s tests/sim_match.gd -- 1  # match complet IA contre IA (graine 1)
xvfb-run -a godot --path . --rendering-driver opengl3 -s tests/screenshot.gd -- /dossier  # captures d'écran
```

Les messages `mesh_get_surface_count` en mode sans écran sont normaux.
