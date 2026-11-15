class_name MapNavigator
extends RefCounted
## Steps through map targets with the keyboard, as the GG map's hotkeys do:
## all systems, systems with own planets, own fleets, and own fleets that
## aren't moving. Each kind keeps its own place in the cycle.

## Kinds of target, and the key presses that step through them:
## [kind, keycode, ctrl, shift, alt, direction].
const KEYS := [
	["system", KEY_COMMA, true, false, false, -1],
	["system", KEY_PERIOD, true, false, false, 1],
	["owned", KEY_COMMA, true, true, false, -1],
	["owned", KEY_PERIOD, true, true, false, 1],
	["fleet", KEY_F, true, false, false, -1],
	["fleet", KEY_G, true, false, false, 1],
	["idle", KEY_F, false, false, true, -1],
	["idle", KEY_G, false, false, true, 1],
]

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


## [kind, direction] for key \a event, or [] if it isn't a navigation key.
static func match_key(event: InputEventKey) -> Array:
	for entry in KEYS:
		if (
			event.keycode == entry[1]
			and event.ctrl_pressed == entry[2]
			and event.shift_pressed == entry[3]
			and event.alt_pressed == entry[4]
		):
			return [entry[0], entry[5]]
	return []


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
