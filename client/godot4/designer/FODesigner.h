#ifndef _FODesigner_h_
#define _FODesigner_h_

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

/** Static ship designer API for GDScript.
  *
  * get_hulls(): [{name, icon, graphic, structure, speed, fuel, slots:
  *   [{type ("external"|"internal"|"core"), x, y}]}] available to the player.
  * get_parts(): [{name, icon, class, capacity, mountable: [slot types]}].
  * evaluate(hull, parts): {valid, attack, structure, shields, speed, fuel,
  *   detection, stealth, colony, troops, cost, turns}; parts has one entry
  *   per hull slot, "" for an empty slot.
  * create(name, hull, parts): adds the design to the empire; returns its
  *   ID or -1 if refused.
  * get_designs(): [{id, name, hull, parts, producible}] the empire knows.
  * Names (hull, part, class) are stringtable keys. Main thread only. */
class FODesigner : public godot::Object {
    GDCLASS(FODesigner, Object)
public:
    static godot::Array get_hulls();
    static godot::Array get_parts();
    static godot::Dictionary evaluate(const godot::String& hull, const godot::PackedStringArray& parts);
    static int create(const godot::String& name, const godot::String& hull,
                      const godot::PackedStringArray& parts);
    static godot::Array get_designs();

protected:
    static void _bind_methods();
};

#endif
