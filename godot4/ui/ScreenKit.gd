class_name ScreenKit
extends RefCounted
## Small builders shared by full screens (production, research, ...), so
## they look and behave alike.

## The game's own button art for screens, by their title key (as GG's map
## buttons show them).
const HEADER_ICONS := {
	"PRODUCTION_WND_TITLE": "icons/buttons/production.png",
	"RESEARCH_WND_TITLE": "icons/buttons/research.png",
	"MAP_BTN_GOVERNMENT": "icons/buttons/government.png",
	"MAP_BTN_DESIGN": "icons/buttons/design.png",
	"MAP_BTN_OBJECTS": "icons/buttons/objects.png",
	"EMPIRES_TITLE": "icons/buttons/empires.png",
	"COMBAT_REPORT_TITLE": "icons/combat.png",
	"MESSAGES_PANEL_TITLE": "icons/buttons/messages.png",
	"MAP_BTN_PEDIA": "icons/buttons/pedia.png",
}


static func label(text: String, variation := "") -> Label:
	var result := Label.new()
	# Callers translate; names and numbers must not go through the stringtable
	# (the label has no parent yet to inherit this from).
	result.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	result.text = text
	result.theme_type_variation = variation
	return result


## Fixed-size art icon; empty placeholder when the file is missing.
## A section caption: \a text in the display face's spaced capitals
## ("SectionCaps").
static func section(text: String) -> Label:
	var caption := label(text, "SectionCaps")
	caption.uppercase = true
	return caption


static func icon(path: String, size: int = -1, fallback: Texture2D = null) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = FOArt.icon(path)
	if rect.texture == null:
		rect.texture = fallback
	var side := size if size > 0 else FOUi.tokens.icon_large
	rect.custom_minimum_size = Vector2(side, side)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect


static func small_button(text: String, tooltip_key: String, enabled := true) -> Button:
	var button := Button.new()
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.text = text
	button.theme_type_variation = "GhostButton"
	button.tooltip_text = TranslationServer.translate(tooltip_key)
	button.disabled = not enabled
	return button


## Vertical list that fills its column.
static func list() -> VBoxContainer:
	var result := VBoxContainer.new()
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result


## Scroll container for \a content that expands vertically and keeps rows
## clear of the scrollbar.
static func scrolling(content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_top", "margin_bottom"]:
		gutter.add_theme_constant_override(side, 0)
	gutter.add_theme_constant_override("margin_right", FOUi.tokens.space_4)
	gutter.add_child(content)
	scroll.add_child(gutter)
	return scroll


## Screen header: title, an info label (returned) and a close button.
static func header(parent: Control, title_key: String, on_close: Callable) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	if HEADER_ICONS.has(title_key):
		var heading_icon := icon(HEADER_ICONS[title_key], FOUi.tokens.icon + FOUi.tokens.space_1)
		heading_icon.name = "HeaderIcon"
		row.add_child(heading_icon)
	var title := label(TranslationServer.translate(title_key), "HeadingLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var info := label("", "SecondaryLabel")
	info.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(info)
	var close := small_button("✕", "PANEL_CLOSE")
	close.pressed.connect(on_close)
	row.add_child(close)
	return info


static func turns_text(turns: int) -> String:
	if turns < 0:
		return TranslationServer.translate("PRODUCTION_NEVER")
	if turns == 1:
		return TranslationServer.translate("MAP_ROUTE_ETA_ONE")
	return TranslationServer.translate("MAP_ROUTE_ETA").replace("%1%", str(turns))


## Show that what is dragged would go before \a card (a queue card): an
## accent outline with a thick top; its siblings lose theirs.
static func mark_drop_target(card: Control) -> void:
	var parent := card.get_parent()
	if parent:
		for sibling in parent.get_children():
			if sibling != card:
				_unmark(sibling)
	if card.has_meta("drop_mark"):
		return
	# The card's own style to put back (false for none: a null meta is no
	# meta at all).
	var previous: Variant = (
		card.get_theme_stylebox("panel") if card.has_theme_stylebox_override("panel") else false
	)
	card.set_meta("drop_mark", previous)
	var base := card.get_theme_stylebox("panel")
	var style: StyleBoxFlat = base.duplicate() if base is StyleBoxFlat else StyleBoxFlat.new()
	style.border_color = FOUi.tokens.accent
	style.set_border_width_all(FOUi.tokens.border_width)
	style.border_width_top = FOUi.tokens.focus_width + FOUi.tokens.border_width
	card.add_theme_stylebox_override("panel", style)


## Drop the marks mark_drop_target() left in \a container (a drag ended).
static func clear_drop_marks(container: Node) -> void:
	for child in container.get_children():
		_unmark(child)


static func _unmark(node: Node) -> void:
	if not node.has_meta("drop_mark"):
		return
	var previous: Variant = node.get_meta("drop_mark")
	node.remove_meta("drop_mark")
	if previous is StyleBox:
		node.add_theme_stylebox_override("panel", previous)
	else:
		node.remove_theme_stylebox_override("panel")


static func clear(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


## Translation of \a key, or a readable form of the key itself when the
## stringtable has no entry (e.g. "PC_GENERAL" -> "General").
static func tr_or_name(key: String) -> String:
	var text := TranslationServer.translate(key)
	if not text.begins_with("ERROR: "):
		return text
	var parts := key.split("_")
	if parts.size() > 1 and parts[0].length() <= 3:
		parts.remove_at(0)
	return " ".join(parts).capitalize()


## A link to Pedia article \a arg of \a kind, showing \a text; clicking it
## calls \a on_link(kind, arg).
static func pedia_link(kind: String, arg: String, text: String, on_link: Callable) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.text = FORichText.to_bbcode("<%s %s>%s</%s>" % [kind, arg, text, kind])
	label.meta_clicked.connect(
		func(meta: Variant):
			var link := FORichText.parse_link(str(meta))
			on_link.call(link["kind"], link["arg"])
	)
	return label
