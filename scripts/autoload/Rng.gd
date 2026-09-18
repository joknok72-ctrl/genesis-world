extends Node
## Rng — مولّد عشوائي حتمي (Deterministic) لكل العالم
## نفس البذرة => نفس الكون. البذرة تُحفظ مع اللعبة حتى تستمر نفس الحكاية.

var seed_value: int = 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	if seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system()) ^ randi()
	reseed(seed_value)

func reseed(s: int) -> void:
	seed_value = s
	_rng.seed = s

func randf() -> float:
	return _rng.randf()

func randf_range(a: float, b: float) -> float:
	return _rng.randf_range(a, b)

func randi_range(a: int, b: int) -> int:
	return _rng.randi_range(a, b)

func randfn(mean: float = 0.0, dev: float = 1.0) -> float:
	return _rng.randfn(mean, dev)

func chance(p: float) -> bool:
	return _rng.randf() < p

func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[_rng.randi_range(0, arr.size() - 1)]

func weighted_pick(weights: Array[float]) -> int:
	var total := 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return 0
	var r := _rng.randf() * total
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			return i
	return weights.size() - 1

func state() -> int:
	return _rng.state

func set_state(s: int) -> void:
	_rng.state = s
