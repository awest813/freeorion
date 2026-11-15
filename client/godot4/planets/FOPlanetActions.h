#ifndef _FOPlanetActions_h_
#define _FOPlanetActions_h_

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

/** Static planet action API for GDScript: what the player can do with a
  * planet (colonise, invade, annex, change focus) and the orders for it,
  * as the GG client's SidePanel::PlanetPanel offers them.
  *
  * Colonise and invade pick the ships themselves: the colony ship in the
  * planet's system giving the largest colony, and "just enough" troop
  * ships. Each order call toggles: it issues the order, or cancels the one
  * issued earlier this turn. Must be called on the main thread. */
class FOPlanetActions : public godot::Object {
    GDCLASS(FOPlanetActions, Object)
public:
    /** Actions for planet \a planet_id; each entry has "state": "" (not
      * offered), "available", "pending" (ordered this turn, can be
      * cancelled) or, for annex, "unaffordable" / "restricted".
      * - colonize: outpost, ship_id, ship_name, species, capacity,
      *   target_population
      * - invade: troops, defenders, ships
      * - annex: cost
      * - bombard: ships
      * - focus: current, options (focus names), icons */
    static godot::Dictionary get_actions(int planet_id);

    /** Order (or cancel) colonising \a planet_id. */
    static bool colonize(int planet_id);

    /** Order (or cancel) invading \a planet_id. */
    static bool invade(int planet_id);

    /** Order (or cancel) annexing \a planet_id. */
    static bool annex(int planet_id);

    /** Order (or stop) bombarding \a planet_id with the ships in its
      * system whose weapons suit it. */
    static bool bombard(int planet_id);

    /** Change own planet \a planet_id's focus to \a focus. */
    static bool set_focus(int planet_id, const godot::String& focus);

    /** Order (or cancel) scrapping own ship or building \a object_id. */
    static bool scrap(int object_id);

    /** True if own ship or building \a object_id is ordered scrapped. */
    static bool is_scrapping(int object_id);

protected:
    static void _bind_methods();
};

#endif
