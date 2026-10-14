class_name Rules
extends RefCounted
## Règles du jeu : dimensions, chances de réussite (en %) et calculs de trajectoires.
## Tout est statique : aucune dépendance à la scène, donc facile à tester.

const GRAVITY := 9.81
const HALF_LENGTH := 30.0
const HALF_WIDTH := 20.0
const GOAL_HALF_WIDTH := 3.0
const GOAL_HEIGHT := 2.44
const GOAL_DEPTH := 2.2
## Hauteur visée dans le but pour chaque niveau : au ras du sol, mi-hauteur, lucarne.
const SHOT_HEIGHTS := [0.35, 1.1, 2.0]
const SHOT_HEIGHT_NAMES := ["Ras du sol", "Mi-hauteur", "Lucarne"]


## Sens d'attaque d'une équipe sur l'axe x : +1 (but à droite) ou -1 (but à gauche).
static func attack_dir(team: int) -> float:
	return 1.0 if team == 0 else -1.0


static func goal_x(team: int) -> float:
	return attack_dir(team) * HALF_LENGTH


# --- Chances de réussite -------------------------------------------------------------------

static func pass_chance(passer: Player, distance: float, aerial: bool, pressure: float, curve: float) -> float:
	return passer.effective_stat("passe") + 20.0 - distance * 0.9 - (6.0 if aerial else 0.0) - pressure - absf(curve) * 4.0


static func shot_chance(shooter: Player, distance: float, height_level: int, power: float, pressure: float, curve: float) -> float:
	var height_penalty: float = [0.0, 5.0, 18.0][height_level]
	return shooter.effective_stat("frappe") + 15.0 - distance * 0.7 - height_penalty - power * 10.0 - pressure - absf(curve) * 4.0


static func control_chance(player: Player, ball_speed: float, ball_height: float) -> float:
	var skill := player.effective_stat("prise") if player.is_keeper else player.effective_stat("technique")
	return skill + 25.0 - ball_speed * 2.5 - (15.0 if ball_height > 0.6 else 0.0)


static func touch_chance(player: Player, speed: float) -> float:
	return player.effective_stat("technique") + 45.0 - speed * 4.0


static func tackle_chance(tackler: Player, carrier: Player) -> float:
	var carrier_skill := (carrier.effective_stat("technique") + carrier.effective_stat("force")) / 2.0
	return 45.0 + (tackler.effective_stat("defense") - carrier_skill) * 0.6


static func keeper_chance(keeper: Player, ball_speed: float, lateral_ratio: float, ball_y: float) -> float:
	var skill := keeper.effective_stat("reflexes") * 0.6 + keeper.effective_stat("placement") * 0.4
	var awkward := 10.0 if (ball_y > 1.7 or ball_y < 0.25) else 0.0
	return skill + 32.0 - ball_speed * 1.0 - lateral_ratio * 25.0 - awkward


static func keeper_catch_chance(keeper: Player, ball_speed: float) -> float:
	return keeper.effective_stat("prise") + 30.0 - ball_speed * 1.5


## Distance de portée latérale d'un plongeon, selon le temps disponible et les réflexes.
static func keeper_reach(keeper: Player, time_available: float) -> float:
	return 1.8 + 5.0 * minf(time_available, 0.6) * keeper.effective_stat("reflexes") / 100.0


## Pression subie : dépend de l'adversaire le plus proche.
static func pressure_at(pos: Vector3, team: int, players: Array) -> float:
	var nearest := 99.0
	for other in players:
		if other.team == team or other.stun_time > 0.0:
			continue
		nearest = minf(nearest, Vector2(other.position.x - pos.x, other.position.z - pos.z).length())
	if nearest < 1.5:
		return 14.0
	if nearest < 3.0:
		return 8.0
	if nearest < 5.0:
		return 3.0
	return 0.0


## Vrai si un adversaire de `team` se trouve à moins de `radius` du segment a-b.
static func lane_blocked(a: Vector3, b: Vector3, team: int, players: Array, radius: float) -> bool:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var length_sq := ab.length_squared()
	if length_sq < 0.01:
		return false
	for other in players:
		if other.team == team:
			continue
		var ap := Vector2(other.position.x - a.x, other.position.z - a.z)
		var t := clampf(ap.dot(ab) / length_sq, 0.0, 1.0)
		if (ap - ab * t).length() < radius:
			return true
	return false


## Amplitude maximale de l'effet (0 à 1) : dépend de la technique du joueur.
static func max_curve(player: Player) -> float:
	return clampf(player.effective_stat("technique") / 100.0, 0.0, 1.0)


# --- Trajectoires --------------------------------------------------------------------------

static func horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


## Passe au sol : vitesse choisie pour arriver avec une vitesse raisonnable malgré le frottement.
static func flat_pass_velocity(from: Vector3, to: Vector3, power_mult: float) -> Vector3:
	var delta := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var speed := clampf((6.0 + delta.length() * 0.55) * power_mult, 5.0, 30.0)
	return delta.normalized() * speed


## Passe aérienne (cloche) qui retombe sur la cible.
static func lob_velocity(from: Vector3, to: Vector3, power_mult: float) -> Vector3:
	var delta := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var theta := deg_to_rad(38.0)
	var speed := sqrt(maxf(delta.length(), 2.0) * GRAVITY / sin(2.0 * theta)) * power_mult
	return delta.normalized() * speed * cos(theta) + Vector3.UP * speed * sin(theta)


## Tir : vitesse donnée, on résout l'angle pour passer par `target` (trajectoire tendue).
static func shot_velocity(from: Vector3, target: Vector3, speed: float) -> Vector3:
	var delta := Vector3(target.x - from.x, 0.0, target.z - from.z)
	var d := maxf(delta.length(), 0.5)
	var a := GRAVITY * d * d / (2.0 * speed * speed)
	var y_rel := target.y - from.y
	var disc := d * d - 4.0 * a * (a + y_rel)
	var u := tan(deg_to_rad(40.0))
	if disc >= 0.0:
		u = (d - sqrt(disc)) / (2.0 * a)
	var angle := atan(u)
	return delta.normalized() * speed * cos(angle) + Vector3.UP * speed * sin(angle)


## Angle (radians) dont il faut viser à l'opposé de l'effet pour retomber près de la cible.
static func curve_compensation(curve: float, distance: float, speed: float) -> float:
	if absf(curve) < 0.01 or speed < 1.0:
		return 0.0
	var flight_time := distance / speed
	return atan2(0.175 * curve * distance * flight_time, distance)


## Applique l'erreur d'exécution décidée par le jet de dés.
static func apply_error(velocity: Vector3, result: Dictionary) -> Vector3:
	var margin: float = result["margin"]
	var angle_deg := 0.0
	var power_factor := 1.0
	var lift := 0.0
	var side := 1.0 if Dice.rng.randf() < 0.5 else -1.0
	match result["tier"]:
		"success":
			angle_deg = Dice.rng.randf_range(-1.0, 1.0)
		"fail":
			angle_deg = side * margin * 0.35
			power_factor = 1.0 + Dice.rng.randf_range(-0.15, 0.15) * (margin / 50.0)
			lift = Dice.rng.randf_range(-1.0, 2.5) * (margin / 50.0)
		"crit_fail":
			angle_deg = side * Dice.rng.randf_range(35.0, 80.0)
			power_factor = Dice.rng.randf_range(0.35, 1.4)
			lift = Dice.rng.randf_range(0.0, 5.0)
	var rotated := velocity.rotated(Vector3.UP, deg_to_rad(angle_deg)) * power_factor
	rotated.y = velocity.y * power_factor + lift
	return rotated


## Prédit où et quand le ballon traverse le plan x = plane_x (trajectoire balistique).
static func predict_plane_crossing(pos: Vector3, vel: Vector3, plane_x: float) -> Dictionary:
	if absf(vel.x) < 0.1:
		return {"ok": false}
	var t := (plane_x - pos.x) / vel.x
	if t <= 0.0:
		return {"ok": false}
	var y := pos.y + vel.y * t - 0.5 * GRAVITY * t * t
	return {"ok": true, "time": t, "y": maxf(y, 0.11), "z": pos.z + vel.z * t}
