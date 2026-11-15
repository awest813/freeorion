class_name UpstreamAdapters
extends RefCounted
## Temporary glue that adds fork features to upstream scenes at runtime, so
## upstream's .tscn files never need editing. Each adapter goes away once the
## fork's own screen replaces that upstream scene.

const GALAXY_MAP_VIEW := preload("res://map/GalaxyMapView.tscn")


## Called by FOUi for each new current scene, after its _ready().
static func adapt(scene: Node) -> void:
	match scene.scene_file_path:
		"res://MapWnd.tscn":
			_add_galaxy_map(scene)


# Upstream MapWnd has only a toolbar and turn button: put the map behind them.
static func _add_galaxy_map(map_wnd: Node) -> void:
	if map_wnd.has_node("GalaxyMapView"):
		return
	var view: Control = GALAXY_MAP_VIEW.instantiate()
	map_wnd.add_child(view)
	map_wnd.move_child(view, 0)
