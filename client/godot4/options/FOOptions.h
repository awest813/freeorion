#ifndef _FOOptions_h_
#define _FOOptions_h_

#include <memory>
#include <string>
#include <unordered_map>

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace boost::signals2 { class scoped_connection; }

/** Engine singleton "FOOptions": typed access to the client OptionsDB.
  *
  * Values come back as their real type (bool, int, float or String; other
  * option types as their string form). set_value() validates against the
  * option's validator and returns false instead of throwing. Call watch() to
  * get option_changed(name) whenever that option changes, from GDScript or
  * from C++. Must be used on the main thread.
  *
  * Kept separate from upstream's "OptionsDB" singleton so the two can merge
  * independently. */
class FOOptions : public godot::Object {
    GDCLASS(FOOptions, Object)
public:
    FOOptions();
    ~FOOptions() override;

    bool exists(const godot::String& name) const;
    godot::Variant get_value(const godot::String& name) const;
    godot::Variant get_default(const godot::String& name) const;
    bool is_default(const godot::String& name) const;
    godot::String get_description(const godot::String& name) const;
    godot::PackedStringArray find(const godot::String& prefix) const;

    /** Validates and sets; returns false if the option is unknown or the value invalid. */
    bool set_value(const godot::String& name, const godot::Variant& value);
    bool reset_to_default(const godot::String& name);

    /** Registers an option whose type is taken from \a default_value
      * (bool, int, float or String). Returns false if it already exists. */
    bool add_option(const godot::String& name, const godot::String& description_key,
                    const godot::Variant& default_value);

    /** Emit option_changed(name) whenever option \a name changes. */
    void watch(const godot::String& name);

    /** Save changed options to the config file. */
    bool commit();

    /** Languages with a stringtable: codes such as "en", "de". */
    godot::PackedStringArray get_languages() const;
    /** The language in use ("en", ...). */
    godot::String get_language() const;
    /** Switch the stringtable to language \a code (a get_languages() entry)
      * for everything translated from now on. */
    bool set_language(const godot::String& code);

protected:
    static void _bind_methods();

private:
    std::unordered_map<std::string, std::unique_ptr<boost::signals2::scoped_connection>> m_watches;
};

#endif
