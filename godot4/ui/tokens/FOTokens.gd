class_name FOTokens
extends Resource
## Design tokens: the single source of colours, spacing, radii, type sizes,
## icon sizes and motion durations for the redesigned UI.
##
## Scenes and components must take these values through the Theme built by
## FOThemeBuilder (or from FOUi.tokens), never as literals.

@export_group("Surfaces")
@export var surface := Color("#11151b")
@export var surface_raised := Color("#1a2029")
@export var surface_overlay := Color("#242c37")
@export var border := Color("#364150")
@export var border_strong := Color("#56657a")

@export_group("Text")
@export var text_primary := Color("#e9edf2")
@export var text_secondary := Color("#aab4c1")
@export var text_disabled := Color("#7d8794")
@export var text_on_accent := Color("#06121f")

@export_group("Accent and status")
@export var accent := Color("#58a8ff")
@export var accent_hover := Color("#7cbcff")
@export var accent_pressed := Color("#3b8de6")
@export var positive := Color("#4cc38a")
@export var negative := Color("#f07171")
@export var warning := Color("#f2b84b")
@export var info := Color("#5bb4f0")
@export var focus_ring := Color("#9fd0ff")

@export_group("Spacing (px at 100% scale)")
@export var space_1 := 4
@export var space_2 := 8
@export var space_3 := 12
@export var space_4 := 16
@export var space_6 := 24
@export var space_8 := 32

@export_group("Shape")
@export var radius_small := 3
@export var radius := 6
@export var border_width := 1
@export var focus_width := 2

@export_group("Type sizes")
@export var font_size_small := 13
@export var font_size_body := 16
@export var font_size_title := 20
@export var font_size_heading := 26

@export_group("Icon sizes")
@export var icon_small := 16
@export var icon := 24
@export var icon_large := 48

@export_group("Motion (seconds)")
@export var motion_fast := 0.12
@export var motion := 0.2
