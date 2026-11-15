class_name ChatPanel
extends VBoxContainer
## Multiplayer chat: the messages so far (each sender in their empire's
## colour) over a line to type in. Enter sends; Up and Down go through what
## was sent before, Tab completes the word typed from `completions` (as
## GG's messages window). The owner passes the lines and does the sending
## (LobbyScreen, GameShell's chat window).

signal message_sent(text: String)

var log_view: RichTextLabel
var input: LineEdit
## Whether lines start with the time they were sent.
var show_time := true
## Words Tab completes (player names, commands): () -> PackedStringArray.
var completions := Callable()
## What was sent, oldest first.
var history := PackedStringArray()

var _history_at := -1


func _init() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_theme_constant_override("separation", FOUi.tokens.space_2 if FOUi.tokens else 8)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	log_view.selection_enabled = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.custom_minimum_size = Vector2(240, 120)
	add_child(log_view)
	input = LineEdit.new()
	input.placeholder_text = tr("CHAT_PLACEHOLDER")
	input.max_length = 1000
	input.text_submitted.connect(_on_submitted)
	input.gui_input.connect(_on_input_key)
	add_child(input)


## Show \a lines ([{player_name, text, color, time}], oldest first).
func set_lines(lines: Array) -> void:
	log_view.clear()
	# Nothing yet: say so rather than leave an empty box.
	if lines.is_empty():
		log_view.append_text(
			"[color=#%s]%s[/color]" % [_secondary_hex(), escape(tr("CHAT_NO_MESSAGES"))]
		)
		return
	for i in lines.size():
		if i > 0:
			log_view.newline()
		var line: Dictionary = lines[i]
		if not show_time:
			line = line.duplicate()
			line.erase("time")
		log_view.append_text(format_line(line))


## One message as BBCode, the text escaped: "12:03 [Name] text"; the
## game's own messages ({text, event}) in FreeOrion markup, in italics.
static func format_line(line: Dictionary) -> String:
	if line.get("event", false):
		return "[i]%s[/i]" % FORichText.to_bbcode(line.get("text", ""))
	var text := ""
	var time: String = line.get("time", "")
	if not time.is_empty():
		# "12:03:45" -> "12:03"
		text += "[color=#%s]%s[/color] " % [_secondary_hex(), escape(time.substr(0, 5))]
	var player_name: String = line.get("player_name", "")
	if not player_name.is_empty():
		var color: Color = line.get("color", Color.WHITE)
		if color.a <= 0.0:
			color = Color.WHITE
		text += "[color=#%s][b]%s[/b][/color] " % [color.to_html(false), escape(player_name)]
	return text + escape(substitute(line.get("text", "")))


## \a text with the server's stringtable references filled in, as the GG
## client does: "[[PLAYER_LEFT_GAME,Bob]]" -> "Bob left game".
static func substitute(text: String) -> String:
	var pattern := RegEx.create_from_string("\\[\\[(\\w+)((?:,[^,\\]]*)*)\\]\\]")
	var result := ""
	var from := 0
	for found in pattern.search_all(text):
		result += text.substr(from, found.get_start() - from)
		var key := found.get_string(1)
		var entry := TranslationServer.translate(key)
		if entry.begins_with("ERROR: "):
			entry = key
		var args := PackedStringArray()
		if not found.get_string(2).is_empty():
			args = found.get_string(2).trim_prefix(",").split(",")
		for i in args.size():
			entry = entry.replace("%%%d%%" % (i + 1), args[i])
		result += entry
		from = found.get_end()
	return result + text.substr(from)


## \a text with BBCode brackets made literal.
static func escape(text: String) -> String:
	return text.replace("[", "[lb]")


static func _secondary_hex() -> String:
	return (FOUi.tokens.text_secondary if FOUi.tokens else Color(0.7, 0.7, 0.7)).to_html(false)


func _on_submitted(text: String) -> void:
	var message := text.strip_edges()
	if message.is_empty():
		return
	input.clear()
	if history.is_empty() or history[history.size() - 1] != message:
		history.push_back(message)
	_history_at = -1
	message_sent.emit(message)


## Go \a step (-1 older, 1 newer) through what was sent; past the newest
## the line is empty again.
func recall(step: int) -> void:
	if history.is_empty():
		return
	var at := history.size() if _history_at < 0 else _history_at
	at = clampi(at + step, 0, history.size())
	_history_at = -1 if at == history.size() else at
	input.text = "" if _history_at < 0 else history[_history_at]
	input.caret_column = input.text.length()


## Complete the word before the caret from \a words: the common start of
## those it begins (all of it if only one does).
static func complete(text: String, caret: int, words: PackedStringArray) -> String:
	var start := caret
	while start > 0 and text[start - 1] != " ":
		start -= 1
	var typed := text.substr(start, caret - start).to_lower()
	if typed.is_empty():
		return text
	var matches := Array(words).filter(func(w: String): return w.to_lower().begins_with(typed))
	if matches.is_empty():
		return text
	var common: String = matches[0]
	for word: String in matches:
		while not word.to_lower().begins_with(common.to_lower()):
			common = common.left(-1)
	if matches.size() == 1:
		common += " "
	return text.left(start) + common + text.substr(caret)


func _on_input_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_UP, KEY_DOWN:
			recall(-1 if key.keycode == KEY_UP else 1)
			input.accept_event()
		KEY_TAB:
			if completions.is_valid():
				var before := input.text.length()
				input.text = complete(input.text, input.caret_column, completions.call())
				input.caret_column += input.text.length() - before
			input.accept_event()
