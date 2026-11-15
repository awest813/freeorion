class_name GalaxyMapView
extends SubViewportContainer
## Control that hosts the galaxy map in its own SubViewport, so the map camera
## never moves UI drawn around it. Follows the running game unless
## follow_game is false (tests feed data directly to `map`).

signal system_selected(system_id: int)

@export var follow_game := true

@onready var map: GalaxyMap = $Viewport/GalaxyMap


func _ready() -> void:
	map.system_selected.connect(system_selected.emit)
	if not follow_game or not is_instance_valid(GlobalFreeOrionNode):
		return
	GlobalFreeOrionNode.start_game.connect(_on_start_game)
	GlobalFreeOrionNode.turn_update.connect(refresh)
	if GlobalFreeOrionNode.get_current_turn() >= 1:
		refresh()


func refresh() -> void:
	map.load_from_universe()


func _on_start_game(_is_new_game: bool) -> void:
	refresh()
