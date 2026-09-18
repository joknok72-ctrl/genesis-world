class_name Genesis
extends Node2D
## Genesis — قبل كل شيء. لا زمن، لا مكان، لا ضوء.
## ثم نقطة… ثم كل شيء. تُروى بالصمت وبالصورة، وبنصوص قليلة.
## المدة الحقيقية للمشهد بضع دقائق (قابلة للتخطّي)؛ لأن الزمن قبل الإنسان لا يُقاس بساعتنا.

signal finished()
signal phase_changed(name_ar: String)

enum Phase { VOID, SINGULARITY, EXPANSION, FIRST_LIGHT, STARS, GALAXY, SUN, EARTH_FORMING, EARTH_COOLING, OCEANS, FIRST_LIFE, LAND_LIFE, DONE }
const PHASE_AR := {
	Phase.VOID: "لا شيء", Phase.SINGULARITY: "نقطة", Phase.EXPANSION: "الانفجار العظيم", Phase.FIRST_LIGHT: "أول ضوء",
	Phase.STARS: "النجوم الأولى", Phase.GALAXY: "المجرّة", Phase.SUN: "الشمس", Phase.EARTH_FORMING: "تكوّن الأرض",
	Phase.EARTH_COOLING: "الأرض تبرد", Phase.OCEANS: "المحيطات", Phase.FIRST_LIFE: "الحياة الأولى", Phase.LAND_LIFE: "الحياة على اليابسة",
	Phase.DONE: "",
}
const PHASE_LEN := {
	Phase.VOID: 9.0, Phase.SINGULARITY: 7.0, Phase.EXPANSION: 6.0, Phase.FIRST_LIGHT: 8.0, Phase.STARS: 12.0,
	Phase.GALAXY: 12.0, Phase.SUN: 10.0, Phase.EARTH_FORMING: 14.0, Phase.EARTH_COOLING: 10.0, Phase.OCEANS: 12.0,
	Phase.FIRST_LIFE: 12.0, Phase.LAND_LIFE: 12.0,
}
const CAPTION := {
	Phase.VOID: "",
	Phase.SINGULARITY: "",
	Phase.EXPANSION: "",
	Phase.FIRST_LIGHT: "",
	Phase.STARS: "",
	Phase.GALAXY: "",
	Phase.SUN: "",
	Phase.EARTH_FORMING: "",
	Phase.EARTH_COOLING: "",
	Phase.OCEANS: "",
	Phase.FIRST_LIFE: "",
	Phase.LAND_LIFE: "",
}

var phase: int = Phase.VOID
var t := 0.0
var total := 0.0
var speed := 1.0
var stars: Array = []       # [pos, brightness, twinkle, color]
var particles: Array = []   # للانفجار
var debris: Array = []      # للأرض المتكوّنة
var vp := Vector2(720, 1280)
var _rng := RandomNumberGenerator.new()
var flash := 0.0
var skip_requested := false

func _ready() -> void:
	_rng.seed = 424242
	vp = get_viewport_rect().size
	for i in 420:
		stars.append([Vector2(_rng.randf(), _rng.randf()), _rng.randf_range(0.2, 1.0), _rng.randf() * TAU, _star_color()])
	for i in 260:
		var a := _rng.randf() * TAU
		particles.append([a, _rng.randf_range(0.2, 1.0), _rng.randf_range(0.6, 1.0), _rng.randf()])
	for i in 140:
		debris.append([_rng.randf() * TAU, _rng.randf_range(0.5, 1.0), _rng.randf_range(2.0, 6.0), _rng.randf_range(0.4, 1.0)])
	AudioBus.play_cosmos()
	phase_changed.emit(PHASE_AR[phase])

func _star_color() -> Color:
	var r := _rng.randf()
	if r < 0.6: return Color(1, 1, 1)
	if r < 0.8: return Color(0.8, 0.85, 1.0)
	if r < 0.92: return Color(1.0, 0.9, 0.7)
	return Color(1.0, 0.7, 0.6)

func _process(delta: float) -> void:
	vp = get_viewport_rect().size
	var d := delta * speed
	t += d
	total += d
	flash = maxf(0.0, flash - delta * 1.2)
	if phase < Phase.DONE and t >= PHASE_LEN[phase]:
		t = 0.0
		phase += 1
		if phase == Phase.EXPANSION:
			flash = 1.0
			AudioBus.sfx("bang", 1.0, 2.0)
		if phase < Phase.DONE:
			phase_changed.emit(PHASE_AR[phase])
		else:
			finished.emit()
	queue_redraw()

func skip() -> void:
	if phase < Phase.DONE:
		phase = Phase.DONE
		finished.emit()

func progress() -> float:
	var sum := 0.0
	var done := 0.0
	for p in PHASE_LEN:
		sum += PHASE_LEN[p]
		if p < phase:
			done += PHASE_LEN[p]
	return clampf((done + t) / sum, 0.0, 1.0)

# ============================ الرسم ============================
func _draw() -> void:
	var c := vp * 0.5
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0))
	match phase:
		Phase.VOID:
			_draw_void()
		Phase.SINGULARITY:
			_draw_void()
			_draw_singularity(c)
		Phase.EXPANSION:
			_draw_expansion(c)
		Phase.FIRST_LIGHT:
			_draw_first_light(c)
		Phase.STARS:
			_draw_stars(clampf(t / 6.0, 0.0, 1.0), 1.0)
		Phase.GALAXY:
			_draw_stars(1.0, 0.5)
			_draw_galaxy(c, clampf(t / 8.0, 0.0, 1.0))
		Phase.SUN:
			_draw_stars(1.0, 0.35)
			_draw_sun(c, clampf(t / 6.0, 0.0, 1.0))
		Phase.EARTH_FORMING:
			_draw_stars(1.0, 0.3)
			_draw_sun_small()
			_draw_earth_forming(c, clampf(t / PHASE_LEN[phase], 0.0, 1.0))
		Phase.EARTH_COOLING:
			_draw_stars(1.0, 0.3)
			_draw_sun_small()
			_draw_earth(c, 1.0, clampf(t / PHASE_LEN[phase], 0.0, 1.0), 0.0, 0.0)
		Phase.OCEANS:
			_draw_stars(1.0, 0.3)
			_draw_sun_small()
			_draw_earth(c, 1.0, 1.0, clampf(t / PHASE_LEN[phase], 0.0, 1.0), 0.0)
		Phase.FIRST_LIFE:
			_draw_stars(1.0, 0.3)
			_draw_sun_small()
			_draw_earth(c, 1.0, 1.0, 1.0, 0.0)
			_draw_microlife(c, clampf(t / PHASE_LEN[phase], 0.0, 1.0))
		Phase.LAND_LIFE:
			_draw_stars(1.0, 0.3)
			_draw_sun_small()
			_draw_earth(c, 1.0, 1.0, 1.0, clampf(t / PHASE_LEN[phase], 0.0, 1.0))
		_:
			pass
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(1, 1, 1, flash))

func _draw_void() -> void:
	# لا شيء… سوى اهتزاز خافت جداً لا يكاد يُرى
	var a := 0.012 + 0.008 * sin(total * 0.7)
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.03, 0.02, 0.06, a))

func _draw_singularity(c: Vector2) -> void:
	var k := clampf(t / PHASE_LEN[Phase.SINGULARITY], 0.0, 1.0)
	var r := 1.0 + k * k * 4.0
	var pulse := 0.6 + 0.4 * sin(total * (2.0 + k * 20.0))
	draw_circle(c, r * 10.0 * k, Color(0.6, 0.5, 1.0, 0.08 * pulse))
	draw_circle(c, r * 4.0 * k, Color(0.8, 0.75, 1.0, 0.25 * pulse))
	draw_circle(c, r, Color(1, 1, 1, 0.6 + 0.4 * k))

func _draw_expansion(c: Vector2) -> void:
	var k := clampf(t / PHASE_LEN[Phase.EXPANSION], 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	var maxr := vp.length() * 0.75
	# توهّج مركزي يخفت
	draw_circle(c, maxr * e * 0.6, Color(1.0, 0.85, 0.6, (1.0 - k) * 0.5))
	draw_circle(c, maxr * e * 0.25, Color(1.0, 0.95, 0.9, (1.0 - k) * 0.8))
	for p in particles:
		var ang: float = p[0]
		var sp: float = p[1]
		var rr := maxr * e * sp
		var pos := c + Vector2(cos(ang), sin(ang)) * rr
		var col := Color(1.0, lerpf(0.5, 0.9, p[3]), lerpf(0.2, 0.7, p[3]), (1.0 - k * 0.7) * p[2])
		draw_circle(pos, 2.0 + 4.0 * (1.0 - k), col)
		draw_line(c.lerp(pos, 0.85), pos, Color(col, col.a * 0.4), 1.5)

func _draw_first_light(c: Vector2) -> void:
	var k := clampf(t / PHASE_LEN[Phase.FIRST_LIGHT], 0.0, 1.0)
	# ضباب حار برتقالي يبرد تدريجياً إلى بنفسجي ثم أسود، تبدأ نقاط كثيفة تلتمع
	var fog := Color(lerpf(0.9, 0.05, k), lerpf(0.45, 0.02, k), lerpf(0.2, 0.1, k), 1.0 - k * 0.85)
	draw_rect(Rect2(Vector2.ZERO, vp), fog)
	for i in 30:
		var s = stars[i]
		var pos: Vector2 = s[0] * vp
		var a := clampf((k - float(i) / 40.0) * 3.0, 0.0, 1.0)
		draw_circle(pos, 30.0 * a, Color(1.0, 0.7, 0.4, 0.05 * a))
		draw_circle(pos, 3.0 * a, Color(1.0, 0.9, 0.7, a))

func _draw_stars(appear: float, alpha: float) -> void:
	var n := int(stars.size() * appear)
	for i in n:
		var s = stars[i]
		var pos: Vector2 = s[0] * vp
		var tw: float = 0.75 + 0.25 * sin(total * 2.0 + s[2])
		var b: float = s[1] * tw * alpha
		var col: Color = s[3]
		draw_circle(pos, 0.8 + s[1] * 1.6, Color(col.r, col.g, col.b, b))
		if s[1] > 0.85:
			draw_circle(pos, 6.0, Color(col.r, col.g, col.b, b * 0.08))

func _draw_galaxy(c: Vector2, k: float) -> void:
	var rot := total * 0.05
	var arms := 3
	for i in 700:
		var f := float(i) / 700.0
		var arm := i % arms
		var ang := f * 5.5 + float(arm) * TAU / arms + rot
		var rad := f * vp.x * 0.42 * k
		var jitter := Vector2(sin(i * 12.9898) * 22.0, cos(i * 78.233) * 22.0) * (0.4 + f)
		var pos := c + Vector2(cos(ang), sin(ang)) * rad + jitter
		var col := Color(0.8 + 0.2 * (1.0 - f), 0.75, 1.0, 0.45 * k * (1.0 - f * 0.6))
		draw_circle(pos, 1.2 + (1.0 - f) * 1.5, col)
	draw_circle(c, 40.0 * k, Color(1.0, 0.95, 0.85, 0.25 * k))
	draw_circle(c, 14.0 * k, Color(1.0, 1.0, 0.95, 0.8 * k))

func _draw_sun(c: Vector2, k: float) -> void:
	# سديم يتكاثف إلى نجم
	var r := lerpf(220.0, 90.0, k)
	for i in 40:
		var a := float(i) / 40.0 * TAU + total * 0.1
		var rr := r * (1.0 + 0.3 * sin(i * 3.1 + total))
		draw_circle(c + Vector2(cos(a), sin(a)) * rr * 0.7, 60.0 * (1.0 - k) + 10.0, Color(1.0, 0.6, 0.2, 0.03 + 0.03 * k))
	draw_circle(c, r * 1.6, Color(1.0, 0.7, 0.3, 0.08 * k))
	draw_circle(c, r * 1.15, Color(1.0, 0.8, 0.4, 0.2 * k))
	draw_circle(c, r, Color(1.0, 0.92, 0.6, 0.6 + 0.4 * k))
	draw_circle(c, r * 0.7, Color(1.0, 1.0, 0.9, k))

func _draw_sun_small() -> void:
	var p := Vector2(vp.x * 0.82, vp.y * 0.18)
	draw_circle(p, 70.0, Color(1.0, 0.8, 0.4, 0.08))
	draw_circle(p, 42.0, Color(1.0, 0.9, 0.6, 0.35))
	draw_circle(p, 28.0, Color(1.0, 0.98, 0.85, 1.0))

func _draw_earth_forming(c: Vector2, k: float) -> void:
	var R := 150.0
	# حطام يدور ويتجمّع
	for d in debris:
		var ang: float = d[0] + total * 0.25 / d[1]
		var rad: float = R * lerpf(d[2], 1.0, k * k)
		var pos := c + Vector2(cos(ang), sin(ang) * 0.5) * rad
		var sz: float = 2.0 + d[3] * 4.0 * (1.0 - k * 0.6)
		var glow := Color(1.0, 0.45 + 0.3 * d[3], 0.2, 0.9)
		draw_circle(pos, sz, glow)
	# الكوكب الملتهب يكبر
	var pr := R * (0.3 + 0.7 * k)
	draw_circle(c, pr * 1.2, Color(1.0, 0.4, 0.1, 0.15 * k))
	draw_circle(c, pr, Color(0.5, 0.15, 0.05))
	for i in 60:
		var a := float(i) * 2.399 + total * 0.1
		var rr := pr * sqrt(float(i) / 60.0) * 0.95
		var pos := c + Vector2(cos(a), sin(a)) * rr
		draw_circle(pos, pr * 0.12 * (0.5 + 0.5 * sin(i + total * 2.0)), Color(1.0, 0.6, 0.15, 0.7))

func _draw_earth(c: Vector2, size: float, cool: float, ocean: float, land: float) -> void:
	var pr := 150.0 * size
	# غلاف جوي
	draw_circle(c, pr * 1.12, Color(0.4, 0.6, 1.0, 0.12 * ocean))
	# سطح: من الحمم إلى الصخر إلى المحيط
	var rock := Color(0.35, 0.3, 0.28)
	var lava := Color(0.6, 0.18, 0.06)
	var surface := lava.lerp(rock, cool)
	var sea := Color(0.1, 0.3, 0.65)
	draw_circle(c, pr, surface.lerp(sea, ocean * 0.85))
	# قارات (بقع ثابتة)
	for i in 28:
		var a := float(i) * 2.399
		var rr := pr * sqrt(float(i) / 28.0) * 0.9
		var pos := c + Vector2(cos(a), sin(a)) * rr
		var sz := pr * (0.14 + 0.1 * sin(i * 1.7))
		var land_col := Color(0.55, 0.45, 0.3).lerp(Color(0.25, 0.55, 0.22), land)
		var col := surface.lerp(land_col, ocean)
		# لا ترسم خارج الكوكب
		if pos.distance_to(c) + sz * 0.6 < pr:
			draw_circle(pos, sz, col)
	# حمم متبقية تخفت
	if cool < 1.0:
		for i in 40:
			var a := float(i) * 2.399 + total * 0.05
			var rr := pr * sqrt(float(i) / 40.0) * 0.9
			var pos := c + Vector2(cos(a), sin(a)) * rr
			draw_circle(pos, pr * 0.05 * (1.0 - cool), Color(1.0, 0.5, 0.1, (1.0 - cool) * 0.8))
	# قمم ثلجية عند القطبين
	if ocean > 0.5:
		draw_circle(c + Vector2(0, -pr * 0.92), pr * 0.18, Color(0.95, 0.97, 1.0, (ocean - 0.5) * 1.6))
		draw_circle(c + Vector2(0, pr * 0.92), pr * 0.16, Color(0.95, 0.97, 1.0, (ocean - 0.5) * 1.6))
	# غيوم
	if ocean > 0.3:
		for i in 14:
			var a := float(i) * 2.399 + total * 0.03
			var rr := pr * sqrt(float(i) / 14.0) * 0.85
			var pos := c + Vector2(cos(a), sin(a)) * rr
			draw_circle(pos, pr * 0.1, Color(1, 1, 1, 0.35 * (ocean - 0.3)))
	# ظل الليل
	draw_circle(c + Vector2(pr * 0.5, pr * 0.25), pr * 1.0, Color(0, 0, 0.05, 0.0))
	# حد الإضاءة
	for i in 24:
		var f := float(i) / 24.0
		draw_arc(c, pr - f * 3.0, PI * 0.15, PI * 1.1, 24, Color(0, 0, 0.02, 0.06), 6.0)

func _draw_microlife(c: Vector2, k: float) -> void:
	# تقريب على قطرة ماء: خيوط وخلايا تتضاعف
	var r := 120.0
	var cc := c + Vector2(0, 330)
	draw_circle(cc, r + 6, Color(0.5, 0.75, 1.0, 0.25))
	draw_circle(cc, r, Color(0.05, 0.2, 0.4, 0.9))
	var n := int(2.0 + k * k * 60.0)
	for i in n:
		var ang := float(i) * 2.399 + total * (0.2 + 0.1 * sin(i))
		var rr := r * 0.85 * sqrt(fmod(float(i) * 0.618, 1.0))
		var pos := cc + Vector2(cos(ang), sin(ang)) * rr
		var wob := 1.0 + 0.15 * sin(total * 3.0 + i)
		draw_circle(pos, 6.0 * wob, Color(0.4, 0.95, 0.6, 0.7))
		draw_circle(pos, 2.5, Color(0.1, 0.4, 0.2, 0.9))
	draw_line(c + Vector2(-40, 150), cc + Vector2(-r * 0.3, -r * 0.95), Color(0.5, 0.75, 1.0, 0.4), 1.5)
	draw_line(c + Vector2(40, 150), cc + Vector2(r * 0.3, -r * 0.95), Color(0.5, 0.75, 1.0, 0.4), 1.5)
