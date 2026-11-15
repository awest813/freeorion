extends RefCounted
## In-memory stand-in for PediaSource (tests and screenshots).

var articles := {
	"tech/LRN_ALGO_ELEGANCE":
	{
		"kind": "tech",
		"name": "LRN_ALGO_ELEGANCE",
		"title": "LRN_ALGO_ELEGANCE",
		"icon": "icons/tech/algorithmic_elegance.png",
		"text":
		(
			"Mathematical <i>elegance</i> speeds up research. Used at "
			+ "<planet 12>Hegira β I</planet>; see <tech LRN_PHYS_BRAIN>The Physical Brain</tech>."
		),
		"facts":
		[
			["PEDIA_FACT_CATEGORY", "Learning"],
			["PEDIA_FACT_COST", "18 RP"],
			["PEDIA_FACT_TIME", "3"],
		],
		"links":
		[
			{"kind": "tech", "name": "LRN_PHYS_BRAIN", "group": "unlocks"},
			{"kind": "buildingtype", "name": "BLD_AUTO_HISTORY_ANALYSER", "group": "unlocks"},
		],
	},
	"tech/LRN_PHYS_BRAIN":
	{
		"kind": "tech",
		"name": "LRN_PHYS_BRAIN",
		"title": "LRN_PHYS_BRAIN",
		"icon": "icons/tech/the_physical_brain.png",
		"text": "The brain, physically.",
		"facts": [["PEDIA_FACT_COST", "30 RP"]],
		"links": [{"kind": "tech", "name": "LRN_ALGO_ELEGANCE", "group": "prerequisites"}],
	},
	"species/SP_HUMAN":
	{
		"kind": "species",
		"name": "SP_HUMAN",
		"title": "SP_HUMAN",
		"icon": "icons/species/human.png",
		"text": "Humans.",
		"facts": [],
		"links":
		[
			{"kind": "policy", "name": "PLC_ALGORITHMIC_RESEARCH", "group": "likes"},
			{"kind": "", "name": "SOMETHING_UNLINKED", "group": "dislikes"},
			{"kind": "planet", "name": "2568", "label": "Hegira β I", "group": "homeworlds"},
		],
		"environments":
		[
			{"planet_type": "PT_TERRAN", "environment": "PE_GOOD"},
			{"planet_type": "PT_TUNDRA", "environment": "PE_POOR"},
			{"planet_type": "PT_GASGIANT", "environment": "PE_UNINHABITABLE"},
		],
	},
}
var index: Array = [
	{"kind": "tech", "name": "LRN_ALGO_ELEGANCE", "category": "LEARNING_CATEGORY"},
	{"kind": "tech", "name": "LRN_PHYS_BRAIN", "category": "LEARNING_CATEGORY"},
	{"kind": "buildingtype", "name": "BLD_SHIPYARD_BASE", "category": ""},
]


func get_article(kind: String, article_name: String) -> Dictionary:
	return articles.get("%s/%s" % [kind, article_name], {})


func get_index() -> Array:
	return index
