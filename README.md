# Tactic Football

Jeu de football tactique en 3D (Godot 4.3). On ne pilote pas les joueurs : on donne des ordres pendant des pauses, et les résultats sont décidés par des jets de d100 et une vraie physique du ballon.

Toutes les règles de conception sont dans [`docs/GDD.md`](docs/GDD.md).

## Lancer le jeu

1. Installer [Godot 4.3](https://godotengine.org/download) (version standard, pas .NET).
2. Cloner ce dépôt : `git clone https://github.com/Azediia/Tactic-football`
3. Ouvrir Godot, cliquer sur **Importer**, choisir le fichier `project.godot` de ce dossier.
4. Appuyer sur **F5** (ou le bouton ▶) pour lancer.

Pour récupérer la dernière version : `git pull`, puis relancer dans Godot.

## Contrôles actuels (prototype)

- **Espace** : pause tactique / reprise. Après une pause, un cooldown de 15 s de jeu empêche d'en refaire une tout de suite.
- **Clic gauche** sur un joueur bleu : le sélectionner (anneau jaune).
- **Clic gauche** sur le terrain, en pause : ajouter un point de passage au joueur sélectionné. Les points s'enchaînent.
- **1 / 2 / 3** : allure des prochains points (marche, trot, sprint). La couleur du tracé indique l'allure.
- **Clic droit**, en pause : effacer les ordres du joueur sélectionné.
- **K** : frappe test du ballon. **R** : ballon au centre.

L'équipe rouge est immobile pour l'instant (pas encore d'IA).

## Test automatique

```
godot --headless --path . -s tests/smoke_test.gd
```

Les messages `mesh_get_surface_count` en mode sans écran sont normaux.
