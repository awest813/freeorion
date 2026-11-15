class_name SystemPanel
extends PanelContainer
## Context panel for the selected system: star, planets (type, size, owner,
## species, focus, population, and what the player can do with each:
## colonise, invade, annex, change focus) and fleets present.
##
## show_system(id) reads the client universe; show_data(dict) takes the same
## data directly (tests, previews). See from_universe() for the layout.

signal close_requested
## An own fleet was selected in the list (-1: selection cleared).
signal fleet_selected(fleet_id: int)
## A planet action button was pressed: "colonize", "invade", "annex" or
## "bombard" (each toggles the order).
signal planet_action_requested(planet_id: int, action: String)
## A new focus was picked for an own planet.
signal focus_requested(planet_id: int, focus: String)
## A planet's name was clicked: show its details.
signal planet_selected(planet_id: int)
## Ships dragged from the fleet panel were dropped on own fleet \a fleet_id.
signal ships_dropped(fleet_id: int, ship_ids: PackedInt32Array)

const WIDTH := 340

var system_id := -1

var _title: Label
var _subtitle: Label
var _planets: VBoxContainer
var _fleets: Label
var _fleet_list: VBoxContainer
var _notice: Label
var _selected_fleet := -1
## Own fleets listed: id -> true (only they take orders).
var _own_fleets := {}


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
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
	var was_hidden := not visible
	visible = not data.is_empty()
	if data.is_empty():
		return
	if was_hidden:
		FOUi.fade_in(self)
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
	_notice.visible = false
	_rebuild_fleet_list(data.get("fleets", []))


func selected_fleet_id() -> int:
	return _selected_fleet


## Select one of the listed fleets (-1 clears), emitting fleet_selected.
func select_fleet(fleet_id: int) -> void:
	if fleet_id == _selected_fleet:
		return
	_selected_fleet = fleet_id
	for button in _fleet_list.find_children("*", "Button", true, false):
		button.set_pressed_no_signal(button.get_meta("fleet_id", -1) == fleet_id)
	_notice.visible = false
	fleet_selected.emit(fleet_id)


## Short message under the fleet list, e.g. why an order was refused.
func show_notice(text: String) -> void:
	_notice.text = text
	_notice.visible = not text.is_empty()


func _rebuild_fleet_list(fleets: Array) -> void:
	for child in _fleet_list.get_children():
		child.queue_free()
	var still_listed := false
	_own_fleets.clear()
	for fleet: Dictionary in fleets:
		var ships: int = fleet.get("ships", 0)
		var line_key := (
			"SYSTEM_PANEL_FLEET_LINE_ONE_SHIP" if ships == 1 else "SYSTEM_PANEL_FLEET_LINE"
		)
		var line := tr(line_key).replace("%1%", fleet.get("name", "")).replace("%2%", str(ships))
		var destination: String = fleet.get("destination", "")
		if not destination.is_empty():
			line += "  " + tr("SYSTEM_PANEL_FLEET_DESTINATION").replace("%1%", destination)
		# Every fleet can be selected; only own ones take ships dropped on them.
		var button := Button.new()
		button.text = line
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.set_meta("fleet_id", fleet["id"])
		button.button_pressed = fleet["id"] == _selected_fleet
		button.toggled.connect(_on_fleet_toggled.bind(fleet["id"]))
		if fleet.get("own", false):
			_own_fleets[fleet["id"]] = true
			# Drag a whole fleet onto another to merge them.
			button.set_drag_forwarding(
				fleet_drag_data.bind(fleet),
				can_drop_ships.bind(fleet["id"]),
				drop_ships.bind(fleet["id"])
			)
		else:
			button.theme_type_variation = "GhostButton"
			button.icon = FOArt.swatch(fleet.get("owner_color", Color.WHITE), 10)
			button.tooltip_text = fleet.get("owner_name", "")
		_fleet_list.add_child(button)
		still_listed = still_listed or fleet["id"] == _selected_fleet
	if _selected_fleet != -1 and not still_listed:
		_selected_fleet = -1
		fleet_selected.emit(-1)
	_update_hint()


## Drag data for own \a fleet: all its ships, as the fleet panel drags ships.
func fleet_drag_data(_at: Vector2, fleet: Dictionary) -> Variant:
	var ship_ids: PackedInt32Array = fleet.get("ship_ids", PackedInt32Array())
	if ship_ids.is_empty():
		return null
	if get_viewport() and get_viewport().gui_is_dragging():
		var preview := PanelContainer.new()
		preview.theme_type_variation = "OverlayPanel"
		preview.add_child(_label(fleet.get("name", "")))
		set_drag_preview(preview)
	return {"type": FleetPanel.SHIP_DRAG, "fleet_id": fleet["id"], "ship_ids": ship_ids}


## Whether \a data (ships dragged from the fleet panel) can join own fleet
## \a fleet_id.
func can_drop_ships(_at: Vector2, data: Variant, fleet_id: int) -> bool:
	return FleetPanel.is_ship_drag(data, fleet_id)


func drop_ships(_at: Vector2, data: Variant, fleet_id: int) -> void:
	ships_dropped.emit(fleet_id, data["ship_ids"])


func _on_fleet_toggled(pressed: bool, fleet_id: int) -> void:
	select_fleet(fleet_id if pressed else -1)
	_update_hint()


func _update_hint() -> void:
	if _own_fleets.has(_selected_fleet) and not _notice.visible:
		show_notice(tr("SYSTEM_PANEL_MOVE_HINT"))


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
					"id": planet_id,
					"actions": FOPlanetActions.get_actions(planet_id),
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
	var fleets: Array[Dictionary] = []
	var fleet_ids := system.get_fleet_ids()
	for fleet_id in fleet_ids:
		var fleet: FOFleet = FOUniverse.get_fleet(fleet_id)
		if fleet == null:
			continue
		var own := fleet.get_owner_id() == empire_id
		if own:
			fleets_own += 1
		var destination := ""
		var destination_id := fleet.get_final_destination_id()
		if destination_id >= 0 and destination_id != fleet.get_system_id():
			var target: FOSystem = FOUniverse.get_system(destination_id)
			destination = target.get_name() if target else ""
		(
			fleets
			. push_back(
				{
					"id": fleet_id,
					"name": fleet.get_name(),
					"ships": fleet.get_ship_ids().size(),
					"ship_ids": fleet.get_ship_ids(),
					"own": own,
					"owner_color": FOUniverse.get_empire_color(fleet.get_owner_id()),
					"owner_name":
					(
						FOUniverse.get_empire_name(fleet.get_owner_id())
						if fleet.get_owner_id() >= 0
						else TranslationServer.translate("MONSTERS")
					),
					"destination": destination,
				}
			)
		)
	return {
		"fleets": fleets,
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
	_fleet_list = VBoxContainer.new()
	box.add_child(_fleet_list)
	_notice = _label("", "SmallLabel")
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.visible = false
	box.add_child(_notice)


# Planet row: type icon, name with owner swatch, population and focus icons,
# then a text line with size, type, species, focus and owner (icons are never
# the only carrier of information).
func _planet_row(planet: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var type_icon := _icon(FOArt.planet_type_icon(planet.get("type", "")), FOUi.tokens.icon)
	type_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	type_icon.tooltip_text = tr(planet.get("type", ""))
	row.add_child(type_icon)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var name_line := HBoxContainer.new()
	text.add_child(name_line)
	var owner_name: String = planet.get("owner_name", "")
	if not owner_name.is_empty():
		var swatch := ColorRect.new()
		swatch.color = planet.get("owner_color", Color.WHITE)
		swatch.custom_minimum_size = Vector2(FOUi.tokens.space_2, FOUi.tokens.space_2) * 1.5
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_line.add_child(swatch)
	# The name opens the planet's details.
	var planet_name := LinkButton.new()
	planet_name.text = planet.get("name", "")
	planet_name.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	planet_name.tooltip_text = tr("SYSTEM_PANEL_PLANET_DETAILS")
	planet_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	planet_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	planet_name.add_theme_color_override("font_color", FOUi.tokens.text_primary)
	planet_name.add_theme_color_override("font_hover_color", FOUi.tokens.accent_hover)
	planet_name.pressed.connect(planet_selected.emit.bind(planet.get("id", -1)))
	name_line.add_child(planet_name)
	var focus: String = planet.get("focus", "")
	if not focus.is_empty():
		var focus_icon := _icon(FOArt.focus_icon(focus), FOUi.tokens.icon_small)
		focus_icon.tooltip_text = tr(focus)
		name_line.add_child(focus_icon)
	var population: float = planet.get("population", 0.0)
	if population > 0.0:
		name_line.add_child(_icon(FOArt.meter_icon("pop"), FOUi.tokens.icon_small))
		var pop := _label("%.1f" % population, "SecondaryLabel")
		pop.tooltip_text = tr("METER_POPULATION")
		name_line.add_child(pop)

	var details: PackedStringArray = []
	var planet_size: String = planet.get("size", "")
	var planet_type: String = planet.get("type", "")
	# Gas giants and asteroid fields have a size named like their type.
	if planet_size in ["SZ_GASGIANT", "SZ_ASTEROIDS"] or planet_size.is_empty():
		details.push_back(tr(planet_type))
	else:
		details.push_back("%s %s" % [tr(planet_size), tr(planet_type)])
	var species: String = planet.get("species", "")
	if not species.is_empty():
		details.push_back(tr(species))
	if not focus.is_empty():
		details.push_back(tr(focus))
	if not owner_name.is_empty():
		details.push_back(owner_name)
	var detail_label := _label(" · ".join(details), "SmallLabel")
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(detail_label)
	var actions := _planet_actions(planet)
	if actions.get_child_count() > 0:
		text.add_child(actions)
	return row


# What the player can do with \a planet: the focus picker for own planets,
# and colonise / invade / annex buttons (or their cancel buttons).
func _planet_actions(planet: Dictionary) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", FOUi.tokens.space_1)
	flow.add_theme_constant_override("v_separation", FOUi.tokens.space_1)
	var actions: Dictionary = planet.get("actions", {})
	var planet_id: int = planet.get("id", -1)
	var focus: Dictionary = actions.get("focus", {})
	if focus.get("state", "") == "available":
		flow.add_child(_focus_picker(planet_id, focus))
	for action in ["colonize", "invade", "annex", "bombard"]:
		var entry: Dictionary = actions.get(action, {})
		var text := action_text(action, entry)
		if text.is_empty():
			continue
		var button := Button.new()
		button.text = text
		var state: String = entry.get("state", "")
		button.theme_type_variation = "GhostButton" if state == "pending" else "SegmentButton"
		button.disabled = state in ["unaffordable", "restricted"]
		if action == "colonize" and state == "available":
			button.tooltip_text = (
				"%s (%s)" % [entry.get("ship_name", ""), tr(entry.get("species", ""))]
			)
		button.pressed.connect(planet_action_requested.emit.bind(planet_id, action))
		flow.add_child(button)
	return flow


func _focus_picker(planet_id: int, focus: Dictionary) -> OptionButton:
	var picker := OptionButton.new()
	picker.theme_type_variation = "SegmentButton"
	picker.tooltip_text = tr("FOCUS")
	var options: PackedStringArray = focus.get("options", PackedStringArray())
	var icons: PackedStringArray = focus.get("icons", PackedStringArray())
	for i in options.size():
		picker.add_item(tr(options[i]))
		var icon: Texture2D = FOArt.icon(icons[i]) if i < icons.size() else null
		if icon:
			picker.set_item_icon(i, icon)
		if options[i] == focus.get("current", ""):
			picker.select(i)
	picker.add_theme_constant_override("icon_max_width", FOUi.tokens.icon_small)
	picker.item_selected.connect(func(index: int): focus_requested.emit(planet_id, options[index]))
	return picker


## Button text for planet \a action ("colonize", "invade", "annex",
## "bombard") in \a entry's state; "" when the action isn't offered.
static func action_text(action: String, entry: Dictionary) -> String:
	var state: String = entry.get("state", "")
	var text := ""
	match [action, state]:
		["colonize", "available"]:
			if entry.get("outpost", false):
				text = _tr("PL_OUTPOST")
			else:
				text = (
					_tr("PL_COLONIZE")
					. replace("%1%", "%.1f" % entry.get("capacity", 0.0))
					. replace("%2%", "%.1f" % entry.get("target_population", 0.0))
				)
		["colonize", "pending"]:
			text = _tr("PL_CANCEL_COLONIZE")
		["invade", "available"]:
			text = (_tr("PL_INVADE").replace("%1%", "%.1f" % entry.get("troops", 0.0)).replace(
				"%2%", "%.1f" % entry.get("defenders", 0.0)
			))
		["invade", "pending"]:
			text = _tr("PL_CANCEL_INVADE")
		["annex", "available"]:
			var cost: float = entry.get("cost", 0.0)
			text = (
				_tr("PL_ANNEX_FREE")
				if cost == 0.0
				else _tr("PL_ANNEX").replace("%1%", "%.1f" % cost)
			)
		["annex", "pending"]:
			text = _tr("PL_CANCEL_ANNEX").replace("%1%", "%.1f" % entry.get("cost", 0.0))
		["annex", "unaffordable"]:
			text = _tr("PL_ANNEXABLE").replace("%1%", "%.1f" % entry.get("cost", 0.0))
		["annex", "restricted"]:
			text = _tr("PL_ANNEXATION_RESTRICTED")
		["bombard", "available"]:
			text = _tr("PL_BOMBARD")
		["bombard", "pending"]:
			text = _tr("PL_CANCEL_BOMBARD")
	return text


static func _tr(key: String) -> String:
	return TranslationServer.translate(key)


# Fixed-size icon; an empty placeholder keeps rows aligned when art is missing.
static func _icon(texture: Texture2D, size: int) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = Vector2(size, size)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect


static func _label(text: String, variation := "") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label
