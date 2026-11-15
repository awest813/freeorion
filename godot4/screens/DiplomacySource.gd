class_name DiplomacySource
extends RefCounted
## Empires and diplomacy via FODiplomacy; tests use a fake.


func get_empires() -> Array:
	return FODiplomacy.get_empires()


func act(empire_id: int, action: String) -> bool:
	return FODiplomacy.act(empire_id, action)


## FOUniverse.get_stat_records(): stat name -> one line per empire.
func get_stat_records() -> Dictionary:
	return FOUniverse.get_stat_records()


func get_own_empire_id() -> int:
	return FOUniverse.get_empire_id()
