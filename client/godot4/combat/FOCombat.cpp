#include "FOCombat.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <map>

#include "../../ClientApp.h"
#include "../../../combat/CombatEvents.h"
#include "../../../combat/CombatLogManager.h"
#include "../../../Empire/Empire.h"
#include "../../../universe/Planet.h"
#include "../../../universe/Ship.h"
#include "../../../universe/ShipDesign.h"
#include "../../../universe/ShipHull.h"
#include "../../../universe/System.h"
#include "../../../universe/Universe.h"
#include "../../../util/i18n.h"
#include "../../../util/Logger.h"

namespace {
    godot::String ToGodot(std::string_view s)
    { return godot::String::utf8(s.data(), static_cast<int>(s.size())); }

    // The GG combat log's limit on nesting; real logs are bouts > attacks > details.
    constexpr int MAX_EVENT_DEPTH = 6;

    godot::Array EventNodes(const CombatEvent& event, int viewing_empire_id,
                            const ScriptingContext& context, int depth);

    // What an event is about, for styling: a round heading, an attack, a
    // loss, fighters, or anything else (e.g. stealth changes).
    std::string_view EventKind(const CombatEvent& event) {
        if (dynamic_cast<const BoutEvent*>(&event))
            return "bout";
        if (dynamic_cast<const WeaponsPlatformEvent*>(&event) || dynamic_cast<const WeaponFireEvent*>(&event))
            return "attack";
        if (dynamic_cast<const IncapacitationsEvent*>(&event) ||
            dynamic_cast<const IncapacitationsEvent::IncapacitationDetail*>(&event) ||
            dynamic_cast<const FightersDestroyedEvent*>(&event))
            return "destroyed";
        if (dynamic_cast<const FighterLaunchesEvent*>(&event) || dynamic_cast<const FighterLaunchEvent*>(&event) ||
            dynamic_cast<const FightersAttackFightersEvent*>(&event))
            return "fighters";
        return "other";
    }

    godot::String Trimmed(const std::string& text)
    { return ToGodot(text).strip_edges(); }

    // A log line: \a event's description and details; nothing if both are empty.
    void PushNode(godot::Array& nodes, const CombatEvent& event, const godot::String& text,
                  const godot::String& details, godot::Array children)
    {
        if (text.is_empty() && details.is_empty() && children.is_empty())
            return;
        godot::Dictionary node;
        node["kind"] = ToGodot(EventKind(event));
        node["text"] = text;
        node["details"] = details;
        node["children"] = children;
        nodes.push_back(node);
    }

    void AppendSubEvents(godot::Array& nodes, const CombatEvent& event, int viewing_empire_id,
                         const ScriptingContext& context, int depth)
    {
        if (event.IsEmpty() || depth >= MAX_EVENT_DEPTH)
            return;
        for (const auto* sub_event : event.SubEvents(viewing_empire_id)) {
            if (!sub_event)
                continue;
            const auto sub_nodes = EventNodes(*sub_event, viewing_empire_id, context, depth + 1);
            nodes.append_array(sub_nodes);
        }
    }

    // As CombatLogWnd::MakeCombatLogPanel: an event with sub-events that isn't
    // flattened becomes one node with children; otherwise its title, details
    // and sub-events are listed in place.
    godot::Array EventNodes(const CombatEvent& event, int viewing_empire_id,
                            const ScriptingContext& context, int depth)
    {
        godot::Array nodes;
        if (!event.FlattenSubEvents() && !event.IsEmpty()) {
            godot::Array children;
            AppendSubEvents(children, event, viewing_empire_id, context, depth);
            PushNode(nodes, event, Trimmed(event.CombatLogDescription(viewing_empire_id, context)),
                     Trimmed(event.CombatLogDetails(viewing_empire_id)), children);
            return nodes;
        }
        PushNode(nodes, event, Trimmed(event.CombatLogDescription(viewing_empire_id, context)),
                 Trimmed(event.CombatLogDetails(viewing_empire_id)), godot::Array());
        AppendSubEvents(nodes, event, viewing_empire_id, context, depth);
        return nodes;
    }

    // Damage dealt per attacking empire, from every weapon fired in the log.
    void SumDamage(const CombatEvent& event, int viewing_empire_id, std::map<int, float>& damage, int depth) {
        if (const auto* fire = dynamic_cast<const WeaponFireEvent*>(&event))
            damage[fire->attacker_owner_id] += fire->damage;
        if (event.IsEmpty() || depth >= MAX_EVENT_DEPTH)
            return;
        for (const auto* sub_event : event.SubEvents(viewing_empire_id))
            if (sub_event)
                SumDamage(*sub_event, viewing_empire_id, damage, depth + 1);
    }

    // Damage per bout: taken by each object and dealt by each empire. A shot
    // belongs to the bout of the BoutEvent it is under.
    struct BoutDamage {
        int bouts = 0;
        std::map<int, std::map<int, float>> taken;  // object id -> bout -> damage
        std::map<int, std::map<int, float>> dealt;  // empire id -> bout -> damage
    };

    void TallyBouts(const CombatEvent& event, int viewing_empire_id, int bout, BoutDamage& tally, int depth) {
        if (const auto* bout_event = dynamic_cast<const BoutEvent*>(&event)) {
            bout = bout_event->bout;
            tally.bouts = std::max(tally.bouts, bout);
        }
        if (const auto* fire = dynamic_cast<const WeaponFireEvent*>(&event); fire && bout > 0) {
            tally.taken[fire->target_id][bout] += fire->damage;
            tally.dealt[fire->attacker_owner_id][bout] += fire->damage;
        }
        if (event.IsEmpty() || depth >= MAX_EVENT_DEPTH)
            return;
        for (const auto* sub_event : event.SubEvents(viewing_empire_id))
            if (sub_event)
                TallyBouts(*sub_event, viewing_empire_id, bout, tally, depth + 1);
    }

    // Health of \a object_id before the combat and after each bout: its final
    // health plus the damage it took later, never above its maximum.
    godot::PackedFloat32Array HealthByBout(int object_id, const CombatLog& log, const BoutDamage& tally) {
        godot::PackedFloat32Array result;
        const auto state_it = log.participant_states.find(object_id);
        if (state_it == log.participant_states.end())
            return result;
        const float final_health = std::max(0.0f, state_it->second.current_health);
        const auto taken_it = tally.taken.find(object_id);
        float total = 0.0f;
        if (taken_it != tally.taken.end())
            for (const auto& [bout, damage] : taken_it->second)
                total += damage;
        float health = std::min(state_it->second.max_health, final_health + total);
        result.push_back(health);
        for (int bout = 1; bout <= tally.bouts; ++bout) {
            if (taken_it != tally.taken.end())
                if (const auto it = taken_it->second.find(bout); it != taken_it->second.end())
                    health = std::max(0.0f, health - it->second);
            result.push_back(health);
        }
        return result;
    }

    std::string_view TypeName(UniverseObjectType type) {
        switch (type) {
        case UniverseObjectType::OBJ_SHIP:     return "ship";
        case UniverseObjectType::OBJ_PLANET:   return "planet";
        case UniverseObjectType::OBJ_BUILDING: return "building";
        case UniverseObjectType::OBJ_FIGHTER:  return "fighter";
        default:                               return "other";
        }
    }

    godot::Dictionary Unit(int object_id, const CombatLog& log, int viewing_empire_id,
                           const ScriptingContext& context, const BoutDamage& tally)
    {
        godot::Dictionary unit;
        unit["id"] = object_id;
        const auto& objects = context.ContextObjects();
        const auto* object = objects.getRaw(object_id);
        unit["name"] = object ? ToGodot(object->PublicName(viewing_empire_id, context.ContextUniverse()))
                              : ToGodot(UserString("COMBAT_REPORT_UNKNOWN_OBJECT"));
        unit["type"] = ToGodot(TypeName(object ? object->ObjectType() : UniverseObjectType::INVALID_UNIVERSE_OBJECT_TYPE));
        godot::String icon;
        godot::String planet_type;
        if (const auto* ship = objects.getRaw<Ship>(object_id)) {
            if (const auto* design = context.ContextUniverse().GetShipDesign(ship->DesignID())) {
                if (!design->Icon().empty())
                    icon = ToGodot(design->Icon());
                else if (const auto* hull = GetShipHull(design->Hull()))
                    icon = ToGodot(hull->Icon());
            }
        } else if (const auto* planet = objects.getRaw<Planet>(object_id)) {
            planet_type = ToGodot(::to_string(planet->Type()));
        }
        unit["icon"] = icon;
        unit["planet_type"] = planet_type;
        const auto state_it = log.participant_states.find(object_id);
        unit["health"] = state_it != log.participant_states.end() ? std::max(0.0f, state_it->second.current_health) : 0.0f;
        unit["max_health"] = state_it != log.participant_states.end() ? state_it->second.max_health : 0.0f;
        unit["destroyed"] = log.destroyed_object_ids.contains(object_id);
        unit["health_by_bout"] = HealthByBout(object_id, log, tally);
        return unit;
    }

    godot::Dictionary Describe(int log_id, const CombatLog& log, bool with_details) {
        const auto* app = ClientApp::GetApp();
        const auto& context = app->GetContext();
        const int viewer = app->EmpireID();

        godot::Dictionary result;
        result["id"] = log_id;
        result["turn"] = log.turn;
        result["system_id"] = log.system_id;
        const auto* system = context.ContextObjects().getRaw<System>(log.system_id);
        result["system_name"] = system ? ToGodot(system->PublicName(viewer, context.ContextUniverse()))
                                       : godot::String();

        std::map<int, float> damage;
        for (const auto& event : log.combat_events)
            if (event)
                SumDamage(*event, viewer, damage, 0);
        BoutDamage tally;
        for (const auto& event : log.combat_events)
            if (event)
                TallyBouts(*event, viewer, 0, tally, 0);
        result["bouts"] = tally.bouts;

        // Sides: one per owner of a participant; the player's side first.
        // Ships and planets fight; the log also lists the system and fleets.
        std::map<int, std::vector<int>> units_by_owner;
        for (const int object_id : log.object_ids) {
            const auto* object = context.ContextObjects().getRaw(object_id);
            if (object && (object->ObjectType() == UniverseObjectType::OBJ_SHIP ||
                           object->ObjectType() == UniverseObjectType::OBJ_PLANET))
            {
                units_by_owner[object->Owner()].push_back(object_id);
            }
        }

        godot::Array sides;
        for (const auto& [owner, unit_ids] : units_by_owner) {
            godot::Dictionary side;
            side["empire_id"] = owner;
            side["own"] = owner == viewer && owner != ALL_EMPIRES;
            const auto* empire = context.GetEmpire(owner).get();
            side["name"] = empire ? ToGodot(empire->Name()) : ToGodot(UserString("NEUTRAL"));
            if (empire) {
                const auto c = empire->Color();
                side["color"] = godot::Color::from_rgba8(c[0], c[1], c[2], c[3]);
            } else {
                side["color"] = godot::Color(0.6f, 0.6f, 0.6f, 1.0f);
            }
            float health = 0.0f, max_health = 0.0f;
            int destroyed = 0;
            godot::Array units;
            for (const int id : unit_ids) {
                const auto state_it = log.participant_states.find(id);
                if (state_it != log.participant_states.end()) {
                    health += std::max(0.0f, state_it->second.current_health);
                    max_health += state_it->second.max_health;
                }
                if (log.destroyed_object_ids.contains(id))
                    ++destroyed;
                if (with_details)
                    units.push_back(Unit(id, log, viewer, context, tally));
            }
            side["units"] = static_cast<int>(unit_ids.size());
            side["destroyed"] = destroyed;
            side["health"] = health;
            side["max_health"] = max_health;
            const auto damage_it = damage.find(owner);
            side["damage_dealt"] = damage_it != damage.end() ? damage_it->second : 0.0f;
            // Health before the combat and after each bout, and damage dealt in each.
            godot::PackedFloat32Array side_health;
            side_health.resize(tally.bouts + 1);
            side_health.fill(0.0f);
            for (const int id : unit_ids) {
                const auto unit_health = HealthByBout(id, log, tally);
                for (int64_t i = 0; i < unit_health.size() && i < side_health.size(); ++i)
                    side_health[i] += unit_health[i];
            }
            side["health_by_bout"] = side_health;
            godot::PackedFloat32Array dealt;
            const auto dealt_it = tally.dealt.find(owner);
            for (int bout = 1; bout <= tally.bouts; ++bout) {
                float value = 0.0f;
                if (dealt_it != tally.dealt.end())
                    if (const auto it = dealt_it->second.find(bout); it != dealt_it->second.end())
                        value = it->second;
                dealt.push_back(value);
            }
            side["dealt_by_bout"] = dealt;
            if (with_details)
                side["unit_list"] = units;
            if (owner == viewer)
                sides.push_front(side);
            else
                sides.push_back(side);
        }
        result["sides"] = sides;

        if (with_details) {
            godot::Array events;
            for (const auto& event : log.combat_events)
                if (event)
                    events.append_array(EventNodes(*event, viewer, context, 0));
            result["events"] = events;
        }
        return result;
    }
}

void FOCombat::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    const auto cls = get_class_static();
    ClassDB::bind_static_method(cls, D_METHOD("list_combats"), &FOCombat::list_combats);
    ClassDB::bind_static_method(cls, D_METHOD("get_combat", "log_id"), &FOCombat::get_combat);
    ClassDB::bind_static_method(cls, D_METHOD("get_pending_count"), &FOCombat::get_pending_count);
}

godot::Array FOCombat::list_combats() {
    godot::Array result;
    const auto* app = ClientApp::GetApp();
    if (!app)
        return result;
    try {
        const auto& manager = GetCombatLogManager();
        const int viewer = app->EmpireID();
        // Log IDs run from 0 to the latest; walk them newest first.
        for (int id = manager.LatestLogID(); id >= 0; --id) {
            const auto log = manager.GetLog(id);
            if (!log)
                continue;
            if (viewer != ALL_EMPIRES && !log->empire_ids.contains(viewer))
                continue;
            result.push_back(Describe(id, *log, false));
        }
    } catch (const std::exception& e) {
        ErrorLogger() << "FOCombat::list_combats: " << e.what();
    }
    return result;
}

godot::Dictionary FOCombat::get_combat(int log_id) {
    if (!ClientApp::GetApp())
        return {};
    try {
        if (const auto log = GetCombatLogManager().GetLog(log_id))
            return Describe(log_id, *log, true);
    } catch (const std::exception& e) {
        ErrorLogger() << "FOCombat::get_combat(" << log_id << "): " << e.what();
    }
    return {};
}

int FOCombat::get_pending_count()
{ return static_cast<int>(GetCombatLogManager().IncompleteLogIDs().size()); }
