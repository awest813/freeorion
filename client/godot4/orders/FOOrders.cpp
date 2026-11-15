#include "FOOrders.h"

#include <godot_cpp/core/class_db.hpp>

#include "../../ClientApp.h"
#include "../../../universe/Fleet.h"
#include "../../../universe/Ship.h"
#include "../../../util/Logger.h"
#include "../../../util/Order.h"
#include "../../../util/OrderSet.h"

void FOOrders::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    const auto cls = get_class_static();
    ClassDB::bind_static_method(cls, D_METHOD("issue_fleet_move", "fleet_id", "dest_system_id", "append"),
                                &FOOrders::issue_fleet_move, DEFVAL(false));
    ClassDB::bind_static_method(cls, D_METHOD("rescind_order", "order_id"), &FOOrders::rescind_order);
    ClassDB::bind_static_method(cls, D_METHOD("get_order_count"), &FOOrders::get_order_count);
    ClassDB::bind_static_method(cls, D_METHOD("set_fleet_aggression", "fleet_id", "aggression"), &FOOrders::set_fleet_aggression);
    ClassDB::bind_static_method(cls, D_METHOD("split_ships", "ship_ids"), &FOOrders::split_ships);
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

    const auto order = app->Orders().IssueOrder<FleetMoveOrder>(context, empire_id, fleet_id, dest_system_id, append);
    for (const auto& [order_id, issued] : app->Orders()) {
        if (issued == order)
            return order_id;
    }
    ErrorLogger() << "FOOrders::issue_fleet_move: issued order not found in order set";
    return -1;
}

bool FOOrders::rescind_order(int order_id) {
    auto* app = ClientApp::GetApp();
    return app && app->Orders().RescindOrder(order_id, app->GetContext());
}

int FOOrders::get_order_count() {
    const auto* app = ClientApp::GetApp();
    return app ? static_cast<int>(app->Orders().size()) : 0;
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

int FOOrders::split_ships(const godot::PackedInt32Array& ship_ids) {
    auto* app = ClientApp::GetApp();
    if (!app || ship_ids.is_empty())
        return -1;
    auto& context = app->GetContext();
    const auto ships = ToVector(ship_ids);
    // Keep the stance of the fleet the ships come from.
    const auto* first = context.ContextObjects().getRaw<Ship>(ships.front());
    const auto* source = first ? context.ContextObjects().getRaw<Fleet>(first->FleetID()) : nullptr;
    const auto aggression = source ? source->Aggression() : FleetAggression::FLEET_OBSTRUCTIVE;
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
