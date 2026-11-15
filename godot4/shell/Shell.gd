extends Control
## Entry point of the fork's client: title, galaxy setup and options, then
## the game in GameShell, and back to the title when the player leaves it.
## Starts the bridge's networking and content parsing, as upstream's
## IntroScreen did, and honours --quickstart.

## Time for the audio server to free stopped sounds before quitting.
const AUDIO_STOP_SECONDS := 0.1

var title: TitleScreen
var setup: GalaxySetupScreen
var options: OptionsScreen
var saves: SaveLoadScreen
var credits: CreditsScreen
var game: GameShell

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
	# Closing the window in game shuts the server down first, as Exit does.
	get_tree().auto_accept_quit = false
	GlobalFreeOrionNode.parsing_completed.connect(_on_parsing_completed)
	GlobalFreeOrionNode.start_game.connect(_on_start_game)
	GlobalFreeOrionNode.game_ended.connect(_on_game_ended)
	GlobalFreeOrionNode.game_aborted.connect(_on_game_aborted)
	GlobalFreeOrionNode.server_error.connect(_on_server_error)
	GlobalFreeOrionNode.turn_progress.connect(_on_turn_progress)
	GlobalFreeOrionNode.start_network_thread()
	GlobalFreeOrionNode.start_parsing_thread()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if game and _leaving.is_empty():
		leave_game("exit")
	elif _leaving.is_empty() or _leaving[0] != "exit":
		quit()


## Quit the application once the sounds have stopped: the audio server
## frees them on a later mix, else they leak at exit.
func quit() -> void:
	var audio := get_node_or_null("/root/FOAudio")
	if audio:
		audio.stop_all()
		await get_tree().create_timer(AUDIO_STOP_SECONDS).timeout
	get_tree().quit()


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

	title.new_game_requested.connect(_show_setup)
	title.quick_start_requested.connect(_start_game)
	title.options_requested.connect(_show_options)
	title.load_requested.connect(_show_saves)
	saves.close_requested.connect(_show_title)
	saves.load_started.connect(_on_load_started)
	title.exit_requested.connect(get_tree().quit)
	setup.back_requested.connect(_show_title)
	setup.start_requested.connect(_start_game)
	options.close_requested.connect(_show_title)


func _show_title() -> void:
	setup.visible = false
	options.visible = false
	saves.visible = false
	credits.visible = false
	title.visible = true


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
	GlobalFreeOrionNode.new_single_player_game()


func _on_parsing_completed() -> void:
	_content_ready = true
	title.set_content_ready(true)
	if GlobalFreeOrionNode.options_get_bool("quickstart"):
		_start_game()


# The game began: replace the menus with the game shell.
func _on_start_game(_is_new_game: bool) -> void:
	if game:
		return
	for child in [title, setup, options, saves, credits]:
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
	if not game and is_instance_valid(title) and not title._menu.visible:
		title.set_busy(text)


# The server ended the game or went away: back to the title, saying why.
func _on_game_aborted(message: String) -> void:
	_notice = message
	if game:
		leave_game("title")


# Errors from the server. In game, GameShell shows them; before the game
# starts (e.g. a failed load), the title does, and a fatal one shuts the
# server down.
func _on_server_error(message: String, fatal: bool) -> void:
	if game:
		return
	if fatal:
		_notice = message
		title.set_busy(tr("MENU_LEAVING"))
		GlobalFreeOrionNode.quit_game()
	else:
		title.set_busy("")
		title.show_notice(message)
