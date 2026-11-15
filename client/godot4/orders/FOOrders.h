#ifndef _FOOrders_h_
#define _FOOrders_h_

#include <godot_cpp/classes/object.hpp>

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

    /** Number of orders issued so far this turn. */
    static int get_order_count();

protected:
    static void _bind_methods();
};

#endif
