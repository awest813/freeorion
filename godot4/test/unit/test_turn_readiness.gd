extends GutTest
## TurnReadiness on plain data, and the warning dialog in GameShell.

const DATA := {
	"resources": {"industry": 15.0, "industry_spent": 12.0, "research": 9.0, "research_spent": 0.0},
	"production_queue": 2,
	"research_queue": 0,
	"fleets":
	[
		{"id": 1, "name": "Colony Fleet", "system_name": "Sol", "system_id": 5, "colony_ships": 1},
		{"id": 2, "name": "New Fleet", "system_name": "Sol", "system_id": 5, "age": 0},
		{"id": 3, "name": "Old Fleet", "system_name": "Sol", "system_id": 5, "age": 4},
		{
			"id": 4,
			"name": "Moving Colony",
			"system_name": "Sol",
			"system_id": -1,
			"colony_ships": 2,
			"moving": true,
		},
		{
			"id": 5,
			"name": "Ordered",
			"system_name": "Sol",
			"system_id": 5,
			"age": 0,
			"destination": "Vega",
		},
	],
}


func test_warnings():
	var issues := TurnReadiness.check(DATA)
	assert_eq(
		issues.map(func(i): return i["text"]),
		[
			tr("READINESS_PP").replace("%1%", "3.0"),
			tr("READINESS_RP_EMPTY").replace("%1%", "9.0"),
			tr("READINESS_COLONY_SHIPS").replace("%1%", "Colony Fleet").replace("%2%", "Sol"),
			tr("READINESS_NEW_FLEET").replace("%1%", "New Fleet").replace("%2%", "Sol"),
		]
	)
	assert_eq(issues[0]["screen"], "production")
	assert_eq(issues[1]["screen"], "research")
	assert_eq(issues[2]["target"]["fleet_id"], 1)
	assert_eq(issues[2]["target"]["system_id"], 5)


func test_idle_scouts_and_free_policy_slots():
	var data := {
		"fleets":
		[
			{"id": 7, "name": "Scout", "system_name": "Sol", "system_id": 5, "armed": false},
			{
				"id": 8,
				"name": "Explorer",
				"system_name": "Sol",
				"system_id": 5,
				"armed": false,
				"exploring": true,
			},
			{"id": 9, "name": "Guard", "system_name": "Sol", "system_id": 5, "armed": true},
		],
		"free_policy_slots": ["ECONOMIC_CATEGORY"],
	}
	var issues := TurnReadiness.check(data)
	assert_eq(
		issues.map(func(i): return i["text"]),
		[
			tr("READINESS_IDLE_SCOUT").replace("%1%", "Scout").replace("%2%", "Sol"),
			tr("READINESS_POLICY_SLOT").replace("%1%", tr("ECONOMIC_CATEGORY")),
		]
	)
	assert_eq(issues[0]["target"]["fleet_id"], 7)
	assert_eq(issues[1]["screen"], "government")
	var slots := [
		{"category": "ECONOMIC_CATEGORY", "policies": [""]},
		{"category": "SOCIAL_CATEGORY", "policies": ["PLC_A"]},
		{"category": "MILITARY_CATEGORY", "policies": [""]},
	]
	var policies := [
		{"name": "PLC_B", "category": "ECONOMIC_CATEGORY", "available": true, "affordable": true},
		{"name": "PLC_C", "category": "SOCIAL_CATEGORY", "available": true, "affordable": true},
		{"name": "PLC_D", "category": "MILITARY_CATEGORY", "available": true, "affordable": false},
	]
	assert_eq(TurnReadiness.free_policy_slots(slots, policies), ["ECONOMIC_CATEGORY"])


func test_nothing_to_say():
	assert_eq(TurnReadiness.check({"resources": {"industry": 5.0, "industry_spent": 5.0}}), [])


func test_end_turn_asks_first():
	var bar := TopBar.new()
	bar.follow_game = false
	add_child_autofree(bar)
	bar.set_state("Empire", Color.WHITE, 3, false)
	var issues := [{"text": "x", "screen": "production"}]
	bar.readiness_provider = func(): return issues
	watch_signals(bar)
	bar._end_turn.pressed.emit()
	assert_signal_emitted_with_parameters(bar, "readiness_issues", [issues])
	assert_false(bar.is_waiting(), "Not ended yet")
	bar.end_turn()
	assert_true(bar.is_waiting())
	bar.set_state("Empire", Color.WHITE, 4, false)
	issues.clear()
	bar._waiting = false
	bar._end_turn.pressed.emit()
	assert_true(bar.is_waiting(), "Nothing to say: ends at once")


func test_dialog_goes_to_the_issue():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(1)
	shell.top_bar.set_state("Empire", Color.WHITE, 3, false)
	var dialog := shell.show_readiness(
		[{"text": "PP", "screen": "production"}, {"text": "RP", "screen": "research"}]
	)
	var links: Array = dialog.find_children("*", "LinkButton", true, false)
	assert_eq(links.map(func(l): return l.text), ["PP", "RP"])
	links[1].pressed.emit()
	assert_eq(shell.active_screen, "research")
	assert_false(shell.top_bar.is_waiting(), "Going there doesn't end the turn")
	dialog = shell.show_readiness([{"text": "PP", "screen": "production"}])
	dialog.choose(0)
	assert_true(shell.top_bar.is_waiting(), "End turn anyway")


func test_issues_ended_anyway_wait_until_resolved():
	var bar := TopBar.new()
	bar.follow_game = false
	add_child_autofree(bar)
	bar.set_state("Empire", Color.WHITE, 3, false)
	var pp := {"text": "PP", "screen": "production", "key": "READINESS_PP"}
	var scout := {"text": "Scout", "screen": "map", "key": "READINESS_IDLE_SCOUT:7"}
	var issues := [pp, scout]
	bar.readiness_provider = func(): return issues
	watch_signals(bar)
	bar._end_turn.pressed.emit()
	assert_signal_emit_count(bar, "readiness_issues", 1)
	bar.end_turn()  # anyway
	bar._waiting = false
	bar._end_turn.pressed.emit()
	assert_true(bar.is_waiting(), "the same issues don't ask again")
	bar._waiting = false
	issues.erase(pp)  # PP resolved
	bar._end_turn.pressed.emit()
	assert_true(bar.is_waiting())
	bar._waiting = false
	issues.push_front(pp)  # PP back: worth saying again
	bar._end_turn.pressed.emit()
	assert_false(bar.is_waiting())
	assert_eq(get_signal_parameters(bar, "readiness_issues", 1)[0], [pp], "only the one back")


func test_unhappy_planets_are_named():
	var planets := [
		{"name": "Hegira I", "population": 12.0, "stability": 3.0, "system_id": 7},
		{"name": "Content", "population": 9.0, "stability": 12.0, "system_id": 8},
		{"name": "Outpost", "population": 0.0, "stability": 0.0, "system_id": 9},
	]
	var issues := TurnReadiness.check({"planets": planets})
	assert_eq(issues.size(), 1, "Outposts have nobody to be unhappy")
	assert_eq(issues[0]["text"], tr("READINESS_UNHAPPY_ONE").replace("%1%", "Hegira I"))
	assert_eq(issues[0]["target"]["system_id"], 7, "Opens its system")
	planets[1]["stability"] = 5.0
	issues = TurnReadiness.check({"planets": planets})
	assert_eq(
		issues[0]["text"],
		tr("READINESS_UNHAPPY_MANY").replace("%1%", "2").replace("%2%", "Hegira I, Content")
	)


func test_influence_running_out_is_warned_of():
	var falling := {"influence": 12.0, "influence_change": -3.0}
	var issues := TurnReadiness.check({"resources": falling})
	assert_eq(issues.size(), 1)
	assert_eq(issues[0]["screen"], "government")
	assert_eq(
		issues[0]["text"], tr("READINESS_INFLUENCE").replace("%1%", "3.0").replace("%2%", "4")
	)
	var slow := {"influence": 120.0, "influence_change": -3.0}
	assert_eq(TurnReadiness.check({"resources": slow}).size(), 0, "40 turns left: no hurry")
	var rising := {"influence": 2.0, "influence_change": 1.5}
	assert_eq(TurnReadiness.check({"resources": rising}).size(), 0)


func test_an_issue_ended_anyway_comes_back_after_a_while():
	var issues := [{"text": "Research queue empty", "key": "READINESS_RP_EMPTY"}]
	var acknowledged := {"READINESS_RP_EMPTY": 10}
	assert_eq(TurnReadiness.unacknowledged(issues, acknowledged, 11).size(), 0, "Not next turn")
	assert_eq(
		TurnReadiness.unacknowledged(issues, acknowledged, 10 + TurnReadiness.REMIND_TURNS).size(),
		1,
		"But a few turns on, still standing, it is raised again"
	)
	assert_false(acknowledged.has("READINESS_RP_EMPTY"))
