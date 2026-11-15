class_name MapModes
extends CenterContainer
## What the map is being used for besides looking, for GameShell: placing
## production (systems that can build an item ringed, a click queues it),
## fleets selected together by a box (moved or merged as one), and the map
## aids (scale legend, scale circle, minimap) shown or hidden. A banner over
## the top of the map says what is going on and offers the way out.

## Map aids: hotkey -> option remembering whether it's shown.
const MAP_AIDS := {
	"scale_legend": "ui.map.scale.legend.shown",
	"scale_circle": "ui.map.scale.circle.shown",
	"minimap": "ui.map.minimap.shown",
}

## Own fleets selected together by dragging a box on the map.
var selected_fleets := PackedInt32Array()
var banner: PanelContainer

var _shell: GameShell
## While placing production: {item, locations, added}.
var _placement := {}
var _label: Label
var _buttons: HBoxContainer


func _init(shell: GameShell) -> void:
	_shell = shell
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_top = FOUi.tokens.space_4 if FOUi.tokens else 16
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Floating over the map, so it never squeezes the panels.
	banner = PanelContainer.new()
	banner.theme_type_variation = "OverlayPanel"
	banner.visible = false
	add_child(banner)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FOUi.tokens.space_3)
	banner.add_child(row)
	_label = ScreenKit.label("")
	row.add_child(_label)
	_buttons = HBoxContainer.new()
	row.add_child(_buttons)


## The banner's message.
func banner_text() -> String:
	return _label.text


## A message over the top of the map with buttons: [label, variation,
## action] each.
func show_banner(text: String, actions: Array) -> void:
	_label.text = text
	ScreenKit.clear(_buttons)
	for action: Array in actions:
		var button := Button.new()
		button.text = action[0]
		button.theme_type_variation = action[1]
		button.pressed.connect(action[2])
		_buttons.add_child(button)
	if not banner.visible:
		banner.visible = true
		FOUi.fade_in(banner)


func hide_banner() -> void:
	banner.visible = false


# Placing production ----------------------------------------------------


## Back to the map with the systems where \a item can be built ringed;
## clicking one queues it at the first of its \a locations there.
func start_placement(item: Dictionary, locations: Array) -> void:
	_placement = {"item": item, "locations": locations, "added": 0}
	var systems := PackedInt32Array()
	for location: Dictionary in locations:
		if location.get("system_id", -1) >= 0 and not location["system_id"] in systems:
			systems.push_back(location["system_id"])
	_shell.map_view.map.set_highlighted(systems)
	_shell.show_screen("")
	clear_fleet_selection()
	_update_placement_banner()


## Leave placing: rings off, banner gone, back to the production screen if
## anything was queued.
func end_placement() -> void:
	if _placement.is_empty():
		return
	var added: int = _placement.get("added", 0)
	cancel_placement()
	if added > 0:
		_shell.show_screen("production")


## Leave placing without going anywhere.
func cancel_placement() -> void:
	_placement = {}
	_shell.map_view.map.set_highlighted(PackedInt32Array())
	hide_banner()


func is_placing() -> bool:
	return not _placement.is_empty()


## A system was clicked: while placing, queue the item there if it can be.
func on_system_clicked(system_id: int) -> void:
	if _placement.is_empty() or not _shell.map_view.map.is_highlighted(system_id):
		return
	for location: Dictionary in _placement["locations"]:
		if location.get("system_id", -1) == system_id:
			if _shell.production_screen.source.enqueue(_placement["item"], location["id"]):
				_placement["added"] += 1
				_shell.top_bar.refresh_resources()
			break
	_update_placement_banner()


func _update_placement_banner() -> void:
	var text := tr("PRODUCTION_PLACE_HINT").replace(
		"%1%", _shell.production_screen.display_name(_placement["item"])
	)
	if _placement["added"] > 0:
		text += "  " + tr("PRODUCTION_PLACE_ADDED").replace("%1%", str(_placement["added"]))
	show_banner(text, [[tr("PRODUCTION_PLACE_DONE"), "PrimaryButton", end_placement]])


# Fleets selected together ----------------------------------------------


## Select own fleets \a fleet_ids together (box selection): one is selected
## as usual; several are ringed on the map and move together on right-click.
func select_fleets(fleet_ids: PackedInt32Array) -> void:
	if is_placing():
		return
	if fleet_ids.size() == 1:
		clear_fleet_selection()
		_go_to_fleet(fleet_ids[0])
		return
	selected_fleets = fleet_ids
	_shell.map_view.map.set_marked_fleets(fleet_ids)
	if fleet_ids.is_empty():
		hide_banner()
		return
	_shell.system_panel.select_fleet(-1)
	_update_fleet_banner("")


func has_fleet_selection() -> bool:
	return not selected_fleets.is_empty()


func clear_fleet_selection() -> void:
	if selected_fleets.is_empty():
		return
	selected_fleets = PackedInt32Array()
	_shell.map_view.map.set_marked_fleets(selected_fleets)
	if not is_placing():
		hide_banner()


## Move the ships of every selected fleet into the first one.
func merge_selected_fleets() -> void:
	if selected_fleets.size() < 2:
		return
	var target := selected_fleets[0]
	for fleet_id in selected_fleets.slice(1):
		var fleet: FOFleet = FOUniverse.get_fleet(fleet_id)
		if fleet:
			FOOrders.merge_ships(target, fleet.get_ship_ids())
	clear_fleet_selection()
	_shell._refresh_fleet_views(target)


## Order every selected fleet to \a system_id (Shift: after their routes);
## say how many could go.
func move_selected_fleets(system_id: int) -> void:
	var append := Input.is_key_pressed(KEY_SHIFT)
	var moved := 0
	for fleet_id in selected_fleets:
		if FOOrders.issue_fleet_move(fleet_id, system_id, append) >= 0:
			moved += 1
	_update_fleet_banner(
		tr("FLEETS_ORDERED").replace("%1%", str(moved)).replace("%2%", str(selected_fleets.size()))
	)
	_shell.system_panel.refresh()


func _update_fleet_banner(note: String) -> void:
	var text := tr("FLEETS_SELECTED").replace("%1%", str(selected_fleets.size()))
	if not note.is_empty():
		text += "  " + note
	var actions := []
	if _shell.follow_game and _same_system(selected_fleets):
		actions.push_back([tr("FLEETS_MERGE_ALL"), "", merge_selected_fleets])
	actions.push_back([tr("FLEETS_CLEAR"), "GhostButton", clear_fleet_selection])
	show_banner(text, actions)


static func _same_system(fleet_ids: PackedInt32Array) -> bool:
	var system_id := -1
	for fleet_id in fleet_ids:
		var fleet: FOFleet = FOUniverse.get_fleet(fleet_id)
		if not fleet or fleet.get_system_id() < 0:
			return false
		if system_id >= 0 and fleet.get_system_id() != system_id:
			return false
		system_id = fleet.get_system_id()
	return system_id >= 0


func _go_to_fleet(fleet_id: int) -> void:
	var fleet: FOFleet = FOUniverse.get_fleet(fleet_id) if _shell.follow_game else null
	if fleet:
		(
			_shell
			. go_to(
				{
					"system_id": fleet.get_system_id(),
					"fleet_id": fleet_id,
					"position": fleet.get_position(),
				}
			)
		)


# Map aids --------------------------------------------------------------


## Show each map aid as \a options (FOOptions) remember it.
func load_map_aids(options: Object) -> void:
	for aid in MAP_AIDS:
		if options.exists(MAP_AIDS[aid]):
			_apply_map_aid(aid, options.get_value(MAP_AIDS[aid]))


## Show or hide map aid \a aid (a MAP_AIDS key), and remember it.
func set_map_aid_shown(aid: String, shown: bool) -> void:
	_apply_map_aid(aid, shown)
	var options := Engine.get_singleton("FOOptions") if _shell.follow_game else null
	if options and options.exists(MAP_AIDS[aid]):
		options.set_value(MAP_AIDS[aid], shown)
		options.commit()


func toggle_map_aid(aid: String) -> void:
	set_map_aid_shown(aid, not is_map_aid_shown(aid))


func is_map_aid_shown(aid: String) -> bool:
	match aid:
		"scale_legend":
			return _shell.map_scale.visible
		"scale_circle":
			return _shell.map_view.map.show_scale_circle
		"minimap":
			return _shell.minimap.visible
	return false


func _apply_map_aid(aid: String, shown: bool) -> void:
	match aid:
		"scale_legend":
			_shell.map_scale.visible = shown
		"scale_circle":
			_shell.map_view.map.show_scale_circle = shown
		"minimap":
			_shell.minimap.visible = shown
