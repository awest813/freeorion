class_name SystemPanel
extends PanelContainer
## Context panel for the selected system: star, planets (type, size, owner,
## species, focus, population) and fleets present.
##
## show_system(id) reads the client universe; show_data(dict) takes the same
## data directly (tests, previews). See from_universe() for the layout.

signal close_requested

const WIDTH := 340

var system_id := -1

var _title: Label
var _subtitle: Label
var _planets: VBoxContainer
var _fleets: Label


func _init() -> void:
	theme_type_variation = "OverlayPanel"
	custom_minimum_size.x = WIDTH
	visible = false
	_build()


## Show the system with \a id from the client universe; -1 hides the panel.
func show_system(id: int) -> void:
	system_id = id
	if id < 0:
		visible = false
		return
	show_data(from_universe(id))


## Re-read the shown system, e.g. after a turn update.
func refresh() -> void:
	if system_id >= 0:
		show_system(system_id)


func show_data(data: Dictionary) -> void:
	visible = not data.is_empty()
	if data.is_empty():
		return
	_title.text = data.get("name", "")
	var star_type: String = data.get("star_type", "")
	_subtitle.text = (
		tr("OBJ_SYSTEM")
		if star_type.is_empty() or star_type == "INVALID_STAR_TYPE"
		else "%s · %s" % [tr(star_type), tr("OBJ_SYSTEM")]
	)
	for child in _planets.get_children():
		child.queue_free()
	var planets: Array = data.get("planets", [])
	if planets.is_empty():
		_planets.add_child(_label(tr("SYSTEM_PANEL_NO_PLANETS"), "SecondaryLabel"))
	for planet: Dictionary in planets:
		_planets.add_child(_planet_row(planet))
	var fleets_total: int = data.get("fleets_total", 0)
	var fleets_own: int = data.get("fleets_own", 0)
	_fleets.text = (tr("SYSTEM_PANEL_FLEETS").replace("%1%", str(fleets_total)).replace(
		"%2%", str(fleets_own)
	))


## Panel data for system \a id from the client universe.
static func from_universe(id: int) -> Dictionary:
	var system: FOSystem = FOUniverse.get_system(id)
	if system == null:
		return {}
	var empire_id: int = FOUniverse.get_empire_id()
	var planets: Array[Dictionary] = []
	for planet_id in system.get_planet_ids():
		var planet: FOPlanet = FOUniverse.get_planet(planet_id)
		if planet == null:
			continue
		var owner_id := planet.get_owner_id()
		(
			planets
			. push_back(
				{
					"name": planet.get_name(),
					"type": planet.get_planet_type(),
					"size": planet.get_planet_size(),
					"owner_name": FOUniverse.get_empire_name(owner_id) if owner_id >= 0 else "",
					"owner_color": FOUniverse.get_empire_color(owner_id),
					"own": owner_id >= 0 and owner_id == empire_id,
					"species": planet.get_species_name(),
					"focus": planet.get_focus(),
					"population": planet.get_meter("METER_POPULATION"),
				}
			)
		)
	var fleets_own := 0
	var fleet_ids := system.get_fleet_ids()
	for fleet_id in fleet_ids:
		var fleet: FOFleet = FOUniverse.get_fleet(fleet_id)
		if fleet and fleet.get_owner_id() == empire_id:
			fleets_own += 1
	return {
		"name": system.get_name(),
		"star_type": system.get_star_type(),
		"planets": planets,
		"fleets_total": fleet_ids.size(),
		"fleets_own": fleets_own,
	}


func _build() -> void:
	var box := VBoxContainer.new()
	add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	_title = _label("", "TitleLabel")
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	titles.add_child(_title)
	_subtitle = _label("", "SecondaryLabel")
	titles.add_child(_subtitle)
	var close := Button.new()
	close.text = "✕"
	close.theme_type_variation = "GhostButton"
	close.tooltip_text = tr("PANEL_CLOSE")
	close.pressed.connect(close_requested.emit)
	header.add_child(close)

	box.add_child(HSeparator.new())
	box.add_child(_label(tr("SYSTEM_PANEL_PLANETS"), "SmallLabel"))
	_planets = VBoxContainer.new()
	box.add_child(_planets)
	box.add_child(HSeparator.new())
	_fleets = _label("", "SecondaryLabel")
	box.add_child(_fleets)


func _planet_row(planet: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var name_line := HBoxContainer.new()
	row.add_child(name_line)
	var owner_name: String = planet.get("owner_name", "")
	if not owner_name.is_empty():
		# Owner swatch: colour plus the name below, never colour alone.
		var swatch := ColorRect.new()
		swatch.color = planet.get("owner_color", Color.WHITE)
		swatch.custom_minimum_size = Vector2(FOUi.tokens.space_2, FOUi.tokens.space_2) * 1.5
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_line.add_child(swatch)
	var planet_name := _label(planet.get("name", ""))
	planet_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	planet_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_line.add_child(planet_name)
	var population: float = planet.get("population", 0.0)
	if population > 0.0:
		var pop := _label("%.1f" % population, "SecondaryLabel")
		pop.tooltip_text = tr("METER_POPULATION")
		name_line.add_child(pop)

	var details: PackedStringArray = []
	details.push_back("%s %s" % [tr(planet.get("size", "")), tr(planet.get("type", ""))])
	var species: String = planet.get("species", "")
	if not species.is_empty():
		details.push_back(tr(species))
	var focus: String = planet.get("focus", "")
	if not focus.is_empty():
		details.push_back(tr(focus))
	if not owner_name.is_empty():
		details.push_back(owner_name)
	var detail_label := _label(" · ".join(details), "SmallLabel")
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(detail_label)
	return row


static func _label(text: String, variation := "") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label
