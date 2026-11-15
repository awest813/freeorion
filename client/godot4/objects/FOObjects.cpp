#include "FOObjects.h"

#include <godot_cpp/core/class_db.hpp>

#include "../../ClientApp.h"
#include "../../../Empire/Empire.h"
#include "../../../universe/Building.h"
#include "../../../universe/Fleet.h"
#include "../../../universe/Planet.h"
#include "../../../universe/Ship.h"
#include "../../../universe/ShipDesign.h"
#include "../../../universe/ShipHull.h"
#include "../../../universe/System.h"
#include "../../../universe/Universe.h"
#include "../../../util/i18n.h"
#include "../../../util/Logger.h"

namespace {
    godot::String ToGodot(std::string_view s)
    { return godot::String::utf8(s.data(), static_cast<int>(s.size())); }

    float MeterValue(const UniverseObject& object, MeterType type) {
        const auto* meter = object.GetMeter(type);
        return meter ? meter->Current() : 0.0f;
    }

    std::string_view AggressionName(FleetAggression aggression) {
        switch (aggression) {
        case FleetAggression::FLEET_PASSIVE:     return "passive";
        case FleetAggression::FLEET_DEFENSIVE:   return "defensive";
        case FleetAggression::FLEET_OBSTRUCTIVE: return "obstructive";
        case FleetAggression::FLEET_AGGRESSIVE:  return "aggressive";
        default:                                 return "";
        }
    }

    struct Lister {
        const ScriptingContext& context;
        const Universe& universe;
        const ObjectMap& objects;
        int viewer;
        bool own_only;

        bool Skip(const UniverseObject& object) const {
            if (own_only && (viewer == ALL_EMPIRES || object.Owner() != viewer))
                return true;
            const auto& destroyed = universe.DestroyedObjectIds();
            return destroyed.contains(object.ID()) ||
                (viewer != ALL_EMPIRES && universe.EmpireKnownDestroyedObjectIDs(viewer).contains(object.ID()));
        }

        godot::String Name(int id) const {
            const auto* object = objects.getRaw(id);
            return object ? ToGodot(object->PublicName(viewer, universe)) : godot::String();
        }

        godot::Dictionary Row(const UniverseObject& object) const {
            godot::Dictionary row;
            row["id"] = object.ID();
            row["name"] = ToGodot(object.PublicName(viewer, universe));
            const int owner = object.Owner();
            row["owner_id"] = owner;
            const auto empire = context.GetEmpire(owner);
            row["owner_name"] = empire ? ToGodot(empire->Name()) : godot::String();
            if (empire) {
                const auto c = empire->Color();
                row["owner_color"] = godot::Color::from_rgba8(c[0], c[1], c[2], c[3]);
            } else {
                row["owner_color"] = godot::Color(0.6f, 0.6f, 0.6f, 1.0f);
            }
            row["system_id"] = object.SystemID();
            row["system_name"] = object.SystemID() != INVALID_OBJECT_ID ? Name(object.SystemID()) : godot::String();
            return row;
        }

        godot::Array Planets() const {
            godot::Array rows;
            for (const auto* planet : objects.allRaw<Planet>()) {
                if (Skip(*planet))
                    continue;
                auto row = Row(*planet);
                row["type"] = ToGodot(::to_string(planet->Type()));
                row["size"] = ToGodot(::to_string(planet->Size()));
                row["species"] = ToGodot(planet->SpeciesName());
                row["focus"] = ToGodot(planet->Focus());
                row["population"] = MeterValue(*planet, MeterType::METER_POPULATION);
                row["industry"] = MeterValue(*planet, MeterType::METER_INDUSTRY);
                row["research"] = MeterValue(*planet, MeterType::METER_RESEARCH);
                row["influence"] = MeterValue(*planet, MeterType::METER_INFLUENCE);
                row["stability"] = MeterValue(*planet, MeterType::METER_HAPPINESS);
                row["supply"] = MeterValue(*planet, MeterType::METER_SUPPLY);
                row["defense"] = MeterValue(*planet, MeterType::METER_DEFENSE);
                row["shield"] = MeterValue(*planet, MeterType::METER_SHIELD);
                row["troops"] = MeterValue(*planet, MeterType::METER_TROOPS);
                rows.push_back(row);
            }
            return rows;
        }

        godot::Array Fleets() const {
            godot::Array rows;
            for (const auto* fleet : objects.allRaw<Fleet>()) {
                if (Skip(*fleet))
                    continue;
                auto row = Row(*fleet);
                row["ships"] = static_cast<int>(fleet->ShipIDs().size());
                const int destination = fleet->FinalDestinationID();
                const bool moving = destination != INVALID_OBJECT_ID && destination != fleet->SystemID();
                row["destination_id"] = moving ? destination : INVALID_OBJECT_ID;
                row["destination"] = moving ? Name(destination) : godot::String();
                int eta = 0;
                if (moving) {
                    const auto turns = fleet->ETA(context).first;
                    eta = (turns == Fleet::ETA_NEVER || turns == Fleet::ETA_UNKNOWN ||
                           turns == Fleet::ETA_OUT_OF_RANGE) ? -1 : static_cast<int>(turns);
                }
                row["eta"] = eta;
                // In transit: the next system on the way stands in for the location.
                if (fleet->SystemID() == INVALID_OBJECT_ID && fleet->NextSystemID() != INVALID_OBJECT_ID)
                    row["system_name"] = Name(fleet->NextSystemID());
                row["moving"] = fleet->SystemID() == INVALID_OBJECT_ID;
                row["aggression"] = ToGodot(AggressionName(fleet->Aggression()));
                float structure = 0.0f, max_structure = 0.0f;
                for (const auto* ship : objects.findRaw<Ship>(fleet->ShipIDs())) {
                    if (!ship)
                        continue;
                    structure += MeterValue(*ship, MeterType::METER_STRUCTURE);
                    max_structure += MeterValue(*ship, MeterType::METER_MAX_STRUCTURE);
                }
                row["structure"] = structure;
                row["max_structure"] = max_structure;
                rows.push_back(row);
            }
            return rows;
        }

        godot::Array Ships() const {
            godot::Array rows;
            for (const auto* ship : objects.allRaw<Ship>()) {
                if (Skip(*ship))
                    continue;
                auto row = Row(*ship);
                const auto* design = universe.GetShipDesign(ship->DesignID());
                row["design"] = design ? ToGodot(design->Name(true)) : godot::String();
                godot::String icon;
                if (design && !design->Icon().empty())
                    icon = ToGodot(design->Icon());
                else if (const auto* hull = design ? GetShipHull(design->Hull()) : nullptr)
                    icon = ToGodot(hull->Icon());
                row["icon"] = icon;
                row["fleet_id"] = ship->FleetID();
                row["fleet_name"] = Name(ship->FleetID());
                row["species"] = ToGodot(ship->SpeciesName());
                row["structure"] = MeterValue(*ship, MeterType::METER_STRUCTURE);
                row["max_structure"] = MeterValue(*ship, MeterType::METER_MAX_STRUCTURE);
                rows.push_back(row);
            }
            return rows;
        }

        godot::Array Buildings() const {
            godot::Array rows;
            for (const auto* building : objects.allRaw<Building>()) {
                if (Skip(*building))
                    continue;
                auto row = Row(*building);
                row["building_type"] = ToGodot(building->BuildingTypeName());
                row["planet_id"] = building->PlanetID();
                row["planet_name"] = Name(building->PlanetID());
                rows.push_back(row);
            }
            return rows;
        }

        godot::Array Systems() const {
            godot::Array rows;
            for (const auto* system : objects.allRaw<System>()) {
                if (Skip(*system))
                    continue;
                auto row = Row(*system);
                row["star"] = ToGodot(::to_string(system->GetStarType()));
                row["planets"] = static_cast<int>(system->PlanetIDs().size());
                row["fleets"] = static_cast<int>(system->FleetIDs().size());
                rows.push_back(row);
            }
            return rows;
        }

        // Systems belong to no one: "own" ones have one of the player's planets.
        godot::Array OwnSystems() const {
            godot::Array rows;
            for (const auto* system : objects.allRaw<System>()) {
                bool own = false;
                for (const auto* planet : objects.findRaw<Planet>(system->PlanetIDs()))
                    own = own || (planet && planet->Owner() == viewer && viewer != ALL_EMPIRES);
                if (!own || universe.DestroyedObjectIds().contains(system->ID()))
                    continue;
                auto row = Row(*system);
                row["star"] = ToGodot(::to_string(system->GetStarType()));
                row["planets"] = static_cast<int>(system->PlanetIDs().size());
                row["fleets"] = static_cast<int>(system->FleetIDs().size());
                rows.push_back(row);
            }
            return rows;
        }
    };
}

void FOObjects::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    ClassDB::bind_static_method(get_class_static(), D_METHOD("list_objects", "kind", "own_only"),
                                &FOObjects::list_objects, DEFVAL(false));
}

godot::Array FOObjects::list_objects(const godot::String& kind, bool own_only) {
    const auto* app = ClientApp::GetApp();
    if (!app)
        return {};
    try {
        const auto& context = app->GetContext();
        const Lister lister{context, context.ContextUniverse(), context.ContextObjects(), app->EmpireID(), own_only};
        if (kind == "planets")   return lister.Planets();
        if (kind == "fleets")    return lister.Fleets();
        if (kind == "ships")     return lister.Ships();
        if (kind == "buildings") return lister.Buildings();
        if (kind == "systems")   return own_only ? lister.OwnSystems() : lister.Systems();
        ErrorLogger() << "FOObjects::list_objects: unknown kind " << kind.utf8().get_data();
    } catch (const std::exception& e) {
        ErrorLogger() << "FOObjects::list_objects: " << e.what();
    }
    return {};
}
