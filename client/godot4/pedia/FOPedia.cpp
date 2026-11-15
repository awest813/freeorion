#include "FOPedia.h"

#include <godot_cpp/core/class_db.hpp>

#include "../../ClientApp.h"
#include "../../../Empire/Empire.h"
#include "../../../Empire/Government.h"
#include "../../../universe/BuildingType.h"
#include "../../../universe/Encyclopedia.h"
#include "../../../universe/FieldType.h"
#include "../../../universe/ShipHull.h"
#include "../../../universe/ShipPart.h"
#include "../../../universe/Planet.h"
#include "../../../universe/Special.h"
#include "../../../universe/Species.h"
#include "../../../universe/Tech.h"
#include "../../../universe/UnlockableItem.h"
#include "../../../util/Logger.h"
#include "../../../util/i18n.h"

namespace {
    godot::String ToGodot(std::string_view s)
    { return godot::String::utf8(s.data(), static_cast<int>(s.size())); }

    std::string ToStd(const godot::String& s)
    { return s.utf8().get_data(); }

    // Descriptions are stringtable keys; expand them here so GDScript gets
    // the text with its markup (UserString leaves unknown keys flagged).
    godot::String Text(const std::string& key)
    { return key.empty() ? godot::String() : ToGodot(UserString(key)); }

    void Fact(godot::Array& facts, const char* label_key, const godot::String& value) {
        godot::Array fact;
        fact.push_back(label_key);
        fact.push_back(value);
        facts.push_back(fact);
    }

    godot::String Number(double value)
    { return godot::String::num(value, value == static_cast<int>(value) ? 0 : 1); }

    void Link(godot::Array& links, const char* kind, std::string_view name, const char* group) {
        godot::Dictionary link;
        link["kind"] = kind;
        link["name"] = ToGodot(name);
        link["group"] = group;
        links.push_back(link);
    }

    // Link to whatever article \a name has (likes and dislikes name policies,
    // buildings, specials, ...); a plain entry if it has none.
    void LinkAnything(godot::Array& links, std::string_view name_view, const char* group) {
        const std::string name{name_view};
        const char* kind = "";
        if (GetPolicy(name))
            kind = "policy";
        else if (GetBuildingType(name))
            kind = "buildingtype";
        else if (GetSpecial(name))
            kind = "special";
        else if (GetTech(name))
            kind = "tech";
        else if (GetShipPart(name))
            kind = "shippart";
        else if (GetShipHull(name))
            kind = "shiphull";
        else if (const auto* app = ClientApp::GetApp(); app && app->GetSpeciesManager().GetSpecies(name))
            kind = "species";
        Link(links, kind, name, group);
    }

    void Unlocks(godot::Array& links, const std::vector<UnlockableItem>& items) {
        for (const auto& item : items) {
            switch (item.type) {
            case UnlockableItemType::UIT_BUILDING:  Link(links, "buildingtype", item.name, "unlocks"); break;
            case UnlockableItemType::UIT_SHIP_PART: Link(links, "shippart", item.name, "unlocks"); break;
            case UnlockableItemType::UIT_SHIP_HULL: Link(links, "shiphull", item.name, "unlocks"); break;
            case UnlockableItemType::UIT_TECH:      Link(links, "tech", item.name, "unlocks"); break;
            case UnlockableItemType::UIT_POLICY:    Link(links, "policy", item.name, "unlocks"); break;
            default: break;
            }
        }
    }

    godot::Dictionary Article(const std::string& kind, const std::string& name) {
        godot::Dictionary a;
        godot::Array facts, links;
        const auto* app = ClientApp::GetApp();
        const int empire_id = app ? app->EmpireID() : ALL_EMPIRES;

        if (kind == "tech") {
            const auto* tech = GetTech(name);
            if (!tech)
                return {};
            a["title"] = ToGodot(name);
            a["icon"] = ToGodot(tech->Graphic());
            a["text"] = Text(tech->Description());
            Fact(facts, "PEDIA_FACT_CATEGORY", Text(tech->Category()));
            if (app) {
                Fact(facts, "PEDIA_FACT_COST", Number(tech->ResearchCost(empire_id, app->GetContext())) + " RP");
                Fact(facts, "PEDIA_FACT_TIME", godot::String::num_int64(tech->ResearchTime(empire_id, app->GetContext())));
            }
            for (const auto& prereq : tech->Prerequisites())
                Link(links, "tech", prereq, "prerequisites");
            Unlocks(links, tech->UnlockedItems());
        } else if (kind == "buildingtype") {
            const auto* type = GetBuildingType(name);
            if (!type)
                return {};
            a["title"] = ToGodot(name);
            a["icon"] = ToGodot(type->Icon());
            a["text"] = Text(type->Description());
            if (app && type->ProductionCostTimeLocationInvariant()) {
                Fact(facts, "PEDIA_FACT_COST", Number(type->ProductionCost(empire_id, INVALID_OBJECT_ID, app->GetContext())) + " PP");
                Fact(facts, "PEDIA_FACT_TIME", godot::String::num_int64(type->ProductionTime(empire_id, INVALID_OBJECT_ID, app->GetContext())));
            }
        } else if (kind == "species") {
            const auto* species = app ? app->GetSpeciesManager().GetSpecies(name) : nullptr;
            if (!species)
                return {};
            a["title"] = ToGodot(name);
            a["icon"] = ToGodot(species->Graphic());
            a["text"] = Text(species->Description());
            for (const auto& like : species->Likes())
                LinkAnything(links, like, "likes");
            for (const auto& dislike : species->Dislikes())
                LinkAnything(links, dislike, "dislikes");
            // How well it lives on each planet type, as the GG article lists.
            godot::Array environments;
            for (const auto& [planet_type, environment] : species->PlanetEnvironments()) {
                godot::Dictionary entry;
                entry["planet_type"] = ToGodot(::to_string(planet_type));
                entry["environment"] = ToGodot(::to_string(environment));
                environments.push_back(entry);
            }
            a["environments"] = environments;
            // Homeworlds the player knows of, linked to the map.
            if (app) {
                const auto& homeworlds = app->GetSpeciesManager().GetSpeciesHomeworldsMap();
                if (const auto it = homeworlds.find(name); it != homeworlds.end()) {
                    const auto& context = app->GetContext();
                    for (const int planet_id : it->second) {
                        const auto* planet = context.ContextObjects().getRaw<Planet>(planet_id);
                        if (!planet)
                            continue;
                        godot::Dictionary link;
                        link["kind"] = "planet";
                        link["name"] = godot::String::num_int64(planet_id);
                        link["label"] = ToGodot(planet->PublicName(empire_id, context.ContextUniverse()));
                        link["group"] = "homeworlds";
                        links.push_back(link);
                    }
                }
            }
        } else if (kind == "special") {
            const auto* special = GetSpecial(name);
            if (!special)
                return {};
            a["title"] = ToGodot(name);
            a["icon"] = ToGodot(special->Graphic());
            a["text"] = Text(special->Description());
        } else if (kind == "shippart") {
            const auto* part = GetShipPart(name);
            if (!part)
                return {};
            a["title"] = ToGodot(name);
            a["icon"] = ToGodot(part->Icon());
            a["text"] = Text(part->Description());
            Fact(facts, "PEDIA_FACT_CAPACITY", Number(part->Capacity()));
        } else if (kind == "shiphull") {
            const auto* hull = GetShipHull(name);
            if (!hull)
                return {};
            a["title"] = ToGodot(name);
            a["icon"] = ToGodot(hull->Icon());
            a["text"] = Text(hull->Description());
            Fact(facts, "PEDIA_FACT_STRUCTURE", Number(hull->Structure()));
            Fact(facts, "PEDIA_FACT_SPEED", Number(hull->Speed()));
            Fact(facts, "PEDIA_FACT_FUEL", Number(hull->Fuel()));
        } else if (kind == "fieldtype") {
            const auto* field = GetFieldType(name);
            if (!field)
                return {};
            a["title"] = ToGodot(name);
            a["icon"] = ToGodot(field->Graphic());
            a["text"] = Text(field->Description());
        } else if (kind == "policy") {
            const auto* policy = GetPolicy(name);
            if (!policy)
                return {};
            a["title"] = ToGodot(name);
            a["icon"] = ToGodot(policy->Graphic());
            a["text"] = Text(policy->Description());
            Fact(facts, "PEDIA_FACT_CATEGORY", Text(policy->Category()));
            if (app)
                Fact(facts, "PEDIA_FACT_ADOPTION_COST", Number(policy->AdoptionCost(empire_id, app->GetContext())) + " IP");
            for (const auto& prereq : policy->Prerequisites())
                Link(links, "policy", prereq, "prerequisites");
            Unlocks(links, policy->UnlockedItems());
        } else if (kind == "encyclopedia") {
            const auto& article = GetEncyclopedia().GetArticleByKey(name);
            if (article.name.empty())
                return {};
            a["title"] = ToGodot(article.name);
            a["icon"] = ToGodot(article.icon);
            a["text"] = Text(article.description);
            if (!article.category.empty())
                Fact(facts, "PEDIA_FACT_CATEGORY", Text(article.category));
        } else {
            return {};
        }
        a["kind"] = ToGodot(kind);
        a["name"] = ToGodot(name);
        a["facts"] = facts;
        a["links"] = links;
        return a;
    }

    void Index(godot::Array& index, const char* kind, std::string_view name, std::string_view category = {}) {
        godot::Dictionary entry;
        entry["kind"] = kind;
        entry["name"] = ToGodot(name);
        entry["category"] = ToGodot(category);
        index.push_back(entry);
    }
}

void FOPedia::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    const auto cls = get_class_static();
    ClassDB::bind_static_method(cls, D_METHOD("get_article", "kind", "name"), &FOPedia::get_article);
    ClassDB::bind_static_method(cls, D_METHOD("get_index"), &FOPedia::get_index);
    ClassDB::bind_static_method(cls, D_METHOD("has_article", "kind", "name"), &FOPedia::has_article);
}

godot::Dictionary FOPedia::get_article(const godot::String& kind, const godot::String& name) {
    try {
        return Article(ToStd(kind), ToStd(name));
    } catch (const std::exception& e) {
        // An exception must not unwind into Godot, which would abort the process.
        ErrorLogger() << "FOPedia::get_article: " << e.what();
        return {};
    }
}

bool FOPedia::has_article(const godot::String& kind, const godot::String& name)
{ return !get_article(kind, name).is_empty(); }

godot::Array FOPedia::get_index() {
    godot::Array index;
    try {
        for (const auto& [name, tech] : GetTechManager())
            if (tech.Researchable())
                Index(index, "tech", name, tech.Category());
        for (const auto& [name, type] : GetBuildingTypeManager())
            Index(index, "buildingtype", name);
        if (const auto* app = ClientApp::GetApp())
            for (const auto& [name, species] : app->GetSpeciesManager().AllSpecies())
                Index(index, "species", name);
        for (const auto name : SpecialNames())
            Index(index, "special", name);
        for (const auto& [name, part] : GetShipPartManager())
            Index(index, "shippart", name);
        for (const auto& [name, hull] : GetShipHullManager())
            Index(index, "shiphull", name);
        for (const auto& [name, field] : GetFieldTypeManager())
            Index(index, "fieldtype", name);
        for (const auto& [name, policy] : GetPolicyManager().Policies())
            Index(index, "policy", name, policy.Category());
        for (const auto& [category, articles] : GetEncyclopedia().Articles())
            for (const auto& article : articles)
                Index(index, "encyclopedia", article.name, category);
    } catch (const std::exception& e) {
        ErrorLogger() << "FOPedia::get_index: " << e.what();
    }
    return index;
}
