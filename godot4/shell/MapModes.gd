class_name MapModes
extends CenterContainer
## What the map is being used for besides looking, for GameShell: placing
## production (systems that can build an item ringed, a click queues it),
## fleets selected together by a box (moved, merged, set to a stance or to
## explore as one, with a route preview for the slowest), and the map aids
## (scale legend, scale circle, minimap) shown or hidden. A banner over the
## top of the map says what is going on and offers the way out. Pressing or
## releasing Shift redraws the route preview (Shift adds to the route).

## Map aids: hotkey -> option remembering whether it's shown.
const MAP_AIDS := {
	"scale_legend": "ui.map.scale.legend.shown",
	"scale_circle": "ui.map.scale.circle.shown",
	"minimap": "ui.map.minimap.shown",
	"zoom_slider": "ui.map.zoom.slider.shown",
}

## Remembers the map mode.
const OPTION_MAP_MODE := "ui.map.mode"

## Own fleets selected together by dragging a box on the map.
var selected_fleets := PackedInt32Array()
## mode -> its per-system values (GalaxyMap.mode_values); the game's by
## default, tests replace it.
var mode_data_provider: Callable = MapModeData.from_game
var banner: PanelContainer

var _shell: GameShell
## While placing production: {item, locations, added}.
var _placement := {}
var _label: Label
var _buttons: HBoxContainer

## What the current mode shows, above the picker (not in standard mode).
var _legend: PanelContainer


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
	# The message above, its buttons below: long messages with several
	# buttons stay narrow enough to sit between the panels.
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", FOUi.tokens.space_2)
	banner.add_child(rows)
	_label = ScreenKit.label("")
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_label)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_child(_buttons)


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
	_shell.refresh_fleet_views(target)


## Order every selected fleet to \a system_id (Shift: after their routes);
## say how many could go.
func move_selected_fleets(system_id: int) -> void:
	var append := Input.is_key_pressed(KEY_SHIFT)
	var moved := 0
	var problem := ""
	for fleet_id in selected_fleets:
		var why := FOOrders.move_problem(fleet_id, system_id, append)
		if FOOrders.issue_fleet_move(fleet_id, system_id, append) >= 0:
			moved += 1
		if problem == "":
			problem = why
	var text := tr("FLEETS_ORDERED").replace("%1%", str(moved)).replace(
		"%2%", str(selected_fleets.size())
	)
	# The first reason a fleet won't get there, so the count isn't a riddle.
	if problem != "":
		text += " " + tr(problem)
	_update_fleet_banner(text)
	_shell.system_panel.refresh()


## Set every selected fleet to \a stance (a FleetPanel.STANCES key).
func _set_selected_stance(stance: String) -> void:
	var done := 0
	for fleet_id in selected_fleets:
		if FOOrders.set_fleet_aggression(fleet_id, stance):
			done += 1
	_update_fleet_banner(
		tr("FLEETS_STANCE_SET").replace("%1%", str(done)).replace(
			"%2%", str(selected_fleets.size())
		)
	)


## Send every selected fleet exploring.
func _explore_selected() -> void:
	for fleet_id in selected_fleets:
		FOExplore.set_exploring(fleet_id, true)
	_update_fleet_banner(tr("FLEETS_EXPLORING"))
	_shell.system_panel.refresh()


## The route preview to \a system_id for the selected fleets: the slowest
## one's (it decides when they're all there); {} if none can go.
func group_preview(system_id: int) -> Dictionary:
	var slowest := {}
	for fleet_id in selected_fleets:
		var fleet: FOFleet = FOUniverse.get_fleet(fleet_id)
		if fleet == null or fleet.get_system_id() == system_id:
			continue
		var preview: Dictionary = fleet.preview_route(system_id, Input.is_key_pressed(KEY_SHIFT))
		if not preview.is_empty() and preview.get("eta", -1) >= slowest.get("eta", -2):
			slowest = preview
	return slowest


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.keycode == KEY_SHIFT and not key.echo and _shell.follow_game:
		MoveOrders.preview_route(_shell, _shell.map_view.map.hovered_system_id())


func _update_fleet_banner(note: String) -> void:
	var text := tr("FLEETS_SELECTED").replace("%1%", str(selected_fleets.size()))
	if not note.is_empty():
		text += "  " + note
	var actions := []
	if _shell.follow_game and _same_system(selected_fleets):
		actions.push_back([tr("FLEETS_MERGE_ALL"), "", merge_selected_fleets])
	if _shell.follow_game:
		actions.push_back(
			[tr("FLEET_STANCE_AGGRESSIVE"), "GhostButton", _set_selected_stance.bind("aggressive")]
		)
		actions.push_back(
			[tr("FLEET_STANCE_PASSIVE"), "GhostButton", _set_selected_stance.bind("passive")]
		)
		actions.push_back([tr("FLEETS_EXPLORE"), "GhostButton", _explore_selected])
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
		"zoom_slider":
			return _shell.zoom_slider.visible
	return false


func _apply_map_aid(aid: String, shown: bool) -> void:
	match aid:
		"scale_legend":
			_shell.map_scale.visible = shown
		"scale_circle":
			_shell.map_view.map.show_scale_circle = shown
		"minimap":
			_shell.minimap.visible = shown
		"zoom_slider":
			_shell.zoom_slider.visible = shown


# Map modes -------------------------------------------------------------


## Switch the map to \a mode (a GalaxyMap.MODES entry), and remember it.
func set_map_mode(mode: String) -> void:
	var map := _shell.map_view.map
	map.map_mode = mode
	map.mode_values = mode_data_provider.call(map.map_mode)
	_shell.map_mode_picker.select(GalaxyMap.MODES.find(map.map_mode))
	_shell.map_mode_picker.tooltip_text = (tr("MAP_MODE_TIP_" + map.map_mode.to_upper()).replace(
		"%1%", FOHotkeys.shown("map_mode")
	))
	_show_legend(map.map_mode)
	var options := Engine.get_singleton("FOOptions") if _shell.follow_game else null
	if options:
		options.add_option(OPTION_MAP_MODE, "OPTIONS_DB_UI_MAP_MODE", "standard")
		options.set_value(OPTION_MAP_MODE, map.map_mode)
		options.commit()


# Above the picker, while a mode other than the standard one is on: what
# its colours and marks mean (the picker's tooltip says it too, but only
# when pointed at).
func _show_legend(mode: String) -> void:
	var picker := _shell.map_mode_picker
	if _legend == null and picker.get_parent():
		_legend = PanelContainer.new()
		_legend.theme_type_variation = "OverlayPanel"
		_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# As wide as the picker, so the corner doesn't grow over the log.
		_legend.size_flags_horizontal = Control.SIZE_FILL
		var text := ScreenKit.label("", "SmallLabel")
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_legend.add_child(text)
		picker.get_parent().add_child(_legend)
		picker.get_parent().move_child(_legend, picker.get_index())
	if _legend:
		_legend.visible = mode != "standard"
		(_legend.get_child(0) as Label).text = tr("MAP_MODE_TIP_" + mode.to_upper())


## The next map mode (the map-mode hotkey), back to the first after the last.
func cycle_map_mode() -> void:
	var modes: Array = GalaxyMap.MODES
	set_map_mode(modes[(modes.find(_shell.map_view.map.map_mode) + 1) % modes.size()])
