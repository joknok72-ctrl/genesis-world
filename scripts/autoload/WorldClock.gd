extends Node
## WorldClock — الزمن الحقيقي 1:1
## الثانية في العالم = ثانية حقيقية. الساعة = ساعة. اليوم = 24 ساعة حقيقية.
## ساعة العالم مضبوطة على ساعة جهازك المحلية: إذا كان الليل عندك فهو ليلٌ في العالم،
## وإذا كان الشتاء في تقويمك فهو شتاءٌ هناك. (يعتمد على ساعة الجهاز وليس على عدد الإطارات،
## لذلك حتى لو أُغلق التطبيق فإن العالم "يواصل العيش" ويُلحق ما فاته عند الفتح.)

signal second_ticked(world_seconds: float)
signal minute_changed(minute_index: int)
signal hour_changed(hour: int)
signal day_changed(day_index: int)
signal season_changed(season: int)

const SECONDS_PER_MINUTE := 60.0
const SECONDS_PER_HOUR := 3600.0
const SECONDS_PER_DAY := 86400.0
const DAYS_PER_YEAR := 365
const SECONDS_PER_YEAR := SECONDS_PER_DAY * 365.25

enum Season { SPRING, SUMMER, AUTUMN, WINTER }
const SEASON_NAMES_AR := ["الربيع", "الصيف", "الخريف", "الشتاء"]
const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

## لحظة ظهور الإنسان الأول على الأرض (Unix). قبلها لا يوجد "زمن أرضي".
var world_epoch: float = 0.0
## إزاحة تُضاف فقط لو فعّل المستخدم "المراقبة السريعة" الاختيارية.
var time_offset: float = 0.0
## مضاعف اختياري — الافتراضي 1.0 (زمن حقيقي تماماً). أي قيمة أخرى اختيارٌ صريح من المستخدم.
var speed_multiplier: float = 1.0
var running: bool = false

var world_seconds: float = 0.0       # عمر العالم البشري بالثواني
var _tz_offset: float = 0.0
var _last_minute := -1
var _last_hour := -1
var _last_day := -1
var _last_season := -1
var _accum := 0.0
var _last_real := 0.0
var _cached_doy := -1
var _cached_doy_day := -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_real = Time.get_unix_time_from_system()
	var tz := Time.get_time_zone_from_system()
	_tz_offset = float(tz.get("bias", 0)) * 60.0

func start_new_world() -> void:
	world_epoch = Time.get_unix_time_from_system()
	time_offset = 0.0
	running = true
	_sync_markers()

func resume_world(epoch: float, offset: float) -> void:
	world_epoch = epoch
	time_offset = offset
	running = true
	_sync_markers()

func _sync_markers() -> void:
	_recompute()
	_last_minute = minute_of_day()
	_last_hour = hour_of_day()
	_last_day = day_index()
	_last_season = season()

func stop() -> void:
	running = false

func _process(delta: float) -> void:
	if not running:
		return
	var now := Time.get_unix_time_from_system()
	var real_dt := now - _last_real
	_last_real = now
	if speed_multiplier != 1.0:
		time_offset += real_dt * (speed_multiplier - 1.0)
	_recompute()
	_accum += real_dt
	if _accum >= 1.0:
		_accum = fmod(_accum, 1.0)
		second_ticked.emit(world_seconds)
	var m := minute_of_day()
	if m != _last_minute:
		_last_minute = m
		minute_changed.emit(m)
	var h := hour_of_day()
	if h != _last_hour:
		_last_hour = h
		hour_changed.emit(h)
	var d := day_index()
	if d != _last_day:
		_last_day = d
		day_changed.emit(d)
	var s := season()
	if s != _last_season:
		_last_season = s
		season_changed.emit(s)

func _recompute() -> void:
	world_seconds = maxf(0.0, Time.get_unix_time_from_system() - world_epoch + time_offset)

## الزمن المحلي "الحقيقي" للعالم (يوافق ساعة الجهاز + الإزاحة)
func local_seconds() -> float:
	return Time.get_unix_time_from_system() + _tz_offset + time_offset

## ---- استعلامات الزمن ----
func seconds_of_day() -> float:
	return fposmod(local_seconds(), SECONDS_PER_DAY)

func hour_of_day() -> int:
	return int(seconds_of_day() / SECONDS_PER_HOUR)

func minute_of_day() -> int:
	return int(seconds_of_day() / SECONDS_PER_MINUTE)

func minute_of_hour() -> int:
	return int(fmod(seconds_of_day(), SECONDS_PER_HOUR) / SECONDS_PER_MINUTE)

func second_of_minute() -> int:
	return int(fmod(seconds_of_day(), SECONDS_PER_MINUTE))

## عدد الأيام منذ ظهور الإنسان
func day_index() -> int:
	return int(world_seconds / SECONDS_PER_DAY)

func year_index() -> int:
	return int(world_seconds / SECONDS_PER_YEAR)

## يوم السنة بحسب التقويم الحقيقي (0 = 1 يناير)
func day_of_year() -> int:
	var abs_day := int(local_seconds() / SECONDS_PER_DAY)
	if abs_day == _cached_doy_day:
		return _cached_doy
	var dt := Time.get_datetime_dict_from_unix_time(int(local_seconds()))
	var doy := 0
	for m in range(0, int(dt.month) - 1):
		doy += MONTH_DAYS[m]
	doy += int(dt.day) - 1
	_cached_doy = doy
	_cached_doy_day = abs_day
	return doy

## الفصل بحسب النصف الشمالي للكرة الأرضية
func season() -> int:
	var d := day_of_year()
	if d >= 79 and d < 172:
		return Season.SPRING
	if d >= 172 and d < 266:
		return Season.SUMMER
	if d >= 266 and d < 355:
		return Season.AUTUMN
	return Season.WINTER

## نسبة اليوم 0..1 (0 = منتصف الليل)
func day_fraction() -> float:
	return seconds_of_day() / SECONDS_PER_DAY

## ارتفاع الشمس -1..1 (الليالي أطول شتاءً والأيام أطول صيفاً)
func sun_elevation() -> float:
	var f := day_fraction()
	var season_tilt := 0.18 * cos(TAU * float(day_of_year() - 172) / 365.0)
	return -cos(f * TAU) + season_tilt

## ضوء النهار 0..1 مع غسق ناعم
func daylight() -> float:
	return clampf(smoothstep(-0.28, 0.28, sun_elevation()), 0.0, 1.0)

func is_night() -> bool:
	return daylight() < 0.15

## طور القمر 0..1 (دورة 29.53 يوماً، مضبوطة على قمر حقيقي تقريبي)
func moon_phase() -> float:
	var ref := 1704598800.0  # قمر جديد مرجعي: 11 يناير 2024
	return fposmod((local_seconds() - ref) / (SECONDS_PER_DAY * 29.530588), 1.0)

func clock_string() -> String:
	return "%02d:%02d:%02d" % [hour_of_day(), minute_of_hour(), second_of_minute()]

func date_string_ar() -> String:
	var parts: Array[String] = []
	var y := year_index()
	if y > 0:
		parts.append("السنة %d" % (y + 1))
	parts.append("اليوم %d" % (day_index() + 1))
	parts.append(SEASON_NAMES_AR[season()])
	return " • ".join(parts)

## يحوّل عدد الثواني إلى نص عربي مقروء
static func duration_ar(sec: float) -> String:
	sec = maxf(0.0, sec)
	var days := int(sec / SECONDS_PER_DAY)
	var hours := int(fmod(sec, SECONDS_PER_DAY) / SECONDS_PER_HOUR)
	var mins := int(fmod(sec, SECONDS_PER_HOUR) / SECONDS_PER_MINUTE)
	var out: Array[String] = []
	if days > 0:
		out.append("%d يوم" % days)
	if hours > 0:
		out.append("%d ساعة" % hours)
	if mins > 0 and days == 0:
		out.append("%d دقيقة" % mins)
	if out.is_empty():
		out.append("%d ثانية" % int(sec))
	return " و".join(out)

static func age_ar(seconds_alive: float) -> String:
	var years := int(seconds_alive / SECONDS_PER_YEAR)
	var days := int(fmod(seconds_alive, SECONDS_PER_YEAR) / SECONDS_PER_DAY)
	if years > 0:
		return "%d سنة و%d يوم" % [years, days]
	if days > 0:
		var h := int(fmod(seconds_alive, SECONDS_PER_DAY) / SECONDS_PER_HOUR)
		return "%d يوم و%d ساعة" % [days, h]
	return duration_ar(seconds_alive)
