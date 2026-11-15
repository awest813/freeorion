#include "FOResearch.h"

#include <godot_cpp/core/class_db.hpp>

#include "../../ClientApp.h"
#include "../../../Empire/Empire.h"
#include "../../../universe/Tech.h"
#include "../../../util/Logger.h"
#include "../../../util/Order.h"
#include "../../../util/OrderSet.h"

namespace {
    godot::String ToGodot(std::string_view s)
    { return godot::String::utf8(s.data(), static_cast<int>(s.size())); }

    Empire* PlayerEmpire() {
        auto* app = ClientApp::GetApp();
        return app ? app->GetEmpire(app->EmpireID()) : nullptr;
    }

    const char* StatusName(TechStatus status) {
        switch (status) {
        case TechStatus::TS_COMPLETE:              return "complete";
        case TechStatus::TS_RESEARCHABLE:          return "researchable";
        case TechStatus::TS_HAS_RESEARCHED_PREREQ: return "partial";
        default:                                   return "unresearchable";
        }
    }

    void Reproject(Empire& empire, ScriptingContext& context)
    { empire.UpdateResearchQueue(context, empire.TechCostsTimes(context)); }
}

void FOResearch::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    const auto cls = get_class_static();
    ClassDB::bind_static_method(cls, D_METHOD("get_queue"), &FOResearch::get_queue);
    ClassDB::bind_static_method(cls, D_METHOD("get_points"), &FOResearch::get_points);
    ClassDB::bind_static_method(cls, D_METHOD("get_techs"), &FOResearch::get_techs);
    ClassDB::bind_static_method(cls, D_METHOD("get_categories"), &FOResearch::get_categories);
    ClassDB::bind_static_method(cls, D_METHOD("enqueue", "name", "position"), &FOResearch::enqueue, DEFVAL(-1));
    ClassDB::bind_static_method(cls, D_METHOD("remove", "name"), &FOResearch::remove);
    ClassDB::bind_static_method(cls, D_METHOD("move", "name", "position"), &FOResearch::move);
}

godot::Array FOResearch::get_queue() {
    godot::Array result;
    const auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    if (!app || !empire)
        return result;
    const auto& context = app->GetContext();
    int index = 0;
    for (const auto& element : empire->GetResearchQueue()) {
        godot::Dictionary entry;
        entry["index"] = index++;
        entry["name"] = ToGodot(element.name);
        const auto* tech = GetTech(element.name);
        const float cost = tech ? tech->ResearchCost(empire->EmpireID(), context) : 0.0f;
        entry["category"] = tech ? ToGodot(tech->Category()) : godot::String();
        entry["icon"] = tech ? ToGodot(tech->Graphic()) : godot::String();
        entry["cost"] = cost;
        entry["allocated_rp"] = element.allocated_rp;
        entry["turns_left"] = element.turns_left;
        entry["progress"] = cost > 0.0f ? empire->ResearchProgress(element.name, context) / cost : 0.0f;
        result.push_back(entry);
    }
    return result;
}

godot::Dictionary FOResearch::get_points() {
    godot::Dictionary points;
    const auto* empire = PlayerEmpire();
    points["available"] = empire ? empire->GetResearchPool().TotalAvailable() : 0.0f;
    points["spent"] = empire ? empire->GetResearchQueue().TotalRPsSpent() : 0.0f;
    return points;
}

godot::Array FOResearch::get_techs() {
    godot::Array result;
    const auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    if (!app || !empire)
        return result;
    const auto& context = app->GetContext();
    const auto& queue = empire->GetResearchQueue();
    try {
        for (const auto& [name, tech] : GetTechManager()) {
            if (!tech.Researchable())
                continue;
            godot::Dictionary entry;
            entry["name"] = ToGodot(name);
            entry["category"] = ToGodot(tech.Category());
            entry["icon"] = ToGodot(tech.Graphic());
            entry["short_description"] = ToGodot(tech.ShortDescription());
            const float cost = tech.ResearchCost(empire->EmpireID(), context);
            entry["cost"] = cost;
            entry["turns"] = tech.ResearchTime(empire->EmpireID(), context);
            entry["status"] = StatusName(empire->GetTechStatus(name));
            entry["in_queue"] = queue.InQueue(name);
            entry["progress"] = cost > 0.0f ? empire->ResearchProgress(name, context) / cost : 0.0f;
            godot::PackedStringArray prerequisites;
            for (const auto& prereq : tech.Prerequisites())
                prerequisites.push_back(ToGodot(prereq));
            entry["prerequisites"] = prerequisites;
            result.push_back(entry);
        }
    } catch (const std::exception& e) {
        // An exception must not unwind into Godot, which would abort the process.
        ErrorLogger() << "FOResearch::get_techs: " << e.what();
    }
    return result;
}

godot::PackedStringArray FOResearch::get_categories() {
    godot::PackedStringArray result;
    for (const auto& category : GetTechManager().CategoryNames())
        result.push_back(ToGodot(category));
    return result;
}

bool FOResearch::enqueue(const godot::String& name, int position) {
    auto* app = ClientApp::GetApp();
    auto* empire = PlayerEmpire();
    std::string tech_name = name.utf8().get_data();
    if (!app || !empire || !GetTech(tech_name) || empire->TechResearched(tech_name))
        return false;
    auto& context = app->GetContext();
    try {
        // Prerequisites first (cheapest first, as RecursivePrereqs orders them).
        auto techs = GetTechManager().RecursivePrereqs(tech_name, empire->EmpireID(), context);
        techs.push_back(tech_name);
        int pos = position;
        for (auto& tech : techs) {
            if (empire->TechResearched(tech))
                continue;
            const auto& queue = empire->GetResearchQueue();
            const bool queued = queue.InQueue(tech);
            if (pos < 0) {
                if (!queued)
                    app->Orders().IssueOrder<ResearchQueueOrder>(context, empire->EmpireID(), std::move(tech), -1);
            } else if (!queued || (queue.find(tech) - queue.begin()) > pos) {
                app->Orders().IssueOrder<ResearchQueueOrder>(context, empire->EmpireID(), std::move(tech), pos);
                ++pos;
            } else if ((queue.find(tech) - queue.begin()) == pos) {
                ++pos;
            }
        }
    } catch (const std::exception& e) {
        ErrorLogger() << "FOResearch::enqueue: " << e.what();
        return false;
    }
    Reproject(*empire, context);
    return true;
}

bool FOResearch::remove(const godot::String& name) {
    auto* app = ClientApp::GetApp();
    auto* empire = PlayerEmpire();
    std::string tech_name = name.utf8().get_data();
    if (!app || !empire || !empire->GetResearchQueue().InQueue(tech_name))
        return false;
    auto& context = app->GetContext();
    app->Orders().IssueOrder<ResearchQueueOrder>(context, empire->EmpireID(), std::move(tech_name));
    Reproject(*empire, context);
    return true;
}

bool FOResearch::move(const godot::String& name, int position) {
    auto* app = ClientApp::GetApp();
    auto* empire = PlayerEmpire();
    std::string tech_name = name.utf8().get_data();
    if (!app || !empire || position < 0 || !empire->GetResearchQueue().InQueue(tech_name))
        return false;
    auto& context = app->GetContext();
    app->Orders().IssueOrder<ResearchQueueOrder>(context, empire->EmpireID(), std::move(tech_name), position);
    Reproject(*empire, context);
    return true;
}
