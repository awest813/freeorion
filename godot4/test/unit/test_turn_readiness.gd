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
