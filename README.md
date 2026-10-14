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

- **Espace** : frapper le ballon
- **R** : remettre le ballon au centre

## Test automatique

```
godot --headless --path . -s tests/smoke_test.gd
```

Les messages `mesh_get_surface_count` en mode sans écran sont normaux.
