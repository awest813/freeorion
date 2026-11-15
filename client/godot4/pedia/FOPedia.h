#ifndef _FOPedia_h_
#define _FOPedia_h_

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

/** Static Pedia API for GDScript.
  *
  * Kinds follow FreeOrion's link tags: tech, buildingtype, species, special,
  * shippart, shiphull, fieldtype, policy, encyclopedia.
  *
  * get_article(kind, name) -> {kind, name, title (stringtable key),
  *   icon, text (expanded description with link markup, for FORichText),
  *   facts: [[label key, value]], links: [{kind, name, group}]} or {} when
  *   unknown. group is "prerequisites" or "unlocks".
  * get_index() -> [{kind, name, category}] of everything with an article.
  * Main thread only. */
class FOPedia : public godot::Object {
    GDCLASS(FOPedia, Object)
public:
    static godot::Dictionary get_article(const godot::String& kind, const godot::String& name);
    static godot::Array get_index();
    static bool has_article(const godot::String& kind, const godot::String& name);

protected:
    static void _bind_methods();
};

#endif
