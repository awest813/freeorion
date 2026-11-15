#include "FOMultiplayer.h"

#include <boost/algorithm/string/replace.hpp>
#include <boost/date_time/posix_time/posix_time.hpp>
#include <boost/uuid/string_generator.hpp>
#include <boost/uuid/uuid_io.hpp>
#include <godot_cpp/core/class_db.hpp>

#include "../GodotClientApp.h"
#include "../../ClientNetworking.h"
#include "../../../Empire/Empire.h"
#include "../../../util/GameRules.h"
#include "../../../util/Logger.h"
#include "../../../util/OptionsDB.h"
#include "../../../util/Version.h"

namespace {
    godot::String ToGodot(std::string_view s)
    { return godot::String::utf8(s.data(), static_cast<int>(s.size())); }

    std::string ToStd(const godot::String& s)
    { return s.utf8().get_data(); }

    godot::Color ToColor(const std::array<uint8_t, 4>& c)
    { return godot::Color::from_rgba8(c[0], c[1], c[2], c[3]); }

    std::array<uint8_t, 4> FromColor(const godot::Color& c) {
        return {static_cast<uint8_t>(c.get_r8()), static_cast<uint8_t>(c.get_g8()),
                static_cast<uint8_t>(c.get_b8()), static_cast<uint8_t>(c.get_a8())};
    }

    // "player", "observer", "moderator", "ai" <-> Networking::ClientType.
    const char* ClientTypeName(Networking::ClientType type) {
        switch (type) {
        case Networking::ClientType::CLIENT_TYPE_AI_PLAYER:       return "ai";
        case Networking::ClientType::CLIENT_TYPE_HUMAN_PLAYER:    return "player";
        case Networking::ClientType::CLIENT_TYPE_HUMAN_OBSERVER:  return "observer";
        case Networking::ClientType::CLIENT_TYPE_HUMAN_MODERATOR: return "moderator";
        default:                                                  return "";
        }
    }

    Networking::ClientType ClientTypeFromName(const godot::String& name) {
        if (name == "ai")        return Networking::ClientType::CLIENT_TYPE_AI_PLAYER;
        if (name == "player")    return Networking::ClientType::CLIENT_TYPE_HUMAN_PLAYER;
        if (name == "observer")  return Networking::ClientType::CLIENT_TYPE_HUMAN_OBSERVER;
        if (name == "moderator") return Networking::ClientType::CLIENT_TYPE_HUMAN_MODERATOR;
        return Networking::ClientType::INVALID_CLIENT_TYPE;
    }

    // Session state the server sent.
    struct Session {
        MultiplayerLobbyData lobby;
        std::vector<ChatHistoryEntity> chat;
        std::string auth_player_name;
        bool hosting = false;
        bool active = false;  // between host/join and leave
    };

    Session& TheSession() {
        static Session session;
        return session;
    }

    GodotClientApp* App() { return GodotClientApp::GetApp(); }

    // The option GG uses to remember a server's cookie, so a rejoining
    // player gets their seat back.
    std::string ServerOption(const std::string& server) {
        std::string encoded = boost::replace_all_copy(server, ".", "_");
        boost::replace_all(encoded, ":", "_");
        return "network.known-servers._" + encoded;
    }

    godot::Dictionary PlayerDict(int player_id, const PlayerSetupData& psd) {
        godot::Dictionary player;
        player["player_id"] = player_id;
        player["player_name"] = ToGodot(psd.player_name);
        player["empire_name"] = ToGodot(psd.empire_name);
        player["species"] = ToGodot(psd.starting_species_name);
        player["color"] = ToColor(psd.empire_color);
        player["client_type"] = ClientTypeName(psd.client_type);
        player["ready"] = psd.player_ready;
        player["team"] = psd.starting_team;
        player["save_empire_id"] = psd.save_game_empire_id;
        player["authenticated"] = psd.authenticated;
        return player;
    }

    PlayerSetupData PlayerFromDict(const godot::Dictionary& player, PlayerSetupData psd) {
        if (player.has("player_name"))  psd.player_name = ToStd(player["player_name"]);
        if (player.has("empire_name"))  psd.empire_name = ToStd(player["empire_name"]);
        if (player.has("species"))      psd.starting_species_name = ToStd(player["species"]);
        if (player.has("color"))        psd.empire_color = FromColor(player["color"]);
        if (player.has("client_type"))  psd.client_type = ClientTypeFromName(player["client_type"]);
        if (player.has("ready"))        psd.player_ready = player["ready"];
        if (player.has("team"))         psd.starting_team = player["team"];
        if (player.has("save_empire_id")) psd.save_game_empire_id = player["save_empire_id"];
        return psd;
    }

    bool Send(Message&& message) {
        auto* app = App();
        if (!app || !app->Networking().IsConnected())
            return false;
        app->Networking().SendMessage(std::move(message));
        return true;
    }
}

void FOMultiplayer::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    const auto cls = get_class_static();
    ClassDB::bind_static_method(cls, D_METHOD("host_game", "player_name"), &FOMultiplayer::host_game);
    ClassDB::bind_static_method(cls, D_METHOD("join_game", "address", "player_name", "client_type"),
                                &FOMultiplayer::join_game);
    ClassDB::bind_static_method(cls, D_METHOD("leave"), &FOMultiplayer::leave);
    ClassDB::bind_static_method(cls, D_METHOD("is_connected_to_server"), &FOMultiplayer::is_connected_to_server);
    ClassDB::bind_static_method(cls, D_METHOD("get_player_id"), &FOMultiplayer::get_player_id);
    ClassDB::bind_static_method(cls, D_METHOD("is_host"), &FOMultiplayer::is_host);
    ClassDB::bind_static_method(cls, D_METHOD("has_role", "role"), &FOMultiplayer::has_role);
    ClassDB::bind_static_method(cls, D_METHOD("get_lobby"), &FOMultiplayer::get_lobby);
    ClassDB::bind_static_method(cls, D_METHOD("send_lobby", "changes"), &FOMultiplayer::send_lobby);
    ClassDB::bind_static_method(cls, D_METHOD("set_ready", "ready"), &FOMultiplayer::set_ready);
    ClassDB::bind_static_method(cls, D_METHOD("send_chat", "text", "recipients"), &FOMultiplayer::send_chat,
                                DEFVAL(godot::PackedInt32Array()));
    ClassDB::bind_static_method(cls, D_METHOD("get_chat"), &FOMultiplayer::get_chat);
    ClassDB::bind_static_method(cls, D_METHOD("send_password", "password"), &FOMultiplayer::send_password);
    ClassDB::bind_static_method(cls, D_METHOD("get_players"), &FOMultiplayer::get_players);
    ClassDB::bind_static_method(cls, D_METHOD("discover_lan_servers"), &FOMultiplayer::discover_lan_servers);
    ClassDB::bind_static_method(cls, D_METHOD("can_concede"), &FOMultiplayer::can_concede);
    ClassDB::bind_static_method(cls, D_METHOD("concede"), &FOMultiplayer::concede);
}

godot::String FOMultiplayer::host_game(const godot::String& player_name) {
    auto* app = App();
    if (!app)
        return "SERVER_WONT_START";
    if (app->Networking().IsConnected())
        return "ERR_ALREADY_CONNECTED";
    ClearSession();
    app->SetSinglePlayerGame(false);
    std::string destination = GetOptionsDB().Get<std::string>("network.server.uri");
    if (!GetOptionsDB().Get<bool>("network.server.external.force")) {
        try {
            app->StartServer();
            app->FreeServer();
        } catch (const std::exception& e) {
            ErrorLogger() << "FOMultiplayer::host_game: " << e.what();
            return "SERVER_WONT_START";
        }
    }
    if (!app->Networking().ConnectToServer(destination)) {
        if (!app->Networking().ConnectToLocalHostServer())
            return "ERR_CONNECT_TIMED_OUT";
    }
    TheSession().hosting = true;
    TheSession().active = true;
    app->Networking().SendMessage(HostMPGameMessage(ToStd(player_name), DependencyVersions()));
    return {};
}

godot::String FOMultiplayer::join_game(const godot::String& address, const godot::String& player_name,
                                       const godot::String& client_type)
{
    auto* app = App();
    if (!app)
        return "ERR_CONNECT_TIMED_OUT";
    if (app->Networking().IsConnected())
        return "ERR_ALREADY_CONNECTED";
    ClearSession();
    app->SetSinglePlayerGame(false);
    const std::string destination = ToStd(address.strip_edges());
    if (destination.empty() || !app->Networking().ConnectToServer(destination))
        return "ERR_CONNECT_TIMED_OUT";
    GetOptionsDB().Set<std::string>("setup.multiplayer.host.address", std::string{destination});
    GetOptionsDB().Set<std::string>("setup.multiplayer.player.name", ToStd(player_name));

    // The cookie the server gave last time lets it recognise us.
    boost::uuids::uuid cookie = boost::uuids::nil_uuid();
    try {
        const auto option = ServerOption(destination);
        if (!GetOptionsDB().OptionExists(option + ".cookie"))
            GetOptionsDB().Add<std::string>(option + ".cookie", "OPTIONS_DB_SERVER_COOKIE",
                                            boost::uuids::to_string(cookie));
        if (!GetOptionsDB().OptionExists(option + ".address"))
            GetOptionsDB().Add<std::string>(option + ".address", "OPTIONS_DB_SERVER_COOKIE", "");
        GetOptionsDB().Set(option + ".address", destination);
        cookie = boost::uuids::string_generator{}(GetOptionsDB().Get<std::string>(option + ".cookie"));
    } catch (const std::exception& e) {
        WarnLogger() << "FOMultiplayer::join_game: no cookie for " << destination << ": " << e.what();
    }
    auto type = ClientTypeFromName(client_type);
    if (type == Networking::ClientType::INVALID_CLIENT_TYPE ||
        type == Networking::ClientType::CLIENT_TYPE_AI_PLAYER)
    { type = Networking::ClientType::CLIENT_TYPE_HUMAN_PLAYER; }
    TheSession().active = true;
    app->Networking().SendMessage(JoinGameMessage(ToStd(player_name), type, DependencyVersions(), cookie));
    return {};
}

void FOMultiplayer::leave() {
    auto* app = App();
    if (!app)
        return;
    if (app->Networking().IsConnected())
        app->Networking().DisconnectFromServer();
    app->Networking().SetPlayerID(Networking::INVALID_PLAYER_ID);
    app->Networking().SetHostPlayerID(Networking::INVALID_PLAYER_ID);
    ClearSession();
}

bool FOMultiplayer::is_connected_to_server() {
    auto* app = App();
    return app && app->Networking().IsConnected();
}

int FOMultiplayer::get_player_id() {
    auto* app = App();
    return app ? app->Networking().PlayerID() : Networking::INVALID_PLAYER_ID;
}

bool FOMultiplayer::is_host() {
    auto* app = App();
    return app && app->Networking().PlayerIsHost(app->Networking().PlayerID());
}

bool FOMultiplayer::has_role(const godot::String& role) {
    auto* app = App();
    if (!app)
        return false;
    using R = Networking::RoleType;
    R type = R::Roles_Count;
    if (role == "host")              type = R::ROLE_HOST;
    else if (role == "galaxy_setup") type = R::ROLE_GALAXY_SETUP;
    else if (role == "player")       type = R::ROLE_CLIENT_TYPE_PLAYER;
    else if (role == "observer")     type = R::ROLE_CLIENT_TYPE_OBSERVER;
    else if (role == "moderator")    type = R::ROLE_CLIENT_TYPE_MODERATOR;
    return type != R::Roles_Count && app->Networking().HasAuthRole(type);
}

godot::Dictionary FOMultiplayer::get_lobby() {
    const auto& lobby = TheSession().lobby;
    godot::Dictionary result;
    result["new_game"] = lobby.new_game;
    result["any_can_edit"] = lobby.any_can_edit;
    result["start_locked"] = lobby.start_locked;
    result["start_lock_cause"] = ToGodot(lobby.start_lock_cause);
    result["save_game"] = ToGodot(lobby.save_game);
    result["in_game"] = lobby.in_game;

    godot::Dictionary galaxy;
    galaxy["seed"] = ToGodot(lobby.seed);
    galaxy["size"] = lobby.size;
    galaxy["shape"] = ToGodot(::to_string(lobby.shape));
    galaxy["age"] = ToGodot(::to_string(lobby.age));
    galaxy["starlane_freq"] = ToGodot(::to_string(lobby.starlane_freq));
    galaxy["planet_density"] = ToGodot(::to_string(lobby.planet_density));
    galaxy["specials_freq"] = ToGodot(::to_string(lobby.specials_freq));
    galaxy["monster_freq"] = ToGodot(::to_string(lobby.monster_freq));
    galaxy["native_freq"] = ToGodot(::to_string(lobby.native_freq));
    galaxy["ai_aggression"] = ToGodot(::to_string(lobby.ai_aggr));
    result["galaxy"] = galaxy;

    godot::Array players;
    for (const auto& [player_id, psd] : lobby.players)
        players.push_back(PlayerDict(player_id, psd));
    result["players"] = players;

    godot::Array save_empires;
    for (const auto& [empire_id, data] : lobby.save_game_empire_data) {
        godot::Dictionary empire;
        empire["empire_id"] = empire_id;
        empire["empire_name"] = ToGodot(data.empire_name);
        empire["player_name"] = ToGodot(data.player_name);
        empire["color"] = ToColor(data.color);
        empire["eliminated"] = data.eliminated;
        save_empires.push_back(empire);
    }
    result["save_empires"] = save_empires;
    return result;
}

bool FOMultiplayer::send_lobby(const godot::Dictionary& changes) {
    auto lobby = TheSession().lobby;
    if (changes.has("new_game"))     lobby.new_game = changes["new_game"];
    if (changes.has("any_can_edit")) lobby.any_can_edit = changes["any_can_edit"];
    if (changes.has("save_game")) {
        lobby.save_game = ToStd(changes["save_game"]);
        lobby.save_game_empire_data.clear();
    }
    if (changes.has("galaxy")) {
        const godot::Dictionary galaxy = changes["galaxy"];
        if (galaxy.has("seed"))           lobby.seed = ToStd(galaxy["seed"]);
        if (galaxy.has("size"))           lobby.size = galaxy["size"];
        if (galaxy.has("shape"))          lobby.shape = ShapeFromString(ToStd(galaxy["shape"]), lobby.shape);
        if (galaxy.has("age"))            lobby.age = GalaxySetupOptionGenericFromString(ToStd(galaxy["age"]), lobby.age);
        if (galaxy.has("starlane_freq"))  lobby.starlane_freq = GalaxySetupOptionGenericFromString(ToStd(galaxy["starlane_freq"]), lobby.starlane_freq);
        if (galaxy.has("planet_density")) lobby.planet_density = GalaxySetupOptionGenericFromString(ToStd(galaxy["planet_density"]), lobby.planet_density);
        if (galaxy.has("specials_freq"))  lobby.specials_freq = GalaxySetupOptionGenericFromString(ToStd(galaxy["specials_freq"]), lobby.specials_freq);
        if (galaxy.has("monster_freq"))   lobby.monster_freq = GalaxySetupOptionMonsterFreqFromString(ToStd(galaxy["monster_freq"]), lobby.monster_freq);
        if (galaxy.has("native_freq"))    lobby.native_freq = GalaxySetupOptionGenericFromString(ToStd(galaxy["native_freq"]), lobby.native_freq);
        if (galaxy.has("ai_aggression"))  lobby.ai_aggr = AggressionFromString(ToStd(galaxy["ai_aggression"]), lobby.ai_aggr);
    }
    if (changes.has("players")) {
        // The players as given: existing ones keep what isn't changed, and a
        // new AI player (player_id -1) starts from defaults.
        std::list<std::pair<int, PlayerSetupData>> players;
        const godot::Array given = changes["players"];
        for (int64_t i = 0; i < given.size(); ++i) {
            const godot::Dictionary player = given[i];
            const int player_id = player.get("player_id", Networking::INVALID_PLAYER_ID);
            PlayerSetupData psd;
            for (const auto& [id, existing] : lobby.players)
                if (id == player_id && player_id != Networking::INVALID_PLAYER_ID)
                    psd = existing;
            players.emplace_back(player_id, PlayerFromDict(player, std::move(psd)));
        }
        lobby.players = std::move(players);
    }
    // What we send is what we show until the server answers.
    TheSession().lobby = lobby;
    if (get_player_id() == Networking::INVALID_PLAYER_ID)
        return false;
    return Send(LobbyUpdateMessage(lobby));
}

bool FOMultiplayer::set_ready(bool ready) {
    auto lobby = TheSession().lobby;
    bool found = false;
    for (auto& [player_id, psd] : lobby.players) {
        if (player_id == get_player_id()) {
            psd.player_ready = ready;
            found = true;
        }
    }
    if (!found)
        return false;
    TheSession().lobby = lobby;
    return Send(LobbyUpdateMessage(lobby));
}

bool FOMultiplayer::send_chat(const godot::String& text, const godot::PackedInt32Array& recipients) {
    const std::string message = ToStd(text.strip_edges());
    if (message.empty())
        return false;
    std::set<int> to;
    for (int64_t i = 0; i < recipients.size(); ++i)
        to.insert(recipients[i]);
    const bool pm = !to.empty();
    return Send(PlayerChatMessage(message, std::move(to), pm));
}

godot::Array FOMultiplayer::get_chat() {
    godot::Array result;
    for (const auto& entry : TheSession().chat) {
        godot::Dictionary line;
        line["player_name"] = ToGodot(entry.player_name);
        line["text"] = ToGodot(entry.text);
        line["color"] = ToColor(entry.text_color);
        line["time"] = ToGodot(entry.timestamp.is_not_a_date_time() ? std::string{} :
                               boost::posix_time::to_simple_string(entry.timestamp.time_of_day()));
        result.push_back(line);
    }
    return result;
}

bool FOMultiplayer::send_password(const godot::String& password) {
    return Send(AuthResponseMessage(TheSession().auth_player_name, ToStd(password)));
}

godot::Array FOMultiplayer::get_players() {
    godot::Array result;
    auto* app = App();
    if (!app)
        return result;
    for (const auto& [player_id, info] : app->Players()) {
        godot::Dictionary player;
        player["player_id"] = player_id;
        player["name"] = ToGodot(info.name);
        player["empire_id"] = info.empire_id;
        player["client_type"] = ClientTypeName(info.client_type);
        player["host"] = info.host;
        const auto* empire = app->GetEmpire(info.empire_id);
        player["empire_name"] = empire ? ToGodot(empire->Name()) : godot::String();
        player["color"] = empire ? ToColor(empire->Color()) : godot::Color(0.6f, 0.6f, 0.6f, 1.0f);
        player["ready"] = empire && empire->Ready();
        player["eliminated"] = empire && empire->Eliminated();
        result.push_back(player);
    }
    return result;
}

godot::PackedStringArray FOMultiplayer::discover_lan_servers() {
    godot::PackedStringArray result;
    auto* app = App();
    if (!app)
        return result;
    try {
        for (const auto& name : app->Networking().DiscoverLANServerNames())
            result.push_back(ToGodot(name));
    } catch (const std::exception& e) {
        WarnLogger() << "FOMultiplayer::discover_lan_servers: " << e.what();
    }
    return result;
}

bool FOMultiplayer::can_concede() {
    auto* app = App();
    if (!app || app->SinglePlayerGame() || !app->GameStarted())
        return false;
    auto& rules = GetGameRules();
    return rules.RuleExists("RULE_ALLOW_CONCEDE") && rules.Get<bool>("RULE_ALLOW_CONCEDE");
}

bool FOMultiplayer::concede() {
    if (!can_concede())
        return false;
    return Send(EliminateSelfMessage());
}

void FOMultiplayer::SetLobby(MultiplayerLobbyData lobby)
{ TheSession().lobby = std::move(lobby); }

void FOMultiplayer::AddChat(ChatHistoryEntity entry)
{ TheSession().chat.push_back(std::move(entry)); }

bool FOMultiplayer::InSession()
{ return TheSession().active; }

void FOMultiplayer::ClearSession()
{ TheSession() = Session{}; }

void FOMultiplayer::SetAuthPlayerName(std::string name)
{ TheSession().auth_player_name = std::move(name); }
