#include "FOExplore.h"

#include <map>
#include <unordered_map>
#include <boost/container/flat_set.hpp>
#include <boost/unordered/unordered_set.hpp>
#include <godot_cpp/core/class_db.hpp>

#include "../../ClientApp.h"
#include "../../../Empire/Empire.h"
#include "../../../Empire/Supply.h"
#include "../../../universe/Fleet.h"
#include "../../../universe/Pathfinder.h"
#include "../../../universe/System.h"
#include "../../../universe/Universe.h"
#include "../../../util/Logger.h"
#include "../../../util/OptionsDB.h"
#include "../../../util/Order.h"
#include "../../../util/OrderSet.h"
#include "../../../util/ranges.h"

// Fleets sent exploring, as the GG client's MapWnd: each turn every idle
// one is sent to the nearest unexplored system it can reach (refuelling
// first when it couldn't get back to supply). The dispatcher below is
// MapWnd::DispatchFleetsExploring and its helpers, moved here.

namespace {
    float KnownSystemMultiplier() {
        const auto& db = GetOptionsDB();
        return db.OptionExists("ui.fleet.explore.system.known.multiplier") ?
            db.Get<float>("ui.fleet.explore.system.known.multiplier") : 10.0f;
    }

    int RouteLimit() {
        const auto& db = GetOptionsDB();
        return db.OptionExists("ui.fleet.explore.system.route.limit") ?
            db.Get<int>("ui.fleet.explore.system.route.limit") : 25;
    }
}

namespace {
    typedef std::vector<int> RouteListType;
    typedef std::pair<double, RouteListType> OrderedRouteType;
    typedef std::pair<int, RouteListType> FleetRouteType;
    typedef std::pair<double, FleetRouteType> OrderedFleetRouteType;
    typedef std::unordered_map<int, int> SystemFleetMap;

    /** Number of jumps in a given route */
    int JumpsForRoute(const RouteListType& route) {
        int count = static_cast<int>(route.size());
        if (count > 0) // dont count source system
            -- count;
        return count;
    }

    /** If @p fleet can determine an eta for @p route */
    bool FleetRouteInRange(const Fleet* fleet, const RouteListType& route,
                           const ScriptingContext& context)
    {
        const auto eta_final_turns = fleet->ETA(fleet->MovePath(route, false, context)).first;
        return (eta_final_turns != Fleet::ETA_NEVER &&
                eta_final_turns != Fleet::ETA_UNKNOWN &&
                eta_final_turns != Fleet::ETA_OUT_OF_RANGE);
    }

    // helper function for DispatchFleetsExploring
    // return systems ID with a starlane connecting them to a system in \a system_ids
    boost::container::flat_set<int> NeighbourSystemsOf(const Empire* empire, const Universe& universe,
                                                       const auto& system_ids)
    {
        const auto starlanes{empire->KnownStarlanes(universe)};
        using starlanes_t = std::decay_t<decltype(starlanes)>;
        static_assert(std::is_same_v<starlanes_t, boost::container::flat_set<Empire::LaneEndpoints>>,
                      "make sure starlanes is sorted for efficient insertion into flat_set below");
        const auto lane_starts_in_system_in_ids = [&system_ids](const auto lane)
        { return range_any_of(system_ids,[lane](const auto sys_id) noexcept { return lane.start == sys_id; }); };

        static constexpr auto to_lane_end = [](const auto& lane) noexcept { return lane.end; };

        return starlanes | range_filter(lane_starts_in_system_in_ids)
            | range_transform(to_lane_end) | range_to<boost::container::flat_set<int>>();
    }

    /** Get the shortest suitable route from @p start_id to @p destination_id as known to @p empire_id */
    OrderedRouteType GetShortestRoute(int empire_id, int start_id, int destination_id,
                                      const ScriptingContext& context)
    {

        const auto& objects = context.ContextObjects();
        const auto start_system = objects.getRaw<System>(start_id);
        const auto dest_system = objects.getRaw<System>(destination_id);
        if (!start_system || !dest_system) {
            WarnLogger() << "GetShortestRoute: couldn't find start or destination systems";
            return {};
        }

        auto [system_list, path_length] =
            context.ContextUniverse().GetPathfinder().ShortestPath(start_id, destination_id, empire_id);

        if (!system_list.empty() && path_length > 0.0)
            return {path_length, system_list};

        return {};
    }

    /** Route from @p fleet current location to @p destination */
    OrderedFleetRouteType GetOrderedFleetRoute(const Fleet* fleet,
                                               const System* destination,
                                               const ScriptingContext& context)
    {
        const ObjectMap& objects{context.ContextObjects()};

        if (!fleet || !destination) {
            WarnLogger() << "GetOrderedFleetRoute: null fleet or system";
            return {};
        }
        if ((fleet->Fuel(objects) < 1.0f) || !fleet->MovePath(false, context).empty()) {
            WarnLogger() << "GetOrderedFleetRoute: no fuel or non-empty move path";
            return {};
        }

        auto [route_length, route_ids] = GetShortestRoute(fleet->Owner(), fleet->SystemID(),
                                                          destination->ID(), context);

        if (route_length <= 0.0) {
            TraceLogger() << "No suitable route from system " << fleet->SystemID() << " to " << destination->ID()
                          << " (" << route_ids.size() << ">" << route_length << ")";
            return {};
        }

        if (!FleetRouteInRange(fleet, route_ids, context)) {
            TraceLogger() << "Fleet " << std::to_string(fleet->ID())
                          << " has no ETA for route to " << std::to_string(route_ids.back());
            return {};
        }

        // decrease priority of system if previously viewed but not yet explored
        if (!destination->Name().empty()) {
            route_length *= KnownSystemMultiplier();
            TraceLogger() << "Deferred priority for system " << destination->Name() << " (" << destination->ID() << ")";
        }

        return std::pair{route_length, std::pair{fleet->ID(), std::move(route_ids)}};
    }

    /** Shortest route not exceeding @p max_jumps from @p dest_id to a system with supply as known to @p empire */
    OrderedRouteType GetNearestSupplyRoute(const std::shared_ptr<const Empire>& empire,
                                           int dest_id, int max_jumps,
                                           const ScriptingContext& context)
    {
        OrderedRouteType retval;

        if (!empire) {
            WarnLogger() << "Invalid empire";
            return retval;
        }

        auto supplyable_systems = context.supply.FleetSupplyableSystemIDs(
            empire->EmpireID(), true, context);
        if (!supplyable_systems.empty()) {
            TraceLogger() << [&supplyable_systems]() {
                    std::string msg = "Supplyable systems:";
                    for (auto sys : supplyable_systems)
                        msg.append(" " + std::to_string(sys));
                    return msg;
                }();
        }

            OrderedRouteType shortest_route;

        for (auto supply_system_id : supplyable_systems) {
            shortest_route = GetShortestRoute(empire->EmpireID(), dest_id, supply_system_id, context);
            TraceLogger() << [&shortest_route, dest_id]() {
                    std::string msg = "Checking supply route from " + std::to_string(dest_id) +
                                      " dist:" + std::to_string(shortest_route.first) + " systems:";
                    for (auto node : shortest_route.second)
                        msg.append(" " + std::to_string(node));
                    return msg;
                }();

            auto route_jumps = JumpsForRoute(shortest_route.second);
            if (max_jumps > -1 && route_jumps > max_jumps) {
                TraceLogger() << "Rejecting route to " << std::to_string(*shortest_route.second.rbegin())
                              << " jumps " << std::to_string(route_jumps) << " exceed max " << std::to_string(max_jumps);
                continue;
            }

            if (shortest_route.first <= 0.0 || shortest_route.second.empty()) {
                TraceLogger() << "Invalid route";
                continue;
            }

            if (retval.first <= 0.0 || shortest_route.first < retval.first) {
                TraceLogger() << "Setting " << std::to_string(*shortest_route.second.rbegin()) << " as shortest route";
                retval = std::move(shortest_route);
            }
        }

        return retval;
    }

    /** If @p fleet would be able to reach a system with supply after completing @p route */
    bool CanResupplyAfterDestination(const Fleet* fleet, const RouteListType& route,
                                     const ScriptingContext& context)
    {
        const ObjectMap& objects{context.ContextObjects()};

        if (!fleet || route.empty()) {
            WarnLogger() << "Invalid fleet or empty route";
            return false;
        }
        auto empire = context.GetEmpire(fleet->Owner());
        if (!empire) {
            WarnLogger() << "Invalid empire";
            return false;
        }

        int max_jumps = std::trunc(fleet->Fuel(objects));
        if (max_jumps < 1) {
            TraceLogger() << "Not enough fuel " << std::to_string(max_jumps)
                          << " to move fleet " << std::to_string(fleet->ID());
            return false;
        }

        auto dest_nearest_supply = GetNearestSupplyRoute(
            empire, route.back(), max_jumps, context);
        auto dest_nearest_supply_jumps = JumpsForRoute(dest_nearest_supply.second);
        auto dest_jumps = JumpsForRoute(route);
        int total_jumps = dest_jumps + dest_nearest_supply_jumps;

        if (total_jumps > max_jumps) {
            TraceLogger() << "Not enough fuel " << std::to_string(max_jumps)
                          << " for fleet " << std::to_string(fleet->ID())
                          << " to resupply after destination " << std::to_string(total_jumps);
            return false;
        }

        return true;
    }

    /** Route from current system of @p fleet to nearest system with supply as determined by owning empire of @p fleet  */
    OrderedRouteType ExploringFleetResupplyRoute(const Fleet* fleet,
                                                 const ScriptingContext& context)
    {
        auto empire = context.GetEmpire(fleet->Owner());
        if (!empire) {
            WarnLogger() << "Invalid empire for id " << fleet->Owner();
            return {};
        }

        auto nearest_supply = GetNearestSupplyRoute(empire, fleet->SystemID(),
                                                    std::trunc(fleet->Fuel(context.ContextObjects())),
                                                    context);
        if (nearest_supply.first > 0.0 && FleetRouteInRange(fleet, nearest_supply.second, context))
            return nearest_supply;

        return {};
    }

    /** Issue an order for @p fleet to move to nearest system with supply */
    bool IssueFleetResupplyOrder(const Fleet* fleet, ScriptingContext& context) {
        if (!fleet) {
            WarnLogger() << "Invalid fleet";
            return false;
        }

        auto route = ExploringFleetResupplyRoute(fleet, context);
        // Attempt move order if route is not empty and fleet has enough fuel to reach it
        if (route.second.empty()) {
            TraceLogger() << "Empty route for resupply of exploring fleet " << fleet->ID();
            return false;
        }

        auto num_jumps_resupply = JumpsForRoute(route.second);
        int max_fleet_jumps = std::trunc(fleet->Fuel(context.ContextObjects()));
        if (num_jumps_resupply <= max_fleet_jumps) {
            ClientApp::GetApp()->Orders().IssueOrder<FleetMoveOrder>(
                context, fleet->Owner(), fleet->ID(), *route.second.crbegin(), false);
        } else {
            TraceLogger() << "Not enough fuel for fleet " << fleet->ID()
                          << " to resupply at system " << *route.second.crbegin();
            return false;
        }

        if (fleet->FinalDestinationID() == *route.second.crbegin()) {
            TraceLogger() << "Sending fleet " << fleet->ID()
                          << " to refuel at system " << *route.second.crbegin();
            return true;
        } else {
            TraceLogger() << "Fleet move order failed fleet:" << fleet->ID() << " route:"
                          << [&route]() {
                                 std::string retval;
                                 for (auto node : route.second)
                                     retval += " " + std::to_string(node);
                                 return retval;
                             }();
        }

        return false;
    }

    /** Issue order for @p fleet to move using @p route */
    bool IssueFleetExploreOrder(const Fleet* fleet, const RouteListType& route,
                                ScriptingContext& context)
    {
        if (!fleet || route.empty()) {
            WarnLogger() << "Invalid fleet or empty route";
            return false;
        }
        if (!FleetRouteInRange(fleet, route, context)) {
            TraceLogger() << "Fleet " << std::to_string(fleet->ID())
                          << " has no eta for route to " << std::to_string(route.back());
            return false;
        }

        ClientApp::GetApp()->Orders().IssueOrder<FleetMoveOrder>( // TODO: pass in app
            context, fleet->Owner(), fleet->ID(), route.back(), false);
        if (fleet->FinalDestinationID() == route.back()) {
            TraceLogger() << "Sending fleet " << fleet->ID() << " to explore system " << route.back();
            return true;
        }

        TraceLogger() << "Fleet move order failed fleet:" << fleet->ID() << " dest:" << route.back();
        return false;
    }

    /** Determine and issue move order for fleet and route @p fleet_route */
    void IssueExploringFleetOrders(boost::unordered_set<int>& idle_fleets,
                                   SystemFleetMap& systems_being_explored,
                                   const FleetRouteType& fleet_route,
                                   ScriptingContext& context)
    {
        ObjectMap& objects{context.ContextObjects()};

        const auto& route = fleet_route.second;
        if (route.empty()) { // no route
            WarnLogger() << "Attempted to issue move order with empty route";
            return;
        }

        if (idle_fleets.empty()) { // no more fleets to issue orders to
            TraceLogger() << "No idle fleets";
            return;
        }

        if (systems_being_explored.contains(route.back())) {
            TraceLogger() << "System " << std::to_string(route.back()) << " already being explored";
            return;
        }

        auto fleet_id = fleet_route.first;
        auto idle_fleet_it = idle_fleets.find(fleet_id);
        if (idle_fleet_it == idle_fleets.end()) { // fleet no longer idle
            TraceLogger() << "Fleet " << std::to_string(fleet_id) << " not idle";
            return;
        }
        auto fleet = objects.getRaw<Fleet>(fleet_id);
        if (!fleet) {
            ErrorLogger() << "No valid fleet with id " << fleet_id;
            idle_fleets.erase(idle_fleet_it);
            return;
        }

        if (std::trunc(fleet->Fuel(objects)) < 1) {  // wait for fuel
            TraceLogger() << "Not enough fuel to move fleet " << std::to_string(fleet->ID());
            return;
        }

        // Determine if fleet should refuel
        if (fleet->Fuel(objects) < fleet->MaxFuel(objects) &&
            !CanResupplyAfterDestination(fleet, route, context))
        {
            if (IssueFleetResupplyOrder(fleet, context)) {
                idle_fleets.erase(idle_fleet_it);
                return;
            }
            TraceLogger() << "Fleet " << std::to_string(fleet->ID()) << " can not reach resupply";
        }

        if (IssueFleetExploreOrder(fleet, route, context)) {
            idle_fleets.erase(idle_fleet_it);
            systems_being_explored.emplace(*route.rbegin(), fleet->ID());
        }
    }

};


std::set<int>& FOExplore::Exploring() {
    static std::set<int> exploring;
    return exploring;
}

void FOExplore::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    const auto cls = get_class_static();
    ClassDB::bind_static_method(cls, D_METHOD("set_exploring", "fleet_id", "exploring"), &FOExplore::set_exploring);
    ClassDB::bind_static_method(cls, D_METHOD("is_exploring", "fleet_id"), &FOExplore::is_exploring);
    ClassDB::bind_static_method(cls, D_METHOD("dispatch"), &FOExplore::dispatch);
}

void FOExplore::set_exploring(int fleet_id, bool exploring) {
    if (exploring)
        Exploring().insert(fleet_id);
    else
        Exploring().erase(fleet_id);
    dispatch();
}

bool FOExplore::is_exploring(int fleet_id)
{ return Exploring().contains(fleet_id); }

void FOExplore::dispatch() {
    auto* app = ClientApp::GetApp();
    if (!app || app->EmpireID() == ALL_EMPIRES)
        return;
    try {
        Dispatch(app->GetContext(), app->EmpireID());
    } catch (const std::exception& e) {
        ErrorLogger() << "FOExplore::dispatch: " << e.what();
    }
}

void FOExplore::Dispatch(ScriptingContext& context, int empire_id) {
    const auto& universe{context.ContextUniverse()};
    const auto& objects{context.ContextObjects()};


    auto empire = context.GetEmpire(empire_id);
    if (!empire) {
        WarnLogger() << "Invalid empire";
        return;
    }
    int max_routes_per_system = RouteLimit();
    const auto& destroyed_objects{universe.EmpireKnownDestroyedObjectIDs(empire_id)};

    boost::unordered_set<int> idle_fleets;
    /** all systems ID for which an exploring fleet is in route and the fleet assigned */
    SystemFleetMap systems_being_explored;

    // clean the fleet list by removing non-existing fleet, and extract the
    // fleets waiting for orders
    for (const auto* fleet : objects.findRaw<Fleet>(Exploring())) {
        if (!fleet)
            continue;
        if (destroyed_objects.contains(fleet->ID())) {
            Exploring().erase(fleet->ID()); //this fleet can't explore anymore
        } else {
            if (fleet->MovePath(false, context).empty())
                idle_fleets.insert(fleet->ID());
            else
                systems_being_explored.emplace(fleet->FinalDestinationID(), fleet->ID());
        }
    }

    if (idle_fleets.empty())
        return;

    TraceLogger() << [&idle_fleets]() {
            std::string retval = "FOExplore::Dispatch Idle Exploring Fleet IDs:";
            for (auto fleet_id : idle_fleets)
                retval += " " + std::to_string(fleet_id);
            return retval;
        }();

    //list all unexplored systems by taking the neighboors of explored systems because ObjectMap does not list them all.
    auto explored_systems{empire->ExploredSystems()};
    auto candidates_unknown_systems{NeighbourSystemsOf(empire.get(), universe, explored_systems)};
    candidates_unknown_systems.merge(NeighbourSystemsOf(empire.get(), universe, candidates_unknown_systems));

    // Populate list of unexplored systems
    boost::unordered_set<int> unexplored_systems;
    for (const auto* system : objects.findRaw<System>(candidates_unknown_systems)) {
        if (!system)
            continue;
        if (!empire->HasExploredSystem(system->ID()) &&
            !systems_being_explored.contains(system->ID()))
        { unexplored_systems.emplace(system->ID()); }
    }

    if (unexplored_systems.empty()) {
        TraceLogger() << "No unknown systems to explore";
        return;
    }

    TraceLogger() << [&unexplored_systems]() {
            std::string retval = "FOExplore::Dispatch Unknown System IDs:";
            for (auto system_id : unexplored_systems)
                retval += " " + std::to_string(system_id);
            return retval;
        }();

    std::multimap<double, FleetRouteType> fleet_routes;  // priority, (fleet, route)

    // Determine fleet routes for each unexplored system
    std::unordered_map<int, int> fleet_route_count;
    for (const auto* unexplored_system : objects.findRaw<System>(unexplored_systems)) {
        if (!unexplored_system)
            continue;

        for (const auto& fleet_id : idle_fleets) {
            if (max_routes_per_system > 0 &&
                fleet_route_count[unexplored_system->ID()] > max_routes_per_system)
            { break; }

            auto fleet = objects.getRaw<Fleet>(fleet_id);
            if (!fleet) {
                WarnLogger() << "Invalid fleet " << fleet_id;
                continue;
            }
            if (fleet->Fuel(objects) < 1.0f)
                continue;

            auto route = GetOrderedFleetRoute(fleet, unexplored_system, context);
            if (route.first > 0.0) {
                ++fleet_route_count[unexplored_system->ID()];
                fleet_routes.insert(std::move(route));
            }
        }
    }

    if (!fleet_routes.empty()) {
        TraceLogger() << [&fleet_routes]() {
            std::string retval = "FOExplore::Dispatch Explorable Systems:\n\t Priority\tFleet\tDestination";
            for (const auto& route : fleet_routes) {
                retval.append("\n\t" + std::to_string(route.first) + "\t" +
                              std::to_string(route.second.first) + "\t " +
                              std::to_string(route.second.second.empty() ? -1 : *route.second.second.rbegin()));
            }
            return retval;
        }();
    }

    // Issue fleet orders
    for (const auto& fleet_route : fleet_routes)
        IssueExploringFleetOrders(idle_fleets, systems_being_explored, fleet_route.second, context);

    // verify fleets have expected destination
    for (const auto& [dest_sys_id, fleet_id] : systems_being_explored) {
        auto fleet = objects.get<Fleet>(fleet_id);
        if (!fleet)
            continue;

        auto dest_id = fleet->FinalDestinationID();
        if (dest_id == dest_sys_id)
            continue;

        WarnLogger() << "Non idle exploring fleet "<< fleet_id << " has differing destination:"
                     << fleet->FinalDestinationID() << " expected:" << dest_sys_id;

        idle_fleets.emplace(fleet_id);
        // systems_being_explored.erase(system_fleet_it);
    }

    if (!idle_fleets.empty()) {
        DebugLogger() << [&idle_fleets]() {
            std::string retval = "FOExplore::Dispatch Idle exploring fleets after orders:";
            retval.reserve(retval.size() + 10*idle_fleets.size()); // rough guesstimate
            for (auto fleet_id : idle_fleets)
                retval.append(" ").append(std::to_string(fleet_id));
            return retval;
        }();
    }
}

