#include "FreeOrionNode.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/translation_server.hpp>
#include <godot_cpp/classes/window.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

#include "GodotClientApp.h"
#include "GodotI18n.h"
#include "designer/FODesigner.h"

#include "../ClientNetworking.h"
#include "../../Empire/Empire.h"
#include "../../util/ranges.h"
#include "../../combat/CombatLogManager.h"
#include "../../util/Directories.h"
#include "../../util/GameRules.h"
#include "../../util/i18n.h"
#include "../../util/OptionsDB.h"
#include "../../util/Version.h"

#include <chrono>
#include <cmath>

namespace {
    /// Maximum time spent dispatching queued server messages per frame. At least one
    /// message is always dispatched per frame, so a slow message (e.g. a large turn
    /// update) delays only the messages queued after it, never reorders them.
    constexpr std::chrono::milliseconds MESSAGE_DISPATCH_BUDGET{8};
}

void FreeOrionNode::_bind_methods() {
    godot::ClassDB::bind_method(godot::D_METHOD("get_version"), &FreeOrionNode::get_version);
    godot::ClassDB::bind_method(godot::D_METHOD("get_user_data_dir"), &FreeOrionNode::get_user_data_dir);
    godot::ClassDB::bind_method(godot::D_METHOD("get_user_config_dir"), &FreeOrionNode::get_user_config_dir);
    godot::ClassDB::bind_method(godot::D_METHOD("get_resource_dir"), &FreeOrionNode::get_resource_dir);
    godot::ClassDB::bind_method(godot::D_METHOD("get_current_turn"), &FreeOrionNode::get_current_turn);
    godot::ClassDB::bind_method(godot::D_METHOD("get_single_player_game"), &FreeOrionNode::get_single_player_game);
    godot::ClassDB::bind_method(godot::D_METHOD("parsing_thread"), &FreeOrionNode::parsing_thread);
    godot::ClassDB::bind_method(godot::D_METHOD("start_network_thread"), &FreeOrionNode::start_network_thread);
    godot::ClassDB::bind_method(godot::D_METHOD("start_parsing_thread"), &FreeOrionNode::start_parsing_thread);
    godot::ClassDB::bind_method(godot::D_METHOD("new_single_player_game"), &FreeOrionNode::new_single_player_game);
    godot::ClassDB::bind_method(godot::D_METHOD("start_turn"), &FreeOrionNode::start_turn);
    godot::ClassDB::bind_method(godot::D_METHOD("set_view", "center", "zoom"), &FreeOrionNode::set_view);
    godot::ClassDB::bind_method(godot::D_METHOD("get_saved_view"), &FreeOrionNode::get_saved_view);
    godot::ClassDB::bind_method(godot::D_METHOD("quit_game"), &FreeOrionNode::quit_game);
    godot::ClassDB::bind_method(godot::D_METHOD("revise_turn"), &FreeOrionNode::revise_turn);
    godot::ClassDB::bind_method(godot::D_METHOD("is_quitting"), &FreeOrionNode::is_quitting);
    godot::ClassDB::bind_method(godot::D_METHOD("options_get_bool"), &FreeOrionNode::options_get_bool);
    godot::ClassDB::bind_method(godot::D_METHOD("options_get_string"), &FreeOrionNode::options_get_string);
    godot::ClassDB::bind_method(godot::D_METHOD("options_find_options", "prefix", "allow_unrecognized"), &FreeOrionNode::options_find_options, DEFVAL(false));
    godot::ClassDB::bind_method(godot::D_METHOD("options_exists"), &FreeOrionNode::options_exists);
    godot::ClassDB::bind_method(godot::D_METHOD("options_add_string"), &FreeOrionNode::options_add_string);
    godot::ClassDB::bind_method(godot::D_METHOD("options_set_string"), &FreeOrionNode::options_set_string);
    godot::ClassDB::bind_method(godot::D_METHOD("options_commit", "only_if_dirty", "only_non_default"),
                                &FreeOrionNode::options_commit,
                                DEFVAL(true),
                                DEFVAL(true));

    ADD_SIGNAL(godot::MethodInfo("parsing_completed"));
    ADD_SIGNAL(godot::MethodInfo("start_game", godot::PropertyInfo(godot::Variant::BOOL, "is_new_game")));
    ADD_SIGNAL(godot::MethodInfo("turn_update"));
    ADD_SIGNAL(godot::MethodInfo("game_ended"));
    ADD_SIGNAL(godot::MethodInfo("combat_logs_updated"));
    ADD_SIGNAL(godot::MethodInfo("diplomacy_changed"));
    ADD_SIGNAL(godot::MethodInfo("turn_progress",
                                 godot::PropertyInfo(godot::Variant::STRING, "phase"),
                                 godot::PropertyInfo(godot::Variant::STRING, "text")));
    ADD_SIGNAL(godot::MethodInfo("server_error",
                                 godot::PropertyInfo(godot::Variant::STRING, "message"),
                                 godot::PropertyInfo(godot::Variant::BOOL, "fatal")));
    ADD_SIGNAL(godot::MethodInfo("game_aborted", godot::PropertyInfo(godot::Variant::STRING, "message")));
    ADD_SIGNAL(godot::MethodInfo("save_completed",
                                 godot::PropertyInfo(godot::Variant::STRING, "filename"),
                                 godot::PropertyInfo(godot::Variant::INT, "bytes_written")));
}

FreeOrionNode::FreeOrionNode()
{ }

FreeOrionNode::~FreeOrionNode()
{ }

void FreeOrionNode::_ready() {
    if (godot::Engine::get_singleton()->is_editor_hint())
        return;

    std::string executable_path = godot::OS::get_singleton()->get_executable_path().utf8().get_data();
#ifdef FREEORION_MACOSX
    InitDirs(executable_path, true);
#else
    InitDirs(executable_path);
#endif

#ifdef FREEORION_WIN32
    GetOptionsDB().Add<std::filesystem::path>("misc.server-local-binary.path", UserStringNop("OPTIONS_DB_FREEORIOND_PATH"),   GetBinDir() / "freeoriond.exe");
#else
    GetOptionsDB().Add<std::filesystem::path>("misc.server-local-binary.path", UserStringNop("OPTIONS_DB_FREEORIOND_PATH"),   GetBinDir() / "freeoriond");
#endif

    GetOptionsDB().SetFromFile(GetConfigPath(), FreeOrionVersionString());
    GetOptionsDB().SetFromFile(GetPersistentConfigPath());

    std::vector<std::string> args;
    args.emplace_back(std::move(executable_path));
    const godot::PackedStringArray wargs = godot::OS::get_singleton()->get_cmdline_args();
    for (const godot::String &warg : wargs) {
        const std::string arg = warg.utf8().get_data();
        // Exclude Godot's options
        if (arg != "-s" && arg.rfind("-g", 0) != 0) {
            InfoLogger() << "Command line " << arg;
            args.emplace_back(std::move(arg));
        }
    }
    const godot::PackedStringArray uwargs = godot::OS::get_singleton()->get_cmdline_user_args();
    for (const godot::String &uwarg : uwargs) {
        const std::string arg = uwarg.utf8().get_data();
        // Exclude Godot's options
        if (arg != "-s" && arg.rfind("-g", 0) != 0) {
            InfoLogger() << "User command line " << arg;
            args.emplace_back(std::move(arg));
        }
    }
    // override previously-saved and default options with command line parameters and flags
    GetOptionsDB().SetFromCommandLine(args);

    CompleteXDGMigration();

#if !defined(FREEORION_ANDROID)
    // Handle the case where the resource.path does not exist anymore
    // gracefully by resetting it to the standard path into the
    // application bundle.  This may happen if a previous installed
    // version of FreeOrion was residing in a different directory.
    if (!std::filesystem::exists(GetResourceDir()) ||
        !std::filesystem::exists(GetResourceDir() / "credits.xml") ||
        !std::filesystem::exists(GetResourceDir() / "data" / "art" / "misc" / "missing.png"))
    {
        DebugLogger() << "Resources directory " << PathToString(GetResourceDir()) << " from config.xml missing or does not contain expected files. Resetting to default.";

        GetOptionsDB().Set<std::filesystem::path>("resource.path", std::filesystem::canonical("../default")); // Temporary default for Godot client prototype development

        // double-check that resetting actually fixed things...
        if (!std::filesystem::exists(GetResourceDir()) ||
            !std::filesystem::exists(GetResourceDir() / "credits.xml") ||
            !std::filesystem::exists(GetResourceDir() / "data" / "art" / "misc" / "missing.png"))
        {
            DebugLogger() << "Default Resources directory missing or does not contain expected files. Cannot start game.";
            throw std::runtime_error("Unable to load game resources at default location: " +
                                     PathToString(GetResourceDir()) + " : Install may be broken.");
        }
    }
#endif

    m_app = std::make_unique<GodotClientApp>();

    if (godot::Window* window = get_window()) {
        window->set_auto_translate_mode(godot::Node::AUTO_TRANSLATE_MODE_DISABLED);
        window->set_title("FreeOrion " + get_version());
    }

    godot::String locale = godot::String::utf8(Language().c_str());
    godot::Ref<GodotI18n> translation;
    translation.instantiate();
    translation->set_locale(locale);
    godot::TranslationServer::get_singleton()->add_translation(translation);
    godot::TranslationServer::get_singleton()->set_locale(locale);

    m_parsing_thread = godot::Ref<godot::Thread>();
    m_parsing_thread.instantiate();

    // Message dispatch is enabled by start_network_thread()
    set_process(false);
}

void FreeOrionNode::_process(double) {
    if (!m_app)
        return;

    if (m_app->Quitting()) {
        // Leaving the game: drop what the server still sends until it's gone.
        while (m_app->Networking().GetMessage()) {}
        if (m_app->UpdateQuitting())
            emit_signal("game_ended");
        return;
    }

    const auto deadline = std::chrono::steady_clock::now() + MESSAGE_DISPATCH_BUDGET;
    do {
        auto msg = m_app->Networking().GetMessage();
        if (!msg)
            break;
        HandleMessage(std::move(*msg));
    } while (m_app && !m_app->Quitting() && std::chrono::steady_clock::now() < deadline);

    // The server went away mid-game (crashed or was killed).
    if (m_app && m_app->GameStarted() && !m_app->Quitting() && !m_app->Networking().IsConnected())
        AbortGame(UserString("SERVER_LOST"));
}

void FreeOrionNode::AbortGame(const std::string& message) {
    ErrorLogger() << "FreeOrionNode::AbortGame: " << message;
    m_app->StartQuitting();
    emit_signal("game_aborted", godot::String::utf8(message.c_str()));
}

void FreeOrionNode::_exit_tree() {
    if (godot::Engine::get_singleton()->is_editor_hint())
        return;

    DebugLogger() << "FreeOrionNode::_exit_tree(): Stopping freeorion node";
    set_process(false);
    if (m_parsing_thread.is_valid() && m_parsing_thread->is_started())
        m_parsing_thread->wait_to_finish();
    m_app.reset();
    DebugLogger() << "FreeOrionNode::_exit_tree(): Freeorion node stopped";

    ShutdownLoggingSystemFileSink();
}

godot::String FreeOrionNode::get_version() const
{ return godot::String::utf8(FreeOrionVersionString().c_str()); }

godot::String FreeOrionNode::get_user_data_dir() const
{ return godot::String::utf8(PathToString(GetUserDataDir()).c_str()); }

godot::String FreeOrionNode::get_resource_dir() const
{ return godot::String::utf8(PathToString(GetResourceDir()).c_str()); }

godot::String FreeOrionNode::get_user_config_dir() const
{ return godot::String::utf8(PathToString(GetUserConfigDir()).c_str()); }

int FreeOrionNode::get_current_turn() const
{ return m_app ? m_app->CurrentTurn() : INVALID_GAME_TURN; }

bool FreeOrionNode::get_single_player_game() const
{ return m_app ? m_app->SinglePlayerGame() : false; }

void FreeOrionNode::parsing_thread() {
    DebugLogger() << "FreeOrionNode::parsing_thread(): Freeorion parsing started";
    m_app->StartParsingContent();
    call_deferred("emit_signal", "parsing_completed");
    DebugLogger() << "FreeOrionNode::parsing_thread(): Freeorion parsing stopped";
}

void FreeOrionNode::start_network_thread() {
    DebugLogger() << "FreeOrionNode::start_network_thread(): dispatching server messages on the main thread";
    set_process(true);
}

void FreeOrionNode::start_parsing_thread()
{ m_parsing_thread->start(godot::Callable(this, "parsing_thread")); }

void FreeOrionNode::new_single_player_game()
{ m_app->NewSinglePlayerGame(); }

void FreeOrionNode::start_turn() {
    m_app->Autosave(GodotClientApp::AutosaveMoment::TURN_END);
    // The empire's designs and those put aside, so a save keeps both.
    auto& designs = m_ui_data.ordered_ship_design_ids_and_obsolete;
    designs.clear();
    if (const auto* empire = m_app->GetEmpire(m_app->EmpireID())) {
        for (const int id : empire->ShipDesigns())
            if (!FODesigner::ObsoleteDesigns().contains(id))
                designs.emplace_back(id, std::pair{false, 0});
    }
    for (const int id : FODesigner::ObsoleteDesigns())
        designs.emplace_back(id, std::pair{true, 0});
    m_app->StartTurn(m_ui_data);
}

// The GG client stores the map window's screen offset in map_left/top; this
// client stores the camera's world centre there. Zoom steps mean the same in
// both: zoom = 2^(steps / 4).
void FreeOrionNode::set_view(godot::Vector2 center, double zoom) {
    m_ui_data.map_left = static_cast<int>(std::lround(center.x));
    m_ui_data.map_top = static_cast<int>(std::lround(center.y));
    m_ui_data.map_zoom_steps_in = zoom > 0.0 ? 4.0 * std::log2(zoom) : 0.0;
}

godot::Dictionary FreeOrionNode::get_saved_view() const {
    godot::Dictionary view;
    if (!m_loaded_ui_data)
        return view;
    view["center"] = godot::Vector2(static_cast<float>(m_loaded_ui_data->map_left),
                                    static_cast<float>(m_loaded_ui_data->map_top));
    view["zoom"] = std::pow(2.0, m_loaded_ui_data->map_zoom_steps_in / 4.0);
    return view;
}

namespace {
    // Stringtable key naming a turn processing phase, as the GG message window uses.
    std::string TurnPhaseKey(Message::TurnProgressPhase phase) {
        switch (phase) {
        case Message::TurnProgressPhase::FLEET_MOVEMENT:      return "TURN_PROGRESS_PHASE_FLEET_MOVEMENT";
        case Message::TurnProgressPhase::COMBAT:              return "TURN_PROGRESS_PHASE_COMBAT";
        case Message::TurnProgressPhase::EMPIRE_PRODUCTION:   return "TURN_PROGRESS_PHASE_EMPIRE_GROWTH";
        case Message::TurnProgressPhase::WAITING_FOR_PLAYERS: return "TURN_PROGRESS_PHASE_WAITING";
        case Message::TurnProgressPhase::PROCESSING_ORDERS:   return "TURN_PROGRESS_PHASE_ORDERS";
        case Message::TurnProgressPhase::COLONIZE_AND_SCRAP:  return "TURN_PROGRESS_COLONIZE_AND_SCRAP";
        case Message::TurnProgressPhase::DOWNLOADING:         return "TURN_PROGRESS_PHASE_DOWNLOADING";
        case Message::TurnProgressPhase::LOADING_GAME:        return "TURN_PROGRESS_PHASE_LOADING_GAME";
        case Message::TurnProgressPhase::GENERATING_UNIVERSE: return "TURN_PROGRESS_PHASE_GENERATING_UNIVERSE";
        case Message::TurnProgressPhase::STARTING_AIS:        return "TURN_PROGRESS_STARTING_AIS";
        default:                                              return "UNKNOWN";
        }
    }
}

void FreeOrionNode::revise_turn() {
    if (m_app && m_app->Networking().IsConnected())
        m_app->Networking().SendMessage(UnreadyMessage());
}

void FreeOrionNode::quit_game() {
    if (m_app)
        m_app->StartQuitting();
}

bool FreeOrionNode::is_quitting() const
{ return m_app && m_app->Quitting(); }

bool FreeOrionNode::options_get_bool(godot::String option) const
{ return GetOptionsDB().Get<bool>(option.utf8().get_data()); }

godot::String FreeOrionNode::options_get_string(godot::String option) const
{ return godot::String::utf8(GetOptionsDB().Get<std::string>(option.utf8().get_data()).c_str()); }

godot::PackedStringArray FreeOrionNode::options_find_options(godot::String prefix, bool allow_unrecognized) const {
    godot::PackedStringArray options;
    for (const auto& option : GetOptionsDB().FindOptions(prefix.utf8().get_data(), allow_unrecognized))
        options.push_back(godot::String::utf8(option.data(), option.size()));
    return options;
}

bool FreeOrionNode::options_exists(godot::String option) const
{ return GetOptionsDB().OptionExists(option.utf8().get_data()); }

void FreeOrionNode::options_add_string(godot::String option, godot::String description, godot::String value) {
    GetOptionsDB().Add<std::string>(option.utf8().get_data(),
        description.utf8().get_data(),
        value.utf8().get_data());
}

void FreeOrionNode::options_set_string(godot::String option, godot::String value)
{ GetOptionsDB().Set<std::string>(option.utf8().get_data(), value.utf8().get_data()); }

bool FreeOrionNode::options_commit(bool only_if_dirty, bool only_non_default)
{ return GetOptionsDB().Commit(only_if_dirty, only_non_default); }

// Client-side state derived from a new turn's data, as the GG client's
// HumanClientFSM and MapWnd::InitTurn compute it.
void FreeOrionNode::InitTurnState() {
    // Pathfinding (fleet move orders, routes) needs the client's system graph
    GetUniverse().InitializeSystemGraph(Empires(), GetUniverse().Objects());
    GetUniverse().UpdateCommonFilteredSystemGraphsWithMainObjectMap(Empires());

    // Meter estimates for next turn, with the effect accounting that explains
    // them, as MapWnd::InitTurn does. Orders loaded with a saved game are
    // re-applied first so the estimates include them.
    auto& context = m_app->GetContext();
    GetUniverse().InitMeterEstimatesAndDiscrepancies(context);
    m_app->Orders().ApplyOrders(context);
    GetUniverse().UpdateMeterEstimates(context);
    GetUniverse().ApplyAppearanceEffects(context);

    // Resource pools: available PP/RP/IP and the projected queues
    for (auto& empire : Empires() | range_values) {
        empire->UpdateResourcePools(context,
                                    empire->TechCostsTimes(context),
                                    empire->PlanetAnnexationCosts(context),
                                    empire->PolicyAdoptionCosts(context),
                                    empire->ProductionCostsTimes(context));
    }
}

void FreeOrionNode::HandleMessage(Message&& msg) {
    try {
        switch (msg.Type()) {
        case Message::MessageType::SET_AUTH_ROLES: {
            ExtractSetAuthorizationRolesMessage(msg, m_app->Networking().AuthorizationRoles());
            break;
        }
        case Message::MessageType::HOST_SP_GAME: {
            try {
                int host_id = boost::lexical_cast<int>(msg.Text());

                m_app->Networking().SetPlayerID(host_id);
                m_app->Networking().SetHostPlayerID(host_id);
            } catch (const boost::bad_lexical_cast& ex) {
                ErrorLogger() << "FreeOrionNode::HandleMessage : (HOST_SP_GAME) Host id " << msg.Text() << " is not a number: " << ex.what();
            }
            break;
        }
        case Message::MessageType::GAME_START: {
            bool loaded_game_data;
            bool ui_data_available;
            SaveGameUIData ui_data;
            bool save_state_string_available;
            std::string save_state_string; // ignored - used by AI but not by human client
            OrderSet orders;
            bool single_player_game = false;
            int empire_id = ALL_EMPIRES;
            int current_turn = INVALID_GAME_TURN;
            m_app->Orders().Reset();
            try {
                ExtractGameStartMessageData(msg,                 single_player_game,             empire_id,
                                            current_turn,        Empires(),                      GetUniverse(),
                                            GetSpeciesManager(), GetCombatLogManager(),          GetSupplyManager(),
                                            m_app->Players(),    m_app->Orders(),                loaded_game_data,
                                            ui_data_available,   ui_data,                        save_state_string_available,
                                            save_state_string,   m_app->GetGalaxySetupData());
            } catch (...) {
                return;
            }

            DebugLogger() << "Extracted GameStart message for turn: " << current_turn << " with empire: " << empire_id;

            m_app->SetSinglePlayerGame(single_player_game);
            m_app->SetEmpireID(empire_id);
            m_app->SetCurrentTurn(current_turn);

            GetGameRules().SetFromStrings(m_app->GetGalaxySetupData().GetGameRules());
            InitTurnState();

            m_app->RequestCombatLogs();

            // Keep the saved UI data (the view, design lists) to send back
            // with the next orders; the view is restored by GameShell.
            m_loaded_ui_data.reset();
            m_ui_data = SaveGameUIData{};
            FODesigner::ObsoleteDesigns().clear();
            if (loaded_game_data && ui_data_available) {
                m_loaded_ui_data = ui_data;
                m_ui_data = ui_data;
                // Designs the player put aside, as the GG client saves them.
                for (const auto& [design_id, obsolete] : ui_data.ordered_ship_design_ids_and_obsolete)
                    if (obsolete && obsolete->first)
                        FODesigner::ObsoleteDesigns().insert(design_id);
            }

            bool is_new_game = !(loaded_game_data && ui_data_available);
            m_app->StartGame(is_new_game);
            if (is_new_game)
                m_app->Autosave(GodotClientApp::AutosaveMoment::TURN_START);
            call_deferred("emit_signal", "start_game", is_new_game);

            if (m_app->AutoTurnsLeft() > 0) {
                SaveGameUIData ui_data;
                m_app->StartTurn(ui_data);
                m_app->DecAutoTurns();
            }

            break;
        }
        case Message::MessageType::TURN_PROGRESS: {
            Message::TurnProgressPhase phase_id;
            ExtractTurnProgressMessageData(msg, phase_id);
            m_app->HandleTurnPhaseUpdate(phase_id);
            const auto key = TurnPhaseKey(phase_id);
            call_deferred("emit_signal", "turn_progress", godot::String::utf8(key.c_str()),
                          godot::String::utf8(UserString(key).c_str()));
            break;
        }
        case Message::MessageType::TURN_PARTIAL_UPDATE: {
            ExtractTurnPartialUpdateMessageData(msg, m_app->EmpireID(), GetUniverse());
            break;
        }
        case Message::MessageType::TURN_UPDATE: {
            int current_turn = INVALID_GAME_TURN;
            m_app->Orders().Reset();
            ExtractTurnUpdateMessageData(msg,                   m_app->EmpireID(),   current_turn,
                                         Empires(),             GetUniverse(),       GetSpeciesManager(),
                                         GetCombatLogManager(), GetSupplyManager(),  m_app->Players());
            m_app->SetCurrentTurn(current_turn);
            InitTurnState();
            m_app->RequestCombatLogs();
            m_app->Autosave(GodotClientApp::AutosaveMoment::TURN_START);
            call_deferred("emit_signal", "turn_update");

            if (m_app->AutoTurnsLeft() > 0) {
                SaveGameUIData ui_data;
                m_app->StartTurn(ui_data);
                m_app->DecAutoTurns();
            }
            break;
        }
        case Message::MessageType::SAVE_GAME_COMPLETE: {
            std::string save_filename;
            int bytes_written = 0;
            ExtractServerSaveGameCompleteMessageData(msg, save_filename, bytes_written);
            m_app->SaveGameCompleted();
            call_deferred("emit_signal", "save_completed",
                          godot::String::utf8(save_filename.c_str()), bytes_written);
            break;
        }
        case Message::MessageType::DISPATCH_COMBAT_LOGS: {
            std::vector<std::pair<int, CombatLog>> logs;
            ExtractDispatchCombatLogsMessageData(msg, logs);
            auto& manager = GetCombatLogManager();
            for (auto& [log_id, log] : logs)
                manager.CompleteLog(log_id, std::move(log));
            call_deferred("emit_signal", "combat_logs_updated");
            break;
        }
        case Message::MessageType::ERROR_MSG: {
            int player_id = Networking::INVALID_PLAYER_ID;
            std::string problem_key, unlocalized_info;
            bool fatal = false;
            ExtractErrorMessageData(msg, player_id, problem_key, unlocalized_info, fatal);
            ErrorLogger() << "FreeOrionNode::HandleMessage : server error " << problem_key
                          << (fatal ? " (fatal) " : " ") << unlocalized_info;
            m_app->InitAutoTurns(0);
            const auto& text = UserStringExists(problem_key) ? UserString(problem_key) : problem_key;
            if (fatal && m_app->GameStarted())
                AbortGame(text);
            else
                emit_signal("server_error", godot::String::utf8(text.c_str()), fatal);
            break;
        }
        case Message::MessageType::END_GAME: {
            Message::EndGameReason reason = Message::EndGameReason::UNKNOWN;
            std::string player_name;
            ExtractEndGameMessageData(msg, reason, player_name);
            std::string text;
            switch (reason) {
            case Message::EndGameReason::LOCAL_CLIENT_DISCONNECT:
                text = UserString("SERVER_LOST");
                break;
            case Message::EndGameReason::PLAYER_DISCONNECT:
                text = boost::io::str(FlexibleFormat(UserString("PLAYER_DISCONNECTED")) % player_name);
                break;
            default:
                text = UserString("UNKNOWN");
            }
            AbortGame(text);
            break;
        }
        case Message::MessageType::DIPLOMACY: {
            DiplomaticMessage diplo_message;
            ExtractDiplomacyMessageData(msg, diplo_message);
            m_app->Empires().SetDiplomaticMessage(diplo_message);
            call_deferred("emit_signal", "diplomacy_changed");
            break;
        }
        case Message::MessageType::DIPLOMATIC_STATUS: {
            DiplomaticStatusUpdateInfo update;
            ExtractDiplomaticStatusMessageData(msg, update);
            m_app->Empires().SetDiplomaticStatus(update.empire1_id, update.empire2_id, update.diplo_status);
            call_deferred("emit_signal", "diplomacy_changed");
            break;
        }
        case Message::MessageType::PLAYER_CHAT:
        case Message::MessageType::PLAYER_STATUS:
        case Message::MessageType::TURN_TIMEOUT:
            // Not shown by this client yet.
            DebugLogger() << "FreeOrionNode::HandleMessage : ignoring message of type " << msg.Type();
            break;
        default:
            ErrorLogger() << "FreeOrionNode::HandleMessage : Not implemented reacting to message of type\""
                          << msg.Type() << "\".";
        }
    } catch (const std::exception& e) {
        ErrorLogger() << "FreeOrionNode::HandleMessage : Exception while reacting to message of type \""
                      << msg.Type() << "\". what: " << e.what();
    }
}
