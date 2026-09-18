extends Node
## Chronicle — "سِجِلّ الكون": كل ما يحدث يُكتب هنا تلقائياً كتاريخ ينشأ من نفسه.
## لا يوجد كاتب. الأحداث تُسجَّل كما تقع.

signal event_added(entry: Dictionary)

enum Kind { COSMOS, EARTH, LIFE, BIRTH, DEATH, DISCOVERY, SOCIAL, LANGUAGE, CONFLICT, MILESTONE, NATURE }

const KIND_ICON := {
	Kind.COSMOS: "✦", Kind.EARTH: "◍", Kind.LIFE: "❀", Kind.BIRTH: "◉",
	Kind.DEATH: "✝", Kind.DISCOVERY: "★", Kind.SOCIAL: "⚭", Kind.LANGUAGE: "✎",
	Kind.CONFLICT: "⚔", Kind.MILESTONE: "▲", Kind.NATURE: "☂",
}
const KIND_COLOR := {
	Kind.COSMOS: Color(0.75, 0.7, 1.0), Kind.EARTH: Color(0.6, 0.8, 1.0), Kind.LIFE: Color(0.5, 0.9, 0.5),
	Kind.BIRTH: Color(1.0, 0.9, 0.6), Kind.DEATH: Color(0.85, 0.5, 0.5), Kind.DISCOVERY: Color(1.0, 0.85, 0.3),
	Kind.SOCIAL: Color(0.95, 0.65, 0.85), Kind.LANGUAGE: Color(0.6, 0.95, 0.95), Kind.CONFLICT: Color(1.0, 0.45, 0.35),
	Kind.MILESTONE: Color(1.0, 0.75, 0.2), Kind.NATURE: Color(0.55, 0.75, 0.95),
}

const MAX_ENTRIES := 1500
var entries: Array[Dictionary] = []
var milestones: Dictionary = {}  # key -> true (لكي تُسجَّل الإنجازات مرة واحدة)

func add(kind: int, text: String, pos: Vector2 = Vector2.INF, importance: int = 1) -> void:
	var e := {
		"t": WorldClock.world_seconds,
		"kind": kind,
		"text": text,
		"imp": importance,
		"clock": WorldClock.clock_string(),
		"date": WorldClock.date_string_ar(),
	}
	if pos != Vector2.INF:
		e["x"] = pos.x
		e["y"] = pos.y
	entries.append(e)
	if entries.size() > MAX_ENTRIES:
		# نحتفظ بالمهم ونحذف الأقل أهمية أولاً
		var idx := -1
		for i in entries.size():
			if entries[i].imp <= 1:
				idx = i
				break
		if idx >= 0:
			entries.remove_at(idx)
		else:
			entries.remove_at(0)
	event_added.emit(e)

## يُسجّل إنجازاً مرة واحدة فقط في تاريخ العالم
func milestone(key: String, text: String, pos: Vector2 = Vector2.INF) -> bool:
	if milestones.has(key):
		return false
	milestones[key] = true
	add(Kind.MILESTONE, text, pos, 3)
	return true

func has_milestone(key: String) -> bool:
	return milestones.has(key)

func recent(n: int = 30, min_importance: int = 1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i := entries.size() - 1
	while i >= 0 and out.size() < n:
		if entries[i].imp >= min_importance:
			out.append(entries[i])
		i -= 1
	return out

func to_save() -> Dictionary:
	return {"entries": entries, "milestones": milestones}

func from_save(d: Dictionary) -> void:
	entries.clear()
	for e in d.get("entries", []):
		entries.append(e)
	milestones = d.get("milestones", {})
