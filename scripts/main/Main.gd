extends Node
## Main — يربط كل شيء: الكون ← الأرض ← البشر. الكاميرا باللمس، الحفظ، الاستدراك.

enum State { BOOT, GENESIS, WORLD }
var state: int = State.BOOT
var world: World
var view: WorldView
var cam: Camera2D
var hud: HUD
var genesis: Genesis
var follow_id := -1
var _touches: Dictionary = {}
var _pinch_start_dist := 0.0
var _pinch_start_zoom := 1.0
var _drag_moved := false
var _tap_pos := Vector2.ZERO
var _catchup_left := 0.0
var _catchup_total := 0.0
var _night_flag := false
var _last_ms := 0
var _fps_acc := 0.0
var _fps_n := 0
var _eye_timer := 0.0
var _eye := false
var _eye_dir := ""
var _eye_seq := 0
var _eye_frames := 0
const CATCHUP_STEP := 20.0        # ثانية عالم لكل خطوة استدراك
const CATCHUP_BUDGET_MS := 40.0   # ميلي ثانية حساب لكل إطار أثناء الاستدراك

func _ready() -> void:
	get_tree().set_auto_accept_quit(true)
	hud = HUD.new()
	hud.main = self
	add_child(hud)
	hud.build()
	hud.follow_requested.connect(func(id): follow_id = id)
	hud.center_requested.connect(func(p): follow_id = -1; cam.global_position = p * WorldView.TILE)
	hud.speed_changed.connect(func(m): WorldClock.speed_multiplier = m)
	hud.new_world_requested.connect(_new_universe)
	hud.skip_requested.connect(func(): if genesis: genesis.skip())
	cam = Camera2D.new()
	cam.zoom = Vector2(0.8, 0.8)
	add_child(cam)
	_parse_args()
	if SaveSystem.has_save():
		_load_world()
	else:
		_start_genesis()

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--eye="):
			_eye = true
			_eye_dir = a.substr(6)
			DirAccess.make_dir_recursive_absolute(_eye_dir)
		if a == "--fresh":
			SaveSystem.delete_save()
		if a == "--skip-genesis":
			set_meta("skip_genesis", true)
		if a.begins_with("--speed="):
			WorldClock.speed_multiplier = float(a.substr(8))
		if a.begins_with("--fake-absence="):
			set_meta("fake_absence", float(a.substr(15)))
		if a == "--test-select":
			set_meta("test_select", true)
		if a.begins_with("--test-panel="):
			set_meta("test_panel", a.substr(13))

# ============================ البداية ============================
func _start_genesis() -> void:
	state = State.GENESIS
	Rng.reseed(int(Time.get_unix_time_from_system()) ^ (randi() << 8))
	genesis = Genesis.new()
	add_child(genesis)
	genesis.phase_changed.connect(func(n): hud.set_genesis_phase(n))
	genesis.finished.connect(_on_genesis_finished)
	cam.enabled = false
	hud.set_genesis_visible(true)
	hud.set_game_ui_visible(false)
	hud.cover.visible = true
	hud.cover.color.a = 1.0
	hud.show_cover_text("قبل كل شيء…\nلم يكن هناك شيء.", 2.0)
	await get_tree().create_timer(4.0).timeout
	hud.fade_cover(0.0, 3.0)
	if has_meta("skip_genesis"):
		genesis.speed = 40.0

func _on_genesis_finished() -> void:
	if state != State.GENESIS:
		return
	state = State.BOOT
	hud.set_genesis_visible(false)
	hud.cover.visible = true
	hud.cover.color.a = 0.0
	hud.cover_lbl.text = ""
	var tw := create_tween()
	tw.tween_property(hud.cover, "color:a", 1.0, 2.0)
	await tw.finished
	if genesis:
		genesis.queue_free()
		genesis = null
	hud.show_cover_text("ثم…\nعلى أرضٍ خضراء، قرب الماء،\nوقف كائنٌ لا يعرف شيئاً.", 2.0)
	await get_tree().create_timer(4.5).timeout
	_create_world()
	hud.fade_cover(0.0, 3.0)

func _create_world() -> void:
	world = World.new()
	world.generate()
	WorldClock.start_new_world()
	Chronicle.entries.clear()
	Chronicle.milestones.clear()
	Chronicle.add(Chronicle.Kind.COSMOS, "من لا شيء… بدأ كل شيء.", Vector2.INF, 3)
	Chronicle.add(Chronicle.Kind.COSMOS, "اشتعلت النجوم الأولى، ثم تجمّعت المجرّات.", Vector2.INF, 2)
	Chronicle.add(Chronicle.Kind.EARTH, "تكوّنت الأرض من الغبار والصخر، وبردت، وامتلأت بالماء.", Vector2.INF, 2)
	Chronicle.add(Chronicle.Kind.LIFE, "في الماء تحرّكت أول خليّة. ثم خرجت الحياة إلى اليابسة.", Vector2.INF, 2)
	world.spawn_first_humans(WorldClock.world_seconds)
	_enter_world()

func _load_world() -> void:
	var d := SaveSystem.load_data()
	if d.is_empty():
		_start_genesis()
		return
	Rng.reseed(int(d.seed))
	if d.has("rng_state"):
		Rng.set_state(int(d.rng_state))
	world = World.new()
	world.from_save(d.world)
	Chronicle.from_save(d.chronicle)
	var off: float = d.get("offset", 0.0)
	if has_meta("fake_absence"):
		off += get_meta("fake_absence")
	WorldClock.resume_world(d.epoch, off)
	WorldClock.speed_multiplier = 1.0
	# الاستدراك: كم من الزمن الحقيقي مرّ ونحن غائبون؟
	_catchup_total = maxf(0.0, WorldClock.world_seconds - world.sim_time)
	_catchup_left = _catchup_total
	_enter_world()
	if _catchup_total > 120.0:
		hud.cover.visible = true
		hud.cover.color.a = 0.85
		hud.show_cover_text("كنتَ غائباً %s.\nالعالم لم يتوقّف…" % WorldClock.duration_ar(_catchup_total), 0.8)
	else:
		hud.fade_cover(0.0, 1.5)

func _enter_world() -> void:
	state = State.WORLD
	view = WorldView.new()
	add_child(view)
	move_child(view, 0)
	view.setup(world, cam)
	cam.enabled = true
	cam.make_current()
	apply_view_settings()
	var c := Vector2(Terrain.W, Terrain.H) * 0.5
	for h in world.humans:
		if h.alive:
			c = h.pos
			follow_id = h.id
			break
	cam.global_position = c * WorldView.TILE
	cam.zoom = Vector2(0.9, 0.9)
	hud.world = world
	hud.set_game_ui_visible(true)
	SaveSystem.world_ref = world
	AudioBus.play_earth_ambient()
	world.human_born.connect(func(h): AudioBus.sfx("birth"); view.pulse(h.pos, Color(1.0, 0.9, 0.6)))
	world.human_died.connect(func(h): AudioBus.sfx("death"); view.pulse(h.pos, Color(0.8, 0.4, 0.4)); if hud.selected == h: hud.refresh_inspect())
	world.fire_started.connect(func(p): view.pulse(p, Color(1.0, 0.6, 0.2)))
	world.lightning.connect(func(p): AudioBus.sfx("thunder", randf_range(0.8, 1.2)))
	Chronicle.event_added.connect(_on_event)
	WorldClock.day_changed.connect(func(d): SaveSystem.save_now())

func _on_event(e: Dictionary) -> void:
	if state != State.WORLD or _catchup_left > 0.0:
		return
	if int(e.imp) >= 3:
		hud.toast(e.text)
		AudioBus.sfx("discover")
		Settings.vibrate(40)
	elif int(e.kind) == Chronicle.Kind.BIRTH or int(e.kind) == Chronicle.Kind.DEATH:
		hud.toast(e.text)

func _new_universe() -> void:
	SaveSystem.world_ref = null
	SaveSystem.delete_save()
	Chronicle.entries.clear()
	Chronicle.milestones.clear()
	get_tree().reload_current_scene()

func apply_view_settings() -> void:
	if view:
		view.show_labels = Settings.show_labels
		view.show_thoughts = Settings.show_thoughts
		view.reduce_effects = Settings.reduce_effects

func set_selected(id: int) -> void:
	if view:
		view.selected_id = id
	if id < 0:
		follow_id = -1

# ============================ الحلقة ============================
func _process(delta: float) -> void:
	match state:
		State.GENESIS:
			if genesis:
				hud.set_genesis_progress(genesis.progress())
		State.WORLD:
			_world_process(delta)
	if _eye:
		_eye_capture(delta)
		if state == State.WORLD and _catchup_left <= 0.0 and _eye_seq >= 2 and has_meta("test_select") and hud.selected == null:
			for h in world.humans:
				if h.alive:
					hud.select_human(h)
					follow_id = h.id
					break
		if state == State.WORLD and _catchup_left <= 0.0 and _eye_seq >= 3 and has_meta("test_panel"):
			var pn: String = get_meta("test_panel")
			remove_meta("test_panel")
			if pn == "chronicle": hud._toggle(hud.chronicle_panel)
			elif pn == "stats": hud._toggle(hud.stats_panel)
			elif pn == "settings": hud._toggle(hud.settings_panel)
			elif pn == "help": hud._toggle(hud.help_panel)

func _world_process(delta: float) -> void:
	# 1) الاستدراك بعد الغياب — نحاكي بخطوات كبيرة ضمن ميزانية زمنية لكل إطار
	if _catchup_left > 0.0:
		var t0 := Time.get_ticks_msec()
		# كلما طال الغياب صار الاستدراك أخشن (خطوات أطول) كي لا ينتظر المستخدم طويلاً
		var sub := 8.0 if _catchup_total < 2.0 * 3600.0 else (30.0 if _catchup_total < 10.0 * 3600.0 else 90.0)
		World.MAX_SUBSTEP_COARSE_DYN = sub
		while _catchup_left > 0.0 and Time.get_ticks_msec() - t0 < CATCHUP_BUDGET_MS:
			var step := minf(sub * 4.0, _catchup_left)
			world.tick(step, world.human_epoch + world.sim_time + step, true)
			_catchup_left -= step
		World.MAX_SUBSTEP_COARSE_DYN = 8.0
		var done := 1.0 - _catchup_left / maxf(1.0, _catchup_total)
		hud.cover_lbl.text = "كنتَ غائباً %s.\nالعالم لم يتوقّف… %d%%" % [WorldClock.duration_ar(_catchup_total), int(done * 100)]
		if _catchup_left <= 0.0:
			hud.fade_cover(0.0, 1.2)
			SaveSystem.save_now()
		return
	# 2) الزمن الحقيقي: نحاكي بقدر ما مضى فعلاً (مع المضاعف الاختياري)
	var target := WorldClock.world_seconds
	var gap := target - world.sim_time
	if gap > 0.0:
		if gap > 5.0:
			# فجوة كبيرة (المستخدم فعّل التسريع أو تجمّد التطبيق): خطوات مجمّعة
			var t0 := Time.get_ticks_msec()
			while world.sim_time < target - 0.5 and Time.get_ticks_msec() - t0 < CATCHUP_BUDGET_MS:
				var step := minf(CATCHUP_STEP, target - world.sim_time)
				world.tick(step, world.human_epoch + world.sim_time + step, step > 3.0)
		else:
			world.tick(gap, target, false)
	# الكاميرا تتبع
	if follow_id >= 0:
		var h := world.human_by_id(follow_id)
		if h != null and h.alive:
			cam.global_position = cam.global_position.lerp(h.pos * WorldView.TILE, clampf(delta * 4.0, 0.0, 1.0))
		else:
			follow_id = -1
	_clamp_camera()
	# الصوت ليلاً/نهاراً
	var night := WorldClock.is_night()
	if night != _night_flag:
		_night_flag = night
		AudioBus.set_night(night)

func _clamp_camera() -> void:
	var lim := Vector2(Terrain.W, Terrain.H) * WorldView.TILE
	cam.global_position.x = clampf(cam.global_position.x, 0.0, lim.x)
	cam.global_position.y = clampf(cam.global_position.y, 0.0, lim.y)

# ============================ اللمس ============================
func _unhandled_input(event: InputEvent) -> void:
	if state != State.WORLD:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if hud.is_point_on_ui(event.position):
				return
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_drag_moved = false
				_tap_pos = event.position
			elif _touches.size() == 2:
				var pts := _touches.values()
				_pinch_start_dist = pts[0].distance_to(pts[1])
				_pinch_start_zoom = cam.zoom.x
		else:
			if _touches.has(event.index) and _touches.size() == 1 and not _drag_moved:
				_tap(event.position)
			_touches.erase(event.index)
	elif event is InputEventScreenDrag:
		if not _touches.has(event.index):
			return
		if _touches.size() == 1:
			var d: Vector2 = event.position - _touches[event.index]
			if d.length() > 3.0:
				_drag_moved = true
				follow_id = -1
			cam.global_position -= d / cam.zoom.x
		elif _touches.size() == 2:
			_touches[event.index] = event.position
			var pts := _touches.values()
			var dist: float = pts[0].distance_to(pts[1])
			if _pinch_start_dist > 1.0:
				var z := clampf(_pinch_start_zoom * dist / _pinch_start_dist, 0.15, 3.0)
				cam.zoom = Vector2(z, z)
			_drag_moved = true
			return
		_touches[event.index] = event.position
	elif event is InputEventMouseButton and event.pressed:
		# دعم عجلة الفأرة على الحاسوب للتجربة
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.zoom = Vector2.ONE * clampf(cam.zoom.x * 1.1, 0.15, 3.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.zoom = Vector2.ONE * clampf(cam.zoom.x / 1.1, 0.15, 3.0)

func _tap(screen_pos: Vector2) -> void:
	var vp := get_viewport().get_visible_rect().size
	var wpos := (screen_pos - vp * 0.5) / cam.zoom.x + cam.global_position
	var tile_pos := wpos / WorldView.TILE
	var best: Human = null
	var bd := 1.1
	for h in world.humans:
		if h.alive and h.carried_by < 0:
			var d := h.pos.distance_to(tile_pos + Vector2(0, 0.2))
			if d < bd:
				bd = d
				best = h
	AudioBus.sfx("tap", 1.2, -6.0)
	if best != null:
		hud.select_human(best)
		Settings.vibrate(15)
	else:
		hud.select_human(null)

# ============================ العين (للاختبار من الطرفية) ============================
func _eye_capture(delta: float) -> void:
	_eye_timer += delta
	_eye_frames += 1
	if _eye_timer >= 2.0 and _eye_frames > 5:
		_eye_timer = 0.0
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/frame_%03d.png" % [_eye_dir, _eye_seq])
		_eye_seq += 1
		if state == State.WORLD and world:
			var f := FileAccess.open("%s/state.txt" % _eye_dir, FileAccess.WRITE)
			if f:
				f.store_line("t=%s fps=%d living=%d born=%d died=%d fires=%d tools=%d meals=%d words=%d" % [WorldClock.clock_string(), Engine.get_frames_per_second(), world.living_count(), world.born_count, world.died_count, world.fires.size(), world.stats.tools_made, world.stats.meals, world.stats.words])
				for e in Chronicle.recent(25):
					f.store_line("[%s] %s" % [e.clock, e.text])
				for h in world.humans:
					if h.alive:
						f.store_line("H%d %s pos=(%.1f,%.1f) hp=%.2f hu=%.2f th=%.2f en=%.2f act=%s hands=%d/%d mem=%d vocab=%d thought=%s" % [h.id, h.stage_ar(WorldClock.world_seconds), h.pos.x, h.pos.y, h.health, h.hunger, h.thirst, h.energy, Human.ACT_AR.get(h.act, "?"), h.hand_r, h.hand_l, h.memory.size(), h.vocab.size(), h.thought])
				f.close()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# زر الرجوع في أندرويد: أغلق اللوحات أولاً
		if hud and (hud.inspect_panel.visible or hud.chronicle_panel.visible or hud.stats_panel.visible or hud.settings_panel.visible or hud.help_panel.visible):
			hud.select_human(null)
			hud.set_game_ui_visible(true)
		else:
			SaveSystem.save_now()
			get_tree().quit()
