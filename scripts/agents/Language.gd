class_name Language
## Language — لا توجد لغة في البداية. الأصوات تُخترع عند الحاجة، وتنتقل بالسماع،
## وتتقارب داخل الجماعة حتى تصبح "كلمات مشتركة". هذا هو المولّد الصوتي فقط.

const CONSONANTS := ["ب", "ت", "ك", "م", "ن", "ر", "ل", "س", "د", "ش", "ح", "غ", "ط", "ز", "ف", "ع", "ه", "ج"]
const VOWELS := ["ا", "و", "ي", "ا", "ي"]

## المفاهيم التي قد يشعر الإنسان بالحاجة للتعبير عنها (ليست كلمات، بل حالات داخلية)
enum C { SELF, WATER, FOOD, DANGER, FIRE, COME, GO_AWAY, GOOD, BAD, PAIN, MATE, CHILD, SLEEP, THIS, GIVE, ANIMAL, DEATH, RAIN, COLD, HOT }
const C_NAME_AR := {
	C.SELF: "أنا", C.WATER: "ماء", C.FOOD: "طعام", C.DANGER: "خطر", C.FIRE: "نار",
	C.COME: "تعال", C.GO_AWAY: "ابعد", C.GOOD: "جيد", C.BAD: "سيء", C.PAIN: "ألم",
	C.MATE: "رفيق", C.CHILD: "صغير", C.SLEEP: "نوم", C.THIS: "هذا", C.GIVE: "أعطِ",
	C.ANIMAL: "حيوان", C.DEATH: "موت", C.RAIN: "مطر", C.COLD: "برد", C.HOT: "حرّ",
}

static func invent_word(syllables: int = -1) -> String:
	if syllables < 0:
		syllables = 1 if Rng.chance(0.45) else 2
	var w := ""
	for i in syllables:
		w += Rng.pick(CONSONANTS)
		w += Rng.pick(VOWELS)
		if Rng.chance(0.2):
			w += Rng.pick(CONSONANTS)
	return w

## تحوير صوتي بسيط عند التقليد غير المتقن (كي تتفرّع اللهجات)
static func mutate(word: String) -> String:
	if word.length() < 2 or not Rng.chance(0.12):
		return word
	var i := Rng.randi_range(0, word.length() - 1)
	var ch := word[i]
	var rep: String
	if ch in VOWELS:
		rep = Rng.pick(VOWELS)
	else:
		rep = Rng.pick(CONSONANTS)
	return word.substr(0, i) + rep + word.substr(i + 1)
