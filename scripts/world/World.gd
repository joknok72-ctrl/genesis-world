class_name World
extends RefCounted
## World — حالة العالم كاملة وقوانينه الفيزيائية والبيولوجية.
## هنا لا توجد "قواعد لعبة"، فقط طبيعة: حرارة، مطر، جوع، ولادة، موت، نار.

signal human_born(h: Human)
signal human_died(h: Human)
signal fire_started(pos: Vector2)
signal lightning(pos: Vector2)

const PERCEPTION := 7.0
const MAX_HUMANS := 140
const MAX_ANIMALS := 90

enum Weather { CLEAR, CLOUDY, RAIN, STORM, SNOW }
const WEATHER_AR := {Weather.CLEAR: "صحو", Weather.CLOUDY: "غائم", Weather.RAIN: "مطر", Weather.STORM: "عاصفة", Weather.SNOW: "ثلج"}

var terrain := Terrain.new()
var humans: Array[Human] = []
var animals: Array[Animal] = []
var ground: Dictionary = {}          # tile idx -> Array[int]
var fires: Array = []                # {i, fuel, age, x, y}
var corpses: Array = []              # {i, t, covered, hid, name}
var shelter := PackedByteArray()
var next_id := 1
var weather: int = Weather.CLEAR
var weather_timer := 0.0
var wind := Vector2(1, 0)
var cloud_cover := 0.1
var rain_intensity := 0.0
var ambient_temp := 22.0
var born_count := 0
var died_count := 0
var human_epoch := 0.0
var sim_time := 0.0                  # ثواني العالم التي حاكيناها فعلاً
var stats := {"fires_made": 0, "tools_made": 0, "hunts": 0, "words": 0, "kills": 0, "meals": 0}
var _hour_accum := 0.0
var _regrow_accum := 0.0
var _animal_spawn_accum := 0.0
var _humans_by_id: Dictionary = {}
var lightning_flash := 0.0
var last_event_pos := Vector2.INF

func _init() -> void:
	shelter.resize(Terrain.W * Terrain.H)
	shelter.fill(0)

# =================== توليد عالم جديد ===================
func generate() -> void:
	terrain.generate(Rng.seed_value)
	_spawn_initial_animals()

func _spawn_initial_animals() -> void:
	var tries := 0
	while animals.size() < 60 and tries < 4000:
		tries += 1
		var x := Rng.randi_range(2, Terrain.W - 3)
		var y := Rng.randi_range(2, Terrain.H - 3)
		var b := terrain.biome_at(x, y)
		var k := -1
		match b:
			Terrain.B.GRASS, Terrain.B.SAVANNA:
				k = Rng.pick([Animal.K.RABBIT, Animal.K.DEER, Animal.K.DEER, Animal.K.BIRD, Animal.K.BOAR])
			Terrain.B.FOREST, Terrain.B.DENSE_FOREST:
				k = Rng.pick([Animal.K.DEER, Animal.K.BOAR, Animal.K.WOLF, Animal.K.BIRD, Animal.K.RABBIT])
			Terrain.B.HILLS, Terrain.B.MOUNTAIN:
				k = Rng.pick([Animal.K.GOAT, Animal.K.GOAT, Animal.K.WOLF])
			Terrain.B.WATER:
				k = Animal.K.FISH
		if k >= 0:
			animals.append(Animal.create(next_id, k, Vector2(x + 0.5, y + 0.5), 0.0))
			next_id += 1

## ظهور البشر الأوائل: بلا ذاكرة، بلا لغة، بلا أدوات.
func spawn_first_humans(now: float) -> void:
	human_epoch = now
	var center := _find_spawn_center()
	var count := 8
	for i in count:
		var p := _walkable_near(center, 2.0, 9.0)
		var s := Human.Sex.MALE if i % 2 == 0 else Human.Sex.FEMALE
		var h := Human.create(next_id, p, Rng.randf_range(16.0, 24.0), s, now)
		next_id += 1
		_add_human(h)
	Chronicle.add(Chronicle.Kind.LIFE, "ظهر أول البشر على الأرض: %d أفراد، لا يعرفون شيئاً بعد." % count, center, 3)

func _find_spawn_center() -> Vector2:
	var best := Vector2(Terrain.W * 0.5, Terrain.H * 0.5)
	var best_score := -1.0
	for t in 400:
		var x := Rng.randi_range(12, Terrain.W - 13)
		var y := Rng.randi_range(12, Terrain.H - 13)
		if not terrain.is_walkable(x, y):
			continue
		var b := terrain.biome_at(x, y)
		if b != Terrain.B.GRASS and b != Terrain.B.SAVANNA and b != Terrain.B.FOREST:
			continue
		var w := terrain.nearest_water(x, y, 10)
		var score := 0.0
		if w.x >= 0:
			score += 1.0
		# غنى الموارد حول النقطة
		for dy in range(-5, 6):
			for dx in range(-5, 6):
				if terrain.in_bounds(x + dx, y + dy):
					var i := terrain.idx(x + dx, y + dy)
					score += terrain.fruit_trees[i] * 0.3 + terrain.bushes[i] * 0.2 + terrain.stones[i] * 0.05 + terrain.trees[i] * 0.05
		if score > best_score:
			best_score = score
			best = Vector2(x + 0.5, y + 0.5)
	return best

func _walkable_near(c: Vector2, rmin: float, rmax: float) -> Vector2:
	for t in 200:
		var a := Rng.randf() * TAU
		var r := Rng.randf_range(rmin, rmax)
		var p := c + Vector2(cos(a), sin(a)) * r
		var ti := Vector2i(int(p.x), int(p.y))
		if terrain.is_walkable(ti.x, ti.y):
			return p
	return c

func _add_human(h: Human) -> void:
	humans.append(h)
	_humans_by_id[h.id] = h

func human_by_id(i: int) -> Human:
	return _humans_by_id.get(i)

func living_count() -> int:
	var n := 0
	for h in humans:
		if h.alive:
			n += 1
	return n

# =================== الأرض والأشياء ===================
func ground_items(i: int) -> Array:
	return ground.get(i, [])

func drop_item(i: int, item: int) -> void:
	if item == Items.T.NONE:
		return
	if not ground.has(i):
		ground[i] = []
	var arr: Array = ground[i]
	if arr.size() < 14:
		arr.append(item)

func take_item(i: int, item: int) -> bool:
	if not ground.has(i):
		return false
	var arr: Array = ground[i]
	var k := arr.find(item)
	if k < 0:
		return false
	arr.remove_at(k)
	if arr.is_empty():
		ground.erase(i)
	return true

func fire_at(i: int) -> Dictionary:
	for f in fires:
		if f.i == i:
			return f
	return {}

func nearest_fire(p: Vector2, r: float) -> Dictionary:
	var best := {}
	var bd := r * r
	for f in fires:
		var d := p.distance_squared_to(Vector2(f.x + 0.5, f.y + 0.5))
		if d < bd:
			bd = d
			best = f
	return best

func start_fire(i: int, fuel: float, cause: String) -> void:
	if not fire_at(i).is_empty():
		fire_at(i).fuel += fuel
		return
	var x := i % Terrain.W
	var y := i / Terrain.W
	if terrain.is_water(x, y):
		return
	fires.append({"i": i, "fuel": fuel, "age": 0.0, "x": x, "y": y})
	fire_started.emit(Vector2(x + 0.5, y + 0.5))
	if cause != "":
		Chronicle.add(Chronicle.Kind.NATURE if cause.begins_with("برق") else Chronicle.Kind.DISCOVERY, cause, Vector2(x + 0.5, y + 0.5), 2)

# =================== الحلقة الرئيسية ===================
## dt: ثواني عالم (حقيقية). تُستدعى كل إطار بـ delta أو بخطوات كبيرة عند الاستدراك.
func tick(dt: float, now: float, coarse: bool = false) -> void:
	sim_time += dt
	_update_weather(dt, now)
	_regrow_accum += dt
	if _regrow_accum > 1.0:
		var hours := _regrow_accum / 3600.0
		terrain.regrow_step(int(clampf(_regrow_accum * 60.0, 60, 16384)), WorldClock.season(), hours * 60.0)
		_regrow_accum = 0.0
	_update_fires(dt)
	_update_corpses(dt)
	_update_animals(dt, now, coarse)
	var daylight := WorldClock.daylight()
	for h in humans:
		if not h.alive:
			continue
		_physiology(h, dt, now, daylight)
		if not h.alive:
			continue
		Brain.step(self, h, dt, now, coarse)
	_hour_accum += dt
	if _hour_accum >= 3600.0:
		_hour_accum -= 3600.0
		_hourly(now)
	if lightning_flash > 0.0:
		lightning_flash = maxf(0.0, lightning_flash - dt * 3.0)

func _hourly(now: float) -> void:
	# حيوانات جديدة (تكاثر بطيء)
	if animals.size() < MAX_ANIMALS and Rng.chance(0.35):
		var a: Animal = Rng.pick(animals)
		if a != null and a.alive and now - a.last_birth > 86400.0 * 60.0 and a.kind != Animal.K.FISH:
			var p := _walkable_near(a.pos, 0.5, 2.0)
			animals.append(Animal.create(next_id, a.kind, p, now))
			next_id += 1
			a.last_birth = now
	# تنظيف الموتى القدامى من مصفوفة البشر (نحتفظ بآخر 60 ميتاً للتاريخ)
	var dead := 0
	for h in humans:
		if not h.alive:
			dead += 1
	if dead > 60:
		for k in range(humans.size() - 1, -1, -1):
			if not humans[k].alive and now - humans[k].died_at > 86400.0 * 30.0:
				_humans_by_id.erase(humans[k].id)
				humans.remove_at(k)
				dead -= 1
				if dead <= 60:
					break
	# إحصاء الكلمات المشتركة
	var words := {}
	for h in humans:
		if h.alive:
			for c in h.vocab:
				words[h.vocab[c]] = true
	stats.words = words.size()

# =================== الطقس ===================
func _update_weather(dt: float, now: float) -> void:
	weather_timer -= dt
	var season := WorldClock.season()
	var center_t := terrain.temperature(Terrain.W / 2, Terrain.H / 2, season, WorldClock.daylight(), WorldClock.day_of_year())
	ambient_temp = center_t
	if weather_timer <= 0.0:
		weather_timer = Rng.randf_range(1800.0, 4.0 * 3600.0)
		var wet: float = [0.35, 0.18, 0.3, 0.4][season]
		var r := Rng.randf()
		if r < 0.5 - wet * 0.5:
			weather = Weather.CLEAR
		elif r < 0.78 - wet * 0.3:
			weather = Weather.CLOUDY
		elif r < 0.95:
			weather = Weather.SNOW if center_t < 1.0 else Weather.RAIN
		else:
			weather = Weather.STORM
		wind = Vector2(cos(Rng.randf() * TAU), sin(Rng.randf() * TAU)) * Rng.randf_range(0.2, 1.0)
	var target_cloud: float = [0.05, 0.6, 0.9, 1.0, 0.85][weather]
	cloud_cover = lerpf(cloud_cover, target_cloud, clampf(dt / 240.0, 0.0, 1.0))
	var target_rain: float = [0.0, 0.0, 0.6, 1.0, 0.5][weather]
	rain_intensity = lerpf(rain_intensity, target_rain, clampf(dt / 120.0, 0.0, 1.0))
	if weather == Weather.STORM and Rng.chance(dt / 220.0):
		var x := Rng.randi_range(0, Terrain.W - 1)
		var y := Rng.randi_range(0, Terrain.H - 1)
		lightning_flash = 1.0
		lightning.emit(Vector2(x + 0.5, y + 0.5))
		var i := terrain.idx(x, y)
		if not terrain.is_water(x, y) and terrain.flammability(i) > 0.3 and Rng.chance(0.5):
			start_fire(i, 25.0, "برقٌ أشعل ناراً في %s." % Terrain.B_NAME_AR[terrain.biome_at(x, y)])
		# قد تُصيب إنساناً
		for h in humans:
			if h.alive and h.pos.distance_to(Vector2(x + 0.5, y + 0.5)) < 1.2 and Rng.chance(0.4):
				_kill(h, "صعقه البرق", now)

func temperature_at(p: Vector2) -> float:
	var t := terrain.temperature(clampi(int(p.x), 0, Terrain.W - 1), clampi(int(p.y), 0, Terrain.H - 1), WorldClock.season(), WorldClock.daylight(), WorldClock.day_of_year())
	t -= cloud_cover * 3.0 + rain_intensity * 4.0
	var f := nearest_fire(p, 2.5)
	if not f.is_empty():
		t += 14.0 * clampf(1.0 - p.distance_to(Vector2(f.x + 0.5, f.y + 0.5)) / 2.5, 0.0, 1.0) * clampf(f.fuel / 10.0, 0.3, 1.0)
	var i := terrain.idx(clampi(int(p.x), 0, Terrain.W - 1), clampi(int(p.y), 0, Terrain.H - 1))
	if shelter[i] >= 3:
		t += 5.0 + (rain_intensity * 4.0)
	return t

# =================== النار ===================
func _update_fires(dt: float) -> void:
	for k in range(fires.size() - 1, -1, -1):
		var f: Dictionary = fires[k]
		f.age += dt
		var burn := dt * (0.02 + rain_intensity * 0.25)
		f.fuel -= burn
		# النار تستهلك الوقود على الأرض
		var i: int = f.i
		if f.fuel < 6.0 and ground.has(i):
			var arr: Array = ground[i]
			for j in range(arr.size() - 1, -1, -1):
				if Items.is_fuel(arr[j]):
					arr.remove_at(j)
					f.fuel += 6.0
					break
		# تطهو ما يوضع حولها
		if Rng.chance(dt / 45.0):
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx: int = f.x + dx
					var ny: int = f.y + dy
					if not terrain.in_bounds(nx, ny):
						continue
					var j := terrain.idx(nx, ny)
					if ground.has(j):
						var arr2: Array = ground[j]
						for q in arr2.size():
							var res := Items.fire_transform(arr2[q])
							if res != Items.T.NONE and Rng.chance(0.5):
								arr2[q] = res
								break
		# انتشار
		var dry := 1.0 - rain_intensity
		if WorldClock.season() == WorldClock.Season.SUMMER:
			dry *= 1.6
		if Rng.chance(dt * 0.0012 * dry * clampf(f.fuel / 15.0, 0.2, 1.5)):
			var dirv := Vector2i(signi(int(round(wind.x + Rng.randf_range(-1, 1)))), signi(int(round(wind.y + Rng.randf_range(-1, 1)))))
			var nx2: int = f.x + dirv.x
			var ny2: int = f.y + dirv.y
			if terrain.in_bounds(nx2, ny2):
				var j2 := terrain.idx(nx2, ny2)
				var fl := terrain.flammability(j2)
				if fl > 0.2 and fire_at(j2).is_empty() and Rng.chance(fl):
					start_fire(j2, 10.0 + fl * 25.0, "")
					terrain.burn_tile(j2)
					if fires.size() == 6:
						Chronicle.add(Chronicle.Kind.NATURE, "اندلع حريقٌ واسع في البرّ.", Vector2(nx2, ny2), 2)
		if f.fuel <= 0.0:
			if f.age > 1200.0:
				drop_item(i, Items.T.CHARCOAL)
			fires.remove_at(k)

func _update_corpses(dt: float) -> void:
	for k in range(corpses.size() - 1, -1, -1):
		var c: Dictionary = corpses[k]
		c.t += dt
		if c.t > 86400.0 * 4.0 or (c.covered and c.t > 86400.0):
			var i: int = c.i
			if c.covered:
				terrain.marks[i] = maxi(terrain.marks[i], 1)
			else:
				drop_item(i, Items.T.BONE)
			corpses.remove_at(k)

# =================== البيولوجيا ===================
func _physiology(h: Human, dt: float, now: float, daylight: float) -> void:
	var age := h.age_years(now)
	var sleeping := h.act == Human.Act.SLEEP
	var moving := h.moving and not sleeping
	var young := age < 13.0
	# جوع/عطش
	var hunger_rate := 1.0 / (2.6 * 86400.0)
	if young: hunger_rate *= 1.4
	if moving: hunger_rate *= 1.6
	if sleeping: hunger_rate *= 0.6
	if h.pregnant_since >= 0.0: hunger_rate *= 1.35
	h.hunger = maxf(0.0, h.hunger - hunger_rate * dt)
	var t_env := temperature_at(h.pos)
	var thirst_rate := 1.0 / (1.3 * 86400.0)
	if t_env > 30.0: thirst_rate *= 1.0 + (t_env - 30.0) * 0.08
	if moving: thirst_rate *= 1.5
	if sleeping: thirst_rate *= 0.5
	h.thirst = maxf(0.0, h.thirst - thirst_rate * dt)
	# الرضيع يرضع من أمه إن كانت قريبة (بيولوجيا لا معرفة)
	if age < 2.0:
		var mom := human_by_id(h.mother_id)
		if mom != null and mom.alive and mom.pos.distance_to(h.pos) < 1.2 and mom.hunger > 0.15:
			var feed := dt / (0.5 * 3600.0)
			h.hunger = minf(1.0, h.hunger + feed)
			h.thirst = minf(1.0, h.thirst + feed)
			mom.hunger = maxf(0.0, mom.hunger - feed * 0.35)
			mom.thirst = maxf(0.0, mom.thirst - feed * 0.3)
	# طاقة
	if sleeping:
		h.energy = minf(1.0, h.energy + dt / (8.0 * 3600.0))
	else:
		var er := 1.0 / (16.0 * 3600.0)
		if moving: er *= 1.5
		if h.act == Human.Act.STRIKE or h.act == Human.Act.RUB or h.act == Human.Act.DIG: er *= 2.2
		h.energy = maxf(0.0, h.energy - er * dt)
	# حرارة الجسم
	var target := 37.0 + (t_env - 23.0) * 0.16
	if sleeping and shelter[terrain.idx(clampi(int(h.pos.x), 0, Terrain.W - 1), clampi(int(h.pos.y), 0, Terrain.H - 1))] == 0:
		target -= 0.8
	if rain_intensity > 0.3 and shelter[terrain.idx(clampi(int(h.pos.x), 0, Terrain.W - 1), clampi(int(h.pos.y), 0, Terrain.H - 1))] < 3:
		target -= 1.5 * rain_intensity
	if h.holds(Items.T.HIDE):
		target += 1.2
	if moving: target += 0.6
	h.body_temp = lerpf(h.body_temp, target, clampf(dt / 1800.0, 0.0, 1.0))
	# سُمّ ومرض
	if h.poison > 0.0:
		h.health -= h.poison * dt / (0.8 * 86400.0)
		h.poison = maxf(0.0, h.poison - dt / (1.5 * 86400.0))
	if h.sick > 0.0:
		h.health -= h.sick * dt / (4.0 * 86400.0)
		h.energy = maxf(0.0, h.energy - h.sick * dt / (30.0 * 3600.0))
		h.sick = maxf(0.0, h.sick - dt / (5.0 * 86400.0) * (1.5 if sleeping else 1.0))
	if h.injury > 0.0:
		h.injury = maxf(0.0, h.injury - dt / (10.0 * 86400.0))
		if Rng.chance(dt / (3.0 * 86400.0) * h.injury):
			h.sick = minf(1.0, h.sick + 0.3)  # التهاب
	# الجوع والعطش يقتلان
	if h.hunger <= 0.0:
		h.health -= dt / (6.0 * 86400.0)
	if h.thirst <= 0.0:
		h.health -= dt / (2.0 * 86400.0)
	if h.body_temp < 34.0:
		h.health -= (34.0 - h.body_temp) * dt / (1.5 * 86400.0)
	if h.body_temp > 40.0:
		h.health -= (h.body_temp - 40.0) * dt / (1.0 * 86400.0)
	# شفاء
	if h.hunger > 0.4 and h.thirst > 0.4 and h.sick < 0.2 and h.poison < 0.1:
		h.health = minf(1.0, h.health + dt / (9.0 * 86400.0) * (1.6 if sleeping else 1.0))
	# النار تحرق من يقف فوقها
	var fi := fire_at(terrain.idx(clampi(int(h.pos.x), 0, Terrain.W - 1), clampi(int(h.pos.y), 0, Terrain.H - 1)))
	if not fi.is_empty() and fi.fuel > 1.0:
		h.injury = minf(1.0, h.injury + dt * 0.08)
		h.health -= dt * 0.01
		h.drives[Human.D.PAIN] = 1.0
		h.drives[Human.D.FEAR] = maxf(h.drives[Human.D.FEAR], 0.8)
		Brain.learn_pain(h, "fire")
	# الحمل والولادة
	if h.pregnant_since >= 0.0 and now - h.pregnant_since > 280.0 * 86400.0:
		_give_birth(h, now)
	# الشيخوخة
	if age > h.g_lifespan * 0.85 and Rng.chance(dt / (365.0 * 86400.0) * pow((age - h.g_lifespan * 0.85) / (h.g_lifespan * 0.15), 2.0) * 3.0):
		_kill(h, "مات شيخاً هرِماً", now)
		return
	# الموت
	if h.health <= 0.0:
		var cause := "مات"
		if h.thirst <= 0.0: cause = "مات من العطش"
		elif h.hunger <= 0.0: cause = "مات من الجوع"
		elif h.poison > 0.2: cause = "مات مسموماً"
		elif h.sick > 0.3: cause = "مات مريضاً"
		elif h.body_temp < 34.5: cause = "مات من البرد"
		elif h.body_temp > 40.0: cause = "مات من الحرّ"
		elif h.injury > 0.3: cause = "مات من جراحه"
		_kill(h, cause, now)

func _give_birth(mom: Human, now: float) -> void:
	var dad := human_by_id(mom.pregnant_by)
	var baby := Human.child_of(next_id, mom, dad, now)
	next_id += 1
	mom.pregnant_since = -1.0
	mom.pregnant_by = -1
	mom.last_birth_at = now
	mom.energy = maxf(0.05, mom.energy - 0.5)
	mom.health = maxf(0.05, mom.health - 0.15)
	if Rng.chance(0.06):
		# ولادة صعبة
		mom.health -= 0.4
		mom.sick = minf(1.0, mom.sick + 0.5)
	_add_human(baby)
	born_count += 1
	baby.carried_by = mom.id
	mom.carrying_child = baby.id
	mom.add_aff(baby.id, 0.9)
	if dad != null:
		dad.add_aff(baby.id, 0.5)
	Chronicle.add(Chronicle.Kind.BIRTH, "وُلد %s لـ%s." % ["ذكرٌ" if baby.sex == Human.Sex.MALE else "أنثى", mom.label_ar()], mom.pos, 2)
	if born_count == 1:
		Chronicle.milestone("first_birth", "أول ولادة في تاريخ البشر.", mom.pos)
	human_born.emit(baby)

func _kill(h: Human, cause: String, now: float) -> void:
	if not h.alive:
		return
	h.alive = false
	h.death_cause = cause
	h.died_at = now
	died_count += 1
	var i := terrain.idx(clampi(int(h.pos.x), 0, Terrain.W - 1), clampi(int(h.pos.y), 0, Terrain.H - 1))
	drop_item(i, h.hand_l)
	drop_item(i, h.hand_r)
	h.hand_l = Items.T.NONE
	h.hand_r = Items.T.NONE
	if h.carrying_child >= 0:
		var c := human_by_id(h.carrying_child)
		if c != null:
			c.carried_by = -1
		h.carrying_child = -1
	if h.carried_by >= 0:
		var p := human_by_id(h.carried_by)
		if p != null:
			p.carrying_child = -1
	corpses.append({"i": i, "t": 0.0, "covered": false, "hid": h.id, "name": h.label_ar()})
	# الحزن ينتشر بين المقرّبين ويتعلّمون الخوف من سبب الموت
	for o in humans:
		if o.alive and o.id != h.id:
			var a := o.aff(h.id)
			if a > 0.15:
				o.grief = minf(1.0, o.grief + a)
				o.drives[Human.D.LONELY] = minf(1.0, o.drives[Human.D.LONELY] + a * 0.5)
				if o.pos.distance_to(h.pos) < PERCEPTION and h.last_meal_item >= 0 and cause.contains("مسموم"):
					o.learn("M|%d" % h.last_meal_item, -0.6)
	Chronicle.add(Chronicle.Kind.DEATH, "%s %s وعمره %s." % [h.label_ar(), cause, WorldClock.age_ar(h.age_seconds(now))], h.pos, 2)
	if died_count == 1:
		Chronicle.milestone("first_death", "أول موتٍ عرفه البشر.", h.pos)
	human_died.emit(h)

# =================== الحيوانات ===================
func _update_animals(dt: float, now: float, coarse: bool) -> void:
	var night := WorldClock.is_night()
	for k in range(animals.size() - 1, -1, -1):
		var a: Animal = animals[k]
		if not a.alive:
			a.corpse_timer += dt
			if a.corpse_timer > 86400.0 * 2.0 or a.meat_left <= 0:
				animals.remove_at(k)
			continue
		a.anim_t += dt
		a.hunger = maxf(0.0, a.hunger - dt / (2.5 * 86400.0))
		a.attack_cd = maxf(0.0, a.attack_cd - dt)
		if a.hunger <= 0.0:
			a.alive = false
			a.corpse_timer = 0.0
			continue
		# الرعي/الأكل
		var ti := Vector2i(int(a.pos.x), int(a.pos.y))
		if terrain.in_bounds(ti.x, ti.y):
			var i := terrain.idx(ti.x, ti.y)
			if not a.is_predator() and a.kind != Animal.K.FISH and a.hunger < 0.8 and (terrain.fiber[i] > 0 or terrain.grain[i] > 0 or terrain.berries[i] > 0) and Rng.chance(dt / 40.0):
				if terrain.fiber[i] > 0: terrain.fiber[i] -= 1
				elif terrain.grain[i] > 0: terrain.grain[i] -= 1
				else: terrain.berries[i] -= 1
				a.hunger = minf(1.0, a.hunger + 0.15)
		# الخوف من البشر
		var threat := Vector2.INF
		var nearest_h: Human = null
		var nd := 99.0
		for h in humans:
			if not h.alive:
				continue
			var d := h.pos.distance_to(a.pos)
			if d < nd:
				nd = d
				nearest_h = h
		if a.is_predator():
			# الذئب يطارد الفريسة أو الإنسان إذا كان جائعاً (ليلاً أكثر)
			if a.hunger < 0.5 and nearest_h != null and nd < (6.0 if night else 3.5) and a.attack_cd <= 0.0:
				var alone := true
				for h2 in humans:
					if h2.alive and h2 != nearest_h and h2.pos.distance_to(nearest_h.pos) < 2.0:
						alone = false
						break
				var fire_near := not nearest_fire(nearest_h.pos, 2.5).is_empty()
				if (alone or Rng.chance(0.2)) and not fire_near:
					a.target = nearest_h.pos
					if nd < 0.9:
						_animal_attacks_human(a, nearest_h, now)
			elif a.hunger < 0.6:
				# اصطياد فريسة
				var prey: Animal = null
				var pd := 7.0
				for b in animals:
					if b.alive and b != a and not b.is_predator() and b.kind != Animal.K.FISH and b.kind != Animal.K.BIRD:
						var d2 := b.pos.distance_to(a.pos)
						if d2 < pd:
							pd = d2
							prey = b
				if prey != null:
					a.target = prey.pos
					if pd < 0.7:
						prey.health -= dt * 0.6
						if prey.health <= 0.0:
							prey.alive = false
							prey.corpse_timer = 0.0
							a.hunger = 1.0
		else:
			var flee_d := 2.5 if a.kind != Animal.K.BIRD else 3.5
			if nearest_h != null and nd < flee_d:
				threat = nearest_h.pos
			for b in animals:
				if b.alive and b.is_predator() and b.pos.distance_to(a.pos) < 4.0:
					threat = b.pos
					break
			if threat != Vector2.INF:
				a.target = a.pos + (a.pos - threat).normalized() * 5.0
				a.fear = 1.0
			elif a.kind == Animal.K.BOAR and nearest_h != null and nd < 1.0 and a.fear > 0.5 and a.attack_cd <= 0.0:
				_animal_attacks_human(a, nearest_h, now)
		a.fear = maxf(0.0, a.fear - dt * 0.1)
		# التجوّل
		a.wander_t -= dt
		if a.wander_t <= 0.0:
			a.wander_t = Rng.randf_range(3.0, 20.0)
			if a.target.distance_to(a.pos) < 1.0 or Rng.chance(0.3):
				a.target = a.pos + Vector2(Rng.randf_range(-4, 4), Rng.randf_range(-4, 4))
		# الحركة
		var to := a.target - a.pos
		if to.length() > 0.2:
			var sp := a.speed() * (1.6 if a.fear > 0.3 else 0.5)
			var step := to.normalized() * minf(sp * dt, to.length())
			var np := a.pos + step
			var ok := false
			if a.kind == Animal.K.FISH:
				ok = terrain.is_water(int(np.x), int(np.y))
			elif a.kind == Animal.K.BIRD:
				ok = terrain.in_bounds(int(np.x), int(np.y))
			else:
				ok = terrain.is_walkable(int(np.x), int(np.y))
			if ok:
				a.pos = np
				a.facing = 1.0 if step.x >= 0 else -1.0
			else:
				a.target = a.pos + Vector2(Rng.randf_range(-3, 3), Rng.randf_range(-3, 3))

func _animal_attacks_human(a: Animal, h: Human, now: float) -> void:
	a.attack_cd = 4.0
	var dmg := a.ferocity() * a.size() * Rng.randf_range(0.5, 1.2)
	var defense := h.g_strength * Items.strike_power(h.best_weapon()) * 0.35
	dmg = maxf(0.02, dmg - defense * 0.4)
	h.injury = minf(1.0, h.injury + dmg)
	h.health -= dmg * 0.6
	h.drives[Human.D.PAIN] = 1.0
	h.drives[Human.D.FEAR] = 1.0
	h.fear_of_animals = minf(1.0, h.fear_of_animals + 0.3)
	h.danger_places.append(h.pos)
	if h.danger_places.size() > 12:
		h.danger_places.remove_at(0)
	Brain.learn_pain(h, "animal%d" % a.kind)
	last_event_pos = h.pos
	if Rng.chance(0.3):
		Chronicle.add(Chronicle.Kind.CONFLICT, "هاجم %s %s." % [a.name_ar(), h.label_ar()], h.pos, 1)
	if h.health <= 0.0:
		_kill(h, "قتله %s" % a.name_ar(), now)
		a.hunger = 1.0
		a.attack_cd = 60.0

func animal_by_id(i: int) -> Animal:
	for a in animals:
		if a.id == i:
			return a
	return null

# =================== الاستدراك بعد إغلاق التطبيق ===================
## يُعيد عدد الثواني التي يجب استدراكها
func catchup_needed(now: float) -> float:
	return maxf(0.0, now - sim_time_origin_now(now))

func sim_time_origin_now(now: float) -> float:
	return human_epoch + sim_time

# =================== حفظ ===================
func to_save() -> Dictionary:
	var hs := []
	for h in humans:
		hs.append(h.to_save())
	var as_ := []
	for a in animals:
		as_.append(a.to_save())
	var gr := {}
	for k in ground:
		gr[str(k)] = ground[k]
	return {
		"terrain": terrain.to_save(), "humans": hs, "animals": as_, "ground": gr, "fires": fires, "corpses": corpses,
		"shelter": Terrain._enc(shelter), "next_id": next_id, "weather": weather, "wt": weather_timer,
		"wind": [wind.x, wind.y], "born": born_count, "died": died_count, "epoch": human_epoch, "sim": sim_time, "stats": stats,
	}

func from_save(d: Dictionary) -> void:
	terrain.from_save(d.terrain)
	humans.clear()
	_humans_by_id.clear()
	for hd in d.humans:
		_add_human(Human.from_save(hd))
	animals.clear()
	for ad in d.animals:
		animals.append(Animal.from_save(ad))
	ground.clear()
	for k in d.ground:
		var arr: Array = []
		for v in d.ground[k]:
			arr.append(int(v))
		ground[int(k)] = arr
	fires.clear()
	for f in d.fires:
		fires.append({"i": int(f.i), "fuel": f.fuel, "age": f.age, "x": int(f.x), "y": int(f.y)})
	corpses.clear()
	for c in d.corpses:
		corpses.append({"i": int(c.i), "t": c.t, "covered": c.covered, "hid": int(c.hid), "name": c.name})
	shelter = Terrain._dec(d.shelter)
	next_id = int(d.next_id)
	weather = int(d.weather)
	weather_timer = d.wt
	wind = Vector2(d.wind[0], d.wind[1])
	born_count = int(d.born)
	died_count = int(d.died)
	human_epoch = d.epoch
	sim_time = d.sim
	for k in d.get("stats", {}):
		stats[k] = int(d.stats[k])
