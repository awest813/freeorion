class_name MapNavigator
extends RefCounted
## Steps through map targets with the keyboard, as the GG map's hotkeys do:
## all systems, systems with own planets, own fleets, and own fleets that
## aren't moving. Each kind keeps its own place in the cycle.

## Kinds of target: [kind, direction] for each FOHotkeys hotkey stepping
## through them (Ctrl+, / Ctrl+. for systems, ... by default).
const HOTKEYS := {
	"system_prev": ["system", -1],
	"system_next": ["system", 1],
	"owned_prev": ["owned", -1],
	"owned_next": ["owned", 1],
	"fleet_prev": ["fleet", -1],
	"fleet_next": ["fleet", 1],
	"idle_prev": ["idle", -1],
	"idle_next": ["idle", 1],
}

## kind -> Array of targets {system_id, fleet_id (-1 for systems),
## position}; the game by default, a fake in tests.
var targets_provider: Callable = targets_from_game

var _index := {}


## The next (\a direction 1) or previous (-1) target of \a kind; {} if none.
func step(kind: String, direction: int) -> Dictionary:
	var targets: Array = targets_provider.call(kind)
	if targets.is_empty():
		return {}
	var index: int = _index.get(kind, -1 if direction > 0 else 0) + direction
	index = posmod(index, targets.size())
	_index[kind] = index
	return targets[index]


## [kind, direction] for FOHotkeys hotkey \a hotkey, or [] if it isn't a
## navigation hotkey.
static func match_hotkey(hotkey: String) -> Array:
	return HOTKEYS.get(hotkey, [])


## Targets of \a kind in the running game, in a stable order.
static func targets_from_game(kind: String) -> Array:
	var targets: Array = []
	match kind:
		"system":
			for system_id in FOUniverse.get_system_ids():
				var system: FOSystem = FOUniverse.get_system(system_id)
				targets.push_back(_target(system_id, -1, system.get_position(), system.get_name()))
		"owned":
			var seen := {}
			for planet: Dictionary in FOObjects.list_objects("planets", true):
				var system_id: int = planet["system_id"]
				if system_id >= 0 and not seen.has(system_id):
					seen[system_id] = true
					var system: FOSystem = FOUniverse.get_system(system_id)
					targets.push_back(
						_target(system_id, -1, system.get_position(), system.get_name())
					)
		"fleet", "idle":
			for fleet: Dictionary in FOObjects.list_objects("fleets", true):
				if (
					kind == "idle"
					and (fleet.get("moving", false) or fleet.get("destination", "") != "")
				):
					continue
				var view: FOFleet = FOUniverse.get_fleet(fleet["id"])
				targets.push_back(
					_target(fleet["system_id"], fleet["id"], view.get_position(), fleet["name"])
				)
	targets.sort_custom(func(a, b): return a["sort"] < b["sort"])
	return targets


static func _target(system_id: int, fleet_id: int, position: Vector2, label: String) -> Dictionary:
	return {
		"system_id": system_id,
		"fleet_id": fleet_id,
		"position": position,
		"sort": "%s#%d" % [label, fleet_id if fleet_id >= 0 else system_id],
	}
