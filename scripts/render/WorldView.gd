class_name WorldView
extends Node2D
## WorldView — يرسم العالم: الأرض، الأشجار، الماء، البشر، الحيوانات، النار، الطقس، الليل والنهار.
## يُحدَّث نسيج الأرض مرّة كل بضع ثوانٍ فقط (أداء الهاتف)، والباقي يُرسم كل إطار في نطاق الكاميرا.

const TILE := 64.0
var world: World
var cam: Camera2D
var terrain_img: Image
var terrain_tex: ImageTexture
var overlay_img: Image
var overlay_tex: ImageTexture
var _terrain_dirty := true
var _overlay_timer := 0.0
var selected_id := -1
var time_acc := 0.0
var rain_drops: Array = []
var ripples: Array = []          # [pos, t]
var pulses: Array = []           # حلقات عند الأحداث [pos, t, color]
var show_labels := true
var show_thoughts := true
var reduce_effects := false

const BIOME_COL := {
	Terrain.B.DEEP_WATER: Color(0.07, 0.18, 0.4), Terrain.B.WATER: Color(0.15, 0.36, 0.62), Terrain.B.BEACH: Color(0.82, 0.76, 0.55),
	Terrain.B.GRASS: Color(0.36, 0.58, 0.28), Terrain.B.SAVANNA: Color(0.62, 0.6, 0.3), Terrain.B.FOREST: Color(0.22, 0.44, 0.2),
	Terrain.B.DENSE_FOREST: Color(0.14, 0.33, 0.15), Terrain.B.HILLS: Color(0.5, 0.48, 0.38), Terrain.B.MOUNTAIN: Color(0.48, 0.45, 0.45),
	Terrain.B.SNOW: Color(0.92, 0.94, 0.97), Terrain.B.SWAMP: Color(0.3, 0.4, 0.28), Terrain.B.DESERT: Color(0.85, 0.74, 0.48),
}

func setup(w: World, c: Camera2D) -> void:
	world = w
	cam = c
	terrain_img = Image.create(Terrain.W, Terrain.H, false, Image.FORMAT_RGBA8)
	overlay_img = Image.create(Terrain.W, Terrain.H, false, Image.FORMAT_RGBA8)
	_paint_terrain()
	terrain_tex = ImageTexture.create_from_image(terrain_img)
	overlay_tex = ImageTexture.create_from_image(overlay_img)
	_paint_overlay()
	for i in 120:
		rain_drops.append(Vector2(randf(), randf()))

func _paint_terrain() -> void:
	var t := world.terrain
	var n := FastNoiseLite.new()
	n.seed = Rng.seed_value + 3
	n.frequency = 0.25
	for y in Terrain.H:
		for x in Terrain.W:
			var i := t.idx(x, y)
			var b := t.biome[i]
			var col: Color = BIOME_COL[b]
			var e := t.elevation[i]
			var shade := 0.85 + 0.3 * (e - 0.4)
			var grain := 1.0 + n.get_noise_2d(x, y) * 0.08
			col = Color(col.r * shade * grain, col.g * shade * grain, col.b * shade * grain, 1.0)
			# ظلال الانحدار
			if x > 0:
				var de := e - t.elevation[t.idx(x - 1, y)]
				col = col.lightened(clampf(de * 3.0, -0.15, 0.15))
			terrain_img.set_pixel(x, y, col)
	_terrain_dirty = false

func _paint_overlay() -> void:
	var t := world.terrain
	for y in Terrain.H:
		for x in Terrain.W:
			var i := t.idx(x, y)
			var c := Color(0, 0, 0, 0)
			if t.burnt[i] > 0:
				c = Color(0.1, 0.08, 0.06, 0.6 * t.burnt[i] / 6.0)
			elif t.trees[i] + t.fruit_trees[i] > 0:
				c = Color(0.1, 0.25, 0.08, 0.08 * mini(3, t.trees[i] + t.fruit_trees[i]))
			overlay_img.set_pixel(x, y, c)
	overlay_tex.update(overlay_img)

func _process(delta: float) -> void:
	time_acc += delta
	_overlay_timer += delta
	if _overlay_timer > 5.0:
		_overlay_timer = 0.0
		_paint_overlay()
	for k in range(ripples.size() - 1, -1, -1):
		ripples[k][1] += delta
		if ripples[k][1] > 1.5:
			ripples.remove_at(k)
	for k in range(pulses.size() - 1, -1, -1):
		pulses[k][1] += delta
		if pulses[k][1] > 2.0:
			pulses.remove_at(k)
	queue_redraw()

func pulse(pos: Vector2, col: Color) -> void:
	pulses.append([pos, 0.0, col])

func world_to_screen(p: Vector2) -> Vector2:
	return p * TILE

func visible_rect_tiles() -> Rect2:
	var vp := get_viewport_rect().size
	var half := vp / cam.zoom * 0.5
	var tl := (cam.global_position - half) / TILE
	var br := (cam.global_position + half) / TILE
	return Rect2(tl, br - tl).grow(1.5)

# ============================ الرسم ============================
func _draw() -> void:
	if world == null:
		return
	var vis := visible_rect_tiles()
	var daylight := WorldClock.daylight()
	var zoom: float = cam.zoom.x
	# الأرض
	draw_texture_rect(terrain_tex, Rect2(Vector2.ZERO, Vector2(Terrain.W, Terrain.H) * TILE), false)
	draw_texture_rect(overlay_tex, Rect2(Vector2.ZERO, Vector2(Terrain.W, Terrain.H) * TILE), false)
	var x0 := maxi(0, int(vis.position.x))
	var y0 := maxi(0, int(vis.position.y))
	var x1 := mini(Terrain.W - 1, int(vis.end.x))
	var y1 := mini(Terrain.H - 1, int(vis.end.y))
	var detail := zoom > 0.28
	var t := world.terrain
	# الماء المتحرّك + الشاطئ
	if zoom > 0.18:
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var i := t.idx(x, y)
				var b := t.biome[i]
				if b == Terrain.B.WATER or b == Terrain.B.DEEP_WATER:
					var ph := sin(time_acc * 1.2 + x * 0.9 + y * 1.3) * 0.5 + 0.5
					var p := Vector2(x, y) * TILE
					draw_rect(Rect2(p + Vector2(8, 20 + ph * 14), Vector2(TILE - 16, 3)), Color(1, 1, 1, 0.08 + 0.08 * ph))
					if b == Terrain.B.WATER and detail:
						draw_rect(Rect2(p + Vector2(20, 40 - ph * 10), Vector2(24, 2)), Color(1, 1, 1, 0.1))
	# الموارد (تفاصيل)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := t.idx(x, y)
			var p := Vector2(x, y) * TILE
			var b := t.biome[i]
			var h01 := fmod(float(i) * 0.6180339, 1.0)
			if t.burnt[i] > 0:
				draw_rect(Rect2(p + Vector2(10, 10), Vector2(TILE - 20, TILE - 20)), Color(0.08, 0.06, 0.05, 0.5))
				continue
			if b == Terrain.B.MOUNTAIN or b == Terrain.B.HILLS:
				_draw_rock(p, h01, b == Terrain.B.MOUNTAIN)
			if t.marks[i] > 0 and detail:
				_draw_marks(p, t.marks[i], h01)
			if world.shelter[i] > 0:
				_draw_shelter(p, world.shelter[i], h01)
			if t.trees[i] > 0:
				_draw_tree(p + Vector2(TILE * (0.3 + h01 * 0.4), TILE * 0.62), 1.0 + t.trees[i] * 0.15, false, 0, daylight, i)
			if t.fruit_trees[i] > 0:
				_draw_tree(p + Vector2(TILE * (0.7 - h01 * 0.4), TILE * 0.68), 0.95, true, t.fruit[i], daylight, i)
			if detail:
				if t.bushes[i] > 0:
					_draw_bush(p + Vector2(TILE * 0.25, TILE * 0.8), Color(0.2, 0.42, 0.18), t.berries[i], Color(0.45, 0.2, 0.7))
				if t.poison_bushes[i] > 0:
					_draw_bush(p + Vector2(TILE * 0.78, TILE * 0.3), Color(0.25, 0.4, 0.22), t.poison_berries[i], Color(0.9, 0.15, 0.4))
				if t.stones[i] > 0 and b != Terrain.B.MOUNTAIN:
					for k in mini(3, t.stones[i]):
						var sp := p + Vector2(12 + k * 16 + h01 * 10, 44 + fmod(h01 * 7 * (k + 1), 1.0) * 10)
						draw_circle(sp, 4.5, Color(0.4, 0.4, 0.42))
						draw_circle(sp + Vector2(-1, -1), 3.0, Color(0.6, 0.6, 0.63))
				if t.sticks[i] > 0:
					draw_line(p + Vector2(14, 50), p + Vector2(30, 56), Color(0.45, 0.3, 0.15), 2.5)
				if t.clay[i] > 0:
					draw_circle(p + Vector2(48, 50), 6.0, Color(0.55, 0.4, 0.32, 0.8))
				if t.fiber[i] > 2 and (b == Terrain.B.GRASS or b == Terrain.B.SAVANNA or b == Terrain.B.SWAMP):
					for k in 3:
						var gx := p.x + 8 + k * 18 + h01 * 8
						draw_line(Vector2(gx, p.y + 40), Vector2(gx + 2 + sin(time_acc * 2 + k) * 2, p.y + 28), Color(0.45, 0.62, 0.25), 1.5)
				if t.grain[i] > 0:
					for k in mini(3, t.grain[i]):
						var gx := p.x + 40 + k * 7 + h01 * 6
						draw_line(Vector2(gx, p.y + 30), Vector2(gx + 1 + sin(time_acc * 2 + k) * 1.5, p.y + 14), Color(0.85, 0.75, 0.35), 1.5)
						draw_circle(Vector2(gx + 1, p.y + 13), 2.5, Color(0.9, 0.8, 0.4))
				if t.roots[i] > 0:
					draw_arc(p + Vector2(20, 22), 5.0, 0, PI, 8, Color(0.7, 0.55, 0.3), 2.0)
			# الأشياء الملقاة على الأرض
			if world.ground.has(i):
				var arr: Array = world.ground[i]
				for k in mini(arr.size(), 6):
					var ip := p + Vector2(10 + (k % 3) * 18, 14 + (k / 3) * 14)
					_draw_item(ip, arr[k], 1.0)
	# الجثث
	for cp in world.corpses:
		var p := Vector2((cp.i % Terrain.W) + 0.5, (cp.i / Terrain.W) + 0.5) * TILE
		if not vis.has_point(p / TILE):
			continue
		if cp.covered:
			for k in 5:
				draw_circle(p + Vector2(-12 + k * 6, 8 - (k % 2) * 4), 5.0, Color(0.45, 0.42, 0.4))
			draw_circle(p + Vector2(0, 4), 5.0, Color(0.5, 0.47, 0.45))
		else:
			draw_oval(p + Vector2(0, 6), Vector2(16, 7), Color(0.55, 0.45, 0.4))
			draw_circle(p + Vector2(-14, 4), 5.0, Color(0.75, 0.62, 0.52))
	# النار
	for f in world.fires:
		var p := Vector2(f.x + 0.5, f.y + 0.5) * TILE
		if vis.has_point(p / TILE):
			_draw_fire(p, clampf(f.fuel / 12.0, 0.25, 1.4))
	# الحيوانات
	for a in world.animals:
		if vis.has_point(a.pos):
			_draw_animal(a)
	# البشر (الأحياء فوق الجميع)
	var now := WorldClock.world_seconds
	for h in world.humans:
		if h.alive and vis.has_point(h.pos) and h.carried_by < 0:
			_draw_human(h, now, zoom)
	# نبضات الأحداث
	for pl in pulses:
		var pp: Vector2 = pl[0] * TILE
		var k: float = pl[1] / 2.0
		draw_arc(pp, 20.0 + k * 90.0, 0, TAU, 32, Color(pl[2].r, pl[2].g, pl[2].b, (1.0 - k) * 0.8), 3.0 * (1.0 - k) + 1.0)
	# الليل والطقس
	_draw_atmosphere(vis, daylight)

func draw_oval(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := float(i) / 20.0 * TAU
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)

func _draw_rock(p: Vector2, h01: float, big: bool) -> void:
	var base := p + Vector2(TILE * 0.5, TILE * 0.7)
	var s := (0.55 if big else 0.4) * TILE
	var pts := PackedVector2Array([base + Vector2(-s * 0.55, 0), base + Vector2(-s * 0.2, -s * (0.7 + h01 * 0.3)), base + Vector2(s * 0.15, -s * 0.5), base + Vector2(s * 0.5, 0)])
	draw_colored_polygon(pts, Color(0.42, 0.4, 0.4) if big else Color(0.5, 0.47, 0.4))
	draw_polyline(pts, Color(0.62, 0.6, 0.6), 1.5)
	if big and h01 > 0.5:
		draw_colored_polygon(PackedVector2Array([base + Vector2(-s * 0.25, -s * 0.62), base + Vector2(-s * 0.2, -s * (0.7 + h01 * 0.3)), base + Vector2(0, -s * 0.6)]), Color(0.95, 0.96, 1.0))

func _draw_tree(base: Vector2, scale: float, fruity: bool, fruit_n: int, daylight: float, i: int) -> void:
	var sway := sin(time_acc * 1.3 + i * 0.7) * 1.5 * world.wind.length()
	var trunk_h := 20.0 * scale
	draw_line(base, base + Vector2(sway * 0.4, -trunk_h), Color(0.35, 0.24, 0.12), 4.0 * scale)
	var crown := base + Vector2(sway, -trunk_h - 8 * scale)
	var col := Color(0.2, 0.5, 0.2) if not fruity else Color(0.26, 0.55, 0.24)
	var season := WorldClock.season()
	if season == WorldClock.Season.AUTUMN:
		col = Color(0.7, 0.45, 0.15) if not fruity else Color(0.6, 0.5, 0.2)
	elif season == WorldClock.Season.WINTER:
		col = Color(0.3, 0.38, 0.28)
	draw_circle(crown + Vector2(0, 2), 13.0 * scale, col.darkened(0.25))
	draw_circle(crown + Vector2(-4, -3), 10.0 * scale, col)
	draw_circle(crown + Vector2(6, -2), 9.0 * scale, col.lightened(0.08))
	if fruity and fruit_n > 0:
		for k in mini(fruit_n, 5):
			var fp := crown + Vector2(cos(k * 1.3) * 8, sin(k * 2.1) * 7)
			draw_circle(fp, 2.5, Color(0.95, 0.35, 0.25))

func _draw_bush(p: Vector2, col: Color, berries: int, bcol: Color) -> void:
	draw_circle(p, 8.0, col.darkened(0.2))
	draw_circle(p + Vector2(-4, -3), 6.0, col)
	draw_circle(p + Vector2(4, -2), 5.5, col.lightened(0.1))
	for k in mini(berries, 4):
		draw_circle(p + Vector2(-5 + k * 3.5, -4 + (k % 2) * 4), 1.8, bcol)

func _draw_shelter(p: Vector2, n: int, h01: float) -> void:
	var c := p + Vector2(TILE * 0.5, TILE * 0.55)
	var s := 10.0 + n * 3.0
	if n >= 3:
		var pts := PackedVector2Array([c + Vector2(-s, 6), c + Vector2(0, -s * 1.1), c + Vector2(s, 6)])
		draw_colored_polygon(pts, Color(0.5, 0.36, 0.2))
		draw_polyline(pts, Color(0.35, 0.24, 0.12), 2.0)
		for k in 4:
			draw_line(c + Vector2(-s + k * (s * 0.5), 6), c + Vector2(0, -s * 1.1), Color(0.4, 0.28, 0.14), 1.2)
	else:
		for k in n * 2:
			draw_line(c + Vector2(-8 + k * 4, 4), c + Vector2(-4 + k * 3, -6 - k), Color(0.45, 0.3, 0.15), 2.0)

func _draw_marks(p: Vector2, n: int, h01: float) -> void:
	var c := p + Vector2(TILE * 0.5, TILE * 0.35)
	for k in mini(n, 6):
		var col := Color(0.8, 0.3, 0.2) if k % 2 == 0 else Color(0.15, 0.12, 0.1)
		var o := Vector2(-10 + k * 4, -4 + (k % 3) * 4)
		draw_line(c + o, c + o + Vector2(3, -8 + (k % 2) * 4), col, 2.0)
		if k % 3 == 0:
			draw_circle(c + o + Vector2(2, 2), 2.0, col)

func _draw_item(p: Vector2, item: int, s: float) -> void:
	var col: Color = Items.COLOR.get(item, Color.WHITE)
	match item:
		Items.T.STICK, Items.T.CLUB, Items.T.SPEAR:
			draw_line(p + Vector2(-7, 3) * s, p + Vector2(7, -3) * s, col, 2.5 * s)
			if item == Items.T.SPEAR:
				draw_circle(p + Vector2(7, -3) * s, 2.2 * s, Items.COLOR[Items.T.SHARP_STONE])
			if item == Items.T.CLUB:
				draw_circle(p + Vector2(7, -3) * s, 3.0 * s, col.darkened(0.2))
		Items.T.STONE, Items.T.SHARP_STONE:
			var pts := PackedVector2Array([p + Vector2(-5, 3) * s, p + Vector2(-3, -4) * s, p + Vector2(4, -3) * s, p + Vector2(5, 3) * s])
			draw_colored_polygon(pts, col)
			if item == Items.T.SHARP_STONE:
				draw_line(p + Vector2(-3, -4) * s, p + Vector2(5, 3) * s, Color(1, 1, 1, 0.6), 1.0)
		Items.T.ROPE:
			draw_arc(p, 5.0 * s, 0, TAU, 12, col, 2.0)
		Items.T.HIDE:
			draw_colored_polygon(PackedVector2Array([p + Vector2(-6, -4) * s, p + Vector2(6, -3) * s, p + Vector2(5, 5) * s, p + Vector2(-5, 4) * s]), col)
		Items.T.POT:
			draw_colored_polygon(PackedVector2Array([p + Vector2(-4, -5) * s, p + Vector2(4, -5) * s, p + Vector2(6, 4) * s, p + Vector2(-6, 4) * s]), col)
		Items.T.BONE, Items.T.BONE_NEEDLE:
			draw_line(p + Vector2(-6, 2) * s, p + Vector2(6, -2) * s, col, 2.0 * s)
			if item == Items.T.BONE:
				draw_circle(p + Vector2(-6, 2) * s, 2.0, col)
				draw_circle(p + Vector2(6, -2) * s, 2.0, col)
		_:
			draw_circle(p, 4.5 * s, col)
			draw_circle(p + Vector2(-1.5, -1.5) * s, 1.5 * s, Color(1, 1, 1, 0.4))

func _draw_fire(p: Vector2, s: float) -> void:
	var fl := 0.8 + 0.2 * sin(time_acc * 17.0 + p.x)
	if not reduce_effects:
		draw_circle(p, 60.0 * s * fl, Color(1.0, 0.6, 0.2, 0.08))
		draw_circle(p, 34.0 * s * fl, Color(1.0, 0.7, 0.3, 0.12))
	# حطب
	draw_line(p + Vector2(-10, 6), p + Vector2(10, 2), Color(0.3, 0.2, 0.1), 4.0)
	draw_line(p + Vector2(-8, 1), p + Vector2(9, 7), Color(0.35, 0.22, 0.1), 4.0)
	# ألسنة
	for k in 3:
		var ph := time_acc * (9.0 + k * 3.0) + k * 2.1
		var hgt := (14.0 + 8.0 * sin(ph)) * s
		var ox := sin(ph * 0.7) * 4.0
		var pts := PackedVector2Array([p + Vector2(-8 + k * 6, 4), p + Vector2(-4 + k * 6 + ox, -hgt), p + Vector2(k * 6, 4)])
		draw_colored_polygon(pts, Color(1.0, 0.45 + k * 0.15, 0.1, 0.85))
	draw_circle(p + Vector2(0, 0), 5.0 * s, Color(1.0, 0.9, 0.5, 0.9))
	# دخان
	if not reduce_effects:
		for k in 3:
			var ph2 := fmod(time_acc * 0.5 + k * 0.33, 1.0)
			draw_circle(p + Vector2(sin(ph2 * 6.0 + k) * 6.0, -20 - ph2 * 40.0), 5.0 + ph2 * 8.0, Color(0.3, 0.3, 0.3, (1.0 - ph2) * 0.25))

func _draw_animal(a: Animal) -> void:
	var p := a.pos * TILE
	var col: Color = Animal.COLOR[a.kind]
	var s := 0.6 + a.size() * 0.9
	var bob := sin(a.anim_t * 8.0) * 1.5 if a.fear > 0.3 else sin(a.anim_t * 2.0) * 0.5
	if not a.alive:
		draw_oval(p + Vector2(0, 4), Vector2(12 * s, 5 * s), col.darkened(0.3))
		draw_circle(p + Vector2(-10 * s, 3), 4 * s, col.darkened(0.2))
		return
	var f := a.facing
	match a.kind:
		Animal.K.BIRD:
			var w := sin(a.anim_t * 12.0) * 6.0
			draw_line(p + Vector2(-8, w), p, col, 2.0)
			draw_line(p, p + Vector2(8, w), col, 2.0)
			draw_circle(p, 2.5, col)
		Animal.K.FISH:
			draw_oval(p, Vector2(7, 3), col)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-7 * f, 0), p + Vector2(-11 * f, -4), p + Vector2(-11 * f, 4)]), col)
		_:
			draw_oval(p + Vector2(0, 6), Vector2(10 * s, 3), Color(0, 0, 0, 0.25))
			# أرجل
			for k in 2:
				var lx := (-6 + k * 12) * s
				var kick := sin(a.anim_t * 10.0 + k * PI) * 3.0 if a.fear > 0.3 or a.target.distance_to(a.pos) > 0.3 else 0.0
				draw_line(p + Vector2(lx, 2 + bob), p + Vector2(lx + kick, 8), col.darkened(0.3), 2.0 * s)
			draw_oval(p + Vector2(0, bob), Vector2(11 * s, 6 * s), col)
			var head := p + Vector2(11 * s * f, -4 * s + bob)
			draw_circle(head, 4.5 * s, col.lightened(0.05))
			draw_circle(head + Vector2(2 * f, -1), 1.0, Color(0.05, 0.05, 0.05))
			if a.kind == Animal.K.DEER or a.kind == Animal.K.GOAT:
				draw_line(head + Vector2(0, -4 * s), head + Vector2(-3 * f, -10 * s), Color(0.4, 0.3, 0.2), 1.5)
				draw_line(head + Vector2(1, -4 * s), head + Vector2(3 * f, -10 * s), Color(0.4, 0.3, 0.2), 1.5)
			if a.kind == Animal.K.WOLF:
				draw_colored_polygon(PackedVector2Array([head + Vector2(-2, -4 * s), head + Vector2(0, -9 * s), head + Vector2(2, -4 * s)]), col)
				draw_line(p + Vector2(-11 * s * f, -2), p + Vector2(-17 * s * f, -8), col, 2.5)
			if a.kind == Animal.K.RABBIT:
				draw_line(head + Vector2(-1, -4), head + Vector2(-2, -11), col, 2.0)
				draw_line(head + Vector2(1, -4), head + Vector2(2, -11), col, 2.0)
			if a.kind == Animal.K.BOAR:
				draw_line(head + Vector2(3 * f, 1), head + Vector2(6 * f, -2), Color(0.95, 0.93, 0.85), 1.5)

func _draw_human(h: Human, now: float, zoom: float) -> void:
	var p := h.pos * TILE
	var sc := h.body_scale(now) * 1.0
	var skin := Color(0.95, 0.8, 0.65).lerp(Color(0.35, 0.22, 0.12), h.g_skin)
	var hair := Color(0.1, 0.08, 0.05).lerp(Color(0.6, 0.4, 0.2), h.g_hair)
	if h.is_elder(now):
		hair = hair.lerp(Color(0.85, 0.85, 0.85), 0.8)
	var f := h.facing
	var sleeping := h.act == Human.Act.SLEEP
	var walk := sin(h.anim_t * 9.0) if h.moving else 0.0
	var H := 30.0 * sc
	# ظل
	draw_oval(p + Vector2(0, 4), Vector2(9 * sc, 3.5), Color(0, 0, 0, 0.3))
	if sleeping:
		draw_oval(p + Vector2(0, -2), Vector2(13 * sc, 5 * sc), skin)
		draw_circle(p + Vector2(-12 * sc, -3), 5 * sc, skin)
		draw_circle(p + Vector2(-13 * sc, -5), 4.5 * sc, hair)
		var zz := fmod(h.anim_t, 2.0)
		draw_string(ThemeDB.fallback_font, p + Vector2(4, -10 - zz * 8), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 1.0 - zz * 0.5))
	else:
		var sel := h.id == selected_id
		if sel:
			draw_arc(p + Vector2(0, 3), 18.0, 0, TAU, 32, Color(1.0, 0.85, 0.4, 0.9), 2.5)
			draw_arc(p + Vector2(0, 3), 22.0 + sin(time_acc * 4.0) * 2.0, 0, TAU, 32, Color(1.0, 0.85, 0.4, 0.35), 1.5)
		# أرجل
		draw_line(p, p + Vector2(-4 * sc + walk * 4, 4), skin.darkened(0.15), 3.0 * sc)
		draw_line(p, p + Vector2(4 * sc - walk * 4, 4), skin.darkened(0.15), 3.0 * sc)
		# جسد
		var hip := p + Vector2(0, -2)
		var shoulder := p + Vector2(0, -H * 0.62)
		var torso_w := 5.0 * sc * (0.85 + h.g_size * 0.3)
		if h.pregnant_since >= 0.0:
			torso_w *= 1.3
		draw_line(hip, shoulder, skin, torso_w * 1.6)
		# ملابس؟ إن حمل جلداً
		if h.holds(Items.T.HIDE):
			draw_line(hip, shoulder, Items.COLOR[Items.T.HIDE], torso_w * 1.7)
		# رأس
		var head := shoulder + Vector2(0, -6 * sc)
		draw_circle(head, 5.5 * sc, skin)
		draw_circle(head + Vector2(0, -2 * sc), 5.0 * sc, hair)
		draw_rect(Rect2(head + Vector2(-5 * sc, -2 * sc), Vector2(10 * sc, 3.5 * sc)), hair)
		if h.sex == Human.Sex.FEMALE:
			draw_line(head + Vector2(-4 * sc, 0), head + Vector2(-5 * sc, 10 * sc), hair, 2.5 * sc)
		draw_circle(head + Vector2(2.5 * f * sc, 0.5), 0.9, Color(0.05, 0.05, 0.05))
		# ذراعان + ما في اليدين
		var arm_swing := walk * 5.0
		var act_anim := 0.0
		if h.act == Human.Act.STRIKE or h.act == Human.Act.RUB or h.act == Human.Act.HUNT or h.act == Human.Act.DIG:
			act_anim = sin(h.anim_t * 14.0) * 7.0
		var hand_r := shoulder + Vector2(7 * sc * f + arm_swing, 8 * sc + act_anim)
		var hand_l := shoulder + Vector2(-7 * sc * f - arm_swing, 8 * sc - act_anim * 0.5)
		if h.act == Human.Act.MOUTH:
			hand_r = head + Vector2(3 * f, 2)
		draw_line(shoulder, hand_r, skin, 2.5 * sc)
		draw_line(shoulder, hand_l, skin, 2.5 * sc)
		if h.hand_r != Items.T.NONE:
			_draw_item(hand_r, h.hand_r, 0.9)
		if h.hand_l != Items.T.NONE:
			_draw_item(hand_l, h.hand_l, 0.9)
		# طفل محمول
		if h.carrying_child >= 0:
			var c := world.human_by_id(h.carrying_child)
			if c != null and c.alive:
				var cs := c.body_scale(now)
				var cp := shoulder + Vector2(-6 * f * sc, 2)
				draw_circle(cp, 4.5 * cs, skin.lerp(Color(0.95, 0.8, 0.65).lerp(Color(0.35, 0.22, 0.12), c.g_skin), 0.5))
				draw_circle(cp + Vector2(0, -3 * cs), 3.0 * cs, hair)
		# حالة جسدية
		if h.health < 0.4 or h.injury > 0.4:
			draw_circle(head + Vector2(6 * sc, -6 * sc), 2.5, Color(0.9, 0.2, 0.2, 0.8 + 0.2 * sin(time_acc * 6.0)))
		if h.sick > 0.3:
			draw_circle(head + Vector2(-6 * sc, -6 * sc), 2.5, Color(0.5, 0.9, 0.3, 0.8))
	# كلام
	if h.speech != "" and zoom > 0.35:
		var sp := p + Vector2(0, -H - 22)
		var font := ThemeDB.fallback_font
		var w := font.get_string_size(h.speech, HORIZONTAL_ALIGNMENT_CENTER, -1, 15).x + 14
		draw_rect(Rect2(sp + Vector2(-w * 0.5, -12), Vector2(w, 22)), Color(1, 1, 1, 0.92), true)
		draw_colored_polygon(PackedVector2Array([sp + Vector2(-4, 10), sp + Vector2(4, 10), sp + Vector2(0, 15)]), Color(1, 1, 1, 0.92))
		draw_string(font, sp + Vector2(-w * 0.5 + 7, 5), h.speech, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.1, 0.1, 0.15))
	# اسم/فكرة
	if zoom > 0.5:
		var font2 := ThemeDB.fallback_font
		if show_labels and h.name_word != "":
			draw_string(font2, p + Vector2(-30, -H - 8), h.name_word, HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color(1, 1, 1, 0.85))
		if show_thoughts and h.thought != "" and (h.id == selected_id or zoom > 0.9):
			var th := h.thought
			var tw := font2.get_string_size(th, HORIZONTAL_ALIGNMENT_CENTER, -1, 11).x
			draw_string(font2, p + Vector2(-tw * 0.5, 18), th, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.9, 1.0, 0.75))

func _draw_atmosphere(vis: Rect2, daylight: float) -> void:
	var r := Rect2(vis.position * TILE, vis.size * TILE)
	# الليل: أزرق داكن
	var night := 1.0 - daylight
	if night > 0.01:
		var tint := Color(0.02, 0.04, 0.12, night * 0.72)
		draw_rect(r, tint)
		# القمر يضيء قليلاً
		var mp := WorldClock.moon_phase()
		var moonlight := 1.0 - absf(mp - 0.5) * 2.0
		draw_rect(r, Color(0.5, 0.6, 0.9, night * moonlight * 0.06))
		# هالة النار في الليل
		for f in world.fires:
			var p := Vector2(f.x + 0.5, f.y + 0.5) * TILE
			var s := clampf(f.fuel / 12.0, 0.3, 1.3)
			draw_circle(p, 150.0 * s, Color(1.0, 0.6, 0.25, 0.12 * night))
			draw_circle(p, 80.0 * s, Color(1.0, 0.7, 0.35, 0.12 * night))
	# الغسق البرتقالي
	var dusk := clampf(1.0 - absf(daylight - 0.5) * 2.0, 0.0, 1.0)
	if dusk > 0.05:
		draw_rect(r, Color(0.9, 0.45, 0.2, dusk * 0.14))
	# غيوم/مطر
	if world.cloud_cover > 0.3:
		draw_rect(r, Color(0.5, 0.55, 0.62, (world.cloud_cover - 0.3) * 0.35))
	if world.rain_intensity > 0.05 and not reduce_effects:
		var n := int(rain_drops.size() * world.rain_intensity)
		var snow := world.weather == World.Weather.SNOW
		for k in n:
			var d: Vector2 = rain_drops[k]
			var yy := fmod(d.y + time_acc * (0.15 if snow else 0.9) + k * 0.013, 1.0)
			var pp := r.position + Vector2(fmod(d.x + (0.02 * sin(time_acc + k) if snow else 0.0), 1.0) * r.size.x, yy * r.size.y)
			if snow:
				draw_circle(pp, 2.5 / cam.zoom.x, Color(1, 1, 1, 0.8))
			else:
				draw_line(pp, pp + Vector2(-3, 14) / cam.zoom.x, Color(0.8, 0.9, 1.0, 0.45), 1.5 / cam.zoom.x)
	if world.lightning_flash > 0.0:
		draw_rect(r, Color(1, 1, 1, world.lightning_flash * 0.6))
	# حدود العالم
	draw_rect(Rect2(Vector2.ZERO, Vector2(Terrain.W, Terrain.H) * TILE), Color(0, 0, 0, 0.6), false, 6.0)
