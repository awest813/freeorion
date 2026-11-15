
#include "GodotClientApp.h"

#include <boost/format.hpp>
#include <map>

#ifdef FREEORION_ANDROID
#  include <godot_cpp/classes/engine.hpp>
#  include <godot_cpp/classes/object.hpp>
#endif

#include "../ClientNetworking.h"
#include "../../combat/CombatLogManager.h"
#include "../../Empire/Empire.h"
#include "../../parse/PythonParser.h"
#include "../../util/Directories.h"
#include "../../util/SaveGamePreviewUtils.h"
#include "../../util/GameRules.h"
#include "../../util/i18n.h"
#include "../../util/Logger.h"
#include "../../util/LoggerWithOptionsDB.h"
#include "../../util/OptionsDB.h"
#include "../../util/PythonCommon.h"
#include "../../util/Version.h"

namespace {
    // persistant between-executions game setup settings
    void AddOptions(OptionsDB& db) {
        db.Add("setup.empire.name",              UserStringNop("OPTIONS_DB_GAMESETUP_EMPIRE_NAME"),              std::string(""),            Validator<std::string>());
        db.Add("setup.player.name",              UserStringNop("OPTIONS_DB_GAMESETUP_PLAYER_NAME"),              std::string(""),            Validator<std::string>());
        db.Add("setup.empire.color.index",       UserStringNop("OPTIONS_DB_GAMESETUP_EMPIRE_COLOR"),             9,                          RangedValidator<int>(0, 100));
        db.Add("setup.initial.species",          UserStringNop("OPTIONS_DB_GAMESETUP_STARTING_SPECIES_NAME"),    std::string("SP_HUMAN"),    Validator<std::string>());
        db.Add("setup.multiplayer.player.name",  UserStringNop("OPTIONS_DB_MP_PLAYER_NAME"),     std::string(""),            Validator<std::string>());
        db.Add("setup.multiplayer.host.address", UserStringNop("OPTIONS_DB_MP_HOST_ADDRESS"),    std::string("localhost"),   Validator<std::string>());
        db.Add<int>("auto-advance-n-turns",      UserStringNop("OPTIONS_DB_AUTO_N_TURNS"),           0,
                    RangedValidator<int>(0, 400),       OptionsDB::Storable::UNSTORABLE);
        // Autosave, as in the GG client (save.auto.exit.enabled is in MultiplayerCommon).
        db.Add("save.auto.turn.start.enabled",   UserStringNop("OPTIONS_DB_AUTOSAVE_SINGLE_PLAYER_TURN_START"), true,  Validator<bool>());
        db.Add("save.auto.turn.end.enabled",     UserStringNop("OPTIONS_DB_AUTOSAVE_SINGLE_PLAYER_TURN_END"),   false, Validator<bool>());
        db.Add("save.auto.turn.interval",        UserStringNop("OPTIONS_DB_AUTOSAVE_TURNS"),                    1,     RangedValidator<int>(1, 50));
        db.Add("save.auto.file.limit",           UserStringNop("OPTIONS_DB_AUTOSAVE_LIMIT"),                    10,    RangedValidator<int>(1, 10000));
        db.Add("ui.map.detection.shown",         UserStringNop("OPTIONS_DB_UI_MAP_DETECTION_SHOWN"),            false, Validator<bool>());
        db.Add("ui.map.scale.legend.shown",      UserStringNop("OPTIONS_DB_GALAXY_MAP_SCALE_LINE"),             true,  Validator<bool>());
        db.Add("ui.map.scale.circle.shown",      UserStringNop("OPTIONS_DB_GALAXY_MAP_SCALE_CIRCLE"),           false, Validator<bool>());
        db.Add("ui.map.minimap.shown",           UserStringNop("OPTIONS_DB_UI_MAP_MINIMAP_SHOWN"),              true,  Validator<bool>());
        db.Add("resource.shipdesign.saved.enabled", UserStringNop("OPTIONS_DB_AUTO_ADD_SAVED_DESIGNS"),       true,  Validator<bool>());
        db.Add("ui.turn.readiness.check",        UserStringNop("OPTIONS_DB_UI_TURN_READINESS_CHECK"),           true,  Validator<bool>());
        db.Add("save.auto.initial.enabled",      UserStringNop("OPTIONS_DB_AUTOSAVE_GALAXY_CREATION"),          true,  Validator<bool>());
    }
    bool temp_bool = RegisterOptions(&AddOptions);

    /** Sets the default and current values for the string option @p option_name to @p option_value if initially empty */
    void SetEmptyStringDefaultOption(const std::string& option_name, const std::string& option_value) {
        OptionsDB& db = GetOptionsDB();
        if (db.Get<std::string>(option_name).empty()) {
            db.SetDefault(option_name, option_value);
            db.Set(option_name, option_value);
        }
    }

    /* Sets the value of options that need language-dependent default values.*/
    void SetStringtableDependentOptionDefaults() {
        SetEmptyStringDefaultOption("setup.empire.name", UserString("DEFAULT_EMPIRE_NAME"));
        std::string player_name = UserString("DEFAULT_PLAYER_NAME");
        SetEmptyStringDefaultOption("setup.player.name", player_name);
        SetEmptyStringDefaultOption("setup.multiplayer.player.name", player_name);
    }

    class LocalServerAlreadyRunningException : public std::runtime_error {
    public:
        LocalServerAlreadyRunningException() :
            std::runtime_error("LOCAL_SERVER_ALREADY_RUNNING_ERROR")
        {}
    };

    void ClearPreviousPendingSaves(std::queue<std::string>& pending_saves) {
        if (pending_saves.empty())
            return;
        WarnLogger() << "Clearing " << std::to_string(pending_saves.size()) << " pending save game request(s)";
        std::queue<std::string>().swap(pending_saves);
    }
}

GodotClientApp::GodotClientApp() {
    if (GetOptionsDB().Get<std::string>("log-file").empty()) {
        const std::string HUMAN_CLIENT_LOG_FILENAME((GetUserCacheDir() / "freeorion-godot.log").string());
        GetOptionsDB().Set("log-file", HUMAN_CLIENT_LOG_FILENAME);
    }

    InitLoggingSystem(GetOptionsDB().Get<std::string>("log-file"), "Godot");
    InitLoggingOptionsDBSystem();

    InfoLogger() << FreeOrionVersionString();

    LogDependencyVersions();

    SetStringtableDependentOptionDefaults();

    m_auto_turns = GetOptionsDB().Get<int>("auto-advance-n-turns");
}

GodotClientApp::~GodotClientApp() {
    m_networking->DisconnectFromServer();
#ifdef FREEORION_ANDROID
    if (auto* engine = godot::Engine::get_singleton()) {
        if (auto* plugin = engine->get_singleton("FreeOrion"))
            plugin->call("stopServer");
        else
            ErrorLogger() << "GodotClientApp::~GodotClientApp: FreeOrion plugin singleton not found";
    }
#else
    m_server_process.RequestTermination();
#endif
}

void GodotClientApp::StartParsingContent() {
    PythonCommon python;
    python.Initialize();
    python.SetModulesDirs({GetResourceDir() / "scripting"});
    parse::StartBackgroundParsing(PythonParser(python), GetSpeciesManager());
}

int GodotClientApp::EffectsProcessingThreads() const
{ return GetOptionsDB().Get<int>("effects.ui.threads"); }

GodotClientApp* GodotClientApp::GetApp()
{ return static_cast<GodotClientApp*>(s_app); }

void GodotClientApp::StartServer() {
    if (m_networking->PingLocalHostServer(std::chrono::milliseconds(100))) {
        ErrorLogger() << "Can't start local server because a server is already connecting at 127.0.0.0.";
        throw LocalServerAlreadyRunningException();
    }
#ifdef FREEORION_ANDROID
    DebugLogger() << "GodotClientApp::StartServer: starting server service";
    if (auto* engine = godot::Engine::get_singleton()) {
        if (auto* plugin = engine->get_singleton("FreeOrion")) {
            godot::PackedStringArray args;
            if (m_single_player_game) {
                args.append("--singleplayer");
                args.append("--skip-checksum");
            }
            plugin->call("startServer", args);
        } else
            ErrorLogger() << "GodotClientApp::StartServer: FreeOrion plugin singleton not found";
    }
    DebugLogger() << "... finished starting server service.";
#else
    std::filesystem::path SERVER_CLIENT_EXE = GetOptionsDB().Get<std::filesystem::path>("misc.server-local-binary.path");
    DebugLogger() << "GodotClientApp::StartServer: " << PathToString(SERVER_CLIENT_EXE);

#  ifdef FREEORION_MACOSX
    // On OSX set environment variable DYLD_LIBRARY_PATH to python framework folder
    // bundled with app, so the dynamic linker uses the bundled python library.
    // Otherwise the dynamic linker will look for a correct python lib in system
    // paths, and if it can't find it, throw an error and terminate!
    // Setting environment variable here, spawned child processes will inherit it.
    const char* old_library_path = getenv("DYLD_LIBRARY_PATH");
    const auto library_path = (old_library_path != nullptr) ? (GetPythonHome().string() + ":" + old_library_path) : GetPythonHome().string();
    setenv("DYLD_LIBRARY_PATH", library_path.c_str(), 1);
#  endif

    std::vector<std::string> args;
    std::string ai_config = GetOptionsDB().Get<std::string>("ai-config");
    std::string ai_path = GetOptionsDB().Get<std::string>("ai-path");
    args.emplace_back("--resource.path");
    args.emplace_back("\"" + PathToString(GetOptionsDB().Get<std::filesystem::path>("resource.path")) + "\"");

    auto force_log_level = GetOptionsDB().Get<std::string>("log-level");
    if (!force_log_level.empty()) {
        args.emplace_back("--log-level");
        args.emplace_back(GetOptionsDB().Get<std::string>("log-level"));
    }

    if (ai_path != GetOptionsDB().GetDefaultValueString("ai-path")) {
        args.emplace_back("--ai-path");
        args.emplace_back(ai_path);
        DebugLogger() << "ai-path set to '" << ai_path << "'";
    }
    if (!ai_config.empty()) {
        args.emplace_back("--ai-config");
        args.emplace_back(ai_config);
        DebugLogger() << "ai-config set to '" << ai_config << "'";
    } else {
        DebugLogger() << "ai-config not set.";
    }
    if (m_single_player_game) {
        args.emplace_back("--singleplayer");
        args.emplace_back("--skip-checksum");
    }
#  ifdef FREEORION_MACOSX
    args.emplace_back("--testing");
#  endif
    DebugLogger() << "Launching server process with args: ";
    for (auto arg : args)
        DebugLogger() << arg;
    m_server_process = Process(m_networking->IoContext(), PathToString(SERVER_CLIENT_EXE), args);
#endif
    DebugLogger() << "... finished launching server process.";
}

void GodotClientApp::FreeServer() {
#ifdef FREEORION_ANDROID
    if (auto* engine = godot::Engine::get_singleton()) {
        if (auto* plugin = engine->get_singleton("FreeOrion"))
            plugin->call("stopServer");
        else
            ErrorLogger() << "GodotClientApp::FreeServer: FreeOrion plugin singleton not found";
    }
#else
    m_server_process.Free();
#endif
    m_networking->SetPlayerID(Networking::INVALID_PLAYER_ID);
    m_networking->SetHostPlayerID(Networking::INVALID_PLAYER_ID);
    SetEmpireID(ALL_EMPIRES);
}

void GodotClientApp::NewSinglePlayerGame() {
    DebugLogger() << "GodotClientApp::NewSinglePlayerGame start";
    ClearPreviousPendingSaves(m_game_saves_in_progress);

    m_single_player_game = true;
    try {
        StartServer();
    } catch (const LocalServerAlreadyRunningException& err) {
        return;
    } catch (const std::runtime_error& err) {
        ErrorLogger() << "GodotClientApp::NewSinglePlayerGame : Couldn't start server.  Got error message: " << err.what();
        return;
    }

    auto game_rules = GetGameRules().GetRulesAsStrings();

    if (!m_networking->ConnectToLocalHostServer()) {
        DebugLogger() << "Not connected; returning to intro screen and showing timed out error";
        //ResetToIntro(true);
        //ClientUI::MessageBox(UserString("ERR_CONNECT_TIMED_OUT"), true);
        return;
    }

    SinglePlayerSetupData setup_data;
    setup_data.new_game = true;
    setup_data.filename.clear();  // not used for new game

    // get values stored in options from previous time game was run or
    // from just having run GalaxySetupWnd

    // GalaxySetupData
    setup_data.SetSeed(GetOptionsDB().Get<std::string>("setup.seed"));
    setup_data.size =             GetOptionsDB().Get<int>("setup.star.count");
    setup_data.shape =            GetOptionsDB().Get<Shape>("setup.galaxy.shape");
    setup_data.age =              GetOptionsDB().Get<GalaxySetupOptionGeneric>("setup.galaxy.age");
    setup_data.starlane_freq =    GetOptionsDB().Get<GalaxySetupOptionGeneric>("setup.starlane.frequency");
    setup_data.planet_density =   GetOptionsDB().Get<GalaxySetupOptionGeneric>("setup.planet.density");
    setup_data.specials_freq =    GetOptionsDB().Get<GalaxySetupOptionGeneric>("setup.specials.frequency");
    setup_data.monster_freq =     GetOptionsDB().Get<GalaxySetupOptionMonsterFreq>("setup.monster.frequency");
    setup_data.native_freq =      GetOptionsDB().Get<GalaxySetupOptionGeneric>("setup.native.frequency");
    setup_data.ai_aggr =          GetOptionsDB().Get<Aggression>("setup.ai.aggression");
    setup_data.game_rules =       game_rules;


    // SinglePlayerSetupData contains a map of PlayerSetupData, for
    // the human and AI players.  Need to compile this information
    // from the specified human options and number of requested AIs

    // Human player setup data
    PlayerSetupData human_player_setup_data;
    human_player_setup_data.player_name = GetOptionsDB().Get<std::string>("setup.player.name");
    human_player_setup_data.empire_name = GetOptionsDB().Get<std::string>("setup.empire.name");

    // DB stores index into array of available colours, so need to get that array to look up value of index.
    // if stored value is invalid, use a default colour
    const std::vector<EmpireColor>& empire_colours = EmpireColors();
    int colour_index = GetOptionsDB().Get<int>("setup.empire.color.index");
    if (colour_index >= 0 && colour_index < static_cast<int>(empire_colours.size()))
        human_player_setup_data.empire_color = empire_colours[colour_index];
    else
        human_player_setup_data.empire_color = {0, 255, 0, 0};

    human_player_setup_data.starting_species_name = GetOptionsDB().Get<std::string>("setup.initial.species");
    if (human_player_setup_data.starting_species_name == "1")
        human_player_setup_data.starting_species_name = "SP_HUMAN";   // kludge / bug workaround for bug with options storage and retreival.  Empty-string options are stored, but read in as "true" boolean, and converted to string equal to "1"

    if (human_player_setup_data.starting_species_name != "RANDOM" &&
        !m_species_manager.GetSpecies(human_player_setup_data.starting_species_name))
    {
        if (m_species_manager.NumPlayableSpecies() < 1) {
            human_player_setup_data.starting_species_name.clear();
        } else {
            auto playable_rng = m_species_manager.AllSpecies() | range_filter(SpeciesManager::is_playable);
            human_player_setup_data.starting_species_name = playable_rng.front().first;
        }
    }

    human_player_setup_data.save_game_empire_id = ALL_EMPIRES; // not used for new games
    human_player_setup_data.client_type = Networking::ClientType::CLIENT_TYPE_HUMAN_PLAYER;

    // add to setup data players
    setup_data.players.push_back(human_player_setup_data);

    // AI player setup data.  One entry for each requested AI
    int num_AIs = GetOptionsDB().Get<int>("setup.ai.player.count");
    for (int ai_i = 1; ai_i <= num_AIs; ++ai_i) {
        PlayerSetupData ai_setup_data;

        ai_setup_data.player_name = "AI_" + std::to_string(ai_i);
        ai_setup_data.empire_name.clear();                // leave blank, to be set by server in Universe::GenerateEmpires
        ai_setup_data.starting_species_name.clear();      // leave blank, to be set by server
        ai_setup_data.save_game_empire_id = ALL_EMPIRES;  // not used for new games
        ai_setup_data.client_type = Networking::ClientType::CLIENT_TYPE_AI_PLAYER;

        setup_data.players.push_back(ai_setup_data);
    }


    DebugLogger() << "Sending host SP setup message";
    m_networking->SendMessage(HostSPGameMessage(setup_data, DependencyVersions()));
    DebugLogger() << "GodotClientApp::NewSinglePlayerGame done";
}

int  GodotClientApp::AutoTurnsLeft() const
{ return m_auto_turns; }

bool GodotClientApp::LoadSinglePlayerGame(const std::string& filename) {
    DebugLogger() << "GodotClientApp::LoadSinglePlayerGame " << filename;
    ClearPreviousPendingSaves(m_game_saves_in_progress);

    m_single_player_game = true;
    try {
        StartServer();
    } catch (const std::runtime_error& err) {
        ErrorLogger() << "GodotClientApp::LoadSinglePlayerGame : Couldn't start server: " << err.what();
        return false;
    }

    if (!m_networking->ConnectToLocalHostServer()) {
        ErrorLogger() << "GodotClientApp::LoadSinglePlayerGame : couldn't connect to the local server";
        return false;
    }

    SinglePlayerSetupData setup_data;
    setup_data.new_game = false;
    setup_data.filename = filename;
    // players are not specified when loading: the server takes them from the save
    m_networking->SendMessage(HostSPGameMessage(setup_data, DependencyVersions()));
    return true;
}

bool GodotClientApp::SaveGame(const std::string& filename) {
    if (!m_networking->IsConnected() || CurrentTurn() == INVALID_GAME_TURN)
        return false;
    m_game_saves_in_progress.push(filename);
    // Only one save at a time; the next goes out when this one completes.
    if (m_game_saves_in_progress.size() == 1)
        m_networking->SendMessage(HostSaveGameInitiateMessage(filename));
    return true;
}

void GodotClientApp::SaveGameCompleted() {
    if (!m_game_saves_in_progress.empty())
        m_game_saves_in_progress.pop();
    if (!m_game_saves_in_progress.empty())
        m_networking->SendMessage(HostSaveGameInitiateMessage(m_game_saves_in_progress.front()));
}

namespace {
    // Keep the newest \a limit - 1 saves in \a dir, making room for one more.
    void RemoveOldestSaves(int limit, const std::filesystem::path& dir) {
        try {
            if (!std::filesystem::is_directory(dir))
                return;
            std::multimap<std::filesystem::file_time_type, std::filesystem::path> by_time;
            for (const auto& entry : std::filesystem::directory_iterator(dir)) {
                std::error_code ec;
                if (entry.is_regular_file(ec) && entry.path().extension() == SP_SAVE_FILE_EXTENSION)
                    by_time.emplace(entry.last_write_time(), entry.path());
            }
            auto excess = static_cast<int>(by_time.size()) - limit + 1;
            for (auto it = by_time.begin(); excess > 0 && it != by_time.end(); ++it, --excess)
                std::filesystem::remove(it->second);
        } catch (const std::exception& e) {
            ErrorLogger() << "RemoveOldestSaves: " << e.what();
        }
    }

    // "FreeOrion_<player>_<empire>_<turn>_<time>.sav", as the GG client names them.
    std::string AutosaveName(const Empire* empire, int turn) {
        const auto filtered = [](std::string text) {
            static constexpr std::string_view legal =
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890_-";
            const auto first = text.find_first_of(legal);
            if (first == std::string::npos)
                return std::string{};
            const auto last = text.find_first_not_of(legal, first);
            return text.substr(first, last == std::string::npos ? std::string::npos : last - first);
        };
        const auto player = filtered(empire ? empire->PlayerName() : std::string{});
        const auto empire_name = filtered(empire ? empire->Name() : UserString("OBSERVER"));
        return boost::io::str(boost::format("FreeOrion_%s_%s_%04d_%s%s") % player % empire_name % turn %
                              FilenameTimestamp() % SP_SAVE_FILE_EXTENSION);
    }
}

void GodotClientApp::Autosave(AutosaveMoment moment) {
    if (!m_single_player_game || !m_networking->IsConnected() || CurrentTurn() == INVALID_GAME_TURN)
        return;
    auto& db = GetOptionsDB();
    const int interval = db.Get<int>("save.auto.turn.interval");
    const bool every_turn = interval > 0 && CurrentTurn() % interval == 0;
    bool wanted = false;
    switch (moment) {
    case AutosaveMoment::TURN_START:
        wanted = (every_turn && db.Get<bool>("save.auto.turn.start.enabled")) ||
            (CurrentTurn() == 1 && db.Get<bool>("save.auto.initial.enabled"));
        break;
    case AutosaveMoment::TURN_END:
        wanted = every_turn && db.Get<bool>("save.auto.turn.end.enabled");
        break;
    case AutosaveMoment::EXIT:
        wanted = db.Get<bool>("save.auto.exit.enabled");
        break;
    }
    if (!wanted)
        return;

    const auto dir = GetSaveDir() / "auto";
    try {
        std::filesystem::create_directories(dir);
    } catch (const std::exception& e) {
        ErrorLogger() << "GodotClientApp::Autosave: can't create " << PathToString(dir) << ": " << e.what();
        return;
    }
    // Room for the kept turns (two saves a turn when saving at start and end),
    // plus the first-turn and exit saves.
    const bool twice_a_turn = db.Get<bool>("save.auto.turn.start.enabled") && db.Get<bool>("save.auto.turn.end.enabled");
    const int limit = std::max(1, db.Get<int>("save.auto.file.limit")) * (twice_a_turn ? 2 : 1) +
        (db.Get<bool>("save.auto.initial.enabled") ? 1 : 0) + (db.Get<bool>("save.auto.exit.enabled") ? 1 : 0);
    RemoveOldestSaves(limit, dir);
    const auto path = PathToString(dir / AutosaveName(m_empires.GetEmpire(EmpireID()).get(), CurrentTurn()));
    DebugLogger() << "GodotClientApp::Autosave to " << path;
    SaveGame(path);
}

void GodotClientApp::RequestCombatLogs() {
    const auto incomplete_ids = GetCombatLogManager().IncompleteLogIDs();
    // At most 50 logs per message, so neither side allocates too much at once.
    static constexpr std::size_t BATCH_SIZE = 50;
    for (std::size_t first = 0; first < incomplete_ids.size(); first += BATCH_SIZE) {
        const auto last = std::min(first + BATCH_SIZE, incomplete_ids.size());
        std::vector<int> batch(incomplete_ids.begin() + first, incomplete_ids.begin() + last);
        DebugLogger() << "Requesting " << batch.size() << " combat logs from the server";
        m_networking->SendMessage(RequestCombatLogsMessage(batch));
    }
}

void GodotClientApp::ResetClientData() {
    m_networking->SetPlayerID(Networking::INVALID_PLAYER_ID);
    m_networking->SetHostPlayerID(Networking::INVALID_PLAYER_ID);
    SetEmpireID(ALL_EMPIRES);
    SetCurrentTurn(INVALID_GAME_TURN);
    m_universe.Clear();
    m_empires.Clear();
    m_orders.Reset();
    m_player_info.clear();
    GetCombatLogManager().Clear();
    ClearPreviousPendingSaves(m_game_saves_in_progress);
}

namespace {
    // As the GG client's QuittingGame state: wait this long for the server to
    // disconnect after asking it to shut down, then terminate it.
    constexpr auto QUITTING_TIMEOUT = std::chrono::seconds(5);
}

void GodotClientApp::StartQuitting() {
    if (m_quitting)
        return;
    DebugLogger() << "GodotClientApp::StartQuitting";
    // The server saves before it handles the shutdown sent after this.
    if (m_game_started)
        Autosave(AutosaveMoment::EXIT);
    m_quitting = true;
    m_game_started = false;
    m_auto_turns = 0;
    m_quit_start = std::chrono::steady_clock::now();
    if (m_networking->IsTxConnected())
        m_networking->SendMessage(ShutdownServerMessage());
}

bool GodotClientApp::UpdateQuitting() {
    if (!m_quitting)
        return true;
    if (m_networking->IsConnected()) {
        if (std::chrono::steady_clock::now() - m_quit_start < QUITTING_TIMEOUT)
            return false;
        WarnLogger() << "GodotClientApp::UpdateQuitting: server didn't disconnect; terminating it";
        m_networking->DisconnectFromServer();
#ifndef FREEORION_ANDROID
        m_server_process.RequestTermination();
#endif
    } else {
        // The server disconnected: it is shutting down in order, let it finish.
        DebugLogger() << "GodotClientApp::UpdateQuitting: server disconnected";
    }
    FreeServer();
    ResetClientData();
    m_quitting = false;
    return true;
}

void GodotClientApp::InitAutoTurns(int auto_turns) {
    m_auto_turns = auto_turns;
    if (!m_game_started || m_auto_turns < 0)
        m_auto_turns = 0;
}

void GodotClientApp::DecAutoTurns(int n)
{ InitAutoTurns(m_auto_turns - n); }

bool GodotClientApp::SinglePlayerGame() const
{ return m_single_player_game; }

void GodotClientApp::SetSinglePlayerGame(bool sp)
{ m_single_player_game = sp; }

void GodotClientApp::StartGame(bool is_new_game)
{ m_game_started = true; }

