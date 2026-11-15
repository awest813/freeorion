#ifndef _FOObjects_h_
#define _FOObjects_h_

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>

/** Static object list API for GDScript: FOObjects.list_objects("planets").
  *
  * One call returns every row of a kind with its column values, so lists of
  * thousands of objects don't cost a bridge call per cell. Must be called
  * on the main thread. */
class FOObjects : public godot::Object {
    GDCLASS(FOObjects, Object)
public:
    /** Known objects of \a kind ("planets", "fleets", "ships", "buildings",
      * "systems"), only the player's own if \a own_only. Destroyed objects
      * are left out. Every row has id, name, owner_id, owner_name,
      * owner_color, system_id and system_name; per kind:
      * - planets: type, size, species, focus, population, industry,
      *   research, influence, stability, supply, defense, shield, troops
      * - fleets: ships, destination, eta, aggression, structure,
      *   max_structure
      * - ships: design, icon, fleet_id, fleet_name, species, structure,
      *   max_structure
      * - buildings: building_type, planet_id, planet_name
      * - systems: star, planets, fleets */
    static godot::Array list_objects(const godot::String& kind, bool own_only = false);

protected:
    static void _bind_methods();
};

#endif
