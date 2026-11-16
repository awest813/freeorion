class_name GameShell
extends Control
## In-game frame: the galaxy map, the top bar and the context panel docked on
## the right. Grows into the Phase 4 shell (left rail, notifications); until
## then UpstreamAdapters places it in upstream's MapWnd.

## Leave the game (from the menu): \a action is "title", "exit" or "load"
## (then \a path is the save to load). Shell ends the game.
signal leave_requested(action: String, path: String)

const GALAXY_MAP_VIEW := preload("res://map/GalaxyMapView.tscn")
## Keys for screens opened from the in-game menu rather than the top bar.
## Hotkeys for screens without a top-bar button.
const MENU_HOTKEYS := {"screen_save": "save", "screen_options": "options"}
## Remembers the stance of new fleets (FleetPanel.NEW_FLEET_STANCES).
const OPTION_NEW_FLEET_STANCE := "ui.fleet.new.aggression"

## Set false before adding to the tree to feed map and panel directly (tests).
var follow_game := true
var map_view: GalaxyMapView
var top_bar: TopBar
var system_panel: SystemPanel
var fleet_panel: FleetPanel
var planet_panel: PlanetPanel
var ship_panel: ShipPanel
var map_scale: MapScale
var map_mode_picker: OptionButton
var minimap: MiniMap
## Zoom by dragging (GG's zoom slider; a map aid, hidden by default).
var zoom_slider: VSlider
## The map's right-click options menu.
var map_menu: MapMenu
## Turns the side panels' requests into orders.
var panel_orders: PanelOrders
var map_modes: MapModes
var hints: HintCoach
## Messages with the other players (and what AIs say).
var chat_window: ChatWindow
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
var empires_screen: EmpiresScreen
## Notes, toasts and server errors.
var message_log: MessageLog
## Automatic turn advance: ends each new turn, unless in danger.
var auto_turn_guard := AutoTurnGuard.new()
## Name of the full screen shown over the map, or "" for the map.
var active_screen := ""

var _side_scroll: ScrollContainer
var _navigator := MapNavigator.new()

## Newest combat the player has seen in the combat screen.
var _seen_combat_id := -1
## Victory or defeat already announced (or already so when the game began).
var _announced := {}


func _init() -> void:
	panel_orders = PanelOrders.new(self)
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
	# Placing production, fleets selected together and the map aids, with a
	# banner floating over the top of the map.
	map_modes = MapModes.new(self)
	screens.add_child(map_modes)
	production_screen = ProductionScreen.new()
	research_screen = ResearchScreen.new()
	pedia_screen = PediaScreen.new()
	options_screen = OptionsScreen.new()
	government_screen = GovernmentScreen.new()
	designer_screen = DesignerScreen.new()
	combat_screen = CombatScreen.new()
	combat_screen.link_activated.connect(_on_link_activated)
	empires_screen = EmpiresScreen.new()
	objects_screen = ObjectsScreen.new()
	objects_screen.link_activated.connect(_on_link_activated)
	objects_screen.production_requested.connect(
		func(planet_id: int):
			show_screen("production")
			production_screen.select_location(planet_id)
	)
	save_screen = SaveLoadScreen.new()
	save_screen.mode = "save"
	load_screen = SaveLoadScreen.new()
	load_screen.defer_load = true
	load_screen.load_started.connect(func(path: String): leave_requested.emit("load", path))
	government_screen.pedia_requested.connect(open_pedia)
	designer_screen.pedia_requested.connect(open_pedia)
	pedia_screen.link_activated.connect(_on_link_activated)
	research_screen.pedia_requested.connect(open_pedia)
	production_screen.pedia_requested.connect(open_pedia)
	production_screen.build_on_map_requested.connect(map_modes.start_placement)
	production_screen.location_requested.connect(_show_planet_on_map)
	production_screen.rally_target = func() -> Array:
		var system_id := map_view.map.selected_system_id()
		var system: FOSystem = (
			FOUniverse.get_system(system_id) if system_id >= 0 and follow_game else null
		)
		return [system_id, system.get_name()] if system else [-1, ""]
	for screen in [
		production_screen,
		research_screen,
		government_screen,
		designer_screen,
		objects_screen,
		combat_screen,
		empires_screen,
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
	top_bar.readiness_issues.connect(show_readiness)
	top_bar.revert_requested.connect(
		func():
			if follow_game:
				FOOrders.revert_all()
	)
	top_bar.wasted_pp_requested.connect(_show_wasted_pp)
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

	# The middle: open map, with the map mode, scale legend and minimap at
	# its bottom right. A plain Control, so they never widen the layout and
	# push the panels off the screen.
	var middle := Control.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(middle)
	var map_aids := HBoxContainer.new()
	map_aids.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_aids.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	map_aids.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	map_aids.grow_vertical = Control.GROW_DIRECTION_BEGIN
	map_aids.offset_bottom = -_gap()
	middle.add_child(map_aids)
	# Mode picker above the scale bar, to keep the row narrow.
	var mode_and_scale := VBoxContainer.new()
	mode_and_scale.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_and_scale.alignment = BoxContainer.ALIGNMENT_END
	map_aids.add_child(mode_and_scale)
	map_mode_picker = OptionButton.new()
	for mode in GalaxyMap.MODES:
		map_mode_picker.add_item(tr("MAP_MODE_" + mode.to_upper()))
	map_mode_picker.item_selected.connect(
		func(index: int): map_modes.set_map_mode(GalaxyMap.MODES[index])
	)
	mode_and_scale.add_child(map_mode_picker)
	map_scale = MapScale.new()
	mode_and_scale.add_child(map_scale)
	minimap = MiniMap.new()
	map_aids.add_child(minimap)
	zoom_slider = _make_zoom_slider()
	map_aids.add_child(zoom_slider)
	var panel_margin := MarginContainer.new()
	panel_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		panel_margin.add_theme_constant_override(side, _gap())
	body.add_child(panel_margin)
	# The panels scroll when they're taller than the screen. The scroll area
	# is only as tall as the panels, so the map below them stays clickable.
	_side_scroll = ScrollContainer.new()
	_side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_side_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_side_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	panel_margin.add_child(_side_scroll)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side_scroll.add_child(column)
	column.minimum_size_changed.connect(_fit_side_column)
	panel_margin.resized.connect(_fit_side_column)
	system_panel = SystemPanel.new()
	column.add_child(system_panel)
	planet_panel = PlanetPanel.new()
	planet_panel.close_requested.connect(planet_panel.show_data.bind({}))
	planet_panel.link_activated.connect(_on_link_activated)
	planet_panel.scrap_requested.connect(_on_building_scrap)
	column.add_child(planet_panel)
	fleet_panel = FleetPanel.new()
	column.add_child(fleet_panel)
	fleet_panel.rename_requested.connect(panel_orders.on_fleet_rename)
	fleet_panel.aggression_requested.connect(panel_orders.on_fleet_aggression)
	fleet_panel.split_requested.connect(panel_orders.on_fleet_split)
	fleet_panel.merge_requested.connect(panel_orders.on_fleet_merge)
	fleet_panel.scrap_requested.connect(panel_orders.on_fleet_scrap)
	fleet_panel.ship_selected.connect(show_ship)
	fleet_panel.split_groups_requested.connect(panel_orders.on_fleet_split_groups)
	fleet_panel.give_requested.connect(panel_orders.on_give)
	fleet_panel.forget_requested.connect(func(id: int): panel_orders.on_forget([id]))
	planet_panel.forget_requested.connect(func(id: int): panel_orders.on_forget([id]))
	system_panel.forget_requested.connect(panel_orders.on_forget)
	planet_panel.give_requested.connect(panel_orders.on_give)
	fleet_panel.settle_targets.send_requested.connect(_move_fleet.bind(false))
	fleet_panel.settle_targets.target_hovered.connect(
		func(system_id: int): MoveOrders.preview_route(self, system_id)
	)
	fleet_panel.settle_targets.targets_changed.connect(
		func(targets: Array): map_view.map.fleets.set_settle_marks(SettleTargets.map_marks(targets))
	)
	fleet_panel.settle_targets.settle_requested.connect(
		panel_orders.on_planet_action.bind("colonize")
	)
	fleet_panel.explore_requested.connect(
		func(fleet_id: int, exploring: bool):
			if follow_game:
				FOExplore.set_exploring(fleet_id, exploring)
				refresh_fleet_views(fleet_id)
				_show_route(fleet_id)
	)
	planet_panel.rename_requested.connect(panel_orders.on_rename)
	system_panel.rename_requested.connect(panel_orders.on_rename)
	system_panel.system_requested.connect(func(id: int): map_view.map.focus_system(id))
	system_panel.systems_provider = panel_orders.known_systems
	fleet_panel.merge_all_requested.connect(panel_orders.on_fleet_merge_all)
	fleet_panel.new_fleet_stance_changed.connect(panel_orders.on_new_fleet_stance)
	ship_panel = ShipPanel.new()
	ship_panel.close_requested.connect(ship_panel.show_data.bind({}))
	ship_panel.link_activated.connect(_on_link_activated)
	ship_panel.rename_requested.connect(
		func(ship_id: int, new_name: String):
			if follow_game and FOOrders.rename(ship_id, new_name):
				ship_panel.refresh()
				fleet_panel.refresh()
	)
	column.add_child(ship_panel)
	system_panel.planet_action_requested.connect(panel_orders.on_planet_action)
	system_panel.focus_requested.connect(_on_focus_requested)
	system_panel.planet_selected.connect(_on_planet_selected)
	system_panel.ships_dropped.connect(panel_orders.on_fleet_merge)

	# Messages over the top left of the map, clear of the feed below.
	chat_window = ChatWindow.new()
	chat_window.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	chat_window.offset_left = _gap()
	chat_window.offset_top = _gap()
	chat_window.unread_changed.connect(top_bar.set_unread_messages)
	screens.add_child(chat_window)
	top_bar.messages_requested.connect(chat_window.toggle)
	message_log = MessageLog.new(self)
	add_child(message_log)
	screens.add_child(ModeratorTools.new(self), true)

	# The menu covers everything, the top bar included.
	# First-time hints, over the map and screens but under the menu; only in
	# a real game.
	hints = HintCoach.new()
	hints.persist = follow_game
	hints.enabled = follow_game
	add_child(hints)

	game_menu = GameMenu.new()
	game_menu.resume_requested.connect(game_menu.close)
	game_menu.screen_requested.connect(_on_menu_screen_requested)
	game_menu.leave_requested.connect(func(action: String): leave_requested.emit(action, ""))
	game_menu.concede_requested.connect(
		func():
			game_menu.close()
			FOMultiplayer.concede()
	)
	add_child(game_menu)

	# Panels pass the mouse wheel on to the scroll area around them.
	for panel in [system_panel, planet_panel, fleet_panel, ship_panel]:
		panel.mouse_filter = Control.MOUSE_FILTER_PASS
	top_bar.resized.connect(_update_frame_margins)
	map_view.map.camera.view_changed.connect(_report_view)

	map_view.system_selected.connect(_on_system_selected)
	map_view.map.system_clicked.connect(map_modes.on_system_clicked)
	map_view.map.fleets_boxed.connect(map_modes.select_fleets)
	minimap.map = map_view.map
	map_view.map.camera.zoom_changed.connect(map_scale.set_zoom)
	map_view.map.camera.zoom_changed.connect(_on_zoom_changed)
	map_scale.set_zoom(map_view.map.camera.zoom_level())
	if follow_game and is_instance_valid(GlobalFreeOrionNode):
		map_view.map.own_empire_id = FOUniverse.get_empire_id()
	map_view.map.system_context_requested.connect(_on_system_context_requested)
	map_view.map.fleet_clicked.connect(_on_fleet_clicked)
	map_menu = MapMenu.new(self)
	add_child(map_menu)
	map_view.map.map_context_requested.connect(map_menu.open_at)
	# Double-click a system or an own planet: production there.
	map_view.map.system_activated.connect(func(_id): show_screen("production"))
	system_panel.production_requested.connect(
		func(planet_id: int):
			show_screen("production")
			production_screen.select_location(planet_id)
	)
	map_view.map.system_hovered.connect(_on_system_hovered)
	map_view.map.field_activated.connect(
		func(field_type: String): open_pedia("fieldtype", field_type)
	)
	system_panel.close_requested.connect(map_view.map.select_system.bind(GalaxyMap.NO_SYSTEM))
	system_panel.fleet_selected.connect(_on_fleet_selected)
	if follow_game and is_instance_valid(GlobalFreeOrionNode):
		GlobalFreeOrionNode.turn_update.connect(_on_turn_update)
		GlobalFreeOrionNode.save_completed.connect(_on_save_completed)
		GlobalFreeOrionNode.combat_logs_updated.connect(_on_combat_logs_updated)
		GlobalFreeOrionNode.diplomacy_changed.connect(_on_diplomacy_changed)
		var options := Engine.get_singleton("FOOptions")
		if options.exists("ui.map.detection.shown"):
			map_view.map.show_detection = options.get_value("ui.map.detection.shown")
		map_modes.load_map_aids(options)
		map_menu.load_all()
		options.add_option(OPTION_NEW_FLEET_STANCE, "OPTIONS_DB_FLEET_WND_AGGRESSION", "auto")
		fleet_panel.new_fleet_stance = str(options.get_value(OPTION_NEW_FLEET_STANCE))
		if options.exists(MapModes.OPTION_MAP_MODE):
			map_modes.set_map_mode(options.get_value(MapModes.OPTION_MAP_MODE))
		# A loaded game that was already won or lost isn't announced again.
		check_game_over(FOUniverse.get_empire_resources(), true)
		MoveOrders.explore_new_scouts()
		chat_window.refresh()
		chat_window.mark_read()
		hints.offer("map")
		hints.offer("end_turn", top_bar.get_end_turn_button())


# Esc on the map: clear the selection first, then open the menu. Screens and
# the menu handle their own Esc before it gets here.
func _unhandled_key_input(event: InputEvent) -> void:
	# Screens without a top-bar button keep their keys.
	var hotkey: String = FOHotkeys.match_event(event)
	if MENU_HOTKEYS.has(hotkey):
		show_screen(MENU_HOTKEYS[hotkey])
		get_viewport().set_input_as_handled()
		return
	if not hotkey.is_empty() and active_screen.is_empty():
		if _handle_map_key(hotkey):
			get_viewport().set_input_as_handled()
			return
	if not event.is_action_pressed("ui_cancel") or not active_screen.is_empty():
		return
	if map_modes.is_placing():
		map_modes.end_placement()
	elif map_modes.has_fleet_selection():
		map_modes.clear_fleet_selection()
	elif map_view.map.selected_system_id() != GalaxyMap.NO_SYSTEM:
		map_view.map.select_system(GalaxyMap.NO_SYSTEM)
	else:
		open_menu()
	get_viewport().set_input_as_handled()


# Map hotkeys: home, detection ranges, map modes and aids, the turn
# reports, and the navigator's steps.
func _handle_map_key(hotkey: String) -> bool:
	var handled := true
	match hotkey:
		"home":
			go_home()
		"detection":
			set_detection_shown(not map_view.map.show_detection)
		"map_mode":
			map_modes.cycle_map_mode()
		"sitrep":
			feed.set_expanded(not feed.is_expanded())
		_:
			if MapModes.MAP_AIDS.has(hotkey):
				map_modes.toggle_map_aid(hotkey)
			else:
				var nav := MapNavigator.match_hotkey(hotkey)
				handled = not nav.is_empty()
				if handled and follow_game:
					go_to(_navigator.step(nav[0], nav[1]))
	return handled


## Centre on \a target ({system_id, fleet_id, position}): select its system,
## and its fleet if it is one.
func go_to(target: Dictionary) -> void:
	if target.is_empty():
		return
	var system_id: int = target.get("system_id", -1)
	var fleet_id: int = target.get("fleet_id", -1)
	if system_id >= 0:
		map_view.map.focus_system(system_id)
		if fleet_id >= 0:
			system_panel.select_fleet(fleet_id)
	else:
		# A fleet between systems: no system is selected, only the fleet.
		map_view.map.select_system(GalaxyMap.NO_SYSTEM)
		map_view.map.camera.center_on(target.get("position", Vector2.ZERO))
		if fleet_id >= 0:
			_on_fleet_selected(fleet_id)


## Centre on the capital's system.
func go_home() -> void:
	if not follow_game:
		return
	var capital: FOPlanet = FOUniverse.get_planet(
		FOUniverse.get_empire_resources().get("capital_id", -1)
	)
	if capital:
		map_view.map.focus_system(capital.get_system_id())


## Show or hide detection ranges, and remember it.
func set_detection_shown(shown: bool) -> void:
	map_view.map.show_detection = shown
	var options := Engine.get_singleton("FOOptions") if follow_game else null
	if options and options.exists("ui.map.detection.shown"):
		options.set_value("ui.map.detection.shown", shown)
		options.commit()


## Go back to the view saved with a loaded game. Views from other clients
## (whose saved position means something else) or outside the galaxy are
## ignored.
func restore_view() -> void:
	if not follow_game or not is_instance_valid(GlobalFreeOrionNode):
		return
	var view: Dictionary = GlobalFreeOrionNode.get_saved_view()
	var map := map_view.map
	if view.is_empty() or not map.bounds.has_area():
		return
	var center: Vector2 = view["center"]
	if map.bounds.grow(map.bounds.size.length() * 0.1).has_point(center):
		map.camera.set_view(center, view["zoom"])


# The view goes with each turn's orders, so saves can restore it.
func _report_view() -> void:
	if follow_game and is_instance_valid(GlobalFreeOrionNode):
		var camera := map_view.map.camera
		GlobalFreeOrionNode.set_view(camera.position, camera.zoom_level())


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
	var is_multiplayer: bool = (
		follow_game
		and is_instance_valid(GlobalFreeOrionNode)
		and not GlobalFreeOrionNode.get_single_player_game()
	)
	game_menu.save_check = func() -> bool:
		return not top_bar.is_waiting() and (not follow_game or FOSaves.can_save())
	game_menu.open(
		subtitle,
		game_menu.save_check.call(),
		is_multiplayer,
		is_multiplayer and FOMultiplayer.can_concede()
	)


func _on_menu_screen_requested(screen_name: String) -> void:
	game_menu.close()
	show_screen(screen_name)


## Show the full screen \a screen_name ("production", "research") over the
## map, or return to the map with "".
func show_screen(screen_name: String) -> void:
	# Opening a screen ends placing production on the map.
	if not screen_name.is_empty() and map_modes.is_placing():
		map_modes.cancel_placement()
	active_screen = screen_name
	top_bar.set_active_screen(screen_name)
	hints.screen_shown(screen_name)
	var screens := _screens()
	for key in screens:
		screens[key].visible = key == screen_name
	if not screens.has(screen_name):
		# Back on the map: queues and focus may have changed what's spent.
		top_bar.refresh_resources()
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
		"empires": empires_screen,
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
				production_screen.select_location_among(system.get_planet_ids())
		"save":
			save_screen.suggested_name = _suggested_save_name()
			save_screen.refresh()
		"pedia":
			pass
		"objects":
			# Distances are measured from the map's selected system.
			var selected := map_view.map.selected_system_id()
			objects_screen.selection_position = (
				map_view.map.system_position(selected) if selected >= 0 else Vector2.INF
			)
			objects_screen.refresh()
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


# The side column's scroll area: as tall as its panels, at most the space
# below the top bar.
func _fit_side_column() -> void:
	var column: Control = _side_scroll.get_child(0)
	var room := _side_scroll.get_parent_control().size.y - 2 * _gap()
	_side_scroll.custom_minimum_size.y = minf(column.get_combined_minimum_size().y, maxf(room, 0.0))


# Frame the galaxy below the top bar; refit while the player hasn't moved.
func _update_frame_margins() -> void:
	var camera := map_view.map.camera
	camera.frame_margins = Vector4(0, top_bar.size.y + _gap(), 0, _gap())
	if not camera.user_moved and map_view.map.bounds.has_area():
		camera.fit_rect(map_view.map.bounds)


func _on_system_selected(system_id: int) -> void:
	system_panel.select_fleet(-1)
	planet_panel.show_data({})
	ship_panel.show_data({})
	if follow_game:
		system_panel.show_system(system_id)


# Right-click on a system while an own fleet is selected: order it there.
func _on_system_context_requested(system_id: int) -> void:
	if map_modes.has_fleet_selection() and follow_game:
		map_modes.move_selected_fleets(system_id)
		return
	var fleet_id := active_fleet()
	if fleet_id < 0 and follow_game and fleet_panel.visible:
		fleet_panel.show_notice(tr("MAP_MOVE_NEEDS_OWN_FLEET"))
	if fleet_id < 0 or not follow_game:
		return
	# With Shift, the move is a waypoint after the fleet's current route.
	_move_fleet(fleet_id, system_id, Input.is_key_pressed(KEY_SHIFT))


# Order \a fleet_id to \a system_id (\a append: after its route), saying
# why when it can't get there.
func _move_fleet(fleet_id: int, system_id: int, append: bool) -> void:
	var problem := FOOrders.move_problem(fleet_id, system_id, append)
	var moved := FOOrders.issue_fleet_move(fleet_id, system_id, append) >= 0
	if moved:
		system_panel.refresh()
		if fleet_panel.visible:
			fleet_panel.refresh()
		map_view.map.fleets.set_preview(PackedVector2Array(), PackedVector2Array())
		_show_route(fleet_id)
	var notice := MoveOrders.move_refusal_text(problem) if not moved or problem != "" else ""
	(fleet_panel if fleet_panel.visible else system_panel).show_notice(notice)


## The own fleet orders go to: the one in the fleet panel (also between
## systems), else the one picked in the system panel; -1 for none.
func active_fleet() -> int:
	if fleet_panel.visible and fleet_panel.fleet_id >= 0:
		return fleet_panel.fleet_id if fleet_panel.is_own() else -1
	return system_panel.selected_fleet_id()


# Where industry goes unspent: that system on the map, and production
# there.
func _show_wasted_pp(system_id: int) -> void:
	map_view.map.focus_system(system_id)
	show_screen("production")


# A vertical slider zooming the map: its value is the zoom's position
# between the camera's limits, on a log scale.
func _make_zoom_slider() -> VSlider:
	var slider := VSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.001
	slider.custom_minimum_size.y = 160
	slider.visible = false
	slider.tooltip_text = tr("OPTIONS_GALAXY_MAP_ZOOM_SLIDER")
	slider.value_changed.connect(
		func(value: float):
			var camera := map_view.map.camera
			var zoom := exp(lerpf(log(camera.min_zoom), log(camera.max_zoom), value))
			if not is_equal_approx(zoom, camera.zoom_level()):
				camera.zoom_at(zoom / camera.zoom_level(), get_viewport_rect().size * 0.5)
	)
	return slider


func _on_zoom_changed(zoom: float) -> void:
	var camera := map_view.map.camera
	var span := log(camera.max_zoom) - log(camera.min_zoom)
	if span > 0.0:
		zoom_slider.set_value_no_signal((log(zoom) - log(camera.min_zoom)) / span)


# Back to the map at planet \a planet_id, its details shown.
func _show_planet_on_map(planet_id: int) -> void:
	var planet: FOPlanet = FOUniverse.get_planet(planet_id) if follow_game else null
	if planet == null:
		return
	show_screen("")
	map_view.map.focus_system(planet.get_system_id())
	_on_planet_selected(planet_id)


# A fleet marker on the map: select that fleet where it is.
func _on_fleet_clicked(fleet_id: int) -> void:
	var fleet: FOFleet = FOUniverse.get_fleet(fleet_id) if follow_game else null
	if fleet == null:
		return
	map_modes.clear_fleet_selection()
	# Select it in place; the camera stays where the player put it.
	var system_id := fleet.get_system_id()
	map_view.map.select_system(system_id if system_id >= 0 else GalaxyMap.NO_SYSTEM)
	if system_id >= 0:
		system_panel.select_fleet(fleet_id)
	else:
		_on_fleet_selected(fleet_id)


# With an own fleet active, hovering a system shows the route it would take
# there and when it would arrive (Shift: after its current route).
func _on_system_hovered(system_id: int) -> void:
	MoveOrders.preview_route(self, system_id)


# A planet's details replace a fleet's, and the other way round.
func _on_planet_selected(planet_id: int) -> void:
	system_panel.select_fleet(-1)
	if follow_game:
		planet_panel.show_planet(planet_id)
	hints.offer("planet", planet_panel)


func _on_building_scrap(building_id: int) -> void:
	if follow_game:
		FOPlanetActions.scrap(building_id)
		planet_panel.refresh()


func _on_fleet_selected(fleet_id: int) -> void:
	if fleet_id >= 0:
		planet_panel.show_data({})
		map_modes.clear_fleet_selection()
		hints.offer("fleet", fleet_panel)
	if fleet_id < 0 or ship_panel.visible and not _fleet_has_ship(fleet_id, ship_panel.ship_id):
		ship_panel.show_data({})
	_show_route(fleet_id)
	map_view.map.fleets.selected_fleet = fleet_id
	map_view.map.fleets.set_preview(PackedVector2Array(), PackedVector2Array())
	if follow_game:
		fleet_panel.show_fleet(fleet_id)
	elif fleet_id < 0:
		fleet_panel.show_data({})


## Show ship \a ship_id's details below its fleet.
func show_ship(ship_id: int) -> void:
	if not follow_game:
		return
	ship_panel.show_ship(ship_id)
	# Scroll the side column to it once it has its size.
	await get_tree().process_frame
	await get_tree().process_frame
	if ship_panel.visible:
		_side_scroll.ensure_control_visible(ship_panel)


func _fleet_has_ship(fleet_id: int, ship_id: int) -> bool:
	if not follow_game:
		return false
	var ship: FOShip = FOUniverse.get_ship(ship_id)
	return ship != null and ship.get_fleet_id() == fleet_id


func _on_focus_requested(planet_id: int, focus: String) -> void:
	if follow_game and not FOPlanetActions.set_focus(planet_id, focus):
		system_panel.show_notice(tr("SYSTEM_PANEL_ACTION_REFUSED"))
	system_panel.refresh()
	if planet_panel.visible:
		planet_panel.refresh()
	top_bar.refresh_resources()


## After a fleet order: re-read the system panel and show \a fleet_id.
func refresh_fleet_views(fleet_id: int) -> void:
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


## Announce victory or defeat from \a resources (get_empire_resources()),
## once each; \a silently only notes them.
func check_game_over(resources: Dictionary, silently := false) -> void:
	for outcome in ["won", "eliminated"]:
		if not resources.get(outcome, false) or _announced.has(outcome):
			continue
		_announced[outcome] = true
		if silently:
			continue
		var quit := [
			tr("MENU_QUIT_TO_TITLE"), "GhostButton", leave_requested.emit.bind("title", "")
		]
		if outcome == "won":
			FODialog.open_on(
				self,
				tr("GAME_OVER_VICTORY_TITLE"),
				tr("GAME_OVER_VICTORY"),
				[quit, [tr("GAME_OVER_KEEP_PLAYING"), "PrimaryButton"]]
			)
		else:
			FODialog.open_on(
				self,
				tr("GAME_OVER_DEFEAT_TITLE"),
				tr("GAME_OVER_DEFEAT"),
				[quit, [tr("GAME_OVER_KEEP_WATCHING"), "GhostButton"]]
			)


## Before the turn ends: list \a issues (TurnReadiness.check()), each going
## to its screen or map target, with End turn anyway and Back.
func show_readiness(issues: Array) -> FODialog:
	var dialog := (
		FODialog
		. open_on(
			self,
			tr("READINESS_TITLE"),
			tr("READINESS_MESSAGE"),
			[
				[tr("READINESS_END_TURN"), "GhostButton", top_bar.end_turn],
				[tr("READINESS_BACK"), "PrimaryButton"],
			]
		)
	)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", FOUi.tokens.space_1)
	for issue: Dictionary in issues:
		var link := LinkButton.new()
		link.text = issue["text"]
		link.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		# Always underlined: "pick one" must look like something to click.
		link.underline = LinkButton.UNDERLINE_MODE_ALWAYS
		link.pressed.connect(
			func():
				dialog.choose(1)
				if issue.has("screen"):
					show_screen(issue["screen"])
				else:
					show_screen("")
					go_to(issue["target"])
		)
		list.add_child(link)
	dialog.add_content(list)
	var dont_ask := CheckBox.new()
	dont_ask.text = tr("READINESS_DONT_ASK")
	dont_ask.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	dont_ask.toggled.connect(
		func(pressed: bool):
			if Engine.has_singleton("FOOptions"):
				var options := Engine.get_singleton("FOOptions")
				options.set_value(TurnReadiness.OPTION, not pressed)
				options.commit()
	)
	dialog.add_content(dont_ask)
	return dialog


# Proposals from other empires: count them on the Empires button.
func _on_diplomacy_changed() -> void:
	top_bar.set_badge("empires", FODiplomacy.get_incoming_count())
	if empires_screen.visible:
		empires_screen.refresh()


func _on_turn_update() -> void:
	check_game_over(FOUniverse.get_empire_resources())
	# The map mode's values follow the new turn.
	map_modes.set_map_mode(map_view.map.map_mode)
	_on_diplomacy_changed()
	system_panel.refresh()
	if fleet_panel.visible:
		fleet_panel.refresh()
	if planet_panel.visible:
		planet_panel.refresh()
	if ship_panel.visible:
		ship_panel.refresh()
	if production_screen.visible:
		production_screen.refresh()
	if research_screen.visible:
		research_screen.refresh()
	if government_screen.visible:
		government_screen.refresh()
	if objects_screen.visible:
		objects_screen.refresh()
	_show_route(system_panel.selected_fleet_id())
	if follow_game:
		MoveOrders.explore_new_scouts()
	auto_turn_guard.on_new_turn(self)


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
				# Select the fleet too, and show the ship's details.
				go_to(
					{
						"system_id": fleet.get_system_id(),
						"fleet_id": fleet_id,
						"position": fleet.get_position(),
					}
				)
				if kind == "ship":
					show_ship(arg.to_int())
				return
	if system_id >= 0:
		map_view.map.focus_system(system_id)


func _gap() -> int:
	return FOUi.tokens.space_4 if FOUi.tokens else 16
