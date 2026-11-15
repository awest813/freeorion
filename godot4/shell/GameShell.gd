class_name GameShell
extends Control
## In-game frame: the galaxy map, the top bar and the context panel docked on
## the right. Grows into the Phase 4 shell (left rail, notifications); until
## then UpstreamAdapters places it in upstream's MapWnd.

const GALAXY_MAP_VIEW := preload("res://map/GalaxyMapView.tscn")

## Set false before adding to the tree to feed map and panel directly (tests).
var follow_game := true
var map_view: GalaxyMapView
var top_bar: TopBar
var system_panel: SystemPanel
var feed: NotificationFeed


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

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(body)
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

	top_bar.resized.connect(_update_frame_margins)

	map_view.system_selected.connect(_on_system_selected)
	map_view.map.system_context_requested.connect(_on_system_context_requested)
	system_panel.close_requested.connect(map_view.map.select_system.bind(GalaxyMap.NO_SYSTEM))
	system_panel.fleet_selected.connect(_show_route)
	if follow_game and is_instance_valid(GlobalFreeOrionNode):
		GlobalFreeOrionNode.turn_update.connect(_on_turn_update)


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


func _on_turn_update() -> void:
	system_panel.refresh()
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


# Links in sitreps: objects on the map select (and centre on) their system.
func _on_link_activated(kind: String, arg: String) -> void:
	if not follow_game or not arg.is_valid_int():
		return
	var system_id := -1
	match kind:
		"system":
			system_id = arg.to_int()
		"planet":
			var planet: FOPlanet = FOUniverse.get_planet(arg.to_int())
			system_id = planet.get_system_id() if planet else -1
		"fleet":
			var fleet: FOFleet = FOUniverse.get_fleet(arg.to_int())
			if fleet:
				system_id = fleet.get_system_id()
				if system_id < 0:
					map_view.map.camera.center_on(fleet.get_position())
					return
	if system_id >= 0:
		map_view.map.focus_system(system_id)


func _gap() -> int:
	return FOUi.tokens.space_4 if FOUi.tokens else 16
