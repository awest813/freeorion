#include "FOOrders.h"

#include <godot_cpp/core/class_db.hpp>

#include "../../ClientApp.h"
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
