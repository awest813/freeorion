class_name FleetPanel
extends PanelContainer
## Details of one own fleet: name (editable), destination, stance, ships
## (design, structure, roles) and split/merge. It doesn't order anything
## itself: it emits requests that GameShell turns into FOOrders and then
## refreshes the panel. show_fleet(id) reads the game; show_data(dict) takes
## the from_universe() layout directly (tests, previews).

signal rename_requested(fleet_id: int, new_name: String)
signal aggression_requested(fleet_id: int, aggression: String)
signal split_requested(ship_ids: PackedInt32Array)
signal merge_requested(dest_fleet_id: int, ship_ids: PackedInt32Array)

const WIDTH := 340
## Stance, its short label key and its full name key (tooltip, with the
## matching _DESC), in increasing aggression.
const STANCES := [
	["passive", "FLEET_STANCE_PASSIVE", "FW_PASSIVE"],
	["defensive", "FLEET_STANCE_DEFENSIVE", "FW_DEFENSIVE"],
	["obstructive", "FLEET_STANCE_OBSTRUCTIVE", "FW_OBSTRUCTIVE"],
	["aggressive", "FLEET_STANCE_AGGRESSIVE", "FW_AGGRESSIVE"],
]

var fleet_id := -1

var _data := {}
var _name: LineEdit
var _route: Label
var _stance_buttons := {}
var _ships: VBoxContainer
var _split: Button
var _merge_target: OptionButton
var _merge: Button
var _selected := {}


func _init() -> void:
	theme_type_variation = "OverlayPanel"
	custom_minimum_size.x = WIDTH
	visible = false
	_build()


## Show own fleet \a id from the client universe; -1 hides the panel.
func show_fleet(id: int) -> void:
	fleet_id = id
	show_data(from_universe(id) if id >= 0 else {})


func refresh() -> void:
	show_fleet(fleet_id)


func show_data(data: Dictionary) -> void:
	var was_hidden := not visible
	_data = data
	visible = not data.is_empty()
	if data.is_empty():
		return
	fleet_id = data.get("id", fleet_id)
	if was_hidden:
		FOUi.fade_in(self)
	if not _name.has_focus():
		_name.text = data.get("name", "")
	var destination: String = data.get("destination", "")
	_route.text = (
		(
			tr("SYSTEM_PANEL_FLEET_DESTINATION").replace("%1%", destination)
			+ "  ·  "
			+ GameShell.eta_text(data.get("eta", 0))
		)
		if not destination.is_empty()
		else tr("FLEET_PANEL_STATIONARY")
	)
	var aggression: String = data.get("aggression", "")
	for stance in _stance_buttons:
		_stance_buttons[stance].set_pressed_no_signal(stance == aggression)
	var ship_ids := {}
	ScreenKit.clear(_ships)
	for ship: Dictionary in data.get("ships", []):
		ship_ids[ship["id"]] = true
		_ships.add_child(_ship_row(ship))
	# Keep the split selection for ships still in the fleet.
	for id in _selected.keys():
		if not ship_ids.has(id):
			_selected.erase(id)
	_merge_target.clear()
	for target: Dictionary in data.get("merge_targets", []):
		_merge_target.add_item(target["name"], target["id"])
	_merge_target.visible = _merge_target.item_count > 0
	_merge.visible = _merge_target.item_count > 0
	_update_buttons()


func selected_ship_ids() -> PackedInt32Array:
	return PackedInt32Array(_selected.keys())


## Panel data for own fleet \a id from the client universe ({} if unknown).
static func from_universe(id: int) -> Dictionary:
	var fleet: FOFleet = FOUniverse.get_fleet(id)
	if fleet == null:
		return {}
	var ships: Array[Dictionary] = []
	for ship_id in fleet.get_ship_ids():
		var ship: FOShip = FOUniverse.get_ship(ship_id)
		if ship == null:
			continue
		(
			ships
			. push_back(
				{
					"id": ship_id,
					"name": ship.get_name(),
					"design": ship.get_design_name(),
					"icon": ship.get_icon(),
					"structure": ship.get_structure(),
					"max_structure": ship.get_max_structure(),
					"armed": ship.is_armed(),
					"colony": ship.can_colonize(),
					"troops": ship.has_troops(),
				}
			)
		)
	var destination := ""
	var destination_id := fleet.get_final_destination_id()
	if destination_id >= 0 and destination_id != fleet.get_system_id():
		var target: FOSystem = FOUniverse.get_system(destination_id)
		destination = target.get_name() if target else ""
	var merge_targets: Array[Dictionary] = []
	var system: FOSystem = FOUniverse.get_system(fleet.get_system_id())
	if system:
		for other_id in system.get_fleet_ids():
			var other: FOFleet = FOUniverse.get_fleet(other_id)
			if other and other_id != id and other.get_owner_id() == fleet.get_owner_id():
				merge_targets.push_back({"id": other_id, "name": other.get_name()})
	return {
		"id": id,
		"name": fleet.get_name(),
		"aggression": fleet.get_aggression(),
		"destination": destination,
		"eta": fleet.get_eta(),
		"ships": ships,
		"merge_targets": merge_targets,
	}


func _build() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	_name = LineEdit.new()
	_name.tooltip_text = tr("FLEET_PANEL_RENAME")
	_name.text_submitted.connect(_on_name_submitted)
	box.add_child(_name)
	_route = ScreenKit.label("", "SecondaryLabel")
	box.add_child(_route)

	# Segmented control: stance names as text (clearer than the dark GG icons).
	var stance_row := HBoxContainer.new()
	stance_row.add_theme_constant_override("separation", FOUi.tokens.space_1)
	box.add_child(stance_row)
	var group := ButtonGroup.new()
	for stance in STANCES:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.text = tr(stance[1])
		button.theme_type_variation = "SegmentButton"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "%s\n%s" % [tr(stance[2]), tr(stance[2] + "_DESC")]
		button.pressed.connect(_on_stance_pressed.bind(stance[0]))
		stance_row.add_child(button)
		_stance_buttons[stance[0]] = button

	box.add_child(HSeparator.new())
	_ships = VBoxContainer.new()
	box.add_child(_ships)

	var actions := HBoxContainer.new()
	box.add_child(actions)
	_split = Button.new()
	_split.text = tr("FLEET_PANEL_SPLIT")
	_split.tooltip_text = tr("FLEET_PANEL_SPLIT_DESC")
	_split.pressed.connect(func(): split_requested.emit(selected_ship_ids()))
	actions.add_child(_split)
	_merge_target = OptionButton.new()
	_merge_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_merge_target.clip_text = true
	actions.add_child(_merge_target)
	_merge = Button.new()
	_merge.text = tr("FLEET_PANEL_MERGE")
	_merge.tooltip_text = tr("FLEET_PANEL_MERGE_DESC")
	_merge.pressed.connect(_on_merge_pressed)
	actions.add_child(_merge)


func _ship_row(ship: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var pick := CheckBox.new()
	pick.button_pressed = _selected.has(ship["id"])
	pick.tooltip_text = tr("FLEET_PANEL_SELECT_SHIP")
	pick.toggled.connect(_on_ship_toggled.bind(ship["id"]))
	row.add_child(pick)
	row.add_child(ScreenKit.icon(ship.get("icon", ""), FOUi.tokens.icon))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var title := ScreenKit.label(ship.get("name", ""))
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(title)
	var roles: PackedStringArray = [ship.get("design", "")]
	for role in [
		["armed", "FLEET_PANEL_ARMED"],
		["colony", "FLEET_PANEL_COLONY"],
		["troops", "FLEET_PANEL_TROOPS"]
	]:
		if ship.get(role[0], false):
			roles.push_back(tr(role[1]))
	text.add_child(ScreenKit.label(" · ".join(roles), "SmallLabel"))
	var max_structure: float = ship.get("max_structure", 0.0)
	if max_structure > 0.0:
		var structure := ProgressBar.new()
		structure.max_value = max_structure
		structure.value = ship.get("structure", 0.0)
		structure.show_percentage = false
		structure.custom_minimum_size.y = FOUi.tokens.space_1
		structure.tooltip_text = (
			"%s %.0f / %.0f" % [tr("FLEET_PANEL_STRUCTURE"), structure.value, max_structure]
		)
		text.add_child(structure)
	return row


func _update_buttons() -> void:
	var ships: Array = _data.get("ships", [])
	# Splitting needs some ships selected, but not all of them.
	_split.disabled = _selected.is_empty() or _selected.size() >= ships.size()


func _on_ship_toggled(pressed: bool, ship_id: int) -> void:
	if pressed:
		_selected[ship_id] = true
	else:
		_selected.erase(ship_id)
	_update_buttons()


func _on_stance_pressed(stance: String) -> void:
	aggression_requested.emit(fleet_id, stance)


func _on_name_submitted(new_name: String) -> void:
	_name.release_focus()
	if new_name.strip_edges() != _data.get("name", "") and not new_name.strip_edges().is_empty():
		rename_requested.emit(fleet_id, new_name.strip_edges())


# Merge moves all of this fleet's ships into the chosen fleet.
func _on_merge_pressed() -> void:
	if _merge_target.selected < 0:
		return
	var ids := PackedInt32Array()
	for ship: Dictionary in _data.get("ships", []):
		ids.push_back(ship["id"])
	merge_requested.emit(_merge_target.get_item_id(_merge_target.selected), ids)
