#ifndef _FOCombat_h_
#define _FOCombat_h_

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

/** Static combat report API for GDScript: FOCombat.list_combats(), ...
  *
  * The client learns of combats as log IDs; FreeOrionNode fetches their
  * contents from the server after each turn and emits combat_logs_updated
  * when they arrive. Texts are FreeOrion markup (links, colours), for
  * FORichText. Must be called on the main thread. */
class FOCombat : public godot::Object {
    GDCLASS(FOCombat, Object)
public:
    /** Combats the player's empire took part in (all, for an observer),
      * newest first: {id, turn, system_id, system_name, sides}. Each side is
      * {empire_id, name, color, units, destroyed, health, max_health,
      * damage_dealt, own}; empire_id -1 is the unowned side
      * (monsters, natives). */
    static godot::Array list_combats();

    /** One combat: the list_combats() entry plus, per side, "units" as
      * {id, name, type ("ship", "planet", ...), icon, planet_type, health,
      * max_health, destroyed}, and "events": the combat log as a tree of
      * {kind, text, details, children}; kind is "bout" (a round), "attack",
      * "destroyed", "fighters" or "other". {} if the log isn't known (yet). */
    static godot::Dictionary get_combat(int log_id);

    /** Number of combat logs still being fetched from the server. */
    static int get_pending_count();

protected:
    static void _bind_methods();
};

#endif
