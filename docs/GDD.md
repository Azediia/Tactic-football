# Football tactique — Document de design (v0.1)

Statut : décisions issues de la discussion de conception. Les points marqués **[À valider]** restent ouverts.

## 1. Concept

Jeu de football en 3D, vu de dessus, où le joueur ne pilote aucun joueur directement. Il donne des **ordres tactiques** (comme dans XCOM ou Door Kickers) pendant des pauses. L'action se déroule en temps réel. Les résultats sont déterminés par des **jets de d100** liés aux notes des joueurs, et par une **vraie physique du ballon**.

- Plateforme : PC. Moteur : Godot. Développement : Claude.
- Visuel : pas de modèles de joueurs. Chaque joueur est une **pastille** (cylindre avec hauteur, ~1,8 m) sur un terrain 3D, comme un tableau tactique.
- Premier mode : **5 contre 5**. Le 11 contre 11 reste incertain.
- Chaque camp commande ses joueurs ; l'adversaire est une IA ou un second humain.

## 2. Contrôle et temps

- Temps réel, avec **pause tactique** à tout moment.
- **Cooldown en secondes** entre deux pauses. Celui qui pause paie le cooldown ; l'adversaire donne ses ordres gratuitement pendant cette pause. Les ordres de l'adversaire sont **cachés**.
- Durée de la pause **illimitée** (option de minuteur plus tard).
- **Aucune limite** d'ordres par pause. Les ordres peuvent s'enchaîner sur plusieurs joueurs.
- Les ordres ont des **conditions de déclenchement** (immédiat, après N secondes, après la réussite de l'action d'un autre joueur, à la réception du ballon...), façon « go-codes » de Door Kickers.
- Si la **possession change de camp**, tous les ordres sont annulés et l'IA reprend avec la tactique de base.
- Si une étape échoue sans perte de balle, seuls les ordres qui en dépendaient sont annulés **[À valider en jeu]**.
- Sans ordre, l'IA alliée joue de façon autonome selon la tactique de l'équipe.

## 3. Déplacements

- Le joueur **dessine le chemin** de chaque pastille. Plus de « décrochage », « démarquage », « appel » : ce sont des tracés.
- **Allures** : marche, trot, sprint (avec ou sans ballon).
- **Inertie** : les joueurs ont une vitesse, une accélération et un angle de virage maximal qui dépend de la vitesse. Un virage infaisable est refusé par l'interface (les angles possibles sont affichés).
- **Arrêt net** : toujours possible. Avec le ballon, il demande un jet de Technique pour le garder, sinon le ballon continue.
- **Consignes défensives** (pas des tracés) : marquage d'un joueur, couverture de zone, pressing.
- Les défenseurs ont aussi inertie et temps de réaction (lié à la Vision).

## 4. Rayon de contrôle et conduite

- Chaque joueur a un **rayon de contrôle** (dépend de la Technique, de la vitesse et de la fatigue).
- Ballon **dans le rayon** : il est au pied, un adversaire ne peut le prendre que par un duel aux dés.
- Ballon **hors du rayon** : il est libre et physique. N'importe qui peut l'intercepter.
- Pendant la course, le joueur donne des **touches de balle** (environ une par seconde), avec un jet à chaque touche qui détermine la distance et la direction. Un sprint avec un joueur peu technique pousse le ballon loin.
- Le tracé s'affiche en **couleurs** (vert, orange, rouge) selon le risque de pousser trop loin.
- **Crochet** : seul geste de dribble. Le joueur choisit l'angle, limité par l'inertie. Virage plus serré que la course normale, avec perte de vitesse et fatigue. Un jet détermine si le ballon suit.

## 5. Jets de dés

- **d100**, notes des joueurs sur 100.
- Chance de réussite = stat − difficulté de l'action − fatigue − pression, bornée entre 1 et 99 %.
- Réussite si le jet ≤ chance. **Réussite critique** si jet ≤ chance / 10.
- Échec : plus le jet dépasse la chance, plus l'écart avec l'ordre est grand (direction, puissance, hauteur). **Échec critique** si l'écart dépasse 50 points.
- Les pourcentages sont affichés avant la validation de chaque action.
- Les actions les plus techniques ont un **seuil minimum de stat** : sinon elles sont grisées avec la mention du seuil.
- Jets déterministes avec graine pour pouvoir **rejouer** une action et en expliquer le résultat **[À prévoir]**.

## 6. Stats (sur 100)

- **Joueur de champ** : Vitesse, Endurance, Force, Agilité, Technique, Passe, Frappe, Défense, Jeu de tête, Vision, Sang-froid.
- **Gardien** : Réflexes, Placement, Prise de balle.

## 7. Catalogue d'actions

| Famille | Actions |
|---|---|
| Passe | courte, longue, transversale, en profondeur, en cloche, une touche, talonnade, passe aveugle |
| Réception | contrôle simple, contrôle orienté, amorti poitrine, contrôle de la tête, leurre |
| Tir | placé, puissant, enroulé, piqué, lob, volée, demi-volée, une touche, retourné |
| Dribble | crochet, protection de balle, une-deux |
| Défense | tacle debout, tacle glissé, interception, harcèlement, contre, dégagement |
| Aérien | duel, tête défensive, tête offensive, déviation |

**[À valider]** : la liste exacte à implémenter dans la première version.

- Un tir ou une passe se donnent avec : **cible/trajectoire, hauteur, puissance** (via un mini-jeu, désactivable, pour les tirs et passes longues), **effet** (voir §8).
- Le jet décide de l'écart entre l'ordre et l'exécution.

## 8. Balle et physique

- Balle physique : gravité, rebonds, frottements, résistance de l'air, **hauteur gérée en 3D** (tirs en lucarne, tirs trop hauts, lobs).
- **Effet (spin)** : le type d'effet se choisit dans un menu, l'amplitude de la courbe à la molette (plus on monte, plus la courbe est grande). L'amplitude maximale dépend de la note du joueur. Valable pour passes longues, frappes, centres, passes classiques.
- **Pastilles avec hauteur** : un lob passe au-dessus, une frappe rasante peut être contrée.
- **Contact balle-pastille** : rebond physique, avec un jet qui décide si le joueur contrôle le ballon. La **vitesse d'arrivée** du ballon modifie la difficulté.
- **Poteaux et barre** : collisions réelles. **Filets** : physique légère, décorative, crédible visuellement.
- Terrain : dimensions réglables (à définir pour le 5 contre 5).

## 9. Tacle

- Tacle sur le porteur ou sur le ballon libre.
- Tacle de rattrapage possible quand le défenseur est en retard (chance plus faible, risque de faute plus élevé). Échec critique : défenseur au sol un moment.
- Arbitrage (fautes, cartons, hors-jeu) : **repoussé à plus tard**.

## 10. Gardien

- Géré uniquement par l'IA.
- Si le tir arrive hors de la zone atteignable (selon son placement) : pas de jet, c'est but (ou poteau).
- Dans la zone : jet = stat du gardien − difficulté du tir (vitesse, distance entre le gardien et le point d'impact, lucarne ou pied de poteau).
- Résultats : capture ou repoussé (selon la Prise de balle), ballon qui lui échappe (échec léger), ballon qui passe à travers lui (échec critique, avec animation d'erreur simple).

## 11. Fatigue

- Une seule barre par joueur sur la durée du match.
- Réglable (faible, normale, élevée), comme dans FIFA. Durée du match et vitesse du jeu réglables.
- Diminue avec l'allure (le sprint coûte cher, la marche récupère légèrement). Réduit les stats effectives, plafonne la vitesse de sprint et réduit le rayon de contrôle.

## 12. Idées gardées pour plus tard

- Moral et pression, initiative des joueurs (désobéissance ou improvisation selon la Vision).
- Rejeu avec ralenti qui explique le jet.
- Multijoueur à planification simultanée.
- Mode carrière, 11 contre 11.
- Arbitrage complet.

## 13. Prototype 1 (proposition)

5 contre 5, un terrain, un match. Pause tactique avec cooldown, tracé de courses avec allures, passe et tir (trajectoire, hauteur, puissance, effet), conduite avec rayon de contrôle, crochet, tacle, gardien IA, jets de d100 avec pourcentages affichés, fatigue, IA d'équipe de base pour les joueurs sans ordre.
