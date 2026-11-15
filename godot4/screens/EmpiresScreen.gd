class_name EmpiresScreen
extends PanelContainer
## Empires: every empire with its player, how the player stands with it
## (war, peace, alliance), proposals waiting either way, and the diplomatic
## actions open now (propose, accept, reject, withdraw, declare war, end an
## alliance). Actions go to the server at once.

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

var source: Variant = DiplomacySource.new()

var _info: Label
var _list: VBoxContainer


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
	_list = ScreenKit.list()
	_list.add_theme_constant_override("separation", FOUi.tokens.space_2)
	box.add_child(ScreenKit.scrolling(_list))


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
