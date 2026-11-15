#include "FOOptions.h"

#include <filesystem>

#include <boost/signals2/connection.hpp>
#include <godot_cpp/core/class_db.hpp>

#include "../../../util/Directories.h"
#include "../../../util/Logger.h"
#include "../../../util/i18n.h"
#include "../../../util/OptionsDB.h"
#include "../../../util/XMLDoc.h"

namespace {
    std::string ToStd(const godot::String& s)
    { return s.utf8().get_data(); }

    godot::String ToGodot(std::string_view s)
    { return godot::String::utf8(s.data(), static_cast<int>(s.size())); }

    enum class OptionType { Missing, Bool, Int, Double, Float, String, Path, Other };

    OptionType TypeOf(std::string_view name) {
        const auto& db = GetOptionsDB();
        if (!db.OptionExists(name))
            return OptionType::Missing;
        if (db.OptionExistsAndHasTypedValue<bool>(name))
            return OptionType::Bool;
        if (db.OptionExistsAndHasTypedValue<int>(name))
            return OptionType::Int;
        if (db.OptionExistsAndHasTypedValue<double>(name))
            return OptionType::Double;
        if (db.OptionExistsAndHasTypedValue<float>(name))
            return OptionType::Float;
        if (db.OptionExistsAndHasTypedValue<std::string>(name))
            return OptionType::String;
        if (db.OptionExistsAndHasTypedValue<std::filesystem::path>(name))
            return OptionType::Path;
        return OptionType::Other;
    }

    godot::Variant Read(std::string_view name, bool default_value) {
        const auto& db = GetOptionsDB();
        try {
            switch (TypeOf(name)) {
            case OptionType::Missing: return {};
            case OptionType::Bool:    return default_value ? db.GetDefault<bool>(name) : db.Get<bool>(name);
            case OptionType::Int:     return default_value ? db.GetDefault<int>(name) : db.Get<int>(name);
            case OptionType::Double:  return default_value ? db.GetDefault<double>(name) : db.Get<double>(name);
            case OptionType::Float:   return default_value ? db.GetDefault<float>(name) : db.Get<float>(name);
            case OptionType::String:
                return ToGodot(default_value ? db.GetDefault<std::string>(name) : db.Get<std::string>(name));
            case OptionType::Path:
                return ToGodot(PathToString(default_value ? db.GetDefault<std::filesystem::path>(name)
                                                          : db.Get<std::filesystem::path>(name)));
            case OptionType::Other:
                return ToGodot(default_value ? db.GetDefaultValueString(name) : db.GetValueString(name));
            }
        } catch (const std::exception& e) {
            ErrorLogger() << "FOOptions: reading option " << name << " failed: " << e.what();
        }
        return {};
    }
}

namespace {
    // Options of other types (enums such as setup.galaxy.shape) take their
    // value as a string. OptionsDB only parses strings privately, so go
    // through SetFromXML, which validates and fires the change signals.
    bool SetFromString(const std::string& option, const std::string& value) {
        auto& db = GetOptionsDB();
        db.Validate(option, value); // throws if not allowed
        XMLDoc doc;
        XMLElement* parent = &doc.root_node;
        std::string_view rest{option};
        while (true) {
            const auto dot = rest.find('.');
            const bool last = dot == std::string_view::npos;
            XMLElement element{std::string{last ? rest : rest.substr(0, dot)}, last ? value : std::string{}};
            parent->AddChild(std::move(element));
            if (last)
                break;
            parent = &parent->Child(std::string{rest.substr(0, dot)});
            rest.remove_prefix(dot + 1);
        }
        db.SetFromXML(doc);
        return db.GetValueString(option) == value;
    }
}

FOOptions::FOOptions() = default;

FOOptions::~FOOptions() = default;

void FOOptions::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    ClassDB::bind_method(D_METHOD("exists", "name"), &FOOptions::exists);
    ClassDB::bind_method(D_METHOD("get_value", "name"), &FOOptions::get_value);
    ClassDB::bind_method(D_METHOD("get_default", "name"), &FOOptions::get_default);
    ClassDB::bind_method(D_METHOD("is_default", "name"), &FOOptions::is_default);
    ClassDB::bind_method(D_METHOD("get_description", "name"), &FOOptions::get_description);
    ClassDB::bind_method(D_METHOD("find", "prefix"), &FOOptions::find);
    ClassDB::bind_method(D_METHOD("set_value", "name", "value"), &FOOptions::set_value);
    ClassDB::bind_method(D_METHOD("reset_to_default", "name"), &FOOptions::reset_to_default);
    ClassDB::bind_method(D_METHOD("add_option", "name", "description_key", "default_value"),
                         &FOOptions::add_option);
    ClassDB::bind_method(D_METHOD("watch", "name"), &FOOptions::watch);
    ClassDB::bind_method(D_METHOD("commit"), &FOOptions::commit);
    ClassDB::bind_method(D_METHOD("get_languages"), &FOOptions::get_languages);
    ClassDB::bind_method(D_METHOD("get_language"), &FOOptions::get_language);
    ClassDB::bind_method(D_METHOD("set_language", "code"), &FOOptions::set_language);

    ADD_SIGNAL(godot::MethodInfo("option_changed", godot::PropertyInfo(godot::Variant::STRING, "name")));
}

bool FOOptions::exists(const godot::String& name) const
{ return GetOptionsDB().OptionExists(ToStd(name)); }

godot::Variant FOOptions::get_value(const godot::String& name) const
{ return Read(ToStd(name), false); }

godot::Variant FOOptions::get_default(const godot::String& name) const
{ return Read(ToStd(name), true); }

bool FOOptions::is_default(const godot::String& name) const {
    const auto option = ToStd(name);
    return GetOptionsDB().OptionExists(option) && GetOptionsDB().IsDefaultValue(option);
}

godot::String FOOptions::get_description(const godot::String& name) const {
    const auto option = ToStd(name);
    return GetOptionsDB().OptionExists(option) ? ToGodot(GetOptionsDB().GetDescription(option)) : godot::String();
}

godot::PackedStringArray FOOptions::find(const godot::String& prefix) const {
    godot::PackedStringArray names;
    for (const auto& option : GetOptionsDB().FindOptions(ToStd(prefix)))
        names.push_back(ToGodot(option));
    return names;
}

bool FOOptions::set_value(const godot::String& name, const godot::Variant& value) {
    const auto option = ToStd(name);
    auto& db = GetOptionsDB();
    try {
        switch (TypeOf(option)) {
        case OptionType::Missing:
            ErrorLogger() << "FOOptions::set_value: unknown option " << option;
            return false;
        case OptionType::Other:
            return SetFromString(option, ToStd(godot::String(value)));
        case OptionType::Bool:
            db.Set<bool>(option, static_cast<bool>(value));
            return true;
        case OptionType::Int: {
            const int v = static_cast<int>(static_cast<int64_t>(value));
            db.Validate(option, std::to_string(v));
            db.Set<int>(option, int{v});
            return true;
        }
        case OptionType::Double: {
            const double v = static_cast<double>(value);
            db.Validate(option, std::to_string(v));
            db.Set<double>(option, double{v});
            return true;
        }
        case OptionType::Float: {
            const float v = static_cast<float>(static_cast<double>(value));
            db.Validate(option, std::to_string(v));
            db.Set<float>(option, float{v});
            return true;
        }
        case OptionType::String: {
            auto v = ToStd(godot::String(value));
            db.Validate(option, v);
            db.Set<std::string>(option, std::move(v));
            return true;
        }
        case OptionType::Path: {
            const auto v = ToStd(godot::String(value));
            db.Validate(option, v);
            db.Set<std::filesystem::path>(option, std::filesystem::path(std::u8string(v.begin(), v.end())));
            return true;
        }
        }
    } catch (const std::exception& e) {
        DebugLogger() << "FOOptions::set_value: rejected value for " << option << ": " << e.what();
    }
    return false;
}

bool FOOptions::reset_to_default(const godot::String& name) {
    const auto option = ToStd(name);
    if (!GetOptionsDB().OptionExists(option))
        return false;
    GetOptionsDB().SetToDefault(option);
    return true;
}

bool FOOptions::add_option(const godot::String& name, const godot::String& description_key,
                           const godot::Variant& default_value)
{
    auto option = ToStd(name);
    auto& db = GetOptionsDB();
    if (db.OptionExists(option))
        return false;
    auto description = ToStd(description_key);
    try {
        switch (default_value.get_type()) {
        case godot::Variant::BOOL:
            db.Add<bool>(std::move(option), std::move(description), static_cast<bool>(default_value));
            return true;
        case godot::Variant::INT:
            db.Add<int>(std::move(option), std::move(description), static_cast<int>(static_cast<int64_t>(default_value)));
            return true;
        case godot::Variant::FLOAT:
            db.Add<double>(std::move(option), std::move(description), static_cast<double>(default_value));
            return true;
        case godot::Variant::STRING:
        case godot::Variant::STRING_NAME:
            db.Add<std::string>(std::move(option), std::move(description), ToStd(godot::String(default_value)));
            return true;
        default:
            ErrorLogger() << "FOOptions::add_option: unsupported default value type for " << option;
            return false;
        }
    } catch (const std::exception& e) {
        ErrorLogger() << "FOOptions::add_option: adding " << option << " failed: " << e.what();
    }
    return false;
}

void FOOptions::watch(const godot::String& name) {
    auto option = ToStd(name);
    if (m_watches.contains(option) || !GetOptionsDB().OptionExists(option))
        return;
    auto connection = GetOptionsDB().OptionChangedSignal(option).connect(
        // deferred: options may change on another thread (e.g. while parsing)
        [this, name]() { call_deferred("emit_signal", "option_changed", name); });
    m_watches.emplace(std::move(option), std::make_unique<boost::signals2::scoped_connection>(std::move(connection)));
}

bool FOOptions::commit()
{ return GetOptionsDB().Commit(); }

namespace {
    // Stringtables are <resources>/stringtables/<code>.txt, e.g. de.txt.
    std::filesystem::path StringtableDir() { return GetResourceDir() / "stringtables"; }

    bool IsLanguageCode(const std::string& stem)
    { return stem.size() >= 2 && stem.size() <= 5 && std::all_of(stem.begin(), stem.end(), ::islower); }
}

godot::PackedStringArray FOOptions::get_languages() const {
    std::vector<std::string> codes;
    std::error_code ec;
    for (const auto& entry : std::filesystem::directory_iterator(StringtableDir(), ec)) {
        if (entry.path().extension() == ".txt" && IsLanguageCode(entry.path().stem().string()))
            codes.push_back(entry.path().stem().string());
    }
    std::sort(codes.begin(), codes.end());
    godot::PackedStringArray result;
    for (const auto& code : codes)
        result.push_back(godot::String::utf8(code.c_str()));
    return result;
}

godot::String FOOptions::get_language() const {
    // The code of the stringtable in use ("en", "de", ...): its file's stem.
    try {
        const auto path = GetOptionsDB().Get<std::filesystem::path>("resource.stringtable.path");
        const auto stem = path.stem().string();
        if (IsLanguageCode(stem))
            return godot::String::utf8(stem.c_str());
    } catch (const std::exception& e) {
        ErrorLogger() << "FOOptions::get_language: " << e.what();
    }
    return "en";
}

bool FOOptions::set_language(const godot::String& code) {
    const std::string stem = code.utf8().get_data();
    const auto path = StringtableDir() / (stem + ".txt");
    if (!IsLanguageCode(stem) || !std::filesystem::exists(path))
        return false;
    try {
        // The option holds a path; GodotI18n reads through UserString(), so
        // flushing the tables is all Godot's translation needs.
        GetOptionsDB().Set<std::filesystem::path>("resource.stringtable.path", std::filesystem::path{path});
        FlushLoadedStringTables();
        return true;
    } catch (const std::exception& e) {
        ErrorLogger() << "FOOptions::set_language: " << e.what();
    }
    return false;
}
