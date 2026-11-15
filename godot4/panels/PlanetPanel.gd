class_name PlanetPanel
extends PanelContainer
## Details of one planet: what it is (type, size, species and how well it
## lives there, focus, owner), its meters (this turn, the change next turn,
## and the target or maximum they move to), buildings (own ones can be
## scrapped) and specials. Names link to the Pedia.
##
## show_planet(id) reads the game; show_data(dict) takes the layout of
## FOUniverse.get_planet_detail() directly (tests, previews).

signal close_requested
signal link_activated(kind: String, arg: String)
## Scrap own building \a building_id, or cancel it.
signal scrap_requested(building_id: int)

const WIDTH := 340
## Meter icons (icons/meter/*.png) where the file isn't the meter's name.
const METER_ICONS := {
	"METER_POPULATION": "pop",
	"METER_HAPPINESS": "happiness",
	"METER_CONSTRUCTION": "construction",
}
## Changes smaller than this show as steady.
const STEADY := 0.05

var planet_id := -1

var _data := {}
var _type_icon: TextureRect
var _title: Label
var _swatch: ColorRect
var _subtitle: Label
var _meters: GridContainer
var _buildings_title: Label
var _buildings: VBoxContainer
var _specials_title: Label
var _specials: VBoxContainer


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "OverlayPanel"
	custom_minimum_size.x = WIDTH
	visible = false
	_build()


## Show planet \a id from the client universe; -1 hides the panel.
func show_planet(id: int) -> void:
	planet_id = id
	show_data(FOUniverse.get_planet_detail(id) if id >= 0 else {})


func refresh() -> void:
	if planet_id >= 0:
		show_planet(planet_id)


func show_data(data: Dictionary) -> void:
	var was_hidden := not visible
	_data = data
	visible = not data.is_empty()
	if data.is_empty():
		return
	planet_id = data.get("id", planet_id)
	if was_hidden:
		FOUi.fade_in(self)
	_type_icon.texture = FOArt.planet_type_icon(data.get("type", ""))
	_title.text = data.get("name", "")
	var owner_name: String = data.get("owner_name", "")
	_swatch.visible = not owner_name.is_empty()
	_swatch.color = data.get("owner_color", Color.WHITE)
	_subtitle.text = subtitle(data)
	_fill_meters(data.get("meters", []))
	_fill_buildings(data.get("buildings", []), data.get("own", false))
	_fill_specials(data.get("specials", []))


## "Medium Terran · Human (Good) · Industry · Empire" for \a data.
static func subtitle(data: Dictionary) -> String:
	var parts: PackedStringArray = []
	var planet_size: String = data.get("size", "")
	var planet_type: String = data.get("type", "")
	if planet_size in ["SZ_GASGIANT", "SZ_ASTEROIDS"] or planet_size.is_empty():
		parts.push_back(_tr(planet_type))
	else:
		parts.push_back("%s %s" % [_tr(planet_size), _tr(planet_type)])
	var species: String = data.get("species", "")
	if not species.is_empty():
		var environment: String = data.get("environment", "")
		parts.push_back(
			(
				"%s (%s)" % [_tr(species), _tr(environment)]
				if not environment.is_empty()
				else _tr(species)
			)
		)
	if not str(data.get("focus", "")).is_empty():
		parts.push_back(_tr(data["focus"]))
	if not str(data.get("owner_name", "")).is_empty():
		parts.push_back(data["owner_name"])
	return " · ".join(parts)


## Text for a meter's change: "+0.4", "−1.0", or "" when steady.
static func change_text(now: float, next: float) -> String:
	var change := next - now
	if absf(change) < STEADY:
		return ""
	return ("+%.1f" if change > 0.0 else "−%.1f") % absf(change)


func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FOUi.tokens.space_2)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_type_icon = ScreenKit.icon("", FOUi.tokens.icon_large)
	header.add_child(_type_icon)
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
	_subtitle = ScreenKit.label("", "SmallLabel")
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_subtitle)
	var close := ScreenKit.small_button("✕", "PANEL_CLOSE")
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(close_requested.emit)
	header.add_child(close)

	_meters = GridContainer.new()
	_meters.columns = 4
	_meters.add_theme_constant_override("h_separation", FOUi.tokens.space_2)
	_meters.add_theme_constant_override("v_separation", 0)
	box.add_child(_meters)
	_buildings_title = ScreenKit.label(tr("PLANET_PANEL_BUILDINGS"), "SecondaryLabel")
	box.add_child(_buildings_title)
	_buildings = VBoxContainer.new()
	box.add_child(_buildings)
	_specials_title = ScreenKit.label(tr("PLANET_PANEL_SPECIALS"), "SecondaryLabel")
	box.add_child(_specials_title)
	_specials = VBoxContainer.new()
	box.add_child(_specials)


# Meter rows: icon, name, value this turn with next turn's change, target.
# Meters that are zero throughout (an empty planet's industry) are left out.
func _fill_meters(meters: Array) -> void:
	ScreenKit.clear(_meters)
	for meter: Dictionary in meters:
		var now: float = meter.get("now", 0.0)
		var next: float = meter.get("next", 0.0)
		var target: float = meter.get("target", 0.0)
		if absf(now) < STEADY and absf(next) < STEADY and absf(target) < STEADY:
			continue
		var key: String = meter.get("meter", "")
		var icon_name: String = METER_ICONS.get(key, key.trim_prefix("METER_").to_lower())
		_meters.add_child(ScreenKit.icon("icons/meter/%s.png" % icon_name, FOUi.tokens.icon_small))
		var label := ScreenKit.label(tr(key), "SmallLabel")
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_meters.add_child(label)
		var value := ScreenKit.label("%.1f" % now)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var change := change_text(now, next)
		if not change.is_empty():
			value.text += " " + change
			value.add_theme_color_override(
				"font_color", FOUi.tokens.positive if next > now else FOUi.tokens.negative
			)
		_meters.add_child(value)
		var goal := ScreenKit.label("/ %.1f" % target, "SmallLabel")
		goal.tooltip_text = tr("PLANET_PANEL_TARGET")
		_meters.add_child(goal)
		for cell in _meters.get_children().slice(-4):
			cell.tooltip_text = (
				tr("PLANET_PANEL_METER_TIP")
				. replace("%1%", tr(key))
				. replace("%2%", "%.1f" % now)
				. replace("%3%", "%.1f" % next)
				. replace("%4%", "%.1f" % target)
			)


func _fill_buildings(buildings: Array, own: bool) -> void:
	ScreenKit.clear(_buildings)
	_buildings_title.visible = not buildings.is_empty()
	for building: Dictionary in buildings:
		var row := HBoxContainer.new()
		row.add_child(ScreenKit.icon(building.get("icon", ""), FOUi.tokens.icon))
		var type: String = building.get("type", "")
		row.add_child(_link("buildingtype", type, building.get("name", tr(type))))
		var scrapping: bool = building.get("scrapping", false)
		if scrapping:
			var note := ScreenKit.label(tr("FLEET_PANEL_SCRAPPING"), "SmallLabel")
			note.add_theme_color_override("font_color", FOUi.tokens.negative)
			row.add_child(note)
		if own:
			var scrap := Button.new()
			scrap.text = tr("PLANET_PANEL_CANCEL_SCRAP" if scrapping else "PLANET_PANEL_SCRAP")
			scrap.theme_type_variation = "GhostButton" if scrapping else "SegmentButton"
			scrap.pressed.connect(scrap_requested.emit.bind(building.get("id", -1)))
			row.add_child(scrap)
		_buildings.add_child(row)


func _fill_specials(specials: Array) -> void:
	ScreenKit.clear(_specials)
	_specials_title.visible = not specials.is_empty()
	for special: Dictionary in specials:
		var row := HBoxContainer.new()
		row.add_child(ScreenKit.icon(special.get("icon", ""), FOUi.tokens.icon))
		var special_name: String = special.get("name", "")
		var link := _link("special", special_name, tr(special_name))
		var capacity: float = special.get("capacity", 0.0)
		if capacity > 0.0:
			link.tooltip_text = tr("PLANET_PANEL_CAPACITY").replace("%1%", "%.1f" % capacity)
		row.add_child(link)
		_specials.add_child(row)


# A Pedia link: \a text for article \a arg of \a kind.
func _link(kind: String, arg: String, text: String) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.text = FORichText.to_bbcode("<%s %s>%s</%s>" % [kind, arg, text, kind])
	label.meta_clicked.connect(
		func(meta: Variant):
			var link := FORichText.parse_link(str(meta))
			link_activated.emit(link["kind"], link["arg"])
	)
	return label


static func _tr(key: String) -> String:
	return TranslationServer.translate(key)
