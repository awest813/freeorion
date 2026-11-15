#include "FOObjects.h"

#include <godot_cpp/core/class_db.hpp>

#include "../../ClientApp.h"
#include "../../../Empire/Empire.h"
#include "../../../universe/Building.h"
#include "../../../universe/Field.h"
#include "../../../universe/ShipPart.h"
#include "../../../universe/Species.h"
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
        bool include_destroyed = false;

        bool Destroyed(const UniverseObject& object) const {
            return universe.DestroyedObjectIds().contains(object.ID()) ||
                (viewer != ALL_EMPIRES && universe.EmpireKnownDestroyedObjectIDs(viewer).contains(object.ID()));
        }

        bool Skip(const UniverseObject& object) const {
            if (own_only && (viewer == ALL_EMPIRES || object.Owner() != viewer))
                return true;
            return !include_destroyed && Destroyed(object);
        }

        // "visible" this turn, "seen" before, or "destroyed" (GG's object
        // list visibility filter).
        const char* VisibilityName(const UniverseObject& object) const {
            if (Destroyed(object))
                return "destroyed";
            if (viewer == ALL_EMPIRES || object.OwnedBy(viewer))
                return "visible";
            return universe.GetObjectVisibilityByEmpire(object.ID(), viewer) >= Visibility::VIS_BASIC_VISIBILITY ?
                "visible" : "seen";
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
            row["visibility"] = VisibilityName(object);
            row["x"] = object.X();
            row["y"] = object.Y();
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
                // More meters, as columns to choose (GG's object list has them all).
                row["target_population"] = MeterValue(*planet, MeterType::METER_TARGET_POPULATION);
                row["construction"] = MeterValue(*planet, MeterType::METER_CONSTRUCTION);
                row["stockpile"] = MeterValue(*planet, MeterType::METER_STOCKPILE);
                row["max_defense"] = MeterValue(*planet, MeterType::METER_MAX_DEFENSE);
                row["max_shield"] = MeterValue(*planet, MeterType::METER_MAX_SHIELD);
                row["max_troops"] = MeterValue(*planet, MeterType::METER_MAX_TROOPS);
                row["rebels"] = MeterValue(*planet, MeterType::METER_REBEL_TROOPS);
                row["detection"] = MeterValue(*planet, MeterType::METER_DETECTION);
                row["stealth"] = MeterValue(*planet, MeterType::METER_STEALTH);
                const auto empire = context.GetEmpire(planet->Owner());
                row["capital"] = empire && empire->CapitalID() == planet->ID();
                bool homeworld = false;
                for (const auto& [species, homeworlds] : context.species.GetSpeciesHomeworldsMap())
                    homeworld = homeworld || homeworlds.contains(planet->ID());
                row["homeworld"] = homeworld;
                // How well the player's capital species would live here.
                const auto viewer_empire = context.GetEmpire(viewer);
                const auto* capital = viewer_empire ? objects.getRaw<Planet>(viewer_empire->CapitalID()) : nullptr;
                const auto* capital_species = capital ? context.species.GetSpecies(capital->SpeciesName()) : nullptr;
                row["environment"] = capital_species ?
                    ToGodot(::to_string(capital_species->GetPlanetEnvironment(planet->Type()))) : godot::String();
                std::string specials;
                for (const auto& [name, turn_capacity] : planet->Specials())
                    specials += (specials.empty() ? "" : ", ") + UserString(name);
                row["specials"] = ToGodot(specials);
                const int attacked = planet->LastTurnAttackedByShip();
                row["last_attacked"] = attacked > 0 ? attacked : 0;
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
                int colony_ships = 0;
                for (const auto* ship : objects.findRaw<Ship>(fleet->ShipIDs())) {
                    if (!ship)
                        continue;
                    structure += MeterValue(*ship, MeterType::METER_STRUCTURE);
                    max_structure += MeterValue(*ship, MeterType::METER_MAX_STRUCTURE);
                    if (ship->CanColonize(universe, context.species))
                        ++colony_ships;
                }
                row["structure"] = structure;
                row["max_structure"] = max_structure;
                // Colony and outpost ships, and turns since the fleet was formed
                // (0 for ships built or split off this turn).
                row["colony_ships"] = colony_ships;
                row["armed"] = fleet->HasArmedShips(context);
                row["can_colonize"] = colony_ships > 0;
                row["speed"] = fleet->Speed(objects);
                row["fuel"] = fleet->Fuel(objects);
                row["age"] = fleet->AgeInTurns(context.current_turn);
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
                row["armed"] = ship->IsArmed(context);
                row["can_colonize"] = ship->CanColonize(universe, context.species);
                row["hull"] = design ? ToGodot(UserString(design->Hull())) : godot::String();
                row["parts"] = design ? static_cast<int>(design->PartCount()) : 0;
                row["cost"] = design ? design->ProductionCost(ship->Owner(), INVALID_OBJECT_ID, context) : 0.0f;
                row["speed"] = MeterValue(*ship, MeterType::METER_SPEED);
                row["fuel"] = MeterValue(*ship, MeterType::METER_FUEL);
                rows.push_back(row);
            }
            return rows;
        }

        // Fields: their type and size; "located" at the nearest known system.
        godot::Array Fields() const {
            godot::Array rows;
            for (const auto* field : objects.allRaw<Field>()) {
                if (Skip(*field))
                    continue;
                auto row = Row(*field);
                row["name"] = ToGodot(UserString(field->FieldTypeName()));
                row["field_type"] = ToGodot(field->FieldTypeName());
                row["size"] = MeterValue(*field, MeterType::METER_SIZE);
                double best = -1.0;
                for (const auto* system : objects.allRaw<System>()) {
                    const double dx = system->X() - field->X(), dy = system->Y() - field->Y();
                    const double d = dx * dx + dy * dy;
                    if (best < 0.0 || d < best) {
                        best = d;
                        row["system_id"] = system->ID();
                        row["system_name"] = ToGodot(system->PublicName(viewer, universe));
                    }
                }
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
    ClassDB::bind_static_method(get_class_static(), D_METHOD("list_objects", "kind", "own_only", "include_destroyed"),
                                &FOObjects::list_objects, DEFVAL(false), DEFVAL(false));
}

godot::Array FOObjects::list_objects(const godot::String& kind, bool own_only, bool include_destroyed) {
    const auto* app = ClientApp::GetApp();
    if (!app)
        return {};
    try {
        const auto& context = app->GetContext();
        const Lister lister{context, context.ContextUniverse(), context.ContextObjects(), app->EmpireID(), own_only,
                            include_destroyed};
        if (kind == "planets")   return lister.Planets();
        if (kind == "fleets")    return lister.Fleets();
        if (kind == "ships")     return lister.Ships();
        if (kind == "buildings") return lister.Buildings();
        if (kind == "fields")    return lister.Fields();
        if (kind == "systems")   return own_only ? lister.OwnSystems() : lister.Systems();
        ErrorLogger() << "FOObjects::list_objects: unknown kind " << kind.utf8().get_data();
    } catch (const std::exception& e) {
        ErrorLogger() << "FOObjects::list_objects: " << e.what();
    }
    return {};
}
