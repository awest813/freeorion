#include "FOViews.h"

#include <unordered_map>
#include <unordered_set>
#include <algorithm>
#include <cstdint>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include "../../ClientApp.h"
#include "../../../Empire/Empire.h"
#include "../../../Empire/Supply.h"
#include "../../../universe/Building.h"
#include "../../../universe/BuildingType.h"
#include "../../../universe/Field.h"
#include "../../../universe/FieldType.h"
#include "../../../universe/Fleet.h"
#include "../../../universe/Planet.h"
#include "../../../universe/Ship.h"
#include "../../../universe/ShipDesign.h"
#include "../../../universe/ShipHull.h"
#include "../../../universe/Special.h"
#include "../../../universe/Species.h"
#include "../../../universe/System.h"
#include "../../../universe/Universe.h"
#include "../../../util/Order.h"
#include "../../../util/OrderSet.h"
#include "../../../util/SitRepEntry.h"

namespace {
    template <typename T>
    const T* Lookup(int id) {
        const auto* app = ClientApp::GetApp();
        if (!app || id == INVALID_OBJECT_ID)
            return nullptr;
        return app->GetUniverse().Objects().getRaw<T>(id);
    }

    template <typename T>
    godot::PackedInt32Array AllIDs() {
        godot::PackedInt32Array ids;
        if (const auto* app = ClientApp::GetApp())
            for (const auto* obj : app->GetUniverse().Objects().allRaw<T>())
                ids.push_back(obj->ID());
        return ids;
    }

    template <typename Container>
    godot::PackedInt32Array ToPacked(const Container& ids) {
        godot::PackedInt32Array out;
        for (int id : ids)
            out.push_back(id);
        return out;
    }

    godot::String ToGodot(std::string_view s)
    { return godot::String::utf8(s.data(), static_cast<int>(s.size())); }

    godot::Vector2 Position(const UniverseObject& obj)
    { return {static_cast<godot::real_t>(obj.X()), static_cast<godot::real_t>(obj.Y())}; }
}

// FOSystem

godot::Ref<FOSystem> FOSystem::make(int id) {
    godot::Ref<FOSystem> view;
    view.instantiate();
    view->m_id = id;
    return view;
}

void FOSystem::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    ClassDB::bind_method(D_METHOD("get_id"), &FOSystem::get_id);
    ClassDB::bind_method(D_METHOD("is_valid"), &FOSystem::is_valid);
    ClassDB::bind_method(D_METHOD("get_name"), &FOSystem::get_name);
    ClassDB::bind_method(D_METHOD("get_position"), &FOSystem::get_position);
    ClassDB::bind_method(D_METHOD("get_star_type"), &FOSystem::get_star_type);
    ClassDB::bind_method(D_METHOD("get_starlanes"), &FOSystem::get_starlanes);
    ClassDB::bind_method(D_METHOD("get_planet_ids"), &FOSystem::get_planet_ids);
    ClassDB::bind_method(D_METHOD("get_fleet_ids"), &FOSystem::get_fleet_ids);
}

bool FOSystem::is_valid() const
{ return Lookup<System>(m_id) != nullptr; }

godot::String FOSystem::get_name() const {
    const auto* sys = Lookup<System>(m_id);
    return sys ? ToGodot(sys->Name()) : godot::String();
}

godot::Vector2 FOSystem::get_position() const {
    const auto* sys = Lookup<System>(m_id);
    return sys ? Position(*sys) : godot::Vector2();
}

godot::String FOSystem::get_star_type() const {
    const auto* sys = Lookup<System>(m_id);
    return ToGodot(::to_string(sys ? sys->GetStarType() : StarType::INVALID_STAR_TYPE));
}

godot::PackedInt32Array FOSystem::get_starlanes() const {
    const auto* sys = Lookup<System>(m_id);
    return sys ? ToPacked(sys->Starlanes()) : godot::PackedInt32Array();
}

godot::PackedInt32Array FOSystem::get_planet_ids() const {
    const auto* sys = Lookup<System>(m_id);
    return sys ? ToPacked(sys->PlanetIDs()) : godot::PackedInt32Array();
}

godot::PackedInt32Array FOSystem::get_fleet_ids() const {
    const auto* sys = Lookup<System>(m_id);
    return sys ? ToPacked(sys->FleetIDs()) : godot::PackedInt32Array();
}

// FOFleet

godot::Ref<FOFleet> FOFleet::make(int id) {
    godot::Ref<FOFleet> view;
    view.instantiate();
    view->m_id = id;
    return view;
}

void FOFleet::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    ClassDB::bind_method(D_METHOD("get_id"), &FOFleet::get_id);
    ClassDB::bind_method(D_METHOD("is_valid"), &FOFleet::is_valid);
    ClassDB::bind_method(D_METHOD("get_name"), &FOFleet::get_name);
    ClassDB::bind_method(D_METHOD("get_position"), &FOFleet::get_position);
    ClassDB::bind_method(D_METHOD("get_owner_id"), &FOFleet::get_owner_id);
    ClassDB::bind_method(D_METHOD("get_system_id"), &FOFleet::get_system_id);
    ClassDB::bind_method(D_METHOD("get_next_system_id"), &FOFleet::get_next_system_id);
    ClassDB::bind_method(D_METHOD("get_previous_system_id"), &FOFleet::get_previous_system_id);
    ClassDB::bind_method(D_METHOD("get_final_destination_id"), &FOFleet::get_final_destination_id);
    ClassDB::bind_method(D_METHOD("get_travel_route"), &FOFleet::get_travel_route);
    ClassDB::bind_method(D_METHOD("get_ship_ids"), &FOFleet::get_ship_ids);
    ClassDB::bind_method(D_METHOD("get_speed"), &FOFleet::get_speed);
    ClassDB::bind_method(D_METHOD("is_aggressive"), &FOFleet::is_aggressive);
    ClassDB::bind_method(D_METHOD("is_passive"), &FOFleet::is_passive);
    ClassDB::bind_method(D_METHOD("get_eta"), &FOFleet::get_eta);
    ClassDB::bind_method(D_METHOD("get_aggression"), &FOFleet::get_aggression);
}

bool FOFleet::is_valid() const
{ return Lookup<Fleet>(m_id) != nullptr; }

godot::String FOFleet::get_name() const {
    const auto* fleet = Lookup<Fleet>(m_id);
    return fleet ? ToGodot(fleet->Name()) : godot::String();
}

godot::Vector2 FOFleet::get_position() const {
    const auto* fleet = Lookup<Fleet>(m_id);
    return fleet ? Position(*fleet) : godot::Vector2();
}

int FOFleet::get_owner_id() const {
    const auto* fleet = Lookup<Fleet>(m_id);
    return fleet ? fleet->Owner() : ALL_EMPIRES;
}

int FOFleet::get_system_id() const {
    const auto* fleet = Lookup<Fleet>(m_id);
    return fleet ? fleet->SystemID() : INVALID_OBJECT_ID;
}

int FOFleet::get_next_system_id() const {
    const auto* fleet = Lookup<Fleet>(m_id);
    return fleet ? fleet->NextSystemID() : INVALID_OBJECT_ID;
}

int FOFleet::get_previous_system_id() const {
    const auto* fleet = Lookup<Fleet>(m_id);
    return fleet ? fleet->PreviousSystemID() : INVALID_OBJECT_ID;
}

int FOFleet::get_final_destination_id() const {
    const auto* fleet = Lookup<Fleet>(m_id);
    return fleet ? fleet->FinalDestinationID() : INVALID_OBJECT_ID;
}

godot::PackedInt32Array FOFleet::get_travel_route() const {
    const auto* fleet = Lookup<Fleet>(m_id);
    return fleet ? ToPacked(fleet->TravelRoute()) : godot::PackedInt32Array();
}

godot::PackedInt32Array FOFleet::get_ship_ids() const {
    const auto* fleet = Lookup<Fleet>(m_id);
    return fleet ? ToPacked(fleet->ShipIDs()) : godot::PackedInt32Array();
}

double FOFleet::get_speed() const {
    const auto* fleet = Lookup<Fleet>(m_id);
    const auto* app = ClientApp::GetApp();
    return (fleet && app) ? fleet->Speed(app->GetUniverse().Objects()) : 0.0;
}

bool FOFleet::is_aggressive() const {
    const auto* fleet = Lookup<Fleet>(m_id);
    return fleet && fleet->Aggressive();
}

bool FOFleet::is_passive() const {
    const auto* fleet = Lookup<Fleet>(m_id);
    return fleet && fleet->Passive();
}

int FOFleet::get_eta() const {
    const auto* fleet = Lookup<Fleet>(m_id);
    const auto* app = ClientApp::GetApp();
    if (!fleet || !app || fleet->FinalDestinationID() == INVALID_OBJECT_ID)
        return 0;
    const auto eta = fleet->ETA(app->GetContext()).first;
    if (eta == Fleet::ETA_NEVER || eta == Fleet::ETA_UNKNOWN || eta == Fleet::ETA_OUT_OF_RANGE)
        return -1;
    return static_cast<int>(eta);
}

godot::String FOFleet::get_aggression() const {
    const auto* fleet = Lookup<Fleet>(m_id);
    switch (fleet ? fleet->Aggression() : FleetAggression::INVALID_FLEET_AGGRESSION) {
    case FleetAggression::FLEET_PASSIVE:     return "passive";
    case FleetAggression::FLEET_DEFENSIVE:   return "defensive";
    case FleetAggression::FLEET_OBSTRUCTIVE: return "obstructive";
    case FleetAggression::FLEET_AGGRESSIVE:  return "aggressive";
    default:                                 return "";
    }
}

// FOShip

godot::Ref<FOShip> FOShip::make(int id) {
    godot::Ref<FOShip> view;
    view.instantiate();
    view->m_id = id;
    return view;
}

void FOShip::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    ClassDB::bind_method(D_METHOD("get_id"), &FOShip::get_id);
    ClassDB::bind_method(D_METHOD("is_valid"), &FOShip::is_valid);
    ClassDB::bind_method(D_METHOD("get_name"), &FOShip::get_name);
    ClassDB::bind_method(D_METHOD("get_fleet_id"), &FOShip::get_fleet_id);
    ClassDB::bind_method(D_METHOD("get_owner_id"), &FOShip::get_owner_id);
    ClassDB::bind_method(D_METHOD("get_design_id"), &FOShip::get_design_id);
    ClassDB::bind_method(D_METHOD("get_design_name"), &FOShip::get_design_name);
    ClassDB::bind_method(D_METHOD("get_icon"), &FOShip::get_icon);
    ClassDB::bind_method(D_METHOD("get_species_name"), &FOShip::get_species_name);
    ClassDB::bind_method(D_METHOD("get_structure"), &FOShip::get_structure);
    ClassDB::bind_method(D_METHOD("get_max_structure"), &FOShip::get_max_structure);
    ClassDB::bind_method(D_METHOD("get_speed"), &FOShip::get_speed);
    ClassDB::bind_method(D_METHOD("is_armed"), &FOShip::is_armed);
    ClassDB::bind_method(D_METHOD("can_colonize"), &FOShip::can_colonize);
    ClassDB::bind_method(D_METHOD("has_troops"), &FOShip::has_troops);
}

bool FOShip::is_valid() const
{ return Lookup<Ship>(m_id) != nullptr; }

godot::String FOShip::get_name() const {
    const auto* ship = Lookup<Ship>(m_id);
    return ship ? ToGodot(ship->Name()) : godot::String();
}

int FOShip::get_fleet_id() const {
    const auto* ship = Lookup<Ship>(m_id);
    return ship ? ship->FleetID() : INVALID_OBJECT_ID;
}

int FOShip::get_owner_id() const {
    const auto* ship = Lookup<Ship>(m_id);
    return ship ? ship->Owner() : ALL_EMPIRES;
}

int FOShip::get_design_id() const {
    const auto* ship = Lookup<Ship>(m_id);
    return ship ? ship->DesignID() : INVALID_DESIGN_ID;
}

godot::String FOShip::get_design_name() const {
    const auto* ship = Lookup<Ship>(m_id);
    const auto* app = ClientApp::GetApp();
    const auto* design = (ship && app) ? app->GetUniverse().GetShipDesign(ship->DesignID()) : nullptr;
    return design ? ToGodot(design->Name(true)) : godot::String();
}

godot::String FOShip::get_icon() const {
    const auto* ship = Lookup<Ship>(m_id);
    const auto* app = ClientApp::GetApp();
    const auto* design = (ship && app) ? app->GetUniverse().GetShipDesign(ship->DesignID()) : nullptr;
    if (!design)
        return {};
    if (!design->Icon().empty())
        return ToGodot(design->Icon());
    const auto* hull = GetShipHull(design->Hull());
    return hull ? ToGodot(hull->Icon()) : godot::String();
}

godot::String FOShip::get_species_name() const {
    const auto* ship = Lookup<Ship>(m_id);
    return ship ? ToGodot(ship->SpeciesName()) : godot::String();
}

double FOShip::get_structure() const {
    const auto* ship = Lookup<Ship>(m_id);
    const auto* meter = ship ? ship->GetMeter(MeterType::METER_STRUCTURE) : nullptr;
    return meter ? meter->Current() : 0.0;
}

double FOShip::get_max_structure() const {
    const auto* ship = Lookup<Ship>(m_id);
    const auto* meter = ship ? ship->GetMeter(MeterType::METER_MAX_STRUCTURE) : nullptr;
    return meter ? meter->Current() : 0.0;
}

double FOShip::get_speed() const {
    const auto* ship = Lookup<Ship>(m_id);
    return ship ? ship->Speed() : 0.0;
}

bool FOShip::is_armed() const {
    const auto* ship = Lookup<Ship>(m_id);
    const auto* app = ClientApp::GetApp();
    return ship && app && ship->IsArmed(app->GetContext());
}

bool FOShip::can_colonize() const {
    const auto* ship = Lookup<Ship>(m_id);
    const auto* app = ClientApp::GetApp();
    return ship && app && ship->CanColonize(app->GetUniverse(), app->GetSpeciesManager());
}

bool FOShip::has_troops() const {
    const auto* ship = Lookup<Ship>(m_id);
    const auto* app = ClientApp::GetApp();
    return ship && app && ship->HasTroops(app->GetUniverse());
}

// FOPlanet

godot::Ref<FOPlanet> FOPlanet::make(int id) {
    godot::Ref<FOPlanet> view;
    view.instantiate();
    view->m_id = id;
    return view;
}

void FOPlanet::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    ClassDB::bind_method(D_METHOD("get_id"), &FOPlanet::get_id);
    ClassDB::bind_method(D_METHOD("is_valid"), &FOPlanet::is_valid);
    ClassDB::bind_method(D_METHOD("get_name"), &FOPlanet::get_name);
    ClassDB::bind_method(D_METHOD("get_position"), &FOPlanet::get_position);
    ClassDB::bind_method(D_METHOD("get_owner_id"), &FOPlanet::get_owner_id);
    ClassDB::bind_method(D_METHOD("get_system_id"), &FOPlanet::get_system_id);
    ClassDB::bind_method(D_METHOD("get_planet_type"), &FOPlanet::get_planet_type);
    ClassDB::bind_method(D_METHOD("get_planet_size"), &FOPlanet::get_planet_size);
    ClassDB::bind_method(D_METHOD("get_species_name"), &FOPlanet::get_species_name);
    ClassDB::bind_method(D_METHOD("get_focus"), &FOPlanet::get_focus);
    ClassDB::bind_method(D_METHOD("get_meter", "meter_name"), &FOPlanet::get_meter);
}

bool FOPlanet::is_valid() const
{ return Lookup<Planet>(m_id) != nullptr; }

godot::String FOPlanet::get_name() const {
    const auto* planet = Lookup<Planet>(m_id);
    return planet ? ToGodot(planet->Name()) : godot::String();
}

godot::Vector2 FOPlanet::get_position() const {
    const auto* planet = Lookup<Planet>(m_id);
    return planet ? Position(*planet) : godot::Vector2();
}

int FOPlanet::get_owner_id() const {
    const auto* planet = Lookup<Planet>(m_id);
    return planet ? planet->Owner() : ALL_EMPIRES;
}

int FOPlanet::get_system_id() const {
    const auto* planet = Lookup<Planet>(m_id);
    return planet ? planet->SystemID() : INVALID_OBJECT_ID;
}

godot::String FOPlanet::get_planet_type() const {
    const auto* planet = Lookup<Planet>(m_id);
    return ToGodot(::to_string(planet ? planet->Type() : PlanetType::INVALID_PLANET_TYPE));
}

godot::String FOPlanet::get_planet_size() const {
    const auto* planet = Lookup<Planet>(m_id);
    return ToGodot(::to_string(planet ? planet->Size() : PlanetSize::INVALID_PLANET_SIZE));
}

godot::String FOPlanet::get_species_name() const {
    const auto* planet = Lookup<Planet>(m_id);
    return planet ? ToGodot(planet->SpeciesName()) : godot::String();
}

godot::String FOPlanet::get_focus() const {
    const auto* planet = Lookup<Planet>(m_id);
    return planet ? ToGodot(planet->Focus()) : godot::String();
}

double FOPlanet::get_meter(const godot::String& meter_name) const {
    const auto* planet = Lookup<Planet>(m_id);
    if (!planet)
        return 0.0;
    const std::string wanted = meter_name.utf8().get_data();
    for (int i = 0; i < static_cast<int>(MeterType::NUM_METER_TYPES); ++i) {
        const auto type = static_cast<MeterType>(i);
        if (::to_string(type) == wanted) {
            const auto* meter = planet->GetMeter(type);
            return meter ? meter->Current() : 0.0;
        }
    }
    return 0.0;
}

// FOUniverse

void FOUniverse::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    const auto cls = get_class_static();
    ClassDB::bind_static_method(cls, D_METHOD("get_empire_id"), &FOUniverse::get_empire_id);
    ClassDB::bind_static_method(cls, D_METHOD("get_system", "id"), &FOUniverse::get_system);
    ClassDB::bind_static_method(cls, D_METHOD("get_fleet", "id"), &FOUniverse::get_fleet);
    ClassDB::bind_static_method(cls, D_METHOD("get_planet", "id"), &FOUniverse::get_planet);
    ClassDB::bind_static_method(cls, D_METHOD("get_ship", "id"), &FOUniverse::get_ship);
    ClassDB::bind_static_method(cls, D_METHOD("get_system_ids"), &FOUniverse::get_system_ids);
    ClassDB::bind_static_method(cls, D_METHOD("get_fleet_ids"), &FOUniverse::get_fleet_ids);
    ClassDB::bind_static_method(cls, D_METHOD("get_planet_ids"), &FOUniverse::get_planet_ids);
    ClassDB::bind_static_method(cls, D_METHOD("get_empire_color", "empire_id"), &FOUniverse::get_empire_color);
    ClassDB::bind_static_method(cls, D_METHOD("get_empire_name", "empire_id"), &FOUniverse::get_empire_name);
    ClassDB::bind_static_method(cls, D_METHOD("get_empire_resources"), &FOUniverse::get_empire_resources);
    ClassDB::bind_static_method(cls, D_METHOD("get_planet_detail", "planet_id"), &FOUniverse::get_planet_detail);
    ClassDB::bind_static_method(cls, D_METHOD("get_sitreps", "turn"), &FOUniverse::get_sitreps, DEFVAL(-1));
    ClassDB::bind_static_method(cls, D_METHOD("get_map_snapshot"), &FOUniverse::get_map_snapshot);
}

int FOUniverse::get_empire_id() {
    const auto* app = ClientApp::GetApp();
    return app ? app->EmpireID() : ALL_EMPIRES;
}

godot::Ref<FOSystem> FOUniverse::get_system(int id)
{ return Lookup<System>(id) ? FOSystem::make(id) : godot::Ref<FOSystem>(); }

godot::Ref<FOFleet> FOUniverse::get_fleet(int id)
{ return Lookup<Fleet>(id) ? FOFleet::make(id) : godot::Ref<FOFleet>(); }

godot::Ref<FOPlanet> FOUniverse::get_planet(int id)
{ return Lookup<Planet>(id) ? FOPlanet::make(id) : godot::Ref<FOPlanet>(); }

godot::Ref<FOShip> FOUniverse::get_ship(int id)
{ return Lookup<Ship>(id) ? FOShip::make(id) : godot::Ref<FOShip>(); }

godot::PackedInt32Array FOUniverse::get_system_ids()
{ return AllIDs<System>(); }

godot::PackedInt32Array FOUniverse::get_fleet_ids()
{ return AllIDs<Fleet>(); }

godot::PackedInt32Array FOUniverse::get_planet_ids()
{ return AllIDs<Planet>(); }

godot::Color FOUniverse::get_empire_color(int empire_id) {
    const auto* app = ClientApp::GetApp();
    const auto* empire = app ? app->GetEmpire(empire_id) : nullptr;
    if (!empire)
        return godot::Color(0.5f, 0.5f, 0.5f, 1.0f);
    const auto c = empire->Color();
    return godot::Color::from_rgba8(c[0], c[1], c[2], c[3]);
}

godot::String FOUniverse::get_empire_name(int empire_id) {
    const auto* app = ClientApp::GetApp();
    const auto* empire = app ? app->GetEmpire(empire_id) : nullptr;
    return empire ? ToGodot(empire->Name()) : godot::String();
}

godot::Array FOUniverse::get_sitreps(int turn) {
    godot::Array result;
    const auto* app = ClientApp::GetApp();
    const auto* empire = app ? app->GetEmpire(app->EmpireID()) : nullptr;
    if (!empire)
        return result;
    if (turn < 0)
        turn = app->CurrentTurn();
    const auto& context = app->GetContext();
    const auto& fixed_infos = empire->SitRepFixedInfos();
    for (const auto& [turn_and_fixed_idx, params_lists] : empire->SitReps()) {
        const auto [sitrep_turn, fixed_idx] = turn_and_fixed_idx;
        if (sitrep_turn != turn || fixed_idx >= fixed_infos.size())
            continue;
        for (const auto& params : params_lists) {
            SitRepEntry sitrep(fixed_infos[fixed_idx], SitRepEntry::UniqueInfo(params.ToStringVector(), turn));
            auto [text, valid] = sitrep.GetTextAndValidity(context);
            if (!valid)
                continue;
            godot::Dictionary entry;
            entry["text"] = ToGodot(text);
            entry["icon"] = ToGodot(sitrep.GetIcon());
            entry["label"] = ToGodot(sitrep.GetLabel());
            entry["turn"] = sitrep.GetTurn();
            result.push_back(entry);
        }
    }
    return result;
}

godot::Dictionary FOUniverse::get_map_snapshot() {
    godot::PackedInt32Array system_ids;
    godot::PackedVector2Array system_positions;
    godot::PackedInt32Array system_star_types;
    godot::PackedInt32Array lanes;
    godot::PackedInt32Array fleet_ids;
    godot::PackedVector2Array fleet_positions;
    godot::PackedInt32Array fleet_owner_ids;
    godot::PackedInt32Array supply_systems;
    godot::PackedInt32Array supply_system_owners;
    godot::PackedInt32Array supply_lanes;
    godot::PackedInt32Array supply_lane_owners;
    godot::PackedInt32Array field_ids;
    godot::PackedVector2Array field_positions;
    godot::PackedFloat32Array field_radii;
    godot::PackedStringArray field_types;
    godot::PackedStringArray field_graphics;

    if (auto* app = ClientApp::GetApp()) {
        const auto& objects = app->GetUniverse().Objects();

        std::unordered_map<int, int> system_index;
        for (const auto* sys : objects.allRaw<System>()) {
            system_index.emplace(sys->ID(), static_cast<int>(system_ids.size()));
            system_ids.push_back(sys->ID());
            system_positions.push_back(Position(*sys));
            system_star_types.push_back(static_cast<int>(sys->GetStarType()));
        }

        // A lane may be known from one end only, so dedupe on the (lower, higher) index pair.
        // Lanes to systems that are not known are skipped.
        std::unordered_set<int64_t> seen_lanes;
        for (const auto* sys : objects.allRaw<System>()) {
            const int from = system_index.at(sys->ID());
            for (int lane_end_id : sys->Starlanes()) {
                const auto it = system_index.find(lane_end_id);
                if (it == system_index.end() || it->second == from)
                    continue;
                const int lo = std::min(from, it->second);
                const int hi = std::max(from, it->second);
                if (!seen_lanes.insert((static_cast<int64_t>(lo) << 32) | static_cast<uint32_t>(hi)).second)
                    continue;
                lanes.push_back(lo);
                lanes.push_back(hi);
            }
        }

        for (const auto* fleet : objects.allRaw<Fleet>()) {
            fleet_ids.push_back(fleet->ID());
            fleet_positions.push_back(Position(*fleet));
            fleet_owner_ids.push_back(fleet->Owner());
        }

        // Fields (ion storms, nebulae, ...): their size meter is the radius.
        const auto& destroyed = app->GetUniverse().EmpireKnownDestroyedObjectIDs(app->EmpireID());
        for (const auto* field : objects.allRaw<Field>()) {
            if (destroyed.contains(field->ID()))
                continue;
            const auto* size = field->GetMeter(MeterType::METER_SIZE);
            const auto* type = GetFieldType(field->FieldTypeName());
            field_ids.push_back(field->ID());
            field_positions.push_back(Position(*field));
            field_radii.push_back(size ? size->Initial() : 0.0f);
            field_types.push_back(ToGodot(field->FieldTypeName()));
            field_graphics.push_back(ToGodot(type && !type->Graphic().empty() ? type->Graphic()
                                                                            : std::string{"fields/ion_storm.png"}));
        }

        // Supply: each empire's supplied systems and the lanes its supply
        // crosses (traversals are directed; keep one per lane and empire).
        const auto& supply = app->GetSupplyManager();
        for (const auto& [empire_id, system_ids_supplied] : supply.FleetSupplyableSystemIDs()) {
            for (const int sys_id : system_ids_supplied) {
                if (const auto it = system_index.find(sys_id); it != system_index.end()) {
                    supply_systems.push_back(it->second);
                    supply_system_owners.push_back(empire_id);
                }
            }
        }
        for (const auto& [empire_id, traversals] : supply.SupplyStarlaneTraversals()) {
            std::unordered_set<int64_t> seen;
            for (const auto& [from_id, to_id] : traversals) {
                const auto from = system_index.find(from_id);
                const auto to = system_index.find(to_id);
                if (from == system_index.end() || to == system_index.end())
                    continue;
                const int lo = std::min(from->second, to->second);
                const int hi = std::max(from->second, to->second);
                if (!seen.insert((static_cast<int64_t>(lo) << 32) | static_cast<uint32_t>(hi)).second)
                    continue;
                supply_lanes.push_back(lo);
                supply_lanes.push_back(hi);
                supply_lane_owners.push_back(empire_id);
            }
        }
    }

    godot::Dictionary snapshot;
    snapshot["system_ids"] = system_ids;
    snapshot["system_positions"] = system_positions;
    snapshot["system_star_types"] = system_star_types;
    snapshot["lanes"] = lanes;
    snapshot["fleet_ids"] = fleet_ids;
    snapshot["fleet_positions"] = fleet_positions;
    snapshot["fleet_owner_ids"] = fleet_owner_ids;
    snapshot["supply_systems"] = supply_systems;
    snapshot["supply_system_owners"] = supply_system_owners;
    snapshot["supply_lanes"] = supply_lanes;
    snapshot["supply_lane_owners"] = supply_lane_owners;
    snapshot["field_ids"] = field_ids;
    snapshot["field_positions"] = field_positions;
    snapshot["field_radii"] = field_radii;
    snapshot["field_types"] = field_types;
    snapshot["field_graphics"] = field_graphics;
    return snapshot;
}

godot::Dictionary FOUniverse::get_empire_resources() {
    godot::Dictionary result;
    const auto* app = ClientApp::GetApp();
    if (!app)
        return result;
    const auto& context = app->GetContext();
    const auto empire = context.GetEmpire(app->EmpireID());
    if (!empire)
        return result;
    result["industry"] = empire->GetIndustryPool().TotalOutput();
    result["industry_spent"] = empire->GetProductionQueue().TotalPPsSpent();
    result["pp_stockpile"] = empire->GetIndustryPool().Stockpile();
    result["research"] = empire->GetResearchPool().TotalOutput();
    result["research_spent"] = empire->GetResearchQueue().TotalRPsSpent();
    const float influence = empire->GetInfluencePool().Stockpile();
    result["influence"] = influence;
    result["influence_change"] = empire->GetInfluenceQueue().ExpectedNewStockpileAmount() - influence;
    result["population"] = empire->GetPopulationPool().Population();
    const auto& destroyed = context.ContextUniverse().EmpireKnownDestroyedObjectIDs(empire->EmpireID());
    int ships = 0;
    for (const auto* ship : context.ContextObjects().allRaw<Ship>())
        if (ship->OwnedBy(empire->EmpireID()) && !destroyed.contains(ship->ID()))
            ++ships;
    result["ships"] = ships;
    const auto* detection = empire->GetMeter("METER_DETECTION_STRENGTH");
    result["detection"] = detection ? detection->Current() : 0.0f;
    result["eliminated"] = empire->Eliminated();
    result["won"] = empire->Won();
    return result;
}

namespace {
    // Meters the planet panel shows: the meter, and the target or maximum it
    // grows towards (METER_ENUM_END: none).
    constexpr std::array<std::pair<MeterType, MeterType>, 13> PLANET_METERS{{
        {MeterType::METER_POPULATION,   MeterType::METER_TARGET_POPULATION},
        {MeterType::METER_INDUSTRY,     MeterType::METER_TARGET_INDUSTRY},
        {MeterType::METER_RESEARCH,     MeterType::METER_TARGET_RESEARCH},
        {MeterType::METER_INFLUENCE,    MeterType::METER_TARGET_INFLUENCE},
        {MeterType::METER_CONSTRUCTION, MeterType::METER_TARGET_CONSTRUCTION},
        {MeterType::METER_HAPPINESS,    MeterType::METER_TARGET_HAPPINESS},
        {MeterType::METER_SUPPLY,       MeterType::METER_MAX_SUPPLY},
        {MeterType::METER_STOCKPILE,    MeterType::METER_MAX_STOCKPILE},
        {MeterType::METER_DEFENSE,      MeterType::METER_MAX_DEFENSE},
        {MeterType::METER_SHIELD,       MeterType::METER_MAX_SHIELD},
        {MeterType::METER_TROOPS,       MeterType::METER_MAX_TROOPS},
        {MeterType::METER_DETECTION,    MeterType::NUM_METER_TYPES},
        {MeterType::METER_STEALTH,      MeterType::NUM_METER_TYPES},
    }};

    bool IsScrapping(const OrderSet& orders, int object_id) {
        for (const auto& [order_id, order] : orders)
            if (auto scrap = std::dynamic_pointer_cast<ScrapOrder>(order); scrap && scrap->ObjectID() == object_id)
                return true;
        return false;
    }
}

godot::Dictionary FOUniverse::get_planet_detail(int planet_id) {
    godot::Dictionary result;
    const auto* app = ClientApp::GetApp();
    const auto* planet = Lookup<Planet>(planet_id);
    if (!app || !planet)
        return result;
    const auto& context = app->GetContext();
    result["id"] = planet_id;
    result["name"] = ToGodot(planet->PublicName(app->EmpireID(), context.ContextUniverse()));
    result["type"] = ToGodot(::to_string(planet->Type()));
    result["size"] = ToGodot(::to_string(planet->Size()));
    result["species"] = ToGodot(planet->SpeciesName());
    result["focus"] = ToGodot(planet->Focus());
    result["owner_id"] = planet->Owner();
    result["own"] = !planet->Unowned() && planet->OwnedBy(app->EmpireID());
    const auto owner = context.GetEmpire(planet->Owner());
    result["owner_name"] = owner ? ToGodot(owner->Name()) : godot::String();
    if (owner) {
        const auto c = owner->Color();
        result["owner_color"] = godot::Color::from_rgba8(c[0], c[1], c[2], c[3]);
    }
    result["environment"] = planet->SpeciesName().empty() ? godot::String() :
        ToGodot(::to_string(planet->EnvironmentForSpecies(context.species)));

    godot::Array meters;
    for (const auto& [type, target_type] : PLANET_METERS) {
        const auto* meter = planet->GetMeter(type);
        if (!meter)
            continue;
        const auto* target = target_type != MeterType::NUM_METER_TYPES ? planet->GetMeter(target_type) : nullptr;
        godot::Dictionary entry;
        entry["meter"] = ToGodot(::to_string(type));
        entry["now"] = meter->Initial();
        entry["next"] = meter->Current();
        entry["target"] = target ? target->Current() : meter->Current();
        meters.push_back(entry);
    }
    result["meters"] = meters;

    godot::Array buildings;
    for (const auto* building : context.ContextObjects().findRaw<Building>(planet->BuildingIDs())) {
        if (!building)
            continue;
        godot::Dictionary entry;
        entry["id"] = building->ID();
        entry["type"] = ToGodot(building->BuildingTypeName());
        entry["name"] = ToGodot(building->PublicName(app->EmpireID(), context.ContextUniverse()));
        const auto* type = GetBuildingType(building->BuildingTypeName());
        entry["icon"] = type ? ToGodot(type->Icon()) : godot::String();
        entry["scrapping"] = IsScrapping(app->Orders(), building->ID());
        buildings.push_back(entry);
    }
    result["buildings"] = buildings;

    godot::Array specials;
    for (const auto& [name, turn_capacity] : planet->Specials()) {
        godot::Dictionary entry;
        entry["name"] = ToGodot(name);
        const auto* special = GetSpecial(name);
        entry["icon"] = special ? ToGodot(special->Graphic()) : godot::String();
        entry["capacity"] = turn_capacity.second;
        specials.push_back(entry);
    }
    result["specials"] = specials;
    return result;
}
