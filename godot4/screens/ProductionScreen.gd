class_name ProductionScreen
extends PanelContainer
## Production: the queue (progress, ETA, quantity and batch size, reorder,
## remove, and a menu per item: to the top or bottom, duplicate, split off
## the batches not started, rally ships, show the location, Pedia) with
## what was removed this turn (restorable) on the left, and what can be
## built at the chosen location on the right (filter, search, add; Shift
## adds to the top). Delete removes the focused queue item. Reads and
## orders through `source` (ProductionSource by default; tests set a fake
## before calling refresh()).

signal close_requested
signal pedia_requested(kind: String, article_name: String)
## Show where \a item can be built on the map, to place it there:
## \a locations as get_item_locations() gives them.
signal build_on_map_requested(item: Dictionary, locations: Array)
## Show where a queue item is built, on the map: planet \a location_id.
signal location_requested(location_id: int)

## Queue item menu entries: id, label key.
const ITEM_MENU := [
	[0, "PRODUCTION_MOVE_TOP"],
	[1, "PRODUCTION_MOVE_BOTTOM"],
	[2, "PRODUCTION_DUPLICATE"],
	[3, "PRODUCTION_SPLIT_INCOMPLETE"],
	[4, "PRODUCTION_RALLY"],
	[5, "PRODUCTION_RALLY_CLEAR"],
	[6, "PRODUCTION_SHOW_LOCATION"],
	[7, "PEDIA_OPEN"],
]

## Pause after a spinner's last change before its order goes out.
const SETTLE_SECONDS := 0.6
const FILTERS := ["all", "building", "ship", "stockpile", "unavailable"]
## Drag data types: a queue item moved, a catalogue item added.
const QUEUE_DRAG := "fo_queue_item"
const CATALOG_DRAG := "fo_catalog_item"

var source: Variant = ProductionSource.new()
## The system ships rally to from the item menu (the map's selected
## system), and its name: [id, name]; [-1, ""] for none. GameShell sets it.
var rally_target: Callable = func() -> Array: return [-1, ""]

var _points: Label
var _stockpile: Label
var _group_points: Label
## The listed queue items' indices in the empire's queue.
var _queue_indices: Array = []
var _queue_list: VBoxContainer
var _removed_list: VBoxContainer
var _location: OptionButton
var _location_search: LineEdit
var _filter: TabBar
var _search: LineEdit
var _catalog: VBoxContainer
var _locations: Array = []
var _buildable: Array = []


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "BackgroundPanel"
	_build()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


## Re-read queue, points and locations (e.g. on show or after a turn).
func refresh() -> void:
	var previous_location := selected_location_id()
	_locations = source.get_locations()
	_fill_locations()
	var index := _location.get_item_index(previous_location) if previous_location >= 0 else -1
	if index < 0 and _location.item_count > 0:
		index = 0
	if index >= 0:
		_location.select(index)
	_refresh_queue()
	_refresh_catalog()


## \a locations for the picker: the first (the capital) alone, then the
## rest by system (a [system name] heading each), planets with people first;
## only those whose planet or system name contains \a needle.
static func group_locations(locations: Array, needle := "") -> Array:
	var rows := []
	var by_system := {}
	var order := []
	for i in locations.size():
		var location: Dictionary = locations[i]
		var system_name: String = location.get("system_name", "")
		var text := (str(location["name"]) + " " + system_name).to_lower()
		if not needle.is_empty() and not text.contains(needle.to_lower()):
			continue
		if i == 0 and needle.is_empty():
			rows.push_back(location)
			continue
		if not by_system.has(system_name):
			by_system[system_name] = []
			order.push_back(system_name)
		by_system[system_name].push_back(location)
	order.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	for system_name: String in order:
		var group: Array = by_system[system_name]
		group.sort_custom(
			func(a, b):
				if a.get("populated", false) != b.get("populated", false):
					return a.get("populated", false)
				return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0
		)
		if not system_name.is_empty():
			rows.push_back([system_name])
		rows.append_array(group)
	return rows


func _fill_locations() -> void:
	var keep := selected_location_id()
	_location.clear()
	for row in group_locations(_locations, _location_search.text.strip_edges()):
		if row is Array:
			_location.add_separator(row[0])
		else:
			_location.add_item(row["name"], row["id"])
	var index := _location.get_item_index(keep) if keep >= 0 else -1
	if index >= 0:
		_location.select(index)


func selected_location_id() -> int:
	if _location.selected < 0:
		return -1
	return _location.get_item_id(_location.selected)


## Choose the build location by planet ID (ignored if not a location).
func select_location(planet_id: int) -> void:
	var index := _location.get_item_index(planet_id)
	if index >= 0:
		_location.select(index)
		_refresh_catalog()


func _build() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", FOUi.tokens.space_6)
	margin.add_child(columns)

	# Queue column
	var queue_column := VBoxContainer.new()
	queue_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_column.size_flags_stretch_ratio = 1.2
	columns.add_child(queue_column)
	_points = ScreenKit.header(queue_column, "PRODUCTION_WND_TITLE", close_requested.emit)
	_stockpile = ScreenKit.label("", "SmallLabel")
	_stockpile.tooltip_text = tr("PRODUCTION_STOCKPILE_TIP")
	_stockpile.mouse_filter = Control.MOUSE_FILTER_PASS
	queue_column.add_child(_stockpile)
	var queue_box := VBoxContainer.new()
	queue_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_list = ScreenKit.list()
	queue_box.add_child(_queue_list)
	# Catalogue items dropped below the queue go at its end.
	queue_box.set_drag_forwarding(
		Callable(),
		func(_at, data): return data is Dictionary and data.get("type", "") == CATALOG_DRAG,
		func(_at, data): _order(source.enqueue(data["item"], selected_location_id()))
	)
	_removed_list = ScreenKit.list()
	queue_box.add_child(_removed_list)
	queue_column.add_child(ScreenKit.scrolling(queue_box))

	# Catalog column
	var catalog_column := VBoxContainer.new()
	catalog_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(catalog_column)
	var location_row := HBoxContainer.new()
	catalog_column.add_child(location_row)
	location_row.add_child(ScreenKit.label(tr("PRODUCTION_LOCATION"), "SecondaryLabel"))
	_location = OptionButton.new()
	_location.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_location.item_selected.connect(func(_i): _refresh_catalog())
	location_row.add_child(_location)
	# Narrow the picker by planet or system name (many outposts later on).
	_location_search = LineEdit.new()
	_location_search.placeholder_text = tr("PRODUCTION_LOCATION_SEARCH")
	_location_search.custom_minimum_size.x = 120
	_location_search.clear_button_enabled = true
	_location_search.text_changed.connect(
		func(_t):
			_fill_locations()
			if _location.selected < 0 and _location.item_count > 0:
				for i in _location.item_count:
					if not _location.is_item_separator(i):
						_location.select(i)
						break
			_refresh_catalog()
	)
	location_row.add_child(_location_search)
	# The selected location's supply group: what it makes and what is spent
	# there (GG's group PP).
	_group_points = ScreenKit.label("", "SmallLabel")
	catalog_column.add_child(_group_points)
	_filter = TabBar.new()
	for filter in FILTERS:
		_filter.add_tab(tr("PRODUCTION_FILTER_" + filter.to_upper()))
	_filter.tab_changed.connect(func(_t): _refresh_catalog())
	catalog_column.add_child(_filter)
	_search = LineEdit.new()
	_search.placeholder_text = tr("PRODUCTION_SEARCH")
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _refresh_catalog())
	catalog_column.add_child(_search)
	_catalog = ScreenKit.list()
	catalog_column.add_child(ScreenKit.scrolling(_catalog))


func _refresh_queue() -> void:
	var points: Dictionary = source.get_points()
	_points.text = (
		tr("PRODUCTION_POINTS")
		. replace("%1%", "%.1f" % points.get("spent", 0.0))
		. replace("%2%", "%.1f" % points.get("available", 0.0))
	)
	_stockpile.text = (
		tr("PRODUCTION_STOCKPILE")
		. replace("%1%", "%.1f" % points.get("stockpile", 0.0))
		. replace("%2%", "%.1f" % points.get("stockpile_capacity", 0.0))
		. replace("%3%", "%.1f" % points.get("stockpile_expected", 0.0))
	)
	_stockpile.text += points_note(points)
	ScreenKit.clear(_queue_list)
	var queue: Array = source.get_queue()
	# Items removed this turn keep their place in the empire's queue but
	# aren't listed: moves go to the listed neighbours' places.
	_queue_indices = queue.map(func(e): return e.get("index", 0))
	if queue.is_empty():
		_queue_list.add_child(ScreenKit.label(tr("PRODUCTION_EMPTY_QUEUE"), "SecondaryLabel"))
	for i in queue.size():
		_queue_list.add_child(_queue_row(queue[i], i, queue.size()))
	_refresh_removed()


## This turn's stockpile draw and the PP going unspent, as GG's info panel:
## " · 1.2 PP drawn · 3.0 PP wasted" (only what isn't zero).
static func points_note(points: Dictionary) -> String:
	var note := ""
	var drawn: float = points.get("stockpile_used", 0.0)
	if drawn > 0.05:
		note += (
			" · " + TranslationServer.translate("PRODUCTION_DRAWN").replace("%1%", "%.1f" % drawn)
		)
	var wasted: float = points.get("available", 0.0) - points.get("spent", 0.0)
	if wasted > 0.05:
		note += (
			" · " + TranslationServer.translate("PRODUCTION_WASTED").replace("%1%", "%.1f" % wasted)
		)
	return note


# Items removed this turn can be put back until the turn ends.
func _refresh_removed() -> void:
	ScreenKit.clear(_removed_list)
	var removed: Array = source.get_removed()
	if removed.is_empty():
		return
	_removed_list.add_child(ScreenKit.label(tr("PRODUCTION_REMOVED_THIS_TURN"), "SecondaryLabel"))
	for entry: Dictionary in removed:
		var row := HBoxContainer.new()
		row.modulate = Color(1, 1, 1, 0.6)
		row.add_child(ScreenKit.icon(entry.get("icon", ""), FOUi.tokens.icon_small))
		var label := ScreenKit.label(
			"%s · %s" % [_display_name(entry), entry.get("location_name", "")], "SmallLabel"
		)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(label)
		var restore := Button.new()
		restore.text = tr("PRODUCTION_RESTORE")
		restore.theme_type_variation = "GhostButton"
		restore.pressed.connect(func(): _order(source.restore(entry["index"])))
		row.add_child(restore)
		_removed_list.add_child(row)


func _refresh_catalog() -> void:
	ScreenKit.clear(_catalog)
	var location_id := selected_location_id()
	var filter: String = FILTERS[_filter.current_tab]
	_buildable = (
		source.get_buildable(location_id, filter == "unavailable") if location_id >= 0 else []
	)
	var group: Dictionary = source.get_group_points(location_id) if location_id >= 0 else {}
	_group_points.text = (
		(tr("PRODUCTION_GROUP_POINTS").replace("%1%", "%.1f" % group.get("output", 0.0)).replace(
			"%2%", "%.1f" % group.get("allocated", 0.0)
		))
		if not group.is_empty()
		else ""
	)
	var needle := _search.text.strip_edges().to_lower()
	var shown := 0
	for item: Dictionary in _buildable:
		var available: bool = item.get("available", true)
		if filter == "unavailable":
			if available:
				continue
		elif filter != "all" and item.get("build_type") != filter:
			continue
		if not needle.is_empty() and not _display_name(item).to_lower().contains(needle):
			continue
		_catalog.add_child(_catalog_row(item))
		shown += 1
	if shown == 0:
		_catalog.add_child(ScreenKit.label(tr("PRODUCTION_NOTHING_BUILDABLE"), "SecondaryLabel"))


func _queue_row(entry: Dictionary, position: int, count: int) -> Control:
	var card := PanelContainer.new()
	var index: int = entry.get("index", position)
	# Drag to reorder; catalogue items dropped here go before it.
	card.set_drag_forwarding(
		func(_at): return {"type": QUEUE_DRAG, "index": index, "label": _display_name(entry)},
		_can_drop_on_queue,
		_drop_on_queue.bind(index)
	)
	card.tooltip_text = queue_tooltip(entry)
	# Click a card to focus it; Delete then removes it.
	card.focus_mode = Control.FOCUS_CLICK
	card.gui_input.connect(
		func(event: InputEvent):
			if event is InputEventKey and event.pressed and event.keycode == KEY_DELETE:
				_order(source.remove(index))
				card.accept_event()
	)
	var row := HBoxContainer.new()
	card.add_child(row)
	row.add_child(ScreenKit.icon(entry.get("icon", "")))

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", FOUi.tokens.space_1)
	row.add_child(text)
	var name_line := HBoxContainer.new()
	text.add_child(name_line)
	var item_name := ScreenKit.label(_display_name(entry))
	item_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_line.add_child(item_name)
	name_line.add_child(ScreenKit.label(turns_label(entry), "SecondaryLabel"))
	var progress := ProgressBar.new()
	progress.max_value = 1.0
	progress.value = entry.get("progress", 0.0)
	progress.show_percentage = false
	progress.custom_minimum_size.y = FOUi.tokens.space_2
	text.add_child(progress)
	var detail := (
		tr("PRODUCTION_QUEUE_DETAIL")
		. replace("%1%", entry.get("location_name", ""))
		. replace("%2%", "%.1f" % entry.get("allocated_pp", 0.0))
	)
	var rally: String = entry.get("rally_point_name", "")
	if not rally.is_empty():
		detail += " · " + tr("PRODUCTION_RALLY_TO").replace("%1%", rally)
	var paused: bool = entry.get("paused", false)
	if paused:
		detail += " · " + tr("PRODUCTION_PAUSED")
		card.modulate = Color(1, 1, 1, 0.6)
	var detail_label := ScreenKit.label(detail, "SmallLabel")
	# Can't be produced where it is any more: it stalls (GG's tooltip says so).
	if not entry.get("location_ok", true):
		detail_label.text += " · " + tr("PRODUCTION_LOCATION_INVALID")
		detail_label.add_theme_color_override("font_color", FOUi.tokens.negative)
	text.add_child(detail_label)

	# Pause or resume; allow or forbid drawing on the imperial stockpile.
	var toggles := VBoxContainer.new()
	toggles.add_theme_constant_override("separation", 0)
	row.add_child(toggles)
	var pause := ScreenKit.small_button(
		"▶" if paused else "Ⅱ", "PRODUCTION_RESUME" if paused else "PRODUCTION_PAUSE"
	)
	pause.pressed.connect(func(): _order(source.set_paused(index, not paused)))
	toggles.add_child(pause)
	var stockpile := Button.new()
	stockpile.toggle_mode = true
	stockpile.button_pressed = entry.get("stockpile_allowed", false)
	stockpile.icon = FOArt.meter_icon("stockpile")
	stockpile.expand_icon = true
	stockpile.custom_minimum_size = Vector2.ONE * (FOUi.tokens.icon_small + FOUi.tokens.space_2)
	stockpile.theme_type_variation = "SegmentButton"
	stockpile.tooltip_text = tr("PRODUCTION_STOCKPILE_USE")
	stockpile.toggled.connect(func(on: bool): _order(source.set_stockpile_allowed(index, on)))
	toggles.add_child(stockpile)
	if entry.get("build_type") in ["ship", "stockpile"]:
		var quantity := SpinBox.new()
		quantity.min_value = 1
		quantity.max_value = 99
		quantity.value = entry.get("remaining", 1)
		quantity.tooltip_text = tr("PRODUCTION_QUANTITY")
		quantity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		quantity.value_changed.connect(
			settle.bind(quantity, func(v): _order(source.set_quantity(index, v)))
		)
		row.add_child(quantity)
		# Batch size: ships built together, finishing on the same turn.
		row.add_child(ScreenKit.label("×", "SecondaryLabel"))
		var blocksize := SpinBox.new()
		blocksize.min_value = 1
		blocksize.max_value = 99
		blocksize.value = entry.get("blocksize", 1)
		blocksize.tooltip_text = tr("PRODUCTION_BLOCKSIZE")
		blocksize.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		blocksize.value_changed.connect(
			settle.bind(blocksize, func(v): _order(source.set_blocksize(index, v)))
		)
		row.add_child(blocksize)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 0)
	row.add_child(buttons)
	var up := ScreenKit.small_button("▲", "PRODUCTION_MOVE_UP", position > 0)
	up.pressed.connect(func(): _order(source.move(index, _queue_index(position - 1))))
	buttons.add_child(up)
	var down := ScreenKit.small_button("▼", "PRODUCTION_MOVE_DOWN", position < count - 1)
	down.pressed.connect(func(): _order(source.move(index, _queue_index(position + 1))))
	buttons.add_child(down)
	var menu := MenuButton.new()
	menu.text = "⋯"
	menu.flat = false
	menu.tooltip_text = tr("PRODUCTION_ITEM_MENU")
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu.about_to_popup.connect(_fill_item_menu.bind(menu.get_popup(), entry, count))
	menu.get_popup().id_pressed.connect(func(id): run_item_action(id, entry, count))
	row.add_child(menu)
	var remove := ScreenKit.small_button("✕", "PRODUCTION_REMOVE", true)
	remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	remove.pressed.connect(func(): _order(source.remove(index)))
	row.add_child(remove)
	return card


## Item menu entries (ITEM_MENU ids) for queue \a entry of \a count.
func item_actions(entry: Dictionary, count: int) -> Array:
	var actions := []
	var position := _queue_position(entry)
	if position > 0:
		actions.push_back(0)
	if position < count - 1:
		actions.push_back(1)
	actions.push_back(2)
	var ship: bool = entry.get("build_type") == "ship"
	if ship and entry.get("remaining", 1) > 1 and entry.get("progress", 0.0) > 0.0:
		actions.push_back(3)
	if ship and rally_target.call()[0] >= 0:
		actions.push_back(4)
	if ship and entry.get("rally_point_id", -1) >= 0:
		actions.push_back(5)
	if entry.get("location_id", -1) >= 0:
		actions.push_back(6)
	if entry.get("build_type") == "building" or ship:
		actions.push_back(7)
	return actions


## Do item menu entry \a id for queue \a entry of \a count.
func run_item_action(id: int, entry: Dictionary, count: int) -> void:
	var index: int = entry.get("index", 0)
	match id:
		0:
			_order(source.move(index, _queue_index(0)))
		1:
			_order(source.move(index, _queue_index(count - 1)))
		2:
			_order(source.duplicate_item(index))
		3:
			_order(source.split_incomplete(index))
		4:
			_order(source.set_rally_point(index, rally_target.call()[0]))
		5:
			_order(source.set_rally_point(index, -1))
		6:
			location_requested.emit(entry.get("location_id", -1))
		7:
			pedia_requested.emit.callv(pedia_target(entry))


# The empire-queue index of the listed item at \a position (as listed).
func _queue_index(position: int) -> int:
	if position >= 0 and position < _queue_indices.size():
		return _queue_indices[position]
	return position


# Where \a entry is listed (its queue index when the list isn't known).
func _queue_position(entry: Dictionary) -> int:
	var index: int = entry.get("index", 0)
	var position := _queue_indices.find(index)
	return position if position >= 0 else index


## The Pedia article of a queue or catalogue item: [kind, name]; ships
## open their design's.
static func pedia_target(item: Dictionary) -> Array:
	if item.get("build_type") == "ship":
		return ["shipdesign", str(item.get("design_id", -1))]
	return ["buildingtype", item.get("name", "")]


func _fill_item_menu(popup: PopupMenu, entry: Dictionary, count: int) -> void:
	popup.clear()
	var actions := item_actions(entry, count)
	for item in ITEM_MENU:
		if item[0] in actions:
			var text := tr(item[1])
			if item[0] == 4:
				text = text.replace("%1%", rally_target.call()[1])
			popup.add_item(text, item[0])


func _catalog_row(item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var available: bool = item.get("available", true)
	row.tooltip_text = catalog_tooltip(item)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	if available:
		row.set_drag_forwarding(
			func(_at): return {"type": CATALOG_DRAG, "item": item}, Callable(), Callable()
		)
	else:
		row.modulate = Color(1, 1, 1, 0.55)
	row.add_child(ScreenKit.icon(item.get("icon", "")))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var item_name := ScreenKit.label(_display_name(item))
	item_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(item_name)
	var cost := tr("PRODUCTION_ITEM_COST").replace("%1%", "%.0f" % item.get("cost", 0.0)).replace(
		"%2%", ScreenKit.turns_text(item.get("turns", 0))
	)
	text.add_child(ScreenKit.label(cost, "SmallLabel"))
	if item.get("build_type") in ["building", "ship"]:
		var info := ScreenKit.small_button("?", "PEDIA_OPEN")
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.pressed.connect(func(): pedia_requested.emit.callv(pedia_target(item)))
		row.add_child(info)
	var where := ScreenKit.small_button("⌖", "PRODUCTION_WHERE")
	where.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	where.pressed.connect(open_locations.bind(item))
	row.add_child(where)
	# Items that can't be built here now can still be queued, to wait for it
	# (as GG allows).
	var add := Button.new()
	add.text = tr("PRODUCTION_ADD" if available else "PRODUCTION_ADD_ANYWAY")
	add.tooltip_text = tr("QUEUE_ADD_TOP_TIP" if available else "PRODUCTION_ADD_ANYWAY_TIP")
	add.disabled = not available and item.get("build_type") == "stockpile"
	add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add.pressed.connect(add_item.bind(item))
	row.add_child(add)
	# Double-click adds too (Shift: at the top), as the tech list and tree.
	row.gui_input.connect(
		func(event: InputEvent):
			var click := event as InputEventMouseButton
			if click and click.double_click and click.button_index == MOUSE_BUTTON_LEFT:
				add_item(item)
				row.accept_event()
	)
	return row


## Once \a spinner has rested at \a value for SETTLE_SECONDS, \a apply it
## (an int): clicking or holding the arrows sends one order, not one per step,
## and the row isn't rebuilt under the pointer.
func settle(value: float, spinner: SpinBox, apply: Callable) -> void:
	var step: int = spinner.get_meta("settle_step", 0) + 1
	spinner.set_meta("settle_step", step)
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	if is_instance_valid(spinner) and spinner.get_meta("settle_step", 0) == step:
		apply.call(int(value))


## Add catalogue \a item at the location shown: at the end, or with Shift at
## the top.
func add_item(item: Dictionary) -> void:
	var top := Input.is_key_pressed(KEY_SHIFT)
	var forced: bool = not item.get("available", true)
	_order(source.enqueue(item, selected_location_id(), 0 if top else -1, forced))


## Tooltip of queue \a entry: total cost, a turn's share, minimum time and
## what it gets this turn (GG's queue row tooltip).
func queue_tooltip(entry: Dictionary) -> String:
	var lines: PackedStringArray = [_display_name(entry)]
	var total: float = entry.get("total_cost", 0.0)
	var turns: int = entry.get("min_turns", 0)
	if total > 0.0:
		lines.push_back(
			tr("PRODUCTION_TIP_COST").replace("%1%", "%.1f" % total).replace(
				"%2%", "%.1f" % (total / maxi(turns, 1))
			)
		)
	if turns > 0:
		lines.push_back(tr("PRODUCTION_TIP_MIN_TURNS").replace("%1%", str(turns)))
	lines.push_back(
		tr("PRODUCTION_TIP_ALLOCATED").replace("%1%", "%.1f" % entry.get("allocated_pp", 0.0))
	)
	if entry.has("location_ok"):
		lines.push_back(
			tr("PRODUCTION_LOCATION_OK" if entry["location_ok"] else "PRODUCTION_LOCATION_INVALID")
		)
	return "\n".join(lines)


## A queue item's time: until it's done, and for a batch of several, until
## the next one is (GG shows that).
func turns_label(entry: Dictionary) -> String:
	var done := ScreenKit.turns_text(entry.get("turns_left", -1))
	var next: int = entry.get("turns_to_next", -1)
	if entry.get("remaining", 1) > 1 and next >= 0 and next != entry.get("turns_left", -1):
		return tr("PRODUCTION_NEXT_AND_DONE").replace("%1%", ScreenKit.turns_text(next)).replace(
			"%2%", done
		)
	return done


## Tooltip of catalogue \a item: cost per turn and time here, description,
## and why it can't be built here when it can't.
## \a parts by name with counts ("2× Mass Driver, Armor Plating"); empty
## slots are left out.
static func parts_summary(parts: Variant) -> String:
	var counts := {}
	for part: String in parts:
		if not part.is_empty():
			counts[part] = counts.get(part, 0) + 1
	var names := PackedStringArray()
	for part: String in counts:
		var count: int = counts[part]
		names.push_back(
			(
				("%d× %s" % [count, TranslationServer.translate(part)])
				if count > 1
				else TranslationServer.translate(part)
			)
		)
	return ", ".join(names) if not names.is_empty() else "—"


func catalog_tooltip(item: Dictionary) -> String:
	var lines: PackedStringArray = [_display_name(item)]
	lines.push_back(
		tr("PRODUCTION_TIP_COST").replace("%1%", "%.1f" % item.get("cost", 0.0)).replace(
			"%2%", "%.1f" % item.get("cost_per_turn", item.get("cost", 0.0))
		)
	)
	lines.push_back(tr("PRODUCTION_TIP_MIN_TURNS").replace("%1%", str(item.get("turns", 0))))
	if item.get("build_type") == "ship" and not item.get("hull", "").is_empty():
		lines.push_back(
			tr("PRODUCTION_TIP_DESIGN").replace("%1%", tr(item["hull"])).replace(
				"%2%", parts_summary(item.get("parts", []))
			)
		)
	var description: String = item.get("description", "")
	if not description.is_empty():
		lines.push_back(FORichText.plain_text(tr(description)).left(400))
	var reason: String = item.get("reason", "")
	if not reason.is_empty():
		lines.push_back(tr("PRODUCTION_TIP_UNAVAILABLE") + "\n" + FORichText.plain_text(reason))
	return "\n\n".join(lines)


func _can_drop_on_queue(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("type", "") in [QUEUE_DRAG, CATALOG_DRAG]


## A queue item or catalogue item dropped on queue item \a target_index.
func _drop_on_queue(_at: Vector2, data: Variant, target_index: int) -> void:
	if data.get("type", "") == QUEUE_DRAG:
		if data["index"] != target_index:
			_order(source.move(data["index"], target_index))
	else:
		_order(source.enqueue(data["item"], selected_location_id(), target_index))


## Every location where \a item can be built, to add it at several at once;
## the chosen location starts ticked.
func open_locations(item: Dictionary) -> FODialog:
	var locations: Array = source.get_item_locations(item)
	var checks: Array[CheckBox] = []
	var dialog := (
		FODialog
		. open_on(
			self,
			_display_name(item),
			tr("PRODUCTION_WHERE_MESSAGE").replace("%1%", str(locations.size())),
			[
				[tr("PRODUCTION_ADD_AT_TICKED"), "PrimaryButton", _add_at.bind(item, checks)],
				[
					tr("PRODUCTION_SHOW_ON_MAP"),
					"GhostButton",
					build_on_map_requested.emit.bind(item, locations)
				],
				[tr("CANCEL"), "GhostButton"],
			]
		)
	)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 0)
	for location: Dictionary in locations:
		var check := CheckBox.new()
		check.text = location["name"]
		check.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		check.button_pressed = location["id"] == selected_location_id()
		check.set_meta("location_id", location["id"])
		list.add_child(check)
		checks.push_back(check)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = mini(locations.size(), 10) * 32
	scroll.add_child(list)
	dialog.add_content(scroll)
	return dialog


func _add_at(item: Dictionary, checks: Array[CheckBox]) -> void:
	var added := false
	for check in checks:
		if check.button_pressed:
			added = source.enqueue(item, check.get_meta("location_id")) or added
	_order(added)


func _order(ok: bool) -> void:
	if ok:
		_refresh_queue.call_deferred()
		# What can be added and the group's points change with the queue
		# (items allowed once, the PP left); keep the list where it was.
		_refresh_catalog_in_place.call_deferred()


func _refresh_catalog_in_place() -> void:
	var scroll := _catalog.get_parent().get_parent() as ScrollContainer
	var at := scroll.scroll_vertical if scroll else 0
	_refresh_catalog()
	if scroll:
		scroll.set_deferred("scroll_vertical", at)


## The name shown for \a item (stringtable key or design name).
func display_name(item: Dictionary) -> String:
	return _display_name(item)


func _display_name(item: Dictionary) -> String:
	# Buildings and the stockpile project carry stringtable keys, ship designs
	# their display name.
	var label: String = item.get("label", "")
	return tr(label) if item.get("build_type") in ["building", "stockpile"] else label
