#include "FOSaves.h"

#include <algorithm>
#include <filesystem>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include "../GodotClientApp.h"
#include "../../../util/Directories.h"
#include "../../../util/Logger.h"
#include "../../../util/MultiplayerCommon.h"
#include "../../../util/SaveGamePreviewUtils.h"

namespace {
    godot::String ToGodot(std::string_view s)
    { return godot::String::utf8(s.data(), static_cast<int>(s.size())); }

    std::filesystem::path ToPath(const godot::String& s) {
        const std::string utf8 = s.utf8().get_data();
        return std::filesystem::path(std::u8string(utf8.begin(), utf8.end()));
    }

    // Names typed by the player become file names: keep it to safe characters.
    std::string SafeFileName(std::string name) {
        for (auto& c : name) {
            const auto u = static_cast<unsigned char>(c);
            if (u < 0x20 || c == '/' || c == '\\' || c == ':' || c == '*' || c == '?' ||
                c == '"' || c == '<' || c == '>' || c == '|')
            { c = '_'; }
        }
        return name;
    }
}

void FOSaves::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    const auto cls = get_class_static();
    ClassDB::bind_static_method(cls, D_METHOD("get_save_dir"), &FOSaves::get_save_dir);
    ClassDB::bind_static_method(cls, D_METHOD("get_extension"), &FOSaves::get_extension);
    ClassDB::bind_static_method(cls, D_METHOD("list_saves"), &FOSaves::list_saves);
    ClassDB::bind_static_method(cls, D_METHOD("save_game", "name"), &FOSaves::save_game);
    ClassDB::bind_static_method(cls, D_METHOD("load_game", "path"), &FOSaves::load_game);
    ClassDB::bind_static_method(cls, D_METHOD("delete_save", "path"), &FOSaves::delete_save);
}

godot::String FOSaves::get_save_dir()
{ return ToGodot(PathToString(GetSaveDir())); }

godot::String FOSaves::get_extension()
{ return ToGodot(SP_SAVE_FILE_EXTENSION); }

godot::Array FOSaves::list_saves() {
    godot::Array result;
    // Player saves and autosaves (in "auto"), each with the directory it is in.
    std::vector<std::pair<std::filesystem::path, FullPreview>> previews;
    try {
        for (const auto& dir : {GetSaveDir(), GetSaveDir() / "auto"}) {
            if (!std::filesystem::exists(dir))
                continue;
            std::vector<FullPreview> in_dir;
            LoadSaveGamePreviews(dir, SP_SAVE_FILE_EXTENSION, in_dir);
            for (auto& preview : in_dir)
                previews.emplace_back(dir, std::move(preview));
        }
    } catch (const std::exception& e) {
        // An exception must not unwind into Godot, which would abort the process.
        ErrorLogger() << "FOSaves::list_saves: " << e.what();
        return result;
    }
    // Newest first; ISO 8601 times sort as strings.
    std::sort(previews.begin(), previews.end(), [](const auto& a, const auto& b)
              { return a.second.preview.save_time > b.second.preview.save_time; });
    for (const auto& [dir, full] : previews) {
        const auto path = dir / std::filesystem::path(full.filename);
        godot::Dictionary save = PreviewEntry(full, ToGodot(PathToString(path)));
        save["auto"] = dir != GetSaveDir();
        result.push_back(save);
    }
    return result;
}

godot::String FOSaves::save_game(const godot::String& name) {
    auto* app = GodotClientApp::GetApp();
    const std::string file = SafeFileName(name.strip_edges().utf8().get_data());
    if (!app || file.empty())
        return {};
    // A multiplayer game is saved by its host into the server's directory.
    const bool single = app->SinglePlayerGame();
    const auto path = (single ? GetSaveDir() : GetServerSaveDir()) /
        std::filesystem::path(std::u8string(file.begin(), file.end()))
            .concat(single ? SP_SAVE_FILE_EXTENSION : MP_SAVE_FILE_EXTENSION);
    const auto path_string = PathToString(path);
    if (!app->SaveGame(path_string))
        return {};
    return ToGodot(path_string);
}

bool FOSaves::load_game(const godot::String& path) {
    auto* app = GodotClientApp::GetApp();
    const auto file = ToPath(path);
    if (!app || !std::filesystem::exists(file))
        return false;
    try {
        return app->LoadSinglePlayerGame(PathToString(file));
    } catch (const std::exception& e) {
        ErrorLogger() << "FOSaves::load_game: " << e.what();
        return false;
    }
}

bool FOSaves::delete_save(const godot::String& path) {
    try {
        const auto file = std::filesystem::weakly_canonical(ToPath(path));
        const auto dir = std::filesystem::weakly_canonical(GetSaveDir());
        const auto parent = file.parent_path();
        if (file.extension() != SP_SAVE_FILE_EXTENSION ||
            (parent != dir && parent != dir / "auto") || !std::filesystem::is_regular_file(file))
        {
            ErrorLogger() << "FOSaves::delete_save: refusing " << PathToString(file);
            return false;
        }
        return std::filesystem::remove(file);
    } catch (const std::exception& e) {
        ErrorLogger() << "FOSaves::delete_save: " << e.what();
        return false;
    }
}

godot::Dictionary FOSaves::PreviewEntry(const FullPreview& full, const godot::String& path) {
    const auto& p = full.preview;
    godot::Dictionary save;
    save["path"] = path;
    save["file"] = ToGodot(full.filename);
    save["player"] = ToGodot(p.main_player_name);
    save["empire"] = ToGodot(p.main_player_empire_name);
    const auto& c = p.main_player_empire_colour;
    save["color"] = godot::Color::from_rgba8(c[0], c[1], c[2], c[3]);
    save["turn"] = p.current_turn;
    save["time"] = ToGodot(p.save_time);
    save["empires"] = p.number_of_empires;
    save["humans"] = p.number_of_human_players;
    save["version"] = ToGodot(p.freeorion_version);
    // The galaxy, as the GG save list's columns show it.
    const auto& g = full.galaxy;
    save["seed"] = ToGodot(g.seed);
    save["systems"] = g.size;
    save["shape"] = ToGodot(TextForGalaxyShape(g.shape));
    save["age"] = ToGodot(TextForGalaxySetupSetting(g.age));
    save["starlanes"] = ToGodot(TextForGalaxySetupSetting(g.starlane_freq));
    save["planets"] = ToGodot(TextForGalaxySetupSetting(g.planet_density));
    save["specials"] = ToGodot(TextForGalaxySetupSetting(g.specials_freq));
    save["monsters"] = ToGodot(TextForGalaxySetupSetting(g.monster_freq));
    save["natives"] = ToGodot(TextForGalaxySetupSetting(g.native_freq));
    save["ai_aggression"] = ToGodot(TextForAIAggression(g.ai_aggr));
    return save;
}
