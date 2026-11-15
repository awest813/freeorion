class_name GameShell
extends Control
## In-game frame: the galaxy map with the context panel docked on the right.
## Grows into the Phase 4 shell (top bar, left rail, notifications); until
## then UpstreamAdapters places it under upstream MapWnd's toolbar.

const GALAXY_MAP_VIEW := preload("res://map/GalaxyMapView.tscn")

## Space kept free at the top, e.g. for upstream's toolbar.
var top_inset := 0.0:
	set(value):
		top_inset = value
		if _panel_margin:
			_panel_margin.add_theme_constant_override("margin_top", int(value) + _gap())

## Set false before adding to the tree to feed map and panel directly (tests).
var follow_game := true
var map_view: GalaxyMapView
var system_panel: SystemPanel
var _panel_margin: MarginContainer


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	map_view = GALAXY_MAP_VIEW.instantiate()
	map_view.follow_game = follow_game
	add_child(map_view)

	_panel_margin = MarginContainer.new()
	_panel_margin.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_panel_margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right", "margin_bottom"]:
		_panel_margin.add_theme_constant_override(side, _gap())
	_panel_margin.add_theme_constant_override("margin_top", int(top_inset) + _gap())
	add_child(_panel_margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_margin.add_child(column)
	system_panel = SystemPanel.new()
	column.add_child(system_panel)

	map_view.system_selected.connect(_on_system_selected)
	map_view.map.system_context_requested.connect(_on_system_context_requested)
	system_panel.close_requested.connect(map_view.map.select_system.bind(GalaxyMap.NO_SYSTEM))
	system_panel.fleet_selected.connect(_show_route)
	if follow_game and is_instance_valid(GlobalFreeOrionNode):
		GlobalFreeOrionNode.turn_update.connect(_on_turn_update)


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
	map_view.map.set_route(fleet.get_position(), fleet.get_travel_route())


func _gap() -> int:
	return FOUi.tokens.space_4 if FOUi.tokens else 16
