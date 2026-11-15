#ifndef _FOOrders_h_
#define _FOOrders_h_

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string.hpp>

/** Static order API for GDScript: FOOrders.issue_fleet_move(...), ...
  *
  * Orders are executed on the client immediately (so views reflect them at
  * once) and sent to the server with the turn. Must be called on the main
  * thread. */
class FOOrders : public godot::Object {
    GDCLASS(FOOrders, Object)
public:
    /** Order fleet \a fleet_id to move to system \a dest_system_id. Ordering a
      * move to the fleet's current system stops it. Returns the order ID, or -1
      * if the order is not allowed (the reason is logged). */
    static int issue_fleet_move(int fleet_id, int dest_system_id, bool append = false);

    /** Undo and remove an order issued this turn. Returns false if there is no
      * such order or its type can't be undone (for example fleet moves; issue a
      * new move instead). */
    static bool rescind_order(int order_id);

    /** Set a fleet's stance: "passive", "defensive", "obstructive" or
      * "aggressive". Returns false if refused. */
    static bool set_fleet_aggression(int fleet_id, const godot::String& aggression);

    /** Move \a ship_ids (all in one fleet) into a new fleet with the same
      * stance. Returns the new fleet's ID, or -1 if refused. */
    /** New fleet with \a ship_ids; its stance is \a aggression ("passive",
        "defensive", "obstructive", "aggressive"), "auto" (aggressive if a
        ship can do damage, else defensive, as GG's Auto) or "" (that of the
        fleet the ships leave). Returns the new fleet's id or -1. */
    static int split_ships(const godot::PackedInt32Array& ship_ids, const godot::String& aggression);

    /** Move \a ship_ids into fleet \a dest_fleet_id (same system, owner). */
    static bool merge_ships(int dest_fleet_id, const godot::PackedInt32Array& ship_ids);

    /** Rename an own fleet, ship, or other object. */
    static bool rename(int object_id, const godot::String& new_name);

    /** Number of orders issued so far this turn. */
    static int get_order_count();
    /** Drop every order given this turn; the server sends the turn again. */
    static bool revert_all();

protected:
    static void _bind_methods();
};

#endif
