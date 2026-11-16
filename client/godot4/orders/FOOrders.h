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
    /** Why moving \a fleet_id to \a dest_system_id can't work, or works only in
      * part, as a string table key: MOVE_PROBLEM_NO_ROUTE (no known starlanes
      * lead there), MOVE_PROBLEM_IMMOBILE (speed 0), MOVE_PROBLEM_FUEL (too
      * far outside supply for the fleet's fuel; it moves as far as it can),
      * MOVE_PROBLEM_UNKNOWN (not an own fleet or a known system); "" when
      * it can get there. issue_fleet_move() refuses all but MOVE_PROBLEM_FUEL. */
    static godot::String move_problem(int fleet_id, int dest_system_id, bool append = false);

    /** Undo and remove an order issued this turn. Returns false if there is no
      * such order or its type can't be undone (for example fleet moves; issue a
      * new move instead). */
    static bool rescind_order(int order_id);

    /** Set a fleet's stance: "passive", "defensive", "obstructive" or
      * "aggressive". Returns false if refused. */
    static bool set_fleet_aggression(int fleet_id, const godot::String& aggression);

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

    /** Whether \a object_id is a sensor ghost: not the player's, and not
        seen this turn (GG's "dismiss sensor ghost"). */
    static bool is_sensor_ghost(int object_id);
    /** Forget sensor ghost \a object_id (a fleet; a lone ship's fleet). */
    static bool forget(int object_id);
    /** Empires at peace with the player that have something at the own
        planet's or idle fleet's system, which it can be given to:
        [{id, name, color}]; and whether it is being given already. */
    static godot::Dictionary get_give_targets(int object_id);
    /** Give own \a object_id to empire \a recipient at the turn's end; -1
        cancels a gift ordered this turn. */
    static bool give_to_empire(int object_id, int recipient);

protected:
    static void _bind_methods();
};

#endif
