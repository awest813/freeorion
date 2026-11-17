class_name LobbyScreen
extends PanelContainer
## The multiplayer lobby, as the GG client's: the players (LobbyPlayerList)
## and chat on the left; on the right a new or loaded game, the galaxy
## settings or the save to load, whether everyone may edit them, why the
## game can't start yet, and the ready button. The game starts once every
## human player is ready. Shell refreshes it when the server sends the
## lobby or chat, and leaves the server on leave_requested.

signal leave_requested

## Galaxy settings: lobby galaxy key -> setup option in GalaxySetupScreen.CHOICES.
const GALAXY_CHOICES := {
	"shape": "setup.galaxy.shape",
	"age": "setup.galaxy.age",
	"starlane_freq": "setup.starlane.frequency",
	"planet_density": "setup.planet.density",
	"specials_freq": "setup.specials.frequency",
	"native_freq": "setup.native.frequency",
	"monster_freq": "setup.monster.frequency",
	"ai_aggression": "setup.ai.aggression",
}
const MIN_STARS := 10
const MAX_STARS := 5000

var source: Variant = LobbySource.new()
var players: LobbyPlayerList
var chat: ChatPanel
var ready_button: Button
var new_game_button: Button
var load_game_button: Button
var any_can_edit: CheckBox
var save_picker: OptionButton
var seed_edit: LineEdit
var stars: SpinBox

var _choices := {}
## Ready was sent and the server hasn't taken it back yet.
var _ready_sent := false
var _galaxy_grid: GridContainer
var _save_label: Label
var _conditions: Label
var _preview: GalaxyPreview
var _room: Label
var _info: Label
# What the server is doing while it starts the game ("" before it begins).
var _progress := ""
var _lobby := {}
var _saves: Array = []


func _init() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "BackgroundPanel"
	_build()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		leave_requested.emit()
		get_viewport().set_input_as_handled()


## Show the lobby as the server last sent it.
func refresh() -> void:
	_lobby = source.lobby()
	var can_setup: bool = source.has_role("galaxy_setup")
	var is_host: bool = source.has_role("host")
	var new_game: bool = _lobby.get("new_game", true)
	if players.species.is_empty():
		players.species = source.playable_species()
		players.colors = source.empire_colors()
	players.show_lobby(_lobby, source.player_id(), is_host, can_setup)

	new_game_button.set_pressed_no_signal(new_game)
	load_game_button.set_pressed_no_signal(not new_game)
	new_game_button.disabled = not can_setup
	load_game_button.disabled = not can_setup
	any_can_edit.set_pressed_no_signal(_lobby.get("any_can_edit", false))
	any_can_edit.disabled = not is_host
	_galaxy_grid.visible = new_game
	_preview.visible = new_game
	_save_label.get_parent().visible = not new_game
	_fill_galaxy(_lobby.get("galaxy", {}), can_setup)
	_fill_save(can_setup)
	_info.text = tr("MP_SETTINGS_LOCKED") if not can_setup else ""
	_update_ready()


## The server's saves arrived: list them anew.
func saves_changed() -> void:
	_saves = []
	refresh()


## Show the chat as received so far.
func refresh_chat() -> void:
	chat.set_lines(source.chat())


## The ready button's text: decline if ready, start if everyone else is.
func ready_text() -> String:
	return ready_button.text


func conditions_text() -> String:
	return _conditions.text


## What the server is doing while it starts the game (its turn progress:
## creating the universe, ...), shown on the start button, as GG's lobby
## shows it.
func set_progress(text: String) -> void:
	_progress = text
	ready_button.text = text if not text.is_empty() else tr("MP_STARTING")
	ready_button.disabled = true


## Whether \a lobby has a player who plays an empire (observers and
## moderators don't): the server can't start a game without one.
static func has_human_player(lobby: Dictionary) -> bool:
	for player: Dictionary in lobby.get("players", []):
		if player.get("client_type", "") == "player":
			return true
	return false


## Empires the game would start with: players and AI players (not
## observers or moderators).
static func empire_count(lobby: Dictionary) -> int:
	return (
		lobby
		. get("players", [])
		. filter(func(p): return p.get("client_type", "") in ["player", "ai"])
		. size()
	)


func _me() -> Dictionary:
	for player: Dictionary in _lobby.get("players", []):
		if player.get("player_id", -1) == source.player_id():
			return player
	return {}


func _update_ready() -> void:
	var me := _me()
	var others_ready := true
	for player: Dictionary in _lobby.get("players", []):
		if (
			player.get("player_id", -1) != source.player_id()
			and player.get("client_type", "") != "ai"
		):
			others_ready = others_ready and player.get("ready", false)
	var me_ready: bool = me.get("ready", false)
	# The server drops a player's ready when it corrects their settings.
	if _ready_sent and not me_ready and not me.is_empty():
		_ready_sent = false
		_info.text = tr("MP_READY_RESET")
	if me_ready:
		ready_button.text = tr("NOT_READY_BN")
	elif others_ready:
		ready_button.text = tr("START_GAME_BN")
	else:
		ready_button.text = tr("READY_BN")
	ready_button.disabled = me.is_empty() or _lobby.get("start_locked", false)
	# Everyone is ready: the game is starting, and a ready sent now would be
	# refused by the server (it disconnects the player).
	if me_ready and others_ready:
		ready_button.text = _progress if not _progress.is_empty() else tr("MP_STARTING")
		ready_button.disabled = true
	else:
		_progress = ""
	_conditions.remove_theme_color_override("font_color")
	if not has_human_player(_lobby):
		_conditions.text = tr("MP_NEEDS_HUMAN_PLAYER")
		_conditions.add_theme_color_override("font_color", FOUi.tokens.warning)
	elif empire_count(_lobby) < 2:
		# Alone, the game is won as soon as it starts.
		_conditions.text = tr("MP_ALONE")
		_conditions.add_theme_color_override("font_color", FOUi.tokens.warning)
	elif not _lobby.get("new_game", true) and _picks_no_empire(me):
		# A loaded game: the server's "not enough human players" means this.
		_conditions.text = tr("MP_PICK_EMPIRE")
		_conditions.add_theme_color_override("font_color", FOUi.tokens.warning)
	elif _lobby.get("start_locked", false):
		_conditions.text = ScreenKit.tr_or_name(_lobby.get("start_lock_cause", ""))
		_conditions.add_theme_color_override("font_color", FOUi.tokens.warning)
	else:
		# What stands in the way, by name; else that all is set.
		var problem := LobbyPlayerList.data_problem(_lobby)
		_conditions.text = problem if not problem.is_empty() else tr("MP_ALL_SET")
		if not problem.is_empty():
			_conditions.add_theme_color_override("font_color", FOUi.tokens.warning)
	# A disabled start button says why, as the line above it does.
	ready_button.tooltip_text = _conditions.text if ready_button.disabled else ""


# Whether \a me plays (not observes) without having picked a saved empire.
static func _picks_no_empire(me: Dictionary) -> bool:
	return me.get("client_type", "") == "player" and me.get("save_empire_id", -1) < 0


func _fill_galaxy(galaxy: Dictionary, editable: bool) -> void:
	if not seed_edit.has_focus():
		seed_edit.text = str(galaxy.get("seed", ""))
	seed_edit.editable = editable
	stars.set_value_no_signal(galaxy.get("size", stars.value))
	stars.editable = editable
	for key in _choices:
		var picker: OptionButton = _choices[key]
		var index := GalaxySetupScreen._choice_index(picker, str(galaxy.get(key, "")))
		if index >= 0:
			picker.select(index)
		picker.disabled = not editable
	var shape: String = galaxy.get("shape", "")
	_preview.shape = shape
	_preview.systems = int(stars.value)
	# As in single-player setup: how much room each empire gets.
	var empires: int = (
		_lobby
		. get("players", [])
		. filter(func(p): return p.get("client_type", "") in ["player", "ai"])
		. size()
	)
	_room.text = GalaxySetupScreen.room_text(int(stars.value), maxi(empires, 1))


func _fill_save(editable: bool) -> void:
	var file: String = _lobby.get("save_game", "")
	_save_label.text = file if not file.is_empty() else tr("MP_SAVE_NONE")
	_save_label.tooltip_text = file
	save_picker.visible = editable
	if not editable or _lobby.get("new_game", true):
		return
	if _saves.is_empty():
		_saves = source.list_saves()
	save_picker.clear()
	save_picker.add_item(tr("MP_SAVE_PICK"))
	save_picker.set_item_metadata(0, "")
	for save: Dictionary in _saves:
		save_picker.add_item(
			tr("MP_SAVE_ENTRY").replace("%1%", save.get("file", "")).replace(
				"%2%", str(save.get("turn", 0))
			)
		)
		save_picker.set_item_metadata(save_picker.item_count - 1, save.get("file", ""))
		if save.get("file", "") == file:
			save_picker.select(save_picker.item_count - 1)
	save_picker.tooltip_text = file


func _send_galaxy(key: String, value: Variant) -> void:
	source.send_lobby({"galaxy": {key: value}})


func _build() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", FOUi.tokens.space_6)
	margin.add_child(columns)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", FOUi.tokens.space_3)
	columns.add_child(left)
	_info = ScreenKit.header(left, "MPLOBBY_WINDOW_TITLE", leave_requested.emit)
	left.add_child(ScreenKit.section(tr("MP_LOBBY_PLAYERS")))
	players = LobbyPlayerList.new()
	players.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players.players_edited.connect(func(list): source.send_lobby({"players": list}))
	var player_scroll := ScreenKit.scrolling(players)
	player_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_scroll.size_flags_stretch_ratio = 1.4
	left.add_child(player_scroll)
	left.add_child(ScreenKit.section(tr("MP_LOBBY_CHAT")))
	chat = ChatPanel.new()
	chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat.message_sent.connect(func(text): source.send_chat(text))
	left.add_child(chat)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 360
	right.add_theme_constant_override("separation", FOUi.tokens.space_3)
	columns.add_child(right)
	_build_game_kind(right)
	# The galaxy settings scroll on short screens; the buttons stay put.
	var galaxy := VBoxContainer.new()
	galaxy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	galaxy.add_theme_constant_override("separation", FOUi.tokens.space_3)
	var galaxy_scroll := ScreenKit.scrolling(galaxy)
	galaxy_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(galaxy_scroll)
	_build_galaxy(galaxy)
	any_can_edit = CheckBox.new()
	any_can_edit.text = tr("EDITABLE_GALAXY_SETTINGS")
	any_can_edit.tooltip_text = tr("EDITABLE_GALAXY_SETTINGS_DESC")
	any_can_edit.toggled.connect(func(on): source.send_lobby({"any_can_edit": on}))
	right.add_child(any_can_edit)
	_conditions = ScreenKit.label("", "SecondaryLabel")
	_conditions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_conditions)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(buttons)
	var leave := Button.new()
	leave.text = tr("MP_LEAVE")
	leave.theme_type_variation = "GhostButton"
	leave.pressed.connect(leave_requested.emit)
	buttons.add_child(leave)
	ready_button = Button.new()
	ready_button.text = tr("READY_BN")
	ready_button.theme_type_variation = "PrimaryButton"
	ready_button.custom_minimum_size.x = 140
	ready_button.pressed.connect(
		func():
			var ready: bool = not _me().get("ready", false)
			_ready_sent = ready
			source.set_ready(ready)
	)
	buttons.add_child(ready_button)


func _build_game_kind(parent: VBoxContainer) -> void:
	var kind := HBoxContainer.new()
	parent.add_child(kind)
	var group := ButtonGroup.new()
	new_game_button = Button.new()
	new_game_button.text = tr("NEW_GAME_BN")
	load_game_button = Button.new()
	load_game_button.text = tr("LOAD_GAME_BN")
	for button: Button in [new_game_button, load_game_button]:
		button.toggle_mode = true
		button.button_group = group
		button.theme_type_variation = "SegmentButton"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kind.add_child(button)
	new_game_button.pressed.connect(func(): source.send_lobby({"new_game": true}))
	load_game_button.pressed.connect(func(): source.send_lobby({"new_game": false}))

	var save_box := VBoxContainer.new()
	parent.add_child(save_box)
	_save_label = ScreenKit.label("", "SecondaryLabel")
	_save_label.clip_text = true
	save_box.add_child(_save_label)
	save_picker = OptionButton.new()
	save_picker.fit_to_longest_item = false
	# A long save name is cut short, not the lobby widened past the window.
	save_picker.clip_text = true
	save_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	save_picker.item_selected.connect(
		func(i):
			var file: String = save_picker.get_item_metadata(i)
			if not file.is_empty():
				source.send_lobby({"save_game": file})
	)
	save_box.add_child(save_picker)


func _build_galaxy(parent: VBoxContainer) -> void:
	_preview = GalaxyPreview.new()
	_preview.custom_minimum_size = Vector2(300, 140)
	parent.add_child(_preview)
	_room = ScreenKit.label("", "SmallLabel")
	_room.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_room)
	_galaxy_grid = GridContainer.new()
	_galaxy_grid.columns = 2
	_galaxy_grid.add_theme_constant_override("h_separation", FOUi.tokens.space_4)
	parent.add_child(_galaxy_grid)
	seed_edit = LineEdit.new()
	seed_edit.tooltip_text = tr("GSETUP_RANDOM_SEED")
	var send_seed := func(_t := ""):
		var text := seed_edit.text.strip_edges()
		if text != str(_lobby.get("galaxy", {}).get("seed", "")):
			_send_galaxy("seed", text)
	seed_edit.text_submitted.connect(send_seed)
	seed_edit.focus_exited.connect(send_seed)
	_galaxy_row("GSETUP_SEED", seed_edit)
	stars = SpinBox.new()
	stars.min_value = MIN_STARS
	stars.max_value = MAX_STARS
	stars.value_changed.connect(func(v): _send_galaxy("size", int(v)))
	_galaxy_row("GSETUP_STARS", stars)
	for key in GALAXY_CHOICES:
		for field in GalaxySetupScreen.CHOICES:
			if field[0] != GALAXY_CHOICES[key]:
				continue
			var picker := OptionButton.new()
			picker.fit_to_longest_item = false
			var values: Array = (
				field[2] if field[2] is Array else GalaxySetupScreen._levels(field[2])
			)
			for value in values:
				picker.add_item(tr(value[1]))
				picker.set_item_metadata(picker.item_count - 1, value[0])
			picker.item_selected.connect(func(i): _send_galaxy(key, picker.get_item_metadata(i)))
			_choices[key] = picker
			_galaxy_row(field[1], picker)


func _galaxy_row(label_key: String, editor: Control) -> void:
	_galaxy_grid.add_child(ScreenKit.label(tr(label_key), "SecondaryLabel"))
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_galaxy_grid.add_child(editor)
