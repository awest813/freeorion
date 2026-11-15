#ifndef _FOGovernment_h_
#define _FOGovernment_h_

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

/** Static government API for GDScript: FOGovernment.get_slots(), ...
  *
  * Slots: [{category, policies: [name or "" per slot]}]
  * Policy (every policy, locked ones too): {name, category, icon,
  *   short_description, description, cost, adopted, available (unlocked),
  *   affordable, prerequisites_ok, adopted_this_turn, current_turns,
  *   total_turns, excluded_by: [adopted names], prerequisites: [{name,
  *   met}]}; names, category and descriptions are stringtable keys.
  * Influence: {stockpile, adoption_cost} (IP; adoption_cost is this turn's
  *   total upkeep of adopted policies).
  * Adoption orders execute on the client at once and update the influence
  * projection, as the GG GovernmentWnd does. Main thread only. */
class FOGovernment : public godot::Object {
    GDCLASS(FOGovernment, Object)
public:
    static godot::Array get_slots();
    static godot::Array get_policies();
    static godot::Dictionary get_influence();

    /** Adopt \a name into \a slot of its category; true if it is adopted. */
    static bool adopt(const godot::String& name, int slot);
    /** Revoke an adopted (or this turn's pending) policy. */
    static bool de_adopt(const godot::String& name);
    /** Whether the adopted policies differ from the turn's start. */
    static bool is_modified();
    /** Undo this turn's adoptions and revocations; true if anything changed. */
    static bool revert();

protected:
    static void _bind_methods();
};

#endif
