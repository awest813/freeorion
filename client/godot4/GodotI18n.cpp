#include "GodotI18n.h"

#include "../../util/i18n.h"

#include <algorithm>
#include <string>

namespace {
    // Stringtable keys are upper-case identifiers, such as "MAP_BTN_PEDIA".
    bool LooksLikeKey(const std::string& text) {
        const auto upper = [](char c) { return c >= 'A' && c <= 'Z'; };
        const auto key_char = [&upper](char c) { return upper(c) || (c >= '0' && c <= '9') || c == '_'; };
        return std::any_of(text.begin(), text.end(), upper) && std::all_of(text.begin(), text.end(), key_char);
    }

    godot::StringName Translate(const godot::StringName& key) {
        const std::string source = godot::String(key).utf8().get_data();
        // Godot also auto-translates text that is already translated or isn't
        // a key at all (names, numbers), e.g. when a control's text is set
        // before it joins a parent that turns auto-translation off. Leave such
        // text as it is (an empty result means "untranslated") rather than
        // logging it as a missing key. Missing keys still show as "ERROR: KEY".
        if (!LooksLikeKey(source) && !UserStringExists(source))
            return {};
        const std::string& text = UserString(source);
        // Stringtables are UTF-8; godot::StringName(const char*) would read Latin-1.
        return godot::StringName(godot::String::utf8(text.data(), static_cast<int>(text.size())));
    }
}

godot::StringName GodotI18n::_get_plural_message(const godot::StringName &p_src_message,
                                                 const godot::StringName &p_src_plural_message,
                                                 int32_t p_n,
                                                 const godot::StringName &p_context) const
{
    return Translate(p_src_message);
}

godot::StringName GodotI18n::_get_message(const godot::StringName &p_src_message, const godot::StringName &p_context) const
{ return Translate(p_src_message); }

void GodotI18n::_bind_methods()
{ }

