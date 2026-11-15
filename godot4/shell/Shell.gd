extends Control
## Entry point of the fork's client: title, galaxy setup and options, then
## the game in GameShell. Starts the bridge's networking and content
## parsing, as upstream's IntroScreen did, and honours --quickstart.

var title: TitleScreen
var setup: GalaxySetupScreen
var options: OptionsScreen
var game: GameShell

var _content_ready := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
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

	title.new_game_requested.connect(_show_setup)
	title.quick_start_requested.connect(_start_game)
	title.options_requested.connect(_show_options)
	title.exit_requested.connect(get_tree().quit)
	setup.back_requested.connect(_show_title)
	setup.start_requested.connect(_start_game)
	options.close_requested.connect(_show_title)

	if not is_instance_valid(GlobalFreeOrionNode):
		return
	GlobalFreeOrionNode.parsing_completed.connect(_on_parsing_completed)
	GlobalFreeOrionNode.start_game.connect(_on_start_game)
	GlobalFreeOrionNode.start_network_thread()
	GlobalFreeOrionNode.start_parsing_thread()


func _show_title() -> void:
	setup.visible = false
	options.visible = false
	title.visible = true


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
	for child in [title, setup, options]:
		child.queue_free()
	game = GameShell.new()
	add_child(game)
	game.map_view.refresh()
