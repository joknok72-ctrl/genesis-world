class_name Brain
## Brain — عقل الإنسان. لا يعرف ما "الطعام" ولا "الأداة" ولا "النار".
## يعرف فقط: ما يشعر به الآن، ما تراه عيناه، ما تمسكه يداه، وما تذكّره من نتائج أفعاله السابقة.
## القاعدة الوحيدة: افعل ما تتوقّع أنه سيُخفّف ما تشعر به، أو ما لم تجرّبه قطّ (فضول).

const WALK_SPEED := 0.72          # بلاطة/ثانية (≈1.4 م/ث)
const RUN_MULT := 1.9
const REACH := 0.9

# ======================= الدوافع =======================
static func update_drives(w: World, h: Human, now: float) -> void:
	var d := h.drives
	d[Human.D.HUNGER] = clampf((0.72 - h.hunger) / 0.72, 0.0, 1.0)
	d[Human.D.THIRST] = clampf((0.7 - h.thirst) / 0.7, 0.0, 1.0)
	var night := WorldClock.is_night()
	d[Human.D.FATIGUE] = clampf((0.45 - h.energy) / 0.45 + (0.35 if night and h.energy < 0.8 else 0.0), 0.0, 1.0)
	d[Human.D.COLD] = clampf((36.2 - h.body_temp) / 2.0, 0.0, 1.0)
	d[Human.D.HEAT] = clampf((h.body_temp - 38.0) / 2.0, 0.0, 1.0)
	d[Human.D.PAIN] = maxf(d[Human.D.PAIN] * 0.995, clampf(h.injury * 0.8 + h.poison * 0.5 + h.sick * 0.4, 0.0, 1.0))
	d[Human.D.FEAR] = maxf(0.0, d[Human.D.FEAR] - 0.0015)
	# الوحدة: تنمو مع البعد عن الآخرين، تتأثر بالجينات
	var near := 0
	for o in w.humans:
		if o.alive and o != h and o.pos.distance_to(h.pos) < 4.0:
			near += 1
	var lonely_target := (0.0 if near > 0 else 0.6) * h.g_sociability + h.grief * 0.5
	d[Human.D.LONELY] = lerpf(d[Human.D.LONELY], lonely_target, 0.02)
	d[Human.D.CURIOUS] = h.g_curiosity * (1.0 - maxf(d[Human.D.HUNGER], maxf(d[Human.D.THIRST], d[Human.D.FEAR])) * 0.8) * (0.4 if night else 1.0)
	var adult := h.is_adult(now)
	var lib := 0.0
	if adult and not h.is_elder(now) and h.hunger > 0.35 and h.thirst > 0.35 and h.health > 0.5:
		var since := now - h.last_birth_at
		if h.pregnant_since < 0.0 and since > 86400.0 * 400.0:
			lib = clampf(0.25 + 0.5 * (1.0 - h.g_aggression * 0.3), 0.0, 1.0) * 0.8
	d[Human.D.LIBIDO] = lerpf(d[Human.D.LIBIDO], lib, 0.01)
	var parent := 0.0
	for o in w.humans:
		if o.alive and (o.mother_id == h.id or o.father_id == h.id) and o.is_child(now):
			parent = maxf(parent, 0.35 + (0.45 if o.hunger < 0.4 or o.pos.distance_to(h.pos) > 3.0 else 0.0))
	d[Human.D.PARENT] = parent

# ======================= الخطوة =======================
static func step(w: World, h: Human, dt: float, now: float, coarse: bool) -> void:
	h.anim_t += dt
	h.moving = false
	if h.speech_timer > 0.0:
		h.speech_timer -= dt
		if h.speech_timer <= 0.0:
			h.speech = ""
	update_drives(w, h, now)
	# الرضيع محمولٌ أو ملقى — لا يقرّر
	if h.age_years(now) < 1.0:
		if h.carried_by >= 0:
			var p := w.human_by_id(h.carried_by)
			if p != null and p.alive:
				h.pos = p.pos + Vector2(0.15, -0.1)
		h.thought = "يرضع وينام" if h.hunger > 0.3 else "يبكي جوعاً"
		if h.hunger < 0.35 or h.thirst < 0.35:
			h.speech = "…واء"
			h.speech_timer = 2.0
		return
	# طفل محمول
	if h.carried_by >= 0:
		var p2 := w.human_by_id(h.carried_by)
		if p2 != null and p2.alive and p2.carrying_child == h.id:
			h.pos = p2.pos + Vector2(0.15, -0.1)
			if h.age_years(now) > 3.5 or Rng.chance(dt / 900.0):
				p2.carrying_child = -1
				h.carried_by = -1
			return
		h.carried_by = -1
	# ردّ فعل الخوف يقطع أي شيء
	if h.drives[Human.D.FEAR] > 0.75 and h.act != Human.Act.FLEE and h.act != Human.Act.STRIKE:
		_start_flee(w, h, now)
	if h.act == Human.Act.IDLE:
		h.think_timer -= dt
		if h.think_timer <= 0.0:
			_decide(w, h, now)
	if h.act != Human.Act.IDLE:
		_perform(w, h, dt, now, coarse)

# ======================= الإدراك =======================
static func _perceive(w: World, h: Human, now: float) -> Dictionary:
	var t := w.terrain
	var c := h.tile()
	var r := int(World.PERCEPTION)
	var p := {
		"water": Vector2i(-1, -1), "fruit": [], "bush": [], "pbush": [], "stone": [], "stick": [], "tree": [],
		"clay": [], "fiber": [], "root": [], "grain": [], "ground": [], "fire": {}, "humans": [], "animals": [],
		"corpses": [], "rock": [], "pile": [],
	}
	var best_w := 999
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := c.x + dx
			var y := c.y + dy
			if not t.in_bounds(x, y):
				continue
			var i := t.idx(x, y)
			var dd := dx * dx + dy * dy
			if dd > r * r:
				continue
			var b := t.biome[i]
			if b == Terrain.B.WATER and dd < best_w:
				best_w = dd
				p.water = Vector2i(x, y)
			if t.burnt[i] > 0:
				continue
			if t.fruit_trees[i] > 0 and t.fruit[i] > 0: p.fruit.append(i)
			if t.bushes[i] > 0 and t.berries[i] > 0: p.bush.append(i)
			if t.poison_bushes[i] > 0 and t.poison_berries[i] > 0: p.pbush.append(i)
			if t.stones[i] > 0: p.stone.append(i)
			if t.sticks[i] > 0: p.stick.append(i)
			if t.trees[i] > 0 or t.fruit_trees[i] > 0: p.tree.append(i)
			if t.clay[i] > 0: p.clay.append(i)
			if t.fiber[i] > 0: p.fiber.append(i)
			if t.roots[i] > 0: p.root.append(i)
			if t.grain[i] > 0: p.grain.append(i)
			if w.ground.has(i): p.ground.append(i)
			if (b == Terrain.B.HILLS or b == Terrain.B.MOUNTAIN) and t.stones[i] > 1: p.rock.append(i)
			if w.shelter[i] > 0: p.pile.append(i)
	p.fire = w.nearest_fire(h.pos, World.PERCEPTION)
	for o in w.humans:
		if o.alive and o != h and o.pos.distance_to(h.pos) < World.PERCEPTION:
			p.humans.append(o)
	for a in w.animals:
		if a.pos.distance_to(h.pos) < World.PERCEPTION:
			p.animals.append(a)
	for cp in w.corpses:
		var cpos := Vector2((cp.i % Terrain.W) + 0.5, (cp.i / Terrain.W) + 0.5)
		if cpos.distance_to(h.pos) < World.PERCEPTION:
			p.corpses.append(cp)
	return p

static func _tile_pos(i: int) -> Vector2:
	return Vector2((i % Terrain.W) + 0.5, (i / Terrain.W) + 0.5)

static func _nearest_idx(h: Human, arr: Array) -> int:
	var best := -1
	var bd := 1e9
	for i in arr:
		var d: float = h.pos.distance_squared_to(_tile_pos(i))
		if d < bd:
			bd = d
			best = i
	return best

# ======================= القرار =======================
## كل مرشّح: {act, tg, tid, pos, key, item, item2}
static func _decide(w: World, h: Human, now: float) -> void:
	h.think_timer = Rng.randf_range(0.6, 2.2)
	var p := _perceive(w, h, now)
	var dom := h.dominant_drive()
	var cands: Array = []
	var child := h.is_child(now)

	# --- النوم ---
	if h.drives[Human.D.FATIGUE] > 0.2:
		cands.append({"act": Human.Act.SLEEP, "tg": Human.Tg.NONE, "key": "SLEEP", "pos": h.pos, "base": h.drives[Human.D.FATIGUE] * 1.6})

	# --- الماء ---
	if p.water.x >= 0:
		cands.append({"act": Human.Act.DRINK, "tg": Human.Tg.WATER, "key": "DRINK", "pos": Vector2(p.water) + Vector2(0.5, 0.5), "base": 0.05})
	elif h.places.has("water") and h.drives[Human.D.THIRST] > 0.3:
		cands.append({"act": Human.Act.MOVE, "tg": Human.Tg.WATER, "key": "GO|water", "pos": h.places.water, "base": h.drives[Human.D.THIRST] * 1.2})

	# --- التقاط من المصادر ---
	if h.has_free_hand():
		_add_pick(cands, h, p.fruit, Human.Tg.FRUIT_TREE, Items.T.FRUIT)
		_add_pick(cands, h, p.bush, Human.Tg.BUSH, Items.T.BERRY)
		_add_pick(cands, h, p.pbush, Human.Tg.POISON_BUSH, Items.T.POISON_BERRY)
		_add_pick(cands, h, p.stone, Human.Tg.STONE_SRC, Items.T.STONE)
		_add_pick(cands, h, p.stick, Human.Tg.STICK_SRC, Items.T.STICK)
		_add_pick(cands, h, p.clay, Human.Tg.CLAY_SRC, Items.T.CLAY)
		_add_pick(cands, h, p.fiber, Human.Tg.FIBER_SRC, Items.T.FIBER)
		_add_pick(cands, h, p.root, Human.Tg.ROOT_SRC, Items.T.ROOT)
		_add_pick(cands, h, p.grain, Human.Tg.GRAIN_SRC, Items.T.GRAIN)
		for gi in p.ground:
			var arr: Array = w.ground[gi]
			var seen := {}
			for it in arr:
				if seen.has(it):
					continue
				seen[it] = true
				cands.append({"act": Human.Act.PICK, "tg": Human.Tg.GROUND_ITEM, "tid": gi, "item": it, "key": "PICK|%d" % it, "pos": _tile_pos(gi), "base": 0.0})
		# التقاط من جثة حيوان
		for a in p.animals:
			if not a.alive and a.meat_left > 0:
				cands.append({"act": Human.Act.PICK, "tg": Human.Tg.ANIMAL, "tid": a.id, "item": Items.T.RAW_MEAT, "key": "PICK|%d" % Items.T.RAW_MEAT, "pos": a.pos, "base": 0.05})
		# هزّ شجرة
		if not p.tree.is_empty():
			var ti := _nearest_idx(h, p.tree)
			cands.append({"act": Human.Act.STRIKE, "tg": Human.Tg.TREE, "tid": ti, "key": "HIT|tree", "pos": _tile_pos(ti), "base": 0.0})
		# ذاكرة الأماكن
		for k in ["fruit", "berry", "stone", "stick", "meat"]:
			if h.places.has(k) and h.pos.distance_to(h.places[k]) > 3.0:
				cands.append({"act": Human.Act.MOVE, "tg": Human.Tg.NONE, "key": "GO|" + k, "pos": h.places[k], "base": 0.0})

	# --- ما في اليد ---
	for held in [h.hand_r, h.hand_l]:
		if held == Items.T.NONE:
			continue
		cands.append({"act": Human.Act.MOUTH, "tg": Human.Tg.HELD, "item": held, "key": "M|%d" % held, "pos": h.pos, "base": 0.0})
		cands.append({"act": Human.Act.DROP, "tg": Human.Tg.HELD, "item": held, "key": "DROP|%d" % held, "pos": h.pos, "base": -0.1 + h.drives[Human.D.CURIOUS] * 0.05})
		var other := h.other_hand_item(held)
		if other != Items.T.NONE and held <= other:
			cands.append({"act": Human.Act.STRIKE, "tg": Human.Tg.HELD, "item": held, "item2": other, "key": "HIT|%d>%d" % [held, other], "pos": h.pos, "base": 0.0})
			cands.append({"act": Human.Act.STRIKE, "tg": Human.Tg.HELD, "item": other, "item2": held, "key": "HIT|%d>%d" % [other, held], "pos": h.pos, "base": 0.0})
			cands.append({"act": Human.Act.RUB, "tg": Human.Tg.HELD, "item": held, "item2": other, "key": "RUB|%d+%d" % [mini(held, other), maxi(held, other)], "pos": h.pos, "base": 0.0})
		# ضرب شيء على الأرض
		for gi in p.ground:
			var arr2: Array = w.ground[gi]
			var seen2 := {}
			for it2 in arr2:
				if seen2.has(it2):
					continue
				seen2[it2] = true
				cands.append({"act": Human.Act.STRIKE, "tg": Human.Tg.GROUND_ITEM, "tid": gi, "item": held, "item2": it2, "key": "HIT|%d>%d" % [held, it2], "pos": _tile_pos(gi), "base": -0.02})
		# وضع شيء قرب النار
		if not p.fire.is_empty():
			cands.append({"act": Human.Act.PLACE_FIRE, "tg": Human.Tg.FIRE, "item": held, "key": "FIRE|%d" % held, "pos": Vector2(p.fire.x + 0.5, p.fire.y + 0.5), "base": 0.0})
		# إعطاء
		for o in p.humans:
			if o.has_free_hand() and (h.aff(o.id) > 0.05 or o.is_child(now) or Rng.chance(0.1)):
				cands.append({"act": Human.Act.GIVE, "tg": Human.Tg.HUMAN, "tid": o.id, "item": held, "key": "GIVE|%d" % held, "pos": o.pos, "base": h.aff(o.id) * 0.3 + (0.4 if (o.mother_id == h.id or o.father_id == h.id) and o.hunger < 0.5 else 0.0)})
		# الخطّ على الصخر
		if (held == Items.T.PIGMENT or held == Items.T.CHARCOAL) and not p.rock.is_empty():
			var ri := _nearest_idx(h, p.rock)
			cands.append({"act": Human.Act.MARK, "tg": Human.Tg.ROCK_FACE, "tid": ri, "item": held, "key": "MARK|%d" % held, "pos": _tile_pos(ri), "base": h.drives[Human.D.CURIOUS] * 0.3})
		# تكويم (بناء بدائي)
		if held == Items.T.STICK or held == Items.T.FIBER or held == Items.T.HIDE or held == Items.T.CLUB:
			var here := w.terrain.idx(h.tile().x, h.tile().y)
			var base := 0.0
			if h.drives[Human.D.COLD] > 0.2 or w.rain_intensity > 0.3:
				base += 0.25
			if h.home != Vector2.INF and h.pos.distance_to(h.home) < 2.0:
				base += 0.15
			cands.append({"act": Human.Act.PILE, "tg": Human.Tg.PILE, "tid": here, "item": held, "key": "PILE|%d" % held, "pos": h.pos, "base": base})
		# دفن/تغطية جثة
		for cp in p.corpses:
			if not cp.covered and h.aff(cp.hid) > 0.2 and (held == Items.T.STONE or held == Items.T.CLAY or held == Items.T.STICK):
				cands.append({"act": Human.Act.PILE, "tg": Human.Tg.GROUND_ITEM, "tid": cp.i, "item": held, "key": "COVER", "pos": _tile_pos(cp.i), "base": h.grief * 0.8})

	# --- الحيوانات ---
	for a in p.animals:
		if not a.alive:
			continue
		var weapon := h.best_weapon()
		var courage := h.g_aggression * 0.5 + Items.strike_power(weapon) * 0.15 - h.fear_of_animals * 0.6
		if a.is_predator():
			cands.append({"act": Human.Act.FLEE, "tg": Human.Tg.ANIMAL, "tid": a.id, "key": "FLEE|animal", "pos": a.pos, "base": h.fear_of_animals * 0.9 + (0.5 if a.pos.distance_to(h.pos) < 3.0 else 0.0)})
		if not child and courage > 0.0 and a.kind != Animal.K.FISH and (a.pos.distance_to(h.pos) < 5.0):
			cands.append({"act": Human.Act.HUNT, "tg": Human.Tg.ANIMAL, "tid": a.id, "item": weapon, "key": "HUNT|%d|%d" % [a.kind, weapon], "pos": a.pos, "base": courage * 0.3 + h.drives[Human.D.HUNGER] * 0.2})
		elif a.kind == Animal.K.FISH and p.water.x >= 0 and not child:
			cands.append({"act": Human.Act.HUNT, "tg": Human.Tg.ANIMAL, "tid": a.id, "item": weapon, "key": "HUNT|%d|%d" % [a.kind, weapon], "pos": a.pos, "base": h.drives[Human.D.HUNGER] * 0.15})

	# --- البشر ---
	for o in p.humans:
		var af := h.aff(o.id)
		cands.append({"act": Human.Act.FOLLOW, "tg": Human.Tg.HUMAN, "tid": o.id, "key": "FOLLOW", "pos": o.pos, "base": h.drives[Human.D.LONELY] * (0.4 + af) + (0.3 if (child and (o.id == h.mother_id or o.id == h.father_id)) else 0.0)})
		if h.drives[Human.D.LIBIDO] > 0.3 and o.sex != h.sex and o.is_adult(now) and not o.is_elder(now) and af > 0.15 and o.drives[Human.D.LIBIDO] > 0.2:
			cands.append({"act": Human.Act.MATE, "tg": Human.Tg.HUMAN, "tid": o.id, "key": "MATE", "pos": o.pos, "base": h.drives[Human.D.LIBIDO] * (0.5 + af)})
		# عدوان: عند الجوع الشديد ورؤية آخر يحمل شيئاً، أو كراهية
		if not child and (af < -0.3 or (h.drives[Human.D.HUNGER] > 0.7 and o.held_any() != Items.T.NONE and h.g_aggression > 0.45)):
			cands.append({"act": Human.Act.STRIKE, "tg": Human.Tg.HUMAN, "tid": o.id, "item": h.best_weapon(), "key": "HIT|human", "pos": o.pos, "base": h.g_aggression * 0.35 - af * 0.3})
		# طفل يطلب من والده
		if o.mother_id == h.id or o.father_id == h.id:
			if o.is_infant(now) and o.carried_by < 0 and h.carrying_child < 0 and o.pos.distance_to(h.pos) > 1.5:
				cands.append({"act": Human.Act.CARRY_CHILD, "tg": Human.Tg.HUMAN, "tid": o.id, "key": "CARRY", "pos": o.pos, "base": h.drives[Human.D.PARENT] * 1.2})
	# صوت
	if not p.humans.is_empty() and h.drives[dom] > 0.35 and dom != Human.D.CURIOUS:
		cands.append({"act": Human.Act.VOCALIZE, "tg": Human.Tg.NONE, "item": _drive_concept(dom), "key": "VOC|%d" % dom, "pos": h.pos, "base": 0.05 + h.g_sociability * 0.15})
	if not p.humans.is_empty() and h.drives[Human.D.FEAR] > 0.4:
		cands.append({"act": Human.Act.VOCALIZE, "tg": Human.Tg.NONE, "item": Language.C.DANGER, "key": "VOC|danger", "pos": h.pos, "base": 0.4})
	# الحزن
	for cp in p.corpses:
		if h.aff(cp.hid) > 0.3 and h.grief > 0.3:
			cands.append({"act": Human.Act.GRIEVE, "tg": Human.Tg.GROUND_ITEM, "tid": cp.i, "key": "GRIEVE", "pos": _tile_pos(cp.i), "base": h.grief * 0.6})
	# النار: الاقتراب عند البرد
	if not p.fire.is_empty() and (h.drives[Human.D.COLD] > 0.15 or WorldClock.is_night()):
		cands.append({"act": Human.Act.MOVE, "tg": Human.Tg.FIRE, "key": "GO|fire", "pos": Vector2(p.fire.x + 0.5, p.fire.y + 0.5) + Vector2(Rng.randf_range(-1.2, 1.2), Rng.randf_range(-1.2, 1.2)), "base": h.drives[Human.D.COLD] * 0.5 + 0.05})
	# مأوى عند البرد/المطر
	if not p.pile.is_empty() and (h.drives[Human.D.COLD] > 0.2 or w.rain_intensity > 0.3):
		var pi := _nearest_idx(h, p.pile)
		cands.append({"act": Human.Act.MOVE, "tg": Human.Tg.PILE, "key": "GO|shelter", "pos": _tile_pos(pi), "base": h.drives[Human.D.COLD] * 0.4 + w.rain_intensity * 0.3})
	# العودة إلى "البيت" ليلاً
	if h.home != Vector2.INF and WorldClock.is_night() and h.pos.distance_to(h.home) > 3.0:
		cands.append({"act": Human.Act.MOVE, "tg": Human.Tg.NONE, "key": "GO|home", "pos": h.home, "base": 0.3 + h.drives[Human.D.FATIGUE] * 0.4})
	# التجوّل دائماً خيار
	cands.append({"act": Human.Act.WANDER, "tg": Human.Tg.NONE, "key": "WANDER", "pos": h.pos, "base": 0.08 + h.drives[Human.D.CURIOUS] * 0.25 + (0.3 if h.hunger < 0.4 and cands.size() < 4 else 0.0)})
	# الوقوف
	cands.append({"act": Human.Act.IDLE, "tg": Human.Tg.NONE, "key": "IDLE", "pos": h.pos, "base": 0.02 + h.drives[Human.D.FATIGUE] * 0.1})

	# ---- التقييم ----
	var best_score := -1e9
	var best: Dictionary = {}
	var sum_needs := 0.0
	for i in h.drives.size():
		sum_needs += h.drives[i]
	for c in cands:
		var key: String = c.key
		var score: float = c.base
		# التوقع المتعلَّم: عام + خاص بالدافع المسيطر
		var n := h.tries(key)
		score += h.expect(key) * 0.9
		score += h.expect(key + "|" + str(dom)) * h.drives[dom] * 1.6
		# لكل دافع مرتفع: ما تعلّمه عن هذا الفعل تحت هذا الدافع
		for di in h.drives.size():
			if di != dom and h.drives[di] > 0.3:
				score += h.expect(key + "|" + str(di)) * h.drives[di] * 0.8
		# فضول: ما لم يُجرَّب يجذب
		var novelty := h.drives[Human.D.CURIOUS] * (0.35 / (1.0 + n * 0.6))
		if c.act == Human.Act.MOUTH and h.drives[Human.D.HUNGER] > 0.4 and n == 0:
			novelty += 0.35  # الجائع يضع الأشياء في فمه ليجرّب
		score += novelty
		# المسافة تكلّف
		var dist: float = h.pos.distance_to(c.pos)
		score -= dist * 0.02 * (1.0 + h.drives[Human.D.FATIGUE])
		# أماكن الخطر المتذكَّرة
		for dp in h.danger_places:
			if c.pos.distance_to(dp) < 2.5:
				score -= 0.5 * h.fear_of_animals
		# ضجيج عشوائي حتى لا يكونوا آلات
		score += Rng.randfn(0.0, 0.06)
		if score > best_score:
			best_score = score
			best = c
	_begin(w, h, best, now)
	# التعلّم بالمشاهدة: الأطفال والاجتماعيون يقتبسون
	if not p.humans.is_empty() and Rng.chance(0.15 + (0.25 if child else 0.0)):
		var model: Human = Rng.pick(p.humans)
		var strength := 0.25 + h.aff(model.id) * 0.3 + (0.3 if child else 0.0)
		if strength > 0.1:
			h.copy_learning_from(model, strength)
			# اللغة تنتقل بالسماع
			if model.speech != "" and model.vocab.size() > 0:
				_hear(h, model, model.speech, model.dominant_drive(), p)

static func _add_pick(cands: Array, h: Human, arr: Array, tg: int, item: int) -> void:
	if arr.is_empty():
		return
	var i := _nearest_idx(h, arr)
	cands.append({"act": Human.Act.PICK, "tg": tg, "tid": i, "item": item, "key": "PICK|%d" % item, "pos": _tile_pos(i), "base": 0.0})

static func _drive_concept(d: int) -> int:
	match d:
		Human.D.HUNGER: return Language.C.FOOD
		Human.D.THIRST: return Language.C.WATER
		Human.D.FEAR: return Language.C.DANGER
		Human.D.PAIN: return Language.C.PAIN
		Human.D.COLD: return Language.C.COLD
		Human.D.HEAT: return Language.C.HOT
		Human.D.LONELY: return Language.C.COME
		Human.D.LIBIDO: return Language.C.MATE
		Human.D.PARENT: return Language.C.CHILD
		Human.D.FATIGUE: return Language.C.SLEEP
		_: return Language.C.THIS

static func _begin(w: World, h: Human, c: Dictionary, now: float) -> void:
	h.act = c.act
	h.act_target = c.tg
	h.act_target_id = c.get("tid", -1)
	h.act_target_pos = c.pos
	h.act_key = c.key
	h.act_time = 0.0
	h.act_progress = 0.0
	h.set_meta("item", c.get("item", Items.T.NONE))
	h.set_meta("item2", c.get("item2", Items.T.NONE))
	for i in h.drives.size():
		h.needs_before[i] = h.drives[i]
	h.set_meta("hp_before", h.health)
	h.thought = _thought_text(h, c, now)
	if c.act == Human.Act.WANDER:
		var ang := Rng.randf() * TAU
		var dist := Rng.randf_range(3.0, 9.0)
		h.act_target_pos = h.pos + Vector2(cos(ang), sin(ang)) * dist
		h.act_target_pos.x = clampf(h.act_target_pos.x, 1.0, Terrain.W - 2.0)
		h.act_target_pos.y = clampf(h.act_target_pos.y, 1.0, Terrain.H - 2.0)
	if c.act == Human.Act.FLEE:
		var away: Vector2 = (h.pos - Vector2(c.pos)).normalized()
		if away.length() < 0.1:
			away = Vector2.RIGHT.rotated(Rng.randf() * TAU)
		h.act_target_pos = h.pos + away * 7.0
	if c.act == Human.Act.VOCALIZE:
		_vocalize(w, h, c.item, now)
	if c.act == Human.Act.IDLE:
		h.act = Human.Act.IDLE
		h.think_timer = Rng.randf_range(1.0, 3.0)

## ما يظهر للمشاهد في "نافذة العقل": ليس معرفة بل إحساس
static func _thought_text(h: Human, c: Dictionary, now: float) -> String:
	var dom := h.dominant_drive()
	var feel: String = Human.D_AR[dom] if h.drives[dom] > 0.3 else "هدوء"
	var what := ""
	var n := h.tries(c.key)
	var item: int = c.get("item", Items.T.NONE)
	match c.act:
		Human.Act.WANDER: what = "يمشي بلا هدف" if n < 3 else "يستكشف"
		Human.Act.SLEEP: what = "جفناه ثقيلان"
		Human.Act.DRINK: what = "شيءٌ لامعٌ يتحرّك" if n == 0 else "يعرف ذلك الشيء اللامع"
		Human.Act.PICK: what = ("شيءٌ غريب… ما هذا؟" if n == 0 else "يعرف هذا الشيء") if item != Items.T.NONE else "شيء"
		Human.Act.MOUTH: what = ("يجرّب طعمه" if n == 0 else ("يتذكّر أنه كان جيداً" if h.expect(c.key) > 0.1 else "يتذكّر أنه كان سيئاً"))
		Human.Act.STRIKE:
			if c.tg == Human.Tg.HUMAN: what = "غضب"
			elif c.tg == Human.Tg.TREE: what = "يهزّ الشيء الكبير"
			else: what = "ماذا لو ضربتُ هذا بذاك؟" if n == 0 else "يكرّر ما فعله"
		Human.Act.RUB: what = "يفرك الشيئين معاً" if n < 2 else "يفرك… شيء يحدث"
		Human.Act.DROP: what = "يداه مشغولتان"
		Human.Act.VOCALIZE: what = "يريد أن يُخرج ما بداخله صوتاً"
		Human.Act.GIVE: what = "يريد أن يقترب من الآخر"
		Human.Act.FOLLOW: what = "لا يريد أن يكون وحده"
		Human.Act.FLEE: what = "اهرب!"
		Human.Act.MATE: what = "قلبه يخفق"
		Human.Act.PLACE_FIRE: what = "يضع شيئاً قرب الشيء الساخن" if n == 0 else "يعرف أن الشيء الساخن يغيّر الأشياء"
		Human.Act.HUNT: what = "يريد أن يلمس ذلك الكائن" if n == 0 else "يطارد"
		Human.Act.MARK: what = "يخطّ على الصخر"
		Human.Act.PILE: what = "يُكوّم الأشياء" if c.key != "COVER" else "يغطّي من كان يحبّه"
		Human.Act.GRIEVE: what = "لماذا لا يتحرّك؟"
		Human.Act.CARRY_CHILD: what = "الصغير بعيد"
		Human.Act.MOVE: what = "يتذكّر مكاناً" if c.key != "GO|fire" else "الشيء الساخن يريح"
		_: what = ""
	return "%s • %s" % [feel, what] if what != "" else feel

# ======================= التنفيذ =======================
static func _move_toward(w: World, h: Human, target: Vector2, dt: float, now: float, run: bool = false) -> bool:
	var to := target - h.pos
	var dist := to.length()
	if dist < REACH:
		return true
	var sp := WALK_SPEED * h.speed_factor(now) * (RUN_MULT if run else 1.0)
	if h.energy < 0.15:
		sp *= 0.6
	var step := to.normalized() * minf(sp * dt, dist)
	var np := h.pos + step
	if w.terrain.is_walkable(int(np.x), int(np.y)):
		h.pos = np
	else:
		# التفاف
		var alt1 := h.pos + step.rotated(PI / 2.0)
		var alt2 := h.pos + step.rotated(-PI / 2.0)
		if w.terrain.is_walkable(int(alt1.x), int(alt1.y)):
			h.pos = alt1
		elif w.terrain.is_walkable(int(alt2.x), int(alt2.y)):
			h.pos = alt2
		else:
			return true  # عالق: اعتبر الوصول
	h.moving = true
	if absf(step.x) > 0.001:
		h.facing = 1.0 if step.x > 0 else -1.0
	return h.pos.distance_to(target) < REACH

static func _perform(w: World, h: Human, dt: float, now: float, coarse: bool) -> void:
	h.act_time += dt
	var item: int = h.get_meta("item", Items.T.NONE)
	var item2: int = h.get_meta("item2", Items.T.NONE)
	match h.act:
		Human.Act.WANDER, Human.Act.MOVE:
			if _move_toward(w, h, h.act_target_pos, dt, now) or h.act_time > 60.0:
				_finish(w, h, now, 0.02 if h.act == Human.Act.WANDER else 0.0)
		Human.Act.FLEE:
			if _move_toward(w, h, h.act_target_pos, dt, now, true) or h.act_time > 12.0:
				h.drives[Human.D.FEAR] *= 0.5
				_finish(w, h, now, 0.1)
		Human.Act.SLEEP:
			if h.act_time < 0.5:
				return
			var wake := h.energy > 0.97 or (WorldClock.daylight() > 0.6 and h.energy > 0.55 and float(WorldClock.hour_of_day()) >= h.wake_hour)
			var disturbed := h.drives[Human.D.FEAR] > 0.6 or h.drives[Human.D.PAIN] > 0.7 or h.drives[Human.D.COLD] > 0.8 or h.thirst < 0.1 or h.hunger < 0.1
			if wake or disturbed or h.act_time > 12.0 * 3600.0:
				# مكان النوم المتكرر يصبح "بيتاً"
				if h.home == Vector2.INF or h.pos.distance_to(h.home) < 3.0:
					h.home_score += 1.0
					if h.home_score >= 2.0:
						h.home = h.pos if h.home == Vector2.INF else h.home.lerp(h.pos, 0.3)
				else:
					h.home_score -= 0.5
					if h.home_score <= 0.0:
						h.home = h.pos
						h.home_score = 1.0
				_finish(w, h, now, 0.0)
		Human.Act.DRINK:
			if _move_toward(w, h, h.act_target_pos, dt, now) or h.act_time > 40.0:
				if h.pos.distance_to(h.act_target_pos) < 1.6:
					h.act_progress += dt
					h.thirst = minf(1.0, h.thirst + dt * 0.08)
					if h.act_progress > 4.0 or h.thirst >= 0.99:
						h.places["water"] = h.act_target_pos
						if w.terrain.biome_at(int(h.act_target_pos.x), int(h.act_target_pos.y)) == Terrain.B.SWAMP or Rng.chance(0.04):
							h.sick = minf(1.0, h.sick + 0.15)
						w.stats.meals += 0
						Chronicle.milestone("first_drink", "أول إنسانٍ يكتشف أن الشيء اللامع يُطفئ العطش.", h.pos)
						_finish(w, h, now, 0.0)
				else:
					_finish(w, h, now, -0.05)
		Human.Act.PICK:
			if _move_toward(w, h, h.act_target_pos, dt, now) or h.act_time > 45.0:
				h.act_progress += dt
				var need := 1.2
				if h.act_target == Human.Tg.ROOT_SRC or h.act_target == Human.Tg.CLAY_SRC:
					need = 8.0
				if h.act_progress >= need or coarse:
					var got := _do_pick(w, h, item)
					_finish(w, h, now, 0.12 if got else -0.05)
		Human.Act.MOUTH:
			h.act_progress += dt
			if h.act_progress > 2.0 or coarse:
				_do_mouth(w, h, item, now)
		Human.Act.STRIKE:
			if h.act_target == Human.Tg.HELD:
				h.act_progress += dt
				if h.act_progress > 3.0 or coarse:
					_do_strike_items(w, h, item, item2, false, now)
			elif h.act_target == Human.Tg.GROUND_ITEM:
				if _move_toward(w, h, h.act_target_pos, dt, now) or h.act_time > 45.0:
					h.act_progress += dt
					if h.act_progress > 3.0 or coarse:
						_do_strike_items(w, h, item, item2, true, now)
			elif h.act_target == Human.Tg.TREE:
				if _move_toward(w, h, h.act_target_pos, dt, now) or h.act_time > 45.0:
					h.act_progress += dt
					if h.act_progress > 3.0 or coarse:
						_do_shake_tree(w, h, now)
			elif h.act_target == Human.Tg.HUMAN:
				var o := w.human_by_id(h.act_target_id)
				if o == null or not o.alive:
					_finish(w, h, now, -0.05)
					return
				if _move_toward(w, h, o.pos, dt, now, true) or h.act_time > 20.0:
					if h.pos.distance_to(o.pos) < 1.3:
						_do_strike_human(w, h, o, now)
					else:
						_finish(w, h, now, -0.05)
		Human.Act.HUNT:
			var a := w.animal_by_id(h.act_target_id)
			if a == null or not a.alive:
				_finish(w, h, now, 0.0 if a == null else 0.3)
				return
			if a.kind == Animal.K.FISH:
				if _move_toward(w, h, a.pos, dt, now) or h.act_time > 30.0:
					h.act_progress += dt
					if h.act_progress > 5.0:
						var pw := Items.strike_power(item)
						if Rng.chance(0.08 * pw):
							a.alive = false
							a.corpse_timer = 0.0
							a.pos = h.pos
							w.stats.hunts += 1
							_finish(w, h, now, 0.4)
						else:
							_finish(w, h, now, -0.08)
				return
			if _move_toward(w, h, a.pos, dt, now, true):
				# ضربة
				var pw2 := Items.strike_power(item) * lerpf(0.6, 1.4, h.g_strength)
				a.health -= pw2 * 0.35
				a.fear = 1.0
				a.flee_from = h.pos
				h.energy = maxf(0.0, h.energy - 0.01)
				if a.health <= 0.0:
					a.alive = false
					a.corpse_timer = 0.0
					w.stats.hunts += 1
					h.places["meat"] = a.pos
					var was_first := Chronicle.milestone("first_hunt", "%s أوقع أول حيوان بيده. لم يعرف بعد ماذا يفعل به." % h.label_ar(), h.pos)
					if not was_first and Rng.chance(0.25):
						Chronicle.add(Chronicle.Kind.DISCOVERY, "%s اصطاد %s." % [h.label_ar(), a.name_ar()], h.pos, 1)
					_finish(w, h, now, 0.5)
				elif a.ferocity() > 0.3 and Rng.chance(0.35):
					# الحيوان يرد
					w._animal_attacks_human(a, h, now)
					_finish(w, h, now, -0.4)
			elif h.act_time > 25.0 or h.energy < 0.1:
				_finish(w, h, now, -0.12)
		Human.Act.RUB:
			h.act_progress += dt
			var stick_rub := item == Items.T.STICK and item2 == Items.T.STICK
			if stick_rub:
				var dry := 1.0 - w.rain_intensity
				h.heat_accum += dt * dry * lerpf(0.6, 1.3, h.g_strength)
				if h.heat_accum > 25.0 and Rng.chance(dt * 0.12 * dry):
					var i := w.terrain.idx(h.tile().x, h.tile().y)
					w.start_fire(i, 8.0, "")
					h.remove_item(Items.T.STICK)
					h.heat_accum = 0.0
					h.known_fire = true
					w.stats.fires_made += 1
					Chronicle.milestone("first_fire", "%s فرك عودَين طويلاً… فخرج منهما شيءٌ ساخنٌ مضيء. النار وُلدت." % h.label_ar(), h.pos)
					if w.stats.fires_made > 1 and Rng.chance(0.3):
						Chronicle.add(Chronicle.Kind.DISCOVERY, "%s أشعل ناراً." % h.label_ar(), h.pos, 1)
					_finish(w, h, now, 0.9)
					return
				if h.act_progress > 40.0 or h.energy < 0.1:
					h.heat_accum *= 0.5
					_finish(w, h, now, 0.03 if h.heat_accum > 10.0 else -0.04)
				return
			if h.act_progress > 6.0 or coarse:
				var r := Items.rub_recipe(item, item2)
				if not r.is_empty() and Rng.chance(r.chance):
					if r.consume_a: h.remove_item(item)
					if r.consume_b: h.remove_item(item2)
					h.take(r.result)
					w.stats.tools_made += 1
					_announce_creation(w, h, r.result)
					_finish(w, h, now, 0.7)
				else:
					_finish(w, h, now, -0.03)
		Human.Act.DROP:
			var i := w.terrain.idx(h.tile().x, h.tile().y)
			h.remove_item(item)
			w.drop_item(i, item)
			_finish(w, h, now, 0.0)
		Human.Act.PLACE_FIRE:
			if _move_toward(w, h, h.act_target_pos, dt, now) or h.act_time > 45.0:
				var f := w.nearest_fire(h.pos, 2.0)
				if f.is_empty():
					_finish(w, h, now, -0.02)
					return
				var ti := w.terrain.idx(h.tile().x, h.tile().y)
				if ti == f.i:
					# يقف على النار! ألم
					_finish(w, h, now, -0.5)
					return
				h.remove_item(item)
				if Items.is_fuel(item):
					f.fuel += 7.0
					_finish(w, h, now, 0.25 if h.drives[Human.D.COLD] > 0.2 else 0.05)
				else:
					w.drop_item(ti, item)
					_finish(w, h, now, 0.02)
		Human.Act.GIVE:
			var o := w.human_by_id(h.act_target_id)
			if o == null or not o.alive:
				_finish(w, h, now, -0.02)
				return
			if _move_toward(w, h, o.pos, dt, now) or h.act_time > 40.0:
				if h.pos.distance_to(o.pos) < 1.5 and o.has_free_hand() and h.holds(item):
					h.remove_item(item)
					o.take(item)
					h.add_aff(o.id, 0.12)
					o.add_aff(h.id, 0.2)
					o.drives[Human.D.LONELY] *= 0.7
					# المتلقي يتعلم من المعطي شيئاً عن هذا الشيء
					var k := "M|%d" % item
					if h.tries(k) > 0 and o.tries(k) == 0:
						o.learn(k, h.expect(k) * 0.5)
					Chronicle.milestone("first_gift", "%s أعطى %s شيئاً بلا مقابل." % [h.label_ar(), o.label_ar()], h.pos)
					_finish(w, h, now, 0.25 + h.drives[Human.D.LONELY] * 0.3)
				else:
					_finish(w, h, now, -0.02)
		Human.Act.FOLLOW:
			var o := w.human_by_id(h.act_target_id)
			if o == null or not o.alive:
				_finish(w, h, now, -0.02)
				return
			if h.pos.distance_to(o.pos) > 1.8:
				_move_toward(w, h, o.pos, dt, now)
			if h.act_time > Rng.randf_range(8.0, 25.0):
				var close := h.pos.distance_to(o.pos) < 3.0
				if close:
					h.add_aff(o.id, 0.03)
					o.add_aff(h.id, 0.02)
					h.drives[Human.D.LONELY] *= 0.6
					_hear_if_speaking(w, h, o, now)
				_finish(w, h, now, 0.15 if close else -0.02)
		Human.Act.MATE:
			var o := w.human_by_id(h.act_target_id)
			if o == null or not o.alive:
				_finish(w, h, now, -0.02)
				return
			if _move_toward(w, h, o.pos, dt, now) or h.act_time > 40.0:
				if h.pos.distance_to(o.pos) < 1.4 and o.aff(h.id) > 0.05 and o.drives[Human.D.LIBIDO] > 0.15:
					h.act_progress += dt
					o.moving = false
					if h.act_progress > 20.0 or coarse:
						var fem := h if h.sex == Human.Sex.FEMALE else o
						var mal := o if fem == h else h
						h.add_aff(o.id, 0.25)
						o.add_aff(h.id, 0.25)
						h.drives[Human.D.LIBIDO] = 0.0
						o.drives[Human.D.LIBIDO] = 0.0
						if fem.pregnant_since < 0.0 and Rng.chance(0.25):
							fem.pregnant_since = now
							fem.pregnant_by = mal.id
						Chronicle.milestone("first_couple", "%s و%s صارا يلازمان بعضهما." % [h.label_ar(), o.label_ar()], h.pos)
						_finish(w, h, now, 0.6)
				else:
					h.add_aff(o.id, -0.02)
					_finish(w, h, now, -0.15)
		Human.Act.VOCALIZE:
			if h.act_time > 1.5:
				_finish(w, h, now, 0.0)
		Human.Act.CARRY_CHILD:
			var c := w.human_by_id(h.act_target_id)
			if c == null or not c.alive:
				_finish(w, h, now, 0.0)
				return
			if _move_toward(w, h, c.pos, dt, now) or h.act_time > 40.0:
				if h.pos.distance_to(c.pos) < 1.5 and h.carrying_child < 0 and c.carried_by < 0:
					h.carrying_child = c.id
					c.carried_by = h.id
					_finish(w, h, now, 0.3)
				else:
					_finish(w, h, now, -0.02)
		Human.Act.MARK:
			if _move_toward(w, h, h.act_target_pos, dt, now) or h.act_time > 45.0:
				h.act_progress += dt
				if h.act_progress > 12.0 or coarse:
					var ti := w.terrain.idx(int(h.act_target_pos.x), int(h.act_target_pos.y))
					w.terrain.marks[ti] = mini(9, w.terrain.marks[ti] + 1)
					if Rng.chance(0.4):
						h.remove_item(item)
					Chronicle.milestone("first_art", "%s خطّ علاماتٍ ملوّنة على صخرة. لا معنى لها… أو ربما لها." % h.label_ar(), h.pos)
					_finish(w, h, now, 0.35)
		Human.Act.PILE:
			if _move_toward(w, h, h.act_target_pos, dt, now) or h.act_time > 45.0:
				h.act_progress += dt
				if h.act_progress > 5.0 or coarse:
					h.remove_item(item)
					if h.act_key == "COVER":
						for cp in w.corpses:
							if cp.i == h.act_target_id:
								cp.covered = true
								h.grief *= 0.4
								Chronicle.milestone("first_burial", "%s غطّى جسد %s بالحجارة والطين. أول قبر." % [h.label_ar(), cp.name], h.pos)
								break
						_finish(w, h, now, 0.5)
					else:
						var ti := w.terrain.idx(h.tile().x, h.tile().y)
						w.shelter[ti] = mini(9, w.shelter[ti] + 1)
						if w.shelter[ti] == 3:
							Chronicle.milestone("first_shelter", "%s كوّم أعواداً وألياف حتى صار له ركنٌ يقيه المطر. أول مأوى." % h.label_ar(), h.pos)
						if h.home == Vector2.INF:
							h.home = h.pos
							h.home_score = 2.0
						_finish(w, h, now, 0.15)
		Human.Act.GRIEVE:
			if _move_toward(w, h, h.act_target_pos, dt, now) or h.act_time > 45.0:
				h.act_progress += dt
				h.grief = maxf(0.0, h.grief - dt / 600.0)
				if h.act_progress > 60.0 or h.grief < 0.1:
					if not Chronicle.has_milestone("first_grief"):
						Chronicle.milestone("first_grief", "%s جلس طويلاً عند جسد لا يتحرّك. شيءٌ ثقيل في صدره لا اسم له." % h.label_ar(), h.pos)
					_finish(w, h, now, 0.2)
		_:
			_finish(w, h, now, 0.0)

# ======================= تفاصيل الأفعال =======================
static func _do_pick(w: World, h: Human, item: int) -> bool:
	var t := w.terrain
	var i := h.act_target_id
	match h.act_target:
		Human.Tg.GROUND_ITEM:
			if w.take_item(i, item):
				return h.take(item)
			return false
		Human.Tg.ANIMAL:
			var a := w.animal_by_id(i)
			if a == null or a.alive or a.meat_left <= 0:
				return false
			a.meat_left -= 1
			var got := h.take(Items.T.RAW_MEAT)
			if a.meat_left == 0:
				var ti := t.idx(int(a.pos.x), int(a.pos.y))
				w.drop_item(ti, Items.T.BONE)
				if a.size() > 0.4:
					w.drop_item(ti, Items.T.HIDE)
			return got
		Human.Tg.FRUIT_TREE:
			if t.fruit[i] > 0:
				t.fruit[i] -= 1
				h.places["fruit"] = _tile_pos(i)
				return h.take(Items.T.FRUIT)
		Human.Tg.BUSH:
			if t.berries[i] > 0:
				t.berries[i] -= 1
				h.places["berry"] = _tile_pos(i)
				return h.take(Items.T.BERRY)
		Human.Tg.POISON_BUSH:
			if t.poison_berries[i] > 0:
				t.poison_berries[i] -= 1
				return h.take(Items.T.POISON_BERRY)
		Human.Tg.STONE_SRC:
			if t.stones[i] > 0:
				t.stones[i] -= 1
				h.places["stone"] = _tile_pos(i)
				return h.take(Items.T.STONE)
		Human.Tg.STICK_SRC:
			if t.sticks[i] > 0:
				t.sticks[i] -= 1
				h.places["stick"] = _tile_pos(i)
				return h.take(Items.T.STICK)
		Human.Tg.CLAY_SRC:
			if t.clay[i] > 0:
				t.clay[i] -= 1
				return h.take(Items.T.CLAY)
		Human.Tg.FIBER_SRC:
			if t.fiber[i] > 0:
				t.fiber[i] -= 1
				return h.take(Items.T.FIBER)
		Human.Tg.ROOT_SRC:
			if t.roots[i] > 0:
				t.roots[i] -= 1
				return h.take(Items.T.ROOT)
		Human.Tg.GRAIN_SRC:
			if t.grain[i] > 0:
				t.grain[i] -= 1
				if Rng.chance(0.3):
					w.drop_item(i, Items.T.SEED)
				return h.take(Items.T.GRAIN)
	return false

static func _do_mouth(w: World, h: Human, item: int, now: float) -> void:
	if not h.holds(item):
		_finish(w, h, now, -0.02)
		return
	var fx := Items.food_effect(item)
	if fx.is_empty():
		# ليس طعاماً: طعمٌ سيء، يبصقه
		h.remove_item(item)
		w.drop_item(w.terrain.idx(h.tile().x, h.tile().y), item)
		_finish(w, h, now, -0.12)
		return
	h.remove_item(item)
	var before := h.hunger
	h.hunger = minf(1.0, h.hunger + fx.cal)
	h.thirst = clampf(h.thirst + fx.water, 0.0, 1.0)
	h.poison = minf(1.0, h.poison + fx.poison)
	if Rng.chance(fx.sick):
		h.sick = minf(1.0, h.sick + 0.35)
	h.last_meal_item = item
	h.last_meal_at = now
	w.stats.meals += 1
	var reward: float = (h.hunger - before) * 2.2 - fx.poison * 2.5 - fx.sick * 0.3
	# طعم فوري: السامّ مرّ عادة
	if fx.poison > 0.3:
		reward -= 0.4
		h.drives[Human.D.PAIN] = maxf(h.drives[Human.D.PAIN], 0.5)
	# الطعم يُطبع في الذاكرة على العنصر نفسه
	h.learn("M|%d" % item, reward)
	if item == Items.T.COOKED_MEAT:
		Chronicle.milestone("first_cooked", "%s أكل لحماً غيّرته النار. كان أفضل بكثير." % h.label_ar(), h.pos)
	elif item == Items.T.BREAD:
		Chronicle.milestone("first_bread", "%s أكل عجيناً تصلّب على النار: أول خبز." % h.label_ar(), h.pos)
	elif item == Items.T.RAW_MEAT:
		Chronicle.milestone("first_meat", "%s أكل لحماً نيئاً لأول مرة." % h.label_ar(), h.pos)
	elif item == Items.T.FRUIT or item == Items.T.BERRY:
		Chronicle.milestone("first_food", "%s وضع شيئاً في فمه… فسكن الجوع. أول وجبة." % h.label_ar(), h.pos)
	_finish(w, h, now, reward)

static func _do_strike_items(w: World, h: Human, held: int, target: int, on_ground: bool, now: float) -> void:
	if not h.holds(held):
		_finish(w, h, now, -0.02)
		return
	var ti := w.terrain.idx(h.tile().x, h.tile().y)
	if on_ground:
		var gi := h.act_target_id
		if not w.ground_items(gi).has(target):
			_finish(w, h, now, -0.02)
			return
		ti = gi
	elif not h.holds(target):
		_finish(w, h, now, -0.02)
		return
	var r := Items.strike_recipe(held, target)
	h.energy = maxf(0.0, h.energy - 0.004)
	# خطر إصابة اليد عند ضرب الحجارة
	if held == Items.T.STONE and target == Items.T.STONE and Rng.chance(0.05):
		h.injury = minf(1.0, h.injury + 0.08)
		h.drives[Human.D.PAIN] = 0.6
	if r.is_empty() or not Rng.chance(r.chance):
		# الحجر قد ينكسر بلا فائدة
		if held == Items.T.STONE and target == Items.T.STONE and Rng.chance(0.15):
			if on_ground: w.take_item(ti, target)
			else: h.remove_item(target)
		_finish(w, h, now, -0.03)
		return
	if r.consume_target:
		if on_ground: w.take_item(ti, target)
		else: h.remove_item(target)
	if r.consume_held:
		h.remove_item(held)
	if not h.take(r.result):
		w.drop_item(ti, r.result)
	w.stats.tools_made += 1
	_announce_creation(w, h, r.result)
	_finish(w, h, now, 0.6)

static func _announce_creation(w: World, h: Human, result: int) -> void:
	var nm: String = Items.NAME_AR[result]
	match result:
		Items.T.SHARP_STONE:
			Chronicle.milestone("first_tool", "%s ضرب حجراً بحجر فانكسر وصار له حدٌّ. أول أداة." % h.label_ar(), h.pos)
		Items.T.SPEAR:
			Chronicle.milestone("first_spear", "%s شحذ طرف عودٍ بحجرٍ حاد. صار الرمح." % h.label_ar(), h.pos)
		Items.T.CLUB:
			Chronicle.milestone("first_club", "%s صنع هراوة." % h.label_ar(), h.pos)
		Items.T.ROPE:
			Chronicle.milestone("first_rope", "%s جدل أليافاً فصارت حبلاً." % h.label_ar(), h.pos)
		Items.T.POT:
			Chronicle.milestone("first_pot", "%s عجن طيناً فصار إناءً." % h.label_ar(), h.pos)
		Items.T.FLOUR:
			Chronicle.milestone("first_flour", "%s طحن حبوباً بحجر." % h.label_ar(), h.pos)
		Items.T.BONE_NEEDLE:
			Chronicle.milestone("first_needle", "%s صنع إبرة من عظمة." % h.label_ar(), h.pos)
		Items.T.WATER_SKIN:
			Chronicle.milestone("first_skin", "%s صنع قربة يحمل فيها الماء." % h.label_ar(), h.pos)
		Items.T.PIGMENT:
			Chronicle.milestone("first_pigment", "%s سحق صَدَفة فخرج منها لونٌ." % h.label_ar(), h.pos)
		_:
			if Rng.chance(0.15):
				Chronicle.add(Chronicle.Kind.DISCOVERY, "%s صنع %s." % [h.label_ar(), nm], h.pos, 1)

static func _do_shake_tree(w: World, h: Human, now: float) -> void:
	var i := h.act_target_id
	var t := w.terrain
	var ti := i
	var got := false
	if t.fruit_trees[i] > 0 and t.fruit[i] > 0 and Rng.chance(0.5):
		t.fruit[i] -= 1
		w.drop_item(ti, Items.T.FRUIT)
		got = true
	if t.trees[i] > 0 and Rng.chance(0.45):
		w.drop_item(ti, Items.T.STICK)
		got = true
	if Rng.chance(0.08):
		w.drop_item(ti, Items.T.EGG)
		got = true
	h.energy = maxf(0.0, h.energy - 0.005)
	_finish(w, h, now, 0.2 if got else -0.04)

static func _do_strike_human(w: World, h: Human, o: Human, now: float) -> void:
	var weapon := h.best_weapon()
	var dmg := 0.08 * Items.strike_power(weapon) * lerpf(0.6, 1.4, h.g_strength) * Rng.randf_range(0.6, 1.3)
	o.injury = minf(1.0, o.injury + dmg)
	o.health -= dmg * 0.7
	o.drives[Human.D.PAIN] = 1.0
	o.drives[Human.D.FEAR] = 0.9
	o.add_aff(h.id, -0.4)
	h.add_aff(o.id, -0.1)
	# الآخرون يرون
	for x in w.humans:
		if x.alive and x != h and x != o and x.pos.distance_to(h.pos) < World.PERCEPTION:
			x.add_aff(h.id, -0.08 * (1.0 + x.aff(o.id)))
	# سلب ما في يده
	var reward := -0.1
	if o.held_any() != Items.T.NONE and Rng.chance(0.5) and h.has_free_hand():
		var it := o.held_any()
		o.remove_item(it)
		h.take(it)
		reward += 0.3
	Chronicle.milestone("first_violence", "%s ضرب %s. أول عنفٍ بين البشر." % [h.label_ar(), o.label_ar()], h.pos)
	if Rng.chance(0.3):
		Chronicle.add(Chronicle.Kind.CONFLICT, "%s ضرب %s." % [h.label_ar(), o.label_ar()], h.pos, 1)
	if o.health <= 0.0:
		w._kill(o, "قتله %s" % h.label_ar(), now)
		w.stats.kills += 1
		Chronicle.milestone("first_murder", "%s قتل %s. أول قتلٍ بين البشر." % [h.label_ar(), o.label_ar()], h.pos)
		reward += 0.2
	_finish(w, h, now, reward)

static func _start_flee(w: World, h: Human, now: float) -> void:
	var threat := Vector2.INF
	var bd := 99.0
	for a in w.animals:
		if a.alive and a.is_predator():
			var d := a.pos.distance_to(h.pos)
			if d < bd:
				bd = d
				threat = a.pos
	var f := w.nearest_fire(h.pos, 1.5)
	if not f.is_empty():
		threat = Vector2(f.x + 0.5, f.y + 0.5)
	if threat == Vector2.INF:
		threat = h.pos + Vector2(Rng.randf_range(-1, 1), Rng.randf_range(-1, 1))
	_begin(w, h, {"act": Human.Act.FLEE, "tg": Human.Tg.NONE, "key": "FLEE", "pos": threat}, now)

# ======================= اللغة =======================
static func _vocalize(w: World, h: Human, concept: int, now: float) -> void:
	var ck := str(concept)
	var word: String = h.vocab.get(ck, "")
	if word == "":
		# يخترع صوتاً جديداً
		word = Language.invent_word()
		h.vocab[ck] = word
		if not Chronicle.has_milestone("first_word"):
			Chronicle.milestone("first_word", "%s أصدر صوتاً مقصوداً: «%s». أول كلمة." % [h.label_ar(), word], h.pos)
	h.speech = word
	h.speech_timer = 3.0
	for o in w.humans:
		if o.alive and o != h and o.pos.distance_to(h.pos) < 6.0:
			_hear(o, h, word, h.dominant_drive(), {})
			# الاستجابة: إن فهم المستمع "خطر" يخاف، وإن فهم "طعام/تعال" يقترب
			var meaning := _understood(o, word)
			if meaning == Language.C.DANGER:
				o.drives[Human.D.FEAR] = maxf(o.drives[Human.D.FEAR], 0.7)
			elif meaning == Language.C.COME or meaning == Language.C.FOOD:
				if o.act == Human.Act.IDLE or o.act == Human.Act.WANDER:
					_begin(w, o, {"act": Human.Act.FOLLOW, "tg": Human.Tg.HUMAN, "tid": h.id, "key": "FOLLOW", "pos": h.pos}, now)
					h.learn("VOC|%d" % h.dominant_drive(), 0.2)

static func _understood(o: Human, word: String) -> int:
	var hd = o.heard.get(word)
	if hd == null:
		return -1
	var best := -1
	var bn := 0
	for c in hd:
		if hd[c] > bn:
			bn = hd[c]
			best = int(c)
	return best if bn >= 2 else -1

## المستمع يربط الصوت بما يبدو أن المتحدّث يشعر به (من حاله وسلوكه)
static func _hear(listener: Human, speaker: Human, word: String, speaker_drive: int, p: Dictionary) -> void:
	var concept := _drive_concept(speaker_drive)
	if speaker.act == Human.Act.FLEE:
		concept = Language.C.DANGER
	elif speaker.act == Human.Act.HUNT:
		concept = Language.C.ANIMAL
	if not listener.heard.has(word):
		listener.heard[word] = {}
	var hd: Dictionary = listener.heard[word]
	var ck := str(concept)
	hd[ck] = hd.get(ck, 0) + 1
	# التبنّي: إذا سمع الكلمة بنفس المعنى مرّات كافية اتّخذها
	if hd[ck] >= 3 and not listener.vocab.has(ck):
		listener.vocab[ck] = Language.mutate(word)
		_check_shared_language(listener)
	elif hd[ck] >= 3 and listener.vocab.get(ck, "") != word and Rng.chance(0.15):
		listener.vocab[ck] = word  # تقارب اللهجات
	listener.add_aff(speaker.id, 0.01)

static func _hear_if_speaking(w: World, h: Human, o: Human, now: float) -> void:
	if o.speech != "":
		_hear(h, o, o.speech, o.dominant_drive(), {})

static func _check_shared_language(h: Human) -> void:
	if Chronicle.has_milestone("shared_word"):
		return
	# نتحقق لاحقاً في World.hourly عبر الإحصاء؛ هنا إشعار مبكّر
	pass

# ======================= التعلّم =======================
static func learn_pain(h: Human, source: String) -> void:
	if source == "fire":
		h.learn("GO|fire", -0.3)
		h.learn("FIRE|%d" % Items.T.STICK, -0.05)
	elif source.begins_with("animal"):
		var k := int(source.substr(6))
		for wpn in [Items.T.NONE, Items.T.STONE, Items.T.STICK, Items.T.SHARP_STONE, Items.T.CLUB, Items.T.SPEAR]:
			h.learn("HUNT|%d|%d" % [k, wpn], -0.35)
		h.learn("FLEE|animal", 0.3)

static func _finish(w: World, h: Human, now: float, intrinsic: float) -> void:
	# المكافأة = ما خفّ من الشعور السيء (موزوناً بشدّته قبل الفعل) + ما جاء من الفعل نفسه
	update_drives(w, h, now)
	var reward := intrinsic
	var dom := 0
	for i in h.drives.size():
		if h.needs_before[i] > h.needs_before[dom]:
			dom = i
	for i in h.drives.size():
		if i == Human.D.CURIOUS:
			continue
		var delta := h.needs_before[i] - h.drives[i]
		reward += delta * (0.6 + h.needs_before[i] * 1.4)
	var hp_before: float = h.get_meta("hp_before", h.health)
	reward += (h.health - hp_before) * 3.0
	var key := h.act_key
	if key != "" and key != "IDLE":
		h.learn(key, reward)
		if h.needs_before[dom] > 0.25:
			h.learn(key + "|" + str(dom), reward)
	h.act = Human.Act.IDLE
	h.act_key = ""
	h.think_timer = Rng.randf_range(0.3, 1.5)
	h.thought = ""
