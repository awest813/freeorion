class_name ProductionScreen
extends PanelContainer
## Production: the queue (progress, ETA, quantity, reorder, remove) on the
## left, and what can be built at the chosen location on the right (filter,
## search, add). Reads and orders through `source` (ProductionSource by
## default; tests set a fake before calling refresh()).

signal close_requested
signal pedia_requested(kind: String, article_name: String)

const FILTERS := ["all", "building", "ship"]

var source: Variant = ProductionSource.new()

var _points: Label
var _stockpile: Label
var _queue_list: VBoxContainer
var _location: OptionButton
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
	_location.clear()
	for location: Dictionary in _locations:
		_location.add_item(location["name"], location["id"])
	var index := _location.get_item_index(previous_location) if previous_location >= 0 else -1
	if index < 0 and _location.item_count > 0:
		index = 0
	if index >= 0:
		_location.select(index)
	_refresh_queue()
	_refresh_catalog()


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
	_queue_list = ScreenKit.list()
	queue_column.add_child(ScreenKit.scrolling(_queue_list))

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
	ScreenKit.clear(_queue_list)
	var queue: Array = source.get_queue()
	if queue.is_empty():
		_queue_list.add_child(ScreenKit.label(tr("PRODUCTION_EMPTY_QUEUE"), "SecondaryLabel"))
	for i in queue.size():
		_queue_list.add_child(_queue_row(queue[i], i, queue.size()))


func _refresh_catalog() -> void:
	ScreenKit.clear(_catalog)
	var location_id := selected_location_id()
	_buildable = source.get_buildable(location_id) if location_id >= 0 else []
	var filter: String = FILTERS[_filter.current_tab]
	var needle := _search.text.strip_edges().to_lower()
	var shown := 0
	for item: Dictionary in _buildable:
		if filter != "all" and item.get("build_type") != filter:
			continue
		if not needle.is_empty() and not _display_name(item).to_lower().contains(needle):
			continue
		_catalog.add_child(_catalog_row(item))
		shown += 1
	if shown == 0:
		_catalog.add_child(ScreenKit.label(tr("PRODUCTION_NOTHING_BUILDABLE"), "SecondaryLabel"))


func _queue_row(entry: Dictionary, position: int, count: int) -> Control:
	var card := PanelContainer.new()
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
	name_line.add_child(
		ScreenKit.label(ScreenKit.turns_text(entry.get("turns_left", -1)), "SecondaryLabel")
	)
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
	var paused: bool = entry.get("paused", false)
	if paused:
		detail += " · " + tr("PRODUCTION_PAUSED")
		card.modulate = Color(1, 1, 1, 0.6)
	text.add_child(ScreenKit.label(detail, "SmallLabel"))

	var index: int = entry.get("index", position)
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
	if entry.get("build_type") == "ship":
		var quantity := SpinBox.new()
		quantity.min_value = 1
		quantity.max_value = 99
		quantity.value = entry.get("remaining", 1)
		quantity.tooltip_text = tr("PRODUCTION_QUANTITY")
		quantity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		quantity.value_changed.connect(func(value): _order(source.set_quantity(index, int(value))))
		row.add_child(quantity)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 0)
	row.add_child(buttons)
	var up := ScreenKit.small_button("▲", "PRODUCTION_MOVE_UP", position > 0)
	up.pressed.connect(func(): _order(source.move(index, index - 1)))
	buttons.add_child(up)
	var down := ScreenKit.small_button("▼", "PRODUCTION_MOVE_DOWN", position < count - 1)
	down.pressed.connect(func(): _order(source.move(index, index + 1)))
	buttons.add_child(down)
	var remove := ScreenKit.small_button("✕", "PRODUCTION_REMOVE", true)
	remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	remove.pressed.connect(func(): _order(source.remove(index)))
	row.add_child(remove)
	return card


func _catalog_row(item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_child(ScreenKit.icon(item.get("icon", "")))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var item_name := ScreenKit.label(_display_name(item))
	item_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(item_name)
	var cost := tr("PRODUCTION_ITEM_COST").replace("%1%", "%.0f" % item.get("cost", 0.0)).replace(
		"%2%", str(item.get("turns", 0))
	)
	text.add_child(ScreenKit.label(cost, "SmallLabel"))
	if item.get("build_type") == "building":
		var info := ScreenKit.small_button("?", "PEDIA_OPEN")
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.pressed.connect(pedia_requested.emit.bind("buildingtype", item.get("name", "")))
		row.add_child(info)
	var add := Button.new()
	add.text = tr("PRODUCTION_ADD")
	add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add.pressed.connect(func(): _order(source.enqueue(item, selected_location_id())))
	row.add_child(add)
	return row


func _order(ok: bool) -> void:
	if ok:
		_refresh_queue.call_deferred()


func _display_name(item: Dictionary) -> String:
	# Buildings and the stockpile project carry stringtable keys, ship designs
	# their display name.
	var label: String = item.get("label", "")
	return tr(label) if item.get("build_type") in ["building", "stockpile"] else label
