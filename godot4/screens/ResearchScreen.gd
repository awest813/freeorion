class_name ResearchScreen
extends PanelContainer
## Research: the queue (progress, ETA, reorder, remove) on the left, and the
## techs on the right, filtered by availability and category, searchable,
## as a list or as the tech tree (TechTreeView).
## Adding a tech also queues its missing prerequisites. Reads and orders
## through `source` (ResearchSource by default; tests set a fake).

signal close_requested
signal pedia_requested(kind: String, article_name: String)

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
var _view: TabBar
var _queue_column: Control
var _list_view: Control
var _tree_view: Control
var _tree: TechTreeView
var _detail_title: Label
var _detail_text: Label
var _detail_add: Button
var _detail_pedia: Button
## The tech whose details are shown under the tree.
var _detail_tech := ""


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


## Show the tech tree (true) or the list.
func show_tree(shown: bool) -> void:
	_view.current_tab = 1 if shown else 0


func _on_view_changed(tab: int) -> void:
	var tree := tab == 1
	_list_view.visible = not tree
	_filter.visible = not tree
	_tree_view.visible = tree
	# The tree needs the room more than the queue does.
	_queue_column.size_flags_stretch_ratio = 0.6 if tree else 1.2
	_refresh_catalog()
	if tree and _tree.selected.is_empty():
		_center_tree_on_frontier.call_deferred()


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
	_queue_column = queue_column
	_points = ScreenKit.header(queue_column, "RESEARCH_WND_TITLE", close_requested.emit)
	_queue_list = ScreenKit.list()
	queue_column.add_child(ScreenKit.scrolling(_queue_list))

	var catalog_column := VBoxContainer.new()
	catalog_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(catalog_column)
	_view = TabBar.new()
	_view.add_tab(tr("RESEARCH_VIEW_LIST"))
	_view.add_tab(tr("RESEARCH_VIEW_TREE"))
	catalog_column.add_child(_view)
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
	_list_view = ScreenKit.scrolling(_catalog)
	catalog_column.add_child(_list_view)

	# The tree, and the chosen tech's details under it.
	var tree_box := VBoxContainer.new()
	tree_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_box.visible = false
	catalog_column.add_child(tree_box)
	_tree_view = tree_box
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_box.add_child(frame)
	_tree = TechTreeView.new()
	_tree.tech_selected.connect(_show_tech_detail)
	_tree.tech_activated.connect(_enqueue)
	frame.add_child(_tree)
	var detail := HBoxContainer.new()
	tree_box.add_child(detail)
	var detail_text := VBoxContainer.new()
	detail_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_text.add_theme_constant_override("separation", 0)
	detail.add_child(detail_text)
	_detail_title = ScreenKit.label(tr("RESEARCH_TREE_HINT"), "SecondaryLabel")
	detail_text.add_child(_detail_title)
	_detail_text = ScreenKit.label("", "SmallLabel")
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_text.add_child(_detail_text)
	_detail_pedia = ScreenKit.small_button("?", "PEDIA_OPEN")
	_detail_pedia.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_detail_pedia.visible = false
	_detail_pedia.pressed.connect(func(): pedia_requested.emit("tech", _detail_tech))
	detail.add_child(_detail_pedia)
	_detail_add = Button.new()
	_detail_add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_detail_add.visible = false
	_detail_add.tooltip_text = tr("QUEUE_ADD_TOP_TIP")
	_detail_add.pressed.connect(func(): _enqueue(_detail_tech))
	detail.add_child(_detail_add)
	_view.tab_changed.connect(_on_view_changed)


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
	if _tree_view.visible:
		_refresh_tree()
		return
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


# Queue \a tech_name (with what it needs) at the end; with Shift, at the top.
func _enqueue(tech_name: String) -> void:
	var top := Input.is_key_pressed(KEY_SHIFT)
	_order(source.enqueue(tech_name, 0 if top else -1), true)


func _queue_row(entry: Dictionary, position: int, count: int) -> Control:
	var tech_name: String = entry.get("name", "")
	var card := PanelContainer.new()
	# Click a card to focus it; Delete then removes it.
	card.focus_mode = Control.FOCUS_CLICK
	card.gui_input.connect(
		func(event: InputEvent):
			if event is InputEventKey and event.pressed and event.keycode == KEY_DELETE:
				_order(source.remove(tech_name), true)
				card.accept_event()
	)
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
	# Paused research keeps its place but gets no RP.
	var paused: bool = entry.get("paused", false)
	if paused:
		detail += " · " + tr("PRODUCTION_PAUSED")
		card.modulate = Color(1, 1, 1, 0.6)
	text.add_child(ScreenKit.label(detail, "SmallLabel"))
	var pause := ScreenKit.small_button(
		"▶" if paused else "Ⅱ", "RESEARCH_RESUME" if paused else "RESEARCH_PAUSE"
	)
	pause.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pause.pressed.connect(func(): _order(source.set_paused(tech_name, not paused)))
	row.add_child(pause)

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
	var info := ScreenKit.small_button("?", "PEDIA_OPEN")
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.pressed.connect(pedia_requested.emit.bind("tech", tech_name))
	row.add_child(info)
	if status != "complete":
		var add := Button.new()
		var queued: bool = tech.get("in_queue", false)
		add.text = tr("RESEARCH_QUEUED") if queued else tr("PRODUCTION_ADD")
		# Missing prerequisites are queued first, in order.
		if not queued and status in ["partial", "unresearchable"]:
			add.text = tr("RESEARCH_ADD_WITH_PREREQS")
			add.tooltip_text = tr("RESEARCH_ADD_WITH_PREREQS_TIP")
		add.disabled = queued
		add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if add.tooltip_text.is_empty():
			add.tooltip_text = tr("QUEUE_ADD_TOP_TIP")
		add.pressed.connect(_enqueue.bind(tech_name))
		row.add_child(add)
	return row


# The tree shows the chosen category (all by default); a search selects and
# centres the first match.
func _refresh_tree() -> void:
	var category := _selected_category()
	var shown: Array = _techs.filter(
		func(t): return category.is_empty() or t.get("category") == category
	)
	_tree.techs = shown
	var positions := {}
	var queue: Array = source.get_queue()
	for i in queue.size():
		positions[queue[i].get("name", "")] = i
	_tree.queue_positions = positions
	var needle := _search.text.strip_edges().to_lower()
	if not needle.is_empty():
		for tech: Dictionary in shown:
			if tr(tech["name"]).to_lower().contains(needle):
				_tree.selected = tech["name"]
				_tree.center_on(tech["name"])
				break
	_show_tech_detail(_tree.selected)


# Start where research is happening: the first researchable tech.
func _center_tree_on_frontier() -> void:
	for tech: Dictionary in _tree.techs:
		if tech.get("status", "") == "researchable":
			_tree.center_on(tech["name"])
			return


func _show_tech_detail(tech_name: String) -> void:
	_detail_tech = tech_name
	var tech: Dictionary = {}
	for candidate: Dictionary in _techs:
		if candidate.get("name") == tech_name:
			tech = candidate
	_detail_pedia.visible = not tech.is_empty()
	_detail_add.visible = not tech.is_empty() and tech.get("status") != "complete"
	if tech.is_empty():
		_detail_title.text = tr("RESEARCH_TREE_HINT")
		_detail_text.text = ""
		return
	_detail_title.text = tr(tech_name)
	_detail_text.text = (
		tr("RESEARCH_ITEM_COST")
		. replace("%1%", "%.0f" % tech.get("cost", 0.0))
		. replace("%2%", str(tech.get("turns", 0)))
		. replace("%3%", tr(tech.get("category", "")))
	)
	var description := tr(tech.get("short_description", ""))
	if not description.is_empty() and not description.begins_with("ERROR: "):
		_detail_text.text += "\n" + description
	var queued: bool = tech.get("in_queue", false)
	_detail_add.disabled = queued
	_detail_add.text = tr("RESEARCH_QUEUED") if queued else tr("PRODUCTION_ADD")
	if not queued and tech.get("status") in ["partial", "unresearchable"]:
		_detail_add.text = tr("RESEARCH_ADD_WITH_PREREQS")


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
