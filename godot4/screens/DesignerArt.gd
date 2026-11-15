class_name DesignerArt
extends RefCounted
## The ship designer's art, from the game's own (as GG's design window):
## slots drawn in their type's shape (external a cross, internal an
## octagon, core a circle), parts on a background of the shape of the slots
## they fit, the generic part picture for parts without one, and what
## follows the pointer while a part is dragged.

const PARTS_DIR := "icons/ship_parts/"
## Slot type -> the slot's shape.
const SLOT_ART := {
	"external": PARTS_DIR + "external_slot.png",
	"internal": PARTS_DIR + "internal_slot.png",
	"core": PARTS_DIR + "core_slot.png",
}
## For parts with no picture of their own (GG shows the same).
const GENERIC_PART := PARTS_DIR + "generic_part.png"
## Badge size in pixels: the part on its mount shape.
const BADGE_SIZE := 64
## The part's picture inside the badge, as a share of it.
const BADGE_INSET := 0.8

static var _badges := {}


## The picture of \a part ({icon}), or the generic one.
static func part_texture(part: Dictionary) -> Texture2D:
	var texture := FOArt.icon(part.get("icon", ""))
	return texture if texture else FOArt.icon(GENERIC_PART)


## The background for a part mounting in \a mountable slot types: external,
## internal, both ("independent") or core, as GG's part backgrounds.
static func mount_background(mountable: PackedStringArray) -> String:
	var outside := mountable.has("external")
	var inside := mountable.has("internal")
	if outside and inside:
		return PARTS_DIR + "independent_part.png"
	if outside:
		return PARTS_DIR + "external_part.png"
	if inside:
		return PARTS_DIR + "internal_part.png"
	if mountable.has("core"):
		return PARTS_DIR + "core_part.png"
	return ""


## \a part's picture on the shape of the slots it fits (cached per part),
## so the list shows where each part goes at a glance.
static func part_badge(part: Dictionary) -> Texture2D:
	var key: String = part.get("name", "")
	if _badges.has(key):
		return _badges[key]
	var badge := _compose(
		_image(FOArt.icon(mount_background(part.get("mountable", PackedStringArray())))),
		_image(part_texture(part))
	)
	_badges[key] = badge
	return badge


## The colour slots of \a slot_type are drawn in (with their shape, so
## colour isn't the only clue).
static func slot_color(slot_type: String) -> Color:
	var t: FOTokens = FOUi.tokens
	return {"external": t.accent, "internal": t.positive, "core": t.warning}.get(
		slot_type, t.text_secondary
	)


## A slot of \a slot_type, \a size pixels: its shape, and \a part_texture
## in it when it holds a part. The button has no box of its own; hovering
## lightens the shape and the selected one (pressed) is ringed.
static func slot_button(slot_type: String, part: Texture2D, size: int) -> Button:
	var t: FOTokens = FOUi.tokens
	var button := Button.new()
	button.set_meta("slot_type", slot_type)
	button.custom_minimum_size = Vector2(size, size)
	button.size = button.custom_minimum_size
	button.toggle_mode = true
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, empty)
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = t.focus_ring
	ring.set_border_width_all(t.focus_width)
	ring.set_corner_radius_all(size / 2)
	ring.set_expand_margin_all(t.space_1)
	button.add_theme_stylebox_override("pressed", ring)
	button.add_theme_stylebox_override("hover_pressed", ring)
	var shape := TextureRect.new()
	shape.name = "Shape"
	shape.texture = FOArt.icon(SLOT_ART.get(slot_type, ""))
	shape.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shape.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shape.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shape.self_modulate = slot_color(slot_type)
	button.add_child(shape)
	if part:
		var picture := TextureRect.new()
		picture.name = "Part"
		picture.texture = part
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var inset := size * 0.14
		picture.offset_left = inset
		picture.offset_top = inset
		picture.offset_right = -inset
		picture.offset_bottom = -inset
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(picture)
	button.mouse_entered.connect(func(): shape.self_modulate = _slot_shade(button).lightened(0.35))
	button.mouse_exited.connect(func(): shape.self_modulate = _slot_shade(button))
	return button


## A row naming the shape of each of \a slot_types (in that order), for
## under the hull.
static func legend(slot_types: Array) -> HBoxContainer:
	var t: FOTokens = FOUi.tokens
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", t.space_4)
	for slot_type: String in slot_types:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", t.space_1)
		var shape := TextureRect.new()
		shape.texture = FOArt.icon(SLOT_ART.get(slot_type, ""))
		shape.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shape.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		shape.custom_minimum_size = Vector2.ONE * t.icon_small
		shape.self_modulate = slot_color(slot_type)
		item.add_child(shape)
		item.add_child(
			ScreenKit.label(
				TranslationServer.translate("DESIGNER_SLOT_" + slot_type.to_upper()), "SmallLabel"
			)
		)
		row.add_child(item)
	return row


## Mark slot \a button (from slot_button()) as one the part in hand fits
## (\a fit 1), doesn't fit (-1, faded) or neither (0).
static func set_slot_fit(button: Control, fit: int) -> void:
	button.set_meta("fit", fit)
	button.modulate.a = 0.35 if fit < 0 else 1.0
	var shape: CanvasItem = button.get_node_or_null("Shape")
	if shape:
		shape.self_modulate = _slot_shade(button)


# The shape's colour for slot \a button: lighter when the part in hand fits.
static func _slot_shade(button: Control) -> Color:
	var color := slot_color(button.get_meta("slot_type", ""))
	return color.lightened(0.45) if button.get_meta("fit", 0) > 0 else color


## A soft light for behind the hull art, from the centre outwards.
static func stage_backdrop() -> TextureRect:
	var t: FOTokens = FOUi.tokens
	var gradient := Gradient.new()
	gradient.set_color(0, Color(t.surface_overlay, 0.9))
	gradient.set_color(1, Color(t.surface_overlay, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 128
	var backdrop := TextureRect.new()
	backdrop.texture = texture
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return backdrop


## What follows the pointer while \a texture's part is dragged.
static func drag_preview(texture: Texture2D, size: int) -> Control:
	var preview := TextureRect.new()
	preview.texture = texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size = Vector2(size, size)
	preview.position = -preview.size / 2.0
	preview.modulate.a = 0.85
	var holder := Control.new()
	holder.add_child(preview)
	return holder


static func _image(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null:
		return null
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image


static func _compose(background: Image, picture: Image) -> Texture2D:
	var badge := Image.create(BADGE_SIZE, BADGE_SIZE, false, Image.FORMAT_RGBA8)
	if background:
		background.resize(BADGE_SIZE, BADGE_SIZE, Image.INTERPOLATE_LANCZOS)
		badge.blend_rect(background, Rect2i(0, 0, BADGE_SIZE, BADGE_SIZE), Vector2i.ZERO)
	if picture:
		var inner := int(BADGE_SIZE * BADGE_INSET)
		picture.resize(inner, inner, Image.INTERPOLATE_LANCZOS)
		var at := Vector2i.ONE * ((BADGE_SIZE - inner) / 2)
		badge.blend_rect(picture, Rect2i(0, 0, inner, inner), at)
	return ImageTexture.create_from_image(badge)
