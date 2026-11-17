class_name FOUiScale
extends RefCounted
## UI scale: a continuous factor applied as Window.content_scale_factor.
##
## "auto" takes the larger of what the display suggests (the OS display scale
## or, failing that, the DPI) and what the window's resolution suggests, then
## caps it so the logical window never gets smaller than the minimum layout
## size. A number ("1.25") is used as given, within the supported range and
## that same cap.

const MIN_SCALE := 0.75
const MAX_SCALE := 2.0
const STEP := 0.05
const REFERENCE_DPI := 96.0
## Smallest logical window size the layouts are designed for (desktop-first).
const MIN_LOGICAL_SIZE := Vector2i(1280, 720)
## Window size at which "auto" is 100% by resolution.
const REFERENCE_SIZE := Vector2i(1920, 1080)


## Parses the ui.scale option value; returns -1.0 for "auto" or invalid values.
static func parse_setting(value: String) -> float:
	var trimmed := value.strip_edges().to_lower()
	if trimmed.is_empty() or trimmed == "auto" or not trimmed.is_valid_float():
		return -1.0
	return clampf(snappedf(trimmed.to_float(), STEP), MIN_SCALE, MAX_SCALE)


## Scale suggested by the display: OS scale (macOS, Wayland) or DPI / 96.
static func display_scale(os_scale: float, dpi: int) -> float:
	var scale := os_scale if os_scale > 1.0 else float(dpi) / REFERENCE_DPI
	# Never shrink below 100% automatically: low DPI reports are often wrong.
	return clampf(snappedf(scale, STEP), 1.0, MAX_SCALE)


## Scale suggested by the window's resolution: the layouts are drawn for
## about REFERENCE_SIZE, so a 2560x1440 window gets 1.35 and 4K 2.0 even when
## the display reports 96 DPI (as X11 and many monitors do). Never below 1.
static func resolution_scale(window_size: Vector2i) -> float:
	var fit := minf(
		float(window_size.x) / REFERENCE_SIZE.x, float(window_size.y) / REFERENCE_SIZE.y
	)
	return clampf(snappedf(fit, STEP), 1.0, MAX_SCALE)


## Largest scale that keeps the logical window at least MIN_LOGICAL_SIZE:
## below 100% in a window smaller than that (80% at 1024 × 640, where the
## top bar alone needs 1200 px), down to MIN_SCALE.
static func max_scale_for_window(window_size: Vector2i) -> float:
	var fit := minf(
		float(window_size.x) / MIN_LOGICAL_SIZE.x, float(window_size.y) / MIN_LOGICAL_SIZE.y
	)
	# (A little slack: 2.0 / 0.05 is 39.999... in floating point.)
	return maxf(MIN_SCALE, floorf(fit / STEP + 0.001) * STEP)


## Final factor for a window: the manual setting if given, else the auto value
## capped to fit the window.
static func resolve(setting: String, os_scale: float, dpi: int, window_size: Vector2i) -> float:
	var manual := parse_setting(setting)
	if manual > 0.0:
		# As chosen, but never so large the layouts don't fit the window.
		return minf(manual, max_scale_for_window(window_size))
	var suggested := maxf(display_scale(os_scale, dpi), resolution_scale(window_size))
	return minf(suggested, max_scale_for_window(window_size))
