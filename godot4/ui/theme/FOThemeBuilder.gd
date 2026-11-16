class_name FOThemeBuilder
extends RefCounted
## Builds the UI Theme from an FOTokens resource.
##
## The theme is generated at runtime instead of being stored as a .tres, so
## the tokens stay the only place where visual values live and every token
## set (default, high contrast, ...) gets a consistent theme for free.

const DISPLAY_FONT := "res://assets/fonts/Exo2-Variable.ttf"
const BODY_FONT := "res://assets/fonts/Roboto-Regular.ttf"


static func build(tokens: FOTokens) -> Theme:
	var theme := Theme.new()
	theme.default_font_size = tokens.font_size_body
	_labels(theme, tokens)
	_buttons(theme, tokens)
	_panels(theme, tokens)
	_line_edit(theme, tokens)
	_popups(theme, tokens)
	_tabs(theme, tokens)
	_ranges(theme, tokens)
	_separators(theme, tokens)
	_trees(theme, tokens)
	return theme


## A filled box with the token border and radius.
static func box(
	tokens: FOTokens, bg: Color, border_color: Color, padding_x: int, padding_y: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border_color
	style.set_border_width_all(tokens.border_width)
	style.set_corner_radius_all(tokens.radius)
	style.content_margin_left = padding_x
	style.content_margin_right = padding_x
	style.content_margin_top = padding_y
	style.content_margin_bottom = padding_y
	return style


## \a style with cut corners (top left and bottom right, \a size px; the
## others barely), the observatory-glass outline of panels and buttons.
static func cut(style: StyleBoxFlat, t: FOTokens, size: int) -> StyleBoxFlat:
	style.corner_radius_top_left = size
	style.corner_radius_bottom_right = size
	style.corner_radius_top_right = t.radius_small
	style.corner_radius_bottom_left = t.radius_small
	style.corner_detail = 1
	return style


## A floating glass panel: see-through fill (FOUi gives such panels the glass
## shader, which blurs what is behind), hairline edge, cut corners and a drop
## shadow; opaque with glass off (high contrast).
static func glass(t: FOTokens, padding: int, alpha: float, edged := true) -> StyleBoxFlat:
	var fill := Color(t.glass_fill, alpha) if t.glass_enabled else t.surface_overlay
	var style := cut(box(t, fill, t.edge if edged else fill, padding, padding), t, t.chamfer)
	if not edged:
		style.set_border_width_all(0)
	style.shadow_color = t.shadow
	style.shadow_size = t.shadow_size
	return style


## The display face (titles, headings, captions): \a t's weight and \a spacing
## (extra px between letters), falling back to the body face for missing
## glyphs (Greek letters in star names).
static func display_font(t: FOTokens, spacing: int) -> Font:
	var base: FontFile = load(DISPLAY_FONT)
	base.fallbacks = [load(BODY_FONT)]
	var font := FontVariation.new()
	font.base_font = base
	font.variation_opentype = {
		TextServerManager.get_primary_interface().name_to_tag("wght"): t.display_weight
	}
	font.spacing_glyph = spacing
	return font


## Make \a color (an empire's) \a t's accent: lightened until text on it
## (text_on_accent) reads at 4.5:1 or better, with hover, pressed and focus
## shades from it.
static func accent_from(t: FOTokens, color: Color) -> void:
	var accent := Color(color, 1.0)
	for i in 16:
		if contrast(accent, t.text_on_accent) >= 4.5:
			break
		accent = accent.lightened(0.08)
	t.accent = accent
	t.accent_hover = accent.lightened(0.18)
	t.accent_pressed = accent.darkened(0.1)
	if contrast(t.accent_pressed, t.text_on_accent) < 4.5:
		t.accent_pressed = accent
	t.focus_ring = accent.lightened(0.45)


## WCAG contrast ratio between \a a and \a b (1 to 21).
static func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## WCAG relative luminance of \a c.
static func luminance(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


## Focus indicator drawn on top of a control: outline only, outside its rect.
static func focus_box(tokens: FOTokens, cut_corners := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = tokens.focus_ring
	style.set_border_width_all(tokens.focus_width)
	style.set_corner_radius_all(tokens.radius + tokens.focus_width)
	style.set_expand_margin_all(tokens.focus_width)
	# Around buttons, following their cut corners.
	return cut(style, tokens, tokens.chamfer_small + tokens.focus_width) if cut_corners else style


static func _labels(theme: Theme, t: FOTokens) -> void:
	theme.set_color("font_color", "Label", t.text_primary)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	theme.set_color("default_color", "RichTextLabel", t.text_primary)
	theme.set_color("font_selected_color", "RichTextLabel", t.text_on_accent)
	theme.set_color("selection_color", "RichTextLabel", t.accent)

	# Type variations: set Control.theme_type_variation to use them.
	for variation in ["SecondaryLabel", "TitleLabel", "HeadingLabel", "SmallLabel"]:
		theme.set_type_variation(variation, "Label")
	theme.set_color("font_color", "SecondaryLabel", t.text_secondary)
	theme.set_font_size("font_size", "SmallLabel", t.font_size_small)
	theme.set_color("font_color", "SmallLabel", t.text_secondary)
	theme.set_font_size("font_size", "TitleLabel", t.font_size_title)
	theme.set_font_size("font_size", "HeadingLabel", t.font_size_heading)
	# Titles and headings in the display face; "DisplayTitle" for the largest
	# (screen and title-screen names), "SectionCaps" for section captions
	# (set uppercase on the label, as ScreenKit.section() does).
	var display := display_font(t, t.display_spacing)
	theme.set_font("font", "TitleLabel", display)
	theme.set_font("font", "HeadingLabel", display)
	theme.set_type_variation("DisplayTitle", "Label")
	theme.set_font("font", "DisplayTitle", display)
	theme.set_font_size("font_size", "DisplayTitle", t.font_size_display)
	theme.set_type_variation("SectionCaps", "Label")
	theme.set_font("font", "SectionCaps", display_font(t, t.caps_spacing))
	theme.set_font_size("font_size", "SectionCaps", t.font_size_small)
	theme.set_color("font_color", "SectionCaps", t.text_secondary)


static func _buttons(theme: Theme, t: FOTokens) -> void:
	var pad_x := t.space_4
	var pad_y := t.space_2
	var cs := t.chamfer_small
	for type in ["Button", "OptionButton", "MenuButton"]:
		var normal := cut(box(t, t.surface_raised, t.border, pad_x, pad_y), t, cs)
		theme.set_stylebox("normal", type, normal)
		var hover := cut(box(t, t.surface_overlay, t.border_strong, pad_x, pad_y), t, cs)
		theme.set_stylebox("hover", type, hover)
		var pressed := cut(box(t, t.surface_overlay, t.accent, pad_x, pad_y), t, cs)
		theme.set_stylebox("pressed", type, pressed)
		theme.set_stylebox("disabled", type, cut(box(t, t.surface, t.border, pad_x, pad_y), t, cs))
		theme.set_stylebox("focus", type, focus_box(t, true))
		theme.set_color("font_color", type, t.text_primary)
		theme.set_color("font_hover_color", type, t.text_primary)
		theme.set_color("font_pressed_color", type, t.text_primary)
		theme.set_color("font_focus_color", type, t.text_primary)
		theme.set_color("font_hover_pressed_color", type, t.text_primary)
		theme.set_color("font_disabled_color", type, t.text_disabled)
		theme.set_color("icon_normal_color", type, t.text_primary)
		theme.set_color("icon_disabled_color", type, t.text_disabled)
		theme.set_constant("h_separation", type, t.space_2)

	# Check boxes and switches: no box of their own, a light hover only.
	for type in ["CheckBox", "CheckButton"]:
		var clear := box(t, Color(0, 0, 0, 0), Color(0, 0, 0, 0), t.space_1, t.space_1)
		var hover := box(t, t.surface_overlay, Color(0, 0, 0, 0), t.space_1, t.space_1)
		for state in ["normal", "pressed", "disabled", "hover_pressed"]:
			theme.set_stylebox(state, type, clear)
		theme.set_stylebox("hover", type, hover)
		theme.set_stylebox("focus", type, focus_box(t))
		theme.set_color("font_color", type, t.text_primary)
		theme.set_color("font_hover_color", type, t.text_primary)
		theme.set_color("font_pressed_color", type, t.text_primary)
		theme.set_color("font_hover_pressed_color", type, t.text_primary)
		theme.set_color("font_disabled_color", type, t.text_disabled)
		theme.set_constant("h_separation", type, t.space_2)
	_check_glyphs(theme, t)

	# Primary call to action, e.g. End Turn: theme_type_variation = "PrimaryButton".
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox(
		"normal", "PrimaryButton", cut(box(t, t.accent, t.accent, pad_x, pad_y), t, cs)
	)
	# Lit from within when pointed at.
	var primary_hover := cut(box(t, t.accent_hover, t.accent_hover, pad_x, pad_y), t, cs)
	if t.glass_enabled:
		primary_hover.shadow_color = Color(t.accent, 0.45)
		primary_hover.shadow_size = t.space_2
	theme.set_stylebox("hover", "PrimaryButton", primary_hover)
	theme.set_stylebox(
		"pressed",
		"PrimaryButton",
		cut(box(t, t.accent_pressed, t.accent_pressed, pad_x, pad_y), t, cs)
	)
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(color, "PrimaryButton", t.text_on_accent)

	# One option of a segmented control: compact padding, small text.
	theme.set_type_variation("SegmentButton", "Button")
	var seg_x := t.space_1
	theme.set_stylebox("normal", "SegmentButton", box(t, t.surface_raised, t.border, seg_x, pad_y))
	theme.set_stylebox(
		"hover", "SegmentButton", box(t, t.surface_overlay, t.border_strong, seg_x, pad_y)
	)
	theme.set_stylebox(
		"pressed", "SegmentButton", box(t, t.surface_overlay, t.accent, seg_x, pad_y)
	)
	theme.set_font_size("font_size", "SegmentButton", t.font_size_small)

	# Destructive action, e.g. leaving the game: "DangerButton".
	theme.set_type_variation("DangerButton", "Button")
	var danger := cut(box(t, t.surface_raised, t.negative, pad_x, pad_y), t, cs)
	theme.set_stylebox("normal", "DangerButton", danger)
	var danger_on := cut(box(t, t.negative, t.negative, pad_x, pad_y), t, cs)
	theme.set_stylebox("hover", "DangerButton", danger_on)
	theme.set_stylebox("pressed", "DangerButton", danger_on)
	theme.set_color("font_color", "DangerButton", t.negative)
	theme.set_color("font_focus_color", "DangerButton", t.negative)
	for color in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(color, "DangerButton", t.text_on_accent)

	# Low-emphasis button with no box until hovered: "GhostButton".
	theme.set_type_variation("GhostButton", "Button")
	var ghost := box(t, Color(0, 0, 0, 0), Color(0, 0, 0, 0), pad_x, pad_y)
	theme.set_stylebox("normal", "GhostButton", ghost)
	theme.set_stylebox("disabled", "GhostButton", ghost)

	# Title-screen menu items: no box, the display face, a bar in the accent
	# at the left and a tint when pointed at; "MenuItemPrimary" in the accent.
	var display := display_font(t, t.display_spacing)
	for variation in ["MenuItem", "MenuItemPrimary"]:
		theme.set_type_variation(variation, "Button")
		var item := box(t, Color(0, 0, 0, 0), Color(0, 0, 0, 0), t.space_4, t.space_2)
		item.set_border_width_all(0)
		theme.set_stylebox("normal", variation, item)
		theme.set_stylebox("disabled", variation, item)
		var lit := box(t, Color(t.accent, 0.14), t.accent, t.space_4, t.space_2)
		lit.set_border_width_all(0)
		lit.border_width_left = t.focus_width + 1
		lit.set_corner_radius_all(0)
		theme.set_stylebox("hover", variation, lit)
		theme.set_stylebox("pressed", variation, lit)
		theme.set_stylebox("hover_pressed", variation, lit)
		theme.set_stylebox("focus", variation, lit)
		theme.set_font("font", variation, display)
		theme.set_font_size("font_size", variation, t.font_size_title)
	for color in ["font_color", "font_focus_color"]:
		theme.set_color(color, "MenuItemPrimary", t.accent_hover)

	# The top bar's screen buttons: ghost buttons a little tighter, so eight
	# names and the empire's fit across a 1280 px bar.
	theme.set_type_variation("NavButton", "GhostButton")
	var nav := box(t, Color(0, 0, 0, 0), Color(0, 0, 0, 0), t.space_3, pad_y)
	theme.set_stylebox("normal", "NavButton", nav)
	theme.set_stylebox("disabled", "NavButton", nav)
	for state in ["hover", "pressed"]:
		var lit := (theme.get_stylebox(state, "Button") as StyleBoxFlat).duplicate()
		lit.content_margin_left = t.space_3
		lit.content_margin_right = t.space_3
		theme.set_stylebox(state, "NavButton", lit)


static func _panels(theme: Theme, t: FOTokens) -> void:
	var panel := box(t, t.surface_raised, t.border, t.space_3, t.space_3)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PanelContainer", panel)

	# Full-bleed background behind screens: "BackgroundPanel".
	theme.set_type_variation("BackgroundPanel", "PanelContainer")
	var background := box(t, t.surface, t.surface, 0, 0)
	if t.glass_enabled:
		background.bg_color = Color(t.glass_fill, t.glass_alpha_screen)
	background.set_border_width_all(0)
	background.set_corner_radius_all(0)
	theme.set_stylebox("panel", "BackgroundPanel", background)

	# Full-width bar along the top of a screen: "TopBarPanel".
	theme.set_type_variation("TopBarPanel", "PanelContainer")
	var top_bar := box(t, Color(t.surface_raised, 0.94), t.border, t.space_4, t.space_2)
	if t.glass_enabled:
		top_bar.bg_color = Color(t.glass_fill, t.glass_alpha)
		top_bar.border_color = t.edge
	top_bar.set_border_width_all(0)
	top_bar.border_width_bottom = t.border_width
	top_bar.set_corner_radius_all(0)
	theme.set_stylebox("panel", "TopBarPanel", top_bar)

	# Floating or emphasised surface: "OverlayPanel".
	theme.set_type_variation("OverlayPanel", "PanelContainer")
	theme.set_stylebox("panel", "OverlayPanel", glass(t, t.space_4, t.glass_alpha))

	theme.set_constant("separation", "BoxContainer", t.space_2)
	theme.set_constant("separation", "HBoxContainer", t.space_2)
	theme.set_constant("separation", "VBoxContainer", t.space_2)
	theme.set_constant("h_separation", "GridContainer", t.space_2)
	theme.set_constant("v_separation", "GridContainer", t.space_2)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		theme.set_constant(side, "MarginContainer", t.space_4)


static func _line_edit(theme: Theme, t: FOTokens) -> void:
	for type in ["LineEdit", "TextEdit", "SpinBox"]:
		theme.set_stylebox("normal", type, box(t, t.surface, t.border, t.space_2, t.space_2))
		theme.set_stylebox("focus", type, focus_box(t))
		theme.set_stylebox("read_only", type, box(t, t.surface, t.border, t.space_2, t.space_2))
		theme.set_color("font_color", type, t.text_primary)
		theme.set_color("font_uneditable_color", type, t.text_disabled)
		theme.set_color("font_placeholder_color", type, t.text_disabled)
		theme.set_color("caret_color", type, t.accent)
		theme.set_color("selection_color", type, Color(t.accent, 0.35))


# Menus and tooltips float like the other chrome: cut corners, a shadow;
# the pointed item gets the menu items' tint and accent bar.
static func _popups(theme: Theme, t: FOTokens) -> void:
	var overlay := cut(
		box(t, t.surface_overlay, t.border_strong, t.space_2, t.space_2), t, t.chamfer_small
	)
	overlay.shadow_color = t.shadow
	overlay.shadow_size = t.space_2
	theme.set_stylebox("panel", "PopupMenu", overlay)
	theme.set_stylebox("panel", "PopupPanel", overlay)
	theme.set_stylebox("panel", "TooltipPanel", overlay)
	var lit := box(t, Color(t.accent, 0.16), t.accent, t.space_2, t.space_1)
	lit.set_border_width_all(0)
	lit.border_width_left = t.focus_width + 1
	lit.set_corner_radius_all(0)
	theme.set_stylebox("hover", "PopupMenu", lit)
	var line := StyleBoxLine.new()
	line.color = Color(t.border_strong, 0.6)
	line.grow_begin = -t.space_1
	line.grow_end = -t.space_1
	theme.set_stylebox("separator", "PopupMenu", line)
	theme.set_stylebox("labeled_separator_left", "PopupMenu", line)
	theme.set_stylebox("labeled_separator_right", "PopupMenu", line)
	theme.set_color("font_color", "PopupMenu", t.text_primary)
	theme.set_color("font_hover_color", "PopupMenu", t.text_primary)
	theme.set_color("font_disabled_color", "PopupMenu", t.text_disabled)
	theme.set_color("font_separator_color", "PopupMenu", t.text_secondary)
	theme.set_color("font_accelerator_color", "PopupMenu", t.text_secondary)
	theme.set_constant("v_separation", "PopupMenu", t.space_2)
	theme.set_constant("item_start_padding", "PopupMenu", t.space_2)
	theme.set_constant("item_end_padding", "PopupMenu", t.space_3)
	theme.set_constant("h_separation", "PopupMenu", t.space_3)
	theme.set_color("font_color", "TooltipLabel", t.text_primary)
	theme.set_font_size("font_size", "TooltipLabel", t.font_size_small)


static func _tabs(theme: Theme, t: FOTokens) -> void:
	var selected := box(t, t.surface_raised, t.accent, t.space_4, t.space_2)
	var unselected := box(t, t.surface, t.border, t.space_4, t.space_2)
	var hovered := box(t, t.surface_overlay, t.border_strong, t.space_4, t.space_2)
	for type in ["TabBar", "TabContainer"]:
		theme.set_stylebox("tab_selected", type, selected)
		theme.set_stylebox("tab_unselected", type, unselected)
		theme.set_stylebox("tab_hovered", type, hovered)
		theme.set_stylebox("tab_disabled", type, unselected)
		theme.set_stylebox("tab_focus", type, focus_box(t))
		theme.set_color("font_selected_color", type, t.text_primary)
		theme.set_color("font_unselected_color", type, t.text_secondary)
		theme.set_color("font_hovered_color", type, t.text_primary)
		theme.set_color("font_disabled_color", type, t.text_disabled)
	theme.set_stylebox(
		"panel", "TabContainer", box(t, t.surface_raised, t.border, t.space_3, t.space_3)
	)


static func _ranges(theme: Theme, t: FOTokens) -> void:
	var track := box(t, t.surface, t.border, 0, 0)
	var fill := box(t, t.accent, t.accent, 0, 0)
	theme.set_stylebox("background", "ProgressBar", track)
	theme.set_stylebox("fill", "ProgressBar", fill)
	theme.set_color("font_color", "ProgressBar", t.text_primary)
	# Slider tracks get their thickness from the vertical content margins.
	var thickness := t.space_1 / 2
	# (horizontal ones for vertical sliders).
	for type in ["HSlider", "VSlider"]:
		var x := thickness if type == "VSlider" else 0
		var y := 0 if type == "VSlider" else thickness
		theme.set_stylebox("slider", type, box(t, t.surface_overlay, t.border, x, y))
		theme.set_stylebox("grabber_area", type, box(t, t.accent, t.accent, x, y))
		theme.set_stylebox(
			"grabber_area_highlight", type, box(t, t.accent_hover, t.accent_hover, x, y)
		)


static func _separators(theme: Theme, t: FOTokens) -> void:
	for type in ["HSeparator", "VSeparator"]:
		var line := StyleBoxLine.new()
		line.color = t.border
		line.thickness = t.border_width
		line.vertical = type == "VSeparator"
		theme.set_stylebox("separator", type, line)
		theme.set_constant("separation", type, t.space_3)


# Check box and switch glyphs drawn from the tokens: Godot's defaults are
# dark grey and vanish on dark surfaces.
static func _check_glyphs(theme: Theme, t: FOTokens) -> void:
	var size := t.icon_small
	theme.set_icon("checked", "CheckBox", _checkbox_icon(size, t.accent, t.text_on_accent, true))
	theme.set_icon("unchecked", "CheckBox", _checkbox_icon(size, t.text_secondary, Color(), false))
	theme.set_icon(
		"checked_disabled", "CheckBox", _checkbox_icon(size, t.text_disabled, t.surface, true)
	)
	theme.set_icon(
		"unchecked_disabled", "CheckBox", _checkbox_icon(size, t.text_disabled, Color(), false)
	)
	var radio_on := _radio_icon(size, t.accent, t.text_on_accent, true)
	var radio_off := _radio_icon(size, t.text_secondary, Color(), false)
	theme.set_icon("radio_checked", "CheckBox", radio_on)
	theme.set_icon("radio_unchecked", "CheckBox", radio_off)
	# Menus' check and radio items look the same as the boxes.
	for item in ["checked", "unchecked", "radio_checked", "radio_unchecked"]:
		theme.set_icon(item, "PopupMenu", theme.get_icon(item, "CheckBox"))
	theme.set_icon("checked_disabled", "PopupMenu", theme.get_icon("checked_disabled", "CheckBox"))
	theme.set_icon(
		"unchecked_disabled", "PopupMenu", theme.get_icon("unchecked_disabled", "CheckBox")
	)
	var switch_on := _switch_icon(size, t.accent, t.text_on_accent, true)
	var switch_off := _switch_icon(size, t.text_secondary, t.text_secondary, false)
	for suffix in ["", "_mirrored"]:
		theme.set_icon("checked" + suffix, "CheckButton", switch_on)
		theme.set_icon("unchecked" + suffix, "CheckButton", switch_off)
		theme.set_icon("checked_disabled" + suffix, "CheckButton", switch_on)
		theme.set_icon("unchecked_disabled" + suffix, "CheckButton", switch_off)


## Square check box: outline only, or filled with a check mark.
static func _checkbox_icon(size: int, frame: Color, mark: Color, filled: bool) -> Texture2D:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	if filled:
		image.fill_rect(Rect2i(1, 1, size - 2, size - 2), frame)
		# Check mark: short stroke down-right, long stroke up-right.
		var left := Vector2(size * 0.25, size * 0.52)
		var bottom := Vector2(size * 0.43, size * 0.7)
		var right := Vector2(size * 0.76, size * 0.3)
		_stroke(image, left, bottom, size * 0.09, mark)
		_stroke(image, bottom, right, size * 0.09, mark)
	else:
		var r := Rect2i(1, 1, size - 2, size - 2)
		for i in 2:
			var inner := r.grow(-i)
			image.fill_rect(Rect2i(inner.position, Vector2i(inner.size.x, 1)), frame)
			image.fill_rect(
				Rect2i(inner.position + Vector2i(0, inner.size.y - 1), Vector2i(inner.size.x, 1)),
				frame
			)
			image.fill_rect(Rect2i(inner.position, Vector2i(1, inner.size.y)), frame)
			image.fill_rect(
				Rect2i(inner.position + Vector2i(inner.size.x - 1, 0), Vector2i(1, inner.size.y)),
				frame
			)
	return ImageTexture.create_from_image(image)


## Round radio mark: a ring, or a filled disc with a dot.
static func _radio_icon(size: int, ring: Color, dot: Color, filled: bool) -> Texture2D:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var center := Vector2(size, size) * 0.5
	var radius := size * 0.5 - 1.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if filled and d <= radius:
				image.set_pixel(x, y, dot if d <= radius * 0.4 else ring)
			elif not filled and d <= radius and d > radius - 2.0:
				image.set_pixel(x, y, ring)
	return ImageTexture.create_from_image(image)


## Pill switch, twice as wide as high; the knob sits right when on.
static func _switch_icon(height: int, track: Color, knob: Color, on: bool) -> Texture2D:
	var width := height * 2
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var radius := height * 0.5 - 1.0
	var center_y := height * 0.5
	for y in height:
		for x in width:
			var p := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(p.x, radius + 1.0, width - radius - 1.0)
			var inside := p.distance_to(Vector2(cx, center_y)) <= radius
			if not inside:
				continue
			var edge := p.distance_to(Vector2(cx, center_y)) > radius - 1.5
			if on or edge:
				image.set_pixel(x, y, track)
	var knob_x := width - radius - 1.0 if on else radius + 1.0
	var knob_r := radius - 2.5
	for y in height:
		for x in width:
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(knob_x, center_y)) <= knob_r:
				image.set_pixel(x, y, knob)
	return ImageTexture.create_from_image(image)


# Thick line by stamping discs along the segment.
static func _stroke(
	image: Image, from: Vector2, to: Vector2, half_width: float, color: Color
) -> void:
	var steps := int(from.distance_to(to) * 2.0) + 1
	for i in steps + 1:
		var c := from.lerp(to, float(i) / steps)
		for y in range(floori(c.y - half_width - 1), ceili(c.y + half_width + 1)):
			for x in range(floori(c.x - half_width - 1), ceili(c.x + half_width + 1)):
				if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
					continue
				if Vector2(x + 0.5, y + 0.5).distance_to(c) <= half_width:
					image.set_pixel(x, y, color)


# Tables (Tree with columns): flat rows, a quiet header, an accent selection.
static func _trees(theme: Theme, t: FOTokens) -> void:
	theme.set_stylebox("panel", "Tree", box(t, t.surface, t.border, t.space_1, t.space_1))
	theme.set_stylebox("focus", "Tree", focus_box(t))
	var selected := box(t, Color(t.accent, 0.22), Color(t.accent, 0.0), 0, 0)
	selected.set_corner_radius_all(t.radius_small)
	theme.set_stylebox("selected", "Tree", selected)
	theme.set_stylebox("selected_focus", "Tree", selected)
	var hovered := box(t, t.surface_raised, Color(0, 0, 0, 0), 0, 0)
	hovered.set_corner_radius_all(t.radius_small)
	theme.set_stylebox("hovered", "Tree", hovered)
	theme.set_stylebox("cursor", "Tree", StyleBoxEmpty.new())
	theme.set_stylebox("cursor_unfocused", "Tree", StyleBoxEmpty.new())
	var title := box(t, t.surface_raised, t.surface_raised, t.space_2, t.space_1)
	title.set_corner_radius_all(0)
	var title_hover := box(t, t.surface_overlay, t.surface_overlay, t.space_2, t.space_1)
	title_hover.set_corner_radius_all(0)
	theme.set_stylebox("title_button_normal", "Tree", title)
	theme.set_stylebox("title_button_hover", "Tree", title_hover)
	theme.set_stylebox("title_button_pressed", "Tree", title_hover)
	theme.set_color("title_button_color", "Tree", t.text_secondary)
	theme.set_color("font_color", "Tree", t.text_primary)
	theme.set_color("font_selected_color", "Tree", t.text_primary)
	theme.set_color("guide_color", "Tree", Color(t.border, 0.5))
	theme.set_constant("draw_guides", "Tree", 1)
	theme.set_constant("draw_relationship_lines", "Tree", 0)
	theme.set_constant("item_margin", "Tree", 0)
	theme.set_constant("inner_item_margin_left", "Tree", t.space_2)
	theme.set_constant("inner_item_margin_right", "Tree", t.space_2)
	theme.set_constant("v_separation", "Tree", t.space_1)
	theme.set_constant("h_separation", "Tree", t.space_1)
	# Plain lists (ItemList) look like the tables.
	theme.set_stylebox("panel", "ItemList", box(t, t.surface, t.border, t.space_1, t.space_1))
	theme.set_stylebox("focus", "ItemList", focus_box(t))
	for state in ["selected", "selected_focus"]:
		theme.set_stylebox(state, "ItemList", selected)
	theme.set_stylebox("hovered", "ItemList", hovered)
	theme.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	theme.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	theme.set_color("font_color", "ItemList", t.text_primary)
	theme.set_color("font_selected_color", "ItemList", t.text_primary)
	theme.set_color("guide_color", "ItemList", Color(0, 0, 0, 0))
	theme.set_constant("v_separation", "ItemList", t.space_2)
	theme.set_constant("h_separation", "ItemList", t.space_2)
