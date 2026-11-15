#ifndef _FODiplomacy_h_
#define _FODiplomacy_h_

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>

/** Static diplomacy API for GDScript: the empires, how the player stands
  * with each, pending proposals, and the diplomatic actions the GG client's
  * player list offers. Actions are sent to the server at once (they aren't
  * turn orders); FreeOrionNode emits diplomacy_changed when the server
  * reports new proposals or statuses. Must be called on the main thread. */
class FODiplomacy : public godot::Object {
    GDCLASS(FODiplomacy, Object)
public:
    /** All empires, the player's first: {id, name, player, color, own,
      * eliminated, status ("war", "peace", "allied"; "" for the own empire),
      * incoming and outgoing (pending proposal: "peace", "allies" or ""),
      * actions (what act() accepts now, in a sensible order)}. */
    static godot::Array get_empires();

    /** Number of proposals other empires made to the player. */
    static int get_incoming_count();

    /** Do \a action towards empire \a empire_id: "propose_peace",
      * "accept_peace", "propose_alliance", "accept_alliance", "reject",
      * "cancel", "end_alliance" or "declare_war". False if not allowed now. */
    static bool act(int empire_id, const godot::String& action);

protected:
    static void _bind_methods();
};

#endif
