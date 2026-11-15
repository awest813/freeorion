#ifndef _FODesigner_h_
#define _FODesigner_h_

#include <set>
#include <vector>
#include <string>

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

/** Static ship designer API for GDScript.
  *
  * get_hulls(include_unavailable): [{name, icon, graphic, description,
  *   structure, speed, fuel, stealth, cost, available, obsolete, slots:
  *   [{type ("external"|"internal"|"core"), x, y}]}]; the player's
  *   available ones, or every producible one.
  * get_parts(include_unavailable): [{name, icon, class, capacity,
  *   secondary, description, cost, available, obsolete, mountable: [slot
  *   types]}].
  * evaluate(hull, parts): {valid, problems: [why not valid], unavailable:
  *   [hull or parts the empire can't build], duplicate_of (an own design's
  *   name, when one has the same hull and parts), attack, structure,
  *   shields, speed, fuel, detection, stealth, colony, troops, cost, turns};
  *   parts has one entry per hull slot, "" for an empty slot.
  * create(name, hull, parts, description): adds the design to the empire;
  *   returns its ID or -1 if refused.
  * get_designs(): [{id, name, hull, parts, producible}] the empire knows.
  * Names (hull, part, class) are stringtable keys. Main thread only. */
class FODesigner : public godot::Object {
    GDCLASS(FODesigner, Object)
public:
    static godot::Array get_hulls(bool include_unavailable = false);
    static godot::Array get_parts(bool include_unavailable = false);
    static godot::Dictionary evaluate(const godot::String& hull, const godot::PackedStringArray& parts);
    static int create(const godot::String& name, const godot::String& hull,
                      const godot::PackedStringArray& parts, const godot::String& description = "");
    /** Replace own design \a design_id with a new one; returns its ID. */
    static int update_design(int design_id, const godot::String& name, const godot::String& hull,
                             const godot::PackedStringArray& parts, const godot::String& description);
    /** Rewrite saved design \a uuid. */
    static bool update_saved(const godot::String& uuid, const godot::String& name, const godot::String& hull,
                             const godot::PackedStringArray& parts, const godot::String& description);
    /** Mark a part or hull obsolete (hidden unless the Obsolete filter is
      * on), kept with the save's UI data as the GG client keeps them. */
    static bool set_part_obsolete(const godot::String& name, bool obsolete);
    static bool set_hull_obsolete(const godot::String& name, bool obsolete);
    static std::set<std::string>& ObsoleteParts();
    static std::set<std::string>& ObsoleteHulls();
    /** Designs of \a kind: "empire" (the player's, which production
      * offers), "obsolete" (put aside: the empire forgets them, this client
      * keeps them listed), "premade" or "monster" (the game's predefined
      * ones). {id, name, hull, parts, producible}. */
    static godot::Array get_designs(const godot::String& kind = "empire");

    /** Put own design \a design_id aside (production stops offering it), or
      * bring it back. */
    static bool set_obsolete(int design_id, bool obsolete);

    /** Forget design \a design_id for good (own or put aside). */
    static bool delete_design(int design_id);

    /** Rename own design \a design_id. */
    static bool rename_design(int design_id, const godot::String& new_name);

    /** Add a copy of premade design \a design_id to the empire's designs. */
    static int add_premade(int design_id);
    /** Designs kept between games in <user data>/shipdesigns, as the GG
      * client keeps them: get_designs("saved") lists them by "uuid". */
    static bool save_design(int design_id);
    static int add_saved(const godot::String& uuid);
    static bool delete_saved(const godot::String& uuid);
    /** Add every saved design to the empire (a new game's first turn). */
    static int add_all_saved();

    /** IDs put aside as obsolete, kept with the save's UI data. */
    static std::set<int>& ObsoleteDesigns();

    /** Move own design \a design_id before \a before_id (-1: to the end):
      * the designs list and production's catalogue follow this order, kept
      * with the save's UI data as the GG client keeps it. */
    static bool move_design(int design_id, int before_id);
    /** The order the player set (designs not in it go after, by id). */
    static std::vector<int>& DesignOrder();
    /** \a ids sorted by DesignOrder(). */
    static std::vector<int> Ordered(std::vector<int> ids);

protected:
    static void _bind_methods();
};

#endif
