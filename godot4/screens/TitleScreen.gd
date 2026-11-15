class_name TitleScreen
extends Control
## Title: seasonal splash and logo, the main menu and the version. Menu
## entries that need game content stay disabled until parsing completes.

signal new_game_requested
signal quick_start_requested
signal load_requested
signal options_requested
signal exit_requested

const ART_DIR := "res://assets/art/"

var _menu: VBoxContainer
var _status: Label
var _content_buttons: Array[Button] = []


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


## Enable the entries that need parsed content (new game, quick start).
func set_content_ready(ready: bool) -> void:
	for button in _content_buttons:
		button.disabled = not ready
	_status.text = "" if ready else tr("TITLE_LOADING")
	_status.visible = not _status.text.is_empty()


## Show a status line instead of the menu, e.g. while a game starts.
func set_busy(message: String) -> void:
	_menu.visible = message.is_empty()
	_status.text = message
	_status.visible = not message.is_empty()


## Splash and logo file names for \a date (a Time date dictionary): April
## Fools, Christmas and Halloween get their own art, like the GG client.
static func seasonal_art(date: Dictionary) -> Array:
	match [date.get("month"), date.get("day")]:
		[4, 1]:
			return ["splash0104.png", "logo0104.png"]
		[12, 25]:
			return ["splash2512.png", "logo2512.png"]
		[10, 31]:
			return ["splash3110.png", "logo3110.png"]
	return ["splash.png", "logo.png"]


func _build() -> void:
	var art := seasonal_art(Time.get_date_dict_from_system())
	var splash := TextureRect.new()
	splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	splash.texture = _load_art(art[0])
	splash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	splash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(splash)

	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", FOUi.tokens.space_8)
	add_child(layout)
	var logo := TextureRect.new()
	logo.texture = _load_art(art[1])
	logo.custom_minimum_size = Vector2(640, 160)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	layout.add_child(logo)

	var panel := PanelContainer.new()
	panel.theme_type_variation = "OverlayPanel"
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.custom_minimum_size.x = 320
	layout.add_child(panel)
	var panel_box := VBoxContainer.new()
	panel.add_child(panel_box)
	_menu = VBoxContainer.new()
	panel_box.add_child(_menu)
	_status = ScreenKit.label("", "SecondaryLabel")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel_box.add_child(_status)

	var new_game := _menu_button("TITLE_NEW_GAME", new_game_requested, "PrimaryButton")
	_content_buttons.push_back(new_game)
	_content_buttons.push_back(_menu_button("TITLE_QUICK_START", quick_start_requested))
	_content_buttons.push_back(_menu_button("GAME_MENU_LOAD", load_requested))
	_menu_button("OPTIONS_TITLE", options_requested)
	_menu_button("TITLE_EXIT", exit_requested)
	new_game.call_deferred("grab_focus")

	var version := ScreenKit.label("", "SmallLabel")
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.position -= Vector2(FOUi.tokens.space_4, FOUi.tokens.space_2)
	if is_instance_valid(GlobalFreeOrionNode):
		version.text = GlobalFreeOrionNode.get_version()
	add_child(version)
	set_content_ready(false)


func _menu_button(key: String, pressed: Signal, variation := "") -> Button:
	var button := Button.new()
	button.text = tr(key)
	button.theme_type_variation = variation
	button.pressed.connect(func(): pressed.emit())
	_menu.add_child(button)
	return button


static func _load_art(file: String) -> Texture2D:
	var path := ART_DIR + file
	return load(path) if ResourceLoader.exists(path) else null
