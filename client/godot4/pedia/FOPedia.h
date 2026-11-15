#ifndef _FOPedia_h_
#define _FOPedia_h_

#include <atomic>

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
  * resolve_values(text) -> text with each <value NAME>...</value> holding
  *   the named value's evaluation, as GG's ValueRefLinkText (unknown names
  *   keep their content).
  * Main thread only. */
class FOPedia : public godot::Object {
    GDCLASS(FOPedia, Object)
public:
    static godot::Dictionary get_article(const godot::String& kind, const godot::String& name);
    static godot::Array get_index();
    static bool has_article(const godot::String& kind, const godot::String& name);
    static godot::String resolve_values(const godot::String& text);
    /** Whether the content has been parsed (set by FreeOrionNode); named
      * values are only evaluated once it has. */
    static std::atomic<bool>& ContentReady();

protected:
    static void _bind_methods();
};

#endif
