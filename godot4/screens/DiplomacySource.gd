class_name DiplomacySource
extends RefCounted
## Empires and diplomacy via FODiplomacy; tests use a fake.


func get_empires() -> Array:
	return FODiplomacy.get_empires()


func act(empire_id: int, action: String) -> bool:
	return FODiplomacy.act(empire_id, action)
