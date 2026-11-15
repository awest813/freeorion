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

	map_view.system_selected.connect(system_panel.show_system)
	system_panel.close_requested.connect(map_view.map.select_system.bind(GalaxyMap.NO_SYSTEM))
	if follow_game and is_instance_valid(GlobalFreeOrionNode):
		GlobalFreeOrionNode.turn_update.connect(system_panel.refresh)


func _gap() -> int:
	return FOUi.tokens.space_4 if FOUi.tokens else 16
