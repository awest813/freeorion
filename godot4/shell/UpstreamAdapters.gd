class_name UpstreamAdapters
extends RefCounted
## Temporary glue that adds fork features to upstream scenes at runtime, so
## upstream's .tscn files never need editing. Each adapter goes away once the
## fork's own screen replaces that upstream scene.


## Called by FOUi for each new current scene, after its _ready().
static func adapt(scene: Node) -> void:
	match scene.scene_file_path:
		"res://MapWnd.tscn":
			_add_galaxy_map(scene)


# Upstream MapWnd has only a toolbar and turn button: replace them with the
# game shell (map, top bar with End Turn, context panel).
static func _add_galaxy_map(map_wnd: Node) -> void:
	if map_wnd.has_node("GameShell"):
		return
	# Loaded at runtime so a script error in the shell or its panels can't break
	# the FOUi autoload (which loads this file) and with it theme and scale.
	var shell_script: GDScript = load("res://shell/GameShell.gd")
	if shell_script == null or not shell_script.can_instantiate():
		push_error("GameShell failed to load; upstream MapWnd shown without the map")
		return
	var shell: Control = shell_script.new()
	shell.name = "GameShell"
	# The shell's top bar replaces upstream's toolbar (turn button included).
	var toolbar := map_wnd.get_node_or_null("ToolBar") as CanvasItem
	if toolbar:
		toolbar.visible = false
	map_wnd.add_child(shell)
	map_wnd.move_child(shell, 0)
