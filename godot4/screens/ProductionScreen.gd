class_name ProductionScreen
extends PanelContainer
## Production: the queue (progress, ETA, quantity, reorder, remove) on the
## left, and what can be built at the chosen location on the right (filter,
## search, add). Reads and orders through `source` (ProductionSource by
## default; tests set a fake before calling refresh()).

signal close_requested

const FILTERS := ["all", "building", "ship"]

var source: Variant = ProductionSource.new()

var _points: Label
var _queue_list: VBoxContainer
var _location: OptionButton
var _filter: TabBar
var _search: LineEdit
var _catalog: VBoxContainer
var _locations: Array = []
var _buildable: Array = []


func _init() -> void:
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
	var queue_header := HBoxContainer.new()
	queue_column.add_child(queue_header)
	var title := _label(tr("PRODUCTION_WND_TITLE"), "HeadingLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_header.add_child(title)
	_points = _label("", "SecondaryLabel")
	_points.size_flags_vertical = Control.SIZE_SHRINK_END
	queue_header.add_child(_points)
	var close := Button.new()
	close.text = "✕"
	close.theme_type_variation = "GhostButton"
	close.tooltip_text = tr("PANEL_CLOSE")
	close.pressed.connect(close_requested.emit)
	queue_header.add_child(close)
	queue_column.add_child(_scrolling(_new_list(), "_queue_list"))

	# Catalog column
	var catalog_column := VBoxContainer.new()
	catalog_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(catalog_column)
	var location_row := HBoxContainer.new()
	catalog_column.add_child(location_row)
	location_row.add_child(_label(tr("PRODUCTION_LOCATION"), "SecondaryLabel"))
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
	catalog_column.add_child(_scrolling(_new_list(), "_catalog"))


func _refresh_queue() -> void:
	var points: Dictionary = source.get_points()
	_points.text = (
		tr("PRODUCTION_POINTS")
		. replace("%1%", "%.1f" % points.get("spent", 0.0))
		. replace("%2%", "%.1f" % points.get("available", 0.0))
	)
	for child in _queue_list.get_children():
		child.queue_free()
	var queue: Array = source.get_queue()
	if queue.is_empty():
		_queue_list.add_child(_label(tr("PRODUCTION_EMPTY_QUEUE"), "SecondaryLabel"))
	for i in queue.size():
		_queue_list.add_child(_queue_row(queue[i], i, queue.size()))


func _refresh_catalog() -> void:
	for child in _catalog.get_children():
		child.queue_free()
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
		_catalog.add_child(_label(tr("PRODUCTION_NOTHING_BUILDABLE"), "SecondaryLabel"))


func _queue_row(entry: Dictionary, position: int, count: int) -> Control:
	var card := PanelContainer.new()
	var row := HBoxContainer.new()
	card.add_child(row)
	row.add_child(_icon(entry.get("icon", "")))

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", FOUi.tokens.space_1)
	row.add_child(text)
	var name_line := HBoxContainer.new()
	text.add_child(name_line)
	var item_name := _label(_display_name(entry))
	item_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_line.add_child(item_name)
	name_line.add_child(_label(_turns_text(entry.get("turns_left", -1)), "SecondaryLabel"))
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
	text.add_child(_label(detail, "SmallLabel"))

	var index: int = entry.get("index", position)
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
	var up := _small_button("▲", "PRODUCTION_MOVE_UP", position > 0)
	up.pressed.connect(func(): _order(source.move(index, index - 1)))
	buttons.add_child(up)
	var down := _small_button("▼", "PRODUCTION_MOVE_DOWN", position < count - 1)
	down.pressed.connect(func(): _order(source.move(index, index + 1)))
	buttons.add_child(down)
	var remove := _small_button("✕", "PRODUCTION_REMOVE", true)
	remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	remove.pressed.connect(func(): _order(source.remove(index)))
	row.add_child(remove)
	return card


func _catalog_row(item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_icon(item.get("icon", "")))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var item_name := _label(_display_name(item))
	item_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(item_name)
	var cost := tr("PRODUCTION_ITEM_COST").replace("%1%", "%.0f" % item.get("cost", 0.0)).replace(
		"%2%", str(item.get("turns", 0))
	)
	text.add_child(_label(cost, "SmallLabel"))
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
	# Buildings carry stringtable keys, ship designs their display name.
	var label: String = item.get("label", "")
	return tr(label) if item.get("build_type") == "building" else label


static func _turns_text(turns: int) -> String:
	if turns < 0:
		return TranslationServer.translate("PRODUCTION_NEVER")
	return TranslationServer.translate("MAP_ROUTE_ETA").replace("%1%", str(turns))


func _scrolling(list: VBoxContainer, field: String) -> ScrollContainer:
	set(field, list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Keep rows clear of the scrollbar.
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_top", "margin_bottom"]:
		gutter.add_theme_constant_override(side, 0)
	gutter.add_theme_constant_override("margin_right", FOUi.tokens.space_4)
	gutter.add_child(list)
	scroll.add_child(gutter)
	return scroll


static func _new_list() -> VBoxContainer:
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return list


static func _icon(path: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = FOArt.icon(path)
	rect.custom_minimum_size = Vector2(FOUi.tokens.icon_large, FOUi.tokens.icon_large)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect


static func _small_button(text: String, tooltip_key: String, enabled: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = "GhostButton"
	button.tooltip_text = TranslationServer.translate(tooltip_key)
	button.disabled = not enabled
	return button


static func _label(text: String, variation := "") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label
