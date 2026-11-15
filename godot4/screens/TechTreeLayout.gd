class_name TechTreeLayout
extends RefCounted
## Places techs on a grid for the tech tree: each tech's column is the
## length of its longest chain of prerequisites (among the techs laid out),
## and techs within a column are ordered to keep arcs short and few
## crossing, by repeated barycentre sweeps as layered graph layouts do.

## Sweeps back and forth to settle the order within columns.
const SWEEPS := 6


## {cells: name -> Vector2i(column, row), columns, rows, arcs: [[from, to]]}
## for \a techs ({name, category, prerequisites}). Prerequisites outside
## \a techs are left out, with their arcs.
static func layout(techs: Array) -> Dictionary:
	var by_name := {}
	for tech: Dictionary in techs:
		by_name[tech["name"]] = tech
	var prereqs := {}
	var dependents := {}
	var arcs := []
	for tech: Dictionary in techs:
		var name: String = tech["name"]
		var own: Array = []
		for prereq in tech.get("prerequisites", []):
			if by_name.has(prereq):
				own.push_back(prereq)
				arcs.push_back([prereq, name])
				if not dependents.has(prereq):
					dependents[prereq] = []
				dependents[prereq].push_back(name)
		prereqs[name] = own

	# Columns by depth.
	var depth := {}
	for tech: Dictionary in techs:
		_depth(tech["name"], prereqs, depth, {})
	var columns: Array = []
	for name in depth:
		var column: int = depth[name]
		while columns.size() <= column:
			columns.push_back([])
		columns[column].push_back(name)

	# Start with related techs together: by category, then name.
	for column: Array in columns:
		column.sort_custom(
			func(a, b):
				var ca: String = by_name[a].get("category", "")
				var cb: String = by_name[b].get("category", "")
				return ca < cb if ca != cb else a < b
		)
	var row := _rows(columns)
	for sweep in SWEEPS:
		if sweep % 2 == 0:
			for i in range(1, columns.size()):
				_order_by(columns[i], prereqs, row)
				_number(columns[i], row)
		else:
			for i in range(columns.size() - 2, -1, -1):
				_order_by(columns[i], dependents, row)
				_number(columns[i], row)

	var cells := {}
	var rows := 0
	for c in columns.size():
		for r in columns[c].size():
			cells[columns[c][r]] = Vector2i(c, r)
		rows = maxi(rows, columns[c].size())
	return {"cells": cells, "columns": columns.size(), "rows": rows, "arcs": arcs}


static func _depth(
	name: String, prereqs: Dictionary, depth: Dictionary, visiting: Dictionary
) -> int:
	if depth.has(name):
		return depth[name]
	if visiting.has(name):
		return 0  # a cycle in content; don't recurse forever
	visiting[name] = true
	var result := 0
	for prereq in prereqs.get(name, []):
		result = maxi(result, _depth(prereq, prereqs, depth, visiting) + 1)
	depth[name] = result
	return result


static func _rows(columns: Array) -> Dictionary:
	var row := {}
	for column: Array in columns:
		_number(column, row)
	return row


static func _number(column: Array, row: Dictionary) -> void:
	for i in column.size():
		row[column[i]] = i


# Sort \a column by the mean row of each tech's neighbours in \a links;
# techs without any keep their place.
static func _order_by(column: Array, links: Dictionary, row: Dictionary) -> void:
	var keys := {}
	for name in column:
		var neighbours: Array = links.get(name, []).filter(func(n): return row.has(n))
		if neighbours.is_empty():
			keys[name] = float(row[name])
		else:
			var total := 0.0
			for n in neighbours:
				total += row[n]
			keys[name] = total / neighbours.size()
	column.sort_custom(
		func(a, b): return keys[a] < keys[b] if keys[a] != keys[b] else row[a] < row[b]
	)
