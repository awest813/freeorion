extends Node
## Autoload "FOUi": owns the design tokens, the generated theme and the UI scale.
##
## The theme is set on the root Window, so every Control without its own
## overrides uses it. The scale is re-applied after each scene change, because
## upstream's IntroScreen sets its own fixed DPI steps in _ready().

signal theme_changed
signal scale_changed(scale: float)

const OPTION_SCALE := "ui.scale"
const OPTION_THEME := "ui.theme"
const OPTION_REDUCE_MOTION := "ui.reduce-motion"
## The accent follows the player's empire colour in a game.
const OPTION_EMPIRE_ACCENT := "ui.accent.empire"
## See-through glass panels (off: opaque, as in high contrast).
const OPTION_GLASS := "ui.glass"
## Panels that get the glass shader (see glass_panel.gdshader).
const GLASS_PANELS := ["OverlayPanel", "TopBarPanel", "BackgroundPanel"]
const GLASS_SHADER := preload("res://ui/theme/glass_panel.gdshader")
const THEMES := {
	"default": "res://ui/tokens/default.tres",
	"high_contrast": "res://ui/tokens/high_contrast.tres",
}

var tokens: FOTokens
var theme: Theme
var scale := 1.0
## Skip UI animations (option ui.reduce-motion); tests set it for stable shots.
var reduce_motion := false
## Shared by every glass panel; its "enabled" follows the tokens.
var glass_material := ShaderMaterial.new()
## Accent from the empire colour while in a game (transparent: none).
var empire_accent := Color(0, 0, 0, 0)
var _empire_accent_enabled := true
var _glass_enabled := true

var _scale_setting := "auto"
var _theme_name := "default"


func _ready() -> void:
	glass_material.shader = GLASS_SHADER
	_read_options()
	apply_theme(_theme_name)
	get_tree().node_added.connect(_on_node_added)
	get_window().size_changed.connect(_apply_scale)
	_apply_scale()


## Fade \a item in over the short motion duration, unless motion is reduced.
func fade_in(item: CanvasItem) -> void:
	if reduce_motion or not item.is_inside_tree():
		item.modulate.a = 1.0
		return
	item.modulate.a = 0.0
	item.create_tween().tween_property(item, "modulate:a", 1.0, tokens.motion_fast)


## Accent the UI in \a color (the player's empire colour, made readable), or
## the token set's own accent again for a transparent colour.
func set_empire_accent(color: Color) -> void:
	if color == empire_accent:
		return
	empire_accent = color
	apply_theme(_theme_name)


## Switch token set ("default", "high_contrast") and rebuild the theme.
func apply_theme(theme_name: String) -> void:
	if not THEMES.has(theme_name):
		push_warning("Unknown UI theme '%s', using default" % theme_name)
		theme_name = "default"
	_theme_name = theme_name
	# A copy: the empire accent changes it, the file stays as it is.
	tokens = (load(THEMES[theme_name]) as FOTokens).duplicate()
	tokens.glass_enabled = tokens.glass_enabled and _glass_enabled
	if empire_accent.a > 0.0 and _empire_accent_enabled and tokens.glass_enabled:
		FOThemeBuilder.accent_from(tokens, empire_accent)
	theme = FOThemeBuilder.build(tokens)
	glass_material.set_shader_parameter("enabled", tokens.glass_enabled)
	glass_material.set_shader_parameter("blur_px", tokens.glass_blur_px)
	get_window().theme = theme
	theme_changed.emit()


## Set the ui.scale option value ("auto" or a factor such as "1.25") and apply it.
func set_scale_setting(value: String) -> void:
	_scale_setting = value
	if _options_available():
		Engine.get_singleton("FOOptions").set_value(OPTION_SCALE, value)
	_apply_scale()


func get_scale_setting() -> String:
	return _scale_setting


func _apply_scale() -> void:
	var window := get_window()
	var screen := window.current_screen
	var new_scale := FOUiScale.resolve(
		_scale_setting,
		DisplayServer.screen_get_scale(screen),
		DisplayServer.screen_get_dpi(screen),
		window.size
	)
	window.content_scale_factor = new_scale
	if not is_equal_approx(new_scale, scale):
		scale = new_scale
		scale_changed.emit(scale)


func _on_node_added(node: Node) -> void:
	if node is PanelContainer:
		_glaze.call_deferred(node)
	elif node is Button and not node is OptionButton:
		adopt_glyph.call_deferred(node)
	# A new current scene: let its _ready() run, then restore our scale and
	# add fork features to upstream scenes.
	if node.get_parent() == get_tree().root:
		_apply_scale.call_deferred()
		_adapt_scene.call_deferred(node)


## Give \a button the interface icon for its text, if that is one of
## FOIcons.GLYPHS (the glyph moves to its "glyph" meta).
func adopt_glyph(button: Button) -> void:
	if not is_instance_valid(button) or button.icon != null:
		return
	var texture := FOIcons.for_glyph(
		button.text, tokens.icon_small + tokens.space_1 if tokens else 20
	)
	if texture == null:
		return
	button.set_meta("glyph", button.text)
	button.text = ""
	button.icon = texture
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER


# Glass for \a panel if it is one of GLASS_PANELS (its variation may be set
# in its _ready, hence deferred).
func _glaze(panel: PanelContainer) -> void:
	if (
		is_instance_valid(panel)
		and panel.material == null
		and GLASS_PANELS.has(panel.theme_type_variation)
	):
		panel.material = glass_material


func _adapt_scene(scene: Node) -> void:
	if is_instance_valid(scene) and scene.is_inside_tree():
		UpstreamAdapters.adapt(scene)


func _read_options() -> void:
	if not _options_available():
		return
	var options := Engine.get_singleton("FOOptions")
	options.add_option(OPTION_SCALE, "OPTIONS_DB_UI_SCALE", "auto")
	options.add_option(OPTION_THEME, "OPTIONS_DB_UI_THEME", "default")
	options.add_option(OPTION_REDUCE_MOTION, "OPTIONS_DB_UI_REDUCE_MOTION", false)
	options.add_option(OPTION_EMPIRE_ACCENT, "OPTIONS_DB_UI_ACCENT_EMPIRE", true)
	_empire_accent_enabled = options.get_value(OPTION_EMPIRE_ACCENT)
	options.add_option(OPTION_GLASS, "OPTIONS_DB_UI_GLASS", true)
	_glass_enabled = options.get_value(OPTION_GLASS)
	reduce_motion = options.get_value(OPTION_REDUCE_MOTION)
	_scale_setting = options.get_value(OPTION_SCALE)
	_theme_name = options.get_value(OPTION_THEME)
	# React live when the options screen (or anything else) changes them.
	options.watch(OPTION_SCALE)
	options.watch(OPTION_THEME)
	options.watch(OPTION_REDUCE_MOTION)
	options.watch(OPTION_EMPIRE_ACCENT)
	options.watch(OPTION_GLASS)
	options.option_changed.connect(_on_option_changed)


func _on_option_changed(option_name: String) -> void:
	var options := Engine.get_singleton("FOOptions")
	match option_name:
		OPTION_SCALE:
			_scale_setting = options.get_value(OPTION_SCALE)
			_apply_scale()
		OPTION_REDUCE_MOTION:
			reduce_motion = options.get_value(OPTION_REDUCE_MOTION)
		OPTION_EMPIRE_ACCENT:
			_empire_accent_enabled = options.get_value(OPTION_EMPIRE_ACCENT)
			apply_theme(_theme_name)
		OPTION_GLASS:
			_glass_enabled = options.get_value(OPTION_GLASS)
			apply_theme(_theme_name)
		OPTION_THEME:
			var theme_name: String = options.get_value(OPTION_THEME)
			if theme_name != _theme_name:
				apply_theme(theme_name)


func _options_available() -> bool:
	return Engine.has_singleton("FOOptions") and not Engine.is_editor_hint()
