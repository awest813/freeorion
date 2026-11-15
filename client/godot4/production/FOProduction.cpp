#include "FOProduction.h"

#include <vector>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include "../../ClientApp.h"
#include "../../../Empire/Empire.h"
#include "../../../universe/BuildingType.h"
#include "../../../universe/Planet.h"
#include "../../../universe/ShipDesign.h"
#include "../../../universe/ShipHull.h"
#include "../../../universe/Universe.h"
#include "../../../util/Logger.h"
#include "../../../util/Order.h"
#include "../../../util/OrderSet.h"

namespace {
    using Action = ProductionQueueOrder::ProdQueueOrderAction;

    godot::String ToGodot(std::string_view s)
    { return godot::String::utf8(s.data(), static_cast<int>(s.size())); }

    Empire* PlayerEmpire() {
        auto* app = ClientApp::GetApp();
        return app ? app->GetEmpire(app->EmpireID()) : nullptr;
    }

    void Describe(const ProductionQueue::ProductionItem& item, const Universe& universe, godot::Dictionary& out) {
        if (item.build_type == BuildType::BT_BUILDING) {
            out["build_type"] = "building";
            out["name"] = ToGodot(item.name);
            out["design_id"] = -1;
            out["label"] = ToGodot(item.name);
            const auto* type = GetBuildingType(item.name);
            out["icon"] = type ? ToGodot(type->Icon()) : godot::String();
        } else if (item.build_type == BuildType::BT_SHIP) {
            out["build_type"] = "ship";
            out["name"] = godot::String();
            out["design_id"] = item.design_id;
            const auto* design = universe.GetShipDesign(item.design_id);
            out["label"] = design ? ToGodot(design->Name(true)) : godot::String();
            const auto* hull = design ? GetShipHull(design->Hull()) : nullptr;
            out["icon"] = design && !design->Icon().empty() ? ToGodot(design->Icon())
                        : hull ? ToGodot(hull->Icon()) : godot::String();
        } else if (item.build_type == BuildType::BT_STOCKPILE) {
            out["build_type"] = "stockpile";
            out["name"] = "PROJECT_BT_STOCKPILE";
            out["design_id"] = -1;
            out["label"] = "PROJECT_BT_STOCKPILE";
            out["icon"] = "icons/meter/stockpile.png";
        } else {
            out["build_type"] = "other";
            out["name"] = ToGodot(item.name);
            out["design_id"] = -1;
            out["label"] = ToGodot(item.name);
            out["icon"] = godot::String();
        }
    }

    // Issue a queue order and re-project the queue, as the GG ProductionWnd does.
    template <typename... Args>
    bool IssueQueueOrder(Args&&... args) {
        auto* app = ClientApp::GetApp();
        auto* empire = PlayerEmpire();
        if (!app || !empire)
            return false;
        auto& context = app->GetContext();
        try {
            app->Orders().IssueOrder<ProductionQueueOrder>(context, std::forward<Args>(args)...);
        } catch (const std::exception& e) {
            ErrorLogger() << "FOProduction: order failed: " << e.what();
            return false;
        }
        empire->UpdateProductionQueue(context, empire->ProductionCostsTimes(context));
        return true;
    }

    const ProductionQueue::Element* ElementAt(int index) {
        const auto* empire = PlayerEmpire();
        if (!empire || index < 0 || index >= static_cast<int>(empire->GetProductionQueue().size()))
            return nullptr;
        return &*empire->GetProductionQueue().find(index);
    }
}

void FOProduction::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    const auto cls = get_class_static();
    ClassDB::bind_static_method(cls, D_METHOD("get_queue"), &FOProduction::get_queue);
    ClassDB::bind_static_method(cls, D_METHOD("get_points"), &FOProduction::get_points);
    ClassDB::bind_static_method(cls, D_METHOD("get_buildable", "location_id"), &FOProduction::get_buildable);
    ClassDB::bind_static_method(cls, D_METHOD("get_production_locations"), &FOProduction::get_production_locations);
    ClassDB::bind_static_method(cls, D_METHOD("get_item_locations", "item"), &FOProduction::get_item_locations);
    ClassDB::bind_static_method(cls, D_METHOD("enqueue_building", "name", "location_id"), &FOProduction::enqueue_building);
    ClassDB::bind_static_method(cls, D_METHOD("enqueue_ship", "design_id", "location_id", "quantity"),
                                &FOProduction::enqueue_ship, DEFVAL(1));
    ClassDB::bind_static_method(cls, D_METHOD("remove", "index"), &FOProduction::remove);
    ClassDB::bind_static_method(cls, D_METHOD("move", "index", "new_index"), &FOProduction::move);
    ClassDB::bind_static_method(cls, D_METHOD("set_quantity", "index", "quantity"), &FOProduction::set_quantity);
    ClassDB::bind_static_method(cls, D_METHOD("set_paused", "index", "paused"), &FOProduction::set_paused);
    ClassDB::bind_static_method(cls, D_METHOD("set_stockpile_allowed", "index", "allowed"),
                                &FOProduction::set_stockpile_allowed);
    ClassDB::bind_static_method(cls, D_METHOD("enqueue_stockpile_project", "location_id"),
                                &FOProduction::enqueue_stockpile_project);
}

godot::Array FOProduction::get_queue() {
    godot::Array result;
    const auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    if (!app || !empire)
        return result;
    const auto& universe = app->GetUniverse();
    int index = 0;
    for (const auto& element : empire->GetProductionQueue()) {
        if (element.to_be_removed) {
            ++index;
            continue;
        }
        godot::Dictionary entry;
        entry["index"] = index++;
        Describe(element.item, universe, entry);
        entry["location_id"] = element.location;
        const auto* location = universe.Objects().getRaw(element.location);
        entry["location_name"] = location ? ToGodot(location->Name()) : godot::String();
        entry["ordered"] = element.ordered;
        entry["remaining"] = element.remaining;
        entry["blocksize"] = element.blocksize;
        entry["progress"] = element.progress;
        entry["allocated_pp"] = element.allocated_pp;
        entry["turns_left"] = element.turns_left_to_completion;
        entry["paused"] = element.paused;
        entry["stockpile_allowed"] = element.allowed_imperial_stockpile_use;
        result.push_back(entry);
    }
    return result;
}

godot::Dictionary FOProduction::get_points() {
    godot::Dictionary points;
    const auto* empire = PlayerEmpire();
    // This turn's output; the stockpile is reported apart, as only a little
    // of it can be drawn each turn.
    points["available"] = empire ? empire->GetIndustryPool().TotalOutput() : 0.0f;
    points["spent"] = empire ? empire->GetProductionQueue().TotalPPsSpent() : 0.0f;
    points["stockpile"] = empire ? empire->GetIndustryPool().Stockpile() : 0.0f;
    if (const auto* app = ClientApp::GetApp(); app && empire) {
        const auto& queue = empire->GetProductionQueue();
        float used = 0.0f;
        for (const auto& [group, pp] : queue.AllocatedStockpilePP())
            used += pp;
        points["stockpile_used"] = used;
        points["stockpile_capacity"] = queue.StockpileCapacity(app->GetUniverse().Objects());
        points["stockpile_expected"] = queue.ExpectedNewStockpileAmount();
    }
    return points;
}

godot::Array FOProduction::get_buildable(int location_id) {
    godot::Array result;
    const auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    if (!app || !empire)
        return result;
    const auto& context = app->GetContext();
    const auto& universe = app->GetUniverse();
    const auto add = [&](const ProductionQueue::ProductionItem& item) {
        godot::Dictionary entry;
        Describe(item, universe, entry);
        const auto [cost, turns] = item.ProductionCostAndTime(empire->EmpireID(), location_id, context);
        entry["cost"] = cost;
        entry["turns"] = turns;
        result.push_back(entry);
    };
    try {
    // The imperial stockpile transfer project, where it can be built.
    if (empire->ProducibleItem(BuildType::BT_STOCKPILE, location_id, context))
        add(ProductionQueue::ProductionItem(BuildType::BT_STOCKPILE));
    for (const auto& name : empire->AvailableBuildingTypes()) {
        if (empire->ProducibleItem(BuildType::BT_BUILDING, name, location_id, context) &&
            empire->EnqueuableItem(BuildType::BT_BUILDING, name, location_id, context))
        { add(ProductionQueue::ProductionItem(BuildType::BT_BUILDING, name)); }
    }
    for (const int design_id : empire->AvailableShipDesigns(universe)) {
        if (empire->ProducibleItem(BuildType::BT_SHIP, design_id, location_id, context))
            add(ProductionQueue::ProductionItem(BuildType::BT_SHIP, design_id, universe));
    }
    } catch (const std::exception& e) {
        // An exception must not unwind into Godot, which would abort the process.
        ErrorLogger() << "FOProduction::get_buildable: " << e.what();
    }
    return result;
}

godot::PackedInt32Array FOProduction::get_production_locations() {
    godot::PackedInt32Array result;
    const auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    if (!app || !empire)
        return result;
    // Owned planets: capital first, then populated planets, then outposts.
    std::vector<int> populated, outposts;
    for (const auto* planet : app->GetUniverse().Objects().allRaw<Planet>()) {
        if (!planet->OwnedBy(empire->EmpireID()) || planet->ID() == empire->CapitalID())
            continue;
        (planet->SpeciesName().empty() ? outposts : populated).push_back(planet->ID());
    }
    if (empire->CapitalID() != INVALID_OBJECT_ID)
        result.push_back(empire->CapitalID());
    for (int id : populated)
        result.push_back(id);
    for (int id : outposts)
        result.push_back(id);
    return result;
}

godot::PackedInt32Array FOProduction::get_item_locations(const godot::Dictionary& item) {
    godot::PackedInt32Array result;
    const auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    if (!app || !empire)
        return result;
    const auto& context = app->GetContext();
    const godot::String build_type = item.get("build_type", "");
    const std::string name = godot::String(item.get("name", "")).utf8().get_data();
    const int design_id = item.get("design_id", INVALID_DESIGN_ID);
    try {
        for (const int location_id : get_production_locations()) {
            bool ok = false;
            if (build_type == "building")
                ok = empire->ProducibleItem(BuildType::BT_BUILDING, name, location_id, context) &&
                     empire->EnqueuableItem(BuildType::BT_BUILDING, name, location_id, context);
            else if (build_type == "ship")
                ok = empire->ProducibleItem(BuildType::BT_SHIP, design_id, location_id, context);
            else if (build_type == "stockpile")
                ok = empire->ProducibleItem(BuildType::BT_STOCKPILE, location_id, context);
            if (ok)
                result.push_back(location_id);
        }
    } catch (const std::exception& e) {
        ErrorLogger() << "FOProduction::get_item_locations: " << e.what();
    }
    return result;
}

bool FOProduction::enqueue_building(const godot::String& name, int location_id) {
    auto* empire = PlayerEmpire();
    const auto* app = ClientApp::GetApp();
    if (!empire || !app)
        return false;
    std::string building = name.utf8().get_data();
    try {
        if (!empire->ProducibleItem(BuildType::BT_BUILDING, building, location_id, app->GetContext()) ||
            !empire->EnqueuableItem(BuildType::BT_BUILDING, building, location_id, app->GetContext()))
        { return false; }
    } catch (const std::exception& e) {
        ErrorLogger() << "FOProduction::enqueue_building: " << e.what();
        return false;
    }
    return IssueQueueOrder(Action::PLACE_IN_QUEUE, empire->EmpireID(),
                           ProductionQueue::ProductionItem(BuildType::BT_BUILDING, std::move(building)),
                           1, location_id);
}

bool FOProduction::enqueue_ship(int design_id, int location_id, int quantity) {
    auto* empire = PlayerEmpire();
    const auto* app = ClientApp::GetApp();
    if (!empire || !app || quantity < 1)
        return false;
    try {
        if (!empire->ProducibleItem(BuildType::BT_SHIP, design_id, location_id, app->GetContext()))
            return false;
    } catch (const std::exception& e) {
        ErrorLogger() << "FOProduction::enqueue_ship: " << e.what();
        return false;
    }
    return IssueQueueOrder(Action::PLACE_IN_QUEUE, empire->EmpireID(),
                           ProductionQueue::ProductionItem(BuildType::BT_SHIP, design_id, app->GetUniverse()),
                           quantity, location_id);
}

bool FOProduction::remove(int index) {
    const auto* element = ElementAt(index);
    return element && IssueQueueOrder(Action::REMOVE_FROM_QUEUE, PlayerEmpire()->EmpireID(), element->uuid);
}

bool FOProduction::move(int index, int new_index) {
    const auto* element = ElementAt(index);
    const auto* empire = PlayerEmpire();
    if (!element || new_index < 0 || new_index >= static_cast<int>(empire->GetProductionQueue().size()))
        return false;
    // Empire::MoveProductionWithinQueue expects the index before removal when moving down.
    const int corrected = new_index + (new_index > index ? 1 : 0);
    return IssueQueueOrder(Action::MOVE_ITEM_TO_INDEX, empire->EmpireID(), element->uuid, corrected);
}

bool FOProduction::set_quantity(int index, int quantity) {
    const auto* element = ElementAt(index);
    return element && quantity >= 1 &&
        IssueQueueOrder(Action::SET_QUANTITY, PlayerEmpire()->EmpireID(), element->uuid, quantity);
}

bool FOProduction::set_paused(int index, bool paused) {
    const auto* element = ElementAt(index);
    return element && element->paused != paused &&
        IssueQueueOrder(paused ? Action::PAUSE_PRODUCTION : Action::RESUME_PRODUCTION,
                        PlayerEmpire()->EmpireID(), element->uuid);
}

bool FOProduction::set_stockpile_allowed(int index, bool allowed) {
    const auto* element = ElementAt(index);
    return element && element->allowed_imperial_stockpile_use != allowed &&
        IssueQueueOrder(allowed ? Action::ALLOW_STOCKPILE_USE : Action::DISALLOW_STOCKPILE_USE,
                        PlayerEmpire()->EmpireID(), element->uuid);
}

bool FOProduction::enqueue_stockpile_project(int location_id) {
    auto* empire = PlayerEmpire();
    const auto* app = ClientApp::GetApp();
    if (!empire || !app || !empire->ProducibleItem(BuildType::BT_STOCKPILE, location_id, app->GetContext()))
        return false;
    return IssueQueueOrder(Action::PLACE_IN_QUEUE, empire->EmpireID(),
                           ProductionQueue::ProductionItem(BuildType::BT_STOCKPILE), 1, location_id);
}
