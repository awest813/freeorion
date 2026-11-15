#include "FOViews.h"

#include <unordered_map>
#include <unordered_set>
#include <algorithm>
#include <cstdint>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include "../../ClientApp.h"
#include "../../../Empire/Empire.h"
#include "../../../universe/Fleet.h"
#include "../../../universe/Planet.h"
#include "../../../universe/System.h"
#include "../../../universe/Universe.h"
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
    ClassDB::bind_static_method(cls, D_METHOD("get_system_ids"), &FOUniverse::get_system_ids);
    ClassDB::bind_static_method(cls, D_METHOD("get_fleet_ids"), &FOUniverse::get_fleet_ids);
    ClassDB::bind_static_method(cls, D_METHOD("get_planet_ids"), &FOUniverse::get_planet_ids);
    ClassDB::bind_static_method(cls, D_METHOD("get_empire_color", "empire_id"), &FOUniverse::get_empire_color);
    ClassDB::bind_static_method(cls, D_METHOD("get_empire_name", "empire_id"), &FOUniverse::get_empire_name);
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

    if (const auto* app = ClientApp::GetApp()) {
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
    }

    godot::Dictionary snapshot;
    snapshot["system_ids"] = system_ids;
    snapshot["system_positions"] = system_positions;
    snapshot["system_star_types"] = system_star_types;
    snapshot["lanes"] = lanes;
    snapshot["fleet_ids"] = fleet_ids;
    snapshot["fleet_positions"] = fleet_positions;
    snapshot["fleet_owner_ids"] = fleet_owner_ids;
    return snapshot;
}
