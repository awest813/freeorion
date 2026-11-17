#include "FOPedia.h"

#include <algorithm>
#include <cctype>

#include <godot_cpp/core/class_db.hpp>

#include <regex>

#include "../../ClientApp.h"
#include "../../../Empire/Empire.h"
#include "../../../Empire/Government.h"
#include "../../../universe/BuildingType.h"
#include "../../../universe/Encyclopedia.h"
#include "../../../universe/FieldType.h"
#include "../../../universe/Building.h"
#include "../../../universe/Condition.h"
#include "../../../universe/Fleet.h"
#include "../../../universe/Ship.h"
#include "../../../universe/ShipDesign.h"
#include "../../../universe/System.h"
#include "../../../Empire/EmpireManager.h"
#include "../../../util/GameRules.h"
#include "../../../util/MultiplayerCommon.h"
#include "../../../universe/NamedValueRefManager.h"
#include "../../../universe/ValueRef.h"
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

    // What unlocks \a name of \a type: techs and policies.
    void UnlockedBy(godot::Array& links, UnlockableItemType type, const std::string& name) {
        const auto unlocks = [&](const std::vector<UnlockableItem>& items) {
            return std::any_of(items.begin(), items.end(),
                               [&](const auto& item) { return item.type == type && item.name == name; });
        };
        for (const auto& [tech_name, tech] : GetTechManager())
            if (unlocks(tech.UnlockedItems()))
                Link(links, "tech", tech_name, "unlocked_by");
        for (const auto& [policy_name, policy] : GetPolicyManager().Policies())
            if (unlocks(policy.UnlockedItems()))
                Link(links, "policy", policy_name, "unlocked_by");
    }

    // The condition an item needs where it is built, in words.
    godot::String Requirements(const Condition::Condition* condition) {
        if (!condition)
            return {};
        try {
            return ToGodot(condition->Description());
        } catch (const std::exception&) {
            return {};
        }
    }

    // Who unlocks it, what it leads to and excludes, which species like or
    // dislike it, where it can be built (GG's article sections).
    void AddRelations(godot::Dictionary& a, godot::Array& links, const std::string& kind, const std::string& name) {
        if (kind == "tech") {
            if (const auto* tech = GetTech(name))
                for (const auto& next : tech->UnlockedTechs())
                    Link(links, "tech", next, "leads_to");
            UnlockedBy(links, UnlockableItemType::UIT_TECH, name);
        } else if (kind == "buildingtype") {
            UnlockedBy(links, UnlockableItemType::UIT_BUILDING, name);
            if (const auto* type = GetBuildingType(name))
                a["requirements"] = Requirements(type->Location());
        } else if (kind == "shippart") {
            UnlockedBy(links, UnlockableItemType::UIT_SHIP_PART, name);
            if (const auto* part = GetShipPart(name)) {
                a["requirements"] = Requirements(part->Location());
                for (const auto& ex : part->Exclusions())
                    LinkAnything(links, ex, "exclusions");
            }
        } else if (kind == "shiphull") {
            UnlockedBy(links, UnlockableItemType::UIT_SHIP_HULL, name);
            if (const auto* hull = GetShipHull(name)) {
                a["requirements"] = Requirements(hull->Location());
                for (const auto& ex : hull->Exclusions())
                    LinkAnything(links, ex, "exclusions");
            }
        } else if (kind == "policy") {
            UnlockedBy(links, UnlockableItemType::UIT_POLICY, name);
            if (const auto* policy = GetPolicy(name))
                for (const auto& ex : policy->Exclusions())
                    Link(links, "policy", ex, "exclusions");
        }
        if (kind == "policy" || kind == "buildingtype" || kind == "special" || kind == "tech" || kind == "shippart") {
            if (const auto* app = ClientApp::GetApp()) {
                for (const auto& [species_name, species] : app->GetSpeciesManager().AllSpecies()) {
                    const auto& likes = species.Likes();
                    const auto& dislikes = species.Dislikes();
                    if (std::find(likes.begin(), likes.end(), name) != likes.end())
                        Link(links, "species", species_name, "liked_by");
                    if (std::find(dislikes.begin(), dislikes.end(), name) != dislikes.end())
                        Link(links, "species", species_name, "disliked_by");
                }
            }
        }
    }

    bool ExtraArticle(godot::Dictionary& a, godot::Array& facts, godot::Array& links,
                      const std::string& kind, const std::string& name);

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
            // What it thinks of each empire (GG's species opinions).
            if (app) {
                const auto& opinions = app->GetSpeciesManager().GetSpeciesEmpireOpinionsMap();
                if (const auto it = opinions.find(name); it != opinions.end()) {
                    std::string text;
                    for (const auto& [opinion_empire_id, opinion] : it->second) {
                        const auto empire = app->GetContext().GetEmpire(opinion_empire_id);
                        if (!empire)
                            continue;
                        text.append("\n<empire ").append(std::to_string(opinion_empire_id)).append(">")
                            .append(empire->Name()).append("</empire>: ")
                            .append(DoubleToString(opinion.first.Initial(), 3, false));
                    }
                    if (!text.empty())
                        a["text"] = godot::String(a["text"]) + ToGodot("\n\n<b>" + UserString("SPECIES_OPINIONS") + "</b>" + text);
                }
            }
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
        } else if (kind == "encyclopedia" && (name == "ENC_GALAXY_SETUP" || name == "ENC_GAME_RULES")) {
            if (!ExtraArticle(a, facts, links, kind, name))
                return {};
        } else if (kind == "encyclopedia") {
            const auto& article = GetEncyclopedia().GetArticleByKey(name);
            if (article.name.empty())
                return {};
            a["title"] = ToGodot(article.name);
            a["icon"] = ToGodot(article.icon);
            a["text"] = Text(article.description);
            if (!article.category.empty())
                Fact(facts, "PEDIA_FACT_CATEGORY", Text(article.category));
        } else if (!ExtraArticle(a, facts, links, kind, name)) {
            return {};
        }
        AddRelations(a, links, kind, name);
        a["kind"] = ToGodot(kind);
        a["name"] = ToGodot(name);
        a["facts"] = facts;
        a["links"] = links;
        return a;
    }

    void Index(godot::Array& index, const char* kind, std::string_view name, std::string_view category = {},
               std::string_view label = {})
    {
        godot::Dictionary entry;
        entry["kind"] = kind;
        entry["name"] = ToGodot(name);
        entry["category"] = ToGodot(category);
        // Entries named by ID (empires, designs) or by a meter type carry
        // the title to list them by.
        if (!label.empty())
            entry["label"] = ToGodot(label);
        index.push_back(entry);
    }
}

void FOPedia::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    const auto cls = get_class_static();
    ClassDB::bind_static_method(cls, D_METHOD("get_article", "kind", "name"), &FOPedia::get_article);
    ClassDB::bind_static_method(cls, D_METHOD("get_index"), &FOPedia::get_index);
    ClassDB::bind_static_method(cls, D_METHOD("has_article", "kind", "name"), &FOPedia::has_article);
    ClassDB::bind_static_method(cls, D_METHOD("resolve_values", "text"), &FOPedia::resolve_values);
    ClassDB::bind_static_method(cls, D_METHOD("search", "text"), &FOPedia::search);
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
        Index(index, "encyclopedia", "ENC_GALAXY_SETUP", "ENC_INDEX");
        Index(index, "encyclopedia", "ENC_GAME_RULES", "ENC_INDEX");
        for (const auto& [type, type_name] : MeterTypeValues()) {
            if (type <= MeterType::INVALID_METER_TYPE || type >= MeterType::NUM_METER_TYPES)
                continue;
            const std::string label_key = std::string{type_name} + "_VALUE_LABEL";
            Index(index, "metertype", type_name, {},
                  UserStringExists(label_key) ? UserString(label_key) : UserString(type_name));
        }
        if (const auto* app = ClientApp::GetApp()) {
            for (const auto& [id, empire] : app->Empires())
                Index(index, "empire", std::to_string(id), {}, empire->Name());
            if (const auto* empire = app->GetEmpire(app->EmpireID()))
                for (const int id : empire->ShipDesigns())
                    if (const auto* design = app->GetUniverse().GetShipDesign(id))
                        Index(index, "shipdesign", std::to_string(id), {}, design->Name(true));
        }
        // Premade designs by name too (they have no id on the client).
        for (const auto* premade : GetPredefinedShipDesignManager().GetOrderedShipDesigns())
            if (premade)
                Index(index, "shipdesign", premade->Name(false), "premade", premade->Name(true));
        // Monsters, a section of their own as GG's ENC_MONSTER, by name (the
        // client knows no ids for them).
        for (const auto* monster : GetPredefinedShipDesignManager().GetOrderedMonsterDesigns())
            if (monster)
                Index(index, "monsterdesign", monster->Name(false), "monster", monster->Name(true));
    } catch (const std::exception& e) {
        ErrorLogger() << "FOPedia::get_index: " << e.what();
    }
    return index;
}

namespace {
    // A named value evaluated in the client's context (EvalAsString's empty
    // default context can't evaluate everything).
    std::string EvalInGame(const ValueRef::ValueRefBase& value_ref) {
        const auto& context = ClientApp::GetApp()->GetContext();
        if (const auto* d = dynamic_cast<const ValueRef::ValueRef<double>*>(&value_ref))
            return ValueRef::FlexibleToString(d->Eval(context));
        if (const auto* i = dynamic_cast<const ValueRef::ValueRef<int>*>(&value_ref))
            return ValueRef::FlexibleToString(i->Eval(context));
        if (const auto* t = dynamic_cast<const ValueRef::ValueRef<std::string>*>(&value_ref))
            return t->Eval(context);
        return value_ref.EvalAsString();
    }
}

godot::String FOPedia::resolve_values(const godot::String& text) {
    std::string in = text.utf8().get_data();
    if (!ContentReady() || !ClientApp::GetApp() || in.find("</value>") == std::string::npos)
        return text;
    static const std::regex value_tag{R"(<value\s+([^<>]+)>([^<>]*)</value>)"};
    std::string out;
    out.reserve(in.size());
    auto it = in.cbegin();
    try {
        for (std::sregex_iterator m{in.cbegin(), in.cend(), value_tag}, end; m != end; ++m) {
            out.append(it, (*m)[0].first);
            const std::string name = (*m)[1].str();
            const auto* value_ref = GetValueRefBase(name);
            const std::string value = value_ref ? EvalInGame(*value_ref) : (*m)[2].str();
            out.append("<value ").append(name).append(">").append(value).append("</value>");
            it = (*m)[0].second;
        }
    } catch (const std::exception& e) {
        // An exception must not unwind into Godot, which would abort the process.
        ErrorLogger() << "FOPedia::resolve_values: " << e.what();
        return text;
    }
    out.append(it, in.cend());
    return godot::String::utf8(out.data(), static_cast<int>(out.size()));
}

std::atomic<bool>& FOPedia::ContentReady() {
    static std::atomic<bool> ready = false;
    return ready;
}

namespace {
    std::string EmpireLink(int empire_id, const ScriptingContext& context) {
        const auto empire = context.GetEmpire(empire_id);
        if (!empire)
            return UserString("UNOWNED");
        return "<empire " + std::to_string(empire_id) + ">" + empire->Name() + "</empire>";
    }

    template <typename T>
    std::string ObjectLink(const char* tag, const T* obj, int empire_id, const Universe& universe) {
        if (!obj)
            return {};
        return std::string{"<"} + tag + " " + std::to_string(obj->ID()) + ">" +
            obj->PublicName(empire_id, universe) + "</" + tag + ">";
    }

    // Whole numbers (slot counts, troops) without decimals.
    std::string PlainNumber(double value) {
        return value == static_cast<int>(value) ? std::to_string(static_cast<int>(value))
                                                : DoubleToString(value, 3, false);
    }

    // "Industry: 12.5", linked to the meter's article; nothing for a meter
    // the object hasn't, or (with skip_zero) one at 0, which an unowned or
    // unexplored planet has for all of them.
    std::string MeterLine(const UniverseObject& obj, MeterType type, bool skip_zero = false) {
        const auto* meter = obj.GetMeter(type);
        if (!meter || (skip_zero && meter->Initial() == 0.0f))
            return {};
        return "<metertype " + std::string{to_string(type)} + ">" + UserString(std::string{to_string(type)}) +
            "</metertype>: " + PlainNumber(meter->Initial()) + "\n";
    }

    // Planets, systems, fleets, ships and buildings, as GG's object pages:
    // what it is, whose, where, and what it holds.
    bool ObjectArticle(godot::Dictionary& a, godot::Array& facts, const std::string& kind, int id) {
        const auto* app = ClientApp::GetApp();
        if (!app)
            return false;
        const auto& context = app->GetContext();
        const auto& objects = context.ContextObjects();
        const auto& universe = context.ContextUniverse();
        const int viewer = app->EmpireID();
        const UniverseObject* obj = objects.getRaw(id);
        if (!obj)
            return false;
        std::string text;
        const auto* system = objects.getRaw<System>(obj->SystemID());
        if (kind == "planet") {
            const auto* planet = objects.getRaw<Planet>(id);
            if (!planet)
                return false;
            Fact(facts, "PEDIA_FACT_PLANET_TYPE", Text(std::string{to_string(planet->Type())}));
            Fact(facts, "PEDIA_FACT_PLANET_SIZE", Text(std::string{to_string(planet->Size())}));
            if (!planet->SpeciesName().empty())
                text += UserString("PEDIA_SPECIES") + ": <species " + planet->SpeciesName() + ">" +
                    UserString(planet->SpeciesName()) + "</species>\n";
            for (const auto type : {MeterType::METER_POPULATION, MeterType::METER_INDUSTRY, MeterType::METER_RESEARCH,
                                    MeterType::METER_INFLUENCE, MeterType::METER_HAPPINESS, MeterType::METER_SUPPLY,
                                    MeterType::METER_DEFENSE, MeterType::METER_SHIELD, MeterType::METER_TROOPS})
                text += MeterLine(*planet, type, true);
            // For the article's picture: the planet as the map's panels draw it.
            a["planet_type"] = ToGodot(std::string{to_string(planet->Type())});
            a["planet_size"] = ToGodot(std::string{to_string(planet->Size())});
            if (system)
                a["star_type"] = ToGodot(std::string{to_string(system->GetStarType())});
            for (const auto* building : objects.findRaw<const Building>(planet->BuildingIDs()))
                text += "\n" + ObjectLink("building", building, viewer, universe);
        } else if (kind == "system") {
            const auto* sys = objects.getRaw<System>(id);
            if (!sys)
                return false;
            Fact(facts, "PEDIA_FACT_STAR", Text(std::string{to_string(sys->GetStarType())}));
            for (const auto* planet : objects.findRaw<const Planet>(sys->PlanetIDs()))
                text += ObjectLink("planet", planet, viewer, universe) + "\n";
        } else if (kind == "fleet") {
            const auto* fleet = objects.getRaw<Fleet>(id);
            if (!fleet)
                return false;
            for (const auto* ship : objects.findRaw<const Ship>(fleet->ShipIDs()))
                text += ObjectLink("ship", ship, viewer, universe) + "\n";
        } else if (kind == "ship") {
            const auto* ship = objects.getRaw<Ship>(id);
            if (!ship)
                return false;
            if (const auto* design = universe.GetShipDesign(ship->DesignID()))
                text += UserString("PEDIA_DESIGN") + ": <shipdesign " + std::to_string(design->ID()) + ">" +
                    design->Name(true) + "</shipdesign>\n";
            text += UserString("PEDIA_FLEET") + ": " + ObjectLink("fleet", objects.getRaw<Fleet>(ship->FleetID()), viewer, universe) + "\n";
            if (!ship->SpeciesName().empty())
                text += UserString("PEDIA_SPECIES") + ": <species " + ship->SpeciesName() + ">" +
                    UserString(ship->SpeciesName()) + "</species>\n";
            for (const auto type : {MeterType::METER_STRUCTURE, MeterType::METER_SHIELD, MeterType::METER_FUEL,
                                    MeterType::METER_SPEED, MeterType::METER_DETECTION, MeterType::METER_STEALTH})
                text += MeterLine(*ship, type);
        } else if (kind == "building") {
            const auto* building = objects.getRaw<Building>(id);
            if (!building)
                return false;
            text += "<buildingtype " + building->BuildingTypeName() + ">" + UserString(building->BuildingTypeName()) +
                "</buildingtype>\n";
            text += UserString("PEDIA_PLANET") + ": " + ObjectLink("planet", objects.getRaw<Planet>(building->PlanetID()), viewer, universe) + "\n";
        } else {
            return false;
        }
        a["title"] = ToGodot(obj->PublicName(viewer, universe));
        a["icon"] = godot::String();
        std::string where = system ? UserString("PEDIA_SYSTEM") + ": " + ObjectLink("system", system, viewer, universe) + "\n" : "";
        a["text"] = ToGodot(UserString("PEDIA_OWNER") + ": " + EmpireLink(obj->Owner(), context) + "\n" +
                            where + "\n" + text);
        a["object_id"] = id;
        return true;
    }

    bool ExtraArticle(godot::Dictionary& a, godot::Array& facts, godot::Array& links,
                      const std::string& kind, const std::string& name)
    {
        const auto* app = ClientApp::GetApp();
        if (kind == "metertype") {
            const auto type = MeterTypeFromString(name, MeterType::INVALID_METER_TYPE);
            if (type == MeterType::INVALID_METER_TYPE)
                return false;
            const std::string label_key = name + "_VALUE_LABEL";
            a["title"] = ToGodot(UserStringExists(label_key) ? UserString(label_key) : UserString(name));
            a["icon"] = godot::String();
            const std::string desc_key = name + "_VALUE_DESC";
            a["text"] = ToGodot(UserStringExists(desc_key) ? UserString(desc_key) : UserString(name));
            return true;
        }
        if (kind == "shipdesign" || kind == "monsterdesign") {
            // The universe's designs by id; premade and monster designs by
            // name (the client knows no ids for them).
            const bool by_id = !name.empty() && std::all_of(name.begin() + (name[0] == '-' ? 1 : 0), name.end(),
                                                            [](unsigned char c) { return std::isdigit(c); });
            const ShipDesign* design = by_id && app ? app->GetUniverse().GetShipDesign(std::atoi(name.c_str()))
                                                    : nullptr;
            const auto& predefined = GetPredefinedShipDesignManager();
            if (!design && !by_id)
                for (const auto* candidate : kind == "monsterdesign" ? predefined.GetOrderedMonsterDesigns()
                                                                     : predefined.GetOrderedShipDesigns())
                    if (candidate && candidate->Name(false) == name)
                        design = candidate;
            if (!design)
                return false;
            a["title"] = ToGodot(design->Name(true));
            const auto* hull = GetShipHull(design->Hull());
            a["icon"] = hull ? ToGodot(hull->Icon()) : godot::String();
            a["text"] = ToGodot(design->Description(true));
            Fact(facts, "PEDIA_FACT_ATTACK", Number(design->Attack()));
            Fact(facts, "PEDIA_FACT_STRUCTURE", Number(design->Structure()));
            Fact(facts, "PEDIA_FACT_SHIELDS", Number(design->Shields()));
            Fact(facts, "PEDIA_FACT_SPEED", Number(design->Speed()));
            Fact(facts, "PEDIA_FACT_FUEL", Number(design->Fuel()));
            Fact(facts, "PEDIA_FACT_DETECTION", Number(design->Detection()));
            Fact(facts, "PEDIA_FACT_STEALTH", Number(design->Stealth()));
            if (app) {
                const auto* empire = app->GetEmpire(app->EmpireID());
                const int location = empire ? empire->CapitalID() : INVALID_OBJECT_ID;
                Fact(facts, "PEDIA_FACT_COST", Number(design->ProductionCost(app->EmpireID(), location, app->GetContext())) + " PP");
                Fact(facts, "PEDIA_FACT_TIME", godot::String::num_int64(design->ProductionTime(app->EmpireID(), location, app->GetContext())));
                if (empire && !empire->ShipDesignAvailable(*design))
                    Fact(facts, "PEDIA_FACT_AVAILABLE", ToGodot(UserString("NO")));
            }
            Link(links, "shiphull", design->Hull(), "hull");
            std::set<std::string_view> seen;
            for (const auto& part : design->Parts())
                if (!part.empty() && seen.insert(part).second)
                    Link(links, "shippart", part, "parts");
            return true;
        }
        if (kind == "empire") {
            if (!app)
                return false;
            const int id = std::atoi(name.c_str());
            const auto& context = app->GetContext();
            const auto empire = context.GetEmpire(id);
            if (!empire)
                return false;
            a["title"] = ToGodot(empire->Name());
            a["icon"] = godot::String();
            a["color"] = godot::Color(empire->Color()[0] / 255.0, empire->Color()[1] / 255.0, empire->Color()[2] / 255.0);
            std::string text;
            if (const auto* capital = context.ContextObjects().getRaw<Planet>(empire->CapitalID()))
                text += UserString("EMPIRE_CAPITAL") + ObjectLink("planet", capital, app->EmpireID(), context.ContextUniverse());
            else
                text += UserString("NO_CAPITAL");
            text += "\n" + UserString("EMPIRE_ID") + ": " + name + "\n" + UserString("PEDIA_PLAYER") + ": " + empire->PlayerName();
            const auto plain = PlainNumber;
            const auto& meters = empire->GetMeters();
            if (!meters.empty()) {
                text += "\n";
                for (const auto& [meter_name, meter] : meters)
                    text += "\n" + UserString(meter_name) + ": " + plain(meter.Initial());
            }
            // Species' opinions of this empire: those that have one, the
            // fondest first (a list of every species at 0 says nothing).
            std::vector<std::pair<double, std::string>> opinions;
            for (const auto& [species_name, empire_opinions] : context.species.GetSpeciesEmpireOpinionsMap()) {
                const auto it = empire_opinions.find(id);
                if (it != empire_opinions.end() && it->second.first.Initial() != 0.0)
                    opinions.emplace_back(it->second.first.Initial(), species_name);
            }
            std::stable_sort(opinions.begin(), opinions.end(),
                             [](const auto& a, const auto& b) { return a.first > b.first; });
            if (!opinions.empty()) {
                text += "\n\n<b>" + UserString("SPECIES_OPINIONS") + "</b>";
                for (const auto& [opinion, species_name] : opinions)
                    text += "\n<species " + species_name + ">" + UserString(species_name) + "</species>: " +
                        plain(opinion);
            }
            a["text"] = ToGodot(text);
            for (const auto& policy : empire->AdoptedPolicies())
                Link(links, "policy", policy, "policies");
            const auto owned = context.ContextObjects().findRaw<const Planet>(
                [id](const Planet* p) { return p->OwnedBy(id); });
            for (const auto* planet : owned) {
                godot::Dictionary link;
                link["kind"] = "planet";
                link["name"] = godot::String::num_int64(planet->ID());
                link["label"] = ToGodot(planet->PublicName(app->EmpireID(), context.ContextUniverse()));
                link["group"] = "planets";
                links.push_back(link);
            }
            // The planets' links say how many (their caption counts them).
            if (owned.empty())
                Fact(facts, "PEDIA_FACT_PLANETS", "0");
            Fact(facts, "PEDIA_FACT_TECHS", godot::String::num_int64(static_cast<int64_t>(empire->ResearchedTechs().size())));
            return true;
        }
        if (kind == "planet" || kind == "system" || kind == "fleet" || kind == "ship" || kind == "building")
            return ObjectArticle(a, facts, kind, std::atoi(name.c_str()));
        if (kind == "encyclopedia" && name == "ENC_GALAXY_SETUP") {
            if (!app)
                return false;
            const auto& gsd = app->GetGalaxySetupData();
            a["title"] = ToGodot(name);
            a["icon"] = godot::String();
            a["text"] = ToGodot(boost::io::str(FlexibleFormat(UserString("ENC_GALAXY_SETUP_SETTINGS"))
                % gsd.seed % std::to_string(gsd.size) % TextForGalaxyShape(gsd.shape)
                % TextForGalaxySetupSetting(gsd.age) % TextForGalaxySetupSetting(gsd.starlane_freq)
                % TextForGalaxySetupSetting(gsd.planet_density) % TextForGalaxySetupSetting(gsd.specials_freq)
                % TextForGalaxySetupSetting(gsd.monster_freq) % TextForGalaxySetupSetting(gsd.native_freq)
                % TextForAIAggression(gsd.ai_aggr) % gsd.game_uid));
            return true;
        }
        if (kind == "encyclopedia" && name == "ENC_GAME_RULES") {
            std::string text;
            std::string_view last_category = "\x01";
            for (const auto* rule : GetGameRules().GetSortedByCategoryAndRank()) {
                if (last_category != rule->category) {
                    last_category = rule->category;
                    text += "\n<b>" + UserString(last_category.empty() ? "GENERAL" : last_category) + "</b>\n";
                }
                const std::string line = UserString(rule->name) + ": " + rule->ValueToString();
                text += rule->ValueIsDefault() ? line + "\n" : "<u>" + line + "</u>\n";
            }
            a["title"] = ToGodot(name);
            a["icon"] = godot::String();
            a["text"] = ToGodot(text);
            return true;
        }
        return false;
    }
}

godot::Array FOPedia::search(const godot::String& needle_text) {
    godot::Array result;
    const std::string needle = ToStd(needle_text.to_lower());
    if (needle.size() < 3)
        return result;
    const auto matches = [&](const std::string& key) {
        if (key.empty())
            return false;
        auto text = UserString(key);
        std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c) { return std::tolower(c); });
        return text.find(needle) != std::string::npos;
    };
    try {
        for (const auto& [name, tech] : GetTechManager())
            if (tech.Researchable() && matches(tech.Description()))
                Index(result, "tech", name, tech.Category());
        for (const auto& [name, type] : GetBuildingTypeManager())
            if (matches(type->Description()))
                Index(result, "buildingtype", name);
        if (const auto* app = ClientApp::GetApp())
            for (const auto& [name, species] : app->GetSpeciesManager().AllSpecies())
                if (matches(species.Description()))
                    Index(result, "species", name);
        for (const auto name : SpecialNames())
            if (const auto* special = GetSpecial(name); special && matches(special->Description()))
                Index(result, "special", name);
        for (const auto& [name, part] : GetShipPartManager())
            if (matches(part->Description()))
                Index(result, "shippart", name);
        for (const auto& [name, hull] : GetShipHullManager())
            if (matches(hull->Description()))
                Index(result, "shiphull", name);
        for (const auto& [name, policy] : GetPolicyManager().Policies())
            if (matches(policy.Description()))
                Index(result, "policy", name, policy.Category());
        for (const auto& [category, articles] : GetEncyclopedia().Articles())
            for (const auto& article : articles)
                if (matches(article.description))
                    Index(result, "encyclopedia", article.name, category);
    } catch (const std::exception& e) {
        ErrorLogger() << "FOPedia::search: " << e.what();
    }
    return result;
}
