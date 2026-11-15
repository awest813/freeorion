#ifndef _FOModerator_h_
#define _FOModerator_h_

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

/** Static API for a multiplayer game's observers and moderators.
  *
  * get_role(): "player", "observer", "moderator" ("" without a game).
  * get_choices(): {star_types, planet_types, planet_sizes: [names]} for the
  *   moderator's creation tools (enum names: STAR_BLUE, PT_SWAMP, SZ_TINY).
  * The moderator actions of the GG client's ModeratorActionsWnd, sent to the
  * server at once; each returns whether it was sent (only a moderator can):
  * destroy(object), set_owner(object, empire; -1 for none),
  * add_starlane(system, system), remove_starlane(system, system),
  * create_system(x, y, star type), create_planet(system, type, size).
  * Main thread only. */
class FOModerator : public godot::Object {
    GDCLASS(FOModerator, Object)
public:
    static godot::String get_role();
    static godot::Dictionary get_choices();
    static bool destroy(int object_id);
    static bool set_owner(int object_id, int empire_id);
    static bool add_starlane(int system_a, int system_b);
    static bool remove_starlane(int system_a, int system_b);
    static bool create_system(double x, double y, const godot::String& star_type);
    static bool create_planet(int system_id, const godot::String& planet_type, const godot::String& planet_size);

protected:
    static void _bind_methods();
};

#endif
