class_name LobbyPlayerList
extends VBoxContainer
## The players of a multiplayer lobby, for LobbyScreen, one row each: type,
## name, empire name, colour and starting species (new game) or the saved
## empire taken over (loaded game), and whether they are ready. The host
## edits any row, others their own, and who may set up the galaxy also the
## AI players' rows; AI players are added and players dropped here. Each
## edit emits the whole players list to send.

signal players_edited(players: Array)

## Client types: name -> label key.
const TYPE_LABELS := {
	"player": "HUMAN_PLAYER",
	"ai": "AI_PLAYER",
	"observer": "OBSERVER",
	"moderator": "MODERATOR",
}
## Types a human player's row can be switched to, then "drop".
const HUMAN_TYPES := ["player", "observer", "moderator"]
const DROP := "drop"
## Cell widths, small enough that the lobby fits a 1024 px window; longer
## names and species are cut short, with the whole in the tooltip.
const TYPE_WIDTH := 88
const NAME_WIDTH := 72
const SPECIES_WIDTH := 112
const STATUS_WIDTH := 72

## Species for the species pickers: [{name, icon}].
var species: Array = []
## Colours an empire can have.
var colors := PackedColorArray()

var _lobby := {}
var _my_id := -1
var _is_host := false
var _can_setup := false
var _rows: VBoxContainer
# The players last sent to the server, until it sends the lobby back.
var _sent: Array = []


func _init() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_theme_constant_override("separation", FOUi.tokens.space_2)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", FOUi.tokens.space_1)
	add_child(_rows)


## Show \a lobby's players as player \a my_id sees them: \a is_host edits
## every row, \a can_setup also AI rows (and adds AIs).
func show_lobby(lobby: Dictionary, my_id: int, is_host: bool, can_setup: bool) -> void:
	_sent = []
	# Keep what is being typed into an empire name across the rebuild.
	var typing := {}
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused is LineEdit and _rows.is_ancestor_of(focused):
		typing = {
			"player_id": focused.get_meta("player_id", -2),
			"text": focused.text,
			"caret": focused.caret_column,
		}
	_lobby = lobby
	_my_id = my_id
	_is_host = is_host
	_can_setup = can_setup
	ScreenKit.clear(_rows)
	var new_game: bool = lobby.get("new_game", true)
	for player: Dictionary in lobby.get("players", []):
		_rows.add_child(_player_row(player, new_game))
	if not new_game:
		for empire: Dictionary in unassigned_empires(lobby):
			_rows.add_child(_empire_row(empire))
	elif can_setup:
		var add_ai := Button.new()
		add_ai.text = "+ " + tr("ADD_AI_PLAYER")
		add_ai.theme_type_variation = "GhostButton"
		add_ai.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		add_ai.pressed.connect(add_ai_player)
		_rows.add_child(add_ai)
	if not typing.is_empty():
		for edit in _rows.find_children("*", "LineEdit", true, false):
			if edit.get_meta("player_id", -3) == typing["player_id"]:
				edit.text = typing["text"]
				edit.grab_focus()
				edit.caret_column = typing["caret"]


## Whether this player may change \a player's row.
func can_edit(player: Dictionary) -> bool:
	if _is_host:
		return true
	if player.get("player_id", -1) == _my_id:
		return true
	return player.get("client_type", "") == "ai" and _can_setup


## Rows drawn, excluding the "add AI" button (tests).
func row_count() -> int:
	return _rows.get_children().filter(func(c): return c is HBoxContainer).size()


## Add an AI player with the first free colour (new game).
func add_ai_player() -> void:
	var players := _players_copy()
	var used := []
	for player: Dictionary in players:
		used.push_back(player.get("color", Color.WHITE))
	var color := Color.WHITE
	for candidate in colors:
		if not candidate in used:
			color = candidate
			break
	(
		players
		. push_back(
			{
				"player_id": -1,
				"client_type": "ai",
				"player_name": "",
				"empire_name": "",
				"color": color,
				"species": species[0]["name"] if not species.is_empty() else "",
			}
		)
	)
	_emit_players(players)


## Saved empires nobody has taken over yet (loaded game).
static func unassigned_empires(lobby: Dictionary) -> Array:
	var taken := []
	for player: Dictionary in lobby.get("players", []):
		taken.push_back(player.get("save_empire_id", -1))
	return lobby.get("save_empires", []).filter(
		func(e: Dictionary): return not e.get("empire_id", -1) in taken
	)


## Whether \a lobby can start as far as names and colours go: each empire
## played (not observed) has a name, and names and colours are unique.
static func player_data_acceptable(lobby: Dictionary) -> bool:
	var names := {}
	var colours := {}
	var count := 0
	for player: Dictionary in lobby.get("players", []):
		if not player.get("client_type", "") in ["player", "ai"]:
			continue
		count += 1
		var empire_name: String = player.get("empire_name", "")
		if empire_name.strip_edges().is_empty():
			return false
		names[empire_name] = true
		colours[Color(player.get("color", Color.WHITE)).to_rgba32()] = true
	return count > 0 and names.size() == count and colours.size() == count


## What keeps \a lobby from starting as far as names and colours go, in
## words ("" when nothing does): an empire without a name, two with one
## name, two of one colour.
static func data_problem(lobby: Dictionary) -> String:
	var t := TranslationServer.translate
	var names := {}
	var colours := {}
	for player: Dictionary in lobby.get("players", []):
		if not player.get("client_type", "") in ["player", "ai"]:
			continue
		var empire_name: String = str(player.get("empire_name", "")).strip_edges()
		if empire_name.is_empty():
			return t.call("MP_EMPIRE_UNNAMED").replace("%1%", player.get("player_name", ""))
		if names.has(empire_name):
			return t.call("MP_EMPIRE_NAME_TWICE").replace("%1%", empire_name)
		names[empire_name] = true
		var colour := Color(player.get("color", Color.WHITE)).to_rgba32()
		if colours.has(colour):
			return t.call("MP_EMPIRE_COLOR_TWICE").replace("%1%", colours[colour]).replace(
				"%2%", empire_name
			)
		colours[colour] = empire_name
	return ""


# Edits ---------------------------------------------------------------


# The players as last sent, while the server hasn't answered yet (so a
# second edit, a second AI added quickly, keeps the first), else as the
# server last sent them.
func _players_copy() -> Array:
	var players := []
	for player: Dictionary in _sent if not _sent.is_empty() else _lobby.get("players", []):
		players.push_back(player.duplicate())
	return players


func _emit_players(players: Array) -> void:
	_sent = players
	players_edited.emit(players)


func _edit(player_id: int, changes: Dictionary) -> void:
	var players := _players_copy()
	for player: Dictionary in players:
		if player.get("player_id", -1) == player_id:
			player.merge(changes, true)
	_emit_players(players)


func _drop(player_id: int) -> void:
	_emit_players(_players_copy().filter(func(p): return p.get("player_id", -1) != player_id))


func _on_type_picked(index: int, picker: OptionButton, player_id: int) -> void:
	var type: String = picker.get_item_metadata(index)
	if type == DROP:
		_drop(player_id)
	else:
		_edit(player_id, {"client_type": type})


func _on_empire_picked(index: int, picker: OptionButton, player_id: int) -> void:
	var empire_id: int = picker.get_item_metadata(index)
	var changes := {"save_empire_id": empire_id}
	for empire: Dictionary in _lobby.get("save_empires", []):
		if empire.get("empire_id", -1) == empire_id:
			changes["empire_name"] = empire.get("empire_name", "")
			changes["color"] = empire.get("color", Color.WHITE)
	_edit(player_id, changes)


func _add_ai_for(empire: Dictionary) -> void:
	var players := _players_copy()
	(
		players
		. push_back(
			{
				"player_id": -1,
				"client_type": "ai",
				"player_name": empire.get("player_name", ""),
				"empire_name": empire.get("empire_name", ""),
				"color": empire.get("color", Color.WHITE),
				"save_empire_id": empire.get("empire_id", -1),
			}
		)
	)
	_emit_players(players)


# Rows ----------------------------------------------------------------


func _player_row(player: Dictionary, new_game: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FOUi.tokens.space_2)
	var player_id: int = player.get("player_id", -1)
	var editable := can_edit(player)
	var type: String = player.get("client_type", "")
	row.add_child(_type_cell(type, player_id, editable and (_is_host or type == "ai")))
	var name_label := ScreenKit.label(player.get("player_name", ""))
	name_label.custom_minimum_size.x = NAME_WIDTH
	name_label.clip_text = true
	# The spare width goes to names and species, not only empire names.
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_stretch_ratio = 0.6
	name_label.tooltip_text = name_label.text
	if player_id == _my_id:
		name_label.add_theme_color_override("font_color", FOUi.tokens.accent)
	row.add_child(name_label)
	var plays := type in ["player", "ai"]
	if plays and new_game:
		_add_new_game_cells(row, player, editable)
	elif plays:
		_add_load_game_cells(row, player, editable)
	else:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
	if type != "ai":
		var ready: bool = player.get("ready", false)
		var mark := ScreenKit.label(
			"✔ " + tr("MP_PLAYER_READY") if ready else tr("MP_PLAYER_NOT_READY"),
			"" if ready else "SecondaryLabel"
		)
		mark.custom_minimum_size.x = STATUS_WIDTH
		if ready:
			mark.add_theme_color_override("font_color", FOUi.tokens.positive)
		row.add_child(mark)
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size.x = STATUS_WIDTH
		row.add_child(spacer)
	return row


func _type_cell(type: String, player_id: int, editable: bool) -> Control:
	if not editable:
		var label := ScreenKit.label(tr(TYPE_LABELS.get(type, "PLAYER")), "SecondaryLabel")
		label.custom_minimum_size.x = TYPE_WIDTH
		return label
	var picker := OptionButton.new()
	picker.custom_minimum_size.x = TYPE_WIDTH
	picker.fit_to_longest_item = false
	for option in ["ai"] if type == "ai" else HUMAN_TYPES:
		picker.add_item(tr(TYPE_LABELS[option]))
		picker.set_item_metadata(picker.item_count - 1, option)
		if option == type:
			picker.select(picker.item_count - 1)
	# The host can't drop themselves; leaving does that.
	if player_id != _my_id:
		picker.add_item(tr("DROP_PLAYER"))
		picker.set_item_metadata(picker.item_count - 1, DROP)
	picker.item_selected.connect(_on_type_picked.bind(picker, player_id))
	return picker


func _add_new_game_cells(row: HBoxContainer, player: Dictionary, editable: bool) -> void:
	var player_id: int = player.get("player_id", -1)
	var empire := LineEdit.new()
	empire.text = player.get("empire_name", "")
	empire.editable = editable
	empire.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	empire.max_length = 64
	empire.placeholder_text = tr("GSETUP_EMPIRE_NAME")
	empire.set_meta("player_id", player_id)
	var commit := func(_t := ""):
		if empire.text.strip_edges() != player.get("empire_name", ""):
			_edit(player_id, {"empire_name": empire.text.strip_edges()})
	empire.text_submitted.connect(commit)
	empire.focus_exited.connect(commit)
	row.add_child(empire)
	row.add_child(_color_picker(player, editable))
	row.add_child(_species_picker(player, editable))


func _color_picker(player: Dictionary, editable: bool) -> OptionButton:
	var picker := OptionButton.new()
	picker.tooltip_text = tr("GSETUP_EMPIRE_COLOR")
	picker.disabled = not editable
	var current := Color(player.get("color", Color.WHITE))
	var all := colors.duplicate()
	if not current in all:
		all.push_back(current)
	for color in all:
		picker.add_icon_item(FOArt.swatch(color), "")
		picker.set_item_metadata(picker.item_count - 1, color)
		if color == current:
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(
		func(i): _edit(player.get("player_id", -1), {"color": picker.get_item_metadata(i)})
	)
	return picker


func _species_picker(player: Dictionary, editable: bool) -> OptionButton:
	var picker := OptionButton.new()
	picker.custom_minimum_size.x = SPECIES_WIDTH
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.size_flags_stretch_ratio = 0.7
	picker.fit_to_longest_item = false
	picker.clip_text = true
	picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	picker.disabled = not editable
	picker.add_theme_constant_override("icon_max_width", FOUi.tokens.icon)
	var current: String = player.get("species", "")
	var names := species.map(func(s): return s["name"])
	var entries := species.duplicate()
	if not current.is_empty() and not current in names:
		entries.push_back({"name": current})
	for entry: Dictionary in entries:
		picker.add_item(ScreenKit.tr_or_name(entry["name"]))
		var index := picker.item_count - 1
		picker.set_item_metadata(index, entry["name"])
		var icon := FOArt.icon(entry.get("icon", ""))
		if icon:
			picker.set_item_icon(index, icon)
		if entry["name"] == current:
			picker.select(index)
	picker.tooltip_text = picker.text
	picker.item_selected.connect(
		func(i): _edit(player.get("player_id", -1), {"species": picker.get_item_metadata(i)})
	)
	return picker


func _add_load_game_cells(row: HBoxContainer, player: Dictionary, editable: bool) -> void:
	var player_id: int = player.get("player_id", -1)
	var current: int = player.get("save_empire_id", -1)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.fit_to_longest_item = false
	picker.disabled = not editable or _lobby.get("save_empires", []).is_empty()
	# Greyed out: why.
	if picker.disabled:
		picker.tooltip_text = tr(
			"MP_NO_SAVE_PICKED" if _lobby.get("save_empires", []).is_empty() else "MP_NOT_YOURS"
		)
	picker.add_item(tr("NO_EMPIRE"))
	picker.set_item_metadata(0, -1)
	var original := ""
	var free := unassigned_empires(_lobby).map(func(e): return e.get("empire_id", -1))
	for empire: Dictionary in _lobby.get("save_empires", []):
		var empire_id: int = empire.get("empire_id", -1)
		# Free empires, and the one this player has.
		if empire_id != current and not empire_id in free:
			continue
		picker.add_icon_item(
			FOArt.swatch(empire.get("color", Color.WHITE)), empire.get("empire_name", "")
		)
		picker.set_item_metadata(picker.item_count - 1, empire_id)
		if empire_id == current:
			picker.select(picker.item_count - 1)
			original = empire.get("player_name", "")
	picker.item_selected.connect(_on_empire_picked.bind(picker, player_id))
	row.add_child(picker)
	var was := ScreenKit.label(
		tr("MP_ORIGINAL_PLAYER").replace("%1%", original) if not original.is_empty() else "",
		"SecondaryLabel"
	)
	was.custom_minimum_size.x = SPECIES_WIDTH
	was.clip_text = true
	was.tooltip_text = was.text
	row.add_child(was)


# A saved empire no player has: who played it, and "add AI" for it.
func _empire_row(empire: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FOUi.tokens.space_2)
	var icon := TextureRect.new()
	icon.texture = FOArt.swatch(empire.get("color", Color.WHITE))
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.custom_minimum_size.x = 110
	row.add_child(icon)
	var label := ScreenKit.label(
		(
			"%s  —  %s"
			% [
				empire.get("empire_name", ""),
				tr("MP_ORIGINAL_PLAYER").replace("%1%", empire.get("player_name", ""))
			]
		),
		"SecondaryLabel"
	)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if _can_setup:
		var add := Button.new()
		add.text = tr("ADD_AI_PLAYER")
		add.theme_type_variation = "GhostButton"
		add.pressed.connect(_add_ai_for.bind(empire))
		row.add_child(add)
	return row
