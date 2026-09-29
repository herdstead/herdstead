class_name DayLight
## Day and night over the one pack: how far into night a local time of day is,
## and what that does to the world. Night is the time of day, never a herdr
## state: it binds no field, so it is lighting, not a signal (docs/VISUAL_LANGUAGE.md).
## Pure: the office reads the clock and hands the minutes in.

## Local minutes after midnight where day starts and where it ends.
const DAWN := 7 * 60
const DUSK := 18 * 60
## Minutes the light takes to change, centred on each of them.
const FADE := 30.0
## The world's tint at full night: darker and cooler, never the grey of a lost
## connection (the stale tint), and the people still move (invariant 4). The HUD
## is its own canvas layer and keeps its colours.
const NIGHT_TINT := Color(0.66, 0.70, 0.88)
## How much harder a task lamp and a chair's contact shadow draw at full night,
## over the pack's own strength; the world's tint dims the lamps with the rest.
const NIGHT_LAMPS := 1.8
const MINUTES_A_DAY := 24 * 60


## 0 by day, 1 by night, and in between during the FADE round DAWN and DUSK.
static func night_at(minutes: float) -> float:
	var at := fposmod(minutes, MINUTES_A_DAY)
	var half := FADE / 2.0
	if at <= DAWN - half or at >= DUSK + half:
		return 1.0
	if at >= DAWN + half and at <= DUSK - half:
		return 0.0
	if at < DAWN + half:
		return (DAWN + half - at) / FADE
	return (at - (DUSK - half)) / FADE


## Whether `night` (0..1) reads as night: past the middle of a fade.
static func is_night(night: float) -> bool:
	return night >= 0.5


## The world's modulate at `night` (0..1).
static func tint(night: float) -> Color:
	return Color.WHITE.lerp(NIGHT_TINT, clampf(night, 0.0, 1.0))
