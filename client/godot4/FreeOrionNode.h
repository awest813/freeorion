#ifndef _FreeOrionNode_h_
#define _FreeOrionNode_h_

#include <atomic>
#include <memory>
#include <optional>

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/thread.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

#include "../../util/MultiplayerCommon.h"

class GodotClientApp;
class Message;

class FreeOrionNode : public godot::Node {
    GDCLASS(FreeOrionNode, Node)
public:
    FreeOrionNode();
    ~FreeOrionNode();

    void _ready() override;
    void _process(double delta) override;
    void _exit_tree() override;
protected:
    static void _bind_methods();
private:
    godot::String get_version() const; ///< Returns FreeOrion version

    godot::String get_user_data_dir() const; ///< Returns user data dir

    godot::String get_user_config_dir() const; ///< Returns user config dir
    godot::String get_resource_dir() const; ///< Content directory (scripting, stringtables, credits.xml)

    int get_current_turn() const; ///< Returns the current turn number, or INVALID_GAME_TURN if no game is running

    bool get_single_player_game() const; ///< Returns true if this game is a single-player game

    void parsing_thread(); ///< Function called in a separate parsing thread

    /** Starts dispatching incoming server messages, should be called after initialization.
      * Messages are dispatched on the main thread from _process(), so Universe, Empires
      * and other client state are only ever modified on the main thread. The name is kept
      * for compatibility with existing scripts. */
    void start_network_thread();

    void start_parsing_thread(); ///< Starts separate parsing thread, should be called after initialization

    godot::String new_single_player_game(); ///< Starts new single player game

    void emit_start_game(bool is_new_game);
    void start_turn(); ///< Starts new turn, sending the view set by set_view() along

    /** The map view to save with the game (world centre and zoom), sent with
      * each turn's orders as the GG client sends its map position. */
    void set_view(godot::Vector2 center, double zoom);

    /** The view saved with a loaded game: {center, zoom}, or {} for a new
      * game. */
    godot::Dictionary get_saved_view() const;

    /** Leaves the game: shuts the local server down and clears the game data
      * over the next frames, then emits game_ended. */
    void quit_game();

    /** Takes back an ended turn while the server still waits for players, so
      * orders can be changed (the GG client's "Revise" button). */
    void revise_turn();

    bool is_quitting() const; ///< True while quit_game() is in progress

    bool options_get_bool(godot::String option) const;

    godot::String options_get_string(godot::String option) const;

    godot::PackedStringArray options_find_options(godot::String prefix, bool allow_unrecognized = false) const;

    bool options_exists(godot::String option) const;

    void options_add_string(godot::String option, godot::String description, godot::String value);

    void options_set_string(godot::String option, godot::String value);

    bool options_commit(bool only_if_dirty = true, bool only_non_default = true);

    void HandleMessage(Message&&); ///< Processes message on the main thread

    void InitTurnState(); ///< System graph and resource pools for a new turn

    /** Leaves the game because of \a message (server lost, game ended by the
      * server): starts quitting and emits game_aborted. */
    void AbortGame(const std::string& message);

    std::unique_ptr<GodotClientApp> m_app;
    std::atomic<bool> m_parsing_done = false; ///< content parsed, so checksums can be compared
    SaveGameUIData m_ui_data;              ///< sent with each turn's orders
    std::optional<SaveGameUIData> m_loaded_ui_data; ///< from the loaded save, if any
    godot::Ref<godot::Thread> m_parsing_thread;
};

#endif
