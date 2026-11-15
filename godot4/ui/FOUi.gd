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
const THEMES := {
	"default": "res://ui/tokens/default.tres",
	"high_contrast": "res://ui/tokens/high_contrast.tres",
}

var tokens: FOTokens
var theme: Theme
var scale := 1.0

var _scale_setting := "auto"
var _theme_name := "default"


func _ready() -> void:
	_read_options()
	apply_theme(_theme_name)
	get_tree().node_added.connect(_on_node_added)
	get_window().size_changed.connect(_apply_scale)
	_apply_scale()


## Switch token set ("default", "high_contrast") and rebuild the theme.
func apply_theme(theme_name: String) -> void:
	if not THEMES.has(theme_name):
		push_warning("Unknown UI theme '%s', using default" % theme_name)
		theme_name = "default"
	_theme_name = theme_name
	tokens = load(THEMES[theme_name])
	theme = FOThemeBuilder.build(tokens)
	get_window().theme = theme
	theme_changed.emit()


## Set the ui.scale option value ("auto" or a factor such as "1.25") and apply it.
func set_scale_setting(value: String) -> void:
	_scale_setting = value
	if _options_available():
		GlobalFreeOrionNode.options_set_string(OPTION_SCALE, value)
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
	# A new current scene: let its _ready() run, then restore our scale and
	# add fork features to upstream scenes.
	if node.get_parent() == get_tree().root:
		_apply_scale.call_deferred()
		_adapt_scene.call_deferred(node)


func _adapt_scene(scene: Node) -> void:
	if is_instance_valid(scene) and scene.is_inside_tree():
		UpstreamAdapters.adapt(scene)


func _read_options() -> void:
	if not _options_available():
		return
	if not GlobalFreeOrionNode.options_exists(OPTION_SCALE):
		GlobalFreeOrionNode.options_add_string(OPTION_SCALE, "OPTIONS_DB_UI_SCALE", "auto")
	if not GlobalFreeOrionNode.options_exists(OPTION_THEME):
		GlobalFreeOrionNode.options_add_string(OPTION_THEME, "OPTIONS_DB_UI_THEME", "default")
	_scale_setting = GlobalFreeOrionNode.options_get_string(OPTION_SCALE)
	_theme_name = GlobalFreeOrionNode.options_get_string(OPTION_THEME)


func _options_available() -> bool:
	return (
		is_instance_valid(GlobalFreeOrionNode)
		and GlobalFreeOrionNode.has_method("options_exists")
		and not Engine.is_editor_hint()
	)
