#include "FODiplomacy.h"

#include <cmath>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

#include "../../ClientApp.h"
#include "../../../universe/Fleet.h"
#include "../../ClientNetworking.h"
#include "../../../Empire/Diplomacy.h"
#include "../../../Empire/Empire.h"
#include "../../../Empire/EmpireManager.h"
#include "../../../network/Message.h"
#include "../../../universe/Planet.h"
#include "../../../universe/Ship.h"
#include "../../../universe/Universe.h"
#include "../../../util/Logger.h"

namespace {
    godot::String ToGodot(std::string_view s)
    { return godot::String::utf8(s.data(), static_cast<int>(s.size())); }

    using Type = DiplomaticMessage::Type;

    std::string_view StatusName(DiplomaticStatus status) {
        switch (status) {
        case DiplomaticStatus::DIPLO_WAR:    return "war";
        case DiplomaticStatus::DIPLO_PEACE:  return "peace";
        case DiplomaticStatus::DIPLO_ALLIED: return "allied";
        default:                             return "";
        }
    }

    std::string_view ProposalName(Type type) {
        switch (type) {
        case Type::PEACE_PROPOSAL:  return "peace";
        case Type::ALLIES_PROPOSAL: return "allies";
        default:                    return "";
        }
    }

    Type PendingType(const EmpireManager& empires, int sender, int recipient) {
        return empires.DiplomaticMessageAvailable(sender, recipient) ?
            empires.GetDiplomaticMessage(sender, recipient).GetType() : Type::INVALID;
    }

    // The actions the GG player list offers towards \a other, given the status
    // and the proposals pending each way.
    godot::PackedStringArray Actions(const EmpireManager& empires, int self, int other) {
        godot::PackedStringArray actions;
        const auto status = empires.GetDiplomaticStatus(self, other);
        const auto incoming = PendingType(empires, other, self);
        const auto outgoing = PendingType(empires, self, other);
        if (incoming == Type::PEACE_PROPOSAL)
            actions.push_back("accept_peace");
        if (incoming == Type::ALLIES_PROPOSAL)
            actions.push_back("accept_alliance");
        if (incoming == Type::PEACE_PROPOSAL || incoming == Type::ALLIES_PROPOSAL)
            actions.push_back("reject");
        if (outgoing == Type::PEACE_PROPOSAL || outgoing == Type::ALLIES_PROPOSAL)
            actions.push_back("cancel");
        if (status == DiplomaticStatus::DIPLO_WAR && incoming != Type::PEACE_PROPOSAL &&
            outgoing != Type::PEACE_PROPOSAL)
        { actions.push_back("propose_peace"); }
        if (status == DiplomaticStatus::DIPLO_PEACE && incoming != Type::ALLIES_PROPOSAL &&
            outgoing != Type::ALLIES_PROPOSAL)
        { actions.push_back("propose_alliance"); }
        if (status == DiplomaticStatus::DIPLO_PEACE)
            actions.push_back("declare_war");
        if (status == DiplomaticStatus::DIPLO_ALLIED)
            actions.push_back("end_alliance");
        return actions;
    }
}

void FODiplomacy::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    const auto cls = get_class_static();
    ClassDB::bind_static_method(cls, D_METHOD("get_empires"), &FODiplomacy::get_empires);
    ClassDB::bind_static_method(cls, D_METHOD("get_incoming_count"), &FODiplomacy::get_incoming_count);
    ClassDB::bind_static_method(cls, D_METHOD("act", "empire_id", "action"), &FODiplomacy::act);
}

namespace {
    // Where empire \a id can be found on the map, as far as \a self knows:
    // its capital, else its known planet nearest our capital, else a fleet
    // of it seen; the system and "capital", "planet" or "fleet" ({-1, ""}
    // when nothing of it is known).
    template <typename IdSet>
    std::pair<int, godot::String> KnownLocation(const ScriptingContext& context, int id, int self,
                                                const IdSet& destroyed, const IdSet& stale)
    {
        const auto& objects = context.ContextObjects();
        const auto known = [&](const UniverseObject* object) {
            return object && object->Owner() == id && object->SystemID() != INVALID_OBJECT_ID &&
                   !destroyed.contains(object->ID()) && !stale.contains(object->ID());
        };
        if (id == self)
            return {INVALID_OBJECT_ID, godot::String()};
        const auto* empire = context.GetEmpire(id).get();
        const auto* capital = empire ? objects.getRaw<Planet>(empire->CapitalID()) : nullptr;
        if (known(capital))
            return {capital->SystemID(), "capital"};
        const auto* own = context.GetEmpire(self).get();
        const auto* home = own ? objects.getRaw<Planet>(own->CapitalID()) : nullptr;
        const Planet* nearest = nullptr;
        double best = 0.0;
        for (const auto* planet : objects.allRaw<Planet>()) {
            if (!known(planet))
                continue;
            const double d = home ? std::hypot(planet->X() - home->X(), planet->Y() - home->Y()) : 0.0;
            if (!nearest || d < best) {
                nearest = planet;
                best = d;
            }
        }
        if (nearest)
            return {nearest->SystemID(), "planet"};
        for (const auto* fleet : objects.allRaw<Fleet>())
            if (known(fleet))
                return {fleet->SystemID(), "fleet"};
        return {INVALID_OBJECT_ID, godot::String()};
    }
}

godot::Array FODiplomacy::get_empires() {
    godot::Array result;
    auto* app = ClientApp::GetApp();
    if (!app)
        return result;
    const auto& empires = app->Empires();
    const int self = app->EmpireID();
    for (const auto& [id, empire] : empires) {
        if (!empire)
            continue;
        godot::Dictionary entry;
        entry["id"] = id;
        entry["name"] = ToGodot(empire->Name());
        entry["player"] = ToGodot(empire->PlayerName());
        const auto c = empire->Color();
        entry["color"] = godot::Color::from_rgba8(c[0], c[1], c[2], c[3]);
        entry["own"] = id == self;
        entry["eliminated"] = empire->Eliminated();
        // Orders sent this turn, and who plays it (multiplayer).
        entry["ready"] = empire->Ready();
        godot::String client_type;
        for (const auto& [player_id, info] : app->Players()) {
            if (info.empire_id != id)
                continue;
            switch (info.client_type) {
            case Networking::ClientType::CLIENT_TYPE_AI_PLAYER:    client_type = "ai"; break;
            case Networking::ClientType::CLIENT_TYPE_HUMAN_PLAYER: client_type = "player"; break;
            default: break;
            }
        }
        entry["client_type"] = client_type;
        const bool other = id != self && self != ALL_EMPIRES;
        entry["status"] = other ? ToGodot(StatusName(empires.GetDiplomaticStatus(self, id))) : godot::String();
        entry["incoming"] = other ? ToGodot(ProposalName(PendingType(empires, id, self))) : godot::String();
        entry["outgoing"] = other ? ToGodot(ProposalName(PendingType(empires, self, id))) : godot::String();
        entry["actions"] = other && !empire->Eliminated() ? Actions(empires, self, id) : godot::PackedStringArray();
        entry["won"] = empire->Won();
        // Its status with every other empire, so the log can tell wars and
        // treaties between others too, as GG's messages window does.
        godot::Dictionary statuses;
        for (const auto& [other_id, other] : empires)
            if (other && other_id != id)
                statuses[other_id] = ToGodot(StatusName(empires.GetDiplomaticStatus(id, other_id)));
        entry["statuses"] = statuses;
        // What this client knows of it, as GG's player list counts it:
        // ships and planets, and the planets' output.
        const auto& context = app->GetContext();
        const auto& universe = context.ContextUniverse();
        const auto& destroyed = universe.EmpireKnownDestroyedObjectIDs(self);
        const auto& stale = universe.EmpireStaleKnowledgeObjectIDs(self);
        int ships = 0, planets = 0;
        double industry = 0.0, research = 0.0, influence = 0.0;
        for (const auto* ship : context.ContextObjects().allRaw<Ship>())
            if (ship->Owner() == id && !destroyed.contains(ship->ID()) && !stale.contains(ship->ID()))
                ++ships;
        for (const auto* planet : context.ContextObjects().allRaw<Planet>()) {
            if (planet->Owner() != id)
                continue;
            ++planets;
            industry += planet->GetMeter(MeterType::METER_INDUSTRY)->Initial();
            research += planet->GetMeter(MeterType::METER_RESEARCH)->Initial();
            influence += planet->GetMeter(MeterType::METER_INFLUENCE)->Initial();
        }
        entry["ships"] = ships;
        entry["planets"] = planets;
        const auto [where, how] = KnownLocation(context, id, self, destroyed, stale);
        entry["known_system_id"] = where;
        entry["known_by"] = how;
        // Its people, as far as known: the species of its capital.
        const auto* capital = context.ContextObjects().getRaw<Planet>(empire->CapitalID());
        entry["species"] = capital ? ToGodot(capital->SpeciesName()) : godot::String();
        entry["industry"] = industry;
        entry["research"] = research;
        entry["influence"] = influence;
        const auto* detection = empire->GetMeter("METER_DETECTION_STRENGTH");
        entry["detection"] = detection ? detection->Initial() : 0.0f;
        if (id == self)
            result.push_front(entry);
        else
            result.push_back(entry);
    }
    return result;
}

int FODiplomacy::get_incoming_count() {
    auto* app = ClientApp::GetApp();
    if (!app || app->EmpireID() == ALL_EMPIRES)
        return 0;
    int count = 0;
    for (const auto& [id, empire] : app->Empires()) {
        const auto type = PendingType(app->Empires(), id, app->EmpireID());
        if (id != app->EmpireID() && (type == Type::PEACE_PROPOSAL || type == Type::ALLIES_PROPOSAL))
            ++count;
    }
    return count;
}

bool FODiplomacy::act(int empire_id, const godot::String& action) {
    auto* app = ClientApp::GetApp();
    if (!app || app->EmpireID() == ALL_EMPIRES || empire_id == app->EmpireID())
        return false;
    const int self = app->EmpireID();
    const auto allowed = Actions(app->Empires(), self, empire_id);
    if (!allowed.has(action))
        return false;
    DiplomaticMessage message;
    if (action == "propose_peace")         message = PeaceProposalDiplomaticMessage(self, empire_id);
    else if (action == "accept_peace")     message = AcceptPeaceDiplomaticMessage(self, empire_id);
    else if (action == "propose_alliance") message = AlliesProposalDiplomaticMessage(self, empire_id);
    else if (action == "accept_alliance")  message = AcceptAlliesDiplomaticMessage(self, empire_id);
    else if (action == "reject")           message = RejectProposalDiplomaticMessage(self, empire_id);
    else if (action == "cancel")           message = CancelDiplomaticMessage(self, empire_id);
    else if (action == "end_alliance")     message = EndAllianceDiplomaticMessage(self, empire_id);
    else if (action == "declare_war")      message = WarDeclarationDiplomaticMessage(self, empire_id);
    else return false;
    if (!message.IsAllowed()) {
        DebugLogger() << "FODiplomacy::act: game rules don't allow " << message.Dump();
        return false;
    }
    app->Networking().SendMessage(DiplomacyMessage(message));
    return true;
}
