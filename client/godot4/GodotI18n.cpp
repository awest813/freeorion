#include "GodotI18n.h"

#include "../../util/i18n.h"

namespace {
    // Stringtables are UTF-8; godot::StringName(const char*) would read Latin-1.
    godot::StringName Translate(const godot::StringName& key) {
        const std::string& text = UserString(godot::String(key).utf8().get_data());
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

