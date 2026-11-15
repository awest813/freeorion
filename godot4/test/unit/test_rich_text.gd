extends GutTest
## FreeOrion markup -> BBCode.


func test_simple_formatting():
	assert_eq(FORichText.to_bbcode("<i>very</i> <u>big</u>"), "[i]very[/i] [u]big[/u]")


func test_colour():
	assert_eq(FORichText.to_bbcode("<rgba 0 255 0 255>+3</rgba>"), "[color=#00ff00ff]+3[/color]")


func test_image_from_art_dir():
	var bb := FORichText.to_bbcode('Build <img src = "icons/buttons/production.png"> now', 20)
	assert_eq(bb, "Build [img height=20]res://assets/art/icons/buttons/production.png[/img] now")


func test_object_links():
	assert_eq(
		FORichText.to_bbcode(
			"<planet 42>Mars</planet> researched <tech SHP_ZORTRIUM_PLATE>Zortrium</tech>"
		),
		"[url=fo://planet/42]Mars[/url] researched [url=fo://tech/SHP_ZORTRIUM_PLATE]Zortrium[/url]"
	)
	assert_eq(
		FORichText.to_bbcode("<encyclopedia ENC_SHIP_DESIGN>designs</encyclopedia>"),
		"[url=fo://encyclopedia/ENC_SHIP_DESIGN]designs[/url]"
	)


func test_web_link():
	assert_eq(
		FORichText.to_bbcode("<url  http://freeorion.org/guide>guide</url>"),
		"[url=http://freeorion.org/guide]guide[/url]"
	)


func test_parse_link():
	assert_eq(FORichText.parse_link("fo://planet/42"), {"kind": "planet", "arg": "42"})
	assert_eq(FORichText.parse_link("fo://tech/SHP_A%20B"), {"kind": "tech", "arg": "SHP_A B"})
	assert_eq(FORichText.parse_link("http://x.org"), {"kind": "url", "arg": "http://x.org"})


func test_brackets_are_escaped():
	assert_eq(FORichText.to_bbcode("[b]not bold[/b]"), "[lb]b]not bold[lb]/b]")


func test_unknown_tags_keep_text():
	assert_eq(FORichText.to_bbcode("<value FOO>12</value> left"), "12 left")


func test_unbalanced_markup_is_closed():
	assert_eq(FORichText.to_bbcode("<i>open <u>both"), "[i]open [u]both[/u][/i]")
	assert_eq(FORichText.to_bbcode("stray</i> close"), "stray close")
	assert_eq(FORichText.to_bbcode("<i>a <u>b</i> c"), "[i]a [u]b[/u][/i] c", "Inner closed first")


func test_real_stringtable_entries_parse_cleanly():
	# Every converted entry must render without leftover FreeOrion tags.
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	add_child_autofree(label)
	for sample in [
		"<i>Increases</i> industry by <rgba 0 255 0 255>+%1%</rgba>.",
		'<img src = "icons/meter/pop.png"> %1% at <planet %2%>%3%</planet>',
	]:
		label.text = FORichText.to_bbcode(sample)
		assert_false(label.get_parsed_text().contains("<"), "No raw tags left: %s" % sample)
