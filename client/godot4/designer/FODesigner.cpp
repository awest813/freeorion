#include "FODesigner.h"

#include <boost/optional.hpp>
#include <godot_cpp/core/class_db.hpp>

#include "../../ClientApp.h"
#include "../../../Empire/Empire.h"
#include "../../../universe/ShipDesign.h"
#include "../../../universe/ShipHull.h"
#include "../../../universe/ShipPart.h"
#include "../../../universe/Universe.h"
#include "../../../util/Logger.h"
#include "../../../util/Order.h"
#include "../../../util/OrderSet.h"

namespace {
    godot::String ToGodot(std::string_view s)
    { return godot::String::utf8(s.data(), static_cast<int>(s.size())); }

    std::string ToStd(const godot::String& s)
    { return s.utf8().get_data(); }

    std::vector<std::string> ToVector(const godot::PackedStringArray& parts) {
        std::vector<std::string> result;
        result.reserve(parts.size());
        for (int64_t i = 0; i < parts.size(); ++i)
            result.push_back(ToStd(parts[i]));
        return result;
    }

    godot::PackedStringArray ToPacked(const std::vector<std::string>& parts) {
        godot::PackedStringArray result;
        for (const auto& part : parts)
            result.push_back(ToGodot(part));
        return result;
    }

    const char* SlotName(ShipSlotType type) {
        switch (type) {
        case ShipSlotType::SL_EXTERNAL: return "external";
        case ShipSlotType::SL_INTERNAL: return "internal";
        case ShipSlotType::SL_CORE:     return "core";
        default:                        return "";
        }
    }

    Empire* PlayerEmpire() {
        auto* app = ClientApp::GetApp();
        return app ? app->GetEmpire(app->EmpireID()) : nullptr;
    }
}

void FODesigner::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    const auto cls = get_class_static();
    ClassDB::bind_static_method(cls, D_METHOD("get_hulls"), &FODesigner::get_hulls);
    ClassDB::bind_static_method(cls, D_METHOD("get_parts"), &FODesigner::get_parts);
    ClassDB::bind_static_method(cls, D_METHOD("evaluate", "hull", "parts"), &FODesigner::evaluate);
    ClassDB::bind_static_method(cls, D_METHOD("create", "name", "hull", "parts"), &FODesigner::create);
    ClassDB::bind_static_method(cls, D_METHOD("get_designs"), &FODesigner::get_designs);
}

godot::Array FODesigner::get_hulls() {
    godot::Array result;
    const auto* empire = PlayerEmpire();
    if (!empire)
        return result;
    for (const auto& name : empire->AvailableShipHulls()) {
        const auto* hull = GetShipHull(name);
        if (!hull)
            continue;
        godot::Dictionary entry;
        entry["name"] = ToGodot(name);
        entry["icon"] = ToGodot(hull->Icon());
        entry["graphic"] = ToGodot(hull->Graphic());
        entry["structure"] = hull->Structure();
        entry["speed"] = hull->Speed();
        entry["fuel"] = hull->Fuel();
        godot::Array slots;
        for (const auto& slot : hull->Slots()) {
            godot::Dictionary s;
            s["type"] = SlotName(slot.type);
            s["x"] = slot.x;
            s["y"] = slot.y;
            slots.push_back(s);
        }
        entry["slots"] = slots;
        result.push_back(entry);
    }
    return result;
}

godot::Array FODesigner::get_parts() {
    godot::Array result;
    const auto* empire = PlayerEmpire();
    if (!empire)
        return result;
    for (const auto& name : empire->AvailableShipParts()) {
        const auto* part = GetShipPart(name);
        if (!part)
            continue;
        godot::Dictionary entry;
        entry["name"] = ToGodot(name);
        entry["icon"] = ToGodot(part->Icon());
        entry["class"] = ToGodot(::to_string(part->Class()));
        entry["capacity"] = part->Capacity();
        godot::PackedStringArray mountable;
        for (const auto type : {ShipSlotType::SL_EXTERNAL, ShipSlotType::SL_INTERNAL, ShipSlotType::SL_CORE})
            if (part->CanMountInSlotType(type))
                mountable.push_back(SlotName(type));
        entry["mountable"] = mountable;
        result.push_back(entry);
    }
    return result;
}

godot::Dictionary FODesigner::evaluate(const godot::String& hull, const godot::PackedStringArray& parts) {
    godot::Dictionary stats;
    const auto hull_name = ToStd(hull);
    auto part_names = ToVector(parts);
    const bool valid = ShipDesign::ValidDesign(hull_name, part_names);
    stats["valid"] = valid;
    const auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    if (!valid || !app || !empire)
        return stats;
    try {
        const ShipDesign design(boost::none, "", "", app->CurrentTurn(), empire->EmpireID(),
                                hull_name, std::move(part_names), "", "");
        const auto& context = app->GetContext();
        stats["attack"] = design.Attack();
        stats["structure"] = design.Structure();
        stats["shields"] = design.Shields();
        stats["speed"] = design.Speed();
        stats["fuel"] = design.Fuel();
        stats["detection"] = design.Detection();
        stats["stealth"] = design.Stealth();
        stats["colony"] = design.ColonyCapacity();
        stats["troops"] = design.TroopCapacity();
        // Costs can depend on where the ship is built: price it at the capital.
        stats["cost"] = design.ProductionCost(empire->EmpireID(), empire->CapitalID(), context);
        stats["turns"] = design.ProductionTime(empire->EmpireID(), empire->CapitalID(), context);
    } catch (const std::exception& e) {
        // An exception must not unwind into Godot, which would abort the process.
        ErrorLogger() << "FODesigner::evaluate: " << e.what();
        stats["valid"] = false;
    }
    return stats;
}

int FODesigner::create(const godot::String& name, const godot::String& hull,
                       const godot::PackedStringArray& parts)
{
    auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    if (!app || !empire)
        return -1;
    const auto design_name = ToStd(name.strip_edges());
    const auto hull_name = ToStd(hull);
    auto part_names = ToVector(parts);
    auto& context = app->GetContext();
    if (design_name.empty() ||
        !ShipDesignOrder::CheckNew(empire->EmpireID(), design_name, "", hull_name, part_names, context))
    { return -1; }
    try {
        const ShipDesign design(boost::none, design_name, "", app->CurrentTurn(), empire->EmpireID(),
                                hull_name, std::move(part_names), "", "");
        const auto order = app->Orders().IssueOrder<ShipDesignOrder>(context, empire->EmpireID(), design);
        return order ? order->DesignID() : -1;
    } catch (const std::exception& e) {
        ErrorLogger() << "FODesigner::create: " << e.what();
        return -1;
    }
}

godot::Array FODesigner::get_designs() {
    godot::Array result;
    const auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    if (!app || !empire)
        return result;
    const auto& universe = app->GetUniverse();
    for (const int id : empire->ShipDesigns()) {
        const auto* design = universe.GetShipDesign(id);
        if (!design)
            continue;
        godot::Dictionary entry;
        entry["id"] = id;
        entry["name"] = ToGodot(design->Name(true));
        entry["hull"] = ToGodot(design->Hull());
        entry["parts"] = ToPacked(design->Parts());
        entry["producible"] = empire->ShipDesignAvailable(*design);
        result.push_back(entry);
    }
    return result;
}
