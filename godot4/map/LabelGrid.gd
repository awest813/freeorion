class_name LabelGrid
extends RefCounted
## Screen-space occupancy grid for greedy label placement on the galaxy map.

const CELL := 64.0
var _cells := {}


func try_place(rect: Rect2) -> bool:
	var keys := _keys(rect)
	for key in keys:
		for other: Rect2 in _cells.get(key, []):
			if other.intersects(rect):
				return false
	for key in keys:
		if not _cells.has(key):
			_cells[key] = []
		_cells[key].push_back(rect)
	return true


func _keys(rect: Rect2) -> Array[Vector2i]:
	var keys: Array[Vector2i] = []
	for cx in range(floori(rect.position.x / CELL), floori(rect.end.x / CELL) + 1):
		for cy in range(floori(rect.position.y / CELL), floori(rect.end.y / CELL) + 1):
			keys.push_back(Vector2i(cx, cy))
	return keys
