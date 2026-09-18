class_name Animal
extends RefCounted
## Animal — حيوانات العالم. لا تعرف البشر ولا يعرفها البشر. تتصرّف بغرائزها.

enum K { RABBIT, DEER, BOAR, WOLF, BIRD, FISH, GOAT }
const K_AR := {K.RABBIT: "أرنب", K.DEER: "غزال", K.BOAR: "خنزير برّي", K.WOLF: "ذئب", K.BIRD: "طائر", K.FISH: "سمكة", K.GOAT: "وعل"}
## [الحجم, السرعة, الشراسة, الصحة, اللحم, هل مفترس]
const STATS := {
	K.RABBIT: [0.25, 1.6, 0.0, 0.3, 1, false],
	K.DEER: [0.7, 1.7, 0.05, 1.0, 3, false],
	K.BOAR: [0.65, 1.1, 0.55, 1.4, 3, false],
	K.WOLF: [0.6, 1.8, 0.85, 1.1, 2, true],
	K.BIRD: [0.15, 2.2, 0.0, 0.15, 1, false],
	K.FISH: [0.2, 0.9, 0.0, 0.2, 1, false],
	K.GOAT: [0.55, 1.3, 0.2, 0.9, 2, false],
}
const COLOR := {
	K.RABBIT: Color(0.8, 0.75, 0.68), K.DEER: Color(0.7, 0.5, 0.3), K.BOAR: Color(0.35, 0.28, 0.22),
	K.WOLF: Color(0.5, 0.5, 0.55), K.BIRD: Color(0.3, 0.35, 0.5), K.FISH: Color(0.5, 0.65, 0.8), K.GOAT: Color(0.85, 0.82, 0.75),
}

var id: int
var kind: int
var pos: Vector2
var health: float
var alive := true
var hunger := 0.8
var fear := 0.0
var target := Vector2.ZERO
var wander_t := 0.0
var attack_cd := 0.0
var facing := 1.0
var anim_t := 0.0
var sex := 0
var born_at := 0.0
var last_birth := -1e9
var flee_from := Vector2.INF
var corpse_timer := 0.0
var meat_left := 0
var hunt_target := -1

static func create(new_id: int, k: int, p: Vector2, now: float) -> Animal:
	var a := Animal.new()
	a.id = new_id
	a.kind = k
	a.pos = p
	a.target = p
	a.health = STATS[k][3]
	a.sex = 0 if Rng.chance(0.5) else 1
	a.born_at = now - Rng.randf_range(0.0, 3.0) * 86400.0 * 365.0
	a.meat_left = STATS[k][4]
	return a

func speed() -> float:
	return STATS[kind][1]

func is_predator() -> bool:
	return STATS[kind][5]

func size() -> float:
	return STATS[kind][0]

func ferocity() -> float:
	return STATS[kind][2]

func name_ar() -> String:
	return K_AR[kind]

func to_save() -> Dictionary:
	return {"id": id, "k": kind, "x": pos.x, "y": pos.y, "hp": health, "al": alive, "hu": hunger, "b": born_at, "ml": meat_left, "ct": corpse_timer, "s": sex}

static func from_save(d: Dictionary) -> Animal:
	var a := Animal.new()
	a.id = int(d.id); a.kind = int(d.k); a.pos = Vector2(d.x, d.y); a.target = a.pos
	a.health = d.hp; a.alive = d.al; a.hunger = d.hu; a.born_at = d.b; a.meat_left = int(d.ml); a.corpse_timer = d.ct; a.sex = int(d.get("s", 0))
	return a
