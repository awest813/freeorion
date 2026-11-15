class_name ObjectsScreen
extends PanelContainer
## Objects: every known planet, fleet, ship, building or system in a table
## that sorts by any column (click its title) and filters by name and by
## owner. Double-click (or Enter on) a row to show the object on the map.

signal close_requested
signal link_activated(kind: String, arg: String)

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
var _rows: Array = []


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
	_rows = source.list_objects(kind, _only_mine.button_pressed)
	_rebuild()


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
	var rows := _rows.filter(func(row): return _matches(row, needle))
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
	box.add_child(_tree)
	_empty = ScreenKit.label(tr("OBJECTS_EMPTY"), "SecondaryLabel")
	_empty.visible = false
	box.add_child(_empty)


func _columns() -> Array:
	return COLUMNS[kind]


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
	for row: Dictionary in rows:
		var item := _tree.create_item(root)
		item.set_metadata(0, row_link(kind, row))
		for i in columns.size():
			var column: Array = columns[i]
			item.set_text(i, _display(row, column[0]))
			if NUMERIC.has(column[2]):
				item.set_text_alignment(i, HORIZONTAL_ALIGNMENT_RIGHT)
			if column[2] == "owner" and row.get("owner_id", -1) >= 0:
				item.set_custom_color(i, row.get("owner_color", Color.WHITE))
		_set_row_icon(item, row)
	_info.text = tr("OBJECTS_COUNT").replace("%1%", str(rows.size()))
	_empty.visible = rows.is_empty()


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
	sort_key = "name" if _columns()[0][0] == "name" else _columns()[0][0]
	sort_ascending = true
	refresh()


func _on_column_title_clicked(column: int, mouse_button: int) -> void:
	if mouse_button == MOUSE_BUTTON_LEFT:
		sort_by(_columns()[column][0])


func _on_item_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
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
