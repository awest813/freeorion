#ifndef _FOProduction_h_
#define _FOProduction_h_

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

/** Static production API for GDScript: FOProduction.get_queue(), ...
  *
  * Items are dictionaries. Queue element:
  *   {index, build_type ("building"|"ship"), name, design_id, label, icon,
  *    location_id, location_name, ordered, remaining, blocksize, progress
  *    (0..1), allocated_pp, turns_left (-1 = never), paused}
  * Buildable item:
  *   {build_type, name, design_id, label, icon, cost, turns}
  * label is a stringtable key for buildings and a display name for ships.
  * Orders execute on the client at once and update the projected queue.
  * Main thread only. */
class FOProduction : public godot::Object {
    GDCLASS(FOProduction, Object)
public:
    static godot::Array get_queue();
    /** {available, spent, stockpile, stockpile_used, stockpile_capacity
      * (PP a turn can draw from it), stockpile_expected (next turn)} */
    static godot::Dictionary get_points();
    static godot::Array get_buildable(int location_id);
    /** Locations (planet IDs) where the player can produce anything. */
    static godot::PackedInt32Array get_production_locations();

    static bool enqueue_building(const godot::String& name, int location_id);
    static bool enqueue_ship(int design_id, int location_id, int quantity = 1);
    static bool remove(int index);
    static bool move(int index, int new_index);
    static bool set_quantity(int index, int quantity);
    /** Pause or resume queue item \a index (paused items get no PP). */
    static bool set_paused(int index, bool paused);
    /** Let queue item \a index draw on the imperial stockpile, or not. */
    static bool set_stockpile_allowed(int index, bool allowed);
    /** Queue the project that moves PP into the imperial stockpile. */
    static bool enqueue_stockpile_project(int location_id);

protected:
    static void _bind_methods();
};

#endif
