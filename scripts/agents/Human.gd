class_name Human
extends RefCounted
## Human — إنسانٌ كامل الجسد والعقل، لكن بلا أيّ معرفة أو تعليمات.
## يملك فقط: جسداً يشعر (جوع، عطش، ألم، برد، تعب، خوف، شوق)، وحواسّاً، ويدين،
## وذاكرةً ترابطية فارغة، وفضولاً. كل ما يفعله بعد ذلك يتعلّمه من العالم وحده.

const SEC_HOUR := 3600.0
const SEC_DAY := 86400.0
const SEC_YEAR := 86400.0 * 365.25

enum Sex { MALE, FEMALE }
enum Act { IDLE, WANDER, MOVE, PICK, MOUTH, DRINK, STRIKE, RUB, DROP, SLEEP, VOCALIZE, GIVE, FOLLOW, FLEE, MATE, PLACE_FIRE, DIG, PILE, MARK, CARRY_CHILD, GRIEVE, HUNT }
const ACT_AR := {
	Act.IDLE: "يقف", Act.WANDER: "يتجوّل", Act.MOVE: "يتحرّك", Act.PICK: "يلتقط", Act.MOUTH: "يضع في فمه",
	Act.DRINK: "يشرب", Act.STRIKE: "يضرب", Act.RUB: "يفرك", Act.DROP: "يترك", Act.SLEEP: "ينام",
	Act.VOCALIZE: "يُصدر صوتاً", Act.GIVE: "يُعطي", Act.FOLLOW: "يتبع", Act.FLEE: "يهرب", Act.MATE: "يقترب من رفيقه",
	Act.PLACE_FIRE: "يضع شيئاً قرب النار", Act.DIG: "يحفر", Act.PILE: "يُكوّم", Act.MARK: "يخطّ على الصخر",
	Act.CARRY_CHILD: "يحمل صغيره", Act.GRIEVE: "يحزن", Act.HUNT: "يطارد",
}
## الدوافع الداخلية (حالات جسدية، ليست معرفة)
enum D { HUNGER, THIRST, FATIGUE, COLD, HEAT, PAIN, FEAR, LONELY, CURIOUS, LIBIDO, PARENT }
const D_AR := {
	D.HUNGER: "الجوع", D.THIRST: "العطش", D.FATIGUE: "التعب", D.COLD: "البرد", D.HEAT: "الحرّ",
	D.PAIN: "الألم", D.FEAR: "الخوف", D.LONELY: "الوحدة", D.CURIOUS: "الفضول", D.LIBIDO: "الشوق", D.PARENT: "حنان الأبوّة",
}
## أهداف الفعل: أنواع الأشياء في العالم
enum Tg { NONE, GROUND_ITEM, TREE, FRUIT_TREE, BUSH, POISON_BUSH, WATER, STONE_SRC, STICK_SRC, CLAY_SRC, FIBER_SRC, ROOT_SRC, GRAIN_SRC, HUMAN, ANIMAL, FIRE, HELD, PILE, ROCK_FACE }

# ---------- الهوية والجسد ----------
var id: int
var sex: int
var born_at: float        # ثانية العالم
var pos: Vector2          # إحداثيات بلاطات (عشرية)
var alive := true
var death_cause := ""
var died_at := -1.0
var mother_id := -1
var father_id := -1
var name_word := ""       # لا اسم في البداية

# جينات (0..1)
var g_curiosity: float
var g_aggression: float
var g_sociability: float
var g_strength: float
var g_endurance: float
var g_size: float
var g_skin: float
var g_hair: float
var g_lifespan: float     # سنوات

# حالة الجسد (0..1)
var health := 1.0
var hunger := 0.85        # 1 = ممتلئ
var thirst := 0.85        # 1 = مرتوٍ
var energy := 0.9         # 1 = مستريح
var body_temp := 37.0
var sick := 0.0
var poison := 0.0
var injury := 0.0
var pregnant_since := -1.0
var pregnant_by := -1
var last_birth_at := -999999.0
var last_meal_item := -1
var last_meal_at := -1.0

# ---------- اليدان ----------
var hand_l: int = Items.T.NONE
var hand_r: int = Items.T.NONE
var carrying_child := -1
var carried_by := -1

# ---------- العقل ----------
var drives := PackedFloat32Array()
var memory: Dictionary = {}          # key(action|target|context) -> [sum_reward, n]
var places: Dictionary = {}          # "water"/"fruit"/... -> Vector2 آخر مكان جيد
var danger_places: Array = []        # [Vector2]
var vocab: Dictionary = {}           # concept(int as string) -> word
var heard: Dictionary = {}           # word -> {concept -> count}
var affinity: Dictionary = {}        # other id (string) -> -1..1
var grief := 0.0
var fear_of_animals := 0.15          # فطري وضعيف؛ ينمو بالتجربة
var known_fire := false
var heat_accum := 0.0                # حرارة الفرك المتراكمة
var home := Vector2.INF              # مكان يعود إليه (يتكوّن من العادة)
var home_score := 0.0

# الحالة الحالية
var act: int = Act.IDLE
var act_target: int = Tg.NONE
var act_target_id := -1
var act_target_pos := Vector2.ZERO
var act_time := 0.0
var act_progress := 0.0
var act_key := ""
var think_timer := 0.0
var thought := ""                    # ما يظهر في "نافذة العقل" للمُشاهد
var needs_before := PackedFloat32Array()
var speech := ""
var speech_timer := 0.0
var wake_hour := 6.0
var stagger := 0.0
var explore_target := Vector2.ZERO
var facing := 1.0
var anim_t := 0.0
var last_pos := Vector2.ZERO
var moving := false

func _init() -> void:
	drives.resize(D.size())
	drives.fill(0.0)
	needs_before.resize(D.size())

# ================= إنشاء =================
static func create(new_id: int, p: Vector2, age_years_v: float, s: int, world_now: float) -> Human:
	var h := Human.new()
	h.id = new_id
	h.pos = p
	h.last_pos = p
	h.sex = s
	h.born_at = world_now - age_years_v * SEC_YEAR
	h.g_curiosity = clampf(Rng.randfn(0.55, 0.18), 0.05, 1.0)
	h.g_aggression = clampf(Rng.randfn(0.3, 0.18), 0.0, 1.0)
	h.g_sociability = clampf(Rng.randfn(0.55, 0.2), 0.05, 1.0)
	h.g_strength = clampf(Rng.randfn(0.5, 0.15), 0.1, 1.0)
	h.g_endurance = clampf(Rng.randfn(0.5, 0.15), 0.1, 1.0)
	h.g_size = clampf(Rng.randfn(0.5, 0.15), 0.1, 1.0)
	h.g_skin = Rng.randf()
	h.g_hair = Rng.randf()
	h.g_lifespan = clampf(Rng.randfn(72.0, 9.0), 38.0, 96.0)
	h.wake_hour = clampf(Rng.randfn(6.0, 0.8), 4.0, 8.5)
	h.stagger = Rng.randf()
	h.explore_target = p
	h.hunger = Rng.randf_range(0.55, 0.9)
	h.thirst = Rng.randf_range(0.5, 0.9)
	return h

static func child_of(new_id: int, mom: Human, dad: Human, world_now: float) -> Human:
	var c := create(new_id, mom.pos, 0.0, Sex.MALE if Rng.chance(0.51) else Sex.FEMALE, world_now)
	c.mother_id = mom.id
	c.father_id = dad.id if dad != null else -1
	var d := dad if dad != null else mom
	c.g_curiosity = _mix(mom.g_curiosity, d.g_curiosity, 0.06)
	c.g_aggression = _mix(mom.g_aggression, d.g_aggression, 0.06)
	c.g_sociability = _mix(mom.g_sociability, d.g_sociability, 0.06)
	c.g_strength = _mix(mom.g_strength, d.g_strength, 0.05)
	c.g_endurance = _mix(mom.g_endurance, d.g_endurance, 0.05)
	c.g_size = _mix(mom.g_size, d.g_size, 0.05)
	c.g_skin = _mix(mom.g_skin, d.g_skin, 0.03)
	c.g_hair = _mix(mom.g_hair, d.g_hair, 0.03)
	c.g_lifespan = clampf(lerpf(mom.g_lifespan, d.g_lifespan, Rng.randf()) + Rng.randfn(0.0, 4.0), 30.0, 98.0)
	c.hunger = 0.7
	c.thirst = 0.7
	c.energy = 0.6
	c.health = 0.85
	c.fear_of_animals = 0.2
	return c

static func _mix(a: float, b: float, dev: float) -> float:
	return clampf(lerpf(a, b, Rng.randf()) + Rng.randfn(0.0, dev), 0.0, 1.0)

# ================= استعلامات =================
func age_seconds(now: float) -> float:
	return now - born_at

func age_years(now: float) -> float:
	return age_seconds(now) / SEC_YEAR

func is_infant(now: float) -> bool:
	return age_years(now) < 2.0

func is_child(now: float) -> bool:
	return age_years(now) < 13.0

func is_adult(now: float) -> bool:
	return age_years(now) >= 15.0

func is_elder(now: float) -> bool:
	return age_years(now) > g_lifespan * 0.8

func speed_factor(now: float) -> float:
	var a := age_years(now)
	var f := 1.0
	if a < 1.0: f = 0.0
	elif a < 4.0: f = 0.35
	elif a < 12.0: f = 0.7
	elif a > g_lifespan * 0.85: f = 0.55
	f *= lerpf(0.75, 1.15, g_endurance)
	f *= clampf(health, 0.2, 1.0)
	f *= 1.0 - injury * 0.5
	if carrying_child >= 0: f *= 0.8
	return f

func body_scale(now: float) -> float:
	var a := age_years(now)
	var grow := clampf(a / 16.0, 0.25, 1.0)
	return grow * lerpf(0.88, 1.12, g_size)

func tile() -> Vector2i:
	return Vector2i(int(floor(pos.x)), int(floor(pos.y)))

func has_free_hand() -> bool:
	return hand_l == Items.T.NONE or hand_r == Items.T.NONE

func take(item: int) -> bool:
	if hand_r == Items.T.NONE:
		hand_r = item; return true
	if hand_l == Items.T.NONE:
		hand_l = item; return true
	return false

func held_any() -> int:
	return hand_r if hand_r != Items.T.NONE else hand_l

func holds(item: int) -> bool:
	return hand_r == item or hand_l == item

func other_hand_item(item: int) -> int:
	if hand_r == item:
		return hand_l
	return hand_r

func best_weapon() -> int:
	return hand_r if Items.strike_power(hand_r) >= Items.strike_power(hand_l) else hand_l

func remove_item(item: int) -> bool:
	if hand_r == item:
		hand_r = Items.T.NONE; return true
	if hand_l == item:
		hand_l = Items.T.NONE; return true
	return false

func dominant_drive() -> int:
	var best := 0
	for i in drives.size():
		if drives[i] > drives[best]:
			best = i
	return best

func label_ar() -> String:
	if name_word != "":
		return name_word
	return "بشريّ %d" % id

func stage_ar(now: float) -> String:
	var a := age_years(now)
	if sex == Sex.FEMALE:
		return "رضيعة" if a < 2 else ("طفلة" if a < 13 else ("شابّة" if a < 30 else ("ناضجة" if a < 55 else "عجوز")))
	return "رضيع" if a < 2 else ("طفل" if a < 13 else ("شابّ" if a < 30 else ("ناضج" if a < 55 else "شيخ")))

func description_ar(now: float) -> String:
	return "%s • %s" % [stage_ar(now), "ذكر" if sex == Sex.MALE else "أنثى"]

func aff(other_id: int) -> float:
	return affinity.get(str(other_id), 0.0)

func add_aff(other_id: int, delta: float) -> void:
	var k := str(other_id)
	affinity[k] = clampf(affinity.get(k, 0.0) + delta, -1.0, 1.0)

# ================= الذاكرة الترابطية =================
## قيمة متوقّعة لفعل معيّن في سياق معيّن (تعلّم بالتجربة فقط)
func expect(key: String) -> float:
	var m = memory.get(key)
	if m == null:
		return 0.0
	return m[0] / maxf(1.0, m[1])

func tries(key: String) -> int:
	var m = memory.get(key)
	return 0 if m == null else int(m[1])

func learn(key: String, reward: float) -> void:
	var m = memory.get(key)
	if m == null:
		memory[key] = [reward, 1.0]
	else:
		# تعلّم بنافذة منزلقة: التجارب الجديدة تُرجّح قليلاً
		var n: float = minf(m[1] + 1.0, 25.0)
		memory[key] = [m[0] * (n - 1.0) / maxf(1.0, m[1]) + reward, n]

func copy_learning_from(other: Human, strength: float) -> void:
	## يتعلّم بالمشاهدة: يقتبس جزءاً من توقّعات الآخر (بدون أن يفهم)
	for k in other.memory:
		var m: Array = other.memory[k]
		var v: float = m[0] / maxf(1.0, m[1])
		if absf(v) < 0.15:
			continue
		var mine = memory.get(k)
		if mine == null:
			memory[k] = [v * strength, 1.0]
		elif mine[1] < 4.0:
			memory[k] = [mine[0] + v * strength, mine[1] + 0.5]

# ================= الحفظ =================
func to_save() -> Dictionary:
	return {
		"id": id, "sex": sex, "born": born_at, "x": pos.x, "y": pos.y, "alive": alive, "dc": death_cause, "da": died_at,
		"mom": mother_id, "dad": father_id, "name": name_word,
		"g": [g_curiosity, g_aggression, g_sociability, g_strength, g_endurance, g_size, g_skin, g_hair, g_lifespan],
		"hp": health, "hu": hunger, "th": thirst, "en": energy, "bt": body_temp, "sk": sick, "po": poison, "inj": injury,
		"preg": pregnant_since, "pby": pregnant_by, "lb": last_birth_at, "lmi": last_meal_item, "lma": last_meal_at,
		"hl": hand_l, "hr": hand_r, "cc": carrying_child, "cb": carried_by,
		"mem": memory, "places": _places_save(), "danger": _vec_arr_save(danger_places),
		"vocab": vocab, "heard": heard, "aff": affinity, "grief": grief, "foa": fear_of_animals, "kf": known_fire,
		"wake": wake_hour, "stag": stagger, "home": [home.x, home.y] if home != Vector2.INF else null, "hs": home_score,
	}

func _places_save() -> Dictionary:
	var out := {}
	for k in places:
		out[k] = [places[k].x, places[k].y]
	return out

func _vec_arr_save(arr: Array) -> Array:
	var out := []
	for v in arr:
		out.append([v.x, v.y])
	return out

static func from_save(d: Dictionary) -> Human:
	var h := Human.new()
	h.id = int(d.id); h.sex = int(d.sex); h.born_at = d.born; h.pos = Vector2(d.x, d.y); h.alive = d.alive
	h.death_cause = d.get("dc", ""); h.died_at = d.get("da", -1.0)
	h.mother_id = int(d.mom); h.father_id = int(d.dad); h.name_word = d.get("name", "")
	var g: Array = d.g
	h.g_curiosity = g[0]; h.g_aggression = g[1]; h.g_sociability = g[2]; h.g_strength = g[3]; h.g_endurance = g[4]
	h.g_size = g[5]; h.g_skin = g[6]; h.g_hair = g[7]; h.g_lifespan = g[8]
	h.health = d.hp; h.hunger = d.hu; h.thirst = d.th; h.energy = d.en; h.body_temp = d.bt; h.sick = d.sk; h.poison = d.po; h.injury = d.inj
	h.pregnant_since = d.preg; h.pregnant_by = int(d.pby); h.last_birth_at = d.lb; h.last_meal_item = int(d.lmi); h.last_meal_at = d.lma
	h.hand_l = int(d.hl); h.hand_r = int(d.hr); h.carrying_child = int(d.cc); h.carried_by = int(d.cb)
	h.memory = d.get("mem", {})
	for k in d.get("places", {}):
		var v: Array = d.places[k]
		h.places[k] = Vector2(v[0], v[1])
	for v in d.get("danger", []):
		h.danger_places.append(Vector2(v[0], v[1]))
	h.vocab = d.get("vocab", {}); h.heard = d.get("heard", {})
	h.affinity = d.get("aff", {}); h.grief = d.get("grief", 0.0); h.fear_of_animals = d.get("foa", 0.15); h.known_fire = d.get("kf", false)
	h.wake_hour = d.get("wake", 6.0); h.stagger = d.get("stag", 0.0)
	var hm = d.get("home")
	if hm != null:
		h.home = Vector2(hm[0], hm[1])
	h.home_score = d.get("hs", 0.0)
	h.explore_target = h.pos
	h.last_pos = h.pos
	return h
