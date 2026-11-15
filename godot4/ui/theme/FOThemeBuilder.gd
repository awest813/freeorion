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
