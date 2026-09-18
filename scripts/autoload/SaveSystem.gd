extends Node
## SaveSystem — حفظ/تحميل العالم كاملاً (JSON مضغوط) في user://
## يحفظ تلقائياً كل دقيقة وعند الخروج/الإيقاف. العالم يستمر حتى لو أُغلق التطبيق.

const PATH := "user://world.save"
const BACKUP := "user://world.bak"
const VERSION := 1

signal saved()
signal loaded()

var autosave_interval := 60.0
var _timer := 45.0  # أول حفظ بعد 15 ثانية من الدخول
var world_ref: RefCounted = null
var last_saved_at: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func has_save() -> bool:
	return FileAccess.file_exists(PATH)

func _process(delta: float) -> void:
	if world_ref == null:
		return
	_timer += delta
	if _timer >= autosave_interval:
		_timer = 0.0
		save_now()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if world_ref != null:
			save_now()

func save_now() -> void:
	if world_ref == null or not world_ref.has_method("to_save"):
		return
	var data := {
		"version": VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"seed": Rng.seed_value,
		"rng_state": Rng.state(),
		"epoch": WorldClock.world_epoch,
		"offset": WorldClock.time_offset,
		"speed": WorldClock.speed_multiplier,
		"chronicle": Chronicle.to_save(),
		"world": world_ref.to_save(),
	}
	var json := JSON.stringify(data)
	if FileAccess.file_exists(PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(PATH), ProjectSettings.globalize_path(BACKUP))
	var f := FileAccess.open_compressed(PATH, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		Log.err("تعذر حفظ العالم: %s" % FileAccess.get_open_error())
		return
	f.store_string(json)
	f.close()
	last_saved_at = Time.get_unix_time_from_system()
	saved.emit()

func load_data() -> Dictionary:
	var f := FileAccess.open_compressed(PATH, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		f = FileAccess.open_compressed(BACKUP, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		Log.err("ملف الحفظ تالف")
		return {}
	return parsed

func delete_save() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	if FileAccess.file_exists(BACKUP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP))
