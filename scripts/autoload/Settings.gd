extends Node
## Settings — إعدادات المستخدم (تُحفظ محلياً)

const PATH := "user://settings.cfg"

var music_volume: float = 0.7
var sfx_volume: float = 0.8
var show_labels: bool = true
var show_thoughts: bool = true
var reduce_effects: bool = false   # لتوفير البطارية على الهواتف الضعيفة
var haptics: bool = true

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	show_labels = cfg.get_value("view", "labels", show_labels)
	show_thoughts = cfg.get_value("view", "thoughts", show_thoughts)
	reduce_effects = cfg.get_value("view", "reduce_effects", reduce_effects)
	haptics = cfg.get_value("view", "haptics", haptics)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("view", "labels", show_labels)
	cfg.set_value("view", "thoughts", show_thoughts)
	cfg.set_value("view", "reduce_effects", reduce_effects)
	cfg.set_value("view", "haptics", haptics)
	cfg.save(PATH)

func vibrate(ms: int = 20) -> void:
	if haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)
