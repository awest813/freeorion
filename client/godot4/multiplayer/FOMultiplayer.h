#ifndef _FOMultiplayer_h_
#define _FOMultiplayer_h_

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include "../../../network/Message.h"
#include "../../../util/MultiplayerCommon.h"

/** Static multiplayer API for GDScript, as the GG client's server connect
  * window, lobby, chat and player list use it: host a game on a local
  * server, join one by address, then the lobby (galaxy setup, players, AI
  * players, readiness), chat, passwords, and the players of a running game.
  * FreeOrionNode passes the server's lobby, chat, password and player
  * messages here and emits mp_joined, lobby_changed, chat_received,
  * auth_requested and players_changed. Must be called on the main thread. */
class FOMultiplayer : public godot::Object {
    GDCLASS(FOMultiplayer, Object)
public:
    /** Start a local server and host a game on it as \a player_name. Empty
      * on success, else a stringtable key saying why not. */
    static godot::String host_game(const godot::String& player_name);
    /** Connect to \a address and join as \a player_name, \a client_type
      * "player", "observer" or "moderator". Empty or an error key. */
    static godot::String join_game(const godot::String& address, const godot::String& player_name,
                                   const godot::String& client_type);
    /** Leave the lobby or game: disconnect (and stop a server we host). */
    static void leave();

    static bool is_connected_to_server();
    static int get_player_id();
    static bool is_host();
    /** Whether the server gave this player \a role: "host", "galaxy_setup",
      * "player", "observer" or "moderator". */
    static bool has_role(const godot::String& role);

    /** The lobby as last received: {new_game, any_can_edit, start_locked,
      * start_lock_cause, save_game, in_game, galaxy: {seed, size, shape, age,
      * starlane_freq, planet_density, specials_freq, monster_freq,
      * native_freq, ai_aggression} (enum names as galaxy setup uses them),
      * players: [{player_id, player_name, empire_name, species, color,
      * client_type, ready, team, save_empire_id, authenticated}],
      * save_empires: [{empire_id, empire_name, player_name, color}]}. */
    static godot::Dictionary get_lobby();
    /** Send the lobby with \a changes applied (the layout of get_lobby();
      * keys left out stay as they are). A player with player_id -1 and
      * client_type "ai" adds an AI player. */
    static bool send_lobby(const godot::Dictionary& changes);
    /** Toggle this player's readiness in the lobby. */
    static bool set_ready(bool ready);

    /** Chat to everyone (\a recipients empty) or to player ids. */
    static bool send_chat(const godot::String& text, const godot::PackedInt32Array& recipients);
    /** Chat so far: [{player_name, text, color, time}]. */
    static godot::Array get_chat();
    /** Answer the server's password request. */
    static bool send_password(const godot::String& password);

    /** Players of the running game: [{player_id, name, empire_id,
      * empire_name, color, client_type, host, ready (orders sent this turn)}]. */
    static godot::Array get_players();

    /** Servers answering on the local network (blocks for about two
        seconds): their names or addresses. */
    static godot::PackedStringArray discover_lan_servers();

    /** Whether this player may concede: a multiplayer game whose rules
        allow it. */
    static bool can_concede();
    /** Give up: the server removes this player's empire from the game. */
    static bool concede();

    // For FreeOrionNode.
    static void SetLobby(MultiplayerLobbyData lobby);
    static void AddChat(ChatHistoryEntity entry);
    static void ClearSession();
    /** Hosting or joining, until leave(). */
    static bool InSession();
    static void SetAuthPlayerName(std::string name);

protected:
    static void _bind_methods();
};

#endif
