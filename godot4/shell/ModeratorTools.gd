class_name ModeratorTools
extends PanelContainer
## A moderator's tools, as the GG client's ModeratorActionsWnd: pick an
## action, then right-click on the map. Right-clicking empty space creates a
## system of the chosen star; right-clicking a system destroys it, gives its
## planets and fleets to the chosen empire, adds a planet of the chosen type
## and size, or adds or removes the starlane between it and the selected
## system. Shown only to moderators (FOModerator.get_role()).

## Actions: key, label key.
const ACTIONS := [
	["none", "MOD_NONE"],
	["destroy", "MOD_DESTROY"],
	["set_owner", "MOD_SET_OWNER"],
	["add_starlane", "MOD_ADD_STARLANE"],
	["remove_starlane", "MOD_REMOVE_STARLANE"],
	["create_system", "MOD_CREATE_SYSTEM"],
	["create_planet", "MOD_CREATE_PLANET"],
]

var action := "none"
## Sends the actions (FOModerator in game; a fake in tests).
var moderator: Variant = FOModerator
var star_type: OptionButton
var planet_type: OptionButton
var planet_size: OptionButton
var owner_pick: OptionButton

var _shell: GameShell
var _buttons := {}


func _init(shell: GameShell) -> void:
	_shell = shell
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "OverlayPanel"
	visible = false
	# Over the top of the map, between the messages and the hints.
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	offset_top = FOUi.tokens.space_4
	var box := VBoxContainer.new()
	add_child(box)
	box.add_child(ScreenKit.label(tr("MODERATOR"), "TitleLabel"))
	var row := HFlowContainer.new()
	row.custom_minimum_size.x = 560
	box.add_child(row)
	for entry in ACTIONS:
		var button := Button.new()
		button.text = tr(entry[1])
		button.toggle_mode = true
		button.button_pressed = entry[0] == action
		button.theme_type_variation = "SegmentButton"
		button.pressed.connect(select.bind(entry[0]))
		row.add_child(button)
		_buttons[entry[0]] = button
	var picks := HFlowContainer.new()
	box.add_child(picks)
	star_type = OptionButton.new()
	planet_type = OptionButton.new()
	planet_size = OptionButton.new()
	owner_pick = OptionButton.new()
	for pick in [star_type, planet_type, planet_size, owner_pick]:
		pick.fit_to_longest_item = false
		pick.custom_minimum_size.x = 140
		picks.add_child(pick)


func _ready() -> void:
	var map := _shell.map_view.map
	map.system_context_requested.connect(on_system_right_clicked)
	map.map_context_requested.connect(on_space_right_clicked)
	if not _shell.follow_game:
		return
	fill_choices(FOModerator.get_choices(), FODiplomacy.get_empires())
	var node := get_node_or_null("/root/GlobalFreeOrionNode")
	if node:
		node.start_game.connect(func(_new): update_role(FOModerator.get_role()))
		node.turn_update.connect(func(): update_role(FOModerator.get_role()))
	update_role(FOModerator.get_role())


## Show the tools if \a role is "moderator".
func update_role(role: String) -> void:
	visible = role == "moderator"


## Fill the pickers: \a choices from FOModerator.get_choices(), \a empires
## from FODiplomacy.get_empires() (owners, and "unowned").
func fill_choices(choices: Dictionary, empires: Array) -> void:
	for entry in [
		[star_type, "star_types"], [planet_type, "planet_types"], [planet_size, "planet_sizes"]
	]:
		var pick: OptionButton = entry[0]
		pick.clear()
		for choice: String in choices.get(entry[1], []):
			pick.add_item(tr(choice))
			pick.set_item_metadata(pick.item_count - 1, choice)
	owner_pick.clear()
	owner_pick.add_item(tr("UNOWNED"))
	owner_pick.set_item_metadata(0, -1)
	for empire: Dictionary in empires:
		owner_pick.add_item(empire.get("name", ""))
		owner_pick.set_item_metadata(owner_pick.item_count - 1, empire.get("id", -1))
	select(action)


## Pick action \a key (an ACTIONS key); only the pickers it uses show.
func select(key: String) -> void:
	action = key
	for other in _buttons:
		_buttons[other].set_pressed_no_signal(other == key)
	star_type.visible = key == "create_system"
	planet_type.visible = key == "create_planet"
	planet_size.visible = key == "create_planet"
	owner_pick.visible = key == "set_owner"


## A right-click on system \a system_id: the chosen action on it; whether
## anything was sent.
func on_system_right_clicked(system_id: int) -> bool:
	if not visible:
		return false
	var sent := false
	var selected: int = _shell.map_view.map.selected_system_id()
	match action:
		"destroy":
			sent = moderator.destroy(system_id)
		"create_planet":
			sent = moderator.create_planet(
				system_id, _picked(planet_type, "PT_BARREN"), _picked(planet_size, "SZ_MEDIUM")
			)
		"add_starlane":
			sent = selected >= 0 and moderator.add_starlane(selected, system_id)
		"remove_starlane":
			sent = selected >= 0 and moderator.remove_starlane(selected, system_id)
		"set_owner":
			var empire_id: int = owner_pick.get_item_metadata(maxi(owner_pick.selected, 0))
			for object_id in _contents(system_id):
				sent = moderator.set_owner(object_id, empire_id) or sent
	return sent


## A right-click on empty space at \a screen_pos: a new system there.
func on_space_right_clicked(screen_pos: Vector2) -> bool:
	if not visible or action != "create_system":
		return false
	var map := _shell.map_view.map
	var world: Vector2 = map.camera.screen_to_world(screen_pos)
	# The tool acts instead of the map menu.
	_shell.map_menu.hide.call_deferred()
	return moderator.create_system(world.x, world.y, _picked(star_type, "STAR_YELLOW"))


# The planets and fleets in a system (what GG's set-owner changes).
func _contents(system_id: int) -> Array:
	if not _shell.follow_game:
		return []
	var system: FOSystem = FOUniverse.get_system(system_id)
	if system == null:
		return []
	return Array(system.get_planet_ids()) + Array(system.get_fleet_ids())


static func _picked(pick: OptionButton, fallback: String) -> String:
	if pick.selected < 0:
		return fallback
	return str(pick.get_item_metadata(pick.selected))
