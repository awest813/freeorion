class_name CombatSource
extends RefCounted
## Combat reports via FOCombat; tests use a fake.


func list_combats() -> Array:
	return FOCombat.list_combats()


func get_combat(log_id: int) -> Dictionary:
	return FOCombat.get_combat(log_id)


func get_pending_count() -> int:
	return FOCombat.get_pending_count()
