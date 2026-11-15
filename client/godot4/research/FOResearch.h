#ifndef _FOResearch_h_
#define _FOResearch_h_

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

/** Static research API for GDScript: FOResearch.get_queue(), ...
  *
  * Queue element: {index, name, category, icon, allocated_rp, turns_left
  *   (-1 = never), progress (0..1), cost}
  * Tech: {name, category, icon, short_description, cost, turns, status
  *   ("complete"|"researchable"|"partial"|"unresearchable"), in_queue,
  *   progress (0..1)}
  * name, category and short_description are stringtable keys.
  * Orders execute on the client at once and update the projected queue.
  * Main thread only. */
class FOResearch : public godot::Object {
    GDCLASS(FOResearch, Object)
public:
    static godot::Array get_queue();
    static godot::Dictionary get_points();      ///< {available, spent}
    static godot::Array get_techs();            ///< every researchable-in-principle tech
    static godot::PackedStringArray get_categories();

    /** Queue \a name at \a position (-1: end), with any unresearched,
      * unqueued prerequisites before it. */
    static bool enqueue(const godot::String& name, int position = -1);
    static bool remove(const godot::String& name);
    static bool move(const godot::String& name, int position);

protected:
    static void _bind_methods();
};

#endif
