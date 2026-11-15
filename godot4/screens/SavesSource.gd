class_name SavesSource
extends RefCounted
## Save listing and save/load requests via FOSaves; tests use a fake.


func list_saves() -> Array:
	return FOSaves.list_saves()


func save_game(save_name: String) -> String:
	return FOSaves.save_game(save_name)


func load_game(path: String) -> bool:
	return FOSaves.load_game(path)


func delete_save(path: String) -> bool:
	return FOSaves.delete_save(path)
