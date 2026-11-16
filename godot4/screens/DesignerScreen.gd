class_name DesignerScreen
extends PanelContainer
## Ship designer: pick a hull (or start from an existing design), fill its
## slots with parts, see the stats update (against the design started from),
## name and describe it, and create it, or update the own or saved design
## started from. Why a design can't be made is said (no name, conflicting
## parts, a duplicate of an own design; parts not yet available).
## Designs are listed by kind: yours, put aside (obsolete), premade,
## monsters and saved; yours can be put aside or deleted, premade and saved
## ones added to your empire (all saved ones at once too). Designs that
## can't be built are marked.
## Hulls and parts are filtered as GG's: available, unavailable, obsolete
## (marked so from their right-click menu), redundant parts and part classes
## (DesignerPalette). Slots sit on the hull art at their positions; they're
## labelled with their type as well as coloured. Select a slot, then click a
## part (or click a part to fill the first free slot that fits; Shift: every
## free slot); drag parts onto slots, between slots, or off the hull;
## right-click a slot to empty it.

signal close_requested
signal pedia_requested(kind: String, article_name: String)

## Own designs' menu.
enum DesignAction { RENAME, KEEP, ASIDE, DELETE, PEDIA, TOP, BOTTOM }
## Hulls' menu.
enum HullAction { PEDIA, OBSOLETE }
## The options adding premade or saved designs to each new game.
const START_OPTIONS := {
	"premade": "resource.shipdesign.default.enabled",
	"saved": "resource.shipdesign.saved.enabled",
}
## Drag data type for reordering own designs.
const DESIGN_ORDER_DRAG := "fo_design_order"

const SLOT_SIZE := 56
## Design lists: kind for get_designs(), tab label key.
const DESIGN_KINDS := [
	["empire", "DESIGNER_KIND_EMPIRE"],
	["obsolete", "DESIGNER_KIND_OBSOLETE"],
	["premade", "DESIGNER_KIND_PREMADE"],
	["monster", "DESIGNER_KIND_MONSTER"],
	["saved", "DESIGNER_KIND_SAVED"],
]
## Stats where less is better (their changes are coloured the other way).
const LOWER_IS_BETTER := ["cost", "turns"]
const SIDE_WIDTH := 300
## Stats: key, label key, meter icon (as the game's meters show them).
const STATS := [
	["attack", "DESIGNER_STAT_ATTACK", "damage"],
	["structure", "DESIGNER_STAT_STRUCTURE", "structure"],
	["shields", "DESIGNER_STAT_SHIELDS", "shield"],
	["speed", "DESIGNER_STAT_SPEED", "speed"],
	["fuel", "DESIGNER_STAT_FUEL", "fuel"],
	["detection", "DESIGNER_STAT_DETECTION", "detection"],
	["stealth", "DESIGNER_STAT_STEALTH", "stealth"],
	["colony", "DESIGNER_STAT_COLONY", "colony"],
	["troops", "DESIGNER_STAT_TROOPS", "troops"],
	["cost", "DESIGNER_STAT_COST", "industry"],
	["turns", "DESIGNER_STAT_TURNS", "construction"],
]

var source: Variant = DesignerSource.new()
## Where the "add at game start" choices are kept.
var options: Variant = OptionsSource.new()

var hull_name := ""
var parts := PackedStringArray()
var selected_slot := -1
## Hull availabilities shown: key -> bool.
var hulls_shown := {"available": true, "unavailable": false, "obsolete": false}

var _hulls: Array = []
var _parts: Array = []
var _status: Label
var _hull_list: VBoxContainer
var _design_list: VBoxContainer
var _design_ids: Array = []
var _design_kind: OptionButton
var _compare_label: Label
## The design started from, to compare against and update: {name, stats,
## kind, id, uuid} or {}.
var _baseline := {}
var _art: TextureRect
var _slot_layer: Control
var _legend: Container
var _hull_caption: Label
var _name: LineEdit
var _stats: GridContainer
var _validity: Label
var _create: Button
var _update: Button
var _description: TextEdit
var _palette: DesignerPalette
var _hull_menu: PopupMenu
var _menu_hull := ""


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "BackgroundPanel"
	_build()


# A part dragged: the slots it fits stand out, the others fade (as GG
# lights the slots a dragged part can go into).
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_DRAG_BEGIN:
			var data: Variant = get_viewport().gui_get_drag_data()
			if data is Dictionary and data.get("type", "") == DesignerPalette.PART_DRAG:
				highlight_slots_for(data["name"])
			elif data is Dictionary and data.get("type", "") == DesignerPalette.SLOT_DRAG:
				highlight_slots_for(parts[data["slot"]], data["slot"])
		NOTIFICATION_DRAG_END:
			highlight_slots_for("")


## Show which slots \a part_name fits ("" for none: all as usual); \a
## from is the slot it is dragged from, if any (swaps must fit both ways).
func highlight_slots_for(part_name: String, from := -1) -> void:
	for button: Node in _slot_layer.get_children():
		var slot: int = button.get_meta("slot", -1)
		if part_name.is_empty() or button.is_queued_for_deletion():
			DesignerArt.set_slot_fit(button, 0)
			continue
		var fits := part_fits(part_name, slot)
		if from >= 0 and fits and not parts[slot].is_empty():
			fits = part_fits(parts[slot], from)
		DesignerArt.set_slot_fit(button, 1 if fits or slot == from else -1)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()
	# Delete empties the selected slot (while no text field has the keys).
	var key := event as InputEventKey
	if key and key.pressed and key.keycode in [KEY_DELETE, KEY_BACKSPACE] and selected_slot >= 0:
		clear_slot(selected_slot)
		get_viewport().set_input_as_handled()


func refresh() -> void:
	_hulls = source.get_hulls(true)
	_parts = source.get_parts(true)
	_palette.parts = _parts
	_palette.source = source
	_rebuild_hull_list()
	_rebuild_design_list()
	if hull_name.is_empty() and not _hulls.is_empty():
		var first: Array = _hulls.filter(func(h): return DesignerPalette.passes(h, hulls_shown))
		select_hull((first if not first.is_empty() else _hulls)[0]["name"])
	else:
		_refresh_design()


## Start a design on \a name with empty slots.
func select_hull(name_key: String) -> void:
	var hull := _hull(name_key)
	if hull.is_empty():
		return
	_baseline = {}
	hull_name = name_key
	parts = PackedStringArray()
	parts.resize(hull.get("slots", []).size())
	selected_slot = -1
	# The big design art, or the small hull icon when a hull has none.
	var art := FOArt.icon(hull.get("graphic", ""))
	_art.texture = art if art else FOArt.icon(hull.get("icon", ""))
	_hull_caption.text = "%s  ·  %s" % [tr(name_key), DesignerPalette.slot_summary(hull)]
	_refresh_design()


## Load an existing design into the editor; its stats become the ones the
## new design is compared with.
func load_design(design: Dictionary, kind := "") -> void:
	select_hull(design.get("hull", ""))
	_baseline = {
		"name": design.get("name", ""),
		"stats": source.evaluate(design.get("hull", ""), design.get("parts", PackedStringArray())),
		"kind": kind,
		"id": design.get("id", -1),
		"uuid": design.get("uuid", ""),
	}
	var description: String = design.get("description", "")
	_description.text = "" if description.begins_with("ERROR") else description
	var design_parts: PackedStringArray = design.get("parts", PackedStringArray())
	for i in mini(parts.size(), design_parts.size()):
		parts[i] = design_parts[i]
	_name.text = copy_name(design.get("name", ""), _known_names())
	_refresh_design()


## Put \a part_name into the selected slot, or the first free slot it fits;
## with \a fill_all, into every free slot it fits.
func place_part(part_name: String, fill_all := false) -> bool:
	if fill_all:
		var filled := false
		for i in parts.size():
			if parts[i].is_empty() and part_fits(part_name, i):
				parts[i] = part_name
				filled = true
		if filled:
			_refresh_design()
		else:
			_status.text = tr("DESIGNER_NO_SLOT")
		return filled
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


## Empty every slot (GG's "Clear Parts").
func clear_all() -> void:
	for i in parts.size():
		parts[i] = ""
	_refresh_design()


## A name for a copy of \a design_name that none of \a taken has and the
## name rules allow: "Frigate 2", "Frigate 3", ... (GG's names can't hold
## brackets, so no "(copy)").
static func copy_name(design_name: String, taken: Array) -> String:
	var base := design_name.strip_edges()
	var number := RegEx.create_from_string(" (\\d+)$").search(base)
	var next := 2
	if number:
		base = base.substr(0, number.get_start())
		next = int(number.get_string(1)) + 1
	for c in "<>;:,.@#$%&*(){}'\"/?\\`[]|":
		base = base.replace(c, "")
	base = base.strip_edges()
	while taken.has("%s %d" % [base, next]):
		next += 1
	return "%s %d" % [base, next]


# Names of the designs listed in the designer (to keep copies apart).
func _known_names() -> Array:
	var names := []
	for kind in ["empire", "obsolete", "saved"]:
		names.append_array(source.get_designs(kind).map(func(d): return d.get("name", "")))
	return names


## Why \a design_name can't name a design (GG's rules: not empty, no
## leading or trailing spaces, no formatting characters), or "".
static func name_problem(design_name: String) -> String:
	if design_name.is_empty():
		return TranslationServer.translate("DESIGN_INV_NO_NAME")
	if design_name != design_name.strip_edges():
		return TranslationServer.translate("DESIGNER_NAME_SPACES")
	for c in "<>;:,.@#$%&*(){}'\"/?\\`[]|":
		if design_name.contains(c):
			return TranslationServer.translate("DESIGNER_NAME_CHARS").replace("%1%", c)
	return ""


## Move or swap the part in slot \a from to slot \a to (dragging).
func move_part(from: int, to: int) -> bool:
	if from == to or from < 0 or to < 0 or from >= parts.size() or to >= parts.size():
		return false
	var moving := parts[from]
	var other := parts[to]
	if not part_fits(moving, to) or (not other.is_empty() and not part_fits(other, from)):
		return false
	parts[to] = moving
	parts[from] = other
	_refresh_design()
	return true


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
	left.add_child(DesignerPalette.availability_row(hulls_shown, func(): _rebuild_hull_list()))
	_hull_list = ScreenKit.list()
	left.add_child(ScreenKit.scrolling(_hull_list))
	left.add_child(ScreenKit.label(tr("DESIGNER_DESIGNS"), "TitleLabel"))
	# Which designs: a picker rather than tabs, to keep the column narrow.
	_design_kind = OptionButton.new()
	for kind in DESIGN_KINDS:
		_design_kind.add_item(tr(kind[1]))
	_design_kind.item_selected.connect(func(_i): _rebuild_design_list())
	left.add_child(_design_kind)
	_design_list = ScreenKit.list()
	left.add_child(ScreenKit.scrolling(_design_list))

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(center)
	_status = ScreenKit.header(center, "MAP_BTN_DESIGN", close_requested.emit)
	_compare_label = ScreenKit.label("", "SmallLabel")
	center.add_child(_compare_label)
	var stage := Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size.y = 260
	center.add_child(stage)
	# A soft light behind the hull, and which hull it is.
	stage.add_child(DesignerArt.stage_backdrop())
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
	_hull_caption = ScreenKit.label("", "SecondaryLabel")
	_hull_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_hull_caption)
	# Which shape is which slot type.
	_legend = CenterContainer.new()
	center.add_child(_legend)
	var hint_row := HBoxContainer.new()
	center.add_child(hint_row)
	var hint := ScreenKit.label(tr("DESIGNER_SLOT_HINT"), "SmallLabel")
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_row.add_child(hint)
	var clear := Button.new()
	clear.text = tr("DESIGN_WND_CLEAR")
	clear.theme_type_variation = "GhostButton"
	clear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clear.pressed.connect(clear_all)
	hint_row.add_child(clear)

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
	var describe := Button.new()
	describe.text = tr("DESIGN_WND_DESIGN_DESCRIPTION")
	describe.toggle_mode = true
	describe.theme_type_variation = "GhostButton"
	describe.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	create_box.add_child(describe)
	_description = TextEdit.new()
	_description.placeholder_text = tr("DESIGNER_DESCRIPTION_HINT")
	_description.custom_minimum_size.y = 64
	_description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_description.visible = false
	describe.toggled.connect(func(on: bool): _description.visible = on)
	create_box.add_child(_description)
	_validity = ScreenKit.label("", "SmallLabel")
	_validity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	create_box.add_child(_validity)
	_create = Button.new()
	_create.text = tr("DESIGNER_CREATE")
	_create.theme_type_variation = "PrimaryButton"
	_create.pressed.connect(_on_create_pressed)
	var buttons := HBoxContainer.new()
	create_box.add_child(buttons)
	buttons.add_child(_create)
	_update = Button.new()
	_update.visible = false
	_update.pressed.connect(update_design)
	buttons.add_child(_update)

	_palette = DesignerPalette.new()
	_palette.custom_minimum_size.x = SIDE_WIDTH
	_palette.source = source
	_palette.fits = func(part_name: String) -> bool:
		return selected_slot < 0 or part_fits(part_name, selected_slot)
	_palette.part_chosen.connect(place_part)
	_palette.part_hovered.connect(highlight_slots_for)
	_palette.slot_cleared.connect(clear_slot)
	_palette.pedia_requested.connect(pedia_requested.emit)
	columns.add_child(_palette)
	_hull_menu = PopupMenu.new()
	_hull_menu.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_hull_menu.id_pressed.connect(_on_hull_menu)
	add_child(_hull_menu)


func _rebuild_hull_list() -> void:
	ScreenKit.clear(_hull_list)
	for hull: Dictionary in _hulls:
		if not DesignerPalette.passes(hull, hulls_shown):
			continue
		var button: Button = DesignerPalette.list_button(
			tr(hull["name"]), DesignerPalette.slot_summary(hull), hull.get("icon", "")
		)
		button.tooltip_text = DesignerPalette.hull_tooltip(hull)
		if DesignerPalette.availability_of(hull) != "available":
			button.modulate.a = 0.6
		button.pressed.connect(func(): select_hull(hull["name"]))
		button.gui_input.connect(
			func(event: InputEvent):
				var click := event as InputEventMouseButton
				if click and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
					open_hull_menu(hull["name"], button.get_screen_position() + click.position)
					button.accept_event()
		)
		_hull_list.add_child(button)


## The right-click menu of \a hull: Pedia, mark obsolete or not.
func open_hull_menu(hull: String, at: Vector2) -> PopupMenu:
	_menu_hull = hull
	_hull_menu.clear()
	_hull_menu.add_item(tr("PEDIA_OPEN"), HullAction.PEDIA)
	_hull_menu.add_item(
		tr(
			(
				"DESIGNER_UNMARK_OBSOLETE"
				if _hull(hull).get("obsolete", false)
				else "DESIGN_WND_OBSOLETE_HULL"
			)
		),
		HullAction.OBSOLETE
	)
	_hull_menu.popup(Rect2i(Vector2i(at), Vector2i.ZERO))
	return _hull_menu


func _on_hull_menu(id: int) -> void:
	match id:
		HullAction.PEDIA:
			pedia_requested.emit("shiphull", _menu_hull)
		HullAction.OBSOLETE:
			var hull := _hull(_menu_hull)
			var obsolete: bool = not hull.get("obsolete", false)
			if source.set_hull_obsolete(_menu_hull, obsolete):
				hull["obsolete"] = obsolete
				_rebuild_hull_list()


func _rebuild_design_list() -> void:
	ScreenKit.clear(_design_list)
	var kind: String = DESIGN_KINDS[maxi(_design_kind.selected, 0)][0]
	var designs: Array = source.get_designs(kind)
	# Premade and saved designs can be added to each new game's (as GG's
	# list menus offer).
	var at_start: String = START_OPTIONS.get(kind, "")
	if not at_start.is_empty() and options.exists(at_start):
		var toggle := CheckBox.new()
		toggle.text = tr(
			(
				"DESIGN_WND_ADD_ALL_SAVED_START"
				if kind == "saved"
				else "DESIGN_WND_ADD_ALL_DEFAULT_START"
			)
		)
		toggle.button_pressed = options.get_value(at_start)
		# Wrapped, so the column keeps its width.
		toggle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		toggle.toggled.connect(
			func(on: bool):
				options.set_value(at_start, on)
				options.commit()
		)
		_design_list.add_child(toggle)
	if kind == "saved" and not designs.is_empty():
		var add_all := Button.new()
		add_all.text = tr("DESIGN_WND_ADD_ALL_SAVED_NOW")
		add_all.theme_type_variation = "GhostButton"
		add_all.pressed.connect(func(): _design_order(source.add_all_saved() >= 0))
		_design_list.add_child(add_all)
	_design_ids = designs.map(func(d): return d.get("id", -1))
	for design: Dictionary in designs:
		_design_list.add_child(_design_row(design, kind))
	if designs.is_empty():
		_design_list.add_child(ScreenKit.label(tr("DESIGNER_NO_DESIGNS"), "SecondaryLabel"))


## List designs of \a kind (a DESIGN_KINDS name: "empire", "saved", ...).
func show_design_kind(kind: String) -> void:
	for i in DESIGN_KINDS.size():
		if DESIGN_KINDS[i][0] == kind:
			_design_kind.select(i)
	_rebuild_design_list()


# Own designs' actions, in one menu to leave room for the name.
func _design_menu(design: Dictionary) -> MenuButton:
	var id: int = design.get("id", -1)
	var menu := MenuButton.new()
	menu.text = "⋯"
	menu.tooltip_text = tr("DESIGNER_ACTIONS")
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var popup := menu.get_popup()
	popup.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if design.get("renamable", false):
		popup.add_item(tr("DESIGNER_RENAME"), DesignAction.RENAME)
	popup.add_item(tr("PEDIA_OPEN"), DesignAction.PEDIA)
	popup.add_item(tr("PRODUCTION_MOVE_TOP"), DesignAction.TOP)
	popup.add_item(tr("PRODUCTION_MOVE_BOTTOM"), DesignAction.BOTTOM)
	popup.add_item(tr("DESIGNER_SAVE_TO_DISK"), DesignAction.KEEP)
	popup.add_item(tr("DESIGNER_OBSOLETE"), DesignAction.ASIDE)
	popup.add_separator()
	popup.add_item(tr("DESIGNER_DELETE"), DesignAction.DELETE)
	popup.id_pressed.connect(
		func(action: int):
			match action:
				DesignAction.RENAME:
					open_rename(design)
				DesignAction.KEEP:
					var ok: bool = source.save_design(id)
					_status.text = (
						tr("DESIGNER_SAVED_TO_DISK" if ok else "DESIGNER_REFUSED")
						. replace("%1%", design.get("name", ""))
					)
				DesignAction.ASIDE:
					_design_order(source.set_obsolete(id, true))
				DesignAction.DELETE:
					confirm_delete(design)
				DesignAction.PEDIA:
					pedia_requested.emit("shipdesign", str(id))
				DesignAction.TOP:
					var first: int = _design_ids[0] if not _design_ids.is_empty() else -1
					_design_order(source.move_design(id, first))
				DesignAction.BOTTOM:
					_design_order(source.move_design(id, -1))
	)
	return menu


# A design: click to start from it; actions for the list it's in.
func _design_row(design: Dictionary, kind: String) -> Control:
	var row := HBoxContainer.new()
	# Can't be built: a mark before the name (the narrow column would cut a
	# word off); the tooltip says it in words.
	var title: String = design.get("name", "")
	if not design.get("producible", true):
		title = "⚠ " + title
	# The hull's picture, as the hulls list shows it.
	var hull_icon: String = _hull(design.get("hull", "")).get("icon", "")
	var button: Button = DesignerPalette.list_button(title, tr(design.get("hull", "")), hull_icon)
	# Smaller than in the hulls list, to leave the name room.
	button.add_theme_constant_override("icon_max_width", FOUi.tokens.icon + FOUi.tokens.space_2)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = DesignerPalette.design_tooltip(design)
	if not design.get("producible", true):
		button.modulate.a = 0.6
	button.pressed.connect(load_design.bind(design, kind))
	row.add_child(button)
	var id: int = design.get("id", -1)
	match kind:
		"empire":
			row.add_child(_design_menu(design))
			# Drag to reorder (production lists them in this order); a
			# design dropped on another goes before it.
			button.set_drag_forwarding(
				func(_at): return {"type": DESIGN_ORDER_DRAG, "id": id},
				func(_at, data):
					return data is Dictionary and data.get("type", "") == DESIGN_ORDER_DRAG,
				func(_at, data): _design_order(source.move_design(data["id"], id))
			)
		"obsolete":
			var back := ScreenKit.small_button("↺", "DESIGNER_RESTORE")
			back.pressed.connect(func(): _design_order(source.set_obsolete(id, false)))
			row.add_child(back)
			row.add_child(_delete_button(design))
		"premade":
			var add := ScreenKit.small_button("+", "DESIGNER_ADD_PREMADE")
			add.pressed.connect(func(): _design_order(source.add_premade(id) >= 0))
			row.add_child(add)
		"saved":
			var uuid: String = design.get("uuid", "")
			var added: bool = design.get("added", false)
			var add := ScreenKit.small_button(
				"✓" if added else "+",
				"DESIGNER_ADDED" if added else "DESIGNER_ADD_SAVED",
				not added
			)
			add.pressed.connect(func(): _design_order(source.add_saved(uuid) >= 0))
			row.add_child(add)
			row.add_child(_delete_button(design, func(): return source.delete_saved(uuid)))
	return row


## Ask for a new name for own design \a design.
func open_rename(design: Dictionary) -> FODialog:
	var field := LineEdit.new()
	field.text = design.get("name", "")
	field.custom_minimum_size.x = 320
	var rename := func():
		var new_name := field.text.strip_edges()
		if not new_name.is_empty() and new_name != design.get("name", ""):
			_design_order(source.rename_design(design.get("id", -1), new_name))
	var dialog := FODialog.open_on(
		self,
		tr("DESIGNER_RENAME"),
		"",
		[[tr("DESIGNER_RENAME"), "PrimaryButton", rename], [tr("CANCEL"), "GhostButton"]]
	)
	dialog.add_content(field)
	field.text_submitted.connect(func(_t): dialog.choose(0))
	field.call_deferred("grab_focus")
	field.call_deferred("select_all")
	return dialog


func _delete_button(design: Dictionary, delete_action := Callable()) -> Button:
	var delete := ScreenKit.small_button("✕", "DESIGNER_DELETE")
	delete.pressed.connect(confirm_delete.bind(design, delete_action))
	return delete


## Ask before deleting \a design (by \a delete_action, or as an own design).
func confirm_delete(design: Dictionary, delete_action := Callable()) -> FODialog:
	if not delete_action.is_valid():
		delete_action = func(): return source.delete_design(design.get("id", -1))
	var confirmed := func(): _design_order(delete_action.call())
	return FODialog.open_on(
		self,
		tr("DESIGNER_DELETE"),
		tr("DESIGNER_DELETE_CONFIRM").replace("%1%", design.get("name", "")),
		[[tr("DESIGNER_DELETE"), "DangerButton", confirmed], [tr("CANCEL"), "GhostButton"]]
	)


func _design_order(ok: bool) -> void:
	_status.text = "" if ok else tr("DESIGNER_REFUSED")
	_rebuild_design_list()


func _rebuild_part_list() -> void:
	_palette.rebuild()


func _refresh_design() -> void:
	_status.text = ""
	_build_slots()
	_layout_slots()
	_rebuild_part_list()
	var stats: Dictionary = (
		source.evaluate(hull_name, parts) if not hull_name.is_empty() else {"valid": false}
	)
	ScreenKit.clear(_stats)
	var base: Dictionary = _baseline.get("stats", {})
	_compare_label.text = (
		tr("DESIGNER_COMPARED_WITH").replace("%1%", _baseline["name"])
		if not _baseline.is_empty()
		else ""
	)
	for stat in STATS:
		var name_cell := HBoxContainer.new()
		name_cell.add_theme_constant_override("separation", FOUi.tokens.space_1)
		name_cell.add_child(ScreenKit.icon("icons/meter/%s.png" % stat[2], FOUi.tokens.icon_small))
		name_cell.add_child(ScreenKit.label(tr(stat[1]), "SecondaryLabel"))
		_stats.add_child(name_cell)
		var cell := HBoxContainer.new()
		cell.add_child(
			ScreenKit.label(_number(stats.get(stat[0], 0.0)) if stats.get("valid") else "–")
		)
		if stats.get("valid") and base.get("valid", false):
			var change := stat_change(stat[0], stats.get(stat[0], 0.0), base.get(stat[0], 0.0))
			if not change.is_empty():
				var label := ScreenKit.label(change["text"], "SmallLabel")
				label.add_theme_color_override(
					"font_color", FOUi.tokens.positive if change["better"] else FOUi.tokens.negative
				)
				cell.add_child(label)
		_stats.add_child(cell)
	_create.set_meta("stats", stats)
	_update_create()


func _build_slots() -> void:
	ScreenKit.clear(_slot_layer)
	var slots: Array = _hull(hull_name).get("slots", [])
	ScreenKit.clear(_legend)
	var types := []
	for type in DesignerArt.SLOT_ART:
		if slots.any(func(s): return s["type"] == type):
			types.push_back(type)
	_legend.add_child(DesignerArt.legend(types))
	for i in slots.size():
		var slot: Dictionary = slots[i]
		var part := _part(parts[i]) if not parts[i].is_empty() else {}
		var button := DesignerArt.slot_button(
			slot["type"], DesignerArt.part_texture(part) if not part.is_empty() else null, SLOT_SIZE
		)
		button.button_pressed = i == selected_slot
		button.set_meta("slot", i)
		var type_label := tr("DESIGNER_SLOT_" + slot["type"].to_upper())
		button.tooltip_text = (
			"%s\n%s" % [type_label, tr(parts[i])] if not parts[i].is_empty() else type_label
		)
		button.gui_input.connect(_on_slot_input.bind(i))
		button.pressed.connect(_on_slot_pressed.bind(i))
		button.set_drag_forwarding(
			func(_at):
				if parts[i].is_empty():
					return null
				button.set_drag_preview(
					DesignerArt.drag_preview(DesignerArt.part_texture(_part(parts[i])), SLOT_SIZE)
				)
				return {"type": DesignerPalette.SLOT_DRAG, "slot": i},
			func(_at, data): return can_drop_on_slot(data, i),
			func(_at, data): _drop_on_slot(data, i)
		)
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
		# The previous hull's slots go at the end of the frame.
		var index: int = button.get_meta("slot", -1)
		if button.is_queued_for_deletion() or index < 0 or index >= slots.size():
			continue
		var slot: Dictionary = slots[index]
		var at := drawn.position + Vector2(slot["x"], slot["y"]) * drawn.size
		button.position = (at - Vector2(SLOT_SIZE, SLOT_SIZE) * 0.5).round()


func _on_slot_pressed(slot: int) -> void:
	selected_slot = slot if selected_slot != slot else -1
	for button in _slot_layer.get_children():
		button.set_pressed_no_signal(button.get_meta("slot") == selected_slot)
	_rebuild_part_list()


func _on_slot_input(event: InputEvent, slot: int) -> void:
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
		clear_slot(slot)


## Whether \a data (a dragged part or slot) can go into \a slot.
func can_drop_on_slot(data: Variant, slot: int) -> bool:
	if not data is Dictionary:
		return false
	match data.get("type", ""):
		DesignerPalette.PART_DRAG:
			return part_fits(data["name"], slot)
		DesignerPalette.SLOT_DRAG:
			var from: int = data["slot"]
			return (
				from != slot
				and part_fits(parts[from], slot)
				and (parts[slot].is_empty() or part_fits(parts[slot], from))
			)
	return false


func _drop_on_slot(data: Dictionary, slot: int) -> void:
	if data["type"] == DesignerPalette.PART_DRAG:
		parts[slot] = data["name"]
		_refresh_design()
	else:
		move_part(data["slot"], slot)


## Why the design as it stands can't be added: [reasons]; empty when it can.
func design_problems() -> PackedStringArray:
	var stats: Dictionary = _create.get_meta("stats", {})
	var problems := PackedStringArray()
	if hull_name.is_empty():
		problems.push_back(tr("DESIGN_INV_NO_HULL"))
		return problems
	var naming := name_problem(_name.text)
	if not naming.is_empty():
		problems.push_back(naming)
	if not stats.get("valid", false):
		problems.append_array(stats.get("problems", PackedStringArray()))
		if stats.get("problems", PackedStringArray()).is_empty():
			problems.push_back(tr("DESIGNER_INVALID"))
	elif stats.has("duplicate_of"):
		problems.push_back(tr("DESIGN_WND_KNOWN_DETAIL").replace("%1%", stats["duplicate_of"]))
	return problems


func _update_create() -> void:
	var problems := design_problems()
	var stats: Dictionary = _create.get_meta("stats", {})
	var notes := Array(problems)
	var unavailable: PackedStringArray = stats.get("unavailable", PackedStringArray())
	if not unavailable.is_empty():
		var names := ", ".join(Array(unavailable).map(func(n): return tr(n)))
		notes.push_back(tr("DESIGNER_NOT_YET_AVAILABLE").replace("%1%", names))
	# Not a reason to refuse it, but easy to miss: slots left empty.
	var empty := Array(parts).count("")
	if not hull_name.is_empty() and empty > 0 and empty < parts.size():
		notes.push_back(
			tr("DESIGNER_EMPTY_SLOT" if empty == 1 else "DESIGNER_EMPTY_SLOTS").replace(
				"%1%", str(empty)
			)
		)
	_validity.text = "\n".join(notes)
	_create.disabled = not problems.is_empty()
	_create.tooltip_text = "\n".join(problems)
	# Update the own or saved design started from.
	var kind: String = _baseline.get("kind", "")
	_update.visible = kind in ["empire", "saved"]
	_update.text = tr(
		"DESIGN_WND_UPDATE_SAVED" if kind == "saved" else "DESIGN_WND_UPDATE_FINISHED"
	)
	_update.tooltip_text = (
		tr(
			(
				"DESIGN_WND_UPDATE_SAVED_DETAIL"
				if kind == "saved"
				else "DESIGN_WND_UPDATE_FINISHED_DETAIL"
			)
		)
		. replace("%1%", _baseline.get("name", ""))
		. replace("%2%", _name.text.strip_edges())
	)
	# A duplicate may replace the design it duplicates (a rename).
	var blocking := Array(problems).filter(func(p): return not p.begins_with(_known_prefix()))
	_update.disabled = not blocking.is_empty()


func _known_prefix() -> String:
	return tr("DESIGN_WND_KNOWN_DETAIL").get_slice("%1%", 0)


func _on_create_pressed() -> void:
	var design_name := _name.text.strip_edges()
	var design_id: int = source.create(design_name, hull_name, parts, _description.text)
	if design_id < 0:
		_status.text = tr("DESIGNER_REFUSED")
		return
	_status.text = tr("DESIGNER_CREATED").replace("%1%", design_name)
	_rebuild_design_list()


## Replace the own or saved design started from with the one on the bench.
func update_design() -> bool:
	var design_name := _name.text.strip_edges()
	var ok := false
	if _baseline.get("kind", "") == "saved":
		ok = source.update_saved(
			_baseline["uuid"], design_name, hull_name, parts, _description.text
		)
	else:
		var new_id: int = source.update_design(
			_baseline.get("id", -1), design_name, hull_name, parts, _description.text
		)
		ok = new_id >= 0
		if ok:
			_baseline["id"] = new_id
	_status.text = (tr("DESIGNER_UPDATED") if ok else tr("DESIGNER_REFUSED")).replace(
		"%1%", design_name
	)
	if ok:
		_baseline["name"] = design_name
		_baseline["stats"] = source.evaluate(hull_name, parts)
	_rebuild_design_list()
	_refresh_design()
	return ok


## How stat \a key changed from \a before to \a after: {text, better},
## or {} when unchanged.
static func stat_change(key: String, after: float, before: float) -> Dictionary:
	var change := after - before
	if absf(change) < 0.005:
		return {}
	return {
		"text": ("+" if change > 0.0 else "") + _number(change),
		"better": (change < 0.0) if key in LOWER_IS_BETTER else (change > 0.0),
	}


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
