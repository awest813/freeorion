#ifndef _FOViews_h_
#define _FOViews_h_

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2.hpp>

/** Read-only views of the client's known universe, for GDScript.
  *
  * Views hold an object ID, not a pointer, and look the object up on every
  * access, so a view stays safe across turn updates: if the object is no
  * longer known, is_valid() returns false and getters return defaults.
  *
  * All of these must be called on the main thread. FreeOrionNode dispatches
  * server messages on the main thread, so the universe never changes while a
  * script is reading it. */

class FOSystem : public godot::RefCounted {
    GDCLASS(FOSystem, RefCounted)
public:
    static godot::Ref<FOSystem> make(int id);

    int get_id() const noexcept { return m_id; }
    bool is_valid() const;
    godot::String get_name() const;
    godot::Vector2 get_position() const;
    godot::String get_star_type() const;
    godot::PackedInt32Array get_starlanes() const; ///< IDs of systems connected by known starlanes
    godot::PackedInt32Array get_planet_ids() const;
    godot::PackedInt32Array get_fleet_ids() const;

protected:
    static void _bind_methods();

private:
    int m_id = -1;
};

class FOFleet : public godot::RefCounted {
    GDCLASS(FOFleet, RefCounted)
public:
    static godot::Ref<FOFleet> make(int id);

    int get_id() const noexcept { return m_id; }
    bool is_valid() const;
    godot::String get_name() const;
    godot::Vector2 get_position() const;
    int get_owner_id() const;
    int get_system_id() const;              ///< INVALID_OBJECT_ID while between systems
    int get_next_system_id() const;
    int get_previous_system_id() const;
    int get_final_destination_id() const;   ///< INVALID_OBJECT_ID if not moving
    godot::PackedInt32Array get_travel_route() const;
    godot::PackedInt32Array get_ship_ids() const;
    double get_speed() const;
    bool is_aggressive() const;
    bool is_passive() const;
    /** Turns until the fleet reaches its final destination: 0 if not moving,
      * -1 if it can't get there (no route, out of fuel range or unknown). */
    int get_eta() const;
    /** "passive", "defensive", "obstructive" or "aggressive". */
    godot::String get_aggression() const;

protected:
    static void _bind_methods();

private:
    int m_id = -1;
};

class FOPlanet : public godot::RefCounted {
    GDCLASS(FOPlanet, RefCounted)
public:
    static godot::Ref<FOPlanet> make(int id);

    int get_id() const noexcept { return m_id; }
    bool is_valid() const;
    godot::String get_name() const;
    godot::Vector2 get_position() const;
    int get_owner_id() const;
    int get_system_id() const;
    godot::String get_planet_type() const;
    godot::String get_planet_size() const;
    godot::String get_species_name() const;
    godot::String get_focus() const;
    /** Current value of a meter, by MeterType name such as "METER_POPULATION";
      * 0.0 if the planet or meter is unknown. */
    double get_meter(const godot::String& meter_name) const;

protected:
    static void _bind_methods();

private:
    int m_id = -1;
};

class FOShip : public godot::RefCounted {
    GDCLASS(FOShip, RefCounted)
public:
    static godot::Ref<FOShip> make(int id);

    int get_id() const noexcept { return m_id; }
    bool is_valid() const;
    godot::String get_name() const;
    int get_fleet_id() const;
    int get_owner_id() const;
    int get_design_id() const;
    godot::String get_design_name() const;  ///< display name
    godot::String get_icon() const;         ///< design or hull icon path
    godot::String get_species_name() const;
    double get_structure() const;
    double get_max_structure() const;
    double get_speed() const;
    bool is_armed() const;
    bool can_colonize() const;
    bool has_troops() const;

protected:
    static void _bind_methods();

private:
    int m_id = -1;
};

/** Static entry points: FOUniverse.get_system(id), FOUniverse.get_map_snapshot(), ... */
class FOUniverse : public godot::Object {
    GDCLASS(FOUniverse, Object)
public:
    static int get_empire_id();
    static godot::Ref<FOSystem> get_system(int id);
    static godot::Ref<FOFleet> get_fleet(int id);
    static godot::Ref<FOPlanet> get_planet(int id);
    static godot::Ref<FOShip> get_ship(int id);
    static godot::PackedInt32Array get_system_ids();
    static godot::PackedInt32Array get_fleet_ids();
    static godot::PackedInt32Array get_planet_ids();
    static godot::Color get_empire_color(int empire_id);
    static godot::String get_empire_name(int empire_id); ///< empty if unknown

    /** The player's empire at a glance, as the GG map toolbar shows it:
      * industry / industry_spent (PP), research / research_spent (RP),
      * influence (IP stockpile) and influence_change (expected next turn),
      * pp_stockpile, population, ships, detection; eliminated and won.
      * {} without an empire. */
    static godot::Dictionary get_empire_resources();

    /** Everything the planet panel shows about planet \a planet_id: name,
      * type, size, species, focus, owner_id, own, owner_name, owner_color,
      * environment (for its species, a PlanetEnvironment name), meters
      * (array of {meter, now, next, target}: this turn, projected next
      * turn and the target or maximum it moves to; only meters the planet
      * has), buildings ({id, type, name, icon, scrapping}) and specials
      * ({name, icon, capacity}). {} if unknown. */
    static godot::Dictionary get_planet_detail(int planet_id);

    /** Species a player can start with, by name: [{name, icon}]. Needs
      * parsed content; [] before. */
    static godot::Array get_playable_species();

    /** The colours empires can have; setup.empire.color.index indexes it. */
    static godot::PackedColorArray get_empire_colors();

    /** The player's situation reports for \a turn (default: current turn),
      * as dictionaries {text, icon, label, turn}. text keeps FreeOrion link
      * markup (<planet 12>Name</planet>), for FORichText. */
    static godot::Array get_sitreps(int turn = -1);

    /** Bulk data for the galaxy map renderer, as packed arrays so a frame
      * needs one call instead of one per object. Keys:
      *  - system_ids (PackedInt32Array), system_positions (PackedVector2Array),
      *    system_star_types (PackedInt32Array, StarType enum values)
      *  - lanes (PackedInt32Array): pairs of indices into the system arrays,
      *    each known starlane listed once
      *  - fleet_ids (PackedInt32Array), fleet_positions (PackedVector2Array),
      *    fleet_owner_ids (PackedInt32Array)
      *  - supply_systems / supply_system_owners: indices of systems each
      *    empire supplies, with that empire's ID
      *  - supply_lanes / supply_lane_owners: index pairs of lanes each
      *    empire's supply crosses, one owner ID per pair
      *  - field_ids, field_positions, field_radii (PackedFloat32Array),
      *    field_types (type names) and field_graphics (art paths) */
    static godot::Dictionary get_map_snapshot();

protected:
    static void _bind_methods();
};

#endif
