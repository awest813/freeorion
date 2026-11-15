class_name GameShell
extends Control
## In-game frame: the galaxy map, the top bar and the context panel docked on
## the right. Grows into the Phase 4 shell (left rail, notifications); until
## then UpstreamAdapters places it in upstream's MapWnd.

## Leave the game (from the menu): \a action is "title", "exit" or "load"
## (then \a path is the save to load). Shell ends the game.
signal leave_requested(action: String, path: String)

const GALAXY_MAP_VIEW := preload("res://map/GalaxyMapView.tscn")

## Set false before adding to the tree to feed map and panel directly (tests).
var follow_game := true
var map_view: GalaxyMapView
var top_bar: TopBar
var system_panel: SystemPanel
var fleet_panel: FleetPanel
var feed: NotificationFeed
var production_screen: ProductionScreen
var research_screen: ResearchScreen
var pedia_screen: PediaScreen
var options_screen: OptionsScreen
var government_screen: GovernmentScreen
var save_screen: SaveLoadScreen
var load_screen: SaveLoadScreen
var game_menu: GameMenu
var designer_screen: DesignerScreen
var combat_screen: CombatScreen
var objects_screen: ObjectsScreen
## Name of the full screen shown over the map, or "" for the map.
var active_screen := ""

## Newest combat the player has seen in the combat screen.
var _seen_combat_id := -1


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Our UI calls tr() on stringtable keys itself. Upstream scenes (MapWnd) set
	# auto-translation to ALWAYS, which would run names and numbers through
	# UserString too and show them as "ERROR: <text>".
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED


func _ready() -> void:
	map_view = GALAXY_MAP_VIEW.instantiate()
	map_view.follow_game = follow_game
	add_child(map_view)

	# UI layer over the map: top bar, then the body with the docked panel.
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)

	top_bar = TopBar.new()
	top_bar.follow_game = follow_game
	layout.add_child(top_bar)

	# Below the top bar: the map overlays (body) and full screens stack here.
	var screens := Control.new()
	screens.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(screens)
	var body := HBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screens.add_child(body)
	production_screen = ProductionScreen.new()
	research_screen = ResearchScreen.new()
	pedia_screen = PediaScreen.new()
	options_screen = OptionsScreen.new()
	government_screen = GovernmentScreen.new()
	designer_screen = DesignerScreen.new()
	combat_screen = CombatScreen.new()
	combat_screen.link_activated.connect(_on_link_activated)
	objects_screen = ObjectsScreen.new()
	objects_screen.link_activated.connect(_on_link_activated)
	save_screen = SaveLoadScreen.new()
	save_screen.mode = "save"
	load_screen = SaveLoadScreen.new()
	load_screen.defer_load = true
	load_screen.load_started.connect(func(path: String): leave_requested.emit("load", path))
	government_screen.pedia_requested.connect(open_pedia)
	pedia_screen.link_activated.connect(_on_link_activated)
	research_screen.pedia_requested.connect(open_pedia)
	production_screen.pedia_requested.connect(open_pedia)
	for screen in [
		production_screen,
		research_screen,
		government_screen,
		designer_screen,
		objects_screen,
		combat_screen,
		pedia_screen,
		options_screen,
		save_screen,
		load_screen,
	]:
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		screen.visible = false
		screen.close_requested.connect(show_screen.bind(""))
		screens.add_child(screen)
	top_bar.screen_requested.connect(show_screen)
	top_bar.menu_requested.connect(open_menu)
	var feed_margin := MarginContainer.new()
	feed_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		feed_margin.add_theme_constant_override(side, _gap())
	body.add_child(feed_margin)
	var feed_column := VBoxContainer.new()
	feed_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed_margin.add_child(feed_column)
	var feed_spacer := Control.new()
	feed_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feed_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed_column.add_child(feed_spacer)
	feed = NotificationFeed.new()
	feed.follow_game = follow_game
	feed.link_activated.connect(_on_link_activated)
	feed_column.add_child(feed)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(spacer)
	var panel_margin := MarginContainer.new()
	panel_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		panel_margin.add_theme_constant_override(side, _gap())
	body.add_child(panel_margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_margin.add_child(column)
	system_panel = SystemPanel.new()
	column.add_child(system_panel)
	fleet_panel = FleetPanel.new()
	column.add_child(fleet_panel)
	fleet_panel.rename_requested.connect(_on_fleet_rename)
	fleet_panel.aggression_requested.connect(_on_fleet_aggression)
	fleet_panel.split_requested.connect(_on_fleet_split)
	fleet_panel.merge_requested.connect(_on_fleet_merge)
	fleet_panel.scrap_requested.connect(_on_fleet_scrap)
	system_panel.planet_action_requested.connect(_on_planet_action)
	system_panel.focus_requested.connect(_on_focus_requested)

	# The menu covers everything, the top bar included.
	game_menu = GameMenu.new()
	game_menu.resume_requested.connect(game_menu.close)
	game_menu.screen_requested.connect(_on_menu_screen_requested)
	game_menu.leave_requested.connect(func(action: String): leave_requested.emit(action, ""))
	add_child(game_menu)

	top_bar.resized.connect(_update_frame_margins)

	map_view.system_selected.connect(_on_system_selected)
	map_view.map.system_context_requested.connect(_on_system_context_requested)
	system_panel.close_requested.connect(map_view.map.select_system.bind(GalaxyMap.NO_SYSTEM))
	system_panel.fleet_selected.connect(_on_fleet_selected)
	if follow_game and is_instance_valid(GlobalFreeOrionNode):
		GlobalFreeOrionNode.turn_update.connect(_on_turn_update)
		GlobalFreeOrionNode.save_completed.connect(_on_save_completed)
		GlobalFreeOrionNode.combat_logs_updated.connect(_on_combat_logs_updated)


# Esc on the map: clear the selection first, then open the menu. Screens and
# the menu handle their own Esc before it gets here.
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		show_screen("save")
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("ui_cancel") or not active_screen.is_empty():
		return
	if map_view.map.selected_system_id() != GalaxyMap.NO_SYSTEM:
		map_view.map.select_system(GalaxyMap.NO_SYSTEM)
	else:
		open_menu()
	get_viewport().set_input_as_handled()


## Open the in-game menu over the map (and any open screen).
func open_menu() -> void:
	var subtitle := ""
	if follow_game and is_instance_valid(GlobalFreeOrionNode):
		subtitle = (
			"%s  ·  %s"
			% [
				FOUniverse.get_empire_name(FOUniverse.get_empire_id()),
				tr("MAP_BTN_TURN_UPDATE").replace(
					"%1%", str(GlobalFreeOrionNode.get_current_turn())
				),
			]
		)
	game_menu.open(subtitle, not top_bar.is_waiting())


func _on_menu_screen_requested(screen_name: String) -> void:
	game_menu.close()
	show_screen(screen_name)


## Show the full screen \a screen_name ("production", "research") over the
## map, or return to the map with "".
func show_screen(screen_name: String) -> void:
	active_screen = screen_name
	top_bar.set_active_screen(screen_name)
	var screens := _screens()
	for key in screens:
		screens[key].visible = key == screen_name
	if not screens.has(screen_name):
		return
	if follow_game:
		_prepare_screen(screen_name)
	if screen_name == "combat":
		_seen_combat_id = maxi(_seen_combat_id, CombatScreen.newest_id(combat_screen.combats()))
		top_bar.set_badge("combat", 0)
	FOUi.fade_in(screens[screen_name])


func _screens() -> Dictionary:
	return {
		"production": production_screen,
		"research": research_screen,
		"government": government_screen,
		"design": designer_screen,
		"objects": objects_screen,
		"combat": combat_screen,
		"pedia": pedia_screen,
		"options": options_screen,
		"save": save_screen,
		"load": load_screen,
	}


# Load fresh game data into \a screen_name before it shows.
func _prepare_screen(screen_name: String) -> void:
	match screen_name:
		"production":
			production_screen.refresh()
			# Build at the selected system's own planet, if there is one.
			var system: FOSystem = FOUniverse.get_system(map_view.map.selected_system_id())
			if system:
				for planet_id in system.get_planet_ids():
					production_screen.select_location(planet_id)
		"save":
			save_screen.suggested_name = _suggested_save_name()
			save_screen.refresh()
		"pedia":
			pass
		_:
			_screens()[screen_name].refresh()


# "<empire>_turn_<n>", a default name for a new save.
func _suggested_save_name() -> String:
	var empire := FOUniverse.get_empire_name(FOUniverse.get_empire_id()).validate_filename()
	return "%s_turn_%d" % [empire.replace(" ", "_"), GlobalFreeOrionNode.get_current_turn()]


## Show the Pedia article \a kind / \a article_name.
func open_pedia(kind: String, article_name: String) -> void:
	show_screen("pedia")
	pedia_screen.open(kind, article_name)


# Frame the galaxy below the top bar; refit while the player hasn't moved.
func _update_frame_margins() -> void:
	var camera := map_view.map.camera
	camera.frame_margins = Vector4(0, top_bar.size.y + _gap(), 0, _gap())
	if not camera.user_moved and map_view.map.bounds.has_area():
		camera.fit_rect(map_view.map.bounds)


func _on_system_selected(system_id: int) -> void:
	system_panel.select_fleet(-1)
	if follow_game:
		system_panel.show_system(system_id)


# Right-click on a system while an own fleet is selected: order it there.
func _on_system_context_requested(system_id: int) -> void:
	var fleet_id := system_panel.selected_fleet_id()
	if fleet_id < 0 or not follow_game:
		return
	if FOOrders.issue_fleet_move(fleet_id, system_id) < 0:
		system_panel.show_notice(tr("SYSTEM_PANEL_ORDER_REFUSED"))
		return
	system_panel.refresh()
	_show_route(fleet_id)


func _on_fleet_selected(fleet_id: int) -> void:
	_show_route(fleet_id)
	if follow_game:
		fleet_panel.show_fleet(fleet_id)
	elif fleet_id < 0:
		fleet_panel.show_data({})


func _on_fleet_rename(fleet_id: int, new_name: String) -> void:
	if FOOrders.rename(fleet_id, new_name):
		_refresh_fleet_views(fleet_id)


func _on_fleet_aggression(fleet_id: int, aggression: String) -> void:
	FOOrders.set_fleet_aggression(fleet_id, aggression)
	_refresh_fleet_views(fleet_id)


func _on_fleet_split(ship_ids: PackedInt32Array) -> void:
	var new_fleet := FOOrders.split_ships(ship_ids)
	_refresh_fleet_views(new_fleet if new_fleet >= 0 else fleet_panel.fleet_id)


func _on_fleet_merge(dest_fleet_id: int, ship_ids: PackedInt32Array) -> void:
	if FOOrders.merge_ships(dest_fleet_id, ship_ids):
		_refresh_fleet_views(dest_fleet_id)


func _on_fleet_scrap(ship_ids: PackedInt32Array) -> void:
	for ship_id in ship_ids:
		FOPlanetActions.scrap(ship_id)
	_refresh_fleet_views(fleet_panel.fleet_id)


# Colonise, invade or annex (each toggles the order), then show the result.
func _on_planet_action(planet_id: int, action: String) -> void:
	if not follow_game:
		return
	var done := false
	match action:
		"colonize":
			done = FOPlanetActions.colonize(planet_id)
		"invade":
			done = FOPlanetActions.invade(planet_id)
		"annex":
			done = FOPlanetActions.annex(planet_id)
	system_panel.refresh()
	if not done:
		system_panel.show_notice(tr("SYSTEM_PANEL_ACTION_REFUSED"))
	if fleet_panel.visible:
		fleet_panel.refresh()


func _on_focus_requested(planet_id: int, focus: String) -> void:
	if follow_game and not FOPlanetActions.set_focus(planet_id, focus):
		system_panel.show_notice(tr("SYSTEM_PANEL_ACTION_REFUSED"))
	system_panel.refresh()


# After a fleet order: re-read the system panel and show \a fleet_id.
func _refresh_fleet_views(fleet_id: int) -> void:
	system_panel.refresh()
	system_panel.select_fleet(fleet_id)
	fleet_panel.show_fleet(fleet_id)


func _on_save_completed(filename: String, _bytes: int) -> void:
	save_screen.on_save_completed(filename)


# Combat logs arrive from the server shortly after a turn starts.
func _on_combat_logs_updated() -> void:
	if combat_screen.visible:
		combat_screen.refresh()
	update_combat_badge(FOCombat.list_combats(), GlobalFreeOrionNode.get_current_turn())


## Count, on the Combat button, the combats of the last turn not seen yet.
func update_combat_badge(combats: Array, current_turn: int) -> void:
	var count := 0
	for combat: Dictionary in combats:
		if combat["turn"] >= current_turn - 1 and combat["id"] > _seen_combat_id:
			count += 1
	top_bar.set_badge("combat", 0 if active_screen == "combat" else count)


func _on_turn_update() -> void:
	system_panel.refresh()
	if fleet_panel.visible:
		fleet_panel.refresh()
	if production_screen.visible:
		production_screen.refresh()
	if research_screen.visible:
		research_screen.refresh()
	if government_screen.visible:
		government_screen.refresh()
	if objects_screen.visible:
		objects_screen.refresh()
	_show_route(system_panel.selected_fleet_id())


func _show_route(fleet_id: int) -> void:
	var fleet: FOFleet = FOUniverse.get_fleet(fleet_id) if fleet_id >= 0 and follow_game else null
	if fleet == null:
		map_view.map.set_route(Vector2.ZERO, PackedInt32Array())
		return
	map_view.map.set_route(
		fleet.get_position(), fleet.get_travel_route(), eta_text(fleet.get_eta())
	)


## Route label for an ETA from FOFleet.get_eta().
static func eta_text(eta: int) -> String:
	if eta < 0:
		return TranslationServer.translate("MAP_ROUTE_UNREACHABLE")
	if eta == 0:
		return ""
	if eta == 1:
		return TranslationServer.translate("MAP_ROUTE_ETA_ONE")
	return TranslationServer.translate("MAP_ROUTE_ETA").replace("%1%", str(eta))


# Links in sitreps and the Pedia: content opens its Pedia article; objects on
# the map select (and centre on) their system and return to the map.
func _on_link_activated(kind: String, arg: String) -> void:
	if PediaScreen.is_article_kind(kind):
		open_pedia(kind, arg)
		return
	if kind == "combat" and arg.is_valid_int():
		show_screen("combat")
		combat_screen.open(arg.to_int())
		return
	if not follow_game or not arg.is_valid_int():
		return
	show_screen("")
	var system_id := -1
	match kind:
		"system":
			system_id = arg.to_int()
		"planet":
			var planet: FOPlanet = FOUniverse.get_planet(arg.to_int())
			system_id = planet.get_system_id() if planet else -1
		"ship", "fleet":
			var fleet_id := arg.to_int()
			if kind == "ship":
				var ship: FOShip = FOUniverse.get_ship(fleet_id)
				fleet_id = ship.get_fleet_id() if ship else -1
			var fleet: FOFleet = FOUniverse.get_fleet(fleet_id)
			if fleet:
				system_id = fleet.get_system_id()
				if system_id < 0:
					map_view.map.camera.center_on(fleet.get_position())
					return
	if system_id >= 0:
		map_view.map.focus_system(system_id)


func _gap() -> int:
	return FOUi.tokens.space_4 if FOUi.tokens else 16
