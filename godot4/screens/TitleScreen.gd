class_name TitleScreen
extends Control
## Title: seasonal splash and logo, the main menu and the version. Menu
## entries that need game content stay disabled until parsing completes.

## Load the newest save (Continue).
signal continue_requested
signal new_game_requested
signal quick_start_requested
signal multiplayer_requested
signal load_requested
signal options_requested
signal exit_requested
signal credits_requested
signal pedia_requested

const WEBSITE := "https://freeorion.org"

const ART_DIR := "res://assets/art/"

var _menu: VBoxContainer
var _status: Label
var _content_buttons: Array[Button] = []
var _continue: Button
var _new_game: Button


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


## Enable the entries that need parsed content (new game, quick start).
func set_content_ready(ready: bool) -> void:
	for button in _content_buttons:
		button.disabled = not ready
	_status.text = "" if ready else tr("TITLE_LOADING")
	_status.visible = not _status.text.is_empty()


## Offer Continue (loading the newest save) when \a can is true: it then
## leads the menu, else New Game does.
func set_can_continue(can: bool) -> void:
	_continue.visible = can
	_continue.theme_type_variation = "PrimaryButton"
	_new_game.theme_type_variation = "" if can else "PrimaryButton"
	(_continue if can else _new_game).call_deferred("grab_focus")


## Show a status line instead of the menu, e.g. while a game starts.
func set_busy(message: String) -> void:
	_menu.visible = message.is_empty()
	_status.text = message
	_status.visible = not message.is_empty()


## Show the menu with \a message under it, e.g. why a load failed.
func show_notice(message: String) -> void:
	_menu.visible = true
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
	splash.texture = without_bands(_load_art(art[0]))
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

	_continue = _menu_button("INTRO_BTN_CONTINUE", continue_requested, "PrimaryButton")
	_continue.visible = false
	_content_buttons.push_back(_continue)
	var new_game := _menu_button("TITLE_NEW_GAME", new_game_requested, "PrimaryButton")
	_new_game = new_game
	_content_buttons.push_back(new_game)
	_content_buttons.push_back(_menu_button("TITLE_QUICK_START", quick_start_requested))
	_content_buttons.push_back(_menu_button("INTRO_BTN_MULTI_PLAYER", multiplayer_requested))
	_content_buttons.push_back(_menu_button("GAME_MENU_LOAD", load_requested))
	_content_buttons.push_back(_menu_button("MAP_BTN_PEDIA", pedia_requested))
	_menu_button("OPTIONS_TITLE", options_requested)
	_menu_button("TITLE_ABOUT", credits_requested, "GhostButton")
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
	# The project's website, bottom left.
	var website := LinkButton.new()
	website.text = tr("INTRO_BTN_WEBSITE")
	website.uri = WEBSITE
	website.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	website.add_theme_color_override("font_color", FOUi.tokens.text_secondary)
	website.add_theme_font_size_override("font_size", FOUi.tokens.font_size_small)
	website.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	website.grow_vertical = Control.GROW_DIRECTION_BEGIN
	website.position += Vector2(FOUi.tokens.space_4, -FOUi.tokens.space_2)
	add_child(website)
	set_content_ready(false)


func _menu_button(key: String, pressed: Signal, variation := "") -> Button:
	var button := Button.new()
	button.text = tr(key)
	button.theme_type_variation = variation
	button.pressed.connect(func(): pressed.emit())
	_menu.add_child(button)
	return button


## \a texture without the black bands above and below its picture (the
## default splash has them baked in, so they would show even when it
## covers the screen).
static func without_bands(texture: Texture2D) -> Texture2D:
	var image := texture.get_image() if texture else null
	if image == null:
		return texture
	if image.is_compressed():
		image = image.duplicate()
		image.decompress()
	var rows := image.get_height()
	var top := 0
	while top < rows / 3 and _dark_row(image, top):
		top += 1
	var bottom := rows - 1
	while bottom > rows * 2 / 3 and _dark_row(image, bottom):
		bottom -= 1
	if top == 0 and bottom == rows - 1:
		return texture
	var cropped := AtlasTexture.new()
	cropped.atlas = texture
	cropped.region = Rect2(0, top, image.get_width(), bottom - top + 1)
	return cropped


# Whether row \a y of \a image is (nearly) black, from a few samples.
static func _dark_row(image: Image, y: int) -> bool:
	var width := image.get_width()
	for i in 16:
		if image.get_pixel(width * i / 16, y).get_luminance() > 0.05:
			return false
	return true


static func _load_art(file: String) -> Texture2D:
	var path := ART_DIR + file
	return load(path) if ResourceLoader.exists(path) else null
