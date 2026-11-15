class_name GovernmentSource
extends RefCounted
## Slots, policies and adoption orders for GovernmentScreen via FOGovernment;
## tests use a fake with the same methods.


func get_slots() -> Array:
	return FOGovernment.get_slots()


func get_policies() -> Array:
	return FOGovernment.get_policies()


func get_influence() -> Dictionary:
	return FOGovernment.get_influence()


func adopt(policy_name: String, slot: int) -> bool:
	return FOGovernment.adopt(policy_name, slot)


func de_adopt(policy_name: String) -> bool:
	return FOGovernment.de_adopt(policy_name)
