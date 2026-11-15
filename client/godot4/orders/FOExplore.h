#ifndef FO_GODOT_EXPLORE_H
#define FO_GODOT_EXPLORE_H

#include <set>
#include <godot_cpp/classes/object.hpp>

struct ScriptingContext;

/** Fleets exploring on their own (the GG client's explore order). The set
    is kept with the game's UI data, so it survives saving and loading. */
class FOExplore : public godot::Object {
    GDCLASS(FOExplore, Object)
public:
    /** Send own fleet \a fleet_id exploring, or stop it. */
    static void set_exploring(int fleet_id, bool exploring);
    static bool is_exploring(int fleet_id);
    /** Order every idle exploring fleet to its next system (each turn). */
    static void dispatch();

    static std::set<int>& Exploring();

protected:
    static void _bind_methods();

private:
    static void Dispatch(ScriptingContext& context, int empire_id);
};

#endif
