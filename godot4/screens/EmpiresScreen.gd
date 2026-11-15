class_name EmpiresScreen
extends PanelContainer
## Empires: every empire with its player, how the player stands with it
## (war, peace, alliance), proposals waiting either way, and the diplomatic
## actions open now (propose, accept, reject, withdraw, declare war, end an
## alliance). Actions go to the server at once. The Statistics tab charts
## the empires' statistics (output, ships, planets, ...) turn by turn.

signal close_requested

## Actions: name for FODiplomacy.act(), label key, button variation.
const ACTIONS := {
	"accept_peace": ["DIPLOMACY_ACCEPT_PEACE", "PrimaryButton"],
	"accept_alliance": ["DIPLOMACY_ACCEPT_ALLIANCE", "PrimaryButton"],
	"reject": ["DIPLOMACY_REJECT", "GhostButton"],
	"cancel": ["DIPLOMACY_CANCEL", "GhostButton"],
	"propose_peace": ["DIPLOMACY_PROPOSE_PEACE", ""],
	"propose_alliance": ["DIPLOMACY_PROPOSE_ALLIANCE", ""],
	"end_alliance": ["DIPLOMACY_END_ALLIANCE", "DangerButton"],
	"declare_war": ["DIPLOMACY_DECLARE_WAR", "DangerButton"],
}
const STATUS_KEYS := {
	"war": "DIPLOMACY_STATUS_WAR",
	"peace": "DIPLOMACY_STATUS_PEACE",
	"allied": "DIPLOMACY_STATUS_ALLIED",
}

## Tabs: label key.
const TABS := ["EMPIRES_TAB_DIPLOMACY", "EMPIRES_TAB_STATISTICS"]

var source: Variant = DiplomacySource.new()

var _info: Label
var _list: VBoxContainer
var _tabs: TabBar
var _diplomacy: Control
var _statistics: Control
var _stat_list: VBoxContainer
var _stat_title: Label
var _chart: LineChart
var _legend: HFlowContainer
var _records := {}
var _stat := ""


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "BackgroundPanel"
	_build()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	ScreenKit.clear(_list)
	for empire: Dictionary in source.get_empires():
		_list.add_child(_empire_card(empire))
	if _statistics.visible:
		_refresh_statistics()


## Show the Statistics tab with statistic \a stat_name (a stat record key).
func show_statistic(stat_name: String) -> void:
	_stat = stat_name
	_tabs.current_tab = 1
	_refresh_statistics()


func _on_tab_changed(tab: int) -> void:
	_diplomacy.visible = tab == 0
	_statistics.visible = tab == 1
	if tab == 1:
		_refresh_statistics()


func _refresh_statistics() -> void:
	_records = source.get_stat_records()
	var names: Array = _records.keys()
	names.sort_custom(func(a, b): return _tr(a).naturalnocasecmp_to(_tr(b)) < 0)
	if not _records.has(_stat):
		_stat = names[0] if not names.is_empty() else ""
	ScreenKit.clear(_stat_list)
	for stat_name: String in names:
		var button := Button.new()
		button.text = ScreenKit.tr_or_name(stat_name)
		button.toggle_mode = true
		button.button_pressed = stat_name == _stat
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.theme_type_variation = "GhostButton"
		button.pressed.connect(_select_stat.bind(stat_name))
		_stat_list.add_child(button)
	_show_chart()


func _select_stat(stat_name: String) -> void:
	_stat = stat_name
	for button: Button in _stat_list.get_children():
		button.set_pressed_no_signal(button.text == ScreenKit.tr_or_name(stat_name))
	_show_chart()


func _show_chart() -> void:
	_stat_title.text = (
		ScreenKit.tr_or_name(_stat) if not _stat.is_empty() else tr("EMPIRES_NO_STATISTICS")
	)
	var lines: Array = _records.get(_stat, [])
	var own_id: int = source.get_own_empire_id()
	var series := []
	var highlight := -1
	for line: Dictionary in lines:
		if line.get("empire_id", -1) == own_id:
			highlight = series.size()
		(
			series
			. push_back(
				{
					"label": line.get("name", ""),
					"color": line.get("color", Color.WHITE),
					"turns": line.get("turns", PackedInt32Array()),
					"values": line.get("values", PackedFloat64Array()),
				}
			)
		)
	_chart.series = series
	_chart.highlight = highlight
	_fill_legend(series)


# One toggle per empire, to leave its line out.
func _fill_legend(series: Array) -> void:
	ScreenKit.clear(_legend)
	for i in series.size():
		var toggle := CheckBox.new()
		toggle.text = series[i]["label"]
		toggle.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		toggle.button_pressed = not _chart.hidden_series.has(i)
		toggle.add_theme_color_override("font_color", series[i]["color"])
		toggle.add_theme_color_override("font_pressed_color", series[i]["color"])
		toggle.add_theme_color_override("font_hover_pressed_color", series[i]["color"])
		toggle.toggled.connect(
			func(on: bool):
				var hidden: Dictionary = _chart.hidden_series.duplicate()
				if on:
					hidden.erase(i)
				else:
					hidden[i] = true
				_chart.hidden_series = hidden
		)
		_legend.add_child(toggle)


## The line under an empire's name: status, then any proposal waiting.
static func status_text(empire: Dictionary) -> String:
	if empire.get("own", false):
		return _tr("DIPLOMACY_YOU")
	if empire.get("eliminated", false):
		return _tr("DIPLOMACY_ELIMINATED")
	var parts: PackedStringArray = []
	var status: String = empire.get("status", "")
	if STATUS_KEYS.has(status):
		parts.push_back(_tr(STATUS_KEYS[status]))
	var incoming: String = empire.get("incoming", "")
	if not incoming.is_empty():
		parts.push_back(_tr("DIPLOMACY_INCOMING_" + incoming.to_upper()))
	var outgoing: String = empire.get("outgoing", "")
	if not outgoing.is_empty():
		parts.push_back(_tr("DIPLOMACY_OUTGOING_" + outgoing.to_upper()))
	return " · ".join(parts)


func _build() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	_info = ScreenKit.header(box, "EMPIRES_TITLE", close_requested.emit)
	_tabs = TabBar.new()
	for key in TABS:
		_tabs.add_tab(tr(key))
	box.add_child(_tabs)
	_list = ScreenKit.list()
	_list.add_theme_constant_override("separation", FOUi.tokens.space_2)
	_diplomacy = ScreenKit.scrolling(_list)
	box.add_child(_diplomacy)

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", FOUi.tokens.space_4)
	split.visible = false
	_statistics = split
	box.add_child(split)
	_stat_list = ScreenKit.list()
	var stat_scroll := ScreenKit.scrolling(_stat_list)
	stat_scroll.custom_minimum_size.x = 260
	stat_scroll.size_flags_horizontal = Control.SIZE_FILL
	split.add_child(stat_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_stat_title = ScreenKit.label("", "TitleLabel")
	right.add_child(_stat_title)
	_chart = LineChart.new()
	_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_chart)
	_legend = HFlowContainer.new()
	right.add_child(_legend)
	_tabs.tab_changed.connect(_on_tab_changed)


func _empire_card(empire: Dictionary) -> Control:
	var card := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FOUi.tokens.space_3)
	card.add_child(row)
	var swatch := ColorRect.new()
	swatch.color = empire.get("color", Color.GRAY)
	swatch.custom_minimum_size = Vector2(FOUi.tokens.space_2, FOUi.tokens.icon_large)
	row.add_child(swatch)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var title := ScreenKit.label(empire.get("name", ""), "TitleLabel")
	var player: String = empire.get("player", "")
	if not player.is_empty():
		title.text += "  ·  " + player
	text.add_child(title)
	var status := ScreenKit.label(status_text(empire), "SecondaryLabel")
	match empire.get("status", ""):
		"war":
			status.add_theme_color_override("font_color", FOUi.tokens.negative)
		"allied":
			status.add_theme_color_override("font_color", FOUi.tokens.positive)
	if not str(empire.get("incoming", "")).is_empty():
		status.add_theme_color_override("font_color", FOUi.tokens.warning)
	text.add_child(status)
	if empire.get("eliminated", false):
		card.modulate = Color(1, 1, 1, 0.5)
	for action: String in empire.get("actions", []):
		if not ACTIONS.has(action):
			continue
		var button := Button.new()
		button.text = tr(ACTIONS[action][0])
		button.theme_type_variation = ACTIONS[action][1]
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(_on_action.bind(empire.get("id", -1), action))
		row.add_child(button)
	return card


func _on_action(empire_id: int, action: String) -> void:
	_info.text = tr("DIPLOMACY_SENT" if source.act(empire_id, action) else "DIPLOMACY_REFUSED")
	refresh()


static func _tr(key: String) -> String:
	return TranslationServer.translate(key)
