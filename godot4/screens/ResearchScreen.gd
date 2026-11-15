class_name ResearchScreen
extends PanelContainer
## Research: the queue (progress, ETA, reorder, remove) on the left, and the
## techs on the right, filtered by availability and category, searchable.
## Adding a tech also queues its missing prerequisites. Reads and orders
## through `source` (ResearchSource by default; tests set a fake).

signal close_requested

## Availability filters: researchable now, everything not yet researched,
## and researched.
const FILTERS := ["researchable", "open", "complete"]

var source: Variant = ResearchSource.new()

var _points: Label
var _queue_list: VBoxContainer
var _filter: TabBar
var _category: OptionButton
var _search: LineEdit
var _catalog: VBoxContainer
var _techs: Array = []


func _init() -> void:
	theme_type_variation = "BackgroundPanel"
	_build()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	var previous_category := _selected_category()
	_category.clear()
	_category.add_item(tr("PRODUCTION_FILTER_ALL"))
	_category.set_item_metadata(0, "")
	for category in source.get_categories():
		_category.add_item(tr(category))
		_category.set_item_metadata(_category.item_count - 1, category)
		if category == previous_category:
			_category.select(_category.item_count - 1)
	_techs = source.get_techs()
	_refresh_queue()
	_refresh_catalog()


func _build() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", FOUi.tokens.space_6)
	margin.add_child(columns)

	var queue_column := VBoxContainer.new()
	queue_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_column.size_flags_stretch_ratio = 1.2
	columns.add_child(queue_column)
	_points = ScreenKit.header(queue_column, "RESEARCH_WND_TITLE", close_requested.emit)
	_queue_list = ScreenKit.list()
	queue_column.add_child(ScreenKit.scrolling(_queue_list))

	var catalog_column := VBoxContainer.new()
	catalog_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(catalog_column)
	_filter = TabBar.new()
	for filter in FILTERS:
		_filter.add_tab(tr("RESEARCH_FILTER_" + filter.to_upper()))
	_filter.tab_changed.connect(func(_t): _refresh_catalog())
	catalog_column.add_child(_filter)
	var filter_row := HBoxContainer.new()
	catalog_column.add_child(filter_row)
	_category = OptionButton.new()
	_category.item_selected.connect(func(_i): _refresh_catalog())
	filter_row.add_child(_category)
	_search = LineEdit.new()
	_search.placeholder_text = tr("PRODUCTION_SEARCH")
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t): _refresh_catalog())
	filter_row.add_child(_search)
	_catalog = ScreenKit.list()
	catalog_column.add_child(ScreenKit.scrolling(_catalog))


func _refresh_queue() -> void:
	var points: Dictionary = source.get_points()
	_points.text = (tr("RESEARCH_POINTS").replace("%1%", "%.1f" % points.get("spent", 0.0)).replace(
		"%2%", "%.1f" % points.get("available", 0.0)
	))
	ScreenKit.clear(_queue_list)
	var queue: Array = source.get_queue()
	if queue.is_empty():
		_queue_list.add_child(ScreenKit.label(tr("RESEARCH_EMPTY_QUEUE"), "SecondaryLabel"))
	for i in queue.size():
		_queue_list.add_child(_queue_row(queue[i], i, queue.size()))


func _refresh_catalog() -> void:
	ScreenKit.clear(_catalog)
	var filter: String = FILTERS[_filter.current_tab]
	var category := _selected_category()
	var needle := _search.text.strip_edges().to_lower()
	var shown: Array = []
	for tech: Dictionary in _techs:
		var status: String = tech.get("status", "")
		match filter:
			"researchable":
				if status != "researchable":
					continue
			"open":
				if status == "complete":
					continue
			"complete":
				if status != "complete":
					continue
		if not category.is_empty() and tech.get("category") != category:
			continue
		if not needle.is_empty() and not tr(tech.get("name", "")).to_lower().contains(needle):
			continue
		shown.push_back(tech)
	# Cheapest first: what can be finished soonest.
	shown.sort_custom(func(a, b): return a.get("cost", 0.0) < b.get("cost", 0.0))
	for tech in shown:
		_catalog.add_child(_catalog_row(tech))
	if shown.is_empty():
		_catalog.add_child(ScreenKit.label(tr("RESEARCH_NOTHING_MATCHES"), "SecondaryLabel"))


func _queue_row(entry: Dictionary, position: int, count: int) -> Control:
	var tech_name: String = entry.get("name", "")
	var card := PanelContainer.new()
	var row := HBoxContainer.new()
	card.add_child(row)
	row.add_child(_tech_icon(entry))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", FOUi.tokens.space_1)
	row.add_child(text)
	var name_line := HBoxContainer.new()
	text.add_child(name_line)
	var title := ScreenKit.label(tr(tech_name))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_line.add_child(title)
	name_line.add_child(
		ScreenKit.label(ScreenKit.turns_text(entry.get("turns_left", -1)), "SecondaryLabel")
	)
	var progress := ProgressBar.new()
	progress.max_value = 1.0
	progress.value = entry.get("progress", 0.0)
	progress.show_percentage = false
	progress.custom_minimum_size.y = FOUi.tokens.space_2
	text.add_child(progress)
	var detail := tr("RESEARCH_QUEUE_DETAIL").replace("%1%", tr(entry.get("category", ""))).replace(
		"%2%", "%.1f" % entry.get("allocated_rp", 0.0)
	)
	text.add_child(ScreenKit.label(detail, "SmallLabel"))

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 0)
	row.add_child(buttons)
	var up := ScreenKit.small_button("▲", "PRODUCTION_MOVE_UP", position > 0)
	up.pressed.connect(func(): _order(source.move(tech_name, position - 1)))
	buttons.add_child(up)
	var down := ScreenKit.small_button("▼", "PRODUCTION_MOVE_DOWN", position < count - 1)
	down.pressed.connect(func(): _order(source.move(tech_name, position + 1)))
	buttons.add_child(down)
	var remove := ScreenKit.small_button("✕", "PRODUCTION_REMOVE")
	remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	remove.pressed.connect(func(): _order(source.remove(tech_name), true))
	row.add_child(remove)
	return card


func _catalog_row(tech: Dictionary) -> Control:
	var tech_name: String = tech.get("name", "")
	var status: String = tech.get("status", "")
	var row := HBoxContainer.new()
	row.tooltip_text = tr(tech.get("short_description", ""))
	row.add_child(_tech_icon(tech))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var title := ScreenKit.label(tr(tech_name))
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(title)
	var detail := (
		tr("RESEARCH_ITEM_COST")
		. replace("%1%", "%.0f" % tech.get("cost", 0.0))
		. replace("%2%", str(tech.get("turns", 0)))
		. replace("%3%", tr(tech.get("category", "")))
	)
	if status == "partial" or status == "unresearchable":
		detail += " · " + tr("RESEARCH_NEEDS_PREREQS")
	text.add_child(ScreenKit.label(detail, "SmallLabel"))
	if status != "complete":
		var add := Button.new()
		var queued: bool = tech.get("in_queue", false)
		add.text = tr("RESEARCH_QUEUED") if queued else tr("PRODUCTION_ADD")
		add.disabled = queued
		add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add.pressed.connect(func(): _order(source.enqueue(tech_name), true))
		row.add_child(add)
	return row


func _order(ok: bool, reload_techs := false) -> void:
	if not ok:
		return
	if reload_techs:
		_techs = source.get_techs()
		_refresh_catalog.call_deferred()
	_refresh_queue.call_deferred()


# Tech graphic, or its category's icon for techs without one.
static func _tech_icon(tech: Dictionary) -> TextureRect:
	return ScreenKit.icon(
		tech.get("icon", ""), -1, FOArt.tech_category_icon(tech.get("category", ""))
	)


func _selected_category() -> String:
	if _category == null or _category.selected < 0:
		return ""
	return str(_category.get_item_metadata(_category.selected))
