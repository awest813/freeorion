class_name ShipPanel
extends PanelContainer
## Details of one ship, as the GG fleet window's ship rows: design, species
## and owner; what it does in combat and carries (damage, fighters, troops,
## colonists); its meters with their breakdowns; and its parts with their
## capacities. Design, hull, species and parts link to the Pedia.
##
## show_ship(id) reads the game; show_data(dict) takes the layout of
## FOUniverse.get_ship_detail() directly (tests, previews).

signal close_requested
signal link_activated(kind: String, arg: String)

const WIDTH := 340
## Combat and cargo stats: key, icon (icons/meter/), title key, tip key.
const STATS := [
	["damage", "damage", "SHIP_DAMAGE_STAT_TITLE", "SHIP_PANEL_DAMAGE_TIP"],
	["destroy", "ammo", "SHIP_DESTRUCTION_STAT_TITLE", "SHIP_PANEL_DESTROY_TIP"],
	["fighters", "fighters", "SHIP_FIGHTERS_TITLE", "SHIP_FIGHTERS_STAT"],
	["troops", "troops", "SHIP_TROOPS_TITLE", "SHIP_TROOPS_STAT"],
	["colony", "colony", "SHIP_COLONY_TITLE", "SHIP_COLONY_STAT"],
]

var ship_id := -1:
	set(value):
		ship_id = value
		if _meters:
			_meters.object_id = value
## Returns get_meter_accounting() for (ship_id, meter); tests replace it.
var accounting_provider: Callable:
	get:
		return _meters.accounting_provider
	set(value):
		_meters.accounting_provider = value

var _icon: TextureRect
var _title: Label
var _swatch: ColorRect
var _subtitle: RichTextLabel
var _stats: HFlowContainer
var _meters: MeterGrid
var _parts_title: Label
var _parts: GridContainer


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "OverlayPanel"
	custom_minimum_size.x = WIDTH
	visible = false
	_build()


## Show ship \a id from the client universe; -1 hides the panel.
func show_ship(id: int) -> void:
	ship_id = id
	show_data(FOUniverse.get_ship_detail(id) if id >= 0 else {})


func refresh() -> void:
	if ship_id >= 0:
		show_ship(ship_id)


func show_data(data: Dictionary) -> void:
	var was_hidden := not visible
	visible = not data.is_empty()
	if data.is_empty():
		ship_id = -1
		return
	ship_id = data.get("id", ship_id)
	if was_hidden:
		FOUi.fade_in(self)
	_icon.texture = FOArt.icon(data.get("icon", ""))
	_title.text = data.get("name", "")
	var owner_name: String = data.get("owner_name", "")
	_swatch.visible = not owner_name.is_empty()
	_swatch.color = data.get("owner_color", Color.WHITE)
	_subtitle.text = FORichText.to_bbcode(subtitle(data))
	_fill_stats(data.get("stats", []))
	_meters.fill(data.get("meters", []))
	_fill_parts(data.get("parts", []))


## Design, hull and species (linked) and owner, joined by " · ", in
## FORichText markup.
static func subtitle(data: Dictionary) -> String:
	var parts: PackedStringArray = []
	var design: String = data.get("design", "")
	if not design.is_empty():
		parts.push_back(design)
	var hull: String = data.get("hull", "")
	if not hull.is_empty():
		parts.push_back("<shiphull %s>%s</shiphull>" % [hull, _tr(hull)])
	var species: String = data.get("species", "")
	if not species.is_empty():
		parts.push_back("<species %s>%s</species>" % [species, _tr(species)])
	if not str(data.get("owner_name", "")).is_empty():
		parts.push_back(data["owner_name"])
	if data.get("scrapping", false):
		parts.push_back(_tr("FLEET_PANEL_SCRAPPING"))
	return " · ".join(parts)


## A part's capacity as shown: "18", "2 / 3" while below its maximum, or ""
## for parts without one (armour shows its structure in the meters).
static func capacity_text(part: Dictionary) -> String:
	var capacity: float = part.get("capacity", -1.0)
	if capacity < 0.0:
		return ""
	var maximum: float = part.get("max_capacity", -1.0)
	if maximum >= 0.0 and maximum - capacity > MeterGrid.STEADY:
		return "%s / %s" % [_number(capacity), _number(maximum)]
	return _number(capacity)


func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FOUi.tokens.space_2)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_icon = ScreenKit.icon("", FOUi.tokens.icon_large)
	header.add_child(_icon)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	var title_row := HBoxContainer.new()
	titles.add_child(title_row)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(FOUi.tokens.space_3, FOUi.tokens.space_3)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_swatch)
	_title = ScreenKit.label("", "TitleLabel")
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title)
	_subtitle = RichTextLabel.new()
	_subtitle.bbcode_enabled = true
	_subtitle.fit_content = true
	_subtitle.scroll_active = false
	_subtitle.add_theme_font_size_override("normal_font_size", FOUi.tokens.font_size_small)
	_subtitle.add_theme_color_override("default_color", FOUi.tokens.text_secondary)
	_subtitle.meta_clicked.connect(_on_meta_clicked)
	titles.add_child(_subtitle)
	var close := ScreenKit.small_button("✕", "PANEL_CLOSE")
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(close_requested.emit)
	header.add_child(close)

	_stats = HFlowContainer.new()
	_stats.add_theme_constant_override("h_separation", FOUi.tokens.space_3)
	box.add_child(_stats)
	_meters = MeterGrid.new()
	box.add_child(_meters)
	_parts_title = ScreenKit.label(tr("SHIP_PANEL_PARTS"), "SecondaryLabel")
	box.add_child(_parts_title)
	_parts = GridContainer.new()
	_parts.columns = 3
	_parts.add_theme_constant_override("h_separation", FOUi.tokens.space_2)
	_parts.add_theme_constant_override("v_separation", 0)
	box.add_child(_parts)


func _fill_stats(stats: Array) -> void:
	ScreenKit.clear(_stats)
	_stats.visible = not stats.is_empty()
	for stat: Dictionary in stats:
		var entry: Array = STATS.filter(func(e): return e[0] == stat.get("stat", ""))
		if entry.is_empty():
			continue
		var chip := HBoxContainer.new()
		chip.tooltip_text = "%s\n%s" % [tr(entry[0][2]), tr(entry[0][3])]
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		var icon := ScreenKit.icon("icons/meter/%s.png" % entry[0][1], FOUi.tokens.icon_small)
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.add_child(icon)
		var value := ScreenKit.label(_number(stat.get("value", 0.0)))
		value.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.add_child(value)
		_stats.add_child(chip)


# Parts once per name: icon, "2 × Mass Driver" linked to the Pedia, capacity.
func _fill_parts(parts: Array) -> void:
	ScreenKit.clear(_parts)
	_parts_title.visible = not parts.is_empty()
	for part: Dictionary in parts:
		_parts.add_child(ScreenKit.icon(part.get("icon", ""), FOUi.tokens.icon_small))
		var part_name: String = part.get("name", "")
		var count: int = part.get("count", 1)
		var text := _tr(part_name) if count == 1 else "%d × %s" % [count, _tr(part_name)]
		var link := ScreenKit.pedia_link("shippart", part_name, text, link_activated.emit)
		link.tooltip_text = ScreenKit.tr_or_name(part.get("class", ""))
		_parts.add_child(link)
		var capacity := ScreenKit.label(capacity_text(part), "SmallLabel")
		capacity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		capacity.tooltip_text = tr("SHIP_PANEL_CAPACITY")
		_parts.add_child(capacity)


func _on_meta_clicked(meta: Variant) -> void:
	var link := FORichText.parse_link(str(meta))
	link_activated.emit(link["kind"], link["arg"])


static func _number(value: float) -> String:
	return str(int(round(value))) if is_equal_approx(value, round(value)) else "%.1f" % value


static func _tr(key: String) -> String:
	return TranslationServer.translate(key)
