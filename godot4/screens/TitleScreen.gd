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
## The menu's glass column, and the splash's slow drift behind it.
const MENU_WIDTH := 400
const DRIFT_SCALE := 1.06
const DRIFT_SECONDS := 40.0

var _menu: VBoxContainer
var _status: Label
var _content_buttons: Array[Button] = []
var _continue: Button
var _continue_detail: Label
var _spinner: FOSpinner
var _tip: Label
var _new_game: Button
## What hides while another menu screen shows over the splash.
var _chrome: Array[Control] = []


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
## \a detail names what Continue would load ("Terran Imperium · Turn 15").
func set_can_continue(can: bool, detail := "") -> void:
	_continue.visible = can
	_continue_detail.text = detail
	_continue_detail.visible = can and not detail.is_empty()
	_continue_detail.get_parent().visible = _continue_detail.visible
	_continue.tooltip_text = detail
	_continue.theme_type_variation = "MenuItemPrimary"
	_new_game.theme_type_variation = "MenuItem" if can else "MenuItemPrimary"
	(_continue if can else _new_game).call_deferred("grab_focus")


## Show the menu column (\a shown) or only the splash, as the backdrop of
## the other menu screens (options, setup, saves...).
func set_menu_shown(shown: bool) -> void:
	visible = true
	for control in _chrome:
		control.visible = shown


## Show a status line instead of the menu, e.g. while a game starts.
func set_busy(message: String) -> void:
	var busy := not message.is_empty()
	_menu.visible = not busy
	_status.text = message
	_status.visible = busy
	# Loading: a spinner, and a tip to read meanwhile (a new one each time).
	if busy and not _spinner.visible:
		_tip.text = loading_tip(randi())
	_spinner.visible = busy
	_tip.visible = busy and not _tip.text.is_empty()


## Show the menu with \a message under it, e.g. why a load failed.
func show_notice(message: String) -> void:
	_menu.visible = true
	_spinner.visible = false
	_tip.visible = false
	_status.text = message
	_status.visible = not message.is_empty()


# The splash drifts slowly closer and back (not with reduced motion).
func _drift(splash: Control) -> void:
	if FOUi.reduce_motion:
		return
	# Around its centre, whatever size it gets (not yet known when built).
	splash.resized.connect(func(): splash.pivot_offset = splash.size / 2.0)
	var tween := splash.create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(splash, "scale", Vector2.ONE * DRIFT_SCALE, DRIFT_SECONDS)
	tween.tween_property(splash, "scale", Vector2.ONE, DRIFT_SECONDS)


## Beginner hint \a pick (of BEGINNER_HINT_01...) as plain text for the
## loading screen: links become the names they show, the number goes.
static func loading_tip(pick: int) -> String:
	var keys := []
	for i in range(1, 100):
		var key := "BEGINNER_HINT_%02d" % i
		if TranslationServer.translate(key) == key:
			break
		keys.push_back(key)
	if keys.is_empty():
		return ""
	var text := TranslationServer.translate(keys[posmod(pick, keys.size())])
	var link := RegEx.create_from_string("\\[\\[[a-z_]+ ([A-Za-z0-9_]+)\\]\\]")
	for found in link.search_all(text):
		text = text.replace(found.get_string(), TranslationServer.translate(found.get_string(1)))
	return RegEx.create_from_string("^\\d+:\\s*").sub(text, "")


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
	_drift(splash)

	# A glass column down the left: the logo, then the menu.
	var column := PanelContainer.new()
	column.theme_type_variation = "OverlayPanel"
	column.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	column.custom_minimum_size.x = MENU_WIDTH
	add_child(column)
	_chrome.push_back(column)
	var layout := VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", FOUi.tokens.space_6)
	column.add_child(layout)
	var logo := TextureRect.new()
	logo.texture = _load_art(art[1])
	logo.custom_minimum_size = Vector2(MENU_WIDTH - FOUi.tokens.space_8, 110)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layout.add_child(logo)

	var panel_box := VBoxContainer.new()
	layout.add_child(panel_box)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", FOUi.tokens.space_1)
	panel_box.add_child(_menu)
	_spinner = FOSpinner.new(FOUi.tokens.icon_large)
	_spinner.visible = false
	panel_box.add_child(_spinner)
	_status = ScreenKit.label("", "SecondaryLabel")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_box.add_child(_status)
	_tip = ScreenKit.label("", "SmallLabel")
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.visible = false
	panel_box.add_child(_tip)

	_continue = _menu_button("INTRO_BTN_CONTINUE", continue_requested, "MenuItemPrimary")
	_continue.visible = false
	# Which game Continue goes back to.
	_continue_detail = ScreenKit.label("", "SmallLabel")
	_continue_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_continue_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_continue_detail.visible = false
	# Lined up with the menu items' text.
	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", FOUi.tokens.space_4)
	indent.add_child(_continue_detail)
	indent.visible = false
	_menu.add_child(indent)
	_content_buttons.push_back(_continue)
	var new_game := _menu_button("TITLE_NEW_GAME", new_game_requested, "MenuItemPrimary")
	_new_game = new_game
	_content_buttons.push_back(new_game)
	_content_buttons.push_back(_menu_button("TITLE_QUICK_START", quick_start_requested))
	_content_buttons.push_back(_menu_button("INTRO_BTN_MULTI_PLAYER", multiplayer_requested))
	_content_buttons.push_back(_menu_button("GAME_MENU_LOAD", load_requested))
	_content_buttons.push_back(_menu_button("MAP_BTN_PEDIA", pedia_requested))
	_menu_button("OPTIONS_TITLE", options_requested)
	_menu_button("TITLE_ABOUT", credits_requested)
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
	_chrome.push_back(version)
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
	_chrome.push_back(website)
	set_content_ready(false)


func _menu_button(key: String, pressed: Signal, variation := "MenuItem") -> Button:
	var button := Button.new()
	button.text = tr(key)
	button.theme_type_variation = variation
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
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
