class_name ResearchScreen
extends PanelContainer
## Research: the queue (progress, ETA, reorder by dragging or arrows,
## pause, remove) on the left, and the techs on the right, filtered by
## availability and one or more categories, searchable, as a list (sorted
## by cost, name, time or category; techs drag into the queue) or as the
## tech tree (TechTreeView; status filter, zoom buttons, Shift+click
## queues).
## Adding a tech also queues its missing prerequisites. Reads and orders
## through `source` (ResearchSource by default; tests set a fake).

signal close_requested
signal pedia_requested(kind: String, article_name: String)

## Availability filters: researchable now, everything not yet researched,
## and researched.
const FILTERS := ["researchable", "open", "complete"]
## Tech statuses the tree can show.
const STATUSES := ["complete", "researchable", "partial", "unresearchable"]
## List sort orders: key, label key.
const SORTS := [
	["cost", "RESEARCH_SORT_COST"],
	["name", "RESEARCH_SORT_NAME"],
	["turns", "RESEARCH_SORT_TURNS"],
	["category", "RESEARCH_SORT_CATEGORY"],
]
const QUEUE_DRAG := "fo_tech_queue"
const TECH_DRAG := "fo_tech"

var source: Variant = ResearchSource.new()
## Statuses shown in the tree: status -> true.
var statuses_shown := {
	"complete": true, "researchable": true, "partial": true, "unresearchable": true
}
## Categories shown besides the picked one: category -> true.
var more_categories := {}

var _points: Label
var _queue_list: VBoxContainer
var _filter: TabBar
var _category: OptionButton
var _more: MenuButton
var _status_menu: MenuButton
var _sort: OptionButton
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
	_sort.visible = not tree
	_status_menu.visible = tree
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
	# More categories at once (GG's category toggles).
	_more = MenuButton.new()
	_more.text = "+"
	_more.flat = false
	_more.tooltip_text = tr("RESEARCH_MORE_CATEGORIES")
	_more.about_to_popup.connect(_fill_more_categories)
	_more.get_popup().hide_on_checkable_item_selection = false
	_more.get_popup().index_pressed.connect(
		func(index: int):
			var popup := _more.get_popup()
			var category: String = popup.get_item_metadata(index)
			if more_categories.has(category):
				more_categories.erase(category)
			else:
				more_categories[category] = true
			popup.set_item_checked(index, more_categories.has(category))
			_refresh_catalog()
	)
	filter_row.add_child(_more)
	_status_menu = MenuButton.new()
	_status_menu.text = tr("RESEARCH_STATUS_FILTER")
	_status_menu.flat = false
	_status_menu.visible = false
	var status_popup := _status_menu.get_popup()
	status_popup.hide_on_checkable_item_selection = false
	for status in STATUSES:
		status_popup.add_check_item(tr("RESEARCH_STATUS_" + status.to_upper()))
		status_popup.set_item_checked(status_popup.item_count - 1, true)
	status_popup.index_pressed.connect(
		func(index: int):
			var status: String = STATUSES[index]
			statuses_shown[status] = not statuses_shown[status]
			status_popup.set_item_checked(index, statuses_shown[status])
			_refresh_catalog()
	)
	filter_row.add_child(_status_menu)
	_sort = OptionButton.new()
	for entry in SORTS:
		_sort.add_item(tr(entry[1]))
	_sort.tooltip_text = tr("RESEARCH_SORT")
	_sort.item_selected.connect(func(_i): _refresh_catalog())
	filter_row.add_child(_sort)
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
	# Shift always means "at the top", as with Add and double-click.
	_tree.tech_queued.connect(func(tech_name): _order(source.enqueue(tech_name, 0), true))
	frame.add_child(_tree)
	# Zoom out, fit, in, over the tree's top right.
	var zoom_row := HBoxContainer.new()
	zoom_row.size_flags_horizontal = Control.SIZE_SHRINK_END
	zoom_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for entry in [
		["−", "RESEARCH_ZOOM_OUT", -1], ["⤢", "RESEARCH_ZOOM_FIT", 0], ["+", "RESEARCH_ZOOM_IN", 1]
	]:
		var button := ScreenKit.small_button(entry[0], entry[1])
		button.pressed.connect(_tree.zoom_step.bind(entry[2]))
		zoom_row.add_child(button)
	frame.add_child(zoom_row)
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
	# Research points no tech takes this turn are lost (GG shows them).
	var wasted: float = points.get("available", 0.0) - points.get("spent", 0.0)
	_points.tooltip_text = (
		tr("RESEARCH_WASTED").replace("%1%", "%.1f" % wasted) if wasted > 0.05 else ""
	)
	if wasted > 0.05:
		_points.add_theme_color_override("font_color", FOUi.tokens.warning)
	else:
		_points.remove_theme_color_override("font_color")
	ScreenKit.clear(_queue_list)
	var queue: Array = source.get_queue()
	var entries := {}
	for entry: Dictionary in queue:
		entries[entry.get("name", "")] = entry
	# The list's and tree's tooltips tell how each queued tech goes.
	_tree.queue_entries = entries
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
		if not category_shown(tech.get("category", "")):
			continue
		if not needle.is_empty() and not tr(tech.get("name", "")).to_lower().contains(needle):
			continue
		shown.push_back(tech)
	sort_techs(shown, SORTS[maxi(_sort.selected, 0)][0])
	for tech in shown:
		_catalog.add_child(_catalog_row(tech))
	if shown.is_empty():
		_catalog.add_child(ScreenKit.label(tr("RESEARCH_NOTHING_MATCHES"), "SecondaryLabel"))


## Whether techs of \a category are shown: the picked category or one of
## the others ticked; all when none is.
func category_shown(category: String) -> bool:
	var picked := _selected_category()
	if picked.is_empty() and more_categories.is_empty():
		return true
	return category == picked or more_categories.has(category)


## Sort \a techs by \a key ("cost": cheapest first, "name", "turns",
## "category").
static func sort_techs(techs: Array, key: String) -> void:
	techs.sort_custom(
		func(a, b):
			match key:
				"name":
					var x := String(TranslationServer.translate(a["name"]))
					return x < String(TranslationServer.translate(b["name"]))
				"turns":
					return a.get("turns", 0) < b.get("turns", 0)
				"category":
					var x := String(TranslationServer.translate(a.get("category", "")))
					var y := String(TranslationServer.translate(b.get("category", "")))
					return x < y or (x == y and a.get("cost", 0.0) < b.get("cost", 0.0))
			return a.get("cost", 0.0) < b.get("cost", 0.0)
	)


func _fill_more_categories() -> void:
	var popup := _more.get_popup()
	popup.clear()
	for category in source.get_categories():
		popup.add_check_item(tr(category))
		popup.set_item_metadata(popup.item_count - 1, category)
		popup.set_item_checked(popup.item_count - 1, more_categories.has(category))


# Queue \a tech_name (with what it needs) at the end; with Shift, at the top.
# The tech named \a tech_name ({name} if unknown).
func _tech(tech_name: String) -> Dictionary:
	for tech: Dictionary in _techs:
		if tech.get("name", "") == tech_name:
			return tech
	return {"name": tech_name}


func _enqueue(tech_name: String) -> void:
	var top := Input.is_key_pressed(KEY_SHIFT)
	_order(source.enqueue(tech_name, 0 if top else -1), true)


func _queue_row(entry: Dictionary, position: int, count: int) -> Control:
	var tech_name: String = entry.get("name", "")
	var card := PanelContainer.new()
	# Click a card to focus it; Delete then removes it.
	card.focus_mode = Control.FOCUS_CLICK
	card.tooltip_text = TechTreeView.describe(_tech(tech_name), entry)
	card.gui_input.connect(
		func(event: InputEvent):
			if event is InputEventKey and event.pressed and event.keycode == KEY_DELETE:
				_order(source.remove(tech_name), true)
				card.accept_event()
			# Clicking a queued tech shows it in the tree (GG centres on it).
			var click := event as InputEventMouseButton
			if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
				if _tree_view.visible:
					_tree.selected = tech_name
					_tree.center_on(tech_name)
	)
	# Drag to reorder; techs dropped here go before it.
	card.set_drag_forwarding(
		func(_at): return {"type": QUEUE_DRAG, "name": tech_name},
		func(_at, data):
			return data is Dictionary and data.get("type", "") in [QUEUE_DRAG, TECH_DRAG],
		func(_at, data): _drop_on_queue(data, position)
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
	row.tooltip_text = TechTreeView.describe(tech, _tree.queue_entries.get(tech_name, {}))
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	if status != "complete":
		row.set_drag_forwarding(
			func(_at): return {"type": TECH_DRAG, "name": tech_name}, Callable(), Callable()
		)
		# Double-click queues it, as in the tree (Shift: at the top).
		row.gui_input.connect(
			func(event: InputEvent):
				var click := event as InputEventMouseButton
				if click and click.double_click and click.button_index == MOUSE_BUTTON_LEFT:
					_enqueue(tech_name)
					row.accept_event()
		)
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
	var shown: Array = _techs.filter(
		func(t):
			return (
				category_shown(t.get("category", ""))
				and statuses_shown.get(t.get("status", ""), true)
			)
	)
	_tree.techs = shown
	var positions := {}
	var queue: Array = source.get_queue()
	var entries := {}
	for i in queue.size():
		positions[queue[i].get("name", "")] = i
		entries[queue[i].get("name", "")] = queue[i]
	_tree.queue_entries = entries
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


# A queued tech moved to, or a tech added at, queue \a position.
func _drop_on_queue(data: Dictionary, position: int) -> void:
	if data.get("type", "") == QUEUE_DRAG:
		_order(source.move(data["name"], position))
	else:
		_order(source.enqueue(data["name"], position), true)


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
