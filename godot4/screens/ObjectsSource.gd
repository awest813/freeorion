class_name ObjectsSource
extends RefCounted
## Object rows via FOObjects; tests use a fake.


func list_objects(kind: String, own_only: bool) -> Array:
	return FOObjects.list_objects(kind, own_only)
