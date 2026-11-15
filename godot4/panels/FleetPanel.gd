class_name FleetPanel
extends PanelContainer
## Details of one fleet: name (editable), destination, stance, ships
## (design, structure, roles) and split/merge. Other empires' and monster
## fleets are shown read-only, with their owner. It doesn't order anything
## itself: it emits requests that GameShell turns into FOOrders and then
## refreshes the panel. show_fleet(id) reads the game; show_data(dict) takes
## the from_universe() layout directly (tests, previews).

signal rename_requested(fleet_id: int, new_name: String)
signal aggression_requested(fleet_id: int, aggression: String)
signal split_requested(ship_ids: PackedInt32Array)
signal merge_requested(dest_fleet_id: int, ship_ids: PackedInt32Array)
## Scrap the ships (or cancel their scrapping) at the next turn.
signal scrap_requested(ship_ids: PackedInt32Array)
## A ship's name was clicked: show its details.
signal ship_selected(ship_id: int)
## Make a new fleet of each group of ships (PackedInt32Array each).
signal split_groups_requested(groups: Array)
## Move the ships of every other own fleet here into fleet \a fleet_id.
signal merge_all_requested(fleet_id: int)
## The stance new fleets get was changed ("auto" or a stance).
signal new_fleet_stance_changed(stance: String)
## Give the fleet to empire \a empire_id (-1: cancel a gift).
signal give_requested(fleet_id: int, empire_id: int)
## Forget sensor ghost \a fleet_id (or one of its ships).
signal forget_requested(fleet_id: int)
## Send the fleet exploring on its own, or stop it.
signal explore_requested(fleet_id: int, exploring: bool)

## Type of the drag data ship rows give: {type, fleet_id, ship_ids}.
const SHIP_DRAG := "fo_ships"

const WIDTH := 340
## Ship rows shown before the list scrolls.
const VISIBLE_SHIPS := 5
## Stance, its short label key and its full name key (tooltip, with the
## matching _DESC), in increasing aggression.
const STANCES := [
	["passive", "FLEET_STANCE_PASSIVE", "FW_PASSIVE"],
	["defensive", "FLEET_STANCE_DEFENSIVE", "FW_DEFENSIVE"],
	["obstructive", "FLEET_STANCE_OBSTRUCTIVE", "FW_OBSTRUCTIVE"],
	["aggressive", "FLEET_STANCE_AGGRESSIVE", "FW_AGGRESSIVE"],
]

## Fleet menu entries: id, label key.
const MENU := [
	[11, "ORDER_FLEET_EXPLORE"],
	[12, "ORDER_CANCEL_FLEET_EXPLORE"],
	[0, "FW_MERGE_SYSTEM_FLEETS"],
	[1, "FW_SPLIT_DAMAGED_FLEET"],
	[2, "FW_SPLIT_UNFUELED_FLEET"],
	[3, "FW_SPLIT_NOT_FULL_FIGHTERS_FLEET"],
	[4, "FW_SPLIT_FLEET"],
	[5, "FW_SPLIT_SHIPS_ALL_DESIGNS"],
	[6, "ORDER_FLEET_SCRAP"],
	[7, "ORDER_CANCEL_FLEET_SCRAP"],
	[9, "ORDER_CANCEL_GIVE_FLEET"],
	[10, "FW_ORDER_DISMISS_SENSOR_GHOST"],
]
## Menu ids of "give to empire N" are GIVE_MENU_BASE + N.
const GIVE_MENU_BASE := 1000
## Menu ids of "split off design N's ships" are DESIGN_MENU_BASE + N.
const DESIGN_MENU_BASE := 100000
## Fleet totals: key, icon, tooltip key.
const TOTALS := [
	["count", "icons/sitrep/fleet_arrived.png", "FW_FLEET_COUNT_SUMMARY"],
	["damage", "icons/meter/damage.png", "FW_FLEET_DAMAGE_SUMMARY"],
	["destroy", "icons/meter/ammo.png", "FW_FLEET_DESTROY_SUMMARY"],
	["fighters", "icons/meter/fighters.png", "FW_FLEET_FIGHTER_SUMMARY"],
	["troops", "icons/meter/troops.png", "FW_FLEET_TROOP_SUMMARY"],
	["colony", "icons/meter/colony.png", "FW_FLEET_COLONY_SUMMARY"],
	["structure", "icons/meter/structure.png", "FW_FLEET_STRUCTURE_SUMMARY"],
	["shield", "icons/meter/shield.png", "FW_FLEET_SHIELD_SUMMARY"],
	["fuel", "icons/meter/fuel.png", "FW_FLEET_FUEL_SUMMARY"],
	["speed", "icons/meter/speed.png", "FW_FLEET_SPEED_SUMMARY"],
]
## Stances a new fleet can get: "auto" first.
const NEW_FLEET_STANCES := ["auto", "passive", "defensive", "obstructive", "aggressive"]
const STANCE_MENU_BASE := 100

var fleet_id := -1
## The stance fleets split off this one get ("auto" or a stance).
var new_fleet_stance := "auto"
## Empires at peace the fleet can be given to: FOOrders.get_give_targets().
var give_targets_provider := func(id: int) -> Dictionary: return FOOrders.get_give_targets(id)

var _data := {}
var _name: LineEdit
var _route: Label
var _owner: Label
var _menu: MenuButton
var _totals: HFlowContainer
var _actions: HBoxContainer
var _scrap_row: HBoxContainer
var _stance_buttons := {}
var _ships: VBoxContainer
var _ships_scroll: ScrollContainer
var _split: Button
var _merge_target: OptionButton
var _merge: Button
var _scrap: Button
var _notice: Label
var _selected := {}


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "OverlayPanel"
	custom_minimum_size.x = WIDTH
	visible = false
	_build()


## Show fleet \a id from the client universe; -1 hides the panel.
func show_fleet(id: int) -> void:
	fleet_id = id
	show_data(from_universe(id) if id >= 0 else {})


func refresh() -> void:
	show_fleet(fleet_id)


## Say why an order wasn't given ("" clears it).
func show_notice(text: String) -> void:
	_notice.text = text
	_notice.visible = not text.is_empty()


func show_data(data: Dictionary) -> void:
	if data.get("id", -1) != _data.get("id", -2):
		show_notice("")
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
	var own := is_own()
	_name.editable = own
	_name.tooltip_text = tr("FLEET_PANEL_RENAME") if own else ""
	_owner.text = data.get("owner_name", "")
	_owner.visible = not own and not _owner.text.is_empty()
	_owner.add_theme_color_override("font_color", data.get("owner_color", Color.WHITE))
	_actions.visible = own
	_scrap_row.visible = own
	_menu.visible = own or data.get("ghost", false)
	_fill_totals(fleet_totals(data.get("ships", [])))
	_route.text = route_text(data)
	var blockade: Dictionary = data.get("blockade", {})
	_route.tooltip_text = ""
	if blockade.get("blockaded", false):
		_route.text += "  ·  " + tr("FLEET_PANEL_BLOCKADED")
		_route.tooltip_text = blockade_text(blockade)
	var aggression: String = data.get("aggression", "")
	for stance in _stance_buttons:
		_stance_buttons[stance].set_pressed_no_signal(stance == aggression)
		_stance_buttons[stance].disabled = not own
	var ship_ids := {}
	ScreenKit.clear(_ships)
	for ship: Dictionary in data.get("ships", []):
		ship_ids[ship["id"]] = true
		_ships.add_child(_ship_row(ship))
	_fit_ship_list()
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


# Big fleets scroll instead of pushing the panel off the screen.
func _fit_ship_list() -> void:
	var height := 0.0
	var rows := _ships.get_children().filter(func(row): return not row.is_queued_for_deletion())
	for i in mini(rows.size(), VISIBLE_SHIPS):
		height += rows[i].get_combined_minimum_size().y
	height += (
		_ships.get_theme_constant("separation") * maxi(0, mini(rows.size(), VISIBLE_SHIPS) - 1)
	)
	_ships_scroll.custom_minimum_size.y = height


## Whether the fleet shown is the player's own (else it's read-only).
func is_own() -> bool:
	return _data.get("own", true)


func selected_ship_ids() -> PackedInt32Array:
	return PackedInt32Array(_selected.keys())


## Panel data for fleet \a id from the client universe ({} if unknown).
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
					"stats": ship.get_stats(),
					"scrapping": FOPlanetActions.is_scrapping(ship_id),
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
	var owner_id := fleet.get_owner_id()
	return {
		"id": id,
		"own": owner_id >= 0 and owner_id == FOUniverse.get_empire_id(),
		"ghost": FOOrders.is_sensor_ghost(id),
		"exploring": FOExplore.is_exploring(id),
		"blockade": fleet.get_blockade(),
		"in_system": fleet.get_system_id() >= 0,
		"owner_name":
		(
			FOUniverse.get_empire_name(owner_id)
			if owner_id >= 0
			else TranslationServer.translate("MONSTERS")
		),
		"owner_color": FOUniverse.get_empire_color(owner_id),
		"name": fleet.get_name(),
		"aggression": fleet.get_aggression(),
		"destination": destination,
		"eta": fleet.get_eta(),
		"etas": fleet.get_etas(),
		"ships": ships,
		"merge_targets": merge_targets,
	}


func _build() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_name = LineEdit.new()
	_name.tooltip_text = tr("FLEET_PANEL_RENAME")
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_submitted.connect(_on_name_submitted)
	header.add_child(_name)
	_menu = MenuButton.new()
	_menu.text = "⋯"
	_menu.tooltip_text = tr("FLEET_PANEL_MENU")
	_menu.flat = false
	_menu.about_to_popup.connect(_fill_menu)
	_menu.get_popup().id_pressed.connect(_on_menu_id)
	header.add_child(_menu)
	_owner = ScreenKit.label("", "SmallLabel")
	_owner.visible = false
	box.add_child(_owner)
	_route = ScreenKit.label("", "SecondaryLabel")
	box.add_child(_route)
	_totals = HFlowContainer.new()
	_totals.add_theme_constant_override("h_separation", FOUi.tokens.space_3)
	box.add_child(_totals)

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
	_ships.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ships_scroll = ScrollContainer.new()
	_ships_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ships_scroll.add_child(_ships)
	# Rows know their height once laid out (the stats wrap to the width):
	# fit the list again then.
	_ships.resized.connect(_fit_ship_list, CONNECT_DEFERRED)
	box.add_child(_ships_scroll)

	var actions := HBoxContainer.new()
	_actions = actions
	box.add_child(actions)
	_split = Button.new()
	_split.text = tr("FLEET_PANEL_SPLIT")
	_split.tooltip_text = tr("FLEET_PANEL_SPLIT_DESC")
	_split.pressed.connect(func(): split_requested.emit(selected_ship_ids()))
	# Ships of this fleet dropped on Split go to a new fleet.
	_split.set_drag_forwarding(Callable(), _can_drop_on_split, _drop_on_split)
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
	# Scrapping on its own row, away from the everyday actions.
	var scrap_row := HBoxContainer.new()
	_scrap_row = scrap_row
	scrap_row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(scrap_row)
	_scrap = Button.new()
	_scrap.theme_type_variation = "DangerButton"
	_scrap.pressed.connect(func(): scrap_requested.emit(selected_ship_ids()))
	scrap_row.add_child(_scrap)
	# Why the last order was refused, until the fleet shown changes.
	_notice = ScreenKit.label("", "SmallLabel")
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.add_theme_color_override("font_color", FOUi.tokens.warning)
	_notice.visible = false
	box.add_child(_notice)


func _ship_row(ship: Dictionary) -> Control:
	var row := HBoxContainer.new()
	# Drag a ship (or the ticked ships, if it is one) onto another fleet to
	# move them there, or onto Split to make a new fleet.
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	if is_own():
		row.set_drag_forwarding(ship_drag_data.bind(ship["id"]), Callable(), Callable())
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
	var title := LinkButton.new()
	title.text = ship.get("name", "")
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	title.tooltip_text = tr("FLEET_PANEL_SHIP_DETAIL")
	title.pressed.connect(ship_selected.emit.bind(ship["id"]))
	text.add_child(title)
	var roles: PackedStringArray = [ship.get("design", "")]
	for role in [
		["armed", "FLEET_PANEL_ARMED"],
		["colony", "FLEET_PANEL_COLONY"],
		["troops", "FLEET_PANEL_TROOPS"]
	]:
		if ship.get(role[0], false):
			roles.push_back(tr(role[1]))
	var role_label := ScreenKit.label(" · ".join(roles), "SmallLabel")
	if ship.get("scrapping", false):
		role_label.text += " · " + tr("FLEET_PANEL_SCRAPPING")
		role_label.add_theme_color_override("font_color", FOUi.tokens.negative)
	text.add_child(role_label)
	var stats: Dictionary = ship.get("stats", {})
	if not stats.is_empty():
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", FOUi.tokens.space_2)
		for key in ["damage", "fighters", "troops", "colony", "shield", "fuel", "speed"]:
			var value := _stat_text(key, stats)
			if not value.is_empty():
				chips.add_child(_stat_chip(key, value))
		text.add_child(chips)
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
	# One ship of a sensor ghost fleet can be dismissed on its own.
	if _data.get("ghost", false) and _data.get("ships", []).size() > 1:
		var forget := ScreenKit.small_button("✕", "FW_ORDER_DISMISS_SENSOR_GHOST")
		forget.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		forget.pressed.connect(forget_requested.emit.bind(ship["id"]))
		row.add_child(forget)
	return row


## Drag data for ship \a ship_id's row: the ticked ships if it is one of
## them, else that ship alone.
func ship_drag_data(_at: Vector2, ship_id: int) -> Variant:
	var ids := selected_ship_ids() if _selected.has(ship_id) else PackedInt32Array([ship_id])
	if get_viewport() and get_viewport().gui_is_dragging():
		var preview := PanelContainer.new()
		preview.theme_type_variation = "OverlayPanel"
		preview.add_child(
			ScreenKit.label(
				(
					tr("FLEET_PANEL_DRAG_SHIPS").replace("%1%", str(ids.size()))
					if ids.size() > 1
					else _ship_name(ship_id)
				)
			)
		)
		set_drag_preview(preview)
	return {"type": SHIP_DRAG, "fleet_id": fleet_id, "ship_ids": ids}


## Whether \a data is ships dragged from a fleet other than \a target_fleet.
static func is_ship_drag(data: Variant, target_fleet := -1) -> bool:
	return (
		data is Dictionary
		and data.get("type", "") == SHIP_DRAG
		and data.get("fleet_id", -1) != target_fleet
	)


func _can_drop_on_split(_at: Vector2, data: Variant) -> bool:
	return (
		data is Dictionary
		and data.get("type", "") == SHIP_DRAG
		and data.get("fleet_id", -1) == fleet_id
		and data.get("ship_ids", []).size() < _data.get("ships", []).size()
	)


func _drop_on_split(_at: Vector2, data: Variant) -> void:
	split_requested.emit(data["ship_ids"])


func _ship_name(ship_id: int) -> String:
	for ship: Dictionary in _data.get("ships", []):
		if ship["id"] == ship_id:
			return ship.get("name", "")
	return ""


func _update_buttons() -> void:
	var ships: Array = _data.get("ships", [])
	# Splitting needs some ships selected, but not all of them.
	_split.disabled = _selected.is_empty() or _selected.size() >= ships.size()
	# Scrap toggles: when all selected ships are being scrapped, it cancels.
	var scrapping := not _selected.is_empty()
	for ship: Dictionary in ships:
		if _selected.has(ship["id"]) and not ship.get("scrapping", false):
			scrapping = false
	# Ships are scrapped at a system; in transit only a cancel makes sense.
	var in_transit: bool = not _data.get("in_system", true)
	_scrap.disabled = _selected.is_empty() or (in_transit and not scrapping)
	_scrap.tooltip_text = tr("FLEET_SCRAP_NEEDS_SYSTEM") if in_transit and not scrapping else ""
	_scrap.text = tr("ORDER_CANCEL_SHIP_SCRAP" if scrapping else "ORDER_SHIP_SCRAP")
	_scrap.theme_type_variation = "GhostButton" if scrapping else "DangerButton"


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


## The fleet's totals from its \a ships' stats, as the GG fleet window
## sums them: counts and capacities added up, shields averaged, fuel and
## speed the lowest.
static func fleet_totals(ships: Array) -> Dictionary:
	var totals := {"count": ships.size()}
	var with_stats := ships.filter(func(s): return not s.get("stats", {}).is_empty())
	if with_stats.is_empty():
		return totals
	for key in ["damage", "destroy", "fighters", "fighters_max", "troops", "colony"]:
		totals[key] = 0.0
	for key in ["structure", "max_structure", "shield"]:
		totals[key] = 0.0
	totals["fuel"] = INF
	totals["speed"] = INF
	for ship: Dictionary in with_stats:
		var stats: Dictionary = ship["stats"]
		for key in ["damage", "destroy", "fighters", "fighters_max", "troops", "colony"]:
			totals[key] += stats.get(key, 0.0)
		for key in ["structure", "max_structure", "shield"]:
			totals[key] += stats.get(key, 0.0)
		totals["fuel"] = minf(totals["fuel"], stats.get("fuel", 0.0))
		totals["speed"] = minf(totals["speed"], stats.get("speed", 0.0))
	totals["shield"] /= with_stats.size()
	return totals


## Ships of the fleet for each menu split: {damaged, unfueled, fighters,
## designs: [ship ids per design]}, as the GG fleet window picks them.
static func split_groups(ships: Array) -> Dictionary:
	var groups := {"damaged": [], "unfueled": [], "fighters": [], "designs": {}}
	for ship: Dictionary in ships:
		var stats: Dictionary = ship.get("stats", {})
		var id: int = ship["id"]
		if stats.get("structure", 0.0) < stats.get("max_structure", 0.0):
			groups["damaged"].push_back(id)
		if not stats.is_empty() and stats.get("fuel", 0.0) < 1.0:
			groups["unfueled"].push_back(id)
		if stats.get("fighters_max", 0.0) > 0.0 and stats["fighters"] < stats["fighters_max"]:
			groups["fighters"].push_back(id)
		var design: int = stats.get("design_id", -1)
		if not groups["designs"].has(design):
			groups["designs"][design] = []
		groups["designs"][design].push_back(id)
	return groups


## Where fleet \a data (from_universe()) is going, as GG's fleet status:
## the destination with the turns there and to the next system on the way
## (or never, unknown, out of range); exploring fleets waiting say for what.
static func route_text(data: Dictionary) -> String:
	var destination: String = data.get("destination", "")
	var exploring: bool = data.get("exploring", false)
	if destination.is_empty():
		if not exploring:
			return TranslationServer.translate("FLEET_PANEL_STATIONARY")
		var fueled: bool = data.get("ships", []).all(
			func(s):
				return (
					s.get("stats", {}).get("fuel", 0.0) >= s.get("stats", {}).get("max_fuel", 0.0)
				)
		)
		return TranslationServer.translate(
			"FW_FLEET_EXPLORING_WAITING" if fueled else "FW_FLEET_EXPLORING_REFUEL"
		)
	var etas: Dictionary = data.get("etas", {})
	var text := TranslationServer.translate("SYSTEM_PANEL_FLEET_DESTINATION").replace(
		"%1%", destination
	)
	text += "  ·  " + eta_word(etas.get("final", data.get("eta", 0)))
	var next: int = etas.get("next", 0)
	if next != 0 and next != etas.get("final", 0):
		text += (
			"  ·  "
			+ TranslationServer.translate("FLEET_PANEL_NEXT_SYSTEM").replace("%1%", eta_word(next))
		)
	if exploring:
		text += "  ·  " + TranslationServer.translate("FLEET_PANEL_EXPLORING")
	return text


## An ETA from FOFleet.get_etas(): turns, or never (-1), unknown (-2), out
## of range (-3).
static func eta_word(eta: int) -> String:
	match eta:
		-1:
			return TranslationServer.translate("FW_FLEET_ETA_NEVER")
		-2:
			return TranslationServer.translate("FW_FLEET_ETA_UNKNOWN")
		-3:
			return TranslationServer.translate("FW_FLEET_ETA_OUT_OF_RANGE")
	return GameShell.eta_text(eta)


## GG's blockade tooltip for \a blockade (FOFleet.get_blockade()).
static func blockade_text(blockade: Dictionary) -> String:
	if blockade.get("monster", false):
		return TranslationServer.translate("FB_TOOLTIP_BLOCKADE_MONSTER")
	var exits: PackedStringArray = blockade.get("exits", PackedStringArray())
	if exits.is_empty():
		return TranslationServer.translate("FB_TOOLTIP_BLOCKADE_NO_EXIT")
	return TranslationServer.translate("FB_TOOLTIP_BLOCKADE_WITH_EXIT") + "\n" + "\n".join(exits)


## Menu entries that apply to the fleet shown: MENU ids.
func menu_actions() -> Array:
	var actions := []
	var ships: Array = _data.get("ships", [])
	if not is_own():
		if _data.get("ghost", false):
			actions.push_back(10)
		return actions
	var in_system: bool = _data.get("in_system", true)
	if _data.get("exploring", false):
		actions.push_back(12)
	elif in_system:
		actions.push_back(11)
	if not _data.get("merge_targets", []).is_empty():
		actions.push_back(0)
	if in_system and ships.size() > 1:
		var groups := split_groups(ships)
		for entry in [[1, "damaged"], [2, "unfueled"], [3, "fighters"]]:
			var count: int = groups[entry[1]].size()
			if count > 0 and count < ships.size():
				actions.push_back(entry[0])
		actions.push_back(4)
		if groups["designs"].size() > 1:
			actions.push_back(5)
	if in_system and ships.any(func(s): return not s.get("scrapping", false)):
		actions.push_back(6)
	if ships.any(func(s): return s.get("scrapping", false)):
		actions.push_back(7)
	if give_targets_provider.call(fleet_id).get("giving_to", -1) >= 0:
		actions.push_back(9)
	return actions


## Do menu entry \a id (a MENU id) for the fleet shown.
func run_menu_action(id: int) -> void:
	var ships: Array = _data.get("ships", [])
	var groups := split_groups(ships)
	match id:
		0:
			merge_all_requested.emit(fleet_id)
		1, 2, 3:
			var key: String = ["damaged", "unfueled", "fighters"][id - 1]
			split_groups_requested.emit([PackedInt32Array(groups[key])])
		4:
			# One new fleet per ship; the first stays in this one.
			var each := []
			for ship: Dictionary in ships.slice(1):
				each.push_back(PackedInt32Array([ship["id"]]))
			split_groups_requested.emit(each)
		5:
			# A fleet per design; the first design stays.
			var per_design := []
			for design in groups["designs"].keys().slice(1):
				per_design.push_back(PackedInt32Array(groups["designs"][design]))
			split_groups_requested.emit(per_design)
		11, 12:
			explore_requested.emit(fleet_id, id == 11)
		9:
			give_requested.emit(fleet_id, -1)
		10:
			forget_requested.emit(fleet_id)
		6, 7:
			var scrapping := id == 7
			var ids := PackedInt32Array()
			for ship: Dictionary in ships:
				if ship.get("scrapping", false) == scrapping:
					ids.push_back(ship["id"])
			scrap_requested.emit(ids)


func _fill_menu() -> void:
	var popup := _menu.get_popup()
	popup.clear(true)
	var actions := menu_actions()
	for entry in MENU:
		if entry[0] in actions:
			popup.add_item(tr(entry[1]), entry[0])
	# Ships of one design can be split off (GG's "this design" entry).
	if 5 in actions:
		var designs: Dictionary = split_groups(_data.get("ships", []))["designs"]
		for design: int in designs:
			popup.add_item(
				"%s: %s" % [tr("FW_SPLIT_SHIPS_THIS_DESIGN"), _design_name(design)],
				DESIGN_MENU_BASE + design
			)
	# Gifts to empires at peace with something here.
	if is_own():
		var give := tr("ORDER_GIVE_FLEET_TO_EMPIRE").trim_suffix("...").trim_suffix("…")
		for target: Dictionary in give_targets_provider.call(fleet_id).get("targets", []):
			popup.add_item("%s %s" % [give, target["name"]], GIVE_MENU_BASE + target["id"])
	if not is_own():
		return
	if popup.item_count > 0:
		popup.add_separator()
	var stances := PopupMenu.new()
	stances.name = "Stances"
	for i in NEW_FLEET_STANCES.size():
		var stance: String = NEW_FLEET_STANCES[i]
		stances.add_radio_check_item(
			tr("FW_AUTO") if stance == "auto" else tr("FW_" + stance.to_upper()),
			STANCE_MENU_BASE + i
		)
		stances.set_item_checked(i, stance == new_fleet_stance)
	stances.id_pressed.connect(_on_menu_id)
	popup.add_submenu_node_item(tr("FLEET_PANEL_NEW_FLEET_STANCE"), stances)


func _on_menu_id(id: int) -> void:
	if id >= DESIGN_MENU_BASE:
		var designs: Dictionary = split_groups(_data.get("ships", []))["designs"]
		var ids: Array = designs.get(id - DESIGN_MENU_BASE, [])
		if not ids.is_empty():
			split_groups_requested.emit([PackedInt32Array(ids)])
	elif id >= GIVE_MENU_BASE:
		give_requested.emit(fleet_id, id - GIVE_MENU_BASE)
	elif id >= STANCE_MENU_BASE:
		new_fleet_stance = NEW_FLEET_STANCES[id - STANCE_MENU_BASE]
		new_fleet_stance_changed.emit(new_fleet_stance)
	else:
		run_menu_action(id)


# The name of design \a design_id among the shown fleet's ships.
func _design_name(design_id: int) -> String:
	for ship: Dictionary in _data.get("ships", []):
		if ship.get("stats", {}).get("design_id", -1) == design_id:
			return ship.get("design", "")
	return ""


func _fill_totals(totals: Dictionary) -> void:
	ScreenKit.clear(_totals)
	for entry in TOTALS:
		var value := _stat_text(entry[0], totals)
		if value.is_empty():
			continue
		var chip := _stat_chip(entry[0], value)
		chip.tooltip_text = tr(entry[2])
		_totals.add_child(chip)


# The value of stat \a key in \a stats as shown, or "" if not worth showing.
static func _stat_text(key: String, stats: Dictionary) -> String:
	if not stats.has(key):
		return ""
	var value: float = stats[key]
	match key:
		"count":
			return str(int(value))
		"fighters":
			var most: float = stats.get("fighters_max", 0.0)
			return "%d/%d" % [value, most] if most > 0.0 else ""
		"structure":
			return "%.0f/%.0f" % [value, stats.get("max_structure", value)]
		"fuel":
			return "%.1f" % value if is_finite(value) else ""
		"speed":
			return "%.0f" % value if is_finite(value) else ""
		"shield":
			return "%.1f" % value if value > 0.0 else ""
	return LineChart.short_number(value) if value > 0.0 else ""


func _stat_chip(key: String, value: String) -> Control:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", FOUi.tokens.space_1)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var icon_path := ""
	for entry in TOTALS:
		if entry[0] == key:
			icon_path = entry[1]
			chip.tooltip_text = tr(entry[2])
	chip.add_child(ScreenKit.icon(icon_path, FOUi.tokens.icon_small))
	chip.add_child(ScreenKit.label(value, "SmallLabel"))
	return chip
