class_name TechCard
extends RefCounted
## The research screen's pieces: a tech's card in the catalogue grid, and
## the timeline rail beside each queued tech.

## Most unlock icons on a card; the rest show as "+N".
const MAX_CHIPS := 4


## The width a catalogue card needs, which sets the grid's columns.
static func min_width() -> int:
	return FOUi.tokens.space_8 * 8


## A card for \a tech: its icon, name and category, cost and turns, what it
## unlocks, and Pedia and Add buttons calling \a pedia and \a add. The
## returned row takes the card's clicks and drags.
static func build(tech: Dictionary, add: Callable, pedia: Callable) -> HBoxContainer:
	var tokens: FOTokens = FOUi.tokens
	var status: String = tech.get("status", "")
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", tokens.space_1)
	var padding := MarginContainer.new()
	padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padding.add_theme_constant_override("margin_top", tokens.space_2)
	padding.add_theme_constant_override("margin_bottom", tokens.space_2)
	padding.mouse_filter = Control.MOUSE_FILTER_PASS
	padding.add_child(body)
	row.add_child(padding)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", tokens.space_3)
	body.add_child(head)
	head.add_child(
		ScreenKit.icon(
			tech.get("icon", ""),
			tokens.icon_large,
			FOArt.tech_category_icon(tech.get("category", ""))
		)
	)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", 0)
	head.add_child(names)
	var title := ScreenKit.label(_t(tech.get("name", "")))
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	names.add_child(title)
	var category := ScreenKit.section(_t(tech.get("category", "")))
	category.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	category.clip_text = true
	names.add_child(category)

	var cost := _t("RESEARCH_CARD_COST").replace("%1%", "%.0f" % tech.get("cost", 0.0)).replace(
		"%2%", ScreenKit.turns_text(tech.get("turns", 0))
	)
	if status == "partial" or status == "unresearchable":
		cost += " · " + _t("RESEARCH_NEEDS_PREREQS")
	body.add_child(ScreenKit.label(cost, "SmallLabel"))

	var foot := HBoxContainer.new()
	body.add_child(foot)
	# The chips give way (clipped) on narrow cards.
	var strip := Control.new()
	strip.clip_contents = true
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.custom_minimum_size.y = tokens.icon
	strip.mouse_filter = Control.MOUSE_FILTER_PASS
	var chips := unlock_chips(tech.get("unlocks", []))
	chips.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	strip.add_child(chips)
	foot.add_child(strip)
	var info := ScreenKit.small_button("?", "PEDIA_OPEN")
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.pressed.connect(pedia)
	foot.add_child(info)
	if status != "complete":
		foot.add_child(_add_button(tech, add))
	ScreenKit.card(row, tech.get("category_color", tokens.border_strong))
	return row


## Small icons for what a tech unlocks, each named in its tooltip.
static func unlock_chips(unlocks: Array) -> HBoxContainer:
	var tokens: FOTokens = FOUi.tokens
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", tokens.space_1)
	chips.mouse_filter = Control.MOUSE_FILTER_PASS
	for i in mini(unlocks.size(), MAX_CHIPS):
		var item: Dictionary = unlocks[i]
		var chip := ScreenKit.icon(item.get("icon", ""), tokens.icon)
		if chip.texture == null:
			chip.free()
			continue
		chip.tooltip_text = _t("RESEARCH_TIP_UNLOCKS") + " " + _t(item.get("name", ""))
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chips.add_child(chip)
	if unlocks.size() > MAX_CHIPS:
		chips.add_child(ScreenKit.label("+%d" % (unlocks.size() - MAX_CHIPS), "SmallLabel"))
	return chips


## The timeline beside the queued tech at \a position of \a count, whose
## row is \a card: a line through the queue, a mark (filled once research
## is under way) and the turn it is done on, \a done_turn (none below 0).
static func rail(card: Control, position: int, count: int, done_turn: int, active: bool) -> Control:
	var tokens: FOTokens = FOUi.tokens
	var rail := Control.new()
	rail.custom_minimum_size.x = tokens.space_8 + tokens.space_2
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.set_meta("done_turn", done_turn)
	var label := Label.new()
	label.theme_type_variation = "SmallLabel"
	label.text = str(done_turn) if done_turn >= 0 else "—"
	label.tooltip_text = _t("RESEARCH_DONE_ON_TURN").replace("%1%", label.text)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	rail.add_child(label)
	rail.draw.connect(
		func():
			var x := rail.size.x / 2
			var mark_y := rail.size.y * 0.35
			var line := Color(tokens.text_secondary, 0.35)
			# The line runs on through the gaps to the next and last rows.
			var gap := 0.0
			if card.get_parent() is BoxContainer:
				gap = card.get_parent().get_theme_constant("separation") / 2.0
			var card_top := card.global_position.y - rail.global_position.y
			var top := card_top - gap if position > 0 else mark_y
			var bottom := card_top + card.size.y + gap if position < count - 1 else mark_y
			if bottom > top:
				rail.draw_line(Vector2(x, top), Vector2(x, bottom), line, 2.0)
			var radius := tokens.space_1 * 1.5
			rail.draw_circle(Vector2(x, mark_y), radius + 2, tokens.surface)
			if active:
				rail.draw_circle(Vector2(x, mark_y), radius, tokens.accent)
			else:
				rail.draw_arc(Vector2(x, mark_y), radius, 0, TAU, 24, tokens.accent, 1.5, true)
	)
	return rail


static func _add_button(tech: Dictionary, add: Callable) -> Button:
	var button := Button.new()
	var queued: bool = tech.get("in_queue", false)
	button.text = _t("RESEARCH_QUEUED") if queued else _t("PRODUCTION_ADD")
	button.tooltip_text = _t("QUEUE_ADD_TOP_TIP")
	# Missing prerequisites are queued first, in order.
	if not queued and tech.get("status", "") in ["partial", "unresearchable"]:
		button.text = _t("RESEARCH_ADD_WITH_PREREQS")
		button.tooltip_text = _t("RESEARCH_ADD_WITH_PREREQS_TIP")
	button.disabled = queued
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(add)
	return button


static func _t(text: String) -> String:
	return TranslationServer.translate(text)
