#include "FODesigner.h"

#include <boost/optional.hpp>
#include <boost/uuid/random_generator.hpp>
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
    ClassDB::bind_static_method(cls, D_METHOD("get_designs", "kind"), &FODesigner::get_designs, DEFVAL("empire"));
    ClassDB::bind_static_method(cls, D_METHOD("set_obsolete", "design_id", "obsolete"), &FODesigner::set_obsolete);
    ClassDB::bind_static_method(cls, D_METHOD("delete_design", "design_id"), &FODesigner::delete_design);
    ClassDB::bind_static_method(cls, D_METHOD("rename_design", "design_id", "new_name"), &FODesigner::rename_design);
    ClassDB::bind_static_method(cls, D_METHOD("add_premade", "design_id"), &FODesigner::add_premade);
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

godot::Array FODesigner::get_designs(const godot::String& kind) {
    godot::Array result;
    const auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    if (!app || !empire)
        return result;
    const auto& universe = app->GetUniverse();
    const auto add = [&](const ShipDesign* design) {
        if (!design)
            return;
        godot::Dictionary entry;
        entry["id"] = design->ID();
        entry["name"] = ToGodot(design->Name(true));
        entry["hull"] = ToGodot(design->Hull());
        entry["parts"] = ToPacked(design->Parts());
        entry["producible"] = empire->ShipDesignAvailable(*design);
        result.push_back(entry);
    };
    if (kind == "empire") {
        for (const int id : empire->ShipDesigns())
            if (!ObsoleteDesigns().contains(id))
                add(universe.GetShipDesign(id));
    } else if (kind == "obsolete") {
        for (const int id : ObsoleteDesigns())
            add(universe.GetShipDesign(id));
    } else if (kind == "premade") {
        for (const auto* design : GetPredefinedShipDesignManager().GetOrderedShipDesigns())
            add(design);
    } else if (kind == "monster") {
        for (const auto* design : GetPredefinedShipDesignManager().GetOrderedMonsterDesigns())
            add(design);
    }
    return result;
}

std::set<int>& FODesigner::ObsoleteDesigns() {
    static std::set<int> obsolete;
    return obsolete;
}

namespace {
    template <typename... Args>
    bool IssueDesignOrder(Args&&... args) {
        auto* app = ClientApp::GetApp();
        if (!app)
            return false;
        try {
            app->Orders().IssueOrder<ShipDesignOrder>(app->GetContext(), std::forward<Args>(args)...);
            return true;
        } catch (const std::exception& e) {
            ErrorLogger() << "FODesigner: design order failed: " << e.what();
        }
        return false;
    }
}

// As the GG designer: putting a design aside makes the empire forget it on
// the server; bringing it back makes it remember it again.
bool FODesigner::set_obsolete(int design_id, bool obsolete) {
    auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    if (!app || !empire)
        return false;
    const auto& context = app->GetContext();
    const int empire_id = empire->EmpireID();
    if (obsolete) {
        if (!ShipDesignOrder::CheckErase(empire_id, design_id, true, context) ||
            !IssueDesignOrder(empire_id, design_id, true))
        { return false; }
        ObsoleteDesigns().insert(design_id);
        return true;
    }
    if (!ObsoleteDesigns().contains(design_id) ||
        !ShipDesignOrder::CheckRemember(empire_id, design_id, context) ||
        !IssueDesignOrder(empire_id, design_id))
    { return false; }
    ObsoleteDesigns().erase(design_id);
    return true;
}

bool FODesigner::delete_design(int design_id) {
    auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    if (!app || !empire)
        return false;
    // Put-aside designs are already forgotten by the empire.
    if (ObsoleteDesigns().erase(design_id) > 0)
        return true;
    return ShipDesignOrder::CheckErase(empire->EmpireID(), design_id, true, app->GetContext()) &&
        IssueDesignOrder(empire->EmpireID(), design_id, true);
}

bool FODesigner::rename_design(int design_id, const godot::String& new_name) {
    auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    const auto* design = app ? app->GetUniverse().GetShipDesign(design_id) : nullptr;
    std::string name = new_name.strip_edges().utf8().get_data();
    if (!empire || !design || name.empty() ||
        !ShipDesignOrder::CheckRename(empire->EmpireID(), design_id, name, design->Description(), app->GetContext()))
    { return false; }
    return IssueDesignOrder(empire->EmpireID(), design_id, std::move(name), std::string{design->Description()});
}

int FODesigner::add_premade(int design_id) {
    auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    // Premade designs live with the predefined design manager, not in the
    // universe's design table.
    const ShipDesign* design = nullptr;
    for (const auto* premade : GetPredefinedShipDesignManager().GetOrderedShipDesigns())
        if (premade && premade->ID() == design_id)
            design = premade;
    if (!app || !empire || !design)
        return -1;
    // A copy with its own UUID, so the empire's design is distinct.
    auto copy{*design};
    copy.SetUUID(boost::uuids::random_generator()());
    try {
        auto order = app->Orders().IssueOrder<ShipDesignOrder>(app->GetContext(), empire->EmpireID(), copy);
        return order ? order->DesignID() : -1;
    } catch (const std::exception& e) {
        ErrorLogger() << "FODesigner::add_premade: " << e.what();
    }
    return -1;
}
