extends "res://test/visual/visual_base.gd"
## Golden screenshots of the multiplayer screens (connect, lobby); see
## visual_base.gd for how to run and update them.

const FAKE_LOBBY := preload("res://test/unit/fake_lobby_source.gd")


func test_lobby_screen():
	var screen := LobbyScreen.new()
	screen.source = FAKE_LOBBY.new()
	await _check_scene(
		screen,
		"lobby_screen",
		func(s):
			s.refresh()
			s.refresh_chat()
	)


func test_connect_screen():
	var screen := ConnectScreen.new()
	var fake: RefCounted = FAKE_OPTIONS.new()
	fake.options["setup.multiplayer.player.name"] = {"value": "Admiral", "default": ""}
	fake.options["setup.multiplayer.host.address"] = {"value": "localhost", "default": ""}
	screen.options = fake
	screen.lobby_source = FAKE_LOBBY.new()
	await _check_scene(
		screen,
		"connect_screen",
		func(s):
			s.refresh()
			s.find_lan_servers()
	)
