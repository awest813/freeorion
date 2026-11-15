#include "FOPlanetActions.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

#include <map>
#include <numeric>

#include "../../ClientApp.h"
#include "../../../Empire/Empire.h"
#include "../../../universe/Building.h"
#include "../../../universe/Conditions.h"
#include "../../../universe/Fleet.h"
#include "../../../universe/Planet.h"
#include "../../../universe/Ship.h"
#include "../../../universe/ShipDesign.h"
#include "../../../universe/Species.h"
#include "../../../universe/System.h"
#include "../../../universe/Universe.h"
#include "../../../universe/ValueRefs.h"
#include "../../../util/Logger.h"
#include "../../../util/Order.h"
#include "../../../util/OrderSet.h"

// The ship choices and checks follow UI/SidePanel.cpp.
namespace {
    godot::String ToGodot(std::string_view s)
    { return godot::String::utf8(s.data(), static_cast<int>(s.size())); }

    float Initial(const UniverseObject& object, MeterType type) {
        const auto* meter = object.GetMeter(type);
        return meter ? meter->Initial() : 0.0f;
    }

    // Own ship in the system, visible, not moving on and not ordered scrapped.
    bool IsAvailable(const Ship& ship, int system_id, int empire_id, const ScriptingContext& context) {
        const auto* fleet = context.ContextObjects().getRaw<Fleet>(ship.FleetID());
        return fleet && ship.SystemID() == system_id && ship.OwnedBy(empire_id) &&
            ship.GetVisibility(empire_id, context.ContextUniverse()) >= Visibility::VIS_PARTIAL_VISIBILITY &&
            !ship.OrderedScrapped() && fleet->FinalDestinationID() == INVALID_OBJECT_ID;
    }

    bool AvailableToColonize(const Ship& ship, int system_id, int empire_id, const ScriptingContext& context) {
        return IsAvailable(ship, system_id, empire_id, context) &&
            ship.CanColonize(context.ContextUniverse(), context.species) &&
            ship.OrderedColonizePlanet() == INVALID_OBJECT_ID;
    }

    bool AvailableToInvade(const Ship& ship, int system_id, int empire_id, const ScriptingContext& context) {
        return IsAvailable(ship, system_id, empire_id, context) &&
            ship.HasTroops(context.ContextUniverse()) &&
            ship.OrderedInvadePlanet() == INVALID_OBJECT_ID;
    }

    float ColonyCapacity(const Ship& ship, const Universe& universe) {
        const auto* design = universe.GetShipDesign(ship.DesignID());
        return design ? design->ColonyCapacity() : 0.0f;
    }

    // Colony ships colonise planets their species can live on; outpost ships
    // (no colonists) take the rest.
    bool CanColonizePlanetType(const Ship& ship, PlanetType type, const ScriptingContext& context) {
        if (type == PlanetType::INVALID_PLANET_TYPE)
            return false;
        const float capacity = ColonyCapacity(ship, context.ContextUniverse());
        if (capacity == 0.0f)
            return ship.CanColonize(context.ContextUniverse(), context.species);
        const auto* species = context.species.GetSpecies(ship.SpeciesName());
        if (!species)
            return false;
        const auto env = species->GetPlanetEnvironment(type);
        return env >= PlanetEnvironment::PE_HOSTILE && env <= PlanetEnvironment::PE_GOOD;
    }

    // Target population \a planet would have with \a species_name living on
    // it, by setting it temporarily and updating the meter estimates.
    float ProjectedTargetPopulation(Planet& planet, const std::string& species_name, int empire_id,
                                    ScriptingContext& context)
    {
        const auto* species = context.species.GetSpecies(species_name);
        if (!species || species->GetPlanetEnvironment(planet.Type()) == PlanetEnvironment::PE_UNINHABITABLE)
            return 0.0f;
        Universe& universe = context.ContextUniverse();
        universe.InhibitUniverseObjectSignals(true);
        const std::string orig_species{planet.SpeciesName()};
        const int orig_owner = planet.Owner();
        auto* target = planet.GetMeter(MeterType::METER_TARGET_POPULATION);
        const float orig_target = target ? target->Initial() : 0.0f;
        planet.SetOwner(empire_id);
        planet.SetSpecies(species_name, context.current_turn, context.species);
        if (target)
            target->Reset();
        universe.UpdateMeterEstimates(planet.ID(), context);
        const float projected = target ? target->Current() : 0.0f;
        planet.SetOwner(orig_owner);
        planet.SetSpecies(orig_species, context.current_turn, context.species);
        if (target)
            target->Set(orig_target, orig_target);
        universe.UpdateMeterEstimates(planet.ID(), context);
        universe.InhibitUniverseObjectSignals(false);
        return projected;
    }

    struct ColonyChoice {
        const Ship* ship = nullptr;
        float target_population = 0.0f;
    };

    // The available colony ship in the planet's system giving the largest
    // colony (any outpost ship for planets no colonists can live on).
    ColonyChoice ChooseColonyShip(Planet& planet, int empire_id, ScriptingContext& context) {
        ColonyChoice best;
        const auto* system = context.ContextObjects().getRaw<System>(planet.SystemID());
        if (!system || empire_id == ALL_EMPIRES)
            return best;
        float best_target = -1.0f;
        for (const auto* ship : context.ContextObjects().findRaw<const Ship>(system->ShipIDs())) {
            if (!ship || !AvailableToColonize(*ship, system->ID(), empire_id, context) ||
                !CanColonizePlanetType(*ship, planet.Type(), context))
            { continue; }
            const float target = ColonyCapacity(*ship, context.ContextUniverse()) > 0.0f ?
                ProjectedTargetPopulation(planet, ship->SpeciesName(), empire_id, context) : 0.0f;
            if (target > best_target) {
                best_target = target;
                best = {ship, target};
            }
        }
        return best;
    }

    // Troop ships in the system until they outnumber the defenders.
    std::vector<const Ship*> ChooseInvasionShips(const Planet& planet, int empire_id, const ScriptingContext& context) {
        std::vector<const Ship*> ships;
        const float defenders = Initial(planet, MeterType::METER_TROOPS);
        float troops = 0.0f;
        for (const auto* ship : context.ContextObjects().allRaw<Ship>()) {
            if (!ship || !AvailableToInvade(*ship, planet.SystemID(), empire_id, context))
                continue;
            troops += ship->TroopCapacity(context.ContextUniverse());
            ships.push_back(ship);
            if (troops > defenders)
                break;
        }
        return ships;
    }

    constexpr std::string_view TAG_BOMBARD_ALWAYS = "CTRL_ALWAYS_BOMBARD";
    constexpr std::string_view TAG_BOMBARD_PREFIX = "CTRL_BOMBARD_";

    // A ship bombards planets carrying one of its CTRL_BOMBARD_<TAG> tags,
    // or any planet with CTRL_ALWAYS_BOMBARD.
    bool BombardsPlanet(const Ship& ship, const Planet& planet, const ScriptingContext& context) {
        if (ship.HasTag(TAG_BOMBARD_ALWAYS, context))
            return true;
        const auto tags = ship.Tags(context);
        for (const auto& range : {tags.first, tags.second}) {
            for (std::string_view tag : range) {
                if (tag.substr(0, TAG_BOMBARD_PREFIX.size()) == TAG_BOMBARD_PREFIX &&
                    planet.HasTag(tag.substr(TAG_BOMBARD_PREFIX.size()), context))
                { return true; }
            }
        }
        return false;
    }

    std::vector<const Ship*> ChooseBombardShips(const Planet& planet, int empire_id, const ScriptingContext& context) {
        std::vector<const Ship*> ships;
        for (const auto* ship : context.ContextObjects().allRaw<Ship>()) {
            if (ship && IsAvailable(*ship, planet.SystemID(), empire_id, context) &&
                ship->CanBombard(context.ContextUniverse()) && BombardsPlanet(*ship, planet, context))
            { ships.push_back(ship); }
        }
        return ships;
    }

    // Own ships already set to bombard \a planet (orders persist over turns).
    std::vector<const Ship*> BombardingShips(const Planet& planet, int empire_id, const ScriptingContext& context) {
        std::vector<const Ship*> ships;
        for (const auto* ship : context.ContextObjects().allRaw<Ship>())
            if (ship && ship->OwnedBy(empire_id) && ship->OrderedBombardPlanet() == planet.ID())
                ships.push_back(ship);
        return ships;
    }

    template <typename OrderType, typename Pred>
    std::vector<int> PendingOrderIDs(const OrderSet& orders, Pred pred) {
        std::vector<int> ids;
        for (const auto& [order_id, order] : orders)
            if (auto typed = std::dynamic_pointer_cast<OrderType>(order); typed && pred(*typed))
                ids.push_back(order_id);
        return ids;
    }

    double AnnexationCost(const Planet& planet, const UniverseObject* source, const ScriptingContext& context) {
        const auto* species = context.species.GetSpecies(planet.SpeciesName());
        const auto* cost = species ? species->AnnexationCost() : nullptr;
        if (!cost)
            return 0.0;
        if (cost->ConstantExpr())
            return cost->Eval();
        if (!cost->SourceInvariant() && !source)
            return 0.0;
        ScriptingContext planet_context{context, ScriptingContext::Source{}, source};
        planet_context.condition_local_candidate = &planet;
        if (!planet_context.condition_root_candidate)
            planet_context.condition_root_candidate = &planet;
        return cost->Eval(planet_context);
    }

    const UniverseObject* EmpireSource(const Empire* empire, const Planet& planet, const ObjectMap& objects) {
        const UniverseObject* source = empire ? empire->Source(objects).get() : nullptr;
        return (!source && !planet.Unowned()) ? &planet : source;
    }

    void Rescind(const std::vector<int>& order_ids, ClientApp& app) {
        for (const int id : order_ids)
            app.Orders().RescindOrder(id, app.GetContext());
    }

    godot::Dictionary ColonizeAction(Planet& planet, int empire_id, ClientApp& app) {
        auto& context = app.GetContext();
        godot::Dictionary result;
        result["state"] = "";
        const auto pending = PendingOrderIDs<ColonizeOrder>(
            app.Orders(), [&](const ColonizeOrder& o) { return o.PlanetID() == planet.ID(); });
        if (!pending.empty()) {
            result["state"] = "pending";
            return result;
        }
        const bool visible = context.ContextUniverse().GetObjectVisibilityByEmpire(planet.ID(), empire_id) >=
            Visibility::VIS_PARTIAL_VISIBILITY;
        const bool populated = Initial(planet, MeterType::METER_POPULATION) > 0.0f;
        const bool free = planet.Unowned() || planet.OwnedBy(empire_id);
        if (!visible || populated || !free || planet.IsAboutToBeColonized())
            return result;
        const auto choice = ChooseColonyShip(planet, empire_id, context);
        if (!choice.ship)
            return result;
        const float capacity = ColonyCapacity(*choice.ship, context.ContextUniverse());
        // Outposts only go to unowned planets.
        if (capacity == 0.0f && !planet.Unowned())
            return result;
        result["state"] = "available";
        result["outpost"] = capacity == 0.0f;
        result["ship_id"] = choice.ship->ID();
        result["ship_name"] = ToGodot(choice.ship->Name());
        result["species"] = ToGodot(choice.ship->SpeciesName());
        result["capacity"] = capacity;
        result["target_population"] = choice.target_population;
        return result;
    }

    bool AtWarWith(const Planet& planet, int empire_id, const ScriptingContext& context) {
        if (planet.OwnedBy(empire_id))
            return false;
        if (planet.Unowned())
            return Initial(planet, MeterType::METER_POPULATION) > 0.0f;
        return context.ContextDiploStatus(empire_id, planet.Owner()) == DiplomaticStatus::DIPLO_WAR;
    }

    godot::Dictionary InvadeAction(const Planet& planet, int empire_id, ClientApp& app) {
        const auto& context = app.GetContext();
        godot::Dictionary result;
        result["state"] = "";
        result["defenders"] = Initial(planet, MeterType::METER_TROOPS);
        const auto pending = PendingOrderIDs<InvadeOrder>(
            app.Orders(), [&](const InvadeOrder& o) { return o.PlanetID() == planet.ID(); });
        if (!pending.empty()) {
            result["state"] = "pending";
            return result;
        }
        const bool visible = context.ContextUniverse().GetObjectVisibilityByEmpire(planet.ID(), empire_id) >=
            Visibility::VIS_PARTIAL_VISIBILITY;
        const bool shielded = Initial(planet, MeterType::METER_SHIELD) > 0.0f;
        if (!AtWarWith(planet, empire_id, context) || shielded || !visible || planet.IsAboutToBeInvaded())
            return result;
        const auto ships = ChooseInvasionShips(planet, empire_id, context);
        if (ships.empty())
            return result;
        float troops = 0.0f;
        for (const auto* ship : ships)
            troops += ship->TroopCapacity(context.ContextUniverse());
        result["state"] = "available";
        result["troops"] = troops;
        result["ships"] = static_cast<int>(ships.size());
        return result;
    }

    godot::Dictionary BombardAction(const Planet& planet, int empire_id, ClientApp& app) {
        const auto& context = app.GetContext();
        godot::Dictionary result;
        result["state"] = "";
        if (!BombardingShips(planet, empire_id, context).empty()) {
            result["state"] = "pending";
            return result;
        }
        const bool visible = context.ContextUniverse().GetObjectVisibilityByEmpire(planet.ID(), empire_id) >=
            Visibility::VIS_PARTIAL_VISIBILITY;
        if (!AtWarWith(planet, empire_id, context) || !visible)
            return result;
        const auto ships = ChooseBombardShips(planet, empire_id, context);
        if (ships.empty())
            return result;
        result["state"] = "available";
        result["ships"] = static_cast<int>(ships.size());
        return result;
    }

    godot::Dictionary AnnexAction(const Planet& planet, int empire_id, ClientApp& app) {
        const auto& context = app.GetContext();
        godot::Dictionary result;
        result["state"] = "";
        result["cost"] = 0.0;
        const auto* species = context.species.GetSpecies(planet.SpeciesName());
        const bool populated = Initial(planet, MeterType::METER_POPULATION) > 0.0f;
        if (planet.OwnedBy(empire_id) || !species || !populated || planet.IsAboutToBeInvaded())
            return result;
        const auto empire = context.GetEmpire(empire_id);
        const auto* source = EmpireSource(empire.get(), planet, context.ContextObjects());
        const ScriptingContext source_context{context, ScriptingContext::Source{}, source};
        const double cost = AnnexationCost(planet, source, source_context);
        result["cost"] = cost;
        const auto pending = PendingOrderIDs<AnnexOrder>(
            app.Orders(), [&](const AnnexOrder& o) { return o.PlanetID() == planet.ID(); });
        if (!pending.empty() || planet.IsAboutToBeAnnexed()) {
            result["state"] = "pending";
            return result;
        }
        const auto* condition = species->AnnexationCondition();
        if (!condition || !source_context.source || !condition->EvalOne(source_context, &planet)) {
            result["state"] = "restricted";
            return result;
        }
        // Other annexations and this turn's policy adoptions draw on the same IP.
        double committed = empire ? empire->ThisTurnAdoptedPoliciesCost(context) : 0.0;
        for (const auto& [order_id, order] : app.Orders())
            if (auto annex = std::dynamic_pointer_cast<AnnexOrder>(order))
                if (const auto* other = context.ContextObjects().getRaw<Planet>(annex->PlanetID()))
                    committed += AnnexationCost(*other, source, source_context);
        const double available = empire ? empire->ResourceStockpile(ResourceType::RE_INFLUENCE) : 0.0;
        result["state"] = committed + cost <= available ? "available" : "unaffordable";
        return result;
    }

    godot::Dictionary FocusAction(const Planet& planet, int empire_id, const ScriptingContext& context) {
        godot::Dictionary result;
        result["current"] = ToGodot(planet.Focus());
        godot::PackedStringArray options;
        godot::PackedStringArray icons;
        if (planet.OwnedBy(empire_id) && !planet.SpeciesName().empty()) {
            for (const auto& focus : planet.AvailableFoci(context)) {
                options.push_back(ToGodot(focus));
                icons.push_back(ToGodot(planet.FocusIcon(focus, context)));
            }
        }
        result["options"] = options;
        result["icons"] = icons;
        result["state"] = options.size() > 1 ? "available" : "";
        return result;
    }
}

void FOPlanetActions::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    const auto cls = get_class_static();
    ClassDB::bind_static_method(cls, D_METHOD("get_actions", "planet_id"), &FOPlanetActions::get_actions);
    ClassDB::bind_static_method(cls, D_METHOD("colonize", "planet_id", "ship_ids"), &FOPlanetActions::colonize,
                                DEFVAL(godot::PackedInt32Array()));
    ClassDB::bind_static_method(cls, D_METHOD("invade", "planet_id", "ship_ids"), &FOPlanetActions::invade,
                                DEFVAL(godot::PackedInt32Array()));
    ClassDB::bind_static_method(cls, D_METHOD("annex", "planet_id"), &FOPlanetActions::annex);
    ClassDB::bind_static_method(cls, D_METHOD("bombard", "planet_id"), &FOPlanetActions::bombard);
    ClassDB::bind_static_method(cls, D_METHOD("set_focus", "planet_id", "focus"), &FOPlanetActions::set_focus);
    ClassDB::bind_static_method(cls, D_METHOD("scrap", "object_id"), &FOPlanetActions::scrap);
    ClassDB::bind_static_method(cls, D_METHOD("is_scrapping", "object_id"), &FOPlanetActions::is_scrapping);
}

godot::Dictionary FOPlanetActions::get_actions(int planet_id) {
    godot::Dictionary result;
    auto* app = ClientApp::GetApp();
    if (!app || app->EmpireID() == ALL_EMPIRES)
        return result;
    try {
        auto* planet = app->GetContext().ContextObjects().getRaw<Planet>(planet_id);
        if (!planet)
            return result;
        const int empire_id = app->EmpireID();
        result["colonize"] = ColonizeAction(*planet, empire_id, *app);
        result["invade"] = InvadeAction(*planet, empire_id, *app);
        result["annex"] = AnnexAction(*planet, empire_id, *app);
        result["bombard"] = BombardAction(*planet, empire_id, *app);
        result["focus"] = FocusAction(*planet, empire_id, app->GetContext());
    } catch (const std::exception& e) {
        ErrorLogger() << "FOPlanetActions::get_actions(" << planet_id << "): " << e.what();
    }
    return result;
}

bool FOPlanetActions::colonize(int planet_id, const godot::PackedInt32Array& ship_ids) {
    auto* app = ClientApp::GetApp();
    if (!app || app->EmpireID() == ALL_EMPIRES)
        return false;
    try {
        auto& context = app->GetContext();
        const int empire_id = app->EmpireID();
        const auto pending = PendingOrderIDs<ColonizeOrder>(
            app->Orders(), [&](const ColonizeOrder& o) { return o.PlanetID() == planet_id; });
        if (!pending.empty()) {
            Rescind(pending, *app);
            return true;
        }
        auto* planet = context.ContextObjects().getRaw<Planet>(planet_id);
        if (!planet)
            return false;
        // A selected ship that can colonise it first, as GG's side panel.
        for (int64_t i = 0; i < ship_ids.size(); ++i) {
            const int ship_id = ship_ids[i];
            const auto* ship = context.ContextObjects().getRaw<Ship>(ship_id);
            if (ship && AvailableToColonize(*ship, planet->SystemID(), empire_id, context) &&
                CanColonizePlanetType(*ship, planet->Type(), context) &&
                ColonizeOrder::Check(empire_id, ship_id, planet_id, context))
            {
                app->Orders().IssueOrder<ColonizeOrder>(context, empire_id, ship_id, planet_id);
                return true;
            }
        }
        const auto choice = ChooseColonyShip(*planet, empire_id, context);
        if (!choice.ship || !ColonizeOrder::Check(empire_id, choice.ship->ID(), planet_id, context))
            return false;
        app->Orders().IssueOrder<ColonizeOrder>(context, empire_id, choice.ship->ID(), planet_id);
        return true;
    } catch (const std::exception& e) {
        ErrorLogger() << "FOPlanetActions::colonize(" << planet_id << "): " << e.what();
    }
    return false;
}

bool FOPlanetActions::invade(int planet_id, const godot::PackedInt32Array& ship_ids) {
    auto* app = ClientApp::GetApp();
    if (!app || app->EmpireID() == ALL_EMPIRES)
        return false;
    try {
        auto& context = app->GetContext();
        const int empire_id = app->EmpireID();
        const auto pending = PendingOrderIDs<InvadeOrder>(
            app->Orders(), [&](const InvadeOrder& o) { return o.PlanetID() == planet_id; });
        if (!pending.empty()) {
            Rescind(pending, *app);
            return true;
        }
        const auto* planet = context.ContextObjects().getRaw<Planet>(planet_id);
        if (!planet)
            return false;
        // The selected troop ships that can land, else enough of those there.
        std::vector<const Ship*> ships;
        for (int64_t i = 0; i < ship_ids.size(); ++i) {
            const auto* ship = context.ContextObjects().getRaw<Ship>(static_cast<int>(ship_ids[i]));
            if (ship && AvailableToInvade(*ship, planet->SystemID(), empire_id, context))
                ships.push_back(ship);
        }
        if (ships.empty())
            ships = ChooseInvasionShips(*planet, empire_id, context);
        bool issued = false;
        for (const auto* ship : ships) {
            if (!InvadeOrder::Check(empire_id, ship->ID(), planet_id, context))
                continue;
            app->Orders().IssueOrder<InvadeOrder>(context, empire_id, ship->ID(), planet_id);
            issued = true;
        }
        return issued;
    } catch (const std::exception& e) {
        ErrorLogger() << "FOPlanetActions::invade(" << planet_id << "): " << e.what();
    }
    return false;
}

bool FOPlanetActions::annex(int planet_id) {
    auto* app = ClientApp::GetApp();
    if (!app || app->EmpireID() == ALL_EMPIRES)
        return false;
    try {
        auto& context = app->GetContext();
        const int empire_id = app->EmpireID();
        const auto pending = PendingOrderIDs<AnnexOrder>(
            app->Orders(), [&](const AnnexOrder& o) { return o.PlanetID() == planet_id; });
        if (!pending.empty()) {
            Rescind(pending, *app);
            return true;
        }
        const auto empire = context.GetEmpire(empire_id);
        const auto* source = empire ? empire->Source(context.ContextObjects()).get() : nullptr;
        if (!source)
            return false;
        ScriptingContext empire_context{context, ScriptingContext::Source{}, source};
        if (!AnnexOrder::Check(empire_id, planet_id, empire_context))
            return false;
        app->Orders().IssueOrder<AnnexOrder>(empire_context, empire_id, planet_id);
        return true;
    } catch (const std::exception& e) {
        ErrorLogger() << "FOPlanetActions::annex(" << planet_id << "): " << e.what();
    }
    return false;
}

bool FOPlanetActions::bombard(int planet_id) {
    auto* app = ClientApp::GetApp();
    if (!app || app->EmpireID() == ALL_EMPIRES)
        return false;
    try {
        auto& context = app->GetContext();
        const int empire_id = app->EmpireID();
        const auto* planet = context.ContextObjects().getRaw<Planet>(planet_id);
        if (!planet)
            return false;
        // Cancel: drop this turn's orders and stop ships set on it earlier.
        const auto pending = PendingOrderIDs<BombardOrder>(
            app->Orders(), [&](const BombardOrder& o) { return o.PlanetID() == planet_id; });
        const auto bombarding = BombardingShips(*planet, empire_id, context);
        if (!pending.empty() || !bombarding.empty()) {
            Rescind(pending, *app);
            for (const auto* ship : BombardingShips(*planet, empire_id, context))
                if (StopBombardOrder::Check(empire_id, ship->ID(), planet_id, context))
                    app->Orders().IssueOrder<StopBombardOrder>(context, empire_id, ship->ID(), planet_id);
            return true;
        }
        bool issued = false;
        for (const auto* ship : ChooseBombardShips(*planet, empire_id, context)) {
            if (!BombardOrder::Check(empire_id, ship->ID(), planet_id, context))
                continue;
            app->Orders().IssueOrder<BombardOrder>(context, empire_id, ship->ID(), planet_id);
            issued = true;
        }
        return issued;
    } catch (const std::exception& e) {
        ErrorLogger() << "FOPlanetActions::bombard(" << planet_id << "): " << e.what();
    }
    return false;
}

bool FOPlanetActions::set_focus(int planet_id, const godot::String& focus) {
    auto* app = ClientApp::GetApp();
    if (!app)
        return false;
    try {
        auto& context = app->GetContext();
        std::string focus_name = focus.utf8().get_data();
        const auto* planet = context.ContextObjects().getRaw<Planet>(planet_id);
        if (!planet || planet->Focus() == focus_name ||
            !ChangeFocusOrder::Check(app->EmpireID(), planet_id, focus_name, context))
        { return false; }
        app->Orders().IssueOrder<ChangeFocusOrder>(context, app->EmpireID(), planet_id, std::move(focus_name));
        // Show the new focus's effect on the projected meters at once.
        context.ContextUniverse().UpdateMeterEstimates(context);
        return true;
    } catch (const std::exception& e) {
        ErrorLogger() << "FOPlanetActions::set_focus(" << planet_id << "): " << e.what();
    }
    return false;
}

bool FOPlanetActions::scrap(int object_id) {
    auto* app = ClientApp::GetApp();
    if (!app || app->EmpireID() == ALL_EMPIRES)
        return false;
    try {
        auto& context = app->GetContext();
        const auto pending = PendingOrderIDs<ScrapOrder>(
            app->Orders(), [&](const ScrapOrder& o) { return o.ObjectID() == object_id; });
        if (!pending.empty()) {
            Rescind(pending, *app);
            return true;
        }
        if (!ScrapOrder::Check(app->EmpireID(), object_id, context))
            return false;
        app->Orders().IssueOrder<ScrapOrder>(context, app->EmpireID(), object_id);
        return true;
    } catch (const std::exception& e) {
        ErrorLogger() << "FOPlanetActions::scrap(" << object_id << "): " << e.what();
    }
    return false;
}

bool FOPlanetActions::is_scrapping(int object_id) {
    const auto* app = ClientApp::GetApp();
    if (!app)
        return false;
    for (const auto& [order_id, order] : app->Orders())
        if (auto scrap = std::dynamic_pointer_cast<ScrapOrder>(order); scrap && scrap->ObjectID() == object_id)
            return true;
    return false;
}
