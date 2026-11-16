class_name GameOver
extends RefCounted
## The end of the game for the player's empire: its flag, VICTORY or DEFEAT
## in the display face (in the good or bad colour), a line, what the empire
## came to, and the way on (keep playing or watching, or quit to the title).

## Flag size in UI units.
const FLAG_SIZE := 96


## Open over \a parent for \a outcome ("won" or "eliminated") of the empire
## \a empire (name, colour) on turn \a turn with \a stats ({planets, ships,
## population}); \a quit leaves the game.
static func open(
	parent: Node, outcome: String, empire: Dictionary, turn: int, stats: Dictionary, quit: Callable
) -> FODialog:
	var t := func(key: String) -> String: return TranslationServer.translate(key)
	var won := outcome == "won"
	var dialog := (
		FODialog
		. open_on(
			parent,
			t.call("GAME_OVER_VICTORY_TITLE" if won else "GAME_OVER_DEFEAT_TITLE"),
			t.call("GAME_OVER_VICTORY" if won else "GAME_OVER_DEFEAT"),
			[
				[t.call("MENU_QUIT_TO_TITLE"), "GhostButton", quit],
				[
					t.call("GAME_OVER_KEEP_PLAYING" if won else "GAME_OVER_KEEP_WATCHING"),
					"PrimaryButton" if won else "GhostButton"
				],
			]
		)
	)
	dialog.set_meta("outcome", outcome)
	# The plain title gives way to the hero: flag, outcome, empire.
	var title: Label = dialog._title
	title.visible = false
	var hero := VBoxContainer.new()
	hero.alignment = BoxContainer.ALIGNMENT_CENTER
	hero.add_theme_constant_override("separation", FOUi.tokens.space_2)
	var flag := TextureRect.new()
	flag.texture = EmpireArt.flag(
		empire.get("name", ""), empire.get("color", Color.WHITE), FLAG_SIZE
	)
	flag.custom_minimum_size = Vector2(FLAG_SIZE, FLAG_SIZE)
	flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	flag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	flag.visible = flag.texture != null
	hero.add_child(flag)
	var verdict := ScreenKit.label(title.text, "DisplayTitle")
	verdict.uppercase = true
	verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	verdict.add_theme_color_override(
		"font_color", FOUi.tokens.positive if won else FOUi.tokens.negative
	)
	hero.add_child(verdict)
	var name := ScreenKit.label(empire.get("name", ""), "TitleLabel")
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero.add_child(name)
	title.get_parent().add_child(hero)
	title.get_parent().move_child(hero, 0)
	var line := ScreenKit.label(summary(turn, stats), "SecondaryLabel")
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog.add_content(line)
	return dialog


## What the empire came to: "Turn 120 · 14 planets · 52 ships · population
## 230.5".
static func summary(turn: int, stats: Dictionary) -> String:
	return (
		TranslationServer
		. translate("GAME_OVER_SUMMARY")
		. replace("%1%", str(turn))
		. replace("%2%", str(stats.get("planets", 0)))
		. replace("%3%", str(stats.get("ships", 0)))
		. replace("%4%", "%.1f" % stats.get("population", 0.0))
	)
