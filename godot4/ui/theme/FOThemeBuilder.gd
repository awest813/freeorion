class_name FOThemeBuilder
extends RefCounted
## Builds the UI Theme from an FOTokens resource.
##
## The theme is generated at runtime instead of being stored as a .tres, so
## the tokens stay the only place where visual values live and every token
## set (default, high contrast, ...) gets a consistent theme for free.


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


## Focus indicator drawn on top of a control: outline only, outside its rect.
static func focus_box(tokens: FOTokens) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = tokens.focus_ring
	style.set_border_width_all(tokens.focus_width)
	style.set_corner_radius_all(tokens.radius + tokens.focus_width)
	style.set_expand_margin_all(tokens.focus_width)
	return style


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


static func _buttons(theme: Theme, t: FOTokens) -> void:
	var pad_x := t.space_4
	var pad_y := t.space_2
	for type in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", type, box(t, t.surface_raised, t.border, pad_x, pad_y))
		theme.set_stylebox("hover", type, box(t, t.surface_overlay, t.border_strong, pad_x, pad_y))
		theme.set_stylebox("pressed", type, box(t, t.surface_overlay, t.accent, pad_x, pad_y))
		theme.set_stylebox("disabled", type, box(t, t.surface, t.border, pad_x, pad_y))
		theme.set_stylebox("focus", type, focus_box(t))
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
	theme.set_stylebox("normal", "PrimaryButton", box(t, t.accent, t.accent, pad_x, pad_y))
	theme.set_stylebox(
		"hover", "PrimaryButton", box(t, t.accent_hover, t.accent_hover, pad_x, pad_y)
	)
	theme.set_stylebox(
		"pressed", "PrimaryButton", box(t, t.accent_pressed, t.accent_pressed, pad_x, pad_y)
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
	theme.set_stylebox("normal", "DangerButton", box(t, t.surface_raised, t.negative, pad_x, pad_y))
	theme.set_stylebox("hover", "DangerButton", box(t, t.negative, t.negative, pad_x, pad_y))
	theme.set_stylebox("pressed", "DangerButton", box(t, t.negative, t.negative, pad_x, pad_y))
	theme.set_color("font_color", "DangerButton", t.negative)
	theme.set_color("font_focus_color", "DangerButton", t.negative)
	for color in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(color, "DangerButton", t.text_on_accent)

	# Low-emphasis button with no box until hovered: "GhostButton".
	theme.set_type_variation("GhostButton", "Button")
	var ghost := box(t, Color(0, 0, 0, 0), Color(0, 0, 0, 0), pad_x, pad_y)
	theme.set_stylebox("normal", "GhostButton", ghost)
	theme.set_stylebox("disabled", "GhostButton", ghost)


static func _panels(theme: Theme, t: FOTokens) -> void:
	var panel := box(t, t.surface_raised, t.border, t.space_3, t.space_3)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PanelContainer", panel)

	# Full-bleed background behind screens: "BackgroundPanel".
	theme.set_type_variation("BackgroundPanel", "PanelContainer")
	var background := box(t, t.surface, t.surface, 0, 0)
	background.set_border_width_all(0)
	background.set_corner_radius_all(0)
	theme.set_stylebox("panel", "BackgroundPanel", background)

	# Full-width bar along the top of a screen: "TopBarPanel".
	theme.set_type_variation("TopBarPanel", "PanelContainer")
	var top_bar := box(t, Color(t.surface_raised, 0.94), t.border, t.space_4, t.space_2)
	top_bar.set_border_width_all(0)
	top_bar.border_width_bottom = t.border_width
	top_bar.set_corner_radius_all(0)
	theme.set_stylebox("panel", "TopBarPanel", top_bar)

	# Floating or emphasised surface: "OverlayPanel".
	theme.set_type_variation("OverlayPanel", "PanelContainer")
	theme.set_stylebox(
		"panel", "OverlayPanel", box(t, t.surface_overlay, t.border_strong, t.space_4, t.space_4)
	)

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


static func _popups(theme: Theme, t: FOTokens) -> void:
	var overlay := box(t, t.surface_overlay, t.border_strong, t.space_2, t.space_2)
	theme.set_stylebox("panel", "PopupMenu", overlay)
	theme.set_stylebox("panel", "PopupPanel", overlay)
	theme.set_stylebox("panel", "TooltipPanel", overlay)
	theme.set_stylebox("hover", "PopupMenu", box(t, t.accent, t.accent, t.space_2, t.space_1))
	theme.set_color("font_color", "PopupMenu", t.text_primary)
	theme.set_color("font_hover_color", "PopupMenu", t.text_on_accent)
	theme.set_color("font_disabled_color", "PopupMenu", t.text_disabled)
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
	var slider_track := box(t, t.surface_overlay, t.border, 0, thickness)
	var slider_fill := box(t, t.accent, t.accent, 0, thickness)
	var slider_fill_hover := box(t, t.accent_hover, t.accent_hover, 0, thickness)
	for type in ["HSlider", "VSlider"]:
		theme.set_stylebox("slider", type, slider_track)
		theme.set_stylebox("grabber_area", type, slider_fill)
		theme.set_stylebox("grabber_area_highlight", type, slider_fill_hover)


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
