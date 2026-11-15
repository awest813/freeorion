class_name ConnectScreen
extends PanelContainer
## Multiplayer, before the lobby: the player's name, then host a game (on a
## server started here) or join one at an address, as a player, observer or
## moderator. Servers on the local network can be looked up. As the GG
## client's server connect window; the name and address are remembered in
## the setup.multiplayer.* options.

signal back_requested
signal host_requested(player_name: String)
signal join_requested(address: String, player_name: String, client_type: String)
## The local network search finished (its results are listed).
signal lan_search_done

const OPTION_NAME := "setup.multiplayer.player.name"
const OPTION_ADDRESS := "setup.multiplayer.host.address"
## Ways to join: client type, label key.
const JOIN_AS := [
	["player", "HUMAN_PLAYER"],
	["observer", "OBSERVER"],
	["moderator", "MODERATOR"],
]

var options: Variant = OptionsSource.new()
var lobby_source: Variant = LobbySource.new()
var name_edit: LineEdit
var address_edit: LineEdit
var join_as: OptionButton
var lan_list: ItemList
var host_button: Button
var join_button: Button

var _status: Label
var _refresh_button: Button
# The local network search running in the background (it waits about two
# seconds for answers).
var _search: Thread


func _init() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "BackgroundPanel"
	_build()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()


## Fill in the remembered name and address.
func refresh() -> void:
	name_edit.text = _option(OPTION_NAME, "")
	address_edit.text = _option(OPTION_ADDRESS, "localhost")
	set_status("")
	_update_buttons()


## A line under the buttons: why connecting failed, or what is going on.
func set_status(text: String) -> void:
	_status.text = text
	_status.visible = not text.is_empty()


func status_text() -> String:
	return _status.text


## Look for servers on the local network and list them.
## The search runs in the background; joining waits until it is done (both
## use the client's network connection).
func find_lan_servers() -> void:
	if _search:
		return
	lan_list.clear()
	set_status(tr("MP_SEARCHING_LAN"))
	_search = Thread.new()
	_search.start(lobby_source.discover_lan_servers)
	_update_buttons()
	while _search.is_alive() and is_inside_tree():
		await get_tree().process_frame
	if _search == null:  # The screen was closed meanwhile.
		return
	var found: PackedStringArray = _search.wait_to_finish()
	_search = null
	_update_buttons()
	for server in found:
		lan_list.add_item(server)
	set_status("" if not found.is_empty() else tr("MP_NO_LAN_SERVERS"))
	lan_search_done.emit()


func _exit_tree() -> void:
	if _search:
		_search.wait_to_finish()
		_search = null


func player_name() -> String:
	return name_edit.text.strip_edges()


func _build() -> void:
	var center := CenterContainer.new()
	add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = "OverlayPanel"
	card.custom_minimum_size.x = 560
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FOUi.tokens.space_4)
	card.add_child(box)
	ScreenKit.header(box, "SCONNECT_WINDOW_TITLE", back_requested.emit)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", FOUi.tokens.space_4)
	box.add_child(grid)
	grid.add_child(ScreenKit.label(tr("PLAYER_NAME_LABEL"), "SecondaryLabel"))
	name_edit = LineEdit.new()
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.max_length = 64
	name_edit.text_changed.connect(func(_t): _update_buttons())
	grid.add_child(name_edit)
	grid.add_child(ScreenKit.label(tr("MP_SERVER_ADDRESS"), "SecondaryLabel"))
	address_edit = LineEdit.new()
	address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_edit.text_changed.connect(func(_t): _update_buttons())
	address_edit.text_submitted.connect(func(_t): _on_join())
	grid.add_child(address_edit)

	var lan_row := HBoxContainer.new()
	box.add_child(lan_row)
	var lan_label := ScreenKit.label(tr("LAN_GAME_LABEL"), "SecondaryLabel")
	lan_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lan_row.add_child(lan_label)
	_refresh_button = Button.new()
	_refresh_button.text = tr("REFRESH_LIST_BN")
	_refresh_button.theme_type_variation = "GhostButton"
	_refresh_button.pressed.connect(find_lan_servers)
	lan_row.add_child(_refresh_button)
	lan_list = ItemList.new()
	lan_list.custom_minimum_size.y = 96
	lan_list.item_selected.connect(func(i): address_edit.text = lan_list.get_item_text(i))
	lan_list.item_activated.connect(
		func(i):
			address_edit.text = lan_list.get_item_text(i)
			_on_join()
	)
	box.add_child(lan_list)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", FOUi.tokens.space_3)
	box.add_child(buttons)
	host_button = Button.new()
	host_button.text = tr("HOST_GAME_BN")
	host_button.tooltip_text = tr("MP_HOST_TIP")
	host_button.pressed.connect(_on_host)
	buttons.add_child(host_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	join_button = Button.new()
	join_button.text = tr("JOIN_GAME_BN")
	join_button.theme_type_variation = "PrimaryButton"
	join_button.pressed.connect(_on_join)
	buttons.add_child(join_button)
	join_as = OptionButton.new()
	for entry in JOIN_AS:
		join_as.add_item(tr(entry[1]))
		join_as.set_item_metadata(join_as.item_count - 1, entry[0])
	buttons.add_child(join_as)

	_status = ScreenKit.label("", "SecondaryLabel")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	box.add_child(_status)


func _update_buttons() -> void:
	var searching := _search != null
	_refresh_button.disabled = searching
	host_button.disabled = player_name().is_empty() or searching
	join_button.disabled = (
		player_name().is_empty() or address_edit.text.strip_edges().is_empty() or searching
	)


func _remember() -> void:
	if options.exists(OPTION_NAME):
		options.set_value(OPTION_NAME, player_name())
	if options.exists(OPTION_ADDRESS):
		options.set_value(OPTION_ADDRESS, address_edit.text.strip_edges())
	options.commit()


func _on_host() -> void:
	if host_button.disabled:
		return
	_remember()
	set_status(tr("MP_STARTING_SERVER"))
	host_requested.emit(player_name())


func _on_join() -> void:
	if join_button.disabled:
		return
	_remember()
	set_status(tr("MP_CONNECTING").replace("%1%", address_edit.text.strip_edges()))
	join_requested.emit(
		address_edit.text.strip_edges(), player_name(), join_as.get_item_metadata(join_as.selected)
	)


func _option(option: String, fallback: String) -> String:
	return str(options.get_value(option)) if options.exists(option) else fallback
