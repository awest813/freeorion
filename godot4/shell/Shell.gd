extends Control
## Entry point of the fork's client: title, galaxy setup and options, then
## the game in GameShell, and back to the title when the player leaves it.
## Starts the bridge's networking and content parsing, as upstream's
## IntroScreen did, and honours --quickstart.

## Add the designs saved between games to a new game.
const OPTION_SAVED_DESIGNS := "resource.shipdesign.saved.enabled"
const OPTION_DEFAULT_DESIGNS := "resource.shipdesign.default.enabled"
## Time for the audio server to free stopped sounds before quitting.
const AUDIO_STOP_SECONDS := 0.1

var title: TitleScreen
var setup: GalaxySetupScreen
var options: OptionsScreen
var saves: SaveLoadScreen
var credits: CreditsScreen
var pedia: PediaScreen
var connect_screen: ConnectScreen
var lobby: LobbyScreen
var game: GameShell
## The multiplayer session (hosting, joining, the lobby); tests replace it.
var lobby_source: Variant = LobbySource.new()

var _content_ready := false
## While leaving a game: [action, save path] to do once the server is gone.
var _leaving: Array = []
## Why the game ended, shown on the title once it's back.
var _notice := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_build_menus()
	var audio := get_node_or_null("/root/FOAudio")
	if audio:
		audio.set_audible(DisplayServer.get_name() != "headless")
	if not is_instance_valid(GlobalFreeOrionNode):
		return
	FOWindow.restore(Engine.get_singleton("FOOptions"))
	# Closing the window in game shuts the server down first, as Exit does.
	get_tree().auto_accept_quit = false
	GlobalFreeOrionNode.parsing_completed.connect(_on_parsing_completed)
	GlobalFreeOrionNode.start_game.connect(_on_start_game)
	GlobalFreeOrionNode.game_ended.connect(_on_game_ended)
	GlobalFreeOrionNode.game_aborted.connect(_on_game_aborted)
	GlobalFreeOrionNode.server_error.connect(_on_server_error)
	GlobalFreeOrionNode.turn_progress.connect(_on_turn_progress)
	GlobalFreeOrionNode.mp_joined.connect(_on_mp_joined)
	GlobalFreeOrionNode.lobby_changed.connect(_on_lobby_changed)
	# The lobby is rebuilt after each game: reach the current one.
	GlobalFreeOrionNode.server_saves.connect(func(): lobby.saves_changed())
	GlobalFreeOrionNode.returned_to_lobby.connect(_on_returned_to_lobby)
	# --auto-quit: the auto-advanced turns are done and saved.
	GlobalFreeOrionNode.auto_quit.connect(_on_auto_quit)
	GlobalFreeOrionNode.chat_received.connect(_on_chat_received)
	GlobalFreeOrionNode.auth_requested.connect(_on_auth_requested)
	GlobalFreeOrionNode.mp_disconnected.connect(_on_mp_disconnected)
	GlobalFreeOrionNode.start_network_thread()
	GlobalFreeOrionNode.start_parsing_thread()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if game and _leaving.is_empty():
		# Ask first, as the in-game menu does; closing again while asked
		# leaves.
		if game.game_menu.visible and game.game_menu.pending_leave == "exit":
			leave_game("exit")
			return
		game.open_menu()
		game.game_menu.request_leave("exit")
	elif _leaving.is_empty() or _leaving[0] != "exit":
		quit()


## Quit the application once the sounds have stopped: the audio server
## frees them on a later mix, else they leak at exit.
func quit() -> void:
	if Engine.has_singleton("FOOptions"):
		FOWindow.remember(Engine.get_singleton("FOOptions"))
	var audio := get_node_or_null("/root/FOAudio")
	if audio:
		audio.stop_all()
		await get_tree().create_timer(AUDIO_STOP_SECONDS).timeout
	get_tree().quit()


func _on_auto_quit() -> void:
	if game:
		leave_game("exit")
	else:
		quit()


## End the running game, then \a action: "title", "exit", or "load" the
## save at \a path. The server shuts down over a few frames meanwhile.
func leave_game(action: String, path := "") -> void:
	if not game:
		return
	_leaving = [action, path]
	game.queue_free()
	game = null
	_build_menus()
	title.set_content_ready(_content_ready)
	_offer_continue()
	title.set_busy(tr("MENU_LEAVING"))
	GlobalFreeOrionNode.quit_game()


func _build_menus() -> void:
	title = TitleScreen.new()
	add_child(title)
	setup = GalaxySetupScreen.new()
	setup.visible = false
	setup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(setup)
	options = OptionsScreen.new()
	options.visible = false
	options.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(options)
	saves = SaveLoadScreen.new()
	saves.mode = "load"
	saves.visible = false
	saves.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(saves)
	credits = CreditsScreen.new()
	credits.visible = false
	credits.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(credits)
	credits.close_requested.connect(_show_title)
	title.credits_requested.connect(_show_credits)
	connect_screen = ConnectScreen.new()
	connect_screen.lobby_source = lobby_source
	connect_screen.visible = false
	connect_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(connect_screen)
	lobby = LobbyScreen.new()
	lobby.source = lobby_source
	lobby.visible = false
	lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(lobby)
	title.multiplayer_requested.connect(_show_connect)
	connect_screen.back_requested.connect(_show_title)
	connect_screen.host_requested.connect(host_game)
	connect_screen.join_requested.connect(join_game)
	lobby.leave_requested.connect(leave_lobby)

	title.new_game_requested.connect(_show_setup)
	title.quick_start_requested.connect(_start_game)
	title.options_requested.connect(_show_options)
	title.load_requested.connect(_show_saves)
	saves.close_requested.connect(_show_title)
	saves.load_started.connect(_on_load_started)
	title.exit_requested.connect(quit)
	title.continue_requested.connect(continue_game)
	title.pedia_requested.connect(_show_pedia)
	pedia = PediaScreen.new()
	pedia.visible = false
	pedia.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pedia)
	pedia.close_requested.connect(_show_title)
	setup.back_requested.connect(_show_title)
	setup.start_requested.connect(_start_game)
	options.close_requested.connect(_show_title)


func _show_title() -> void:
	setup.visible = false
	options.visible = false
	saves.visible = false
	credits.visible = false
	connect_screen.visible = false
	lobby.visible = false
	pedia.visible = false
	title.visible = true


# Continue, when there is a save to go back to, naming it.
func _offer_continue() -> void:
	var newest: Array = saves.source.list_saves() if _content_ready else []
	if newest.is_empty():
		title.set_can_continue(false)
		return
	var save: Dictionary = newest[0]
	title.set_can_continue(
		true,
		(
			"%s  ·  %s"
			% [
				save.get("empire", ""),
				tr("MAP_BTN_TURN_UPDATE").replace("%1%", str(save.get("turn", 0)))
			]
		)
	)


## Load the newest save, as the GG client's Continue.
func continue_game() -> void:
	var newest: Array = saves.source.list_saves()
	if newest.is_empty() or not _content_ready:
		return
	if saves.source.load_game(newest[0]["path"]):
		_on_load_started(newest[0]["path"])
	else:
		title.show_notice(tr("SAVES_LOAD_FAILED"))


func _show_pedia() -> void:
	title.visible = false
	pedia.visible = true
	FOUi.fade_in(pedia)


# Alt+Enter (hotkey "fullscreen") toggles fullscreen, in the menus and in game.
func _unhandled_key_input(event: InputEvent) -> void:
	if FOHotkeys.match_event(event) == "fullscreen" and Engine.has_singleton("FOOptions"):
		FOWindow.toggle_fullscreen(Engine.get_singleton("FOOptions"))
		get_viewport().set_input_as_handled()


func _show_credits() -> void:
	credits.refresh()
	title.visible = false
	credits.visible = true
	FOUi.fade_in(credits)


func _show_saves() -> void:
	saves.refresh()
	title.visible = false
	saves.visible = true
	FOUi.fade_in(saves)


func _on_load_started(_path: String) -> void:
	_show_title()
	title.set_busy(tr("TITLE_LOADING_GAME"))


func _show_setup() -> void:
	setup.refresh()
	title.visible = false
	setup.visible = true
	FOUi.fade_in(setup)


func _show_options() -> void:
	options.refresh()
	title.visible = false
	options.visible = true
	FOUi.fade_in(options)


func _start_game() -> void:
	if not _content_ready:
		return
	_show_title()
	title.set_busy(tr("TITLE_STARTING"))
	# The server didn't start or answer: say so, as the GG client does.
	var error: String = GlobalFreeOrionNode.new_single_player_game()
	if not error.is_empty():
		title.show_notice(error)


func _on_parsing_completed() -> void:
	_content_ready = true
	title.set_content_ready(true)
	_offer_continue()
	_start_from_command_line()


# What the command line asks for once content is ready, as the GG client:
# --quickstart (-q), --continue (the newest save), --load FILE,
# --auto-connect (-A: join the multiplayer server remembered).
func _start_from_command_line() -> void:
	if GlobalFreeOrionNode.options_get_bool("quickstart"):
		_start_game()
	elif _flag("continue"):
		continue_game()
	elif not str(GlobalFreeOrionNode.options_get_string("load")).is_empty():
		var path: String = GlobalFreeOrionNode.options_get_string("load")
		if saves.source.load_game(path):
			_on_load_started(path)
		else:
			title.show_notice(tr("SAVES_LOAD_FAILED"))
	elif _flag("auto-connect"):
		_show_connect()
		connect_screen._on_join()


func _flag(option: String) -> bool:
	return (
		GlobalFreeOrionNode.options_exists(option) and GlobalFreeOrionNode.options_get_bool(option)
	)


# The game began: replace the menus with the game shell.
func _on_start_game(is_new_game: bool) -> void:
	if game:
		return
	# A new game starts with the designs kept from earlier ones, as in the
	# GG client (option resource.shipdesign.saved.enabled).
	# Without the premade designs (resource.shipdesign.default.enabled off)
	# the empire forgets those the server gave it, as GG does.
	var option_db := Engine.get_singleton("FOOptions")
	if is_new_game and option_db.exists(OPTION_DEFAULT_DESIGNS):
		if not option_db.get_value(OPTION_DEFAULT_DESIGNS):
			for design: Dictionary in FODesigner.get_designs("empire"):
				FODesigner.delete_design(design["id"])
	if is_new_game and option_db.exists(OPTION_SAVED_DESIGNS):
		if option_db.get_value(OPTION_SAVED_DESIGNS):
			FODesigner.add_all_saved()
	for child in [title, setup, options, saves, credits, connect_screen, lobby, pedia]:
		child.queue_free()
	game = GameShell.new()
	game.leave_requested.connect(leave_game)
	add_child(game)
	game.map_view.refresh()
	game.restore_view()


# The server is gone after leave_game(): do what the player asked for.
func _on_game_ended() -> void:
	var action: String = _leaving[0] if not _leaving.is_empty() else "title"
	var path: String = _leaving[1] if not _leaving.is_empty() else ""
	_leaving = []
	match action:
		"exit":
			quit()
		"load":
			if saves.source.load_game(path):
				title.set_busy(tr("TITLE_LOADING_GAME"))
			else:
				title.set_busy("")
				title.show_notice(tr("SAVES_LOAD_FAILED"))
		_:
			title.set_busy("")
	if not _notice.is_empty():
		FODialog.open_on(self, tr("GAME_ABORTED_TITLE"), _notice, [[tr("OK"), "PrimaryButton"]])
		_notice = ""


# While a game is generated or loaded, the title says what the server does.
func _on_turn_progress(_phase: String, text: String) -> void:
	if game:
		return
	# A multiplayer game starting: the lobby says what the server is doing.
	if is_instance_valid(lobby) and lobby.visible:
		lobby.set_progress(text)
	elif is_instance_valid(title) and not title._menu.visible:
		title.set_busy(text)


# The server ended the game or went away: back to the title, saying why.
func _on_game_aborted(message: String) -> void:
	_notice = message
	if game:
		leave_game("title")
	else:
		# Lost before the game began (the server died while starting).
		_show_title()
		title.show_notice(message)


# Errors from the server. In game, GameShell shows them; before the game
# starts (e.g. a failed load), the title does, and a fatal one shuts the
# server down.
func _on_server_error(message: String, fatal: bool) -> void:
	if game:
		return
	if connect_screen.visible or lobby.visible:
		_show_connect()
		connect_screen.set_status(message)
		if fatal:
			lobby_source.leave()
		return
	if fatal:
		_notice = message
		title.set_busy(tr("MENU_LEAVING"))
		GlobalFreeOrionNode.quit_game()
	else:
		title.set_busy("")
		title.show_notice(message)


# Multiplayer -----------------------------------------------------------


func _show_connect() -> void:
	if not _content_ready:
		return
	connect_screen.refresh()
	title.visible = false
	lobby.visible = false
	connect_screen.visible = true
	FOUi.fade_in(connect_screen)


## Host a multiplayer game on a server started here; the lobby opens once
## the server answers (mp_joined).
func host_game(player_name: String) -> void:
	var error: String = lobby_source.host_game(player_name)
	if not error.is_empty():
		connect_screen.set_status(tr(error))


## Join the multiplayer game at \a address.
func join_game(address: String, player_name: String, client_type: String) -> void:
	var error: String = lobby_source.join_game(address, player_name, client_type)
	if not error.is_empty():
		connect_screen.set_status(tr(error))


## Leave the lobby (and the server), back to the connect screen.
func leave_lobby() -> void:
	lobby_source.leave()
	_show_connect()


func _on_mp_joined(_player_id: int) -> void:
	if game:
		return
	connect_screen.visible = false
	title.visible = false
	lobby.visible = true
	lobby_source.request_saves()
	lobby.refresh()
	lobby.refresh_chat()
	FOUi.fade_in(lobby)


# The server went back to its lobby (a dedicated server's host left): leave
# the game for the lobby, still connected, as the GG client does.
func _on_returned_to_lobby() -> void:
	if not game:
		return
	game.queue_free()
	game = null
	_build_menus()
	title.set_content_ready(_content_ready)
	_on_mp_joined(FOMultiplayer.get_player_id())


func _on_lobby_changed() -> void:
	if not game and lobby.visible:
		lobby.refresh()


func _on_chat_received() -> void:
	if game:
		game.chat_window.refresh()
	elif lobby.visible:
		lobby.refresh_chat()


# The server wants a password for the player's name.
func _on_auth_requested(player_name: String) -> void:
	var password := LineEdit.new()
	password.secret = true
	password.placeholder_text = tr("PASSWORD_LABEL")
	var dialog := FODialog.open_on(
		self,
		tr("AUTHENTICATION_WINDOW_TITLE"),
		"%s\n\n%s" % [player_name, tr("AUTHENTICATION_DESC")],
		[
			[tr("OK"), "PrimaryButton", func(): lobby_source.send_password(password.text)],
			[tr("CANCEL"), "GhostButton", leave_lobby],
		]
	)
	dialog.add_content(password)
	password.text_submitted.connect(func(_t): dialog.choose(0))
	password.call_deferred("grab_focus")


# The server went away before the game started.
func _on_mp_disconnected(message: String) -> void:
	if game or not (lobby.visible or connect_screen.visible):
		return
	_show_connect()
	connect_screen.set_status(message)
