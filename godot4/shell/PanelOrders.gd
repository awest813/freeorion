class_name PanelOrders
extends RefCounted
## What the side panels ask for, turned into orders for GameShell: fleet
## renames, stances, splits and merges, scrapping, gifts to empires at
## peace, renaming systems and planets; then the panels are refreshed.

var _shell: GameShell


func _init(shell: GameShell) -> void:
	_shell = shell


func on_fleet_rename(fleet_id: int, new_name: String) -> void:
	if FOOrders.rename(fleet_id, new_name):
		_shell.refresh_fleet_views(fleet_id)


func on_fleet_aggression(fleet_id: int, aggression: String) -> void:
	FOOrders.set_fleet_aggression(fleet_id, aggression)
	_shell.refresh_fleet_views(fleet_id)


func on_fleet_split(ship_ids: PackedInt32Array) -> void:
	var new_fleet := FOOrders.split_ships(ship_ids, _shell.fleet_panel.new_fleet_stance)
	_shell.refresh_fleet_views(new_fleet if new_fleet >= 0 else _shell.fleet_panel.fleet_id)


# Several new fleets at once (split damaged, per ship, per design, ...);
# the fleet they left stays selected.
func on_fleet_split_groups(groups: Array) -> void:
	var source := _shell.fleet_panel.fleet_id
	for ship_ids: PackedInt32Array in groups:
		if not ship_ids.is_empty():
			FOOrders.split_ships(ship_ids, _shell.fleet_panel.new_fleet_stance)
	_shell.refresh_fleet_views(source)


# Every other own fleet at the fleet's system joins it.
func on_fleet_merge_all(fleet_id: int) -> void:
	var fleet: FOFleet = FOUniverse.get_fleet(fleet_id)
	var system: FOSystem = FOUniverse.get_system(fleet.get_system_id()) if fleet else null
	if system == null:
		return
	for other_id in system.get_fleet_ids():
		var other: FOFleet = FOUniverse.get_fleet(other_id)
		if other and other_id != fleet_id and other.get_owner_id() == fleet.get_owner_id():
			FOOrders.merge_ships(fleet_id, other.get_ship_ids())
	_shell.refresh_fleet_views(fleet_id)


func on_new_fleet_stance(stance: String) -> void:
	var options := Engine.get_singleton("FOOptions") if _shell.follow_game else null
	if options:
		options.add_option(
			GameShell.OPTION_NEW_FLEET_STANCE, "OPTIONS_DB_FLEET_WND_AGGRESSION", "auto"
		)
		options.set_value(GameShell.OPTION_NEW_FLEET_STANCE, stance)
		options.commit()


func on_fleet_merge(dest_fleet_id: int, ship_ids: PackedInt32Array) -> void:
	if FOOrders.merge_ships(dest_fleet_id, ship_ids):
		_shell.refresh_fleet_views(dest_fleet_id)


func on_fleet_scrap(ship_ids: PackedInt32Array) -> void:
	for ship_id in ship_ids:
		FOPlanetActions.scrap(ship_id)
	_shell.refresh_fleet_views(_shell.fleet_panel.fleet_id)
	if _shell.ship_panel.visible:
		_shell.ship_panel.refresh()


# Systems with names, by name, for the system panel's picker.
func known_systems() -> Array:
	var systems := []
	if not _shell.follow_game:
		return systems
	for system_id in FOUniverse.get_system_ids():
		var system: FOSystem = FOUniverse.get_system(system_id)
		if system and not system.get_name().is_empty():
			systems.push_back([system_id, system.get_name()])
	systems.sort_custom(func(a, b): return a[1].naturalnocasecmp_to(b[1]) < 0)
	return systems


# Rename an own system or planet; the map shows the new name.
func on_rename(object_id: int, new_name: String) -> void:
	if _shell.follow_game and FOOrders.rename(object_id, new_name):
		_shell.map_view.refresh()
		_shell.system_panel.refresh()
		if _shell.planet_panel.visible:
			_shell.planet_panel.refresh()


# Give an own planet or fleet to an empire at peace (-1: cancel the gift).
func on_give(object_id: int, empire_id: int) -> void:
	if _shell.follow_game and FOOrders.give_to_empire(object_id, empire_id):
		_shell.system_panel.refresh()
		if _shell.fleet_panel.visible:
			_shell.fleet_panel.refresh()
		if _shell.planet_panel.visible:
			_shell.planet_panel.refresh()
