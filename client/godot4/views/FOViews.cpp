#include "FOViews.h"

#include <set>
#include <tuple>
#include <unordered_map>
#include <unordered_set>
#include <algorithm>
#include <cstdint>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include "../../ClientApp.h"
#include "../../../Empire/Empire.h"
#include "../../../Empire/EmpireManager.h"
#include "../../../Empire/Supply.h"
#include "../../../universe/Building.h"
#include "../../../universe/Effect.h"
#include "../../../universe/BuildingType.h"
#include "../../../universe/Field.h"
#include "../../../universe/FieldType.h"
#include "../../../universe/Fleet.h"
#include "../../../universe/Pathfinder.h"
#include "../../../universe/Planet.h"
#include "../../../universe/Ship.h"
#include "../../../universe/ShipDesign.h"
#include "../../../universe/ShipHull.h"
#include "../../../universe/ShipPart.h"
#include "../../../universe/Special.h"
#include "../../../universe/Species.h"
#include "../../../universe/System.h"
#include "../../../universe/Tech.h"
#include "../../../universe/Universe.h"
#include "../../../util/i18n.h"
#include "../../../util/Logger.h"
#include "../../../util/Order.h"
#include "../../../util/OrderSet.h"
#include "../../../util/SitRepEntry.h"
#include "../../../util/ranges.h"

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
    ClassDB::bind_method(D_METHOD("get_owner_id"), &FOSystem::get_owner_id);
}

int FOSystem::get_owner_id() const {
    const auto* sys = Lookup<System>(m_id);
    return sys ? sys->Owner() : ALL_EMPIRES;
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
    ClassDB::bind_method(D_METHOD("preview_route", "dest_system_id", "append"), &FOFleet::preview_route,
                         DEFVAL(false));
    ClassDB::bind_method(D_METHOD("get_blockade"), &FOFleet::get_blockade);
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

namespace {
    // A move path as points, and the points where turns end.
    void PathPoints(const std::vector<MovePathNode>& path, godot::PackedVector2Array& points,
                    godot::PackedVector2Array& turn_ends)
    {
        for (const auto& node : path) {
            const godot::Vector2 at{static_cast<float>(node.x), static_cast<float>(node.y)};
            if (points.is_empty() || points[points.size() - 1] != at)
                points.push_back(at);
            if (node.turn_end)
                turn_ends.push_back(at);
        }
    }

    // Turn ends' numbers and warnings, as GG's ETA markers: the turn the
    // fleet gets there, and 1 if a blockade stops it there, 2 if the path has
    // left the player's unobstructed supply by then (\a unobstructed null:
    // not checked, e.g. other empires' fleets).
    void TurnMarks(const std::vector<MovePathNode>& path, const std::set<int>* unobstructed,
                   godot::PackedInt32Array& etas, godot::PackedInt32Array& flags)
    {
        bool out_of_supply = false;
        for (const auto& node : path) {
            if (unobstructed && node.object_id != INVALID_OBJECT_ID && !unobstructed->contains(node.object_id))
                out_of_supply = true;
            if (!node.turn_end)
                continue;
            etas.push_back(node.eta);
            flags.push_back(node.post_blockade ? 1 : out_of_supply ? 2 : 0);
        }
    }
}

godot::Dictionary FOFleet::preview_route(int dest_system_id, bool append) const {
    godot::Dictionary result;
    const auto* fleet = Lookup<Fleet>(m_id);
    auto* app = ClientApp::GetApp();
    if (!fleet || !app)
        return result;
    const auto& context = app->GetContext();
    // Checked first, as Check logs an error for each (and this runs on hover).
    if (!fleet->OwnedBy(app->EmpireID()) || !context.ContextObjects().getRaw<System>(dest_system_id))
        return result;
    if (!FleetMoveOrder::Check(app->EmpireID(), m_id, dest_system_id, append, context))
        return result;
    // As FleetMoveOrder builds the route.
    int start = fleet->SystemID();
    if (start == INVALID_OBJECT_ID)
        start = fleet->NextSystemID();
    const auto& current = fleet->TravelRoute();
    if (append && !current.empty())
        start = current.back();
    auto path = context.ContextUniverse().GetPathfinder().ShortestPath(start, dest_system_id, app->EmpireID()).first;
    if (path.empty())
        return result;
    if (path.front() == fleet->SystemID())
        path.erase(path.begin());
    std::vector<int> route;
    if (append)
        route.assign(current.begin(), current.end());
    for (const int id : path)
        if (route.empty() || route.back() != id)
            route.push_back(id);
    const auto move_path = fleet->MovePath(route, false, context);
    godot::PackedVector2Array points, turn_ends;
    points.push_back(Position(*fleet));
    PathPoints(move_path, points, turn_ends);
    godot::PackedInt32Array turn_etas, turn_flags;
    if (const auto empire = context.GetEmpire(app->EmpireID())) {
        const auto unobstructed = empire->SupplyUnobstructedSystems();
        const std::set<int> systems(unobstructed.begin(), unobstructed.end());
        TurnMarks(move_path, &systems, turn_etas, turn_flags);
    }
    result["turn_etas"] = turn_etas;
    result["turn_flags"] = turn_flags;
    const auto eta = fleet->ETA(move_path).first;
    const bool never = eta == Fleet::ETA_NEVER || eta == Fleet::ETA_UNKNOWN || eta == Fleet::ETA_OUT_OF_RANGE;
    result["systems"] = ToPacked(route);
    result["points"] = points;
    result["turn_ends"] = turn_ends;
    result["eta"] = never ? -1 : static_cast<int>(eta);
    return result;
}

godot::Dictionary FOFleet::get_blockade() const {
    godot::Dictionary result;
    result["blockaded"] = false;
    const auto* fleet = Lookup<Fleet>(m_id);
    const auto* app = ClientApp::GetApp();
    if (!fleet || !app)
        return result;
    const auto& context = app->GetContext();
    const auto* system = context.ContextObjects().getRaw<System>(fleet->SystemID());
    if (!system || !fleet->Blockaded(context))
        return result;
    result["blockaded"] = true;
    result["monster"] = fleet->Unowned();
    godot::PackedStringArray exits;
    for (const int target : system->Starlanes()) {
        if (fleet->BlockadedAtSystem(fleet->SystemID(), target, context))
            continue;
        if (const auto* to = context.ContextObjects().getRaw<System>(target))
            exits.push_back(ToGodot(to->ApparentName(app->EmpireID(), context.ContextUniverse())));
    }
    result["exits"] = exits;
    return result;
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
    ClassDB::bind_method(D_METHOD("get_stats"), &FOShip::get_stats);
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

godot::Dictionary FOShip::get_stats() const {
    godot::Dictionary stats;
    const auto* ship = Lookup<Ship>(m_id);
    const auto* app = ClientApp::GetApp();
    if (!ship || !app)
        return stats;
    const auto& context = app->GetContext();
    const auto& universe = context.ContextUniverse();
    const auto meter = [ship](MeterType type) {
        const auto* m = ship->UniverseObject::GetMeter(type);
        return m ? static_cast<double>(m->Initial()) : 0.0;
    };
    stats["damage"] = ship->TotalWeaponsShipDamage(context, 0.0f, true);
    stats["destroy"] = ship->TotalWeaponsFighterDamage(context, true);
    stats["fighters"] = static_cast<double>(ship->FighterCount());
    stats["fighters_max"] = static_cast<double>(ship->FighterMax());
    stats["troops"] = ship->TroopCapacity(universe);
    stats["colony"] = ship->ColonyCapacity(universe);
    stats["structure"] = meter(MeterType::METER_STRUCTURE);
    stats["max_structure"] = meter(MeterType::METER_MAX_STRUCTURE);
    stats["shield"] = meter(MeterType::METER_SHIELD);
    stats["fuel"] = meter(MeterType::METER_FUEL);
    stats["max_fuel"] = meter(MeterType::METER_MAX_FUEL);
    stats["speed"] = meter(MeterType::METER_SPEED);
    stats["design_id"] = ship->DesignID();
    stats["scrapping"] = ship->OrderedScrapped();
    return stats;
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
    ClassDB::bind_static_method(cls, D_METHOD("get_ship_detail", "ship_id"), &FOUniverse::get_ship_detail);
    ClassDB::bind_static_method(cls, D_METHOD("get_stat_records"), &FOUniverse::get_stat_records);
    ClassDB::bind_static_method(cls, D_METHOD("get_planet_suitability", "planet_id"),
                                &FOUniverse::get_planet_suitability);
    ClassDB::bind_static_method(cls, D_METHOD("get_meter_accounting", "object_id", "meter_name"),
                                &FOUniverse::get_meter_accounting);
    ClassDB::bind_static_method(cls, D_METHOD("get_playable_species"), &FOUniverse::get_playable_species);
    ClassDB::bind_static_method(cls, D_METHOD("get_empire_colors"), &FOUniverse::get_empire_colors);
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
    godot::PackedByteArray fleet_blockaded;
    godot::PackedStringArray fleet_heads;
    godot::PackedInt32Array fleet_ship_counts;
    godot::PackedByteArray fleet_stale;
    godot::PackedInt32Array system_owner_ids;
    godot::Array fleet_paths;
    godot::Array fleet_turn_ends;
    godot::Array fleet_turn_etas;
    godot::Array fleet_turn_flags;
    godot::PackedInt32Array supply_systems;
    godot::PackedInt32Array supply_system_owners;
    godot::PackedInt32Array supply_lanes;
    godot::PackedInt32Array supply_lane_owners;
    godot::PackedInt32Array field_ids;
    godot::PackedVector2Array field_positions;
    godot::PackedFloat32Array field_radii;
    godot::PackedStringArray field_types;
    godot::PackedStringArray field_graphics;
    godot::PackedVector2Array detection_positions;
    godot::PackedFloat32Array detection_radii;
    godot::PackedInt32Array detection_owner_ids;

    if (auto* app = ClientApp::GetApp()) {
        const auto& objects = app->GetUniverse().Objects();

        std::unordered_map<int, int> system_index;
        for (const auto* sys : objects.allRaw<System>()) {
            system_index.emplace(sys->ID(), static_cast<int>(system_ids.size()));
            system_ids.push_back(sys->ID());
            system_positions.push_back(Position(*sys));
            system_star_types.push_back(static_cast<int>(sys->GetStarType()));
        }

        // Each system's owner: the empire owning its planets (the first one
        // found when several do), for owner-coloured circles and names.
        for (const auto* sys : objects.allRaw<System>()) {
            int owner = ALL_EMPIRES;
            for (const auto* planet : objects.findRaw<const Planet>(sys->PlanetIDs())) {
                if (planet && !planet->Unowned()) {
                    owner = planet->Owner();
                    break;
                }
            }
            system_owner_ids.push_back(owner);
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

        // Fleets, and the paths of those under way (each turn's end marked).
        const auto& destroyed = app->GetUniverse().EmpireKnownDestroyedObjectIDs(app->EmpireID());
        const auto& context = app->GetContext();
        std::set<int> own_supply;
        if (const auto empire = context.GetEmpire(app->EmpireID())) {
            const auto unobstructed = empire->SupplyUnobstructedSystems();
            own_supply.insert(unobstructed.begin(), unobstructed.end());
        }
        for (const auto* fleet : objects.allRaw<Fleet>()) {
            if (destroyed.contains(fleet->ID()) || fleet->Empty())
                continue;
            fleet_ids.push_back(fleet->ID());
            fleet_positions.push_back(Position(*fleet));
            fleet_owner_ids.push_back(fleet->Owner());
            godot::PackedVector2Array points, turn_ends;
            godot::PackedInt32Array turn_etas, turn_flags;
            const int destination = fleet->FinalDestinationID();
            if (destination != INVALID_OBJECT_ID && destination != fleet->SystemID() &&
                !fleet->TravelRoute().empty())
            {
                points.push_back(Position(*fleet));
                const auto move_path = fleet->MovePath(false, context);
                PathPoints(move_path, points, turn_ends);
                TurnMarks(move_path, fleet->OwnedBy(app->EmpireID()) ? &own_supply : nullptr,
                          turn_etas, turn_flags);
            }
            fleet_paths.push_back(points);
            fleet_turn_ends.push_back(turn_ends);
            fleet_turn_etas.push_back(turn_etas);
            fleet_turn_flags.push_back(turn_flags);
            // The fleet's icon, as GG's FleetButton picks it: monster,
            // warship, colony, outpost, lander, else scout.
            {
                const auto& u = context.ContextUniverse();
                const bool armed = fleet->CanDamageShips(context);
                const char* head = "scout";
                if (fleet->HasMonsters(u))           head = armed ? "monster" : "monster-harmless";
                else if (armed)                      head = "warship";
                else if (fleet->HasColonyShips(u))   head = "colony";
                else if (fleet->HasOutpostShips(u))  head = "outpost";
                else if (fleet->HasTroopShips(u))    head = "lander";
                fleet_heads.push_back(head);
                fleet_ship_counts.push_back(static_cast<int>(fleet->NumShips()));
            }
            fleet_blockaded.push_back(fleet->SystemID() != INVALID_OBJECT_ID && fleet->Blockaded(context) ? 1 : 0);
            // Not seen this turn: drawn as a ghost.
            const int seen = app->GetUniverse().GetObjectVisibilityTurnByEmpire(fleet->ID(), app->EmpireID());
            fleet_stale.push_back(!fleet->OwnedBy(app->EmpireID()) && seen != INVALID_GAME_TURN &&
                                  seen < context.current_turn ? 1 : 0);
        }

        // Fields (ion storms, nebulae, ...): their size meter is the radius.
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

        // Detection ranges of every empire's objects the player knows, as
        // GG draws them: one circle per object that detects (a fleet's ships
        // share one place; keep each circle once per owner).
        {
            std::set<std::tuple<int, int, int, int>> seen;
            for (const auto* object : objects.allRaw()) {
                if (object->Unowned() || destroyed.contains(object->ID()))
                    continue;
                const auto* meter = object->GetMeter(MeterType::METER_DETECTION);
                const float radius = meter ? meter->Initial() : 0.0f;
                if (radius <= 0.0f)
                    continue;
                const auto key = std::tuple{static_cast<int>(object->X()), static_cast<int>(object->Y()),
                                            static_cast<int>(radius), object->Owner()};
                if (!seen.insert(key).second)
                    continue;
                detection_positions.push_back(godot::Vector2(static_cast<float>(object->X()),
                                                             static_cast<float>(object->Y())));
                detection_radii.push_back(radius);
                detection_owner_ids.push_back(object->Owner());
            }
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
    snapshot["fleet_paths"] = fleet_paths;
    snapshot["fleet_blockaded"] = fleet_blockaded;
    snapshot["fleet_heads"] = fleet_heads;
    snapshot["fleet_ship_counts"] = fleet_ship_counts;
    snapshot["fleet_stale"] = fleet_stale;
    snapshot["system_owner_ids"] = system_owner_ids;
    snapshot["fleet_turn_ends"] = fleet_turn_ends;
    snapshot["fleet_turn_etas"] = fleet_turn_etas;
    snapshot["fleet_turn_flags"] = fleet_turn_flags;
    snapshot["supply_systems"] = supply_systems;
    snapshot["supply_system_owners"] = supply_system_owners;
    snapshot["supply_lanes"] = supply_lanes;
    snapshot["supply_lane_owners"] = supply_lane_owners;
    snapshot["field_ids"] = field_ids;
    snapshot["field_positions"] = field_positions;
    snapshot["field_radii"] = field_radii;
    snapshot["field_types"] = field_types;
    snapshot["field_graphics"] = field_graphics;
    snapshot["detection_positions"] = detection_positions;
    snapshot["detection_radii"] = detection_radii;
    snapshot["detection_owner_ids"] = detection_owner_ids;
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
    // Census, as the GG population tooltip: population by species and by
    // species tag.
    {
        godot::Dictionary by_species, by_tag;
        for (const auto* planet : context.ContextObjects().allRaw<Planet>()) {
            if (!planet->OwnedBy(empire->EmpireID()) || planet->SpeciesName().empty())
                continue;
            const auto* meter = planet->GetMeter(MeterType::METER_POPULATION);
            const double pop = meter ? meter->Current() : 0.0;
            if (pop <= 0.0)
                continue;
            const auto name = ToGodot(planet->SpeciesName());
            by_species[name] = double(by_species.get(name, 0.0)) + pop;
            if (const auto* species = context.species.GetSpecies(planet->SpeciesName())) {
                for (const auto& tag : species->Tags()) {
                    const auto key = ToGodot(tag);
                    by_tag[key] = double(by_tag.get(key, 0.0)) + pop;
                }
            }
        }
        result["population_by_species"] = by_species;
        result["population_by_tag"] = by_tag;
    }
    {
        const auto& queue = empire->GetProductionQueue();
        result["stockpile_capacity"] = queue.StockpileCapacity(context.ContextObjects());
        result["stockpile_expected"] = queue.ExpectedNewStockpileAmount();
        result["research_queue_spent"] = empire->GetResearchQueue().TotalRPsSpent();
    }
    const auto& destroyed = context.ContextUniverse().EmpireKnownDestroyedObjectIDs(empire->EmpireID());
    // Ships, and how many are armed, carry troops or colonists, or fighters
    // (the GG top bar's ships tooltip).
    int ships = 0, armed = 0, troops = 0, colony = 0, carriers = 0;
    for (const auto* ship : context.ContextObjects().allRaw<Ship>()) {
        if (!ship->OwnedBy(empire->EmpireID()) || destroyed.contains(ship->ID()))
            continue;
        ++ships;
        if (ship->IsArmed(context))
            ++armed;
        if (ship->HasTroops(context.ContextUniverse()))
            ++troops;
        if (ship->CanColonize(context.ContextUniverse(), context.species))
            ++colony;
        if (ship->HasFighters(context.ContextUniverse()))
            ++carriers;
    }
    result["ships"] = ships;
    result["ships_armed"] = armed;
    result["ships_unarmed"] = ships - armed;
    result["ships_troops"] = troops;
    result["ships_colony"] = colony;
    result["ships_carriers"] = carriers;
    // A system where industry goes unspent, to show it (GG's wasted PP button).
    int wasted_system = INVALID_OBJECT_ID;
    for (const auto& ids : empire->GetProductionQueue().ObjectsWithWastedPP(empire->GetIndustryPool())) {
        for (const int id : ids) {
            const auto* object = context.ContextObjects().getRaw(id);
            if (object && object->SystemID() != INVALID_OBJECT_ID) {
                wasted_system = object->SystemID();
                break;
            }
        }
        if (wasted_system != INVALID_OBJECT_ID)
            break;
    }
    result["wasted_pp_system"] = wasted_system;
    const auto* detection = empire->GetMeter("METER_DETECTION_STRENGTH");
    result["detection"] = detection ? detection->Current() : 0.0f;
    result["capital_id"] = empire->CapitalID();
    result["eliminated"] = empire->Eliminated();
    result["won"] = empire->Won();
    return result;
}

namespace {
    // Meters the planet panel shows: the meter, and the target or maximum it
    // grows towards (METER_ENUM_END: none).
    constexpr std::array<std::pair<MeterType, MeterType>, 14> PLANET_METERS{{
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
        {MeterType::METER_REBEL_TROOPS, MeterType::NUM_METER_TYPES},
        {MeterType::METER_DETECTION,    MeterType::NUM_METER_TYPES},
        {MeterType::METER_STEALTH,      MeterType::NUM_METER_TYPES},
    }};

    // Ship meters and their maximum, in the order of the GG ship panel.
    constexpr std::array<std::pair<MeterType, MeterType>, 9> SHIP_METERS{{
        {MeterType::METER_STRUCTURE,    MeterType::METER_MAX_STRUCTURE},
        {MeterType::METER_SHIELD,       MeterType::METER_MAX_SHIELD},
        {MeterType::METER_FUEL,         MeterType::METER_MAX_FUEL},
        {MeterType::METER_DETECTION,    MeterType::NUM_METER_TYPES},
        {MeterType::METER_STEALTH,      MeterType::NUM_METER_TYPES},
        {MeterType::METER_SPEED,        MeterType::NUM_METER_TYPES},
        {MeterType::METER_INDUSTRY,     MeterType::METER_TARGET_INDUSTRY},
        {MeterType::METER_RESEARCH,     MeterType::METER_TARGET_RESEARCH},
        {MeterType::METER_INFLUENCE,    MeterType::METER_TARGET_INFLUENCE},
    }};

    // Meter rows for get_planet_detail() and get_ship_detail().
    template <typename Meters>
    godot::Array MeterRows(const UniverseObject& object, const Meters& types) {
        godot::Array meters;
        for (const auto& [type, target_type] : types) {
            const auto* meter = object.GetMeter(type);
            if (!meter)
                continue;
            const auto* target = target_type != MeterType::NUM_METER_TYPES ? object.GetMeter(target_type) : nullptr;
            godot::Dictionary entry;
            entry["meter"] = ToGodot(::to_string(type));
            entry["now"] = meter->Initial();
            entry["next"] = meter->Current();
            // Only meters that move towards a target or maximum have one.
            if (target)
                entry["target"] = target->Current();
            // The breakdown explains the target or maximum where there is one.
            entry["accounting_meter"] = ToGodot(::to_string(target ? target_type : type));
            meters.push_back(entry);
        }
        return meters;
    }

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

    result["meters"] = MeterRows(*planet, PLANET_METERS);

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
        entry["description"] = type ? ToGodot(type->Description()) : godot::String();
        buildings.push_back(entry);
    }
    result["buildings"] = buildings;

    // Buildings queued here, with their progress (GG's buildings panel).
    godot::Array producing;
    if (const auto empire = context.GetEmpire(app->EmpireID())) {
        for (const auto& element : empire->GetProductionQueue()) {
            if (element.location != planet_id || element.item.build_type != BuildType::BT_BUILDING ||
                element.to_be_removed)
            { continue; }
            godot::Dictionary entry;
            entry["type"] = ToGodot(element.item.name);
            const auto* type = GetBuildingType(element.item.name);
            entry["icon"] = type ? ToGodot(type->Icon()) : godot::String();
            entry["progress"] = element.progress;
            entry["turns_left"] = element.turns_left_to_completion;
            producing.push_back(entry);
        }
    }
    result["producing"] = producing;

    // Status (own planets), as the GG side panel's status icon.
    godot::PackedStringArray status;
    std::string status_icon;
    if (planet->OwnedBy(app->EmpireID())) {
        const auto name = planet->Name();
        if (!context.supply.SystemHasFleetSupply(planet->SystemID(), planet->Owner(), true,
                                                           context.diplo_statuses))
        {
            status.push_back(ToGodot(boost::io::str(FlexibleFormat(UserString("OPTIONS_DB_UI_PLANET_STATUS_NO_SUPPLY")) % name)));
            status_icon = "icons/planet_status_supply.png";
        }
        if (planet->LastTurnAttackedByShip() == context.current_turn - 1) {
            status.push_back(ToGodot(boost::io::str(FlexibleFormat(UserString("OPTIONS_DB_UI_PLANET_STATUS_ATTACKED")) % name)));
            status_icon = "icons/planet_status_attacked.png";
        }
        if (planet->LastTurnConquered() == context.current_turn - 1) {
            status.push_back(ToGodot(boost::io::str(FlexibleFormat(UserString("OPTIONS_DB_UI_PLANET_STATUS_CONQUERED")) % name)));
            status_icon = "icons/planet_status_conquered.png";
        }
        const auto* happiness = planet->GetMeter(MeterType::METER_HAPPINESS);
        const auto* population = planet->GetMeter(MeterType::METER_POPULATION);
        if (happiness && population && happiness->Current() <= 5 && population->Current() > 0) {
            status.push_back(ToGodot(boost::io::str(FlexibleFormat(UserString("OPTIONS_DB_UI_PLANET_STATUS_UNHAPPY")) % name)));
            status_icon = "icons/planet_status_unhappy.png";
        }
        if (status.size() > 1)
            status_icon = "icons/planet_status_warning.png";
    }
    result["status"] = status;
    result["status_icon"] = ToGodot(status_icon);

    // What is known of a planet not seen now (GG's planet stealth tooltip).
    std::string visibility_text;
    const int empire_id = app->EmpireID();
    if (empire_id != ALL_EMPIRES) {
        const auto& universe = context.ContextUniverse();
        const auto visibility = universe.GetObjectVisibilityByEmpire(planet_id, empire_id);
        const auto& turns = universe.GetObjectVisibilityTurnsByEmpire(planet_id, empire_id);
        const auto empire = context.GetEmpire(empire_id);
        const auto* strength_meter = empire ? empire->GetMeter("METER_DETECTION_STRENGTH") : nullptr;
        const float strength = strength_meter ? strength_meter->Current() : 0.0f;
        const auto* stealth_meter = planet->GetMeter(MeterType::METER_STEALTH);
        const float stealth = stealth_meter ? stealth_meter->Initial() : 0.0f;
        const auto turn_of = [&turns](Visibility vis)
        { return vis == Visibility::VIS_BASIC_VISIBILITY ? turns.basic : turns.partial; };
        const auto detection = [&]() {
            if (stealth > strength)
                return boost::io::str(FlexibleFormat(UserString("PL_APPARENT_STEALTH_EXCEEDS_DETECTION")) %
                                      static_cast<int>(stealth) % static_cast<int>(strength));
            return boost::io::str(FlexibleFormat(UserString("PL_APPARENT_STEALTH_DOES_NOT_EXCEED_DETECTION")) %
                                  static_cast<int>(strength));
        };
        if (visibility == Visibility::VIS_NO_VISIBILITY) {
            const int seen = turn_of(Visibility::VIS_BASIC_VISIBILITY);
            visibility_text = UserString("PL_NO_VISIBILITY") + "  " + (seen != INVALID_GAME_TURN ?
                boost::io::str(FlexibleFormat(UserString("PL_LAST_TURN_SEEN")) % seen) : UserString("PL_NEVER_SEEN"));
            const auto* system = context.ContextObjects().getRaw<System>(planet->SystemID());
            visibility_text += "\n" + (system && system->GetVisibility(empire_id, universe) <= Visibility::VIS_BASIC_VISIBILITY ?
                UserString("PL_NOT_IN_RANGE") : detection());
        } else if (visibility == Visibility::VIS_BASIC_VISIBILITY) {
            const int scanned = turn_of(Visibility::VIS_PARTIAL_VISIBILITY);
            visibility_text = UserString("PL_BASIC_VISIBILITY") + "  " + (scanned != INVALID_GAME_TURN ?
                boost::io::str(FlexibleFormat(UserString("PL_LAST_TURN_SCANNED")) % scanned) : UserString("PL_NEVER_SCANNED"));
            visibility_text += "\n" + detection();
        }
    }
    result["visibility_text"] = ToGodot(visibility_text);

    godot::Array specials;
    for (const auto& [name, turn_capacity] : planet->Specials()) {
        godot::Dictionary entry;
        entry["name"] = ToGodot(name);
        const auto* special = GetSpecial(name);
        entry["icon"] = special ? ToGodot(special->Graphic()) : godot::String();
        entry["capacity"] = turn_capacity.second;
        entry["turn_added"] = turn_capacity.first;
        specials.push_back(entry);
    }
    result["specials"] = specials;
    return result;
}

godot::Dictionary FOUniverse::get_ship_detail(int ship_id) {
    godot::Dictionary result;
    const auto* app = ClientApp::GetApp();
    const auto* ship = Lookup<Ship>(ship_id);
    if (!app || !ship)
        return result;
    const auto& context = app->GetContext();
    const auto& universe = context.ContextUniverse();
    result["id"] = ship_id;
    result["name"] = ToGodot(ship->PublicName(app->EmpireID(), universe));
    result["species"] = ToGodot(ship->SpeciesName());
    result["owner_id"] = ship->Owner();
    result["own"] = !ship->Unowned() && ship->OwnedBy(app->EmpireID());
    const auto owner = context.GetEmpire(ship->Owner());
    result["owner_name"] = owner ? ToGodot(owner->Name()) : godot::String();
    if (owner) {
        const auto c = owner->Color();
        result["owner_color"] = godot::Color::from_rgba8(c[0], c[1], c[2], c[3]);
    }
    result["fleet_id"] = ship->FleetID();
    result["age"] = ship->AgeInTurns(context.current_turn);
    result["scrapping"] = IsScrapping(app->Orders(), ship_id);
    const auto* design = universe.GetShipDesign(ship->DesignID());
    result["design_id"] = ship->DesignID();
    result["design"] = design ? ToGodot(design->Name()) : godot::String();
    result["hull"] = design ? ToGodot(design->Hull()) : godot::String();
    result["icon"] = design ? ToGodot(design->Icon()) : godot::String();
    if (const auto* hull = design ? GetShipHull(design->Hull()) : nullptr) {
        if (result["icon"].operator godot::String().is_empty())
            result["icon"] = ToGodot(hull->Icon());
    }

    result["meters"] = MeterRows(*ship, SHIP_METERS);

    // Combat and cargo, as UI/FleetWnd.cpp's ShipDataPanel::StatValue().
    godot::Array stats;
    // Each stat's breakdown, as GG's ship damage and fighters tooltips:
    // lines of [label, value text].
    godot::Array weapon_lines, fighter_lines;
    if (design) {
        const ScriptingContext source_context{context, ScriptingContext::Source{}, ship};
        std::map<std::string, int> counted;
        for (const auto& part_name : design->Parts())
            if (!part_name.empty())
                ++counted[part_name];
        for (const auto& [part_name, count] : counted) {
            const auto* part = GetShipPart(part_name);
            if (!part)
                continue;
            godot::Array line;
            const auto label = (count > 1 ? std::to_string(count) + " × " : std::string{}) + UserString(part_name);
            if (part->Class() == ShipPartClass::PC_DIRECT_WEAPON) {
                const float damage = ship->WeaponPartShipDamage(part, source_context);
                const float shot = ship->WeaponPartFighterDamage(part, source_context);
                line.push_back(ToGodot(label));
                line.push_back(ToGodot(DoubleToString(damage * count, 3, false) + " / " +
                                       std::to_string(static_cast<int>(shot * count))));
                weapon_lines.push_back(line);
            } else if (part->Class() == ShipPartClass::PC_FIGHTER_HANGAR) {
                const float capacity = ship->CurrentPartMeterValue(MeterType::METER_MAX_CAPACITY, part_name);
                const float damage = ship->CurrentPartMeterValue(MeterType::METER_SECONDARY_STAT, part_name);
                line.push_back(ToGodot(label));
                line.push_back(ToGodot(boost::io::str(FlexibleFormat(UserString("SHIP_PANEL_HANGAR_LINE")) %
                                                      static_cast<int>(capacity * count) % DoubleToString(damage, 3, false))));
                fighter_lines.push_back(line);
            } else if (part->Class() == ShipPartClass::PC_FIGHTER_BAY) {
                const float launch = ship->CurrentPartMeterValue(MeterType::METER_CAPACITY, part_name);
                line.push_back(ToGodot(label));
                line.push_back(ToGodot(boost::io::str(FlexibleFormat(UserString("SHIP_PANEL_BAY_LINE")) %
                                                      static_cast<int>(launch * count))));
                fighter_lines.push_back(line);
            }
        }
    }
    const auto stat = [&stats](const char* key, double value, const godot::Array& lines = {}) {
        godot::Dictionary entry;
        entry["stat"] = key;
        entry["value"] = value;
        entry["breakdown"] = lines;
        stats.push_back(entry);
    };
    if (ship->IsArmed(context)) {
        stat("damage", ship->TotalWeaponsShipDamage(context, 0.0f, true), weapon_lines);
        stat("destroy", ship->TotalWeaponsFighterDamage(context, true));
    }
    if (ship->HasFighters(universe))
        stat("fighters", ship->FighterCount(), fighter_lines);
    if (ship->HasTroops(universe))
        stat("troops", ship->TroopCapacity(universe));
    if (ship->CanColonize(universe, context.species))
        stat("colony", ship->ColonyCapacity(universe));
    result["stats"] = stats;

    // Parts once per name, with how many and their meters.
    godot::Array parts;
    if (design) {
        std::vector<std::pair<std::string, int>> counts;
        for (const auto& part_name : design->Parts()) {
            if (part_name.empty())
                continue;
            auto it = std::find_if(counts.begin(), counts.end(),
                                   [&part_name](const auto& entry) { return entry.first == part_name; });
            if (it == counts.end())
                counts.emplace_back(part_name, 1);
            else
                ++it->second;
        }
        const auto part_meter = [ship](MeterType type, const std::string& name) {
            const auto* meter = ship->GetPartMeter(type, name);
            return meter ? static_cast<double>(meter->Initial()) : -1.0;
        };
        for (const auto& [part_name, count] : counts) {
            godot::Dictionary entry;
            entry["name"] = ToGodot(part_name);
            entry["count"] = count;
            const auto* part = GetShipPart(part_name);
            entry["class"] = part ? ToGodot(::to_string(part->Class())) : godot::String();
            entry["icon"] = part ? ToGodot(part->Icon()) : godot::String();
            // -1 where the part has no such meter.
            entry["capacity"] = part_meter(MeterType::METER_CAPACITY, part_name);
            entry["max_capacity"] = part_meter(MeterType::METER_MAX_CAPACITY, part_name);
            entry["secondary"] = part_meter(MeterType::METER_SECONDARY_STAT, part_name);
            entry["max_secondary"] = part_meter(MeterType::METER_MAX_SECONDARY_STAT, part_name);
            parts.push_back(entry);
        }
    }
    result["parts"] = parts;
    return result;
}

godot::Dictionary FOUniverse::get_stat_records() {
    godot::Dictionary result;
    const auto* app = ClientApp::GetApp();
    if (!app)
        return result;
    const auto& context = app->GetContext();
    for (const auto& [stat_name, empire_lines] : context.ContextUniverse().GetStatRecords()) {
        godot::Array lines;
        for (const auto& [empire_id, values_by_turn] : empire_lines) {
            godot::Dictionary line;
            line["empire_id"] = empire_id;
            const auto empire = context.GetEmpire(empire_id);
            line["name"] = empire ? ToGodot(empire->Name()) : godot::String();
            if (empire) {
                const auto c = empire->Color();
                line["color"] = godot::Color::from_rgba8(c[0], c[1], c[2], c[3]);
            } else {
                line["color"] = godot::Color(0.8f, 0.8f, 0.8f, 1.0f);
            }
            godot::PackedInt32Array turns;
            godot::PackedFloat64Array values;
            for (const auto& [turn, value] : values_by_turn) {
                turns.push_back(turn);
                values.push_back(value);
            }
            line["turns"] = turns;
            line["values"] = values;
            lines.push_back(line);
        }
        result[ToGodot(stat_name)] = lines;
    }
    return result;
}

namespace {
    // Species tags as UI/EncyclopediaDetailPanel.cpp reads them.
    constexpr std::string_view TAG_ALWAYS_REPORT = "CTRL_ALWAYS_REPORT";
    constexpr std::string_view TAG_EXTINCT = "CTRL_EXTINCT";

    // As ReportedSpeciesForPlanet() in UI/EncyclopediaDetailPanel.cpp.
    std::vector<std::string> ReportedSpecies(const Planet& planet, int empire_id, const ScriptingContext& context) {
        std::vector<std::string> result;
        const auto& species_manager = context.species;
        if (!planet.SpeciesName().empty() && species_manager.GetSpecies(planet.SpeciesName()))
            result.push_back(planet.SpeciesName());
        const auto empire = context.GetEmpire(empire_id);
        if (!empire)
            return result;
        for (const auto& [name, species] : species_manager.AllSpecies()) {
            if (species.HasTag(TAG_ALWAYS_REPORT)) {
                result.push_back(name);
            } else if (species.HasTag(TAG_EXTINCT)) {
                for (const auto& tech_name : empire->ResearchedTechs() | range_keys) {
                    const auto* tech = GetTech(tech_name);
                    if (tech && tech->HasTag(TAG_EXTINCT) && tech->HasTag(name)) {
                        result.push_back(name);
                        break;
                    }
                }
            }
        }
        for (const auto* owned : context.ContextObjects().allRaw<Planet>()) {
            if (!owned->OwnedBy(empire_id) || !owned->Populated() || owned->SpeciesName().empty())
                continue;
            const auto* species = species_manager.GetSpecies(owned->SpeciesName());
            if (species && species->CanColonize())
                result.push_back(owned->SpeciesName());
        }
        std::sort(result.begin(), result.end());
        result.erase(std::unique(result.begin(), result.end()), result.end());
        return result;
    }

    // Restores what GG's UniverseObjectSignalInhibitor guards.
    struct SignalInhibitor {
        explicit SignalInhibitor(Universe& universe) noexcept : u{universe} { u.InhibitUniverseObjectSignals(true); }
        ~SignalInhibitor() noexcept { u.InhibitUniverseObjectSignals(false); }
        Universe& u;
    };
}

godot::Array FOUniverse::get_planet_suitability(int planet_id) {
    godot::Array result;
    auto* app = ClientApp::GetApp();
    if (!app)
        return result;
    auto& context = app->GetContext();
    auto& universe = context.ContextUniverse();
    auto* planet = context.ContextObjects().getRaw<Planet>(planet_id);
    if (!planet)
        return result;
    const int empire_id = app->EmpireID();
    std::vector<std::tuple<float, std::string, PlanetEnvironment>> rows;
    try {
        const auto names = ReportedSpecies(*planet, empire_id, context);
        if (names.empty())
            return result;
        // Try each species on the planet, as SpeciesEnvByTargetPop() does,
        // then put the planet back as it was.
        const std::string original_species{planet->SpeciesName()};
        const int original_owner = planet->Owner();
        const float original_target = planet->GetMeter(MeterType::METER_TARGET_POPULATION)->Initial();
        const std::vector<int> ids{planet_id};
        {
            SignalInhibitor inhibitor{universe};
            for (const auto& name : names) {
                try {
                    planet->SetSpecies(name, context.current_turn, context.species);
                    planet->SetOwner(empire_id);
                    universe.ApplyMeterEffectsAndUpdateMeters(ids, context, false);
                    const auto* species = context.species.GetSpecies(name);
                    const auto environment = species ? species->GetPlanetEnvironment(planet->Type())
                                                     : PlanetEnvironment::PE_UNINHABITABLE;
                    const float target = environment == PlanetEnvironment::PE_UNINHABITABLE ? 0.0f :
                        planet->GetMeter(MeterType::METER_TARGET_POPULATION)->Current();
                    rows.emplace_back(target, name, environment);
                } catch (const std::exception& e) {
                    ErrorLogger() << "FOUniverse::get_planet_suitability: species " << name << ": " << e.what();
                }
            }
            planet->SetSpecies(original_species, context.current_turn, context.species);
            planet->SetOwner(original_owner);
            planet->GetMeter(MeterType::METER_TARGET_POPULATION)->Set(original_target, original_target);
        }
        universe.ApplyMeterEffectsAndUpdateMeters(ids, context, false);
    } catch (const std::exception& e) {
        ErrorLogger() << "FOUniverse::get_planet_suitability: " << e.what();
    }
    std::sort(rows.begin(), rows.end(), [](const auto& a, const auto& b) { return std::get<0>(a) > std::get<0>(b); });
    for (const auto& [target, name, environment] : rows) {
        godot::Dictionary entry;
        entry["species"] = ToGodot(name);
        const auto* species = context.species.GetSpecies(name);
        entry["icon"] = species ? ToGodot(species->Graphic()) : godot::String();
        entry["environment"] = ToGodot(::to_string(environment));
        entry["target_population"] = target;
        result.push_back(entry);
    }
    return result;
}

godot::Array FOUniverse::get_playable_species() {
    godot::Array result;
    const auto* app = ClientApp::GetApp();
    if (!app)
        return result;
    try {
        for (const auto& [name, species] : app->GetSpeciesManager().AllSpecies()) {
            if (!species.Playable())
                continue;
            godot::Dictionary entry;
            entry["name"] = ToGodot(name);
            entry["icon"] = ToGodot(species.Graphic());
            result.push_back(entry);
        }
    } catch (const std::exception& e) {
        // Content still being parsed, or failed to.
        ErrorLogger() << "FOUniverse::get_playable_species: " << e.what();
    }
    return result;
}

godot::PackedColorArray FOUniverse::get_empire_colors() {
    godot::PackedColorArray result;
    for (const auto& c : EmpireColors())
        result.push_back(godot::Color::from_rgba8(c[0], c[1], c[2], c[3]));
    return result;
}

namespace {
    // Label of one accounting entry, as UI/MeterBrowseWnd.cpp writes it.
    std::string AccountingLabel(const Effect::AccountingInfo& info, std::string name, const ScriptingContext& context) {
        const auto templ = [&info](std::string_view fallback) -> const std::string&
        { return UserString(info.custom_label.empty() ? std::string{fallback} : info.custom_label); };
        const auto format = [&](std::string_view fallback) {
            return boost::io::str(FlexibleFormat(templ(fallback)) % name % UserString(info.specific_cause));
        };
        const auto* source = context.ContextObjects().getRaw(info.source_id);
        switch (info.cause_type) {
        case EffectsCauseType::ECT_TECH:
        case EffectsCauseType::ECT_POLICY: {
            const auto empire = source ? context.GetEmpire(source->Owner()) : nullptr;
            name = empire ? empire->Name() : std::string{};
            return format(info.cause_type == EffectsCauseType::ECT_TECH ? "TT_TECH" : "TT_POLICY");
        }
        case EffectsCauseType::ECT_BUILDING:   return format("TT_BUILDING");
        case EffectsCauseType::ECT_FIELD:      return format("TT_FIELD");
        case EffectsCauseType::ECT_SPECIAL:    return format("TT_SPECIAL");
        case EffectsCauseType::ECT_SPECIES:    return format("TT_SPECIES");
        case EffectsCauseType::ECT_SHIP_HULL:  return format("TT_SHIP_HULL");
        case EffectsCauseType::ECT_SHIP_PART:  return format("TT_SHIP_PART");
        case EffectsCauseType::ECT_INHERENT:   return UserString("TT_INHERENT");
        default:                               return templ("TT_UNKNOWN");
        }
    }

    MeterType MeterTypeByName(const std::string& name) {
        for (int i = 0; i < static_cast<int>(MeterType::NUM_METER_TYPES); ++i)
            if (::to_string(static_cast<MeterType>(i)) == name)
                return static_cast<MeterType>(i);
        return MeterType::INVALID_METER_TYPE;
    }
}

godot::Dictionary FOUniverse::get_meter_accounting(int object_id, const godot::String& meter_name) {
    godot::Dictionary result;
    const auto* app = ClientApp::GetApp();
    if (!app)
        return result;
    try {
        const auto& context = app->GetContext();
        const auto type = MeterTypeByName(meter_name.utf8().get_data());
        const auto* object = context.ContextObjects().getRaw(object_id);
        const auto* meter = object ? object->GetMeter(type) : nullptr;
        if (!meter)
            return result;
        const auto& accounting = context.ContextUniverse().GetEffectAccountingMap();
        const auto object_it = accounting.find(object_id);
        if (object_it == accounting.end())
            return result;
        const auto meter_it = object_it->second.find(type);
        if (meter_it == object_it->second.end())
            return result;
        const auto& infos = meter_it->second;

        godot::Array lines;
        int combined = 0;
        for (std::size_t i = 0; i < infos.size(); ++i) {
            const auto& info = infos[i];
            const auto* source = context.ContextObjects().getRaw(info.source_id);
            std::string name = source ? source->Name() : std::string{};
            float change = info.meter_change;
            if (info.cause_type == EffectsCauseType::ECT_BUILDING) {
                const auto* building = dynamic_cast<const Building*>(source);
                const auto* planet = building ? context.ContextObjects().getRaw<Planet>(building->PlanetID()) : nullptr;
                name = planet ? planet->Name() : std::string{};
                // Identical effects of many buildings make one line: "3 x".
                if (i + 1 < infos.size() && infos[i + 1].cause_type == info.cause_type &&
                    std::fabs(infos[i + 1].meter_change - info.meter_change) < 0.001f &&
                    infos[i + 1].specific_cause == info.specific_cause)
                {
                    ++combined;
                    continue;
                }
                if (combined > 0) {
                    ++combined;
                    name = std::to_string(combined) + " x";
                    change *= static_cast<float>(combined);
                    combined = 0;
                }
            }
            godot::Dictionary line;
            const auto label = AccountingLabel(info, std::move(name), context);
            line["label"] = ToGodot(label);
            line["change"] = change;
            lines.push_back(line);
        }
        result["meter"] = meter_name;
        result["total"] = meter->Current();
        result["lines"] = lines;
    } catch (const std::exception& e) {
        ErrorLogger() << "FOUniverse::get_meter_accounting: " << e.what();
    }
    return result;
}
