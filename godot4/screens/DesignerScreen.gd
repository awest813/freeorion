class_name DesignerScreen
extends PanelContainer
## Ship designer: pick a hull (or start from an existing design), fill its
## slots with parts, see the stats update, name it and create it.
## Slots sit on the hull art at their positions; they're labelled with their
## type as well as coloured. Select a slot, then click a part (or click a
## part to fill the first free slot that fits); right-click a slot to empty
## it.

signal close_requested

const SLOT_SIZE := 56
const SIDE_WIDTH := 300
const STATS := [
	["attack", "DESIGNER_STAT_ATTACK"],
	["structure", "DESIGNER_STAT_STRUCTURE"],
	["shields", "DESIGNER_STAT_SHIELDS"],
	["speed", "DESIGNER_STAT_SPEED"],
	["fuel", "DESIGNER_STAT_FUEL"],
	["detection", "DESIGNER_STAT_DETECTION"],
	["stealth", "DESIGNER_STAT_STEALTH"],
	["colony", "DESIGNER_STAT_COLONY"],
	["troops", "DESIGNER_STAT_TROOPS"],
	["cost", "DESIGNER_STAT_COST"],
	["turns", "DESIGNER_STAT_TURNS"],
]

var source: Variant = DesignerSource.new()

var hull_name := ""
var parts := PackedStringArray()
var selected_slot := -1

var _hulls: Array = []
var _parts: Array = []
var _status: Label
var _hull_list: VBoxContainer
var _design_list: VBoxContainer
var _art: TextureRect
var _slot_layer: Control
var _name: LineEdit
var _stats: GridContainer
var _validity: Label
var _create: Button
var _part_class: OptionButton
var _fits_only: CheckBox
var _search: LineEdit
var _part_list: VBoxContainer


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "BackgroundPanel"
	_build()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	_hulls = source.get_hulls()
	_parts = source.get_parts()
	_rebuild_hull_list()
	_rebuild_design_list()
	var classes := {}
	for part: Dictionary in _parts:
		classes[part.get("class", "")] = true
	_part_class.clear()
	_part_class.add_item(tr("PRODUCTION_FILTER_ALL"))
	_part_class.set_item_metadata(0, "")
	for part_class in classes.keys():
		_part_class.add_item(ScreenKit.tr_or_name(part_class))
		_part_class.set_item_metadata(_part_class.item_count - 1, part_class)
	if hull_name.is_empty() and not _hulls.is_empty():
		select_hull(_hulls[0]["name"])
	else:
		_refresh_design()


## Start a design on \a name with empty slots.
func select_hull(name_key: String) -> void:
	var hull := _hull(name_key)
	if hull.is_empty():
		return
	hull_name = name_key
	parts = PackedStringArray()
	parts.resize(hull.get("slots", []).size())
	selected_slot = -1
	# The big design art, or the small hull icon when a hull has none.
	var art := FOArt.icon(hull.get("graphic", ""))
	_art.texture = art if art else FOArt.icon(hull.get("icon", ""))
	_refresh_design()


## Load an existing design into the editor.
func load_design(design: Dictionary) -> void:
	select_hull(design.get("hull", ""))
	var design_parts: PackedStringArray = design.get("parts", PackedStringArray())
	for i in mini(parts.size(), design_parts.size()):
		parts[i] = design_parts[i]
	_name.text = design.get("name", "") + " " + tr("DESIGNER_COPY_SUFFIX")
	_refresh_design()


## Put \a part_name into the selected slot, or the first free slot it fits.
func place_part(part_name: String) -> bool:
	var slot := selected_slot
	if slot < 0 or not part_fits(part_name, slot):
		slot = -1
		for i in parts.size():
			if parts[i].is_empty() and part_fits(part_name, i):
				slot = i
				break
	if slot < 0:
		_status.text = tr("DESIGNER_NO_SLOT")
		return false
	parts[slot] = part_name
	_refresh_design()
	return true


func clear_slot(slot: int) -> void:
	if slot >= 0 and slot < parts.size():
		parts[slot] = ""
		_refresh_design()


func part_fits(part_name: String, slot: int) -> bool:
	var slots: Array = _hull(hull_name).get("slots", [])
	if slot < 0 or slot >= slots.size():
		return false
	return slots[slot]["type"] in _part(part_name).get("mountable", PackedStringArray())


func _build() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", FOUi.tokens.space_6)
	margin.add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = SIDE_WIDTH
	columns.add_child(left)
	left.add_child(ScreenKit.label(tr("DESIGNER_HULLS"), "TitleLabel"))
	_hull_list = ScreenKit.list()
	left.add_child(ScreenKit.scrolling(_hull_list))
	left.add_child(ScreenKit.label(tr("DESIGNER_DESIGNS"), "TitleLabel"))
	_design_list = ScreenKit.list()
	left.add_child(ScreenKit.scrolling(_design_list))

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(center)
	_status = ScreenKit.header(center, "MAP_BTN_DESIGN", close_requested.emit)
	var stage := Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size.y = 260
	center.add_child(stage)
	_art = TextureRect.new()
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stage.add_child(_art)
	_slot_layer = Control.new()
	_slot_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_slot_layer)
	stage.resized.connect(_layout_slots)
	center.add_child(ScreenKit.label(tr("DESIGNER_SLOT_HINT"), "SmallLabel"))

	var details := HBoxContainer.new()
	details.add_theme_constant_override("separation", FOUi.tokens.space_6)
	center.add_child(details)
	_stats = GridContainer.new()
	_stats.columns = 4
	details.add_child(_stats)
	var create_box := VBoxContainer.new()
	create_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_child(create_box)
	_name = LineEdit.new()
	_name.placeholder_text = tr("DESIGNER_NAME")
	_name.text_changed.connect(func(_t): _update_create())
	create_box.add_child(_name)
	_validity = ScreenKit.label("", "SmallLabel")
	_validity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	create_box.add_child(_validity)
	_create = Button.new()
	_create.text = tr("DESIGNER_CREATE")
	_create.theme_type_variation = "PrimaryButton"
	_create.pressed.connect(_on_create_pressed)
	create_box.add_child(_create)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = SIDE_WIDTH
	columns.add_child(right)
	right.add_child(ScreenKit.label(tr("DESIGN_WND_PART_PALETTE_TITLE"), "TitleLabel"))
	_part_class = OptionButton.new()
	_part_class.item_selected.connect(func(_i): _rebuild_part_list())
	right.add_child(_part_class)
	_fits_only = CheckBox.new()
	_fits_only.text = tr("DESIGNER_FITS")
	_fits_only.toggled.connect(func(_on): _rebuild_part_list())
	right.add_child(_fits_only)
	_search = LineEdit.new()
	_search.placeholder_text = tr("PRODUCTION_SEARCH")
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _rebuild_part_list())
	right.add_child(_search)
	_part_list = ScreenKit.list()
	right.add_child(ScreenKit.scrolling(_part_list))


func _rebuild_hull_list() -> void:
	ScreenKit.clear(_hull_list)
	for hull: Dictionary in _hulls:
		var counts := {"external": 0, "internal": 0, "core": 0}
		for slot: Dictionary in hull.get("slots", []):
			counts[slot["type"]] = counts.get(slot["type"], 0) + 1
		var summary: PackedStringArray = []
		for slot_type in ["external", "internal", "core"]:
			if counts[slot_type] > 0:
				summary.push_back(
					(
						"%d %s"
						% [
							counts[slot_type],
							tr("DESIGNER_SLOT_" + slot_type.to_upper()).to_lower()
						]
					)
				)
		var button := _list_button(tr(hull["name"]), " · ".join(summary), hull.get("icon", ""))
		button.pressed.connect(func(): select_hull(hull["name"]))
		_hull_list.add_child(button)


func _rebuild_design_list() -> void:
	ScreenKit.clear(_design_list)
	for design: Dictionary in source.get_designs():
		var button := _list_button(design.get("name", ""), tr(design.get("hull", "")), "")
		button.pressed.connect(load_design.bind(design))
		_design_list.add_child(button)


func _rebuild_part_list() -> void:
	ScreenKit.clear(_part_list)
	var part_class: String = (
		str(_part_class.get_item_metadata(_part_class.selected))
		if _part_class.selected >= 0
		else ""
	)
	var needle := _search.text.strip_edges().to_lower()
	for part: Dictionary in _parts:
		var part_name: String = part["name"]
		if not part_class.is_empty() and part.get("class") != part_class:
			continue
		if not needle.is_empty() and not tr(part_name).to_lower().contains(needle):
			continue
		if (
			_fits_only.button_pressed
			and selected_slot >= 0
			and not part_fits(part_name, selected_slot)
		):
			continue
		var mountable := ", ".join(
			Array(part.get("mountable", PackedStringArray())).map(
				func(t): return tr("DESIGNER_SLOT_" + t.to_upper())
			)
		)
		var button := _list_button(
			tr(part_name),
			(
				"%s · %s · %s"
				% [tr(part.get("class", "")), _number(part.get("capacity", 0.0)), mountable]
			),
			part.get("icon", "")
		)
		button.pressed.connect(func(): place_part(part_name))
		_part_list.add_child(button)


func _refresh_design() -> void:
	_status.text = ""
	_build_slots()
	_layout_slots()
	_rebuild_part_list()
	var stats: Dictionary = (
		source.evaluate(hull_name, parts) if not hull_name.is_empty() else {"valid": false}
	)
	ScreenKit.clear(_stats)
	for stat in STATS:
		_stats.add_child(ScreenKit.label(tr(stat[1]), "SecondaryLabel"))
		_stats.add_child(
			ScreenKit.label(_number(stats.get(stat[0], 0.0)) if stats.get("valid") else "–")
		)
	_validity.text = "" if stats.get("valid", false) else tr("DESIGNER_INVALID")
	_create.set_meta("valid", stats.get("valid", false))
	_update_create()


func _build_slots() -> void:
	ScreenKit.clear(_slot_layer)
	var slots: Array = _hull(hull_name).get("slots", [])
	for i in slots.size():
		var slot: Dictionary = slots[i]
		var button := Button.new()
		button.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		button.size = button.custom_minimum_size
		button.toggle_mode = true
		button.button_pressed = i == selected_slot
		button.expand_icon = true
		button.set_meta("slot", i)
		var type_label := tr("DESIGNER_SLOT_" + slot["type"].to_upper())
		if parts[i].is_empty():
			button.text = type_label.substr(0, 3)
			button.add_theme_font_size_override("font_size", FOUi.tokens.font_size_small)
		else:
			button.icon = FOArt.icon(_part(parts[i]).get("icon", ""))
		button.tooltip_text = (
			"%s\n%s" % [type_label, tr(parts[i]) if not parts[i].is_empty() else ""]
		)
		button.add_theme_stylebox_override("normal", _slot_style(slot["type"], false))
		button.add_theme_stylebox_override("hover", _slot_style(slot["type"], true))
		button.add_theme_stylebox_override("pressed", _slot_style(slot["type"], true))
		button.gui_input.connect(_on_slot_input.bind(i))
		button.pressed.connect(_on_slot_pressed.bind(i))
		_slot_layer.add_child(button)


# Slots at their positions on the drawn hull art (x, y are 0..1 of the art).
func _layout_slots() -> void:
	var area := _art.size
	var texture := _art.texture
	var drawn := Rect2(Vector2.ZERO, area)
	if texture:
		var ratio := minf(area.x / texture.get_width(), area.y / texture.get_height())
		var art_size := texture.get_size() * ratio
		drawn = Rect2((area - art_size) * 0.5, art_size)
	var slots: Array = _hull(hull_name).get("slots", [])
	for button in _slot_layer.get_children():
		var slot: Dictionary = slots[button.get_meta("slot")]
		var at := drawn.position + Vector2(slot["x"], slot["y"]) * drawn.size
		button.position = (at - Vector2(SLOT_SIZE, SLOT_SIZE) * 0.5).round()


func _slot_style(slot_type: String, highlight: bool) -> StyleBoxFlat:
	var t: FOTokens = FOUi.tokens
	var color: Color = {"external": t.accent, "internal": t.info, "core": t.warning}.get(
		slot_type, t.border
	)
	var style := FOThemeBuilder.box(t, Color(t.surface, 0.85), color, 2, 2)
	style.set_border_width_all(t.focus_width if highlight else t.border_width + 1)
	return style


func _on_slot_pressed(slot: int) -> void:
	selected_slot = slot if selected_slot != slot else -1
	for button in _slot_layer.get_children():
		button.set_pressed_no_signal(button.get_meta("slot") == selected_slot)
	_rebuild_part_list()


func _on_slot_input(event: InputEvent, slot: int) -> void:
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
		clear_slot(slot)


func _update_create() -> void:
	_create.disabled = not _create.get_meta("valid", false) or _name.text.strip_edges().is_empty()


func _on_create_pressed() -> void:
	var design_id: int = source.create(_name.text.strip_edges(), hull_name, parts)
	if design_id < 0:
		_status.text = tr("DESIGNER_REFUSED")
		return
	_status.text = tr("DESIGNER_CREATED").replace("%1%", _name.text.strip_edges())
	_rebuild_design_list()


func _list_button(title: String, detail: String, icon_path: String) -> Button:
	var button := Button.new()
	button.text = "%s\n%s" % [title, detail]
	button.icon = FOArt.icon(icon_path)
	button.expand_icon = false
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.theme_type_variation = "GhostButton"
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_constant_override("icon_max_width", FOUi.tokens.icon_large)
	return button


func _hull(name_key: String) -> Dictionary:
	for hull: Dictionary in _hulls:
		if hull["name"] == name_key:
			return hull
	return {}


func _part(name_key: String) -> Dictionary:
	for part: Dictionary in _parts:
		if part["name"] == name_key:
			return part
	return {}


static func _number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
