class_name MapLayer
extends Node2D
## A drawing layer of the galaxy map; GalaxyMap supplies the draw callback.

var draw_callback: Callable


func _draw() -> void:
	if draw_callback.is_valid():
		draw_callback.call(self)
