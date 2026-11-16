class_name SettleTargets
extends VBoxContainer
## In the fleet panel, for an own idle fleet with colony or outpost ships: the
## nearest places it could settle (planet, projected population, turns to get
## there), each a button sending the fleet there, or settling at once when
## it is here. With none in reach, says to explore further.

## Send the fleet shown to \a system_id.
signal send_requested(fleet_id: int, system_id: int)
## Settle \a planet_id, in the fleet's system, now.
signal settle_requested(planet_id: int)
## The places listed changed (empty when the list is hidden), for the map.
signal targets_changed(targets: Array)
## The pointer is over the place in \a system_id (-1: left it): preview the
## route there.
signal target_hovered(system_id: int)

## Places shown at most.
const COUNT := 3

## (fleet_id, count) -> rows as FOPlanetActions.colony_targets(); tests swap it.
var provider := func(id: int, count: int) -> Array: return FOPlanetActions.colony_targets(id, count)

var _fleet_id := -1
var _rows: VBoxContainer


func _init() -> void:
	visible = false
	add_child(ScreenKit.label(tr("SETTLE_TARGETS_TITLE"), "SmallLabel"))
	_rows = VBoxContainer.new()
	add_child(_rows)


## Show the places for fleet \a data (FleetPanel.from_universe()): only for an
## own fleet with colony ships that isn't on its way somewhere.
func show_fleet(data: Dictionary, own: bool) -> void:
	_fleet_id = data.get("id", -1)
	var settlers: bool = data.get("ships", []).any(func(s): return s.get("colony", false))
	visible = own and settlers and str(data.get("destination", "")) == ""
	ScreenKit.clear(_rows)
	if not visible:
		targets_changed.emit([])
		return
	var targets: Array = provider.call(_fleet_id, COUNT)
	targets_changed.emit(targets)
	if targets.is_empty():
		var none := ScreenKit.label(tr("SETTLE_TARGETS_NONE"), "SecondaryLabel")
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_rows.add_child(none)
		return
	for target: Dictionary in targets:
		_rows.add_child(_target_button(target))


## The text of a place \a target: planet, what grows there, how far.
static func target_text(target: Dictionary) -> String:
	var tr_s := func(key: String) -> String: return TranslationServer.translate(key)
	var what: String = (
		tr_s.call("SETTLE_TARGETS_OUTPOST")
		if target.get("outpost", false)
		else (tr_s.call("SETTLE_TARGETS_POPULATION").replace(
			"%1%", "%.1f" % target.get("target_population", 0.0)
		))
	)
	var eta: int = target.get("eta", 0)
	var when: String = tr_s.call("SETTLE_TARGETS_HERE") if eta == 0 else ScreenKit.turns_text(eta)
	return "%s · %s · %s" % [target.get("planet_name", ""), what, when]


func _target_button(target: Dictionary) -> Button:
	var button := Button.new()
	button.text = target_text(target)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var system_id: int = target.get("system_id", -1)
	var planet_id: int = target.get("planet_id", -1)
	button.mouse_entered.connect(func(): target_hovered.emit(system_id))
	button.mouse_exited.connect(func(): target_hovered.emit(-1))
	if target.get("eta", 0) == 0:
		button.tooltip_text = tr("SETTLE_TARGETS_SETTLE")
		button.pressed.connect(func(): settle_requested.emit(planet_id))
	else:
		button.tooltip_text = tr("SETTLE_TARGETS_SEND").replace(
			"%1%", target.get("system_name", "")
		)
		button.pressed.connect(func(): send_requested.emit(_fleet_id, system_id))
	return button


## Map marks ([{position, text}], FleetLayer.set_settle_marks()) for
## \a targets: one per system, with what its places would be (population or
## outpost, "×2" for two alike) and how far.
static func map_marks(targets: Array) -> Array:
	var by_system := {}
	for target: Dictionary in targets:
		var system_id: int = target.get("system_id", -1)
		var system: FOSystem = FOUniverse.get_system(system_id)
		if system == null:
			continue
		if not by_system.has(system_id):
			by_system[system_id] = {"position": system.get_position(), "targets": []}
		by_system[system_id]["targets"].push_back(target)
	var marks := []
	for entry: Dictionary in by_system.values():
		marks.push_back({"position": entry["position"], "text": mark_text(entry["targets"])})
	return marks


## A map mark's text for \a targets in one system: "outpost ×2 · 3 turns".
static func mark_text(targets: Array) -> String:
	var counts := {}
	for target: Dictionary in targets:
		var what: String = target_text(target).get_slice(" · ", 1)
		counts[what] = counts.get(what, 0) + 1
	var whats := []
	for what: String in counts:
		whats.push_back(what if counts[what] == 1 else "%s ×%d" % [what, counts[what]])
	return "%s · %s" % [", ".join(whats), target_text(targets[0]).get_slice(" · ", 2)]
