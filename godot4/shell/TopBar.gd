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
## The messages button was pressed (opens the chat window).
signal messages_requested
## Industry goes unspent in system \a system_id: show it (the industry
## chip, while PP are wasted).
signal wasted_pp_requested(system_id: int)
## Drop this turn's orders (End turn's menu).
signal revert_requested
## End turn was pressed but TurnReadiness found \a issues; end_turn() ends it
## anyway.
signal readiness_issues(issues: Array)

## Screen buttons: name, label key. Each has the FOHotkeys shortcut
## "screen_" + name (F2, F3, ... by default); End turn has "end_turn".
## Save and Options are in the in-game menu.
const SCREENS := [
	["production", "MAP_BTN_PRODUCTION"],
	["research", "MAP_BTN_RESEARCH"],
	["government", "GOVERNMENT_TAB"],
	["design", "DESIGNER_TAB"],
	["objects", "MAP_BTN_OBJECTS"],
	["combat", "COMBAT_TAB"],
	["empires", "EMPIRES_TAB"],
	["pedia", "MAP_BTN_PEDIA"],
]
## The game's button art for the screens, shown instead of their names when
## the names don't fit (narrow windows, long translations).
const SCREEN_ICONS := {
	"production": "icons/buttons/production.png",
	"research": "icons/buttons/research.png",
	"government": "icons/buttons/government.png",
	"design": "icons/buttons/design.png",
	"objects": "icons/buttons/objects.png",
	"combat": "icons/combat.png",
	"empires": "icons/buttons/empires.png",
	"pedia": "icons/buttons/pedia.png",
}

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
## End each turn as soon as it starts (GG's automatic turn advance).
var auto_end_turn := false
## "player", or (multiplayer, no empire) "observer" or "moderator".
var role := "player"
## Orders given this turn, for End turn's menu.
var order_count_provider: Callable = func() -> int: return FOOrders.get_order_count()
## Returns TurnReadiness.check()'s warnings; the game's by default.
var readiness_provider: Callable = _game_readiness

var _swatch: ColorRect
var _flag: TextureRect
var _empire: Label
var _turn: Label
var _end_turn: Button
var _end_turn_width := 0.0
## Screens shown by their icons (their names don't fit).
var _compact := false
var _nav_row: HBoxContainer
var _screen_buttons := {}
var _resource_chips := {}
var _waiting := false
var _turn_number := 0
var _phase := ""
var _phase_text := ""
var _messages: Button
var _auto_turn: Button
## Readiness issue keys ended anyway (TurnReadiness.unacknowledged()), and
## the issues last shown.
var _acknowledged := {}
var _shown_issues: Array = []
var _turn_menu: PopupMenu
## Last resources shown (set_resources()).
var _resources := {}
## When the server ends the turn regardless (multiplayer), in msec ticks; 0 for none.
var _turn_deadline := 0
var _timeout_timer: Timer


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "TopBarPanel"
	_build()


func _ready() -> void:
	get_viewport().size_changed.connect(fit_screen_buttons, CONNECT_DEFERRED)
	fit_screen_buttons.call_deferred()
	FOHotkeys.changed.connect(_update_shortcut_tips)
	_update_shortcut_tips()
	if not follow_game or not is_instance_valid(GlobalFreeOrionNode):
		return
	GlobalFreeOrionNode.start_game.connect(_on_start_game)
	GlobalFreeOrionNode.turn_update.connect(_on_turn_update)
	GlobalFreeOrionNode.turn_progress.connect(set_phase)
	GlobalFreeOrionNode.turn_timeout.connect(set_turn_timeout)
	_on_turn_update()


## Show \a empire_name / \a color at \a turn; \a waiting disables End Turn.
func set_state(empire_name: String, color: Color, turn: int, waiting: bool) -> void:
	_empire.text = empire_name if role == "player" else tr(role.to_upper())
	_empire.tooltip_text = _empire.text
	# As wide as the name, up to a limit past which it gives way.
	var font := _empire.get_theme_font("font")
	var full := (
		font.get_string_size(_empire.text, 0, -1, _empire.get_theme_font_size("font_size")).x
	)
	_empire.custom_minimum_size.x = minf(ceilf(full), FOUi.tokens.space_8 * 6)
	_swatch.color = color
	var shown := not empire_name.is_empty() and role == "player"
	# The empire's flag; the plain colour square where there is no flag art.
	_flag.texture = EmpireArt.flag(empire_name, color, FOUi.tokens.icon) if shown else null
	_flag.visible = _flag.texture != null
	_swatch.visible = shown and not _flag.visible
	_turn_number = turn
	if not waiting:
		_phase = ""
		_phase_text = ""
	_waiting = waiting
	_update_turn_controls()


## Play as \a new_role ("player", "observer", "moderator"), as the GG map
## window: without an empire the empire's screens and auto end turn go, the
## name shows the role, and an observer can't end turns.
func set_role(new_role: String) -> void:
	role = new_role
	var spectating := role != "player"
	for key in ["production", "research", "government", "design"]:
		_screen_buttons[key].visible = not spectating
	_auto_turn.visible = role != "observer"
	# No empire: no resources to show (the row keeps the messages button).
	for chip: Control in _resource_chips.values():
		chip.visible = not spectating
	if spectating:
		_empire.text = tr(role.to_upper())
		_swatch.visible = false
		_flag.visible = false
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
	var left := turn_seconds_left()
	if left >= 0:
		turn_text += "  ·  " + tr("TOPBAR_TURN_TIMEOUT").replace("%1%", timeout_text(left))
	_turn.text = turn_text
	_turn.tooltip_text = turn_text
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
		_end_turn.tooltip_text = with_key(tr("MAP_BTN_TURN_TOOLTIP_DESC_SP"), "end_turn")
		_end_turn.disabled = _turn_number < 1
		_end_turn.theme_type_variation = "PrimaryButton"
	# As wide as the widest label it has had, so Menu beside it stays put.
	_end_turn.custom_minimum_size.x = 0.0
	_end_turn.custom_minimum_size.x = maxf(_end_turn_width, _end_turn.get_combined_minimum_size().x)
	_end_turn_width = _end_turn.custom_minimum_size.x
	match role:
		"observer":
			_end_turn.disabled = true
			_end_turn.tooltip_text = tr("MAP_BTN_TURN_TOOLTIP_DESC_OBS")
		"moderator":
			_end_turn.tooltip_text = tr("MAP_BTN_TURN_TOOLTIP_DESC_MOD")


## Messages that came in while the chat was closed, as a count on its button.
func set_unread_messages(count: int) -> void:
	_messages.text = str(count) if count > 0 else ""
	if count > 0:
		_messages.add_theme_color_override("font_color", FOUi.tokens.accent)
	else:
		_messages.remove_theme_color_override("font_color")


## The server ends the turn in \a seconds whether everyone is ready or not
## (multiplayer turn timeout); 0 or less for no limit.
func set_turn_timeout(seconds: int) -> void:
	_turn_deadline = Time.get_ticks_msec() + seconds * 1000 if seconds > 0 else 0
	if seconds > 0:
		_timeout_timer.start()
	else:
		_timeout_timer.stop()
	_update_turn_controls()


## Seconds until the turn times out, or -1 without a limit.
func turn_seconds_left() -> int:
	if _turn_deadline == 0:
		return -1
	var left := ceili((_turn_deadline - Time.get_ticks_msec()) / 1000.0)
	if left <= 0:
		_turn_deadline = 0
		_timeout_timer.stop()
		return -1
	return left


## "1:05" for 65 seconds; hours as "1:01:05".
static func timeout_text(seconds: int) -> String:
	if seconds >= 3600:
		return "%d:%02d:%02d" % [seconds / 3600, (seconds / 60) % 60, seconds % 60]
	return "%d:%02d" % [seconds / 60, seconds % 60]


## \a text with hotkey \a hotkey's key after it: "Production (F2)".
static func with_key(text: String, hotkey: String) -> String:
	var key: String = FOHotkeys.binding(hotkey)
	return text if key.is_empty() else "%s (%s)" % [text, key]


func _update_shortcut_tips() -> void:
	for screen in SCREENS:
		_screen_buttons[screen[0]].tooltip_text = with_key(tr(screen[1]), "screen_" + screen[0])
	_messages.tooltip_text = with_key(tr("MESSAGES_PANEL_TITLE"), "messages")
	_update_turn_controls()


## Show the empire's resources (FOUniverse.get_empire_resources()).
func set_resources(data: Dictionary) -> void:
	_resources = data
	for entry in RESOURCES:
		var chip: Button = _resource_chips[entry[0]]
		chip.visible = data.has(entry[0]) and role == "player"
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
				if key == "industry" and data.get("wasted_pp_system", -1) >= 0:
					tooltip += "\n" + tr("TOPBAR_WASTED_SHOW")
			if key == "industry" and data.has("stockpile_capacity"):
				tooltip += (
					"\n"
					+ (
						tr("TOPBAR_STOCKPILE_DETAIL")
						. replace("%1%", "%.1f" % data.get("pp_stockpile", 0.0))
						. replace("%2%", "%.1f" % data["stockpile_capacity"])
						. replace("%3%", "%.1f" % data.get("stockpile_expected", 0.0))
					)
				)
		"influence":
			var change: float = data.get("influence_change", 0.0)
			text = "%.1f (%+.1f)" % [value, change]
			tooltip = tooltip.replace("%1%", "%.1f" % value).replace("%2%", "%+.1f" % change)
			if change < 0.0:
				color = FOUi.tokens.negative
		"population":
			tooltip += census_text(data)
		"ships":
			text = str(int(value))
			for line in [
				["ships_armed", "MAP_FLEET_ARMED_COUNT"],
				["ships_unarmed", "MAP_FLEET_UNARMED_COUNT"],
				["ships_troops", "MAP_FLEET_TROOP_COUNT"],
				["ships_colony", "MAP_FLEET_COLONY_COUNT"],
				["ships_carriers", "MAP_FLEET_CARRIER_COUNT"],
			]:
				if data.has(line[0]):
					tooltip += "\n%s: %d" % [tr(line[1]), data[line[0]]]
		"detection":
			text = "%.0f" % value
	chip.text = text
	chip.tooltip_text = tooltip
	if color == Color():
		chip.remove_theme_color_override("font_color")
	else:
		chip.add_theme_color_override("font_color", color)


## The population tooltip's census: each species' population, then each
## species tag's, largest first (as GG's census).
static func census_text(data: Dictionary) -> String:
	var text := ""
	for group in [
		["population_by_species", "TOPBAR_CENSUS_SPECIES"],
		["population_by_tag", "TOPBAR_CENSUS_TAGS"]
	]:
		var counts: Dictionary = data.get(group[0], {})
		if counts.is_empty():
			continue
		var keys := counts.keys()
		keys.sort_custom(func(a, b): return counts[a] > counts[b])
		text += "\n\n" + TranslationServer.translate(group[1])
		for key in keys.slice(0, 12):
			text += "\n%s: %.1f" % [ScreenKit.tr_or_name(key), counts[key]]
	return text


## Mark \a screen_name ("" for the map) as shown, without emitting signals.
func set_active_screen(screen_name: String) -> void:
	for key in _screen_buttons:
		_screen_buttons[key].set_pressed_no_signal(key == screen_name)


## Show \a count new items on \a screen_name's button (0 clears it).
func set_badge(screen_name: String, count: int) -> void:
	var button: Button = _screen_buttons.get(screen_name)
	if button == null:
		return
	button.set_meta("badge", count)
	_apply_screen_text(button)
	if count > 0:
		button.add_theme_color_override("font_color", FOUi.tokens.accent)
	else:
		button.remove_theme_color_override("font_color")


# A screen button's text: its name and badge count, or only the count when
# shown by its icon.
func _apply_screen_text(button: Button) -> void:
	var label: String = button.get_meta("label")
	var count: int = button.get_meta("badge", 0)
	if _compact:
		button.text = str(count) if count > 0 else ""
		button.icon = button.get_meta("icon_texture")
	else:
		button.text = "%s (%d)" % [label, count] if count > 0 else label
		button.icon = null


## Show the screens by name when everything fits on the top row, else by
## their icons (so End turn and Menu never go past the right edge).
func fit_screen_buttons() -> void:
	# The room the bar is given (its own size grows to what it holds).
	var room := get_parent_area_size().x
	if _nav_row == null or room <= 0.0:
		return
	_compact = false
	for button: Button in _screen_buttons.values():
		_apply_screen_text(button)
	var padding := get_combined_minimum_size().x - _nav_row.get_combined_minimum_size().x
	var compact := _nav_row.get_combined_minimum_size().x + maxf(padding, 0.0) > room
	if compact != _compact:
		_compact = compact
		for button: Button in _screen_buttons.values():
			_apply_screen_text(button)


func is_compact() -> bool:
	return _compact


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		fit_screen_buttons.call_deferred()


func _on_screen_toggled(pressed: bool, screen_name: String) -> void:
	screen_requested.emit(screen_name if pressed else "")


## The End turn button (for hints pointing at it).
func get_end_turn_button() -> Button:
	return _end_turn


func is_waiting() -> bool:
	return _waiting


func _build() -> void:
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	add_child(rows)
	var row := HBoxContainer.new()
	_nav_row = row
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
			chip.pressed.connect(_on_chip_pressed.bind(entry[0], entry[2]))
		resources.add_child(chip)
		_resource_chips[entry[0]] = chip
	# Messages and automatic turns at the right end of the resources row:
	# the top row is full.
	var resource_gap := Control.new()
	resource_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resources.add_child(resource_gap)
	# The turn and, while it is processed, its phase, on the second row where
	# there is room: the first row keeps the screens, End turn and Menu. Long
	# phase texts are shortened (the whole text is the tooltip).
	_turn = Label.new()
	_turn.theme_type_variation = "SecondaryLabel"
	_turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_turn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_turn.clip_text = true
	_turn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_turn.size_flags_stretch_ratio = 3.0
	_turn.mouse_filter = Control.MOUSE_FILTER_PASS
	resources.add_child(_turn)
	_auto_turn = Button.new()
	_auto_turn.toggle_mode = true
	_auto_turn.icon = FOArt.icon("icons/buttons/manual_turn.png")
	_auto_turn.expand_icon = false
	# The game's button art has a margin: at the small icon size it can't be
	# made out.
	_auto_turn.add_theme_constant_override("icon_max_width", FOUi.tokens.icon)
	_auto_turn.theme_type_variation = "GhostButton"
	_auto_turn.tooltip_text = tr("MAP_BTN_MANUAL_TURN_ADVANCE")
	_auto_turn.toggled.connect(set_auto_end_turn)
	resources.add_child(_auto_turn)
	_messages = Button.new()
	_messages.icon = FOArt.icon("icons/buttons/messages.png")
	_messages.expand_icon = false
	_messages.add_theme_constant_override("icon_max_width", FOUi.tokens.icon)
	_messages.add_theme_font_size_override("font_size", FOUi.tokens.font_size_small)
	_messages.theme_type_variation = "GhostButton"
	_messages.tooltip_text = with_key(tr("MESSAGES_PANEL_TITLE"), "messages")
	_messages.shortcut = FOHotkeys.shortcut("messages")
	_messages.shortcut_in_tooltip = false
	_messages.pressed.connect(messages_requested.emit)
	resources.add_child(_messages)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(FOUi.tokens.space_3, FOUi.tokens.space_3)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_swatch)
	_flag = TextureRect.new()
	_flag.custom_minimum_size = Vector2.ONE * FOUi.tokens.icon
	_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_flag.visible = false
	row.add_child(_flag)
	_empire = Label.new()
	_empire.theme_type_variation = "TitleLabel"
	# A long name gives way (ellipsis, full name in the tooltip) before the
	# screen buttons have to lose their words.
	_empire.clip_text = true
	_empire.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_empire.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_empire)
	var nav_gap := Control.new()
	nav_gap.custom_minimum_size.x = FOUi.tokens.space_6
	row.add_child(nav_gap)
	for screen in SCREENS:
		var button := Button.new()
		button.text = tr(screen[1])
		button.set_meta("label", button.text)
		button.set_meta("icon_texture", FOArt.icon(SCREEN_ICONS.get(screen[0], "")))
		button.add_theme_constant_override("icon_max_width", FOUi.tokens.icon)
		button.toggle_mode = true
		button.theme_type_variation = "NavButton"
		button.shortcut = FOHotkeys.shortcut("screen_" + screen[0])
		button.shortcut_in_tooltip = false
		button.toggled.connect(_on_screen_toggled.bind(screen[0]))
		row.add_child(button)
		_screen_buttons[screen[0]] = button
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_end_turn = Button.new()
	_end_turn.theme_type_variation = "PrimaryButton"
	_end_turn.tooltip_text = tr("MAP_BTN_TURN_TOOLTIP_DESC_SP")
	_end_turn.shortcut = FOHotkeys.shortcut("end_turn")
	_end_turn.shortcut_in_tooltip = false
	_end_turn.set_meta("sound", "turn")
	_end_turn.pressed.connect(_on_end_turn_pressed)
	# Right-click: send the orders and start, or revoke them all.
	_end_turn.gui_input.connect(
		func(event: InputEvent):
			if (
				event is InputEventMouseButton
				and event.pressed
				and event.button_index == MOUSE_BUTTON_RIGHT
			):
				open_turn_menu()
	)
	_turn_menu = PopupMenu.new()
	_turn_menu.id_pressed.connect(_on_turn_menu)
	add_child(_turn_menu)
	row.add_child(_end_turn)
	_timeout_timer = Timer.new()
	_timeout_timer.wait_time = 1.0
	_timeout_timer.timeout.connect(_update_turn_controls)
	add_child(_timeout_timer)
	var menu := Button.new()
	menu.text = tr("GAME_MENU_WINDOW_TITLE")
	menu.theme_type_variation = "GhostButton"
	menu.tooltip_text = tr("TOPBAR_MENU")
	menu.pressed.connect(menu_requested.emit)
	row.add_child(menu)
	set_state("", Color.WHITE, 0, false)


## End turn's menu, as GG's: send the orders and start the turn, or revoke
## all of this turn's orders.
func open_turn_menu() -> void:
	var count: int = order_count_provider.call() if follow_game else 0
	_turn_menu.clear()
	_turn_menu.add_item(
		tr("MAP_BTN_TURN_SEND_AND_START").replace("%1%", str(_turn_number)).replace(
			"%2%", str(count)
		),
		0
	)
	_turn_menu.set_item_disabled(0, _waiting or _turn_number < 1)
	_turn_menu.add_item(
		tr("MAP_BTN_TURN_REVOKE").replace("%1%", str(_turn_number)).replace("%2%", str(count)), 1
	)
	_turn_menu.set_item_disabled(1, _waiting or count < 1)
	var at := _end_turn.get_screen_position() + Vector2(0, _end_turn.size.y)
	_turn_menu.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


func _on_turn_menu(id: int) -> void:
	if id == 0:
		end_turn()
	else:
		revert_requested.emit()


## Turn automatic turn advance on or off: each new turn then ends at once.
func set_auto_end_turn(on: bool) -> void:
	auto_end_turn = on
	_auto_turn.set_pressed_no_signal(on)
	_auto_turn.icon = FOArt.icon("icons/buttons/%s_turn.png" % ("auto" if on else "manual"))
	_auto_turn.tooltip_text = tr(
		"MAP_BTN_AUTO_ADVANCE_ENABLED" if on else "MAP_BTN_MANUAL_TURN_ADVANCE"
	)


func _on_chip_pressed(key: String, screen_name: String) -> void:
	var wasted_system: int = _resources.get("wasted_pp_system", -1)
	var unspent: float = _resources.get("industry", 0.0) - _resources.get("industry_spent", 0.0)
	if key == "industry" and wasted_system >= 0 and unspent > WASTE_EPSILON:
		wasted_pp_requested.emit(wasted_system)
		return
	screen_requested.emit(screen_name)


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
	var issues := TurnReadiness.unacknowledged(readiness_provider.call(), _acknowledged)
	_shown_issues = issues
	if not issues.is_empty():
		readiness_issues.emit(issues)
		return
	end_turn()


func _game_readiness() -> Array:
	if not follow_game or not is_instance_valid(GlobalFreeOrionNode) or not TurnReadiness.enabled():
		return []
	return TurnReadiness.check(TurnReadiness.gather())


## End the turn without checking first.
func end_turn() -> void:
	if _waiting:
		return
	# Ended anyway: the issues just shown are not raised again until resolved.
	for issue: Dictionary in _shown_issues:
		_acknowledged[issue.get("key", "")] = true
	_shown_issues = []
	_waiting = true
	_refresh_from_game()
	if follow_game and is_instance_valid(GlobalFreeOrionNode):
		GlobalFreeOrionNode.start_turn()


func _on_start_game(_is_new_game: bool) -> void:
	_on_turn_update()


func _on_turn_update() -> void:
	# Turns ended by themselves (auto-advance from the command line) wait.
	_waiting = GlobalFreeOrionNode.is_turn_auto_ended()
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
	var game_role := FOModerator.get_role()
	if not game_role.is_empty() and game_role != role:
		set_role(game_role)
