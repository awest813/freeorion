class_name HintCoach
extends Control
## First-time hints: a short tip the first time the player meets a part of
## the game (the map, End turn, a screen, a panel), next to it. One shows at
## a time, the others wait their turn. "Got it" marks a hint seen; "No more
## hints" turns them off. Seen hints and the switch are kept in options
## (ui.hints.seen, ui.hints.enabled); Options can show them again.

const OPTION_SEEN := "ui.hints.seen"
const OPTION_ENABLED := "ui.hints.enabled"
## Hints: id -> text key.
const HINTS := {
	"map": "HINT_MAP",
	"end_turn": "HINT_END_TURN",
	"fleet": "HINT_FLEET",
	"planet": "HINT_PLANET",
	"production": "HINT_PRODUCTION",
	"research": "HINT_RESEARCH",
	"government": "HINT_GOVERNMENT",
	"design": "HINT_DESIGN",
	"objects": "HINT_OBJECTS",
	"empires": "HINT_EMPIRES",
	"pedia": "HINT_PEDIA",
}
## Hints about the map: they wait while a full screen is open (they'd
## cover its controls). A screen's hint shows only on that screen.
const MAP_HINTS := ["map", "end_turn", "fleet", "planet"]
## Hotkeys hints name, filled in for %1%.
const HINT_HOTKEYS := {"end_turn": "end_turn"}
const WIDTH := 340

## Hints are kept in the options; tests turn this off.
var persist := true
var enabled := true
## Seen hints: id -> true.
var seen := {}
## The hint on screen ("" for none) and those waiting: [id, anchor].
var current := ""
## The full screen open ("" for the map).
var screen := ""
var _queue: Array = []
var _anchor: Control
var _card: PanelContainer
var _text: Label
var _placing := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_card = PanelContainer.new()
	_card.theme_type_variation = "OverlayPanel"
	_card.visible = false
	_card.custom_minimum_size.x = WIDTH
	# Its height settles once the text wraps: place it again then.
	_card.resized.connect(_place)
	add_child(_card)
	var box := VBoxContainer.new()
	_card.add_child(box)
	box.add_child(ScreenKit.label(tr("HINT_TITLE"), "SecondaryLabel"))
	_text = ScreenKit.label("")
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	var stop := Button.new()
	stop.text = tr("HINT_STOP")
	stop.theme_type_variation = "GhostButton"
	stop.pressed.connect(turn_off)
	row.add_child(stop)
	var got_it := Button.new()
	got_it.text = tr("HINT_GOT_IT")
	got_it.theme_type_variation = "PrimaryButton"
	got_it.pressed.connect(dismiss)
	row.add_child(got_it)


func _ready() -> void:
	if persist and Engine.has_singleton("FOOptions"):
		var options := Engine.get_singleton("FOOptions")
		options.add_option(OPTION_SEEN, "OPTIONS_DB_UI_HINTS_SEEN", "")
		options.add_option(OPTION_ENABLED, "OPTIONS_DB_UI_HINTS_ENABLED", true)
		_load(options)
		# Options can show the hints again while a game runs.
		options.watch(OPTION_SEEN)
		options.watch(OPTION_ENABLED)
		options.option_changed.connect(
			func(option: String):
				if option in [OPTION_SEEN, OPTION_ENABLED]:
					_load(options)
		)


func _load(options: Object) -> void:
	enabled = options.get_value(OPTION_ENABLED)
	seen.clear()
	for id in str(options.get_value(OPTION_SEEN)).split(" ", false):
		seen[id] = true


## Show hint \a id next to \a anchor (or near the top of the map) unless it
## was seen, hints are off, or it is shown or waiting already.
func offer(id: String, anchor: Control = null) -> void:
	if not enabled or seen.has(id) or not HINTS.has(id) or id == current:
		return
	for waiting in _queue:
		if waiting[0] == id:
			return
	_queue.push_back([id, anchor])
	if current.is_empty():
		_show_next()


## The full screen \a screen_name opened ("" for back to the map): hints
## for elsewhere step aside, and the screen's own hint comes first.
func screen_shown(screen_name: String) -> void:
	screen = screen_name
	if not current.is_empty() and not _fits(current):
		_queue.push_front([current, _anchor])
		current = ""
		_card.visible = false
	if not screen_name.is_empty() and enabled and HINTS.has(screen_name):
		if not seen.has(screen_name) and current != screen_name:
			_queue = _queue.filter(func(w): return w[0] != screen_name)
			_queue.push_front([screen_name, null])
	if current.is_empty():
		_show_next()


# Whether hint \a id belongs where the player is now.
func _fits(id: String) -> bool:
	if id in MAP_HINTS:
		return screen.is_empty()
	return id == screen


## Mark the shown hint seen and show the next one.
func dismiss() -> void:
	if current.is_empty():
		return
	seen[current] = true
	_save()
	current = ""
	_card.visible = false
	_show_next()


## No more hints (Options can turn them back on).
func turn_off() -> void:
	enabled = false
	_queue.clear()
	current = ""
	_card.visible = false
	_save()


## Forget which hints were seen and turn them on again.
func reset() -> void:
	seen.clear()
	enabled = true
	_save()


func _show_next() -> void:
	# The first waiting hint that belongs here; the others keep waiting.
	_queue = _queue.filter(func(w): return not seen.has(w[0]))
	for i in _queue.size():
		if not _fits(_queue[i][0]):
			continue
		var next: Array = _queue.pop_at(i)
		current = next[0]
		_anchor = next[1] if is_instance_valid(next[1]) else null
		# %1% is the key of the hotkey a hint mentions (it can be rebound).
		_text.text = tr(HINTS[current]).replace(
			"%1%", FOHotkeys.binding(HINT_HOTKEYS.get(current, ""))
		)
		_card.size = Vector2(WIDTH, 0)
		_card.visible = true
		FOUi.fade_in(_card)
		_place.call_deferred()
		return


# Below the anchor if there's room, else above it; near the top middle
# without one (a screen's hint: its bottom right). Always inside the screen.
func _place() -> void:
	if not _card.visible or _placing:
		return
	_placing = true
	# Shrink to the wrapped text: a first pass may have made it taller.
	_card.reset_size()
	var card_size := _card.size
	var gap := FOUi.tokens.space_2
	var position := Vector2((size.x - card_size.x) / 2.0, size.y * 0.15)
	# A screen's hint sits in its bottom right corner, clear of the filters
	# and pickers along the top.
	if not current in MAP_HINTS:
		position = size - card_size - Vector2.ONE * gap * 2.0
	if _anchor and _anchor.is_visible_in_tree():
		var rect := _anchor.get_global_rect()
		var local := rect.position - global_position
		position = Vector2(
			local.x + rect.size.x / 2.0 - card_size.x / 2.0, local.y + rect.size.y + gap
		)
		if position.y + card_size.y > size.y:
			position.y = local.y - card_size.y - gap
	position.x = clampf(position.x, gap, maxf(gap, size.x - card_size.x - gap))
	position.y = clampf(position.y, gap, maxf(gap, size.y - card_size.y - gap))
	_card.position = position
	_placing = false


func _save() -> void:
	if not persist or not Engine.has_singleton("FOOptions"):
		return
	var options := Engine.get_singleton("FOOptions")
	options.set_value(OPTION_SEEN, " ".join(PackedStringArray(seen.keys())))
	options.set_value(OPTION_ENABLED, enabled)
	options.commit()
