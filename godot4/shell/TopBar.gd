class_name TopBar
extends PanelContainer
## In-game top bar: empire (colour + name), screen buttons, turn number and
## End Turn, and below them the empire's resources (each opens its screen).
## Follows the running game unless follow_game is false; set_state() then
## drives it directly (tests, previews).

## A screen button was pressed: the screen's name, or "" to return to the map.
signal screen_requested(screen_name: String)
## The Menu button was pressed (Esc on the map does the same, in GameShell).
signal menu_requested

## Ctrl+Enter ends the turn, as a keyboard path to the primary action.
const END_TURN_KEY := KEY_ENTER
## Screen buttons: name, label key, shortcut.
## Save (F5) and Options (F10) are in the in-game menu.
const SCREENS := [
	["production", "MAP_BTN_PRODUCTION", KEY_F2],
	["research", "MAP_BTN_RESEARCH", KEY_F3],
	["government", "GOVERNMENT_TAB", KEY_F4],
	["design", "DESIGNER_TAB", KEY_F6],
	["objects", "MAP_BTN_OBJECTS", KEY_F8],
	["combat", "COMBAT_TAB", KEY_F7],
	["empires", "EMPIRES_TAB", KEY_F9],
	["pedia", "MAP_BTN_PEDIA", KEY_F1],
]

## Resource chips: key in get_empire_resources(), icon, screen to open,
## tooltip key.
const RESOURCES := [
	["industry", "icons/meter/industry.png", "production", "TOPBAR_INDUSTRY"],
	["research", "icons/meter/research.png", "research", "TOPBAR_RESEARCH"],
	["influence", "icons/meter/influence.png", "government", "TOPBAR_INFLUENCE"],
	["pp_stockpile", "icons/meter/stockpile.png", "production", "TOPBAR_STOCKPILE"],
	["population", "icons/meter/pop.png", "objects", "TOPBAR_POPULATION"],
	["ships", "icons/fleet/big-head-warship.png", "objects", "TOPBAR_SHIPS"],
	["detection", "icons/meter/detection.png", "", "TOPBAR_DETECTION"],
]
## The phase in which the server waits for players' orders.
const WAITING_PHASE := "TURN_PROGRESS_PHASE_WAITING"
## Unspent PP or RP above this counts as wasted.
const WASTE_EPSILON := 0.05

var follow_game := true

var _swatch: ColorRect
var _empire: Label
var _turn: Label
var _end_turn: Button
var _screen_buttons := {}
var _resource_chips := {}
var _waiting := false
var _turn_number := 0
var _phase := ""
var _phase_text := ""


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "TopBarPanel"
	_build()


func _ready() -> void:
	if not follow_game or not is_instance_valid(GlobalFreeOrionNode):
		return
	GlobalFreeOrionNode.start_game.connect(_on_start_game)
	GlobalFreeOrionNode.turn_update.connect(_on_turn_update)
	GlobalFreeOrionNode.turn_progress.connect(set_phase)
	_refresh_from_game()


## Show \a empire_name / \a color at \a turn; \a waiting disables End Turn.
func set_state(empire_name: String, color: Color, turn: int, waiting: bool) -> void:
	_empire.text = empire_name
	_swatch.color = color
	_swatch.visible = not empire_name.is_empty()
	_turn_number = turn
	if not waiting:
		_phase = ""
		_phase_text = ""
	_waiting = waiting
	_update_turn_controls()


## While waiting for the turn: the server's processing phase (a
## TURN_PROGRESS_* key and its text). The turn can be revised only while the
## server still waits for players.
func set_phase(phase: String, text: String) -> void:
	if not _waiting:
		return
	_phase = phase
	_phase_text = text
	_update_turn_controls()


## True while an ended turn can still be taken back.
func can_revise() -> bool:
	return _waiting and (_phase.is_empty() or _phase == WAITING_PHASE)


func _update_turn_controls() -> void:
	var turn_text := (
		tr("MAP_BTN_TURN_UPDATE").replace("%1%", str(_turn_number)) if _turn_number >= 1 else ""
	)
	if _waiting and not _phase_text.is_empty():
		turn_text += "  ·  " + _phase_text
	_turn.text = turn_text
	if _waiting:
		_end_turn.text = (
			tr("MAP_BTN_TURN_UNREADY").replace("%1%", str(_turn_number))
			if can_revise()
			else tr("TOPBAR_WAITING")
		)
		_end_turn.tooltip_text = tr("TOPBAR_REVISE_TIP") if can_revise() else ""
		_end_turn.disabled = not can_revise()
		_end_turn.theme_type_variation = "GhostButton"
	else:
		_end_turn.text = tr("TOPBAR_END_TURN")
		_end_turn.tooltip_text = tr("MAP_BTN_TURN_TOOLTIP_DESC_SP")
		_end_turn.disabled = _turn_number < 1
		_end_turn.theme_type_variation = "PrimaryButton"


## Show the empire's resources (FOUniverse.get_empire_resources()).
func set_resources(data: Dictionary) -> void:
	for entry in RESOURCES:
		var chip: Button = _resource_chips[entry[0]]
		chip.visible = data.has(entry[0])
		if chip.visible:
			_fill_chip(chip, entry, data)


## Re-read the resources, e.g. after the queues changed.
func refresh_resources() -> void:
	if follow_game and is_instance_valid(GlobalFreeOrionNode):
		set_resources(FOUniverse.get_empire_resources())


func _fill_chip(chip: Button, entry: Array, data: Dictionary) -> void:
	var key: String = entry[0]
	var value: float = data.get(key, 0.0)
	var text := "%.1f" % value
	var tooltip := tr(entry[3])
	var color := Color()
	match key:
		"industry", "research":
			var spent: float = data.get(key + "_spent", 0.0)
			tooltip = tooltip.replace("%1%", "%.1f" % value).replace("%2%", "%.1f" % spent)
			if value - spent > WASTE_EPSILON:
				color = FOUi.tokens.warning
				tooltip += "\n" + tr("TOPBAR_WASTED").replace("%1%", "%.1f" % (value - spent))
		"influence":
			var change: float = data.get("influence_change", 0.0)
			text = "%.1f (%+.1f)" % [value, change]
			tooltip = tooltip.replace("%1%", "%.1f" % value).replace("%2%", "%+.1f" % change)
			if change < 0.0:
				color = FOUi.tokens.negative
		"ships":
			text = str(int(value))
		"detection":
			text = "%.0f" % value
	chip.text = text
	chip.tooltip_text = tooltip
	if color == Color():
		chip.remove_theme_color_override("font_color")
	else:
		chip.add_theme_color_override("font_color", color)


## Mark \a screen_name ("" for the map) as shown, without emitting signals.
func set_active_screen(screen_name: String) -> void:
	for key in _screen_buttons:
		_screen_buttons[key].set_pressed_no_signal(key == screen_name)


## Show \a count new items on \a screen_name's button (0 clears it).
func set_badge(screen_name: String, count: int) -> void:
	var button: Button = _screen_buttons.get(screen_name)
	if button == null:
		return
	var label: String = button.get_meta("label")
	button.text = "%s (%d)" % [label, count] if count > 0 else label
	if count > 0:
		button.add_theme_color_override("font_color", FOUi.tokens.accent)
	else:
		button.remove_theme_color_override("font_color")


func _on_screen_toggled(pressed: bool, screen_name: String) -> void:
	screen_requested.emit(screen_name if pressed else "")


func is_waiting() -> bool:
	return _waiting


func _build() -> void:
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	add_child(rows)
	var row := HBoxContainer.new()
	rows.add_child(row)
	var resources := HBoxContainer.new()
	resources.add_theme_constant_override("separation", FOUi.tokens.space_1)
	rows.add_child(resources)
	for entry in RESOURCES:
		var chip := Button.new()
		chip.theme_type_variation = "GhostButton"
		chip.icon = FOArt.icon(entry[1])
		chip.expand_icon = false
		chip.add_theme_constant_override("icon_max_width", FOUi.tokens.icon_small)
		chip.add_theme_font_size_override("font_size", FOUi.tokens.font_size_small)
		chip.focus_mode = Control.FOCUS_NONE if entry[2].is_empty() else Control.FOCUS_ALL
		if not entry[2].is_empty():
			chip.pressed.connect(screen_requested.emit.bind(entry[2]))
		resources.add_child(chip)
		_resource_chips[entry[0]] = chip
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(FOUi.tokens.space_3, FOUi.tokens.space_3)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_swatch)
	_empire = Label.new()
	_empire.theme_type_variation = "TitleLabel"
	row.add_child(_empire)
	var nav_gap := Control.new()
	nav_gap.custom_minimum_size.x = FOUi.tokens.space_6
	row.add_child(nav_gap)
	for screen in SCREENS:
		var button := Button.new()
		button.text = tr(screen[1])
		button.set_meta("label", button.text)
		button.toggle_mode = true
		button.theme_type_variation = "GhostButton"
		button.tooltip_text = "%s (%s)" % [tr(screen[1]), OS.get_keycode_string(screen[2])]
		var key := InputEventKey.new()
		key.keycode = screen[2]
		button.shortcut = Shortcut.new()
		button.shortcut.events = [key]
		button.toggled.connect(_on_screen_toggled.bind(screen[0]))
		row.add_child(button)
		_screen_buttons[screen[0]] = button
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_turn = Label.new()
	_turn.theme_type_variation = "SecondaryLabel"
	row.add_child(_turn)
	_end_turn = Button.new()
	_end_turn.theme_type_variation = "PrimaryButton"
	_end_turn.tooltip_text = tr("MAP_BTN_TURN_TOOLTIP_DESC_SP")
	var shortcut_key := InputEventKey.new()
	shortcut_key.keycode = END_TURN_KEY
	shortcut_key.ctrl_pressed = true
	_end_turn.shortcut = Shortcut.new()
	_end_turn.shortcut.events = [shortcut_key]
	_end_turn.set_meta("sound", "turn")
	_end_turn.pressed.connect(_on_end_turn_pressed)
	row.add_child(_end_turn)
	var menu := Button.new()
	menu.text = tr("GAME_MENU_WINDOW_TITLE")
	menu.theme_type_variation = "GhostButton"
	menu.tooltip_text = tr("TOPBAR_MENU")
	menu.pressed.connect(menu_requested.emit)
	row.add_child(menu)
	set_state("", Color.WHITE, 0, false)


func _on_end_turn_pressed() -> void:
	if _waiting:
		# Take the turn back to change orders.
		if not can_revise():
			return
		_waiting = false
		_refresh_from_game()
		if follow_game and is_instance_valid(GlobalFreeOrionNode):
			GlobalFreeOrionNode.revise_turn()
		return
	_waiting = true
	_refresh_from_game()
	if follow_game and is_instance_valid(GlobalFreeOrionNode):
		GlobalFreeOrionNode.start_turn()


func _on_start_game(_is_new_game: bool) -> void:
	_waiting = false
	_refresh_from_game()


func _on_turn_update() -> void:
	_waiting = false
	_refresh_from_game()


func _refresh_from_game() -> void:
	if not follow_game or not is_instance_valid(GlobalFreeOrionNode):
		set_state(_empire.text, _swatch.color, _turn_number, _waiting)
		return
	var empire_id: int = FOUniverse.get_empire_id()
	set_resources(FOUniverse.get_empire_resources())
	set_state(
		FOUniverse.get_empire_name(empire_id),
		FOUniverse.get_empire_color(empire_id),
		GlobalFreeOrionNode.get_current_turn(),
		_waiting
	)
