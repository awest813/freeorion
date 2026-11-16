extends GutTest
## Planet spheres, empire flags and species portraits.


func test_planets_get_their_surface_and_keep_it():
	var a := PlanetView.surface_texture("PT_TERRAN", 7)
	assert_not_null(a)
	assert_eq(PlanetView.surface_texture("PT_TERRAN", 7), a, "the same planet, the same look")
	assert_null(PlanetView.surface_texture("PT_ASTEROIDS", 7), "asteroids keep their icon")
	var view := PlanetView.new("PT_OCEAN", 3, 48, "STAR_RED", "SZ_SMALL")
	add_child_autofree(view)
	assert_not_null(view.material)
	var shader := view.material as ShaderMaterial
	assert_eq(shader.get_shader_parameter("radius"), PlanetView.SIZE_RADIUS["SZ_SMALL"])
	assert_eq(shader.get_shader_parameter("light_color"), PlanetView.STAR_LIGHT["STAR_RED"])
	view.show_planet("PT_ASTEROIDS")
	assert_null(view.material, "an icon instead")


func test_each_empire_has_its_own_flag():
	var blue := EmpireArt.flag("Terran Imperium", Color.DODGER_BLUE, 32)
	assert_not_null(blue)
	assert_eq(blue.get_width(), 32)
	assert_eq(EmpireArt.flag("Terran Imperium", Color.DODGER_BLUE, 32), blue, "cached")
	var other := EmpireArt.flag("Congregation", Color.DODGER_BLUE, 32)
	assert_ne(
		other.get_image().get_data(), blue.get_image().get_data(), "another name, another flag"
	)


func test_species_portraits_prefer_the_painting():
	var painted := EmpireArt.species_portrait("SP_ABADDONI")
	assert_not_null(painted)
	assert_gt(painted.get_width(), 64, "the large painting")
	assert_not_null(EmpireArt.species_portrait("SP_HUMAN"), "else the species icon")


func test_galaxy_previews_follow_the_shape():
	var ring := GalaxyPreview.place("RING", 300)
	for p in ring:
		assert_between(p.length(), 0.4, 1.0, "on the ring")
	assert_eq(GalaxyPreview.place("RING", 300), ring, "the same picture each time")
	var preview := GalaxyPreview.new()
	preview.systems = 1000
	assert_eq(preview._points.size(), GalaxyPreview.STARS_MAX)
	preview.free()
