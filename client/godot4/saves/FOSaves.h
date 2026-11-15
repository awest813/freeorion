#ifndef _FOSaves_h_
#define _FOSaves_h_

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

struct FullPreview;

/** Static save/load API for GDScript.
  *
  * list_saves() -> [{path, file, player, empire, color, turn, time,
  *   empires, humans, version}] for single-player saves in the save
  *   directory, newest first.
  * save_game(name) asks the server to save; FreeOrionNode emits
  *   save_completed(filename, bytes) when it is written.
  * load_game(path) starts a local server and loads the save; the game
  *   arrives like a new one, through FreeOrionNode's start_game signal.
  * Main thread only. */
class FOSaves : public godot::Object {
    GDCLASS(FOSaves, Object)
public:
    static godot::String get_save_dir();
    static godot::String get_extension();
    static godot::Array list_saves();
    /** \a name without directory or extension; returns the full path, or ""
      * if no game can be saved now. */
    static godot::String save_game(const godot::String& name);
    static bool load_game(const godot::String& path);

    /** Delete the save at \a path; only files in the save directory (or its
      * autosave directory) with the save extension. */
    static bool delete_save(const godot::String& path);

    /** One save's entry, as list_saves() gives it, at \a path. */
    static godot::Dictionary PreviewEntry(const FullPreview& full, const godot::String& path);

protected:
    static void _bind_methods();
};

#endif
