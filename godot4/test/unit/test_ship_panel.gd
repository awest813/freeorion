extends GutTest
## ShipPanel with fixed data.

const SAMPLE := {
	"id": 71,
	"name": "Pronghorn",
	"species": "SP_HUMAN",
	"owner_name": "Terran Imperium",
	"owner_color": Color("#1193ff"),
	"own": true,
	"design": "Frigate Ms",
	"design_id": 7,
	"hull": "SH_BASIC_MEDIUM",
	"icon": "icons/ship_hulls/basic-medium-hull_small.png",
	"scrapping": false,
	"stats": [{"stat": "damage", "value": 18.0}, {"stat": "destroy", "value": 3.0}],
	"meters":
	[
		{
			"meter": "METER_STRUCTURE",
			"now": 24.0,
			"next": 28.0,
			"target": 40.0,
			"accounting_meter": "METER_MAX_STRUCTURE"
		},
		{"meter": "METER_SPEED", "now": 75.0, "next": 75.0, "accounting_meter": "METER_SPEED"},
		{"meter": "METER_INDUSTRY", "now": 0.0, "next": 0.0, "target": 0.0},
	],
	"parts":
	[
		{
			"name": "SR_WEAPON_1_1",
			"count": 3,
			"class": "PC_DIRECT_WEAPON",
			"capacity": 6.0,
			"max_capacity": 6.0,
		},
		{
			"name": "FU_BASIC_TANK",
			"count": 1,
			"class": "PC_FUEL",
			"capacity": 1.5,
			"max_capacity": 3.0
		},
		{"name": "AR_STD_PLATE", "count": 1, "class": "PC_ARMOUR", "capacity": -1.0},
	],
}

var panel: ShipPanel


func before_each():
	panel = ShipPanel.new()
	add_child_autofree(panel)
	panel.show_data(SAMPLE)


func _texts(node: Node) -> String:
	var parts: PackedStringArray = []
	for child in node.find_children("*", "", true, false):
		if child is Label or child is Button:
			parts.push_back(child.text)
		elif child is RichTextLabel:
			parts.push_back(child.get_parsed_text())
	return "\n".join(parts)


func test_header():
	assert_true(panel.visible)
	assert_eq(panel._title.text, "Pronghorn")
	assert_eq(
		panel._subtitle.get_parsed_text(),
		"Frigate Ms · %s · %s · Terran Imperium" % [tr("SH_BASIC_MEDIUM"), tr("SP_HUMAN")]
	)
	watch_signals(panel)
	panel._subtitle.meta_clicked.emit("fo://species/SP_HUMAN")
	assert_signal_emitted_with_parameters(panel, "link_activated", ["species", "SP_HUMAN"])


func test_stats_and_meters():
	var stats := _texts(panel._stats)
	assert_string_contains(stats, "18")
	assert_string_contains(stats, "3")
	var meters := _texts(panel._meters)
	assert_string_contains(meters, "24.0 +4.0")
	assert_string_contains(meters, "/ 40.0")
	assert_string_contains(meters, "75.0")
	assert_false(meters.contains("/ 75.0"), "No maximum for speed")
	assert_false(meters.contains(tr("METER_INDUSTRY")), "Zero meters left out")


func test_parts():
	var parts := _texts(panel._parts)
	assert_string_contains(parts, "3 × " + tr("SR_WEAPON_1_1"))
	assert_string_contains(parts, "1.5 / 3")
	assert_eq(ShipPanel.capacity_text(SAMPLE["parts"][0]), "6")
	assert_eq(ShipPanel.capacity_text(SAMPLE["parts"][2]), "", "Armour has no capacity")


func test_meter_breakdown_uses_the_ship():
	var asked := []
	panel.accounting_provider = func(id: int, meter: String) -> Dictionary:
		asked.push_back([id, meter])
		return {"total": 40.0, "lines": [{"label": "Hull", "change": 40.0}]}
	var tooltip := panel._meters.accounting_tooltip("METER_MAX_STRUCTURE")
	assert_eq(asked, [[71, "METER_MAX_STRUCTURE"]])
	assert_not_null(tooltip)
	tooltip.free()


func test_hide():
	panel.show_data({})
	assert_false(panel.visible)
	assert_eq(panel.ship_id, -1)


func test_fleet_panel_names_open_the_ship():
	var fleet := FleetPanel.new()
	add_child_autofree(fleet)
	(
		fleet
		. show_data(
			{
				"id": 5,
				"name": "Battle Fleet",
				"own": true,
				"ships": [{"id": 71, "name": "Pronghorn", "design": "Frigate Ms"}],
			}
		)
	)
	watch_signals(fleet)
	var link: LinkButton = fleet._ships.find_children("*", "LinkButton", true, false)[0]
	assert_eq(link.text, "Pronghorn")
	link.pressed.emit()
	assert_signal_emitted_with_parameters(fleet, "ship_selected", [71])
