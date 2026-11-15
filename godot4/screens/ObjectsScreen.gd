class_name ObjectsScreen
extends PanelContainer
## Objects: every known planet, fleet, ship, building or system in a table
## that sorts by any column (click its title) and filters by name, owner and
## a preset per kind (populated planets, idle fleets, ...). Rows can be
## grouped (by location, owner, ...) with totals per group. Right-click a
## title to choose the columns, a row for its actions. Double-click (or
## Enter on) a row to show the object on the map.

signal close_requested
signal link_activated(kind: String, arg: String)
## "Build here" on own planet \a planet_id.
signal production_requested(planet_id: int)

## Row menu ids.
enum { ACTION_MAP, ACTION_PEDIA, ACTION_BUILD }

## Kinds: list name, tab label key.
const KINDS := [
	["planets", "OBJECTS_PLANETS"],
	["fleets", "OBJECTS_FLEETS"],
	["ships", "OBJECTS_SHIPS"],
	["buildings", "OBJECTS_BUILDINGS"],
	["systems", "OBJECTS_SYSTEMS"],
]
## Columns per kind: row key, title key, format. Formats: text, tr (a
## stringtable key), number, int, owner, eta, structure, stance, location.
const COLUMNS := {
	"planets":
	[
		["name", "NAME", "text"],
		["system_name", "OBJECTS_COL_LOCATION", "text"],
		["owner_name", "OWNER", "owner"],
		["species", "SPECIES", "tr"],
		["focus", "FOCUS", "tr"],
		["population", "METER_POPULATION", "number"],
		["industry", "METER_INDUSTRY", "number"],
		["research", "METER_RESEARCH", "number"],
		["influence", "METER_INFLUENCE", "number"],
		["stability", "METER_HAPPINESS", "number"],
		["supply", "METER_SUPPLY", "int"],
		["defense", "METER_DEFENSE", "int"],
		["troops", "METER_TROOPS", "number"],
		["type", "OBJECTS_COL_TYPE", "tr"],
		["size", "OBJECTS_COL_SIZE", "tr"],
		["shield", "METER_SHIELD", "int"],
	],
	"fleets":
	[
		["name", "NAME", "text"],
		["system_name", "OBJECTS_COL_LOCATION", "location"],
		["owner_name", "OWNER", "owner"],
		["ships", "OBJECTS_COL_SHIPS", "int"],
		["structure", "METER_STRUCTURE", "structure"],
		["destination", "OBJECTS_COL_DESTINATION", "text"],
		["eta", "OBJECTS_COL_ETA", "eta"],
		["aggression", "OBJECTS_COL_STANCE", "stance"],
		["colony_ships", "OBJECTS_COL_COLONY_SHIPS", "int"],
	],
	"ships":
	[
		["name", "NAME", "text"],
		["design", "OBJECTS_COL_DESIGN", "text"],
		["fleet_name", "OBJECTS_COL_FLEET", "text"],
		["system_name", "OBJECTS_COL_LOCATION", "text"],
		["owner_name", "OWNER", "owner"],
		["species", "SPECIES", "tr"],
		["structure", "METER_STRUCTURE", "structure"],
	],
	"buildings":
	[
		["building_type", "OBJECTS_COL_TYPE", "tr"],
		["planet_name", "OBJECTS_COL_PLANET", "text"],
		["system_name", "OBJECTS_COL_LOCATION", "text"],
		["owner_name", "OWNER", "owner"],
	],
	"systems":
	[
		["name", "NAME", "text"],
		["star", "OBJECTS_COL_STAR", "tr"],
		["planets", "OBJECTS_COL_PLANETS", "int"],
		["fleets", "OBJECTS_COL_FLEETS", "int"],
	],
}
## Columns hidden until chosen in the column menu: "kind:key".
const OPTIONAL_COLUMNS := ["planets:type", "planets:size", "planets:shield", "fleets:colony_ships"]
## Filter presets per kind: name, label key ("all" first).
const FILTERS := {
	"planets":
	[
		["all", "OBJECTS_FILTER_ALL"],
		["populated", "OBJECTS_FILTER_POPULATED"],
		["outposts", "OBJECTS_FILTER_OUTPOSTS"]
	],
	"fleets":
	[
		["all", "OBJECTS_FILTER_ALL"],
		["moving", "OBJECTS_FILTER_MOVING"],
		["idle", "OBJECTS_FILTER_IDLE"]
	],
	"ships": [["all", "OBJECTS_FILTER_ALL"], ["damaged", "OBJECTS_FILTER_DAMAGED"]],
	"buildings": [["all", "OBJECTS_FILTER_ALL"]],
	"systems": [["all", "OBJECTS_FILTER_ALL"]],
}
## Grouping per kind: row key ("" for none).
const GROUPS := {
	"planets": ["", "system_name", "owner_name", "species"],
	"fleets": ["", "system_name", "owner_name"],
	"ships": ["", "fleet_name", "design", "system_name", "species"],
	"buildings": ["", "system_name", "building_type"],
	"systems": [""],
}
## Formats shown right-aligned and sorted as numbers.
const NUMERIC := ["number", "int", "eta", "structure"]
## Width of number columns: fits the titles, leaves the rest to names.
const NUMBER_WIDTH := 84

var source: Variant = ObjectsSource.new()
## Shown kind (a KINDS name), sort column key and direction.
var kind := "planets"
var sort_key := "name"
var sort_ascending := true

var _info: Label
var _tabs: TabBar
var _only_mine: CheckBox
var _search: LineEdit
var _tree: Tree
var _empty: Label
var _filter: OptionButton
var _group: OptionButton
var _rows: Array = []
## Columns shown or hidden against their default: "kind:key" -> shown.
var _column_choice := {}
var _menu: PopupMenu


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "BackgroundPanel"
	_build()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


## Reload the rows of the shown kind from the game.
func refresh() -> void:
	if _column_choice.is_empty():
		_column_choice = parse_column_choice(source.load_columns())
	_rows = source.list_objects(kind, _only_mine.button_pressed)
	_rebuild()


## Whether column \a key of the shown kind is shown.
func is_column_shown(key: String) -> bool:
	var id := "%s:%s" % [kind, key]
	return _column_choice.get(id, not OPTIONAL_COLUMNS.has(id))


## Show or hide column \a key of the shown kind; remembered in the options.
func set_column_shown(key: String, shown: bool) -> void:
	var id := "%s:%s" % [kind, key]
	if shown == (not OPTIONAL_COLUMNS.has(id)):
		_column_choice.erase(id)
	else:
		_column_choice[id] = shown
	if sort_key == key and not shown:
		sort_key = _columns()[0][0]
	source.save_columns(column_choice_text(_column_choice))
	_rebuild()


## Column choices from option text "planets:type=1 fleets:eta=0".
static func parse_column_choice(text: String) -> Dictionary:
	var choice := {}
	for part in text.split(" ", false):
		var pair := part.split("=")
		if pair.size() == 2:
			choice[pair[0]] = pair[1] == "1"
	return choice


static func column_choice_text(choice: Dictionary) -> String:
	var parts: PackedStringArray = []
	for id in choice:
		parts.push_back("%s=%d" % [id, 1 if choice[id] else 0])
	return " ".join(parts)


## Show \a kind_name ("planets", "fleets", ...).
func show_kind(kind_name: String) -> void:
	for i in KINDS.size():
		if KINDS[i][0] == kind_name:
			_tabs.current_tab = i
			return


## Sort by \a key; the same key again flips the direction.
func sort_by(key: String) -> void:
	if key == sort_key:
		sort_ascending = not sort_ascending
	else:
		sort_key = key
		sort_ascending = not _is_numeric(key)
	_rebuild()


## Rows of the shown kind as filtered and sorted on screen.
func shown_rows() -> Array:
	var needle := _search.text.strip_edges().to_lower()
	var preset := _filter_name()
	var rows := _rows.filter(
		func(row): return _matches(row, needle) and passes_filter(kind, preset, row)
	)
	var numeric := _is_numeric(sort_key)
	var key := sort_key
	var ascending := sort_ascending
	rows.sort_custom(
		func(a, b):
			var x: Variant = a.get(key, 0 if numeric else "")
			var y: Variant = b.get(key, 0 if numeric else "")
			if not numeric:
				x = _display(a, key).to_lower()
				y = _display(b, key).to_lower()
			if x == y:
				return a["id"] < b["id"]
			return (x < y) == ascending
	)
	return rows


## Whether \a row of \a kind_name passes filter preset \a preset.
static func passes_filter(kind_name: String, preset: String, row: Dictionary) -> bool:
	match [kind_name, preset]:
		["planets", "populated"]:
			return not str(row.get("species", "")).is_empty()
		["planets", "outposts"]:
			return str(row.get("species", "")).is_empty() and row.get("owner_id", -1) >= 0
		["fleets", "moving"]:
			return not str(row.get("destination", "")).is_empty()
		["fleets", "idle"]:
			return str(row.get("destination", "")).is_empty() and not row.get("moving", false)
		["ships", "damaged"]:
			return row.get("structure", 0.0) < row.get("max_structure", 0.0) - 0.01
	return true


func _filter_name() -> String:
	var presets: Array = FILTERS[kind]
	var index := clampi(_filter.selected, 0, presets.size() - 1)
	return presets[index][0]


func _group_key() -> String:
	var keys: Array = GROUPS[kind]
	return keys[clampi(_group.selected, 0, keys.size() - 1)]


func _build() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	_info = ScreenKit.header(box, "MAP_BTN_OBJECTS", close_requested.emit)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", FOUi.tokens.space_4)
	box.add_child(toolbar)
	_tabs = TabBar.new()
	for entry in KINDS:
		_tabs.add_tab(tr(entry[1]))
	_tabs.clip_tabs = false
	_tabs.tab_changed.connect(_on_tab_changed)
	toolbar.add_child(_tabs)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	_only_mine = CheckBox.new()
	_only_mine.text = tr("OBJECTS_ONLY_MINE")
	_only_mine.button_pressed = true
	_only_mine.toggled.connect(func(_on): refresh())
	toolbar.add_child(_only_mine)
	_filter = OptionButton.new()
	_filter.tooltip_text = tr("OBJECTS_FILTER_TIP")
	_filter.item_selected.connect(func(_i): _rebuild())
	toolbar.add_child(_filter)
	_group = OptionButton.new()
	_group.tooltip_text = tr("OBJECTS_GROUP_TIP")
	_group.item_selected.connect(func(_i): _rebuild())
	toolbar.add_child(_group)
	_search = LineEdit.new()
	_search.placeholder_text = tr("OBJECTS_SEARCH")
	_search.clear_button_enabled = true
	_search.custom_minimum_size.x = 260
	_search.text_changed.connect(func(_t): _rebuild())
	toolbar.add_child(_search)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.column_titles_visible = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.tooltip_text = tr("OBJECTS_ACTIVATE_HINT")
	_tree.column_title_clicked.connect(_on_column_title_clicked)
	_tree.item_activated.connect(_on_item_activated)
	_tree.allow_rmb_select = true
	_tree.item_mouse_selected.connect(_on_item_mouse_selected)
	box.add_child(_tree)
	_fill_pickers()
	_empty = ScreenKit.label(tr("OBJECTS_EMPTY"), "SecondaryLabel")
	_empty.visible = false
	box.add_child(_empty)


# Filter and group choices for the shown kind.
func _fill_pickers() -> void:
	_filter.clear()
	for preset in FILTERS[kind]:
		_filter.add_item(tr(preset[1]))
	_filter.select(0)
	_filter.visible = _filter.item_count > 1
	_group.clear()
	for key: String in GROUPS[kind]:
		_group.add_item(
			(
				tr("OBJECTS_GROUP_NONE")
				if key.is_empty()
				else tr("OBJECTS_GROUP_BY").replace("%1%", tr(_title_key(key)))
			)
		)
	_group.select(0)
	_group.visible = _group.item_count > 1


func _title_key(key: String) -> String:
	for column in COLUMNS[kind]:
		if column[0] == key:
			return column[1]
	return key


## The shown columns of the shown kind.
func _columns() -> Array:
	return COLUMNS[kind].filter(func(column): return is_column_shown(column[0]))


func _is_numeric(key: String) -> bool:
	for column in _columns():
		if column[0] == key:
			return NUMERIC.has(column[2])
	return false


func _matches(row: Dictionary, needle: String) -> bool:
	if needle.is_empty():
		return true
	for column in _columns():
		if column[2] in ["text", "tr", "owner", "location"]:
			if _display(row, column[0]).to_lower().contains(needle):
				return true
	return false


func _rebuild() -> void:
	var columns := _columns()
	_tree.clear()
	_tree.columns = columns.size()
	for i in columns.size():
		var key: String = columns[i][0]
		var title := tr(columns[i][1])
		if key == sort_key:
			title += " ▲" if sort_ascending else " ▼"
		_tree.set_column_title(i, title)
		var numeric: bool = NUMERIC.has(columns[i][2])
		_tree.set_column_title_alignment(
			i, HORIZONTAL_ALIGNMENT_RIGHT if numeric else HORIZONTAL_ALIGNMENT_LEFT
		)
		_tree.set_column_expand(i, not numeric)
		_tree.set_column_expand_ratio(i, 3 if i == 0 else 2)
		_tree.set_column_clip_content(i, not numeric)
		_tree.set_column_custom_minimum_width(i, NUMBER_WIDTH if numeric else 0)
	var root := _tree.create_item()
	var rows := shown_rows()
	var group_key := _group_key()
	var groups := {}
	for row: Dictionary in rows:
		var parent := root
		if not group_key.is_empty():
			var value := _display(row, group_key)
			if not groups.has(value):
				groups[value] = _group_item(root, value)
			parent = groups[value]
			_add_to_group(parent, row)
		var item := _tree.create_item(parent)
		item.set_metadata(0, row_link(kind, row))
		item.set_meta("row", row)
		for i in columns.size():
			var column: Array = columns[i]
			item.set_text(i, _display(row, column[0]))
			if NUMERIC.has(column[2]):
				item.set_text_alignment(i, HORIZONTAL_ALIGNMENT_RIGHT)
			if column[2] == "owner" and row.get("owner_id", -1) >= 0:
				item.set_custom_color(i, row.get("owner_color", Color.WHITE))
		_set_row_icon(item, row)
	for group: TreeItem in groups.values():
		_finish_group(group)
	_info.text = tr("OBJECTS_COUNT").replace("%1%", str(rows.size()))
	_empty.visible = rows.is_empty()


# A group heading: its value, how many rows, and the totals of number
# columns (filled in by _add_to_group()).
func _group_item(root: TreeItem, value: String) -> TreeItem:
	var item := _tree.create_item(root)
	item.set_meta("group", value if not value.is_empty() else tr("OBJECTS_GROUP_UNKNOWN"))
	item.set_meta("count", 0)
	item.set_meta("totals", {})
	item.set_selectable(0, false)
	for i in _tree.columns:
		item.set_custom_bg_color(i, Color(FOUi.tokens.surface_overlay, 0.6))
	return item


func _add_to_group(group: TreeItem, row: Dictionary) -> void:
	group.set_meta("count", group.get_meta("count") + 1)
	var totals: Dictionary = group.get_meta("totals")
	var columns := _columns()
	for i in columns.size():
		if (
			columns[i][2] in ["number", "int"]
			and not (kind == "planets" and str(row.get("species", "")).is_empty())
		):
			totals[i] = totals.get(i, 0.0) + float(row.get(columns[i][0], 0.0))


func _finish_group(group: TreeItem) -> void:
	group.set_text(0, "%s (%d)" % [group.get_meta("group"), group.get_meta("count")])
	var columns := _columns()
	var totals: Dictionary = group.get_meta("totals")
	for i in totals:
		var value: float = totals[i]
		group.set_text(i, "%.1f" % value if columns[i][2] == "number" else str(int(value)))
		group.set_text_alignment(i, HORIZONTAL_ALIGNMENT_RIGHT)


func _set_row_icon(item: TreeItem, row: Dictionary) -> void:
	var texture: Texture2D = null
	match kind:
		"planets":
			texture = FOArt.planet_type_icon(row.get("type", ""))
		"ships":
			texture = FOArt.icon(row.get("icon", ""))
	if texture:
		item.set_icon(0, texture)
		item.set_icon_max_width(0, FOUi.tokens.icon_small + FOUi.tokens.space_1)


## Text shown for \a key of \a row.
func _display(row: Dictionary, key: String) -> String:
	var format := "text"
	for column in _columns():
		if column[0] == key:
			format = column[2]
	var value: Variant = row.get(key, "")
	var text := str(value)
	# Planets nobody lives on have no meters worth showing.
	if kind == "planets" and NUMERIC.has(format) and str(row.get("species", "")).is_empty():
		return ""
	match format:
		"tr":
			text = tr(value) if not text.is_empty() else ""
		"number":
			text = "%.1f" % value
		"int":
			text = str(int(value))
		"eta":
			text = GameShell.eta_text(int(value)) if row.get("destination", "") != "" else ""
		"structure":
			text = "%.0f / %.0f" % [value, row.get("max_structure", 0.0)]
		"stance":
			text = _stance_text(text)
		"location":
			if row.get("moving", false) and not text.is_empty():
				text = tr("SYSTEM_PANEL_FLEET_DESTINATION").replace("%1%", text)
	return text


static func _stance_text(stance: String) -> String:
	for entry in FleetPanel.STANCES:
		if entry[0] == stance:
			return TranslationServer.translate(entry[1])
	return ""


func _on_tab_changed(tab: int) -> void:
	kind = KINDS[tab][0]
	_fill_pickers()
	sort_key = "name" if _columns()[0][0] == "name" else _columns()[0][0]
	sort_ascending = true
	refresh()


func _on_column_title_clicked(column: int, mouse_button: int) -> void:
	if mouse_button == MOUSE_BUTTON_LEFT:
		sort_by(_columns()[column][0])
	elif mouse_button == MOUSE_BUTTON_RIGHT:
		open_column_menu()


## Tick the columns to show (the first, the name, always stays).
func open_column_menu() -> PopupMenu:
	var menu := _new_menu()
	var columns: Array = COLUMNS[kind]
	for i in range(1, columns.size()):
		menu.add_check_item(tr(columns[i][1]), i)
		menu.set_item_checked(menu.item_count - 1, is_column_shown(columns[i][0]))
	menu.id_pressed.connect(
		func(id: int): set_column_shown(columns[id][0], not is_column_shown(columns[id][0]))
	)
	menu.popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))
	return menu


## Actions for \a row: show on the map, its Pedia article, build there.
func open_row_menu(row: Dictionary) -> PopupMenu:
	var menu := _new_menu()
	menu.add_item(tr("OBJECTS_SHOW_ON_MAP"), ACTION_MAP)
	var article := pedia_article(kind, row)
	if not article.is_empty():
		menu.add_item(tr("OBJECTS_PEDIA").replace("%1%", tr(article[1])), ACTION_PEDIA)
	var own: bool = row.get("owner_id", -1) == source.empire_id() and row.get("owner_id", -1) >= 0
	if kind == "planets" and own:
		menu.add_item(tr("OBJECTS_BUILD_HERE"), ACTION_BUILD)
	menu.id_pressed.connect(
		func(id: int):
			match id:
				ACTION_MAP:
					var link := row_link(kind, row)
					link_activated.emit(link[0], link[1])
				ACTION_PEDIA:
					link_activated.emit(article[0], article[1])
				ACTION_BUILD:
					production_requested.emit(row["id"])
	)
	menu.popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))
	return menu


## The Pedia article for \a row of \a kind_name: [kind, name], or [].
static func pedia_article(kind_name: String, row: Dictionary) -> Array:
	if kind_name == "buildings" and not str(row.get("building_type", "")).is_empty():
		return ["buildingtype", row["building_type"]]
	if kind_name in ["planets", "ships"] and not str(row.get("species", "")).is_empty():
		return ["species", row["species"]]
	return []


func _new_menu() -> PopupMenu:
	if is_instance_valid(_menu):
		_menu.queue_free()
	_menu = PopupMenu.new()
	_menu.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_menu)
	return _menu


func _on_item_mouse_selected(_position: Vector2, mouse_button: int) -> void:
	var item := _tree.get_selected()
	if mouse_button == MOUSE_BUTTON_RIGHT and item and item.has_meta("row"):
		open_row_menu(item.get_meta("row"))


func _on_item_activated() -> void:
	var item := _tree.get_selected()
	if item == null or not item.has_meta("row"):
		return
	var link: Array = item.get_metadata(0)
	link_activated.emit(link[0], link[1])


## The map link for \a row of \a kind_name: [link kind, id]. Buildings
## show their planet.
static func row_link(kind_name: String, row: Dictionary) -> Array:
	match kind_name:
		"buildings":
			return ["planet", str(row.get("planet_id", -1))]
		"systems":
			return ["system", str(row["id"])]
	return [kind_name.trim_suffix("s"), str(row["id"])]
