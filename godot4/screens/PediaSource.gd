class_name PediaSource
extends RefCounted
## Articles and index for PediaScreen via FOPedia; tests use a fake.


func get_article(kind: String, article_name: String) -> Dictionary:
	return FOPedia.get_article(kind, article_name)


func get_index() -> Array:
	return FOPedia.get_index()


func search(text: String) -> Array:
	return FOPedia.search(text)
