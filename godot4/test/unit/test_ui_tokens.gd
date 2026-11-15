extends GutTest
## Design tokens and the generated theme.

const TOKEN_SETS := ["res://ui/tokens/default.tres", "res://ui/tokens/high_contrast.tres"]


func test_text_contrast_meets_wcag_aa():
	for path in TOKEN_SETS:
		var t: FOTokens = load(path)
		for bg_name in ["surface", "surface_raised", "surface_overlay"]:
			var bg: Color = t.get(bg_name)
			for fg_name in ["text_primary", "text_secondary"]:
				var ratio := _contrast(t.get(fg_name), bg)
				assert_gte(ratio, 4.5, "%s: %s on %s is %.2f:1" % [path, fg_name, bg_name, ratio])
		var accent_ratio := _contrast(t.text_on_accent, t.accent)
		assert_gte(
			accent_ratio, 4.5, "%s: text_on_accent on accent is %.2f:1" % [path, accent_ratio]
		)


func test_theme_builds_from_every_token_set():
	for path in TOKEN_SETS:
		var t: FOTokens = load(path)
		var theme := FOThemeBuilder.build(t)
		assert_eq(theme.default_font_size, t.font_size_body, path)
		for type in ["Button", "PanelContainer", "LineEdit", "TooltipPanel", "TabContainer"]:
			var names := theme.get_stylebox_list(type)
			assert_gt(names.size(), 0, "%s: %s has styleboxes" % [path, type])
		assert_eq(theme.get_color("font_color", "Label"), t.text_primary, path)
		for variation in ["PrimaryButton", "GhostButton", "SecondaryLabel", "TitleLabel"]:
			assert_ne(theme.get_type_variation_base(variation), &"", "%s: %s" % [path, variation])


func test_focus_ring_is_visible_on_every_surface():
	for path in TOKEN_SETS:
		var t: FOTokens = load(path)
		for bg_name in ["surface", "surface_raised", "surface_overlay"]:
			var ratio := _contrast(t.focus_ring, t.get(bg_name))
			assert_gte(ratio, 3.0, "%s: focus ring on %s is %.2f:1" % [path, bg_name, ratio])


# WCAG 2.x contrast ratio of two opaque colours.
func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(c: Color) -> float:
	return 0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b)


func _channel(v: float) -> float:
	return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
