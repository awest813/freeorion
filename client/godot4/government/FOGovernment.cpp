#include "FOGovernment.h"

#include <algorithm>

#include <godot_cpp/core/class_db.hpp>

#include "../../ClientApp.h"
#include "../../../Empire/Empire.h"
#include "../../../Empire/Government.h"
#include "../../../universe/Universe.h"
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

    // Re-project influence spending and meters after a policy change, as the
    // GG GovernmentWnd's PostChangeBigUpdate does.
    void Reproject(Empire& empire, ScriptingContext& context) {
        empire.UpdateInfluenceSpending(context, empire.PlanetAnnexationCosts(context),
                                       empire.PolicyAdoptionCosts(context));
        context.ContextUniverse().UpdateMeterEstimates(context);
    }
}

void FOGovernment::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    const auto cls = get_class_static();
    ClassDB::bind_static_method(cls, D_METHOD("get_slots"), &FOGovernment::get_slots);
    ClassDB::bind_static_method(cls, D_METHOD("get_policies"), &FOGovernment::get_policies);
    ClassDB::bind_static_method(cls, D_METHOD("get_influence"), &FOGovernment::get_influence);
    ClassDB::bind_static_method(cls, D_METHOD("adopt", "name", "slot"), &FOGovernment::adopt);
    ClassDB::bind_static_method(cls, D_METHOD("de_adopt", "name"), &FOGovernment::de_adopt);
    ClassDB::bind_static_method(cls, D_METHOD("is_modified"), &FOGovernment::is_modified);
    ClassDB::bind_static_method(cls, D_METHOD("revert"), &FOGovernment::revert);
}

godot::Array FOGovernment::get_slots() {
    godot::Array result;
    const auto* empire = PlayerEmpire();
    if (!empire)
        return result;
    const auto adopted = empire->CategoriesSlotsPoliciesAdopted();
    for (const auto& [category, total] : empire->TotalPolicySlots()) {
        godot::Dictionary slots;
        slots["category"] = ToGodot(category);
        godot::Array policies;
        const auto it = adopted.find(category);
        for (int slot = 0; slot < total; ++slot) {
            std::string_view name;
            if (it != adopted.end()) {
                const auto slot_it = it->second.find(slot);
                if (slot_it != it->second.end())
                    name = slot_it->second;
            }
            policies.push_back(ToGodot(name));
        }
        slots["policies"] = policies;
        result.push_back(slots);
    }
    return result;
}

godot::Array FOGovernment::get_policies() {
    godot::Array result;
    const auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    if (!app || !empire)
        return result;
    const auto& context = app->GetContext();
    try {
        const auto initial = empire->InitialAdoptedPolicies();
        // Every policy, locked ones too, as GG's availability filters show them.
        for (const auto& [name, policy] : GetPolicyManager().Policies()) {
            godot::Dictionary entry;
            entry["name"] = ToGodot(name);
            entry["category"] = ToGodot(policy.Category());
            entry["icon"] = ToGodot(policy.Graphic());
            entry["short_description"] = ToGodot(policy.ShortDescription());
            entry["description"] = ToGodot(policy.Description());
            entry["cost"] = policy.AdoptionCost(empire->EmpireID(), context);
            entry["adopted"] = empire->PolicyAdopted(name);
            entry["available"] = empire->PolicyAvailable(name);
            entry["affordable"] = empire->PolicyAffordable(name, context);
            entry["prerequisites_ok"] = empire->PolicyPrereqsAndExclusionsOK(name, context.current_turn);
            entry["adopted_this_turn"] = empire->PolicyAdopted(name) &&
                std::find(initial.begin(), initial.end(), std::string_view{name}) == initial.end();
            entry["current_turns"] = empire->CurrentTurnsPolicyHasBeenAdopted(name);
            entry["total_turns"] = empire->CumulativeTurnsPolicyHasBeenAdopted(name);
            // Adopted policies that exclude this one; prerequisites and
            // whether they were adopted at the start of the turn.
            godot::PackedStringArray excluded_by;
            for (const auto& ex : policy.Exclusions())
                if (empire->PolicyAdopted(ex))
                    excluded_by.push_back(ToGodot(ex));
            entry["excluded_by"] = excluded_by;
            godot::Array prerequisites;
            for (const auto& prereq : policy.Prerequisites()) {
                godot::Dictionary p;
                p["name"] = ToGodot(prereq);
                p["met"] = std::find(initial.begin(), initial.end(), std::string_view{prereq}) != initial.end();
                prerequisites.push_back(p);
            }
            entry["prerequisites"] = prerequisites;
            result.push_back(entry);
        }
    } catch (const std::exception& e) {
        // An exception must not unwind into Godot, which would abort the process.
        ErrorLogger() << "FOGovernment::get_policies: " << e.what();
    }
    return result;
}

bool FOGovernment::is_modified() {
    const auto* empire = PlayerEmpire();
    return empire && empire->PoliciesModified();
}

bool FOGovernment::revert() {
    auto* app = ClientApp::GetApp();
    auto* empire = PlayerEmpire();
    if (!app || !empire || !empire->PoliciesModified())
        return false;
    auto& context = app->GetContext();
    try {
        app->Orders().IssueOrder<PolicyOrder>(context, empire->EmpireID());
        Reproject(*empire, context);
    } catch (const std::exception& e) {
        ErrorLogger() << "FOGovernment::revert: " << e.what();
        return false;
    }
    return true;
}

godot::Dictionary FOGovernment::get_influence() {
    godot::Dictionary influence;
    const auto* app = ClientApp::GetApp();
    const auto* empire = PlayerEmpire();
    influence["stockpile"] = empire ? empire->GetInfluencePool().Stockpile() : 0.0f;
    double cost = 0.0;
    if (app && empire) {
        try {
            cost = empire->ThisTurnAdoptedPoliciesCost(app->GetContext());
        } catch (const std::exception& e) {
            ErrorLogger() << "FOGovernment::get_influence: " << e.what();
        }
    }
    influence["adoption_cost"] = cost;
    return influence;
}

bool FOGovernment::adopt(const godot::String& name, int slot) {
    auto* app = ClientApp::GetApp();
    auto* empire = PlayerEmpire();
    std::string policy_name = name.utf8().get_data();
    const auto* policy = GetPolicy(policy_name);
    if (!app || !empire || !policy || slot < 0)
        return false;
    auto& context = app->GetContext();
    try {
        app->Orders().IssueOrder<PolicyOrder>(context, empire->EmpireID(), policy_name,
                                              std::string{policy->Category()}, slot);
        Reproject(*empire, context);
    } catch (const std::exception& e) {
        ErrorLogger() << "FOGovernment::adopt: " << e.what();
        return false;
    }
    // Adoption is validated when the order executes; report what happened.
    return empire->PolicyAdopted(policy_name);
}

bool FOGovernment::de_adopt(const godot::String& name) {
    auto* app = ClientApp::GetApp();
    auto* empire = PlayerEmpire();
    std::string policy_name = name.utf8().get_data();
    if (!app || !empire || !empire->PolicyAdopted(policy_name))
        return false;
    auto& context = app->GetContext();
    try {
        app->Orders().IssueOrder<PolicyOrder>(context, empire->EmpireID(), policy_name);
        Reproject(*empire, context);
    } catch (const std::exception& e) {
        ErrorLogger() << "FOGovernment::de_adopt: " << e.what();
        return false;
    }
    return !empire->PolicyAdopted(policy_name);
}
