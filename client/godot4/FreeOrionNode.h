#ifndef _FreeOrionNode_h_
#define _FreeOrionNode_h_

#include <memory>

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/thread.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

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

    int get_current_turn() const; ///< Returns the current turn number, or INVALID_GAME_TURN if no game is running

    bool get_single_player_game() const; ///< Returns true if this game is a single-player game

    void parsing_thread(); ///< Function called in a separate parsing thread

    /** Starts dispatching incoming server messages, should be called after initialization.
      * Messages are dispatched on the main thread from _process(), so Universe, Empires
      * and other client state are only ever modified on the main thread. The name is kept
      * for compatibility with existing scripts. */
    void start_network_thread();

    void start_parsing_thread(); ///< Starts separate parsing thread, should be called after initialization

    void new_single_player_game(); ///< Starts new single player game

    void start_turn(); ///< Starts new turn

    /** Leaves the game: shuts the local server down and clears the game data
      * over the next frames, then emits game_ended. */
    void quit_game();

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

    std::unique_ptr<GodotClientApp> m_app;
    godot::Ref<godot::Thread> m_parsing_thread;
};

#endif
