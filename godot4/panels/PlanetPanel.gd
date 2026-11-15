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

var planet_id := -1:
	set(value):
		planet_id = value
		if _meters:
			_meters.object_id = value
## Returns get_meter_accounting() for (planet_id, meter); tests replace it.
var accounting_provider: Callable:
	get:
		return _meters.accounting_provider
	set(value):
		_meters.accounting_provider = value
## Returns get_planet_suitability() for a planet; tests replace it.
var suitability_provider := func(id: int) -> Array: return FOUniverse.get_planet_suitability(id)

var _data := {}
var _type_icon: TextureRect
var _title: Label
var _swatch: ColorRect
var _subtitle: Label
var _meters: MeterGrid
var _buildings_title: Label
var _buildings: VBoxContainer
var _specials_title: Label
var _specials: VBoxContainer
var _suitability_button: Button
var _suitability: GridContainer


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
	_meters.fill(data.get("meters", []))
	_fill_buildings(data.get("buildings", []), data.get("own", false))
	_fill_specials(data.get("specials", []))
	# The suitability report is worked out on request: it tries every species.
	ScreenKit.clear(_suitability)
	_suitability.visible = false
	_suitability_button.set_pressed_no_signal(false)


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
	return MeterGrid.change_text(now, next)


## Tooltip content for \a meter's breakdown (MeterGrid.accounting_tooltip()).
func accounting_tooltip(meter: String) -> Control:
	return _meters.accounting_tooltip(meter)


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

	_meters = MeterGrid.new()
	box.add_child(_meters)
	_buildings_title = ScreenKit.label(tr("PLANET_PANEL_BUILDINGS"), "SecondaryLabel")
	box.add_child(_buildings_title)
	_buildings = VBoxContainer.new()
	box.add_child(_buildings)
	_specials_title = ScreenKit.label(tr("PLANET_PANEL_SPECIALS"), "SecondaryLabel")
	box.add_child(_specials_title)
	_specials = VBoxContainer.new()
	box.add_child(_specials)
	_suitability_button = Button.new()
	_suitability_button.text = tr("PLANET_PANEL_SUITABILITY")
	_suitability_button.tooltip_text = tr("PLANET_PANEL_SUITABILITY_TIP")
	_suitability_button.toggle_mode = true
	_suitability_button.theme_type_variation = "GhostButton"
	_suitability_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_suitability_button.toggled.connect(show_suitability)
	box.add_child(_suitability_button)
	_suitability = GridContainer.new()
	_suitability.columns = 4
	_suitability.add_theme_constant_override("h_separation", FOUi.tokens.space_2)
	_suitability.visible = false
	box.add_child(_suitability)


## Show (or hide) which species could live here: environment and the
## population each would reach, highest first.
func show_suitability(shown: bool) -> void:
	_suitability_button.set_pressed_no_signal(shown)
	ScreenKit.clear(_suitability)
	_suitability.visible = shown
	if not shown:
		return
	var rows: Array = suitability_provider.call(planet_id)
	if rows.is_empty():
		var none := ScreenKit.label(tr("PLANET_PANEL_SUITABILITY_NONE"), "SecondaryLabel")
		_suitability.add_child(none)
		return
	for row: Dictionary in rows:
		_suitability.add_child(ScreenKit.icon(row.get("icon", ""), FOUi.tokens.icon_small))
		var species: String = row.get("species", "")
		_suitability.add_child(_link("species", species, tr(species)))
		var environment: String = row.get("environment", "")
		var env_label := ScreenKit.label(tr(environment), "SmallLabel")
		env_label.add_theme_color_override("font_color", PediaScreen.environment_color(environment))
		_suitability.add_child(env_label)
		var target: float = row.get("target_population", 0.0)
		var value := ScreenKit.label("%+.1f" % target if target < 0.0 else "%.1f" % target)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.tooltip_text = tr("PLANET_PANEL_SUITABILITY_POP")
		value.add_theme_color_override(
			"font_color", FOUi.tokens.positive if target > 0.0 else FOUi.tokens.negative
		)
		_suitability.add_child(value)


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
	return ScreenKit.pedia_link(kind, arg, text, link_activated.emit)


static func _tr(key: String) -> String:
	return TranslationServer.translate(key)
