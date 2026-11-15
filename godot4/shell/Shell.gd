extends Control
## Entry point of the fork's redesigned client.
##
## All new UI is reached through this scene, so upstream's root-level scenes
## (IntroScreen, MapWnd, CUI*) can keep merging without edits on our side.
## Global UI setup (UI scale, theme, input map) will move here in Phase 2 of
## doc/UI_OVERHAUL_PLAN.md. Until our own intro screen exists, the shell hands
## off to upstream's IntroScreen.

const FIRST_SCREEN := "res://IntroScreen.tscn"


func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred(FIRST_SCREEN)
