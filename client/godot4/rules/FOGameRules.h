#ifndef _FOGameRules_h_
#define _FOGameRules_h_

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

/** Static game rules API for GDScript, for galaxy setup. The rules a new
  * game starts with are GetGameRules()'s values, so set_rules() changes
  * those before new_single_player_game(). */
class FOGameRules : public godot::Object {
    GDCLASS(FOGameRules, Object)
public:
    /** Every game rule, by category and rank:
      * {name, category, type ("toggle", "int", "double", "string"), value,
      * default, description, and where the validator says: min, max, step,
      * choices (string rules picked from a list)}. All of them, as the GG
      * rules panel shows ("engine internal" rules are ones client and server
      * both need, not hidden ones). */
    static godot::Array list_rules();

    /** Set the rules in \a values ({name: value}) and every other rule to
      * its default. False (nothing changed) if a value isn't allowed. */
    static bool set_rules(const godot::Dictionary& values);

protected:
    static void _bind_methods();
};

#endif
