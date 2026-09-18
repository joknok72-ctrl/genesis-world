class_name Items
## Items — "قوانين المادة" في هذا العالم. هذه ليست معرفة للبشر؛ هذه هي الفيزياء.
## البشر لا يعرفون أي شيء منها. يكتشفونها بالتجربة (أو لا يكتشفونها أبداً).

enum T {
	NONE, STONE, STICK, SHARP_STONE, SPEAR, CLUB, FRUIT, ROOT, BERRY, POISON_BERRY,
	RAW_MEAT, COOKED_MEAT, HIDE, FIBER, ROPE, EGG, SHELL, BONE, BONE_NEEDLE, CLAY, POT,
	WATER_SKIN, SEED, GRAIN, FLOUR, BREAD, CHARCOAL, PIGMENT
}

const NAME_AR := {
	T.NONE: "لا شيء", T.STONE: "حجر", T.STICK: "عود خشب", T.SHARP_STONE: "حجر مسنّن",
	T.SPEAR: "رمح", T.CLUB: "هراوة", T.FRUIT: "ثمرة", T.ROOT: "جذر", T.BERRY: "توت",
	T.POISON_BERRY: "توت سامّ", T.RAW_MEAT: "لحم نيئ", T.COOKED_MEAT: "لحم مشويّ",
	T.HIDE: "جلد", T.FIBER: "ألياف", T.ROPE: "حبل", T.EGG: "بيضة", T.SHELL: "صَدَفة",
	T.BONE: "عظمة", T.BONE_NEEDLE: "إبرة عظم", T.CLAY: "طين", T.POT: "إناء طين",
	T.WATER_SKIN: "قربة ماء", T.SEED: "بذور", T.GRAIN: "حبوب", T.FLOUR: "دقيق",
	T.BREAD: "خبز", T.CHARCOAL: "فحم", T.PIGMENT: "صبغة",
}

const COLOR := {
	T.STONE: Color(0.55, 0.55, 0.58), T.STICK: Color(0.55, 0.38, 0.2), T.SHARP_STONE: Color(0.75, 0.75, 0.8),
	T.SPEAR: Color(0.8, 0.6, 0.35), T.CLUB: Color(0.45, 0.3, 0.15), T.FRUIT: Color(0.95, 0.35, 0.25),
	T.ROOT: Color(0.8, 0.65, 0.4), T.BERRY: Color(0.45, 0.2, 0.7), T.POISON_BERRY: Color(0.9, 0.15, 0.4),
	T.RAW_MEAT: Color(0.8, 0.25, 0.25), T.COOKED_MEAT: Color(0.5, 0.25, 0.1), T.HIDE: Color(0.7, 0.55, 0.35),
	T.FIBER: Color(0.75, 0.75, 0.45), T.ROPE: Color(0.7, 0.6, 0.3), T.EGG: Color(0.95, 0.93, 0.85),
	T.SHELL: Color(0.9, 0.85, 0.8), T.BONE: Color(0.92, 0.9, 0.82), T.BONE_NEEDLE: Color(0.98, 0.97, 0.9),
	T.CLAY: Color(0.6, 0.45, 0.35), T.POT: Color(0.65, 0.4, 0.3), T.WATER_SKIN: Color(0.55, 0.45, 0.35),
	T.SEED: Color(0.8, 0.75, 0.45), T.GRAIN: Color(0.9, 0.8, 0.4), T.FLOUR: Color(0.97, 0.95, 0.9),
	T.BREAD: Color(0.85, 0.65, 0.35), T.CHARCOAL: Color(0.12, 0.12, 0.12), T.PIGMENT: Color(0.8, 0.3, 0.2),
}

## هل يُؤكل؟ وما أثره على الجسم (سعرات، ماء، سُمّ، خطر مرض)
static func food_effect(t: int) -> Dictionary:
	match t:
		T.FRUIT: return {"cal": 0.22, "water": 0.12, "poison": 0.0, "sick": 0.0}
		T.ROOT: return {"cal": 0.25, "water": 0.03, "poison": 0.0, "sick": 0.02}
		T.BERRY: return {"cal": 0.12, "water": 0.08, "poison": 0.0, "sick": 0.0}
		T.POISON_BERRY: return {"cal": 0.05, "water": 0.05, "poison": 0.4, "sick": 0.5}
		T.RAW_MEAT: return {"cal": 0.45, "water": 0.05, "poison": 0.0, "sick": 0.3}
		T.COOKED_MEAT: return {"cal": 0.6, "water": 0.02, "poison": 0.0, "sick": 0.01}
		T.EGG: return {"cal": 0.2, "water": 0.05, "poison": 0.0, "sick": 0.08}
		T.GRAIN: return {"cal": 0.15, "water": 0.0, "poison": 0.0, "sick": 0.02}
		T.BREAD: return {"cal": 0.5, "water": 0.0, "poison": 0.0, "sick": 0.0}
		T.SEED: return {"cal": 0.06, "water": 0.0, "poison": 0.0, "sick": 0.02}
		T.FLOUR: return {"cal": 0.1, "water": -0.05, "poison": 0.0, "sick": 0.02}
		T.CLAY: return {"cal": 0.0, "water": 0.0, "poison": 0.1, "sick": 0.5}
		T.CHARCOAL: return {"cal": 0.0, "water": 0.0, "poison": 0.05, "sick": 0.2}
		_: return {}

static func is_edible(t: int) -> bool:
	return not food_effect(t).is_empty()

## قوة الضرب بالأداة (اليد الفارغة = 1.0)
static func strike_power(t: int) -> float:
	match t:
		T.SPEAR: return 3.2
		T.CLUB: return 2.4
		T.SHARP_STONE: return 1.8
		T.STONE: return 1.5
		T.STICK: return 1.2
		T.BONE: return 1.3
		_: return 1.0

static func is_weapon(t: int) -> bool:
	return strike_power(t) > 1.4

static func is_fuel(t: int) -> bool:
	return t == T.STICK or t == T.CLUB or t == T.SPEAR or t == T.CHARCOAL

## هل ينفع كأداة قطع؟
static func is_sharp(t: int) -> bool:
	return t == T.SHARP_STONE or t == T.SPEAR

## ---- تفاعلات المادة: ضرب "held" على "target" ----
## تُعيد {result: نوع جديد, consume_target: bool, consume_held: bool, chance: float}
static func strike_recipe(held: int, target: int) -> Dictionary:
	if held == T.STONE and target == T.STONE:
		return {"result": T.SHARP_STONE, "consume_target": true, "consume_held": false, "chance": 0.22}
	if held == T.SHARP_STONE and target == T.STONE:
		return {"result": T.SHARP_STONE, "consume_target": true, "consume_held": false, "chance": 0.35}
	if held == T.SHARP_STONE and target == T.STICK:
		return {"result": T.SPEAR, "consume_target": true, "consume_held": false, "chance": 0.3}
	if held == T.STONE and target == T.STICK:
		return {"result": T.CLUB, "consume_target": true, "consume_held": false, "chance": 0.18}
	if held == T.SHARP_STONE and target == T.BONE:
		return {"result": T.BONE_NEEDLE, "consume_target": true, "consume_held": false, "chance": 0.2}
	if held == T.STONE and target == T.GRAIN:
		return {"result": T.FLOUR, "consume_target": true, "consume_held": false, "chance": 0.5}
	if held == T.STONE and target == T.SEED:
		return {"result": T.FLOUR, "consume_target": true, "consume_held": false, "chance": 0.3}
	if held == T.SHARP_STONE and target == T.HIDE:
		return {"result": T.ROPE, "consume_target": true, "consume_held": false, "chance": 0.25}
	if (held == T.STONE or held == T.SHARP_STONE) and target == T.SHELL:
		return {"result": T.PIGMENT, "consume_target": true, "consume_held": false, "chance": 0.3}
	return {}

## ---- فرك عنصرين معاً ----
## STICK×STICK => حرارة (النار تُدار في World لأنها تحتاج تراكم)
static func rub_recipe(a: int, b: int) -> Dictionary:
	if a == T.FIBER and b == T.FIBER:
		return {"result": T.ROPE, "consume_a": true, "consume_b": true, "chance": 0.35}
	if a == T.CLAY and b == T.CLAY:
		return {"result": T.POT, "consume_a": true, "consume_b": true, "chance": 0.3}
	if (a == T.HIDE and b == T.ROPE) or (a == T.ROPE and b == T.HIDE):
		return {"result": T.WATER_SKIN, "consume_a": true, "consume_b": true, "chance": 0.3}
	return {}

## ---- أثر النار على عنصر موضوع بجانبها ----
static func fire_transform(t: int) -> int:
	match t:
		T.RAW_MEAT: return T.COOKED_MEAT
		T.FLOUR: return T.BREAD
		T.STICK: return T.CHARCOAL
		T.EGG: return T.COOKED_MEAT
		_: return T.NONE
