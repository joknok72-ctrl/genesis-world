class_name Terrain
extends RefCounted
## Terrain — الأرض: ارتفاع، رطوبة، حرارة، أحياء (Biomes)، وموارد تتجدّد بالفصول.

const W := 128
const H := 128
const TILE_METERS := 2.0

enum B { DEEP_WATER, WATER, BEACH, GRASS, SAVANNA, FOREST, DENSE_FOREST, HILLS, MOUNTAIN, SNOW, SWAMP, DESERT }
const B_NAME_AR := {
	B.DEEP_WATER: "بحر عميق", B.WATER: "ماء", B.BEACH: "شاطئ", B.GRASS: "مرج",
	B.SAVANNA: "سافانا", B.FOREST: "غابة", B.DENSE_FOREST: "غابة كثيفة", B.HILLS: "تلال",
	B.MOUNTAIN: "جبل", B.SNOW: "قمم ثلجية", B.SWAMP: "مستنقع", B.DESERT: "صحراء",
}

var elevation := PackedFloat32Array()
var moisture := PackedFloat32Array()
var biome := PackedByteArray()
# الموارد (عدد لكل بلاطة)
var trees := PackedByteArray()       # أشجار عادية (تُسقط عيداناً)
var fruit_trees := PackedByteArray() # أشجار مثمرة
var fruit := PackedByteArray()       # ثمار ناضجة على الأشجار
var bushes := PackedByteArray()      # شجيرات توت
var berries := PackedByteArray()
var poison_bushes := PackedByteArray()
var poison_berries := PackedByteArray()
var stones := PackedByteArray()
var sticks := PackedByteArray()
var clay := PackedByteArray()
var fiber := PackedByteArray()
var roots := PackedByteArray()
var grain := PackedByteArray()
var burnt := PackedByteArray()       # أرض محروقة (تتعافى ببطء)
var marks := PackedByteArray()       # رسوم/علامات صنعها البشر على الصخور

var sea_level := 0.36
var _regrow_cursor := 0

func idx(x: int, y: int) -> int:
	return y * W + x

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H

func is_water(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	var b := biome[idx(x, y)]
	return b == B.DEEP_WATER or b == B.WATER

func is_walkable(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	var b := biome[idx(x, y)]
	return b != B.DEEP_WATER and b != B.WATER and b != B.SNOW

func biome_at(x: int, y: int) -> int:
	return biome[idx(x, y)]

func _alloc() -> void:
	var n := W * H
	elevation.resize(n); moisture.resize(n); biome.resize(n)
	for arr in [trees, fruit_trees, fruit, bushes, berries, poison_bushes, poison_berries, stones, sticks, clay, fiber, roots, grain, burnt, marks]:
		arr.resize(n)
		arr.fill(0)

func generate(seed_v: int) -> void:
	_alloc()
	var n1 := FastNoiseLite.new()
	n1.seed = seed_v
	n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n1.frequency = 0.018
	n1.fractal_octaves = 5
	n1.fractal_lacunarity = 2.1
	n1.fractal_gain = 0.5
	var n2 := FastNoiseLite.new()
	n2.seed = seed_v + 7919
	n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n2.frequency = 0.03
	n2.fractal_octaves = 3
	var n3 := FastNoiseLite.new()
	n3.seed = seed_v + 104729
	n3.noise_type = FastNoiseLite.TYPE_CELLULAR
	n3.frequency = 0.08

	var cx := W * 0.5
	var cy := H * 0.5
	for y in H:
		for x in W:
			var i := idx(x, y)
			var e := (n1.get_noise_2d(x, y) + 1.0) * 0.5
			# جزيرة/قارة: تنخفض الأرض قرب الأطراف لتحيط بها المياه
			var dx := (x - cx) / cx
			var dy := (y - cy) / cy
			var d := sqrt(dx * dx + dy * dy)
			e = e * (1.0 - smoothstep(0.62, 1.05, d)) + 0.02
			# نهر متعرّج
			var river := absf(n2.get_noise_2d(x * 0.6, y * 0.6))
			if river < 0.035 and e > sea_level and e < 0.72:
				e = sea_level - 0.02
			elevation[i] = clampf(e, 0.0, 1.0)
			moisture[i] = clampf((n2.get_noise_2d(x + 500, y + 500) + 1.0) * 0.5 + (0.3 if river < 0.09 else 0.0), 0.0, 1.0)

	# تصنيف الأحياء
	for y in H:
		for x in W:
			var i := idx(x, y)
			var e := elevation[i]
			var m := moisture[i]
			var lat := absf((y - cy) / cy)  # 0 خط الاستواء، 1 القطب
			var b: int
			if e < sea_level - 0.08:
				b = B.DEEP_WATER
			elif e < sea_level:
				b = B.WATER
			elif e < sea_level + 0.03:
				b = B.BEACH
			elif e > 0.86:
				b = B.SNOW
			elif e > 0.76:
				b = B.MOUNTAIN
			elif e > 0.66:
				b = B.HILLS
			elif m > 0.78 and e < sea_level + 0.1:
				b = B.SWAMP
			elif m < 0.22 and lat < 0.45:
				b = B.DESERT
			elif m > 0.66:
				b = B.DENSE_FOREST
			elif m > 0.5:
				b = B.FOREST
			elif m > 0.36:
				b = B.GRASS
			else:
				b = B.SAVANNA
			if lat > 0.9 and b != B.DEEP_WATER and b != B.WATER:
				b = B.SNOW
			biome[i] = b

	# توزيع الموارد الأولي
	for y in H:
		for x in W:
			var i := idx(x, y)
			var b := biome[i]
			var cell := (n3.get_noise_2d(x, y) + 1.0) * 0.5
			match b:
				B.GRASS:
					fiber[i] = Rng.randi_range(1, 4)
					if Rng.chance(0.06): fruit_trees[i] = 1
					if Rng.chance(0.08): bushes[i] = 1
					if Rng.chance(0.03): poison_bushes[i] = 1
					if Rng.chance(0.07): roots[i] = Rng.randi_range(1, 3)
					if Rng.chance(0.15): grain[i] = Rng.randi_range(1, 4)
					if Rng.chance(0.05): stones[i] = 1
					if Rng.chance(0.04): trees[i] = 1
				B.SAVANNA:
					fiber[i] = Rng.randi_range(0, 3)
					if Rng.chance(0.03): trees[i] = 1
					if Rng.chance(0.02): fruit_trees[i] = 1
					if Rng.chance(0.2): grain[i] = Rng.randi_range(1, 3)
					if Rng.chance(0.08): stones[i] = Rng.randi_range(1, 2)
					if Rng.chance(0.04): roots[i] = 1
				B.FOREST:
					trees[i] = 1 if Rng.chance(0.5) else 0
					if Rng.chance(0.12): fruit_trees[i] = 1
					if Rng.chance(0.12): bushes[i] = 1
					if Rng.chance(0.06): poison_bushes[i] = 1
					if Rng.chance(0.1): roots[i] = Rng.randi_range(1, 2)
					sticks[i] = Rng.randi_range(0, 2)
					fiber[i] = Rng.randi_range(0, 2)
					if Rng.chance(0.04): stones[i] = 1
				B.DENSE_FOREST:
					trees[i] = Rng.randi_range(1, 2)
					if Rng.chance(0.15): fruit_trees[i] = 1
					if Rng.chance(0.1): bushes[i] = 1
					if Rng.chance(0.08): poison_bushes[i] = 1
					sticks[i] = Rng.randi_range(1, 3)
					if Rng.chance(0.08): roots[i] = 1
				B.HILLS:
					stones[i] = Rng.randi_range(1, 4)
					if Rng.chance(0.08): trees[i] = 1
					if Rng.chance(0.03): bushes[i] = 1
					fiber[i] = Rng.randi_range(0, 1)
				B.MOUNTAIN:
					stones[i] = Rng.randi_range(2, 6)
				B.BEACH:
					if Rng.chance(0.3): stones[i] = Rng.randi_range(1, 2)
					if Rng.chance(0.25): clay[i] = Rng.randi_range(1, 3)
				B.SWAMP:
					clay[i] = Rng.randi_range(1, 4)
					fiber[i] = Rng.randi_range(2, 5)
					if Rng.chance(0.1): trees[i] = 1
					if Rng.chance(0.08): poison_bushes[i] = 1
					if Rng.chance(0.06): roots[i] = 2
				B.DESERT:
					if Rng.chance(0.1): stones[i] = Rng.randi_range(1, 3)
					if Rng.chance(0.01): fruit_trees[i] = 1
					if Rng.chance(0.02): roots[i] = 1
			if cell > 0.85 and (b == B.GRASS or b == B.FOREST):
				stones[i] += 1
			# طين قرب أي ماء
			if b != B.WATER and b != B.DEEP_WATER and _near_water(x, y, 1) and Rng.chance(0.4):
				clay[i] += Rng.randi_range(1, 2)
			# ثمار وتوت في البداية
			if fruit_trees[i] > 0: fruit[i] = Rng.randi_range(2, 6)
			if bushes[i] > 0: berries[i] = Rng.randi_range(2, 7)
			if poison_bushes[i] > 0: poison_berries[i] = Rng.randi_range(2, 6)

func _near_water(x: int, y: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if is_water(x + dx, y + dy):
				return true
	return false

func nearest_water(x: int, y: int, max_r: int = 30) -> Vector2i:
	for r in range(1, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var nx := x + dx
				var ny := y + dy
				if in_bounds(nx, ny) and biome[idx(nx, ny)] == B.WATER:
					return Vector2i(nx, ny)
	return Vector2i(-1, -1)

## درجة الحرارة بالمئوية عند بلاطة في هذه اللحظة
func temperature(x: int, y: int, season: int, daylight: float, day_of_year: int) -> float:
	var i := idx(x, y)
	var lat := absf((y - H * 0.5) / (H * 0.5))
	var base := 30.0 - lat * 34.0
	var season_wave := 9.0 * cos(TAU * float(day_of_year) / 365.0 - PI * 0.5) # ربيع=0، صيف=+، شتاء=-
	var alt := -22.0 * maxf(0.0, elevation[i] - sea_level) / (1.0 - sea_level)
	var diurnal := (daylight - 0.5) * 12.0
	var wet := -3.0 * moisture[i]
	var b := biome[i]
	if b == B.DESERT:
		diurnal *= 1.8
		wet = 4.0
	return base + season_wave + alt + diurnal + wet

## ---- التجدد الموسمي (يُستدعى بضع مئات بلاطات في الثانية) ----
func regrow_step(count: int, season: int, dt_hours: float) -> void:
	var n := W * H
	var growth: float = [1.0, 0.7, 0.3, 0.05][season]
	for k in count:
		var i := _regrow_cursor
		_regrow_cursor = (_regrow_cursor + 1) % n
		var b := biome[i]
		if b == B.WATER or b == B.DEEP_WATER or b == B.SNOW:
			continue
		var p: float = growth * dt_hours
		if burnt[i] > 0:
			if Rng.chance(0.06 * dt_hours):
				burnt[i] -= 1
			continue
		if fruit_trees[i] > 0 and fruit[i] < 8 and Rng.chance(0.08 * p):
			fruit[i] += 1
		if bushes[i] > 0 and berries[i] < 9 and Rng.chance(0.1 * p):
			berries[i] += 1
		if poison_bushes[i] > 0 and poison_berries[i] < 8 and Rng.chance(0.1 * p):
			poison_berries[i] += 1
		if trees[i] > 0 and sticks[i] < 5 and Rng.chance(0.05 * dt_hours):
			sticks[i] += 1
		if (b == B.GRASS or b == B.SAVANNA or b == B.SWAMP) and fiber[i] < 6 and Rng.chance(0.06 * p):
			fiber[i] += 1
		if (b == B.GRASS or b == B.SAVANNA) and grain[i] < 6 and Rng.chance(0.04 * p):
			grain[i] += 1
		if roots[i] < 3 and (b == B.GRASS or b == B.FOREST or b == B.SWAMP) and Rng.chance(0.02 * p):
			roots[i] += 1
		# انتشار بطيء للأشجار والشجيرات
		if (trees[i] > 0 or fruit_trees[i] > 0) and Rng.chance(0.002 * p):
			var nx := (i % W) + Rng.randi_range(-1, 1)
			var ny := (i / W) + Rng.randi_range(-1, 1)
			if in_bounds(nx, ny):
				var j := idx(nx, ny)
				var nb := biome[j]
				if (nb == B.GRASS or nb == B.FOREST or nb == B.DENSE_FOREST or nb == B.SAVANNA) and trees[j] + fruit_trees[j] < 2 and burnt[j] == 0:
					if fruit_trees[i] > 0 and Rng.chance(0.5):
						fruit_trees[j] += 1
					else:
						trees[j] += 1

func burn_tile(i: int) -> void:
	burnt[i] = 6
	trees[i] = 0; fruit_trees[i] = 0; fruit[i] = 0; bushes[i] = 0; berries[i] = 0
	poison_bushes[i] = 0; poison_berries[i] = 0; sticks[i] = 0; fiber[i] = 0; grain[i] = 0

func flammability(i: int) -> float:
	return clampf(trees[i] * 0.25 + fruit_trees[i] * 0.2 + bushes[i] * 0.15 + fiber[i] * 0.05 + sticks[i] * 0.05 + grain[i] * 0.06, 0.0, 1.0)

## ---- حفظ ----
func to_save() -> Dictionary:
	return {
		"sea": sea_level,
		"elev": _enc(elevation), "moist": _enc(moisture), "biome": _enc(biome),
		"trees": _enc(trees), "ftrees": _enc(fruit_trees), "fruit": _enc(fruit), "bushes": _enc(bushes),
		"berries": _enc(berries), "pbush": _enc(poison_bushes), "pberr": _enc(poison_berries),
		"stones": _enc(stones), "sticks": _enc(sticks), "clay": _enc(clay), "fiber": _enc(fiber),
		"roots": _enc(roots), "grain": _enc(grain), "burnt": _enc(burnt), "marks": _enc(marks),
	}

func from_save(d: Dictionary) -> void:
	_alloc()
	sea_level = d.get("sea", sea_level)
	elevation = _dec(d["elev"]); moisture = _dec(d["moist"]); biome = _dec(d["biome"])
	trees = _dec(d["trees"]); fruit_trees = _dec(d["ftrees"]); fruit = _dec(d["fruit"]); bushes = _dec(d["bushes"])
	berries = _dec(d["berries"]); poison_bushes = _dec(d["pbush"]); poison_berries = _dec(d["pberr"])
	stones = _dec(d["stones"]); sticks = _dec(d["sticks"]); clay = _dec(d["clay"]); fiber = _dec(d["fiber"])
	roots = _dec(d["roots"]); grain = _dec(d["grain"]); burnt = _dec(d["burnt"]); marks = _dec(d["marks"])

static func _enc(arr: Variant) -> String:
	return Marshalls.raw_to_base64(var_to_bytes(arr).compress(FileAccess.COMPRESSION_ZSTD)) + "|" + str(var_to_bytes(arr).size())

static func _dec(s: String) -> Variant:
	var parts := s.split("|")
	var raw := Marshalls.base64_to_raw(parts[0]).decompress(int(parts[1]), FileAccess.COMPRESSION_ZSTD)
	return bytes_to_var(raw)
