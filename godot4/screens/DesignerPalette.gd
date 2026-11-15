class_name DesignerPalette
extends VBoxContainer
## The ship designer's parts, as GG's part palette: availability filters
## (available, unavailable, obsolete), redundant parts hidden unless asked
## for, part classes ticked on or off, parts fitting the selected slot, and a
## search. Click a part to place it (Shift: in every free slot it fits),
## drag it onto a slot, right-click for its Pedia article, filling every
## free slot, or marking it obsolete. Parts dragged off the hull back here
## are removed. Also the designer's hull, part and design tooltips.

signal part_chosen(part_name: String, fill_all: bool)
signal slot_cleared(slot: int)
signal pedia_requested(kind: String, article_name: String)
## A part was marked obsolete or not.
signal obsolete_changed

enum PartAction { PEDIA, FILL, OBSOLETE }

## GG's availability filters: key, label key.
const AVAILABILITY := [
	["available", "PRODUCTION_WND_AVAILABILITY_AVAILABLE"],
	["unavailable", "PRODUCTION_WND_AVAILABILITY_UNAVAILABLE"],
	["obsolete", "PRODUCTION_WND_AVAILABILITY_OBSOLETE"],
]
const PART_DRAG := "fo_part"
const SLOT_DRAG := "fo_slot"

## Every part known (available or not): get_parts(true).
var parts: Array = []
## Availabilities shown: key -> bool.
var shown := {"available": true, "unavailable": false, "obsolete": false}
## Show parts another part does better for no more (GG's "Redundant").
var show_redundant := false
## Part classes switched off: class -> true.
var hidden_classes := {}
## (part name) -> bool: whether it fits the selected slot; null when no slot
## is selected.
var fits: Callable = Callable()
var source: Variant = null

var _availability := {}
var _redundant: Button
var _classes: MenuButton
var _fits_only: CheckBox
var _search: LineEdit
var _part_list: VBoxContainer
var _menu: PopupMenu
var _menu_part := ""


func _init() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(ScreenKit.label(tr("DESIGN_WND_PART_PALETTE_TITLE"), "TitleLabel"))
	var filters := availability_row(shown, rebuild)
	add_child(filters)
	_availability = filters.get_meta("toggles")
	_redundant = _toggle(tr("PRODUCTION_WND_REDUNDANT"), show_redundant)
	_redundant.tooltip_text = tr("DESIGNER_REDUNDANT_TIP")
	_redundant.toggled.connect(
		func(on: bool):
			show_redundant = on
			rebuild()
	)
	filters.add_child(_redundant)
	var row := HBoxContainer.new()
	add_child(row)
	_classes = MenuButton.new()
	_classes.text = tr("DESIGNER_PART_CLASSES")
	_classes.flat = false
	_classes.about_to_popup.connect(_fill_classes)
	_classes.get_popup().hide_on_checkable_item_selection = false
	_classes.get_popup().index_pressed.connect(_on_class_pressed)
	row.add_child(_classes)
	_fits_only = CheckBox.new()
	_fits_only.text = tr("DESIGNER_FITS")
	_fits_only.toggled.connect(func(_on): rebuild())
	row.add_child(_fits_only)
	_search = LineEdit.new()
	_search.placeholder_text = tr("PRODUCTION_SEARCH")
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): rebuild())
	add_child(_search)
	_part_list = ScreenKit.list()
	var scroll := ScreenKit.scrolling(_part_list)
	# Parts dragged off the hull are removed.
	scroll.set_drag_forwarding(
		Callable(),
		func(_at, data): return data is Dictionary and data.get("type", "") == SLOT_DRAG,
		func(_at, data): slot_cleared.emit(data["slot"])
	)
	add_child(scroll)
	_menu = PopupMenu.new()
	_menu.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)


## The parts shown with the filters as they are.
func visible_parts() -> Array:
	var redundant := {} if show_redundant else redundant_parts(parts)
	var needle := _search.text.strip_edges().to_lower()
	var result := []
	for part: Dictionary in parts:
		var part_name: String = part["name"]
		if not passes(part, shown) or redundant.has(part_name):
			continue
		if hidden_classes.has(part.get("class", "")):
			continue
		if not needle.is_empty() and not tr(part_name).to_lower().contains(needle):
			continue
		if _fits_only.button_pressed and fits.is_valid() and not fits.call(part_name):
			continue
		result.push_back(part)
	return result


func rebuild() -> void:
	ScreenKit.clear(_part_list)
	for part: Dictionary in visible_parts():
		_part_list.add_child(_part_row(part))
	if _part_list.get_child_count() == 0:
		_part_list.add_child(ScreenKit.label(tr("DESIGNER_NO_PARTS"), "SecondaryLabel"))


## Toggles for GG's availability filters, changing \a state (key -> bool)
## and calling \a changed; the row's "toggles" meta maps key -> Button.
static func availability_row(state: Dictionary, changed: Callable) -> HFlowContainer:
	var row := HFlowContainer.new()
	var toggles := {}
	for entry in AVAILABILITY:
		var toggle := _toggle(TranslationServer.translate(entry[1]), state[entry[0]])
		toggle.toggled.connect(
			func(on: bool):
				state[entry[0]] = on
				changed.call()
		)
		row.add_child(toggle)
		toggles[entry[0]] = toggle
	row.set_meta("toggles", toggles)
	return row


## "obsolete", "unavailable" or "available".
static func availability_of(item: Dictionary) -> String:
	if item.get("obsolete", false):
		return "obsolete"
	return "available" if item.get("available", true) else "unavailable"


static func passes(item: Dictionary, state: Dictionary) -> bool:
	return state.get(availability_of(item), true)


## Parts made redundant by another available part of the same class that
## fits wherever they fit, does more and costs no more (GG's culling with
## its default ratios): name -> true.
static func redundant_parts(part_list: Array) -> Dictionary:
	var result := {}
	for part: Dictionary in part_list:
		# Parts marked obsolete are the player's call, not culled.
		if not part.get("available", true) or part.get("obsolete", false):
			continue
		var capacity: float = part.get("capacity", 0.0)
		if capacity < 0.0:
			continue
		for better: Dictionary in part_list:
			if (
				better.get("available", true)
				and better.get("class", "") == part.get("class", "")
				and better.get("capacity", 0.0) > capacity
				and better.get("cost", 0.0) <= part.get("cost", 0.0)
				and _mounts_wherever(better, part)
			):
				result[part["name"]] = true
				break
	return result


## A part's tooltip: class, capacity, cost, slots, availability, text.
static func part_tooltip(part: Dictionary) -> String:
	var t := TranslationServer.translate
	var lines: PackedStringArray = [t.call(part.get("name", ""))]
	(
		lines
		. push_back(
			(
				"%s · %s %s · %s %s"
				% [
					ScreenKit.tr_or_name(part.get("class", "")),
					t.call("DESIGNER_CAPACITY"),
					_number(part.get("capacity", 0.0)),
					_number(part.get("cost", 0.0)),
					t.call("DESIGNER_PP"),
				]
			)
		)
	)
	var mountable := ", ".join(
		Array(part.get("mountable", PackedStringArray())).map(
			func(slot_type): return t.call("DESIGNER_SLOT_" + slot_type.to_upper())
		)
	)
	lines.push_back(t.call("DESIGNER_MOUNTS").replace("%1%", mountable))
	_add_state(lines, part)
	_add_description(lines, part)
	return "\n".join(lines)


## A hull's tooltip: structure, speed, fuel, stealth, slots, cost, text.
static func hull_tooltip(hull: Dictionary) -> String:
	var t := TranslationServer.translate
	var lines: PackedStringArray = [t.call(hull.get("name", ""))]
	(
		lines
		. push_back(
			(
				"%s %s · %s %s · %s %s · %s %s"
				% [
					t.call("DESIGNER_STAT_STRUCTURE"),
					_number(hull.get("structure", 0.0)),
					t.call("DESIGNER_STAT_SPEED"),
					_number(hull.get("speed", 0.0)),
					t.call("DESIGNER_STAT_FUEL"),
					_number(hull.get("fuel", 0.0)),
					t.call("DESIGNER_STAT_STEALTH"),
					_number(hull.get("stealth", 0.0)),
				]
			)
		)
	)
	lines.push_back(
		"%s %s · %s" % [_number(hull.get("cost", 0.0)), t.call("DESIGNER_PP"), slot_summary(hull)]
	)
	_add_state(lines, hull)
	_add_description(lines, hull)
	return "\n".join(lines)


## A design's tooltip: hull, parts by count, whether it can be built, text.
static func design_tooltip(design: Dictionary) -> String:
	var t := TranslationServer.translate
	var lines: PackedStringArray = [design.get("name", ""), t.call(design.get("hull", ""))]
	var counts := {}
	for part_name: String in design.get("parts", PackedStringArray()):
		if not part_name.is_empty():
			counts[part_name] = counts.get(part_name, 0) + 1
	for part_name: String in counts:
		lines.push_back("%d × %s" % [counts[part_name], t.call(part_name)])
	if not design.get("producible", true):
		lines.push_back(t.call("DESIGNER_CANT_BUILD"))
	var description: String = design.get("description", "")
	if not description.is_empty() and not description.begins_with("ERROR"):
		lines.push_back("")
		lines.push_back(FORichText.plain_text(description))
	return "\n".join(lines)


## "3 external · 1 internal" for \a hull's slots.
static func slot_summary(hull: Dictionary) -> String:
	var counts := {"external": 0, "internal": 0, "core": 0}
	for slot: Dictionary in hull.get("slots", []):
		counts[slot["type"]] = counts.get(slot["type"], 0) + 1
	var summary: PackedStringArray = []
	for slot_type in ["external", "internal", "core"]:
		if counts[slot_type] > 0:
			var label := TranslationServer.translate("DESIGNER_SLOT_" + slot_type.to_upper())
			summary.push_back("%d %s" % [counts[slot_type], String(label).to_lower()])
	return " · ".join(summary)


func _part_row(part: Dictionary) -> Button:
	var part_name: String = part["name"]
	var mountable := ", ".join(
		Array(part.get("mountable", PackedStringArray())).map(
			func(slot_type): return tr("DESIGNER_SLOT_" + slot_type.to_upper())
		)
	)
	var button := list_button(
		tr(part_name),
		"%s · %s · %s" % [tr(part.get("class", "")), _number(part.get("capacity", 0.0)), mountable],
		part.get("icon", "")
	)
	button.tooltip_text = part_tooltip(part)
	if availability_of(part) != "available":
		button.modulate.a = 0.6
	button.pressed.connect(func(): part_chosen.emit(part_name, Input.is_key_pressed(KEY_SHIFT)))
	button.gui_input.connect(
		func(event: InputEvent):
			var click := event as InputEventMouseButton
			if click and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
				open_part_menu(part_name, button.get_screen_position() + click.position)
				button.accept_event()
	)
	button.set_drag_forwarding(
		func(_at): return {"type": PART_DRAG, "name": part_name}, Callable(), Callable()
	)
	return button


## The right-click menu of \a part_name: Pedia, fill free slots, obsolete.
func open_part_menu(part_name: String, at: Vector2) -> PopupMenu:
	_menu_part = part_name
	_menu.clear()
	_menu.add_item(tr("PEDIA_OPEN"), PartAction.PEDIA)
	_menu.add_item(tr("DESIGNER_FILL_SLOTS"), PartAction.FILL)
	var part := _find(part_name)
	_menu.add_item(
		tr(
			(
				"DESIGNER_UNMARK_OBSOLETE"
				if part.get("obsolete", false)
				else "DESIGN_WND_OBSOLETE_PART"
			)
		),
		PartAction.OBSOLETE
	)
	_menu.popup(Rect2i(Vector2i(at), Vector2i.ZERO))
	return _menu


func _on_menu(id: int) -> void:
	match id:
		PartAction.PEDIA:
			pedia_requested.emit("shippart", _menu_part)
		PartAction.FILL:
			part_chosen.emit(_menu_part, true)
		PartAction.OBSOLETE:
			var part := _find(_menu_part)
			var obsolete: bool = not part.get("obsolete", false)
			if source and source.set_part_obsolete(_menu_part, obsolete):
				part["obsolete"] = obsolete
				obsolete_changed.emit()
				rebuild()


func _fill_classes() -> void:
	var popup := _classes.get_popup()
	popup.clear()
	var classes := {}
	for part: Dictionary in parts:
		classes[part.get("class", "")] = true
	for part_class: String in classes:
		popup.add_check_item(ScreenKit.tr_or_name(part_class))
		popup.set_item_metadata(popup.item_count - 1, part_class)
		popup.set_item_checked(popup.item_count - 1, not hidden_classes.has(part_class))


func _on_class_pressed(index: int) -> void:
	var popup := _classes.get_popup()
	var part_class: String = popup.get_item_metadata(index)
	set_class_shown(part_class, hidden_classes.has(part_class))
	popup.set_item_checked(index, not hidden_classes.has(part_class))


## Show or hide parts of \a part_class.
func set_class_shown(part_class: String, on: bool) -> void:
	if on:
		hidden_classes.erase(part_class)
	else:
		hidden_classes[part_class] = true
	_classes.text = tr("DESIGNER_PART_CLASSES") + (" •" if not hidden_classes.is_empty() else "")
	rebuild()


func _find(part_name: String) -> Dictionary:
	for part: Dictionary in parts:
		if part["name"] == part_name:
			return part
	return {}


static func _mounts_wherever(better: Dictionary, part: Dictionary) -> bool:
	var slots: PackedStringArray = better.get("mountable", PackedStringArray())
	for slot_type in part.get("mountable", PackedStringArray()):
		if not slot_type in slots:
			return false
	return true


static func _add_state(lines: PackedStringArray, item: Dictionary) -> void:
	match availability_of(item):
		"obsolete":
			lines.push_back(TranslationServer.translate("PRODUCTION_WND_AVAILABILITY_OBSOLETE"))
		"unavailable":
			lines.push_back(TranslationServer.translate("PRODUCTION_WND_AVAILABILITY_UNAVAILABLE"))


static func _add_description(lines: PackedStringArray, item: Dictionary) -> void:
	var description: String = item.get("description", "")
	if description.is_empty():
		return
	lines.push_back("")
	lines.push_back(FORichText.plain_text(TranslationServer.translate(description)).left(600))


static func _toggle(text: String, on: bool) -> Button:
	var toggle := Button.new()
	toggle.text = text
	toggle.toggle_mode = true
	toggle.button_pressed = on
	toggle.theme_type_variation = "SegmentButton"
	return toggle


## A list row: icon, title and a detail line.
static func list_button(title: String, detail: String, icon_path: String) -> Button:
	var button := Button.new()
	button.text = "%s\n%s" % [title, detail]
	button.icon = FOArt.icon(icon_path)
	button.expand_icon = false
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.theme_type_variation = "GhostButton"
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_constant_override("icon_max_width", FOUi.tokens.icon_large)
	return button


static func _number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
