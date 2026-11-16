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


func test_empire_colours_make_readable_accents():
	var base: FOTokens = load(TOKEN_SETS[0])
	for color in [Color("#3a0a5a"), Color("#00ff00"), Color("#6b1a1a"), Color("#0a0a40")]:
		var t: FOTokens = base.duplicate()
		FOThemeBuilder.accent_from(t, color)
		for name in ["accent", "accent_pressed"]:
			var ratio := _contrast(t.text_on_accent, t.get(name))
			assert_gte(ratio, 4.5, "%s from %s: %.2f:1" % [name, color.to_html(), ratio])
		assert_gt(t.accent_hover.get_luminance(), t.accent.get_luminance(), "hover is lighter")
	assert_eq(base.accent, load(TOKEN_SETS[0]).accent, "the token file is left alone")


func test_text_stays_readable_on_glass_over_anything():
	var t: FOTokens = load(TOKEN_SETS[0])
	for alpha in [t.glass_alpha, t.glass_alpha_screen]:
		# Worst case behind the glass: a white star.
		var worst := Color.WHITE.lerp(t.glass_fill, alpha)
		for fg_name in ["text_primary", "text_secondary"]:
			var ratio := _contrast(t.get(fg_name), worst)
			assert_gte(ratio, 4.5, "%s on glass %.2f: %.2f:1" % [fg_name, alpha, ratio])


func test_floating_panels_get_the_glass():
	var panel := PanelContainer.new()
	panel.theme_type_variation = "OverlayPanel"
	var plain := PanelContainer.new()
	add_child_autofree(panel)
	add_child_autofree(plain)
	await wait_process_frames(1)
	assert_eq(panel.material, FOUi.glass_material)
	assert_null(plain.material, "nested cards stay as they are")


func test_interface_glyphs_become_icons():
	for glyph: String in FOIcons.GLYPHS:
		assert_not_null(FOIcons.for_glyph(glyph, 16), "icon for %s" % glyph)
	var close := Button.new()
	close.text = "✕"
	var plain := Button.new()
	plain.text = "Add"
	add_child_autofree(close)
	add_child_autofree(plain)
	await wait_process_frames(1)
	assert_eq(close.text, "")
	assert_not_null(close.icon)
	assert_eq(close.get_meta("glyph"), "✕")
	assert_eq(plain.text, "Add", "words stay words")


func test_long_tooltips_wrap():
	var label := Label.new()
	label.theme_type_variation = "TooltipLabel"
	label.text = "word ".repeat(200)
	add_child_autofree(label)
	assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "wrapped as it entered the tree")
	assert_eq(label.custom_minimum_size.x, float(FOUi.tokens.space_8 * 13))
	var short := Label.new()
	short.theme_type_variation = "TooltipLabel"
	short.text = "Close"
	add_child_autofree(short)
	assert_eq(short.autowrap_mode, TextServer.AUTOWRAP_OFF, "short ones keep their width")


func test_destructive_dialogs_start_on_cancel():
	var dialog := FODialog.open_on(
		self, "Delete", "Sure?", [["Delete", "DangerButton"], ["Cancel", "GhostButton"]]
	)
	await wait_process_frames(2)
	assert_eq(get_viewport().gui_get_focus_owner(), dialog._row.get_child(1), "Enter cancels")
	dialog.queue_free()
	var safe := FODialog.open_on(self, "Saved", "Done.", [["OK", "PrimaryButton"]])
	await wait_process_frames(2)
	assert_eq(get_viewport().gui_get_focus_owner(), safe._row.get_child(0))
	safe.queue_free()
