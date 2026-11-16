class_name CombatScreen
extends PanelContainer
## Combat reports: the player's combats on the left, newest first, with
## losses at a glance; the chosen one on the right: each side's strength,
## losses and damage dealt, its ships and planets, and the log by round.
## Attacks expand into the individual shots. Links (ships, planets, parts)
## emit link_activated, as in the turn events.

signal close_requested
signal link_activated(kind: String, arg: String)

const SIDE_MIN_WIDTH := 300
## Markers before log lines, by event kind.
const KIND_MARKERS := {"attack": "›", "destroyed": "✕", "fighters": "»"}
## Ships whose design has no icon (monsters).
const FALLBACK_SHIP_ICON := "icons/ship_hulls/generic-medium-hull_small.png"

var source: Variant = CombatSource.new()
## Replay: the bout shown (0 before the combat, the last after it). The
## replay moves health bars ([ProgressBar, health_by_bout]), unit rows'
## "destroyed" labels and log rows (by bout).
var bout := 0

var _info: Label
var _columns: Control
var _empty: VBoxContainer
var _list: VBoxContainer
var _detail: VBoxContainer
var _detail_scroll: ScrollContainer
var _combats: Array = []
var _selected_id := -1
var _bouts := 0
var _replay_bars: Array = []
var _replay_losses: Array = []
var _log_rows: Array = []
var _bout_label: Label
var _whole_log: Button


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "BackgroundPanel"
	_build()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


## Reload the combats; keeps the shown one, or shows the newest.
func refresh() -> void:
	_combats = source.list_combats()
	var pending: int = source.get_pending_count()
	_info.text = tr("COMBAT_REPORTS_FETCHING") if pending > 0 else ""
	ScreenKit.clear(_list)
	for combat: Dictionary in _combats:
		_list.add_child(_combat_card(combat))
	# No combats: the columns give way to a picture and a line saying so.
	ScreenKit.clear(_empty)
	_columns.visible = not _combats.is_empty()
	_empty.visible = _combats.is_empty()
	if _combats.is_empty():
		_empty.add_child(
			ScreenKit.empty_state(
				ScreenKit.HEADER_ICONS["COMBAT_REPORT_TITLE"],
				tr("COMBAT_REPORTS_FETCHING" if pending > 0 else "COMBAT_REPORTS_EMPTY")
			)
		)
	var ids: Array = _combats.map(func(c): return c["id"])
	open(_selected_id if ids.has(_selected_id) else (ids[0] if not ids.is_empty() else -1))


## Show combat \a log_id (-1: none).
func open(log_id: int) -> void:
	_selected_id = log_id
	for card in _list.get_children():
		if card is Button:
			card.set_pressed_no_signal(card.get_meta("id") == log_id)
	ScreenKit.clear(_detail)
	_replay_bars.clear()
	_replay_losses.clear()
	_log_rows.clear()
	_bouts = 0
	var combat: Dictionary = source.get_combat(log_id) if log_id >= 0 else {}
	if combat.is_empty():
		return
	_build_detail(combat)
	_detail_scroll.scroll_vertical = 0


## The combats from the last refresh(), as list_combats() returns them.
func combats() -> Array:
	return _combats


## Newest combat id in \a combats (from list_combats()), or -1.
static func newest_id(combats: Array) -> int:
	var newest := -1
	for combat: Dictionary in combats:
		newest = maxi(newest, combat["id"])
	return newest


## Units lost by the player's side and by everyone else.
static func losses(combat: Dictionary) -> Vector2i:
	var result := Vector2i.ZERO
	for side: Dictionary in combat.get("sides", []):
		if side.get("own", false):
			result.x += side.get("destroyed", 0)
		else:
			result.y += side.get("destroyed", 0)
	return result


func _build() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	_info = ScreenKit.header(box, "COMBAT_REPORT_TITLE", close_requested.emit)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", FOUi.tokens.space_6)
	box.add_child(columns)
	_columns = columns
	_empty = VBoxContainer.new()
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty.visible = false
	box.add_child(_empty)
	_list = ScreenKit.list()
	var list_scroll := ScreenKit.scrolling(_list)
	list_scroll.custom_minimum_size.x = 300
	list_scroll.size_flags_horizontal = Control.SIZE_FILL
	columns.add_child(list_scroll)
	_detail = ScreenKit.list()
	_detail.add_theme_constant_override("separation", FOUi.tokens.space_3)
	_detail_scroll = ScreenKit.scrolling(_detail)
	_detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(_detail_scroll)


func _combat_card(combat: Dictionary) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.set_meta("id", combat["id"])
	card.custom_minimum_size.y = 72
	card.pressed.connect(open.bind(combat["id"]))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = FOUi.tokens.space_3
	box.offset_right = -FOUi.tokens.space_3
	box.offset_top = FOUi.tokens.space_2
	box.offset_bottom = -FOUi.tokens.space_2
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var title := ScreenKit.label(combat.get("system_name", ""))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(title)
	top.add_child(
		ScreenKit.label(
			tr("MAP_BTN_TURN_UPDATE").replace("%1%", str(combat.get("turn", 0))), "SmallLabel"
		)
	)
	var lost := losses(combat)
	var outcome := ScreenKit.label(
		tr("COMBAT_REPORT_LOSSES").replace("%1%", str(lost.x)).replace("%2%", str(lost.y)),
		"SecondaryLabel"
	)
	if lost.x > 0:
		outcome.add_theme_color_override("font_color", FOUi.tokens.negative)
	box.add_child(outcome)
	box.add_child(_side_strip(combat.get("sides", [])))
	return card


# A thin bar split by side, in the sides' colours and sized by unit count.
func _side_strip(sides: Array) -> Control:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", FOUi.tokens.space_1 >> 1)
	strip.custom_minimum_size.y = FOUi.tokens.space_1
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: Dictionary in sides:
		var part := ColorRect.new()
		part.color = side.get("color", Color.GRAY)
		part.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		part.size_flags_stretch_ratio = maxf(1.0, side.get("units", 1))
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
		part.tooltip_text = side.get("name", "")
		strip.add_child(part)
	return strip


func _build_detail(combat: Dictionary) -> void:
	_detail.add_child(_hero(combat))
	var sides := HFlowContainer.new()
	sides.add_theme_constant_override("h_separation", FOUi.tokens.space_3)
	sides.add_theme_constant_override("v_separation", FOUi.tokens.space_3)
	_detail.add_child(sides)
	for side: Dictionary in combat.get("sides", []):
		sides.add_child(_side_card(side))

	# GG's graphical summary: a bar per unit.
	_detail.add_child(ScreenKit.label(tr("COMBAT_SUMMARY"), "TitleLabel"))
	var summary := CombatSummary.new()
	summary.persist = source is CombatSource
	summary.sides = combat.get("sides", [])
	_detail.add_child(summary)

	_bouts = combat.get("bouts", 0)
	if _bouts > 0:
		_detail.add_child(_health_chart(combat.get("sides", [])))
		_detail.add_child(_replay_bar())

	_detail.add_child(ScreenKit.label(tr("COMBAT_LOG"), "TitleLabel"))
	var all_events: Array = combat.get("events", [])
	var events := without_empty_bouts(all_events)
	if events.is_empty():
		_detail.add_child(ScreenKit.label(tr("COMBAT_REPORT_NO_EVENTS"), "SecondaryLabel"))
	var log_box := VBoxContainer.new()
	log_box.add_theme_constant_override("separation", FOUi.tokens.space_1)
	_detail.add_child(log_box)
	# Bouts are counted on the whole log, empty ones included.
	var event_bout := 0
	for event: Dictionary in all_events:
		if event.get("kind", "") == "bout":
			event_bout += 1
		if not events.has(event):
			continue
		var row := _event_row(event)
		_log_rows.push_back([row, event_bout])
		log_box.add_child(row)
	bout = _bouts


## What \a combat came to for the player: [text key, colour token name] —
## a victory, a defeat, losses on both sides, or none.
static func outcome(combat: Dictionary) -> Array:
	var lost := losses(combat)
	if lost.x == 0 and lost.y > 0:
		return ["COMBAT_OUTCOME_VICTORY", "positive"]
	if lost.x > 0 and lost.y == 0:
		return ["COMBAT_OUTCOME_DEFEAT", "negative"]
	if lost.x > 0:
		return ["COMBAT_OUTCOME_BOTH", "warning"]
	return ["COMBAT_OUTCOME_NONE", "text_secondary"]


# The report's header: the sides' flags facing each other, where and when,
# and what it came to, on a band tinted by the outcome.
func _hero(combat: Dictionary) -> Control:
	var tokens: FOTokens = FOUi.tokens
	var result := outcome(combat)
	var tint: Color = tokens.get(result[1])
	var band := PanelContainer.new()
	var style := FOThemeBuilder.cut(
		FOThemeBuilder.box(
			tokens, Color(tint, 0.12), Color(tint, 0.6), tokens.space_4, tokens.space_3
		),
		tokens,
		tokens.chamfer
	)
	band.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", tokens.space_4)
	band.add_child(row)
	var own := []
	var others := []
	for side: Dictionary in combat.get("sides", []):
		(own if side.get("own", false) else others).push_back(side)
	row.add_child(_flags(own))
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 0)
	row.add_child(middle)
	middle.add_child(
		_rich(
			tr("COMBAT_REPORT_AT").replace(
				"%1%", "<system %d>%s</system>" % [combat["system_id"], combat["system_name"]]
			),
			"HeadingLabel"
		)
	)
	middle.add_child(
		ScreenKit.label(
			tr("MAP_BTN_TURN_UPDATE").replace("%1%", str(combat.get("turn", 0))), "SecondaryLabel"
		)
	)
	var verdict := ScreenKit.label(tr(result[0]), "DisplayTitle")
	verdict.uppercase = true
	verdict.add_theme_color_override("font_color", tint)
	middle.add_child(verdict)
	row.add_child(_flags(others))
	return band


# The flags of \a sides, side by side (neutral sides without one).
func _flags(sides: Array) -> Control:
	var box := HBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for side: Dictionary in sides:
		var flag := ScreenKit.icon("", FOUi.tokens.icon_large)
		flag.texture = EmpireArt.flag(
			side.get("name", ""), side.get("color", Color.GRAY), FOUi.tokens.icon_large
		)
		flag.tooltip_text = side.get("name", "")
		flag.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(flag)
	return box


## Show the combat as it stood at \a at_bout (0 before it, 1.. after each
## bout): health bars, units lost by then, and that bout's part of the log.
func show_bout(at_bout: int) -> void:
	bout = clampi(at_bout, 0, _bouts)
	for entry: Array in _replay_bars:
		var health: PackedFloat32Array = entry[1]
		if bout < health.size():
			entry[0].value = health[bout]
	for entry: Array in _replay_losses:
		var health: PackedFloat32Array = entry[1]
		entry[0].visible = bout < health.size() and health[bout] <= 0.0
	for entry: Array in _log_rows:
		entry[0].visible = entry[1] == bout
	_bout_label.text = (
		tr("COMBAT_REPLAY_BEFORE")
		if bout == 0
		else tr("COMBAT_REPLAY_AFTER").replace("%1%", str(bout)).replace("%2%", str(_bouts))
	)
	_whole_log.disabled = false


## Back to the whole report: final health and the full log.
func show_whole_combat() -> void:
	show_bout(_bouts)
	for entry: Array in _log_rows:
		entry[0].visible = true
	_bout_label.text = tr("COMBAT_REPLAY_ALL").replace("%1%", str(_bouts))
	_whole_log.disabled = true


# Each side's health before the combat and after each bout.
func _health_chart(sides: Array) -> Control:
	var chart := LineChart.new()
	chart.custom_minimum_size.y = FOUi.tokens.space_8 * 5
	chart.hover_title = func(at: int) -> String:
		return (
			tr("COMBAT_REPLAY_BEFORE")
			if at == 0
			else tr("COMBAT_CHART_AFTER").replace("%1%", str(at))
		)
	var series := []
	for side: Dictionary in sides:
		var turns := PackedInt32Array()
		var values := PackedFloat64Array()
		var health: PackedFloat32Array = side.get("health_by_bout", PackedFloat32Array())
		for i in health.size():
			turns.push_back(i)
			values.push_back(health[i])
		(
			series
			. push_back(
				{
					"label": side.get("name", ""),
					"color": side.get("color", Color.GRAY),
					"turns": turns,
					"values": values,
				}
			)
		)
	chart.series = series
	return chart


# ◀ bout ▶, and back to the whole combat.
func _replay_bar() -> Control:
	var row := HBoxContainer.new()
	row.add_child(ScreenKit.label(tr("COMBAT_REPLAY"), "TitleLabel"))
	var back := ScreenKit.small_button("◀", "COMBAT_REPLAY_PREVIOUS")
	back.pressed.connect(func(): show_bout(bout - 1))
	row.add_child(back)
	_bout_label = ScreenKit.label(tr("COMBAT_REPLAY_ALL").replace("%1%", str(_bouts)))
	_bout_label.custom_minimum_size.x = SIDE_MIN_WIDTH * 0.6
	_bout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_bout_label)
	var next := ScreenKit.small_button("▶", "COMBAT_REPLAY_NEXT")
	next.pressed.connect(func(): show_bout(bout + 1))
	row.add_child(next)
	_whole_log = Button.new()
	_whole_log.text = tr("COMBAT_REPLAY_WHOLE")
	_whole_log.theme_type_variation = "GhostButton"
	_whole_log.disabled = true
	_whole_log.pressed.connect(show_whole_combat)
	row.add_child(_whole_log)
	return row


func _side_card(side: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size.x = SIDE_MIN_WIDTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FOUi.tokens.space_1)
	card.add_child(box)
	var color: Color = side.get("color", Color.GRAY)
	var top := HBoxContainer.new()
	box.add_child(top)
	var swatch := ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(FOUi.tokens.space_3, FOUi.tokens.space_3)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(swatch)
	var side_name := ScreenKit.label(side.get("name", ""), "TitleLabel")
	side_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(side_name)

	var max_health: float = side.get("max_health", 0.0)
	var side_bar := _health_bar(side.get("health", 0.0), max_health, color, FOUi.tokens.space_2)
	_replay_bars.push_back([side_bar, side.get("health_by_bout", PackedFloat32Array())])
	box.add_child(side_bar)
	var facts: PackedStringArray = [
		tr("COMBAT_REPORT_LOST").replace("%1%", str(side.get("destroyed", 0))).replace(
			"%2%", str(side.get("units", 0))
		),
		tr("COMBAT_REPORT_DAMAGE").replace("%1%", "%.0f" % side.get("damage_dealt", 0.0)),
	]
	box.add_child(ScreenKit.label("  ·  ".join(facts), "SecondaryLabel"))
	# Initial forces and losses, each a section that folds (as GG's report).
	var units: Array = side.get("unit_list", [])
	var losses := units.filter(func(u): return u.get("destroyed", false))
	if not units.is_empty():
		box.add_child(HSeparator.new())
		var forces := _section(
			box, tr("COMBAT_INITIAL_FORCES_COUNT").replace("%1%", str(units.size())), true
		)
		for unit: Dictionary in units:
			forces.add_child(_unit_row(unit, color))
	if not losses.is_empty():
		var lost := _section(box, tr("COMBAT_LOSSES").replace("%1%", str(losses.size())), false)
		for unit: Dictionary in losses:
			lost.add_child(_unit_row(unit, color, false))
	return card


# A foldable section of \a parent titled \a title; returns its content.
func _section(parent: Control, title: String, expanded: bool) -> VBoxContainer:
	var header := Button.new()
	header.theme_type_variation = "GhostButton"
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(header)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", FOUi.tokens.space_1)
	content.visible = expanded
	parent.add_child(content)
	var label := func(): header.text = ("▾ " if content.visible else "▸ ") + title
	label.call()
	header.pressed.connect(
		func():
			content.visible = not content.visible
			label.call()
	)
	return content


func _unit_row(unit: Dictionary, color: Color, replayed := true) -> Control:
	var row := HBoxContainer.new()
	var art: Texture2D = null
	if unit.get("type", "") == "planet":
		art = FOArt.planet_type_icon(unit.get("planet_type", ""))
	var icon := ScreenKit.icon(
		unit.get("icon", ""), FOUi.tokens.icon, art if art else FOArt.icon(FALLBACK_SHIP_ICON)
	)
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var link_kind: String = unit.get("type", "")
	var unit_name := _rich("<%s %d>%s</%s>" % [link_kind, unit["id"], unit["name"], link_kind])
	text.add_child(unit_name)
	var destroyed: bool = unit.get("destroyed", false)
	var health: PackedFloat32Array = unit.get("health_by_bout", PackedFloat32Array())
	if destroyed:
		icon.modulate = Color(1, 1, 1, 0.4)
		var lost := ScreenKit.label(tr("COMBAT_REPORT_DESTROYED"), "SmallLabel")
		lost.add_theme_color_override("font_color", FOUi.tokens.negative)
		text.add_child(lost)
		# In the replay, "destroyed" shows from the bout it happened in.
		if replayed:
			_replay_losses.push_back([lost, health])
	if unit.get("max_health", 0.0) > 0.0 and (not destroyed or not health.is_empty()):
		var bar := _health_bar(
			unit.get("health", 0.0), unit["max_health"], color, FOUi.tokens.space_1
		)
		bar.tooltip_text = (
			"%s %.0f / %.0f" % [tr("FLEET_PANEL_STRUCTURE"), unit["health"], unit["max_health"]]
		)
		text.add_child(bar)
		if replayed:
			_replay_bars.push_back([bar, health])
	return row


func _health_bar(value: float, max_value: float, color: Color, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = maxf(max_value, 1.0)
	bar.value = clampf(value, 0.0, bar.max_value)
	bar.show_percentage = false
	bar.custom_minimum_size.y = height
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(FOUi.tokens.radius_small)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _event_row(event: Dictionary) -> Control:
	var kind: String = event.get("kind", "other")
	if kind == "bout":
		return _indented(
			ScreenKit.label(event.get("text", ""), "TitleLabel"), 0, FOUi.tokens.space_2
		)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	box.add_child(row)
	var children: Array = event.get("children", [])
	var details: String = event.get("details", "")
	var expandable := not (children.is_empty() and details.is_empty())
	# The marker column: the event's kind, or a toggle for its shots.
	var marker: Control
	if expandable:
		marker = _shots_toggle()
	else:
		marker = ScreenKit.label(KIND_MARKERS.get(kind, "·"), "SecondaryLabel")
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if kind == "destroyed":
			marker.add_theme_color_override("font_color", FOUi.tokens.negative)
	marker.custom_minimum_size.x = FOUi.tokens.space_6
	marker.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(marker)
	row.add_child(_rich(event.get("text", "")))
	if not expandable:
		return box
	var shots := VBoxContainer.new()
	shots.visible = false
	shots.add_theme_constant_override("separation", 0)
	box.add_child(shots)
	# Shots are built on first expand: big combats have hundreds.
	marker.toggled.connect(_on_shots_toggled.bind(marker, shots, event))
	return box


# A borderless ▸/▾ toggle, the size of the text beside it.
func _shots_toggle() -> Button:
	var toggle := Button.new()
	toggle.text = "▸"
	toggle.toggle_mode = true
	toggle.tooltip_text = tr("COMBAT_REPORT_SHOW_SHOTS")
	toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		toggle.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for color in ["font_color", "font_pressed_color", "font_focus_color"]:
		toggle.add_theme_color_override(color, FOUi.tokens.text_secondary)
	toggle.add_theme_color_override("font_hover_color", FOUi.tokens.accent)
	toggle.add_theme_color_override("font_hover_pressed_color", FOUi.tokens.accent)
	return toggle


func _on_shots_toggled(
	pressed: bool, toggle: Button, shots: VBoxContainer, event: Dictionary
) -> void:
	toggle.text = "▾" if pressed else "▸"
	if pressed and shots.get_child_count() == 0:
		var details: String = event.get("details", "")
		var indent := FOUi.tokens.space_6
		if not details.is_empty():
			shots.add_child(_indented(_rich(details, "SmallLabel"), indent))
		for child: Dictionary in event.get("children", []):
			shots.add_child(_indented(_rich(child.get("text", ""), "SmallLabel"), indent))
			if not str(child.get("details", "")).is_empty():
				shots.add_child(_indented(_rich(child["details"], "SmallLabel"), indent * 2))
	shots.visible = pressed


# \a control with \a left and \a top margins only (the theme's
# MarginContainer default pads every side).
static func _indented(control: Control, left: int, top := 0) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_right", 0)
	margin.add_theme_constant_override("margin_bottom", 0)
	margin.add_child(control)
	return margin


## Log events without rounds that have nothing in them.
static func without_empty_bouts(events: Array) -> Array:
	var result: Array = []
	for i in events.size():
		var event: Dictionary = events[i]
		if event.get("kind", "") == "bout":
			var next_is_bout: bool = (
				i + 1 >= events.size() or events[i + 1].get("kind", "") == "bout"
			)
			if next_is_bout:
				continue
		result.push_back(event)
	return result


# Text with FreeOrion markup; links emit link_activated.
func _rich(text: String, size_variation := "") -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match size_variation:
		"HeadingLabel":
			label.add_theme_font_size_override("normal_font_size", FOUi.tokens.font_size_heading)
		"SmallLabel":
			label.add_theme_font_size_override("normal_font_size", FOUi.tokens.font_size_small)
			label.add_theme_color_override("default_color", FOUi.tokens.text_secondary)
	label.text = FORichText.to_bbcode(text, FOUi.tokens.icon_small)
	label.meta_clicked.connect(_on_meta_clicked)
	return label


func _on_meta_clicked(meta: Variant) -> void:
	var link := FORichText.parse_link(str(meta))
	link_activated.emit(link["kind"], link["arg"])
