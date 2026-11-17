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
## Dialogs and menus that keep the keyboard focus while they show.
const MODAL_GROUP := "fo_modal"
## Full screens; while one shows, Tab cycles through it and CHROME_GROUP
## (the top bar), not the map's controls behind it.
const SCREEN_GROUP := "fo_screen"
const CHROME_GROUP := "fo_chrome"
## Panels that get the glass shader (see glass_panel.gdshader).
const GLASS_PANELS := ["OverlayPanel", "TopBarPanel", "BackgroundPanel"]
const GLASS_SHADER := preload("res://ui/theme/glass_panel.gdshader")
## A screen opening settles from this scale.
const SETTLE_SCALE := 1.015
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

## The FPS counter (video.fps.shown), made when first shown.
var _fps: Label

## The tooltip showing now, if any (a WeakRef).
var _tooltip: WeakRef


func _ready() -> void:
	glass_material.shader = GLASS_SHADER
	_read_options()
	apply_theme(_theme_name)
	get_tree().node_added.connect(_on_node_added)
	get_window().size_changed.connect(_apply_scale)
	_apply_scale()
	get_viewport().gui_focus_changed.connect(_keep_focus_in_modal)


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


## Bring \a item in: fade in while settling from a touch larger (a full
## screen opening), unless motion is reduced. Only its drawing changes (scale
## and modulate), never its layout: moving an anchored screen as it first
## shows would upset its offsets.
func slide_in(item: Control) -> void:
	if reduce_motion or not item.is_inside_tree():
		item.modulate.a = 1.0
		item.scale = Vector2.ONE
		return
	item.pivot_offset = item.get_parent_area_size() / 2.0
	item.scale = Vector2.ONE * SETTLE_SCALE
	item.modulate.a = 0.0
	var tween := item.create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "modulate:a", 1.0, tokens.motion)
	tween.tween_property(item, "scale", Vector2.ONE, tokens.motion)


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
	# Deferred, so the node's own setup comes first; it may be freed by then.
	if node is PanelContainer:
		_when_valid.call_deferred(_glaze, node)
	elif node is Button and not node is OptionButton:
		_when_valid.call_deferred(adopt_glyph, node)
	elif node is Label and node.theme_type_variation == "TooltipLabel":
		wrap_tooltip(node)
	elif node is PopupPanel and node.theme_type_variation == "TooltipPanel":
		_pass_escape_on(node)
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
	var size := tokens.icon_small + tokens.space_1 if tokens else 20
	var texture := FOIcons.for_glyph(button.text, size)
	if texture == null:
		return
	# Drawn at the UI scale for sharpness, shown at its size in UI units.
	button.add_theme_constant_override("icon_max_width", size)
	button.set_meta("glyph", button.text)
	button.text = ""
	button.icon = texture
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER


# Glass for \a panel if it is one of GLASS_PANELS (its variation may be set
# in its _ready, hence deferred).
## Make a tooltip's \a label wrap at a readable width when it is longer.
## Godot's own tooltip never wraps; this runs as it enters the tree, before
## the tooltip is measured.
func wrap_tooltip(label: Label) -> void:
	var limit := tokens.space_8 * 13
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var widest := 0.0
	for line in label.text.split("\n"):
		widest = maxf(
			widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		)
	if widest > limit:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = limit


# Esc while a tooltip shows only closes the tooltip (the viewport keeps the
# key), so the player pointing at something and pressing Esc to close a
# screen would have to press it twice. Esc goes on to the game once the
# tooltip is gone.
func _pass_escape_on(tooltip: Window) -> void:
	_tooltip = weakref(tooltip) if tooltip else null


## The modal on top (a dialog, the game menu): the last visible member of
## MODAL_GROUP; null when there is none.
func top_modal() -> Control:
	var modals := get_tree().get_nodes_in_group(MODAL_GROUP).filter(
		func(node): return node is Control and node.is_visible_in_tree()
	)
	return modals.back() if not modals.is_empty() else null


# Tab doesn't leave a modal for the controls hidden behind it.
func _keep_focus_in_modal(focused: Control) -> void:
	var modal := top_modal()
	if modal and focused and not modal.is_ancestor_of(focused):
		_refocus_modal.call_deferred()


func _refocus_modal() -> void:
	var modal := top_modal()
	if modal:
		ScreenKit.focus_first(modal)


## Where Tab moves now: the modal on top; else an open screen with the top
## bar; else [] (anywhere).
func focus_scope() -> Array[Node]:
	var modal := top_modal()
	if modal:
		return [modal]
	var visible_in := func(group: String) -> Array[Node]:
		var nodes: Array[Node] = []
		for node in get_tree().get_nodes_in_group(group):
			if node is Control and node.is_visible_in_tree():
				nodes.push_back(node)
		return nodes
	var screens: Array[Node] = visible_in.call(SCREEN_GROUP)
	if screens.is_empty():
		return []
	# The screen's own controls first, then the top bar's.
	return screens + visible_in.call(CHROME_GROUP)


# Tab (Shift+Tab back) to the next control in the focus scope, round from
# the last to the first; with nothing focused, to the first.
func _cycle_focus(scope: Array[Node], step: int) -> void:
	var order: Array[Control] = []
	for root in scope:
		order.append_array(ScreenKit.focusables(root))
	if order.is_empty():
		return
	var at := order.find(get_viewport().gui_get_focus_owner())
	var next := (at + step) if at >= 0 else (0 if step > 0 else -1)
	order[posmod(next, order.size())].grab_focus()


func _input(event: InputEvent) -> void:
	var step := 0
	if event.is_action_pressed("ui_focus_next"):
		step = 1
	elif event.is_action_pressed("ui_focus_prev"):
		step = -1
	if step != 0:
		var scope := focus_scope()
		if scope.is_empty() and get_viewport().gui_get_focus_owner() == null:
			scope = [get_tree().current_scene]
		if not scope.is_empty():
			_cycle_focus(scope, step)
			get_viewport().set_input_as_handled()
			return
	if not (event is InputEventKey and event.is_action_pressed("ui_cancel")):
		return
	var tooltip: Window = _tooltip.get_ref() if _tooltip else null
	if tooltip and tooltip.visible:
		_tooltip = null
		# Once the tooltip has gone (it closes over the next frames).
		for i in 5:
			await get_tree().process_frame
			if not is_instance_valid(tooltip) or not tooltip.is_inside_tree():
				break
		get_viewport().push_input(event)


func _when_valid(action: Callable, node: Variant) -> void:
	if is_instance_valid(node):
		action.call(node)


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
	FOWindow.add_options(options)
	for video in [FOWindow.OPTION_VSYNC, FOWindow.OPTION_FPS_LIMITED, FOWindow.OPTION_FPS_MAX]:
		options.watch(video)
	for video in [FOWindow.OPTION_FPS_BACKGROUND, FOWindow.OPTION_FPS_SHOWN]:
		options.watch(video)
	FOWindow.apply_frame_rate(options)
	_show_fps(options.get_value(FOWindow.OPTION_FPS_SHOWN))
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
		FOWindow.OPTION_FPS_SHOWN:
			_show_fps(options.get_value(FOWindow.OPTION_FPS_SHOWN))
		_:
			if option_name.begins_with("video."):
				FOWindow.apply_frame_rate(options)


# The window in the background runs at the lower frame rate (if set), and
# back at the full one in front.
func _notification(what: int) -> void:
	if not _options_available():
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		FOWindow.apply_frame_rate(Engine.get_singleton("FOOptions"), false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		FOWindow.apply_frame_rate(Engine.get_singleton("FOOptions"), true)


# The frames per second in the top-right corner, over everything.
func _show_fps(shown: bool) -> void:
	if shown and _fps == null:
		var layer := CanvasLayer.new()
		layer.layer = 128
		add_child(layer)
		_fps = Label.new()
		_fps.theme_type_variation = "SmallLabel"
		_fps.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_fps.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_fps.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_fps.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_fps)
	if _fps:
		_fps.get_parent().visible = shown


func _process(_delta: float) -> void:
	if _fps and _fps.is_visible_in_tree() and Engine.get_process_frames() % 30 == 0:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()


func _options_available() -> bool:
	return Engine.has_singleton("FOOptions") and not Engine.is_editor_hint()
