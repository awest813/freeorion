#include "FODesigner.h"

#include <algorithm>

#include <fstream>
#include <boost/optional.hpp>
#include <boost/uuid/random_generator.hpp>
#include <boost/uuid/uuid_io.hpp>
#include <godot_cpp/core/class_db.hpp>

#include "../../ClientApp.h"
#include "../../../Empire/Empire.h"
#include "../../../universe/ShipDesign.h"
#include "../../../universe/ShipHull.h"
#include "../../../universe/ShipPart.h"
#include "../../../universe/Universe.h"
#include "../../../parse/Parse.h"
#include "../../../util/Directories.h"
#include "../../../util/Logger.h"
#include "../../../util/Order.h"
#include "../../../util/OrderSet.h"
#include "../../../util/i18n.h"

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

    // Where and how the GG client keeps saved designs (UI/DesignWnd.cpp).
    constexpr std::string_view DESIGN_FILENAME_PREFIX = "ShipDesign-";
    constexpr std::string_view DESIGN_FILENAME_EXTENSION = ".focs.txt";

    std::filesystem::path SavedDesignsDir() { return GetUserDataDir() / "shipdesigns/"; }

    std::filesystem::path SavedDesignPath(const boost::uuids::uuid& uuid) {
        return SavedDesignsDir() / (std::string{DESIGN_FILENAME_PREFIX} + boost::uuids::to_string(uuid) +
                                    std::string{DESIGN_FILENAME_EXTENSION});
    }

    // The saved designs, parsed afresh: uuid -> (design, file).
    auto SavedDesigns() {
        std::decay_t<decltype(std::get<1>(LoadShipDesignsAndManifestOrderFromParseResults(
            std::declval<PredefinedShipDesignManager::ParsedShipDesignsType&>())))> designs;
        std::vector<boost::uuids::uuid> ordering;
        std::error_code ec;
        if (!std::filesystem::exists(SavedDesignsDir(), ec))
            return std::pair{std::move(designs), ordering};
        try {
            auto parsed = parse::ship_designs(SavedDesignsDir());
            auto [inconsistent, loaded, order] = LoadShipDesignsAndManifestOrderFromParseResults(parsed);
            designs = std::move(loaded);
            ordering = std::move(order);
            // Designs the manifest doesn't list yet (it may not exist): after
            // the listed ones, by name.
            std::vector<std::pair<std::string, boost::uuids::uuid>> rest;
            for (const auto& [uuid, design_and_path] : designs)
                if (std::find(ordering.begin(), ordering.end(), uuid) == ordering.end())
                    rest.emplace_back(design_and_path.first->Name(true), uuid);
            std::sort(rest.begin(), rest.end());
            for (const auto& name_and_uuid : rest)
                ordering.push_back(name_and_uuid.second);
        } catch (const std::exception& e) {
            ErrorLogger() << "FODesigner: reading saved designs: " << e.what();
        }
        return std::pair{std::move(designs), ordering};
    }

    Empire* PlayerEmpire() {
        auto* app = ClientApp::GetApp();
        return app ? app->GetEmpire(app->EmpireID()) : nullptr;
    }
}

void FODesigner::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    const auto cls = get_class_static();
    ClassDB::bind_static_method(cls, D_METHOD("get_hulls", "include_unavailable"), &FODesigner::get_hulls, DEFVAL(false));
    ClassDB::bind_static_method(cls, D_METHOD("get_parts", "include_unavailable"), &FODesigner::get_parts, DEFVAL(false));
    ClassDB::bind_static_method(cls, D_METHOD("evaluate", "hull", "parts"), &FODesigner::evaluate);
    ClassDB::bind_static_method(cls, D_METHOD("create", "name", "hull", "parts", "description"), &FODesigner::create, DEFVAL(""));
    ClassDB::bind_static_method(cls, D_METHOD("update_design", "design_id", "name", "hull", "parts", "description"),
                                &FODesigner::update_design);
    ClassDB::bind_static_method(cls, D_METHOD("update_saved", "uuid", "name", "hull", "parts", "description"),
                                &FODesigner::update_saved);
    ClassDB::bind_static_method(cls, D_METHOD("set_part_obsolete", "name", "obsolete"), &FODesigner::set_part_obsolete);
    ClassDB::bind_static_method(cls, D_METHOD("set_hull_obsolete", "name", "obsolete"), &FODesigner::set_hull_obsolete);
    ClassDB::bind_static_method(cls, D_METHOD("get_designs", "kind"), &FODesigner::get_designs, DEFVAL("empire"));
    ClassDB::bind_static_method(cls, D_METHOD("set_obsolete", "design_id", "obsolete"), &FODesigner::set_obsolete);
    ClassDB::bind_static_method(cls, D_METHOD("move_design", "design_id", "before_id"), &FODesigner::move_design);
    ClassDB::bind_static_method(cls, D_METHOD("delete_design", "design_id"), &FODesigner::delete_design);
    ClassDB::bind_static_method(cls, D_METHOD("rename_design", "design_id", "new_name"), &FODesigner::rename_design);
    ClassDB::bind_static_method(cls, D_METHOD("add_premade", "design_id"), &FODesigner::add_premade);
    ClassDB::bind_static_method(cls, D_METHOD("save_design", "design_id"), &FODesigner::save_design);
    ClassDB::bind_static_method(cls, D_METHOD("add_saved", "uuid"), &FODesigner::add_saved);
    ClassDB::bind_static_method(cls, D_METHOD("delete_saved", "uuid"), &FODesigner::delete_saved);
    ClassDB::bind_static_method(cls, D_METHOD("add_all_saved"), &FODesigner::add_all_saved);
}

namespace {
    // A hull's or part's cost at the capital (costs can depend on where).
    template <typename T>
    float CostAtCapital(const T& item, const Empire& empire) {
        try {
            return item.ProductionCost(empire.EmpireID(), empire.CapitalID(), ClientApp::GetApp()->GetContext());
        } catch (const std::exception& e) {
            ErrorLogger() << "FODesigner: cost: " << e.what();
        }
        return 0.0f;
    }
}

godot::Array FODesigner::get_hulls(bool include_unavailable) {
    godot::Array result;
    const auto* empire = PlayerEmpire();
    if (!empire)
        return result;
    for (const auto& [name, hull_ptr] : GetShipHullManager()) {
        const auto* hull = hull_ptr.get();
        if (!hull || !hull->Producible())
            continue;
        const bool available = empire->ShipHullAvailable(name);
        if (!available && !include_unavailable)
            continue;
        godot::Dictionary entry;
        entry["name"] = ToGodot(name);
        entry["icon"] = ToGodot(hull->Icon());
        entry["graphic"] = ToGodot(hull->Graphic());
        entry["description"] = ToGodot(hull->Description());
        entry["structure"] = hull->Structure();
        entry["speed"] = hull->Speed();
        entry["fuel"] = hull->Fuel();
        entry["stealth"] = hull->Stealth();
        entry["cost"] = CostAtCapital(*hull, *empire);
        entry["available"] = available;
        entry["obsolete"] = ObsoleteHulls().contains(name);
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

godot::Array FODesigner::get_parts(bool include_unavailable) {
    godot::Array result;
    const auto* empire = PlayerEmpire();
    if (!empire)
        return result;
    for (const auto& [name, part_ptr] : GetShipPartManager()) {
        const auto* part = part_ptr.get();
        if (!part || !part->Producible())
            continue;
        const bool available = empire->ShipPartAvailable(name);
        if (!available && !include_unavailable)
            continue;
        godot::Dictionary entry;
        entry["name"] = ToGodot(name);
        entry["icon"] = ToGodot(part->Icon());
        entry["class"] = ToGodot(::to_string(part->Class()));
        entry["capacity"] = part->Capacity();
        entry["secondary"] = part->SecondaryStat();
        entry["description"] = ToGodot(part->Description());
        entry["cost"] = CostAtCapital(*part, *empire);
        entry["available"] = available;
        entry["obsolete"] = ObsoleteParts().contains(name);
        godot::PackedStringArray mountable;
        for (const auto type : {ShipSlotType::SL_EXTERNAL, ShipSlotType::SL_INTERNAL, ShipSlotType::SL_CORE})
            if (part->CanMountInSlotType(type))
                mountable.push_back(SlotName(type));
        entry["mountable"] = mountable;
        result.push_back(entry);
    }
    return result;
}

std::set<std::string>& FODesigner::ObsoleteParts() {
    static std::set<std::string> obsolete;
    return obsolete;
}

std::set<std::string>& FODesigner::ObsoleteHulls() {
    static std::set<std::string> obsolete;
    return obsolete;
}

bool FODesigner::set_part_obsolete(const godot::String& name, bool obsolete) {
    const auto part = ToStd(name);
    if (!GetShipPart(part))
        return false;
    if (obsolete)
        ObsoleteParts().insert(part);
    else
        ObsoleteParts().erase(part);
    return true;
}

bool FODesigner::set_hull_obsolete(const godot::String& name, bool obsolete) {
    const auto hull = ToStd(name);
    if (!GetShipHull(hull))
        return false;
    if (obsolete)
        ObsoleteHulls().insert(hull);
    else
        ObsoleteHulls().erase(hull);
    return true;
}

namespace {
    // Why hull and parts don't make a design, as the GG designer tells:
    // a part the hull excludes or two parts excluding each other, a part in
    // a slot it can't go in, more parts than slots.
    std::vector<std::string> DesignProblems(const std::string& hull_name, const std::vector<std::string>& parts) {
        std::vector<std::string> problems;
        const auto* hull = GetShipHull(hull_name);
        if (!hull) {
            problems.push_back(UserString("DESIGN_INV_NO_HULL"));
            return problems;
        }
        const auto conflict = [&](std::string_view a, std::string_view b) {
            problems.push_back(boost::io::str(FlexibleFormat(UserString("DESIGN_WND_COMPONENT_CONFLICT_DETAIL"))
                                              % UserString(a) % UserString(b)));
        };
        for (const auto& part_name : parts)
            if (!part_name.empty() &&
                std::find(hull->Exclusions().begin(), hull->Exclusions().end(), part_name) != hull->Exclusions().end())
            { conflict(hull_name, part_name); }
        std::set<std::string_view> seen{hull_name};
        for (const auto& part_name : parts) {
            const auto* part = GetShipPart(part_name);
            if (!part)
                continue;
            for (const auto& excluded : part->Exclusions())
                if (seen.contains(excluded) && excluded != part_name)
                    conflict(part_name, excluded);
            seen.insert(part_name);
        }
        const auto& slots = hull->Slots();
        if (parts.size() > slots.size())
            problems.push_back(UserString("DESIGNER_TOO_MANY_PARTS"));
        for (std::size_t i = 0; i < std::min(parts.size(), slots.size()); ++i) {
            const auto* part = GetShipPart(parts[i]);
            if (part && !part->CanMountInSlotType(slots[i].type))
                problems.push_back(boost::io::str(FlexibleFormat(UserString("DESIGNER_WRONG_SLOT"))
                                                  % UserString(parts[i])));
        }
        return problems;
    }
}

godot::Dictionary FODesigner::evaluate(const godot::String& hull, const godot::PackedStringArray& parts) {
    godot::Dictionary stats;
    const auto hull_name = ToStd(hull);
    auto part_names = ToVector(parts);
    const bool valid = ShipDesign::ValidDesign(hull_name, part_names);
    stats["valid"] = valid;
    const auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    godot::PackedStringArray problems;
    if (!valid)
        for (const auto& problem : DesignProblems(hull_name, part_names))
            problems.push_back(ToGodot(problem));
    stats["problems"] = problems;
    // What the empire can't build yet: the hull or parts not available.
    godot::PackedStringArray unavailable;
    if (empire) {
        if (!hull_name.empty() && !empire->ShipHullAvailable(hull_name))
            unavailable.push_back(ToGodot(hull_name));
        for (const auto& part_name : part_names)
            if (!part_name.empty() && !empire->ShipPartAvailable(part_name) && !unavailable.has(ToGodot(part_name)))
                unavailable.push_back(ToGodot(part_name));
    }
    stats["unavailable"] = unavailable;
    if (!valid || !app || !empire)
        return stats;
    // An own design with the same hull and parts (GG's "duplicates").
    for (const int id : empire->ShipDesigns()) {
        const auto* own = app->GetUniverse().GetShipDesign(id);
        if (own && own->Hull() == hull_name && own->Parts() == part_names) {
            stats["duplicate_of"] = ToGodot(own->Name(true));
            break;
        }
    }
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
                       const godot::PackedStringArray& parts, const godot::String& description)
{
    auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    if (!app || !empire)
        return -1;
    const auto design_name = ToStd(name.strip_edges());
    const auto hull_name = ToStd(hull);
    const auto design_description = ToStd(description.strip_edges());
    auto part_names = ToVector(parts);
    auto& context = app->GetContext();
    if (design_name.empty() ||
        !ShipDesignOrder::CheckNew(empire->EmpireID(), design_name, design_description, hull_name, part_names, context))
    { return -1; }
    try {
        // A UUID of its own, as the GG designer gives: saved designs are
        // told apart by it.
        const ShipDesign design(boost::none, design_name, design_description, app->CurrentTurn(), empire->EmpireID(),
                                hull_name, std::move(part_names), "", "", false,
                                ShipDesign::Monster::NOTMONSTER, boost::uuids::random_generator()());
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
        entry["description"] = ToGodot(design->Description(true));
        // Only designs the empire made itself can be renamed.
        entry["renamable"] = design->DesignedByEmpire() == empire->EmpireID();
        result.push_back(entry);
    };
    if (kind == "empire") {
        const auto& known = empire->ShipDesigns();
        for (const int id : Ordered({known.begin(), known.end()}))
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
    } else if (kind == "saved") {
        auto [designs, ordering] = SavedDesigns();
        for (const auto& uuid : ordering) {
            const auto it = designs.find(uuid);
            if (it == designs.end())
                continue;
            add(it->second.first.get());
            godot::Dictionary entry = result.back();
            entry["uuid"] = ToGodot(boost::uuids::to_string(uuid));
            // Already one of the empire's designs?
            entry["added"] = false;
            for (const int id : empire->ShipDesigns())
                if (const auto* own = universe.GetShipDesign(id); own && own->UUID() == uuid)
                    entry["added"] = true;
        }
    }
    return result;
}

std::vector<int>& FODesigner::DesignOrder() {
    static std::vector<int> order;
    return order;
}

std::vector<int> FODesigner::Ordered(std::vector<int> ids) {
    const auto& order = DesignOrder();
    const auto rank = [&order](int id) {
        const auto it = std::find(order.begin(), order.end(), id);
        return it == order.end() ? order.size() : static_cast<std::size_t>(it - order.begin());
    };
    std::stable_sort(ids.begin(), ids.end(), [&rank](int a, int b) { return rank(a) < rank(b); });
    return ids;
}

bool FODesigner::move_design(int design_id, int before_id) {
    try {
        const auto* app = ClientApp::GetApp();
        const auto* empire = app ? app->GetEmpire(app->EmpireID()) : nullptr;
        if (!empire || !empire->ShipDesigns().contains(design_id) || design_id == before_id)
            return false;
        // Start from the order as shown, so designs not yet placed keep theirs.
        const auto& known = empire->ShipDesigns();
        auto order = Ordered({known.begin(), known.end()});
        order.erase(std::remove(order.begin(), order.end(), design_id), order.end());
        const auto at = std::find(order.begin(), order.end(), before_id);
        order.insert(at, design_id);
        DesignOrder() = std::move(order);
        return true;
    } catch (const std::exception& e) {
        ErrorLogger() << "FODesigner::move_design: " << e.what();
        return false;
    }
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

bool FODesigner::save_design(int design_id) {
    const auto* app = ClientApp::GetApp();
    const auto* design = app ? app->GetUniverse().GetShipDesign(design_id) : nullptr;
    if (!design)
        return false;
    try {
        std::error_code ec;
        std::filesystem::create_directories(SavedDesignsDir(), ec);
        // Designs made before they had UUIDs get one for the file.
        auto copy{*design};
        if (copy.UUID().is_nil())
            copy.SetUUID(boost::uuids::random_generator()());
        std::ofstream file(SavedDesignPath(copy.UUID()));
        if (!file)
            return false;
        file << copy.Dump();
        return static_cast<bool>(file);
    } catch (const std::exception& e) {
        ErrorLogger() << "FODesigner::save_design: " << e.what();
    }
    return false;
}

int FODesigner::add_saved(const godot::String& uuid_text) {
    auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    if (!app || !empire)
        return -1;
    auto [designs, ordering] = SavedDesigns();
    for (const auto& [uuid, design_and_path] : designs) {
        if (ToGodot(boost::uuids::to_string(uuid)) != uuid_text)
            continue;
        // Added already: that design.
        for (const int id : empire->ShipDesigns())
            if (const auto* own = app->GetUniverse().GetShipDesign(id); own && own->UUID() == uuid)
                return id;
        try {
            auto order = app->Orders().IssueOrder<ShipDesignOrder>(
                app->GetContext(), empire->EmpireID(), *design_and_path.first);
            return order ? order->DesignID() : -1;
        } catch (const std::exception& e) {
            ErrorLogger() << "FODesigner::add_saved: " << e.what();
        }
        return -1;
    }
    return -1;
}

bool FODesigner::delete_saved(const godot::String& uuid_text) {
    auto [designs, ordering] = SavedDesigns();
    for (const auto& [uuid, design_and_path] : designs) {
        if (ToGodot(boost::uuids::to_string(uuid)) != uuid_text)
            continue;
        std::error_code ec;
        return std::filesystem::remove(design_and_path.second, ec);
    }
    return false;
}

int FODesigner::add_all_saved() {
    int added = 0;
    auto [designs, ordering] = SavedDesigns();
    for (const auto& uuid : ordering)
        if (add_saved(ToGodot(boost::uuids::to_string(uuid))) >= 0)
            ++added;
    return added;
}

// As GG's "Update Finished Design": the new design takes the old one's
// place; the old one is forgotten (ships already queued keep it).
int FODesigner::update_design(int design_id, const godot::String& name, const godot::String& hull,
                              const godot::PackedStringArray& parts, const godot::String& description)
{
    auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    if (!app || !empire || !app->GetUniverse().GetShipDesign(design_id))
        return -1;
    const int new_id = create(name, hull, parts, description);
    if (new_id < 0)
        return -1;
    if (ObsoleteDesigns().erase(design_id) == 0 &&
        ShipDesignOrder::CheckErase(empire->EmpireID(), design_id, true, app->GetContext()))
    { IssueDesignOrder(empire->EmpireID(), design_id, true); }
    return new_id;
}

// As GG's "Update Saved Design": the saved design's file is rewritten.
bool FODesigner::update_saved(const godot::String& uuid_text, const godot::String& name, const godot::String& hull,
                              const godot::PackedStringArray& parts, const godot::String& description)
{
    const auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    const auto design_name = ToStd(name.strip_edges());
    auto part_names = ToVector(parts);
    if (!app || design_name.empty() || !ShipDesign::ValidDesign(ToStd(hull), part_names))
        return false;
    auto [designs, ordering] = SavedDesigns();
    for (const auto& [uuid, design_and_path] : designs) {
        if (ToGodot(boost::uuids::to_string(uuid)) != uuid_text)
            continue;
        try {
            const ShipDesign design(boost::none, design_name, ToStd(description.strip_edges()), app->CurrentTurn(),
                                    empire ? empire->EmpireID() : ALL_EMPIRES, ToStd(hull), std::move(part_names),
                                    "", "", false, ShipDesign::Monster::NOTMONSTER, uuid);
            std::ofstream file(design_and_path.second);
            if (!file)
                return false;
            file << design.Dump();
            return static_cast<bool>(file);
        } catch (const std::exception& e) {
            ErrorLogger() << "FODesigner::update_saved: " << e.what();
        }
        return false;
    }
    return false;
}
