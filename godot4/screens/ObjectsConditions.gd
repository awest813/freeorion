class_name ObjectsConditions
extends VBoxContainer
## The objects list's condition filter, as GG's filter dialog builds
## conditions: rows of [what] [how] [value], all of which a row must meet.
## What is a column of the shown kind or one of its traits (homeworld,
## capital, armed, can colonise); numbers compare (at least, at most,
## equal), texts match (is, contains), traits are true or not.

signal changed

## Traits per kind: row key, label key.
const TRAITS := {
	"planets": [["homeworld", "OBJECTS_TRAIT_HOMEWORLD"], ["capital", "OBJECTS_TRAIT_CAPITAL"]],
	"fleets": [["armed", "OBJECTS_TRAIT_ARMED"], ["can_colonize", "OBJECTS_TRAIT_COLONIZE"]],
	"ships": [["armed", "OBJECTS_TRAIT_ARMED"], ["can_colonize", "OBJECTS_TRAIT_COLONIZE"]],
}
## Operators per value type: id, label key.
const OPERATORS := {
	"number":
	[[">=", "OBJECTS_OP_AT_LEAST"], ["<=", "OBJECTS_OP_AT_MOST"], ["==", "OBJECTS_OP_EQUAL"]],
	"text":
	[["is", "OBJECTS_OP_IS"], ["contains", "OBJECTS_OP_CONTAINS"], ["not", "OBJECTS_OP_NOT"]],
	"trait": [["true", "OBJECTS_OP_TRUE"], ["false", "OBJECTS_OP_FALSE"]],
}

## [{key, type ("number", "text", "trait"), op, value}]
var conditions: Array = []
## What can be tested: [[key, label, type]] for the shown kind.
var fields: Array = []

var _rows: VBoxContainer


func _init() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_rows = VBoxContainer.new()
	add_child(_rows)
	var add := Button.new()
	add.text = "+ " + tr("OBJECTS_ADD_CONDITION")
	add.theme_type_variation = "GhostButton"
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add.pressed.connect(add_condition)
	add_child(add)


## The fields of \a kind: its \a columns ([key, title key, format]) and
## traits.
func set_kind(kind: String, columns: Array) -> void:
	fields = []
	for column: Array in columns:
		var number: bool = column[2] in ["number", "int", "eta"]
		fields.push_back([column[0], tr(column[1]), "number" if number else "text"])
	for entry: Array in TRAITS.get(kind, []):
		fields.push_back([entry[0], tr(entry[1]), "trait"])
	conditions = []
	_rebuild()
	changed.emit()


## A new condition on the first field.
func add_condition() -> void:
	if fields.is_empty():
		return
	var field: Array = fields[0]
	conditions.push_back(
		{"key": field[0], "type": field[2], "op": OPERATORS[field[2]][0][0], "value": ""}
	)
	_rebuild()
	changed.emit()


## Whether \a row meets every condition; \a display gives a text column's
## shown text (row, key) -> String.
static func passes(row: Dictionary, conditions_list: Array, display: Callable) -> bool:
	for condition: Dictionary in conditions_list:
		var key: String = condition["key"]
		var value: String = str(condition.get("value", "")).strip_edges()
		match condition["type"]:
			"trait":
				if bool(row.get(key, false)) != (condition["op"] == "true"):
					return false
			"number":
				if value.is_empty() or not value.is_valid_float():
					continue
				var have := float(row.get(key, 0.0))
				var want := value.to_float()
				var ok: bool = (
					have >= want
					if condition["op"] == ">="
					else have <= want if condition["op"] == "<=" else is_equal_approx(have, want)
				)
				if not ok:
					return false
			_:
				if value.is_empty():
					continue
				var text: String = display.call(row, key).to_lower()
				var needle := value.to_lower()
				var ok: bool = (
					text == needle
					if condition["op"] == "is"
					else text.contains(needle) if condition["op"] == "contains" else text != needle
				)
				if not ok:
					return false
	return true


func _rebuild() -> void:
	ScreenKit.clear(_rows)
	for i in conditions.size():
		_rows.add_child(_condition_row(i))


func _condition_row(index: int) -> HBoxContainer:
	var condition: Dictionary = conditions[index]
	var row := HBoxContainer.new()
	var field := OptionButton.new()
	for i in fields.size():
		field.add_item(fields[i][1])
		if fields[i][0] == condition["key"]:
			field.select(i)
	field.item_selected.connect(
		func(i: int):
			condition["key"] = fields[i][0]
			condition["type"] = fields[i][2]
			condition["op"] = OPERATORS[fields[i][2]][0][0]
			condition["value"] = ""
			_rebuild()
			changed.emit()
	)
	row.add_child(field)
	var op := OptionButton.new()
	var ops: Array = OPERATORS[condition["type"]]
	for i in ops.size():
		op.add_item(tr(ops[i][1]))
		if ops[i][0] == condition["op"]:
			op.select(i)
	op.item_selected.connect(
		func(i: int):
			condition["op"] = ops[i][0]
			changed.emit()
	)
	row.add_child(op)
	if condition["type"] != "trait":
		var value := LineEdit.new()
		value.text = condition["value"]
		value.custom_minimum_size.x = 140
		value.text_changed.connect(
			func(text: String):
				condition["value"] = text
				changed.emit()
		)
		row.add_child(value)
	var remove := ScreenKit.small_button("✕", "OBJECTS_REMOVE_CONDITION")
	remove.pressed.connect(
		func():
			conditions.remove_at(index)
			_rebuild()
			changed.emit()
	)
	row.add_child(remove)
	return row
