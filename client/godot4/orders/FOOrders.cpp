#include "FOOrders.h"

#include <godot_cpp/core/class_db.hpp>

#include "../../ClientApp.h"
#include "../../../Empire/Empire.h"
#include "../../../Empire/EmpireManager.h"
#include "../../../universe/Fleet.h"
#include "../../../universe/Planet.h"
#include "../../../universe/System.h"
#include "../../../universe/Universe.h"
#include "../../../universe/Ship.h"
#include "../../../util/Logger.h"
#include "../../../util/Order.h"
#include "../../../util/OrderSet.h"

void FOOrders::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    const auto cls = get_class_static();
    ClassDB::bind_static_method(cls, D_METHOD("issue_fleet_move", "fleet_id", "dest_system_id", "append"),
                                &FOOrders::issue_fleet_move, DEFVAL(false));
    ClassDB::bind_static_method(cls, D_METHOD("move_problem", "fleet_id", "dest_system_id", "append"),
                                &FOOrders::move_problem, DEFVAL(false));
    ClassDB::bind_static_method(cls, D_METHOD("rescind_order", "order_id"), &FOOrders::rescind_order);
    ClassDB::bind_static_method(cls, D_METHOD("get_order_count"), &FOOrders::get_order_count);
    ClassDB::bind_static_method(cls, D_METHOD("revert_all"), &FOOrders::revert_all);
    ClassDB::bind_static_method(cls, D_METHOD("is_sensor_ghost", "object_id"), &FOOrders::is_sensor_ghost);
    ClassDB::bind_static_method(cls, D_METHOD("forget", "object_id"), &FOOrders::forget);
    ClassDB::bind_static_method(cls, D_METHOD("get_give_targets", "object_id"), &FOOrders::get_give_targets);
    ClassDB::bind_static_method(cls, D_METHOD("give_to_empire", "object_id", "recipient"), &FOOrders::give_to_empire);
    ClassDB::bind_static_method(cls, D_METHOD("set_fleet_aggression", "fleet_id", "aggression"), &FOOrders::set_fleet_aggression);
    ClassDB::bind_static_method(cls, D_METHOD("split_ships", "ship_ids", "aggression"), &FOOrders::split_ships,
                                DEFVAL(godot::String()));
    ClassDB::bind_static_method(cls, D_METHOD("merge_ships", "dest_fleet_id", "ship_ids"), &FOOrders::merge_ships);
    ClassDB::bind_static_method(cls, D_METHOD("rename", "object_id", "new_name"), &FOOrders::rename);
}

int FOOrders::issue_fleet_move(int fleet_id, int dest_system_id, bool append) {
    auto* app = ClientApp::GetApp();
    if (!app)
        return -1;

    auto& context = app->GetContext();
    const int empire_id = app->EmpireID();
    if (!FleetMoveOrder::Check(empire_id, fleet_id, dest_system_id, append, context))
        return -1;
    // An order with no way there would leave the fleet where it is, silently.
    const auto problem = move_problem(fleet_id, dest_system_id, append);
    if (!problem.is_empty() && problem != "MOVE_PROBLEM_FUEL")
        return -1;

    const auto order = app->Orders().IssueOrder<FleetMoveOrder>(context, empire_id, fleet_id, dest_system_id, append);
    for (const auto& [order_id, issued] : app->Orders()) {
        if (issued == order)
            return order_id;
    }
    ErrorLogger() << "FOOrders::issue_fleet_move: issued order not found in order set";
    return -1;
}

godot::String FOOrders::move_problem(int fleet_id, int dest_system_id, bool append) {
    auto* app = ClientApp::GetApp();
    if (!app)
        return "MOVE_PROBLEM_UNKNOWN";
    const auto& context = app->GetContext();
    const auto& objects = context.ContextObjects();
    const auto* fleet = objects.getRaw<Fleet>(fleet_id);
    if (!fleet || !fleet->OwnedBy(app->EmpireID()) || !objects.getRaw<System>(dest_system_id))
        return "MOVE_PROBLEM_UNKNOWN";
    int start = fleet->SystemID();
    if (start == INVALID_OBJECT_ID)
        start = fleet->NextSystemID();
    if (append && !fleet->TravelRoute().empty())
        start = fleet->TravelRoute().back();
    if (start == dest_system_id)
        return "";
    if (fleet->Speed(objects) <= 0.0f)
        return "MOVE_PROBLEM_IMMOBILE";
    auto path = context.ContextUniverse().GetPathfinder().ShortestPath(
        start, dest_system_id, app->EmpireID()).first;
    if (path.empty())
        return "MOVE_PROBLEM_NO_ROUTE";
    if (append && !fleet->TravelRoute().empty()) {
        // The fuel check covers the whole route: the current one, then this.
        std::vector<int> whole(fleet->TravelRoute().begin(), fleet->TravelRoute().end());
        whole.insert(whole.end(), path.begin() + 1, path.end());
        path = std::move(whole);
    }
    const auto eta = fleet->ETA(fleet->MovePath(path, false, context)).first;
    return eta == Fleet::ETA_OUT_OF_RANGE ? "MOVE_PROBLEM_FUEL" : "";
}

bool FOOrders::rescind_order(int order_id) {
    auto* app = ClientApp::GetApp();
    return app && app->Orders().RescindOrder(order_id, app->GetContext());
}

int FOOrders::get_order_count() {
    const auto* app = ClientApp::GetApp();
    return app ? static_cast<int>(app->Orders().size()) : 0;
}

bool FOOrders::revert_all() {
    auto* app = ClientApp::GetApp();
    if (!app)
        return false;
    app->RevertOrders();  // does nothing without a connection
    return true;
}

namespace {
    std::vector<int> ToVector(const godot::PackedInt32Array& ids) {
        std::vector<int> result;
        result.reserve(ids.size());
        for (int64_t i = 0; i < ids.size(); ++i)
            result.push_back(ids[i]);
        return result;
    }

    FleetAggression ParseAggression(const godot::String& value) {
        if (value == "passive")     return FleetAggression::FLEET_PASSIVE;
        if (value == "defensive")   return FleetAggression::FLEET_DEFENSIVE;
        if (value == "obstructive") return FleetAggression::FLEET_OBSTRUCTIVE;
        if (value == "aggressive")  return FleetAggression::FLEET_AGGRESSIVE;
        return FleetAggression::INVALID_FLEET_AGGRESSION;
    }
}

bool FOOrders::set_fleet_aggression(int fleet_id, const godot::String& aggression) {
    auto* app = ClientApp::GetApp();
    const auto value = ParseAggression(aggression);
    if (!app || value == FleetAggression::INVALID_FLEET_AGGRESSION)
        return false;
    auto& context = app->GetContext();
    if (!AggressiveOrder::Check(app->EmpireID(), fleet_id, value, context))
        return false;
    app->Orders().IssueOrder<AggressiveOrder>(context, app->EmpireID(), fleet_id, value);
    return true;
}

int FOOrders::split_ships(const godot::PackedInt32Array& ship_ids, const godot::String& stance) {
    auto* app = ClientApp::GetApp();
    if (!app || ship_ids.is_empty())
        return -1;
    auto& context = app->GetContext();
    const auto ships = ToVector(ship_ids);
    auto aggression = ParseAggression(stance);
    if (stance == "auto") {
        const auto armed = context.ContextObjects().check_if_any<Ship>(
            [&context](const Ship* ship) { return ship && ship->CanDamageShips(context); }, ships);
        aggression = armed ? FleetDefaults::FLEET_DEFAULT_ARMED : FleetDefaults::FLEET_DEFAULT_UNARMED;
    } else if (aggression == FleetAggression::INVALID_FLEET_AGGRESSION) {
        // Keep the stance of the fleet the ships come from.
        const auto* first = context.ContextObjects().getRaw<Ship>(ships.front());
        const auto* source = first ? context.ContextObjects().getRaw<Fleet>(first->FleetID()) : nullptr;
        aggression = source ? source->Aggression() : FleetAggression::FLEET_OBSTRUCTIVE;
    }
    if (!NewFleetOrder::Check(app->EmpireID(), "", ships, aggression, context))
        return -1;
    const auto order = app->Orders().IssueOrder<NewFleetOrder>(context, app->EmpireID(), "", ships, aggression);
    return order ? order->FleetID() : -1;
}

bool FOOrders::merge_ships(int dest_fleet_id, const godot::PackedInt32Array& ship_ids) {
    auto* app = ClientApp::GetApp();
    if (!app || ship_ids.is_empty())
        return false;
    auto& context = app->GetContext();
    auto ships = ToVector(ship_ids);
    if (!FleetTransferOrder::Check(app->EmpireID(), dest_fleet_id, ships, context))
        return false;
    app->Orders().IssueOrder<FleetTransferOrder>(context, app->EmpireID(), dest_fleet_id, std::move(ships));
    return true;
}

bool FOOrders::rename(int object_id, const godot::String& new_name) {
    auto* app = ClientApp::GetApp();
    std::string name = new_name.utf8().get_data();
    if (!app || !RenameOrder::Check(app->EmpireID(), object_id, name, app->GetContext()))
        return false;
    app->Orders().IssueOrder<RenameOrder>(app->GetContext(), app->EmpireID(), object_id, std::move(name));
    return true;
}

bool FOOrders::is_sensor_ghost(int object_id) {
    const auto* app = ClientApp::GetApp();
    if (!app)
        return false;
    const auto& context = app->GetContext();
    const auto* object = context.ContextObjects().getRaw(object_id);
    if (!object || object->OwnedBy(app->EmpireID()))
        return false;
    const int last_seen = context.ContextUniverse().GetObjectVisibilityTurnByEmpire(
        object_id, app->EmpireID(), Visibility::VIS_BASIC_VISIBILITY);
    return last_seen != INVALID_GAME_TURN && last_seen < context.current_turn;
}

bool FOOrders::forget(int object_id) {
    auto* app = ClientApp::GetApp();
    if (!app || !is_sensor_ghost(object_id))
        return false;
    auto& context = app->GetContext();
    // A lone ship goes with its fleet, as in the GG client.
    if (const auto* ship = context.ContextObjects().getRaw<Ship>(object_id)) {
        if (const auto* fleet = context.ContextObjects().getRaw<Fleet>(ship->FleetID()); fleet && fleet->NumShips() == 1)
            object_id = fleet->ID();
    }
    try {
        app->Orders().IssueOrder<ForgetOrder>(context, app->EmpireID(), object_id);
        context.ContextUniverse().ForgetKnownObject(ALL_EMPIRES, object_id);
    } catch (const std::exception& e) {
        ErrorLogger() << "FOOrders::forget: " << e.what();
        return false;
    }
    return true;
}

godot::Dictionary FOOrders::get_give_targets(int object_id) {
    godot::Dictionary result;
    godot::Array targets;
    const auto* app = ClientApp::GetApp();
    result["targets"] = targets;
    result["giving_to"] = ALL_EMPIRES;
    if (!app)
        return result;
    const auto& context = app->GetContext();
    const int self = app->EmpireID();
    const auto* object = context.ContextObjects().getRaw(object_id);
    if (!object || !object->OwnedBy(self))
        return result;
    if (const auto* fleet = dynamic_cast<const Fleet*>(object)) {
        result["giving_to"] = fleet->OrderedGivenToEmpire();
        if (!fleet->TravelRoute().empty())
            return result;
    } else if (const auto* planet = dynamic_cast<const Planet*>(object)) {
        result["giving_to"] = planet->OrderedGivenToEmpire();
    }
    const auto* system = context.ContextObjects().getRaw<System>(object->SystemID());
    if (!system)
        return result;
    // As the GG client: empires at peace that own something visible here.
    std::set<int> peaceful;
    for (const auto* other : context.ContextObjects().findRaw<const UniverseObject>(system->ObjectIDs())) {
        if (!other || other->Unowned() || other->Owner() == self)
            continue;
        if (context.ContextUniverse().GetObjectVisibilityByEmpire(other->ID(), self) < Visibility::VIS_PARTIAL_VISIBILITY)
            continue;
        if (context.ContextDiploStatus(self, other->Owner()) >= DiplomaticStatus::DIPLO_PEACE)
            peaceful.insert(other->Owner());
    }
    for (const int empire_id : peaceful) {
        const auto empire = context.GetEmpire(empire_id);
        if (!empire || !GiveObjectToEmpireOrder::Check(self, object_id, empire_id, context))
            continue;
        godot::Dictionary target;
        target["id"] = empire_id;
        target["name"] = godot::String::utf8(empire->Name().c_str());
        const auto c = empire->Color();
        target["color"] = godot::Color::from_rgba8(c[0], c[1], c[2], c[3]);
        targets.push_back(target);
    }
    result["targets"] = targets;
    return result;
}

bool FOOrders::give_to_empire(int object_id, int recipient) {
    auto* app = ClientApp::GetApp();
    if (!app)
        return false;
    auto& context = app->GetContext();
    // Cancel a gift ordered this turn.
    std::vector<int> pending;
    for (const auto& [order_id, order] : app->Orders())
        if (const auto give = std::dynamic_pointer_cast<GiveObjectToEmpireOrder>(order); give && give->ObjectID() == object_id)
            pending.push_back(order_id);
    for (const int order_id : pending)
        app->Orders().RescindOrder(order_id, context);
    if (recipient == ALL_EMPIRES)
        return !pending.empty();
    if (!GiveObjectToEmpireOrder::Check(app->EmpireID(), object_id, recipient, context))
        return false;
    app->Orders().IssueOrder<GiveObjectToEmpireOrder>(context, app->EmpireID(), object_id, recipient, context);
    return true;
}
