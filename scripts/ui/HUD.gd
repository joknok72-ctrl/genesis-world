class_name HUD
extends CanvasLayer
## HUD — واجهة الموبايل: شريط الزمن، الأزرار، لوحة الفحص، السجلّ، الإعدادات.

signal follow_requested(id: int)
signal center_requested(pos: Vector2)
signal speed_changed(mult: float)
signal new_world_requested()
signal skip_requested()

var main: Node
var world: World

var top_panel: PanelContainer
var clock_lbl: Label
var date_lbl: Label
var weather_lbl: Label
var pop_lbl: Label
var era_lbl: Label
var bottom_panel: PanelContainer
var bottom_bar: HBoxContainer
var inspect_panel: PanelContainer
var inspect_text: RichTextLabel
var inspect_title: Label
var chronicle_panel: PanelContainer
var chronicle_list: RichTextLabel
var settings_panel: PanelContainer
var help_panel: PanelContainer
var stats_panel: PanelContainer
var stats_text: RichTextLabel
var toast_lbl: Label
var toast_timer := 0.0
var _toast_queue: Array[String] = []
var genesis_panel: PanelContainer
var genesis_lbl: Label
var genesis_bar: ProgressBar
var skip_btn: Button
var speed_btn: Button
var cover: ColorRect
var cover_lbl: Label
var selected: Human = null
var _inspect_timer := 0.0

func build() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_cover(root)
	_build_top(root)
	_build_toast(root)
	_build_bottom(root)
	_build_inspect(root)
	_build_panels(root)
	_build_genesis(root)
	set_game_ui_visible(false)

func _build_cover(root: Control) -> void:
	cover = ColorRect.new()
	cover.color = Color(0, 0, 0, 1)
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cover)
	cover_lbl = Label.new()
	cover_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cover_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cover_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cover_lbl.add_theme_font_size_override("font_size", 26)
	cover_lbl.modulate = Color(1, 1, 1, 0)
	cover.add_child(cover_lbl)

func _build_top(root: Control) -> void:
	top_panel = PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.offset_left = 12
	top_panel.offset_right = -12
	top_panel.offset_top = 14
	root.add_child(top_panel)
	var v := VBoxContainer.new()
	top_panel.add_child(v)
	var h1 := HBoxContainer.new()
	v.add_child(h1)
	clock_lbl = Label.new()
	clock_lbl.add_theme_font_size_override("font_size", 34)
	clock_lbl.text = "00:00:00"
	h1.add_child(clock_lbl)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h1.add_child(sp)
	pop_lbl = Label.new()
	pop_lbl.add_theme_font_size_override("font_size", 22)
	h1.add_child(pop_lbl)
	var h2 := HBoxContainer.new()
	v.add_child(h2)
	date_lbl = Label.new()
	date_lbl.add_theme_font_size_override("font_size", 18)
	date_lbl.modulate = Color(0.95, 0.85, 0.6)
	h2.add_child(date_lbl)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h2.add_child(sp2)
	weather_lbl = Label.new()
	weather_lbl.add_theme_font_size_override("font_size", 18)
	h2.add_child(weather_lbl)
	era_lbl = Label.new()
	era_lbl.add_theme_font_size_override("font_size", 15)
	era_lbl.modulate = Color(0.75, 0.8, 0.95)
	era_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(era_lbl)

func _build_toast(root: Control) -> void:
	toast_lbl = Label.new()
	toast_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	toast_lbl.offset_top = 160
	toast_lbl.offset_left = 20
	toast_lbl.offset_right = -20
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_lbl.add_theme_font_size_override("font_size", 20)
	toast_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	toast_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	toast_lbl.add_theme_constant_override("shadow_offset_y", 2)
	toast_lbl.modulate.a = 0.0
	toast_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_lbl)

func _build_bottom(root: Control) -> void:
	bottom_panel = PanelContainer.new()
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.offset_left = 12
	bottom_panel.offset_right = -12
	bottom_panel.offset_top = -92
	bottom_panel.offset_bottom = -16
	root.add_child(bottom_panel)
	bottom_bar = HBoxContainer.new()
	bottom_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_bar.add_theme_constant_override("separation", 8)
	bottom_panel.add_child(bottom_bar)
	_btn("👥", "البشر", func(): _cycle_human())
	_btn("📜", "السجلّ", func(): _toggle(chronicle_panel))
	_btn("📊", "العالم", func(): _toggle(stats_panel))
	speed_btn = _btn("⏱", "زمن حقيقي", func(): _cycle_speed())
	_btn("⚙", "إعدادات", func(): _toggle(settings_panel))

func _btn(icon: String, label: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = icon + "\n" + label
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(124, 66)
	b.pressed.connect(func(): AudioBus.sfx("tap"); Settings.vibrate(10); cb.call())
	bottom_bar.add_child(b)
	return b

func _build_inspect(root: Control) -> void:
	inspect_panel = PanelContainer.new()
	inspect_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	inspect_panel.offset_left = 12
	inspect_panel.offset_right = -12
	inspect_panel.offset_top = -470
	inspect_panel.offset_bottom = -104
	inspect_panel.visible = false
	root.add_child(inspect_panel)
	var iv := VBoxContainer.new()
	inspect_panel.add_child(iv)
	var ih := HBoxContainer.new()
	iv.add_child(ih)
	inspect_title = Label.new()
	inspect_title.add_theme_font_size_override("font_size", 24)
	inspect_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ih.add_child(inspect_title)
	var follow := Button.new()
	follow.text = "تتبّع"
	follow.pressed.connect(func(): if selected: follow_requested.emit(selected.id))
	ih.add_child(follow)
	var close := Button.new()
	close.text = "✕"
	close.pressed.connect(func(): select_human(null))
	ih.add_child(close)
	inspect_text = RichTextLabel.new()
	inspect_text.bbcode_enabled = true
	inspect_text.scroll_active = true
	inspect_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	iv.add_child(inspect_text)

func _big_panel(root: Control, title: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 12
	p.offset_right = -12
	p.offset_top = 150
	p.offset_bottom = -104
	p.visible = false
	root.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 26)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var c := Button.new()
	c.text = "✕"
	c.pressed.connect(func(): p.visible = false)
	h.add_child(c)
	return p

func _build_panels(root: Control) -> void:
	chronicle_panel = _big_panel(root, "سِجِلّ الكون")
	chronicle_list = RichTextLabel.new()
	chronicle_list.bbcode_enabled = true
	chronicle_list.scroll_active = true
	chronicle_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chronicle_panel.get_child(0).add_child(chronicle_list)
	chronicle_list.meta_clicked.connect(_on_chronicle_link)

	stats_panel = _big_panel(root, "حال العالم")
	stats_text = RichTextLabel.new()
	stats_text.bbcode_enabled = true
	stats_text.scroll_active = true
	stats_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_panel.get_child(0).add_child(stats_text)

	settings_panel = _big_panel(root, "الإعدادات")
	var sv: VBoxContainer = settings_panel.get_child(0)
	_slider(sv, "صوت الأجواء", Settings.music_volume, func(v): Settings.music_volume = v; AudioBus.apply_volumes(); Settings.save_settings())
	_slider(sv, "المؤثرات", Settings.sfx_volume, func(v): Settings.sfx_volume = v; AudioBus.apply_volumes(); Settings.save_settings())
	_check(sv, "إظهار أسماء البشر", Settings.show_labels, func(v): Settings.show_labels = v; Settings.save_settings(); main.apply_view_settings())
	_check(sv, "إظهار ما يدور في رؤوسهم", Settings.show_thoughts, func(v): Settings.show_thoughts = v; Settings.save_settings(); main.apply_view_settings())
	_check(sv, "تقليل المؤثرات (لتوفير البطارية)", Settings.reduce_effects, func(v): Settings.reduce_effects = v; Settings.save_settings(); main.apply_view_settings())
	_check(sv, "الاهتزاز", Settings.haptics, func(v): Settings.haptics = v; Settings.save_settings())
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 16)
	note.modulate = Color(0.8, 0.8, 0.85)
	note.text = "الزمن في هذا العالم حقيقي: ساعة جهازك هي ساعة العالم. البشر يستمرّون في العيش وأنت بعيد؛ وعند عودتك يُستدرَك ما فات."
	sv.add_child(note)
	var help_btn := Button.new()
	help_btn.text = "كيف أشاهد؟"
	help_btn.pressed.connect(func(): _toggle(help_panel))
	sv.add_child(help_btn)
	var nw := Button.new()
	nw.text = "بداية كونٍ جديد (يمسح هذا العالم)"
	nw.modulate = Color(1.0, 0.7, 0.7)
	nw.pressed.connect(_confirm_new_world)
	sv.add_child(nw)

	help_panel = _big_panel(root, "كيف أشاهد؟")
	var hl := RichTextLabel.new()
	hl.bbcode_enabled = true
	hl.scroll_active = true
	hl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hl.text = "[b]أنت لا تلعب. أنت تشاهد.[/b]\n\n• اسحب بإصبع للتحرّك، وقرّب بإصبعين.\n• المس إنساناً لترى جسده وما يشعر به وما تعلّمه.\n• زر [b]👥[/b] ينقلك بين البشر واحداً واحداً.\n• [b]📜[/b] سجلّ كل ما حدث منذ بداية الكون؛ المس أي حدث لتذهب إلى مكانه.\n• [b]⏱[/b] الزمن الحقيقي هو الأصل. يمكنك تسريع [i]المشاهدة[/i] مؤقتاً إن أردت، لكنه اختيارك أنت وليس قانوناً من قوانين العالم.\n\nلا أحد يعطيهم تعليمات. لا أنت ولا نحن. ما سيصنعونه — إن صنعوا شيئاً — فهو منهم وحدهم."
	help_panel.get_child(0).add_child(hl)

func _build_genesis(root: Control) -> void:
	genesis_panel = PanelContainer.new()
	genesis_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	genesis_panel.offset_left = 12
	genesis_panel.offset_right = -12
	genesis_panel.offset_top = -160
	genesis_panel.offset_bottom = -16
	genesis_panel.visible = false
	root.add_child(genesis_panel)
	var gv := VBoxContainer.new()
	genesis_panel.add_child(gv)
	genesis_lbl = Label.new()
	genesis_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	genesis_lbl.add_theme_font_size_override("font_size", 28)
	gv.add_child(genesis_lbl)
	genesis_bar = ProgressBar.new()
	genesis_bar.min_value = 0
	genesis_bar.max_value = 1
	genesis_bar.show_percentage = false
	genesis_bar.custom_minimum_size.y = 6
	gv.add_child(genesis_bar)
	skip_btn = Button.new()
	skip_btn.text = "تخطّي إلى ظهور الإنسان ⏭"
	skip_btn.pressed.connect(func(): skip_requested.emit())
	gv.add_child(skip_btn)

func _slider(parent: Control, label: String, val: float, cb: Callable) -> void:
	var l := Label.new()
	l.text = label
	parent.add_child(l)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 1
	s.step = 0.05
	s.value = val
	s.custom_minimum_size.y = 36
	s.value_changed.connect(cb)
	parent.add_child(s)

func _check(parent: Control, label: String, val: bool, cb: Callable) -> void:
	var c := CheckButton.new()
	c.text = label
	c.button_pressed = val
	c.toggled.connect(cb)
	parent.add_child(c)

func _toggle(p: Control) -> void:
	var show := not p.visible
	for x in [chronicle_panel, stats_panel, settings_panel, help_panel]:
		x.visible = false
	p.visible = show
	if show and p == chronicle_panel:
		refresh_chronicle()
	elif show and p == stats_panel:
		refresh_stats()

func _on_chronicle_link(meta: Variant) -> void:
	var parts := str(meta).split(",")
	if parts.size() == 2:
		center_requested.emit(Vector2(float(parts[0]), float(parts[1])))
		chronicle_panel.visible = false

func set_game_ui_visible(v: bool) -> void:
	top_panel.visible = v
	bottom_panel.visible = v
	if not v:
		inspect_panel.visible = false
		for x in [chronicle_panel, stats_panel, settings_panel, help_panel]:
			x.visible = false

func set_genesis_visible(v: bool) -> void:
	genesis_panel.visible = v

func set_genesis_phase(name_ar: String) -> void:
	genesis_lbl.text = name_ar

func set_genesis_progress(p: float) -> void:
	genesis_bar.value = p

func is_point_on_ui(p: Vector2) -> bool:
	for c in [top_panel, bottom_panel, inspect_panel, chronicle_panel, stats_panel, settings_panel, help_panel, genesis_panel]:
		if c.visible and c.get_global_rect().has_point(p):
			return true
	return false

func toast(text: String) -> void:
	if _toast_queue.size() < 5:
		_toast_queue.append(text)

func show_cover_text(text: String, fade_in: float = 1.5) -> void:
	cover_lbl.text = text
	var tw := create_tween()
	tw.tween_property(cover_lbl, "modulate:a", 1.0, fade_in)

func fade_cover(to_alpha: float, dur: float) -> void:
	cover.visible = true
	var tw := create_tween()
	tw.tween_property(cover, "color:a", to_alpha, dur)
	tw.parallel().tween_property(cover_lbl, "modulate:a", 0.0, dur * 0.6)
	if to_alpha < 0.01:
		tw.tween_callback(func(): cover.visible = false)

# ================= التحديث =================
func _process(delta: float) -> void:
	if toast_timer > 0.0:
		toast_timer -= delta
		toast_lbl.modulate.a = clampf(minf(toast_timer, 1.0), 0.0, 1.0)
	elif not _toast_queue.is_empty():
		toast_lbl.text = _toast_queue.pop_front()
		toast_timer = 5.0
		toast_lbl.modulate.a = 1.0
	if world == null or not top_panel.visible:
		return
	clock_lbl.text = WorldClock.clock_string()
	date_lbl.text = WorldClock.date_string_ar()
	weather_lbl.text = "%s • %d°" % [World.WEATHER_AR[world.weather], int(round(world.ambient_temp))]
	pop_lbl.text = "👥 %d" % world.living_count()
	era_lbl.text = _era_text()
	_inspect_timer -= delta
	if selected != null and _inspect_timer <= 0.0:
		_inspect_timer = 0.5
		if not selected.alive:
			inspect_title.text = selected.label_ar() + " (مات)"
		refresh_inspect()

func _era_text() -> String:
	var parts: Array[String] = []
	if Chronicle.has_milestone("first_fire"): parts.append("النار")
	if Chronicle.has_milestone("first_tool"): parts.append("الأدوات")
	if Chronicle.has_milestone("first_word"): parts.append("الكلام")
	if Chronicle.has_milestone("first_shelter"): parts.append("المأوى")
	if Chronicle.has_milestone("first_burial"): parts.append("القبور")
	if Chronicle.has_milestone("first_art"): parts.append("الرسم")
	var since := WorldClock.duration_ar(WorldClock.world_seconds)
	if parts.is_empty():
		return "لا يعرفون شيئاً بعد • مضى %s منذ ظهور الإنسان" % since
	return "عرفوا: " + "، ".join(parts) + " • " + since

# ================= الفحص =================
func select_human(h: Human) -> void:
	selected = h
	inspect_panel.visible = h != null
	if main:
		main.set_selected(h.id if h else -1)
	if h:
		inspect_title.text = h.label_ar()
		refresh_inspect()

func _cycle_human() -> void:
	if world == null:
		return
	var living: Array[Human] = []
	for h in world.humans:
		if h.alive:
			living.append(h)
	if living.is_empty():
		toast("لم يبقَ أحد.")
		return
	var idx := 0
	if selected != null:
		for i in living.size():
			if living[i].id == selected.id:
				idx = (i + 1) % living.size()
				break
	select_human(living[idx])
	follow_requested.emit(living[idx].id)

func _cycle_speed() -> void:
	var opts := [1.0, 60.0, 600.0, 3600.0]
	var i := opts.find(WorldClock.speed_multiplier)
	i = (i + 1) % opts.size()
	var m: float = opts[i]
	speed_changed.emit(m)
	speed_btn.text = "⏱\n" + ("زمن حقيقي" if m == 1.0 else ("×%d" % int(m)))
	if m != 1.0:
		toast("مراقبة سريعة ×%d — هذا اختيارك أنت؛ العالم نفسه لا يعرف إلا الزمن الحقيقي." % int(m))

func _bar(v: float, col: String) -> String:
	var n := int(round(clampf(v, 0.0, 1.0) * 10.0))
	return "[color=%s]%s[/color][color=#444444]%s[/color]" % [col, "█".repeat(n), "█".repeat(10 - n)]

func refresh_inspect() -> void:
	if selected == null:
		return
	var h := selected
	var now := WorldClock.world_seconds
	var s := ""
	s += "[color=#f2c14e]%s[/color] • العمر: %s\n" % [h.description_ar(now), WorldClock.age_ar(h.age_seconds(now))]
	if not h.alive:
		s += "[color=#e07070]%s[/color]\n" % h.death_cause
	s += "\n[b]الجسد[/b]\n"
	s += "الصحة  %s %d%%\n" % [_bar(h.health, "#7ed07e"), int(h.health * 100)]
	s += "الشبع  %s\n" % _bar(h.hunger, "#f0b060")
	s += "الارتواء %s\n" % _bar(h.thirst, "#70b0f0")
	s += "الطاقة %s\n" % _bar(h.energy, "#d0d070")
	s += "حرارة الجسم: %.1f°" % h.body_temp
	if h.sick > 0.2: s += " • [color=#a0e070]مريض[/color]"
	if h.poison > 0.1: s += " • [color=#e070a0]مسموم[/color]"
	if h.injury > 0.1: s += " • [color=#e07070]مصاب[/color]"
	if h.pregnant_since >= 0.0: s += " • [color=#f0c0f0]حامل (%d يوم)[/color]" % int((now - h.pregnant_since) / 86400.0)
	s += "\n\n[b]ما يشعر به الآن[/b]\n"
	var top: Array = []
	for i in h.drives.size():
		if h.drives[i] > 0.12:
			top.append([h.drives[i], i])
	top.sort_custom(func(a, b): return a[0] > b[0])
	if top.is_empty():
		s += "هدوء.\n"
	for k in mini(top.size(), 4):
		s += "%s %s\n" % [Human.D_AR[top[k][1]], _bar(top[k][0], "#f2c14e")]
	s += "\n[b]الآن[/b]: %s" % Human.ACT_AR.get(h.act, "")
	if h.thought != "":
		s += "\n[i][color=#c0c8ff]%s[/color][/i]" % h.thought
	s += "\n\n[b]اليدان[/b]: %s / %s\n" % [Items.NAME_AR[h.hand_r], Items.NAME_AR[h.hand_l]]
	if h.carrying_child >= 0:
		s += "يحمل صغيراً.\n"
	var learned: Array = []
	for k in h.memory:
		var v: float = h.memory[k][0] / maxf(1.0, h.memory[k][1])
		var ks: String = k
		if h.memory[k][1] >= 2 and absf(v) > 0.2 and ks.count("|") <= 1:
			learned.append([v, ks])
	learned.sort_custom(func(a, b): return absf(a[0]) > absf(b[0]))
	if not learned.is_empty():
		s += "\n[b]ما تعلّمه من التجربة[/b]\n"
		for k in mini(learned.size(), 7):
			var col := "#7ed07e" if learned[k][0] > 0 else "#e07070"
			s += "[color=%s]%s[/color] %s\n" % [col, "✓" if learned[k][0] > 0 else "✗", _key_ar(learned[k][1])]
	if not h.vocab.is_empty():
		s += "\n[b]أصواته[/b]: "
		var ws: Array[String] = []
		for c in h.vocab:
			ws.append("«%s» (%s)" % [h.vocab[c], Language.C_NAME_AR[int(c)]])
		s += "، ".join(ws) + "\n"
	var rel: Array = []
	for k in h.affinity:
		var o := world.human_by_id(int(k))
		if o != null and absf(h.affinity[k]) > 0.15:
			rel.append([h.affinity[k], o])
	rel.sort_custom(func(a, b): return a[0] > b[0])
	if not rel.is_empty():
		s += "\n[b]علاقاته[/b]\n"
		for k in mini(rel.size(), 5):
			var o: Human = rel[k][1]
			var tag := ""
			if o.id == h.mother_id: tag = " (أمّه)"
			elif o.id == h.father_id: tag = " (أبوه)"
			elif o.mother_id == h.id or o.father_id == h.id: tag = " (ولده)"
			var col := "#f0a0d0" if rel[k][0] > 0.4 else ("#7ed07e" if rel[k][0] > 0 else "#e07070")
			var sym := "♥" if rel[k][0] > 0.4 else ("+" if rel[k][0] > 0 else "−")
			s += "[color=%s]%s[/color] %s%s%s\n" % [col, sym, o.label_ar(), tag, "" if o.alive else " (مات)"]
	s += "\n[color=#888888]الجينات: فضول %d • عدوانية %d • اجتماعية %d • قوّة %d[/color]" % [int(h.g_curiosity * 100), int(h.g_aggression * 100), int(h.g_sociability * 100), int(h.g_strength * 100)]
	inspect_text.text = s

func _key_ar(k: String) -> String:
	var parts := k.split("|")
	var p1 := parts[1] if parts.size() > 1 else ""
	match parts[0]:
		"M": return "وضع %s في الفم" % Items.NAME_AR.get(int(p1), "?")
		"PICK": return "التقاط %s" % Items.NAME_AR.get(int(p1), "?")
		"HIT":
			if p1 == "tree": return "هزّ الشجرة"
			if p1 == "human": return "ضرب إنسان"
			var ab := p1.split(">")
			if ab.size() < 2: return "ضرب"
			return "ضرب %s بـ%s" % [Items.NAME_AR.get(int(ab[1]), "?"), Items.NAME_AR.get(int(ab[0]), "?")]
		"RUB":
			var ab := p1.split("+")
			if ab.size() < 2: return "فرك"
			return "فرك %s بـ%s" % [Items.NAME_AR.get(int(ab[0]), "?"), Items.NAME_AR.get(int(ab[1]), "?")]
		"DRINK": return "الشرب من الماء"
		"SLEEP": return "النوم"
		"FIRE": return "وضع %s قرب النار" % Items.NAME_AR.get(int(p1), "?")
		"HUNT":
			var wp := ""
			if parts.size() > 2 and int(parts[2]) != 0:
				wp = " بـ" + Items.NAME_AR.get(int(parts[2]), "")
			return "مطاردة %s%s" % [Animal.K_AR.get(int(p1), "?"), wp]
		"FLEE": return "الهرب"
		"FOLLOW": return "ملازمة الآخرين"
		"GIVE": return "إعطاء %s" % Items.NAME_AR.get(int(p1), "?")
		"MATE": return "الاقتران"
		"GO":
			var names := {"water": "الماء", "fire": "النار", "home": "المكان المعتاد", "fruit": "الثمار", "berry": "التوت", "stone": "الحجارة", "stick": "الأعواد", "meat": "اللحم", "shelter": "المأوى"}
			return "الذهاب إلى " + names.get(p1, p1)
		"WANDER": return "التجوّل"
		"PILE": return "تكويم %s" % Items.NAME_AR.get(int(p1), "?")
		"COVER": return "تغطية الموتى"
		"MARK": return "الخطّ على الصخر"
		"VOC": return "إخراج صوت"
		"GRIEVE": return "الجلوس عند الميت"
		"CARRY": return "حمل الصغير"
		"DROP": return "ترك %s" % Items.NAME_AR.get(int(p1), "?")
	return k

func refresh_chronicle() -> void:
	var s := ""
	var list := Chronicle.recent(120, 1)
	if list.is_empty():
		s = "لا شيء بعد."
	for e in list:
		var col: Color = Chronicle.KIND_COLOR[int(e.kind)]
		var icon: String = Chronicle.KIND_ICON[int(e.kind)]
		var line := "[color=#%s]%s[/color] " % [col.to_html(false), icon]
		line += ("[b]%s[/b]" % e.text) if int(e.imp) >= 3 else str(e.text)
		if e.has("x"):
			line = "[url=%.1f,%.1f]%s[/url]" % [e.x, e.y, line]
		line += "  [color=#777777]%s • %s[/color]\n" % [e.clock, e.date]
		s += line
	chronicle_list.text = s

func refresh_stats() -> void:
	if world == null:
		return
	var living := world.living_count()
	var children := 0
	var elders := 0
	var males := 0
	var now := WorldClock.world_seconds
	var tools := 0
	var words := {}
	var avg_h := 0.0
	for h in world.humans:
		if not h.alive:
			continue
		if h.is_child(now): children += 1
		if h.is_elder(now): elders += 1
		if h.sex == Human.Sex.MALE: males += 1
		if Items.is_weapon(h.hand_l) or Items.is_weapon(h.hand_r) or Items.is_sharp(h.hand_l) or Items.is_sharp(h.hand_r): tools += 1
		for c in h.vocab: words[h.vocab[c]] = true
		avg_h += h.health
	var s := ""
	s += "[b]البشر[/b]: %d حيّ • %d وُلدوا • %d ماتوا\n" % [living, world.born_count, world.died_count]
	s += "أطفال %d • شيوخ %d • ذكور %d • إناث %d\n" % [children, elders, males, living - males]
	if living > 0:
		s += "متوسّط الصحة: %d%%\n" % int(avg_h / living * 100)
	s += "\n[b]ما اكتسبوه[/b]\n"
	s += "نيران أُشعلت بأيديهم: %d\n" % world.stats.fires_made
	s += "أدوات صُنعت: %d • يحمل أدوات الآن: %d\n" % [world.stats.tools_made, tools]
	s += "صيد: %d • وجبات: %d\n" % [world.stats.hunts, world.stats.meals]
	s += "أصوات ذات معنى متداولة: %d\n" % words.size()
	s += "\n[b]الأرض[/b]\n"
	s += "الطقس: %s • %d° • غيوم %d%%\n" % [World.WEATHER_AR[world.weather], int(world.ambient_temp), int(world.cloud_cover * 100)]
	s += "نيران مشتعلة: %d • حيوانات: %d\n" % [world.fires.size(), world.animals.size()]
	s += "الفصل: %s • القمر: %s\n" % [WorldClock.SEASON_NAMES_AR[WorldClock.season()], _moon_ar(WorldClock.moon_phase())]
	s += "\n[b]الإنجازات[/b] (%d)\n" % Chronicle.milestones.size()
	for e in Chronicle.entries:
		if int(e.imp) >= 3:
			s += "▲ %s\n" % e.text
	s += "\n[color=#888888]بذرة الكون: %d[/color]" % Rng.seed_value
	stats_text.text = s

func _moon_ar(p: float) -> String:
	if p < 0.06 or p > 0.94: return "محاق"
	if p < 0.25: return "هلال أول"
	if p < 0.31: return "تربيع أول"
	if p < 0.47: return "أحدب أول"
	if p < 0.53: return "بدر"
	if p < 0.69: return "أحدب ثانٍ"
	if p < 0.75: return "تربيع ثانٍ"
	return "هلال آخر"

func _confirm_new_world() -> void:
	var d := ConfirmationDialog.new()
	d.title = "بداية جديدة"
	d.dialog_text = "سيُمحى هذا الكون بكل ما فيه ومن فيه، ويبدأ كونٌ آخر من العدم.\nهل أنت متأكد؟"
	d.ok_button_text = "نعم، من العدم"
	d.cancel_button_text = "لا"
	add_child(d)
	d.confirmed.connect(func(): new_world_requested.emit(); d.queue_free())
	d.canceled.connect(func(): d.queue_free())
	d.popup_centered()
