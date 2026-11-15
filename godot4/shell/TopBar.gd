class_name TopBar
extends PanelContainer
## In-game top bar: empire (colour + name), turn number and End Turn.
## Follows the running game unless follow_game is false; set_state() then
## drives it directly (tests, previews).

## Emitted when the Production toggle changes (F2 toggles it too).
signal production_toggled(shown: bool)

## Ctrl+Enter ends the turn, as a keyboard path to the primary action.
const END_TURN_KEY := KEY_ENTER
const PRODUCTION_KEY := KEY_F2

var follow_game := true

var _swatch: ColorRect
var _empire: Label
var _turn: Label
var _end_turn: Button
var _production: Button
var _waiting := false


func _init() -> void:
	theme_type_variation = "TopBarPanel"
	_build()


func _ready() -> void:
	if not follow_game or not is_instance_valid(GlobalFreeOrionNode):
		return
	GlobalFreeOrionNode.start_game.connect(_on_start_game)
	GlobalFreeOrionNode.turn_update.connect(_on_turn_update)
	_refresh_from_game()


## Show \a empire_name / \a color at \a turn; \a waiting disables End Turn.
func set_state(empire_name: String, color: Color, turn: int, waiting: bool) -> void:
	_empire.text = empire_name
	_swatch.color = color
	_swatch.visible = not empire_name.is_empty()
	_turn.text = tr("MAP_BTN_TURN_UPDATE").replace("%1%", str(turn)) if turn >= 1 else ""
	_waiting = waiting
	_end_turn.disabled = waiting or turn < 1
	_end_turn.text = tr("TOPBAR_WAITING") if waiting else tr("TOPBAR_END_TURN")


## Reflect the production screen state without emitting production_toggled.
func set_production_shown(shown: bool) -> void:
	_production.set_pressed_no_signal(shown)


func is_waiting() -> bool:
	return _waiting


func _build() -> void:
	var row := HBoxContainer.new()
	add_child(row)
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
	_production = Button.new()
	_production.text = tr("MAP_BTN_PRODUCTION")
	_production.toggle_mode = true
	_production.theme_type_variation = "GhostButton"
	_production.tooltip_text = "%s (F2)" % tr("MAP_BTN_PRODUCTION")
	var production_key := InputEventKey.new()
	production_key.keycode = PRODUCTION_KEY
	_production.shortcut = Shortcut.new()
	_production.shortcut.events = [production_key]
	_production.toggled.connect(production_toggled.emit)
	row.add_child(_production)
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
	_end_turn.pressed.connect(_on_end_turn_pressed)
	row.add_child(_end_turn)
	set_state("", Color.WHITE, 0, false)


func _on_end_turn_pressed() -> void:
	if _waiting:
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
		set_state(_empire.text, _swatch.color, 0, _waiting)
		return
	var empire_id: int = FOUniverse.get_empire_id()
	set_state(
		FOUniverse.get_empire_name(empire_id),
		FOUniverse.get_empire_color(empire_id),
		GlobalFreeOrionNode.get_current_turn(),
		_waiting
	)
