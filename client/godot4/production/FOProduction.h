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
    /** What can be built at \a location_id; with \a include_unavailable also
        what can't, each with available false and the failed conditions
        (reason). Entries carry cost, turns, cost_per_turn, description. */
    static godot::Array get_buildable(int location_id, bool include_unavailable = false);
    /** The industry of \a location_id's supply group: {output, allocated}. */
    static godot::Dictionary get_group_points(int location_id);
    /** Locations (planet IDs) where the player can produce anything. */
    static godot::PackedInt32Array get_production_locations();
    /** Of get_production_locations(), those where \a item (as get_buildable()
      * describes it: build_type, name or design_id) can be built now. */
    static godot::PackedInt32Array get_item_locations(const godot::Dictionary& item);

    /** Add to the queue's end, or at \a position (0: the top). */
    /** With \a force, items that can't be produced at \a location_id now are
      * queued too (they wait there, as GG lets the player add them). */
    static bool enqueue_building(const godot::String& name, int location_id, int position = -1,
                                 bool force = false);
    static bool enqueue_ship(int design_id, int location_id, int quantity = 1, int position = -1,
                             bool force = false);
    static bool remove(int index);
    static bool move(int index, int new_index);
    static bool set_quantity(int index, int quantity);
    /** Pause or resume queue item \a index (paused items get no PP). */
    static bool set_paused(int index, bool paused);
    /** Let queue item \a index draw on the imperial stockpile, or not. */
    static bool set_stockpile_allowed(int index, bool allowed);
    /** Queue the project that moves PP into the imperial stockpile. */
    static bool enqueue_stockpile_project(int location_id, int position = -1);
    /** Ships built together in each batch (all finish on the same turn). */
    static bool set_blocksize(int index, int blocksize);
    /** Another copy of the item, after it. */
    static bool duplicate(int index);
    /** Split the batches not yet started into an item of their own. */
    static bool split_incomplete(int index);
    /** Ships built by item \a index go to system \a system_id (-1: stay). */
    static bool set_rally_point(int index, int system_id);
    /** Items removed this turn, which can still be restored: [{index, label,
        build_type, name, design_id, icon, location_name}]. */
    static godot::Array get_removed();
    /** Put a removed item back where it was. */
    static bool restore(int index);

protected:
    static void _bind_methods();
};

#endif
