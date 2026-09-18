extends Node
## Log — تسجيل داخلي خفيف (لا يؤثر على الأداء في نسخة الموبايل)

var enabled: bool = OS.is_debug_build()
var _buffer: PackedStringArray = []
const MAX_LINES := 400

func info(msg: String) -> void:
	_push("[INFO] " + msg)

func warn(msg: String) -> void:
	_push("[WARN] " + msg)

func err(msg: String) -> void:
	_push("[ERR ] " + msg)
	push_error(msg)

func _push(line: String) -> void:
	if not enabled:
		return
	_buffer.append(line)
	if _buffer.size() > MAX_LINES:
		_buffer.remove_at(0)
	print(line)

func dump() -> String:
	return "\n".join(_buffer)
