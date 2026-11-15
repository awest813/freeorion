#include "FOGameRules.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

#include "../../../universe/EnumsFwd.h"
#include "../../../util/GameRules.h"
#include "../../../util/Logger.h"
#include "../../../util/OptionValidators.h"

namespace {
    godot::String ToGodot(std::string_view s)
    { return godot::String::utf8(s.data(), static_cast<int>(s.size())); }

    std::string_view TypeName(GameRule::Type type) {
        switch (type) {
        case GameRule::Type::TOGGLE: return "toggle";
        case GameRule::Type::INT:    return "int";
        case GameRule::Type::DOUBLE: return "double";
        case GameRule::Type::STRING: return "string";
        default:                     return "";
        }
    }

    godot::Variant Value(const GameRule& rule, const boost::any& value) {
        try {
            switch (rule.type) {
            case GameRule::Type::TOGGLE: return boost::any_cast<bool>(value);
            case GameRule::Type::INT:
                if (value.type() == typeid(Visibility))
                    return static_cast<int>(boost::any_cast<Visibility>(value));
                return boost::any_cast<int>(value);
            case GameRule::Type::DOUBLE: return boost::any_cast<double>(value);
            case GameRule::Type::STRING: return ToGodot(boost::any_cast<std::string>(value));
            default: break;
            }
        } catch (const boost::bad_any_cast&) {}
        return {};
    }

    // Range, step or choices, as the GG rules panel reads them.
    template <typename T>
    void AddLimits(godot::Dictionary& entry, const ValidatorBase* validator) {
        if (const auto* ranged = dynamic_cast<const RangedValidator<T>*>(validator)) {
            entry["min"] = ranged->m_min;
            entry["max"] = ranged->m_max;
        } else if (const auto* ranged_step = dynamic_cast<const RangedStepValidator<T>*>(validator)) {
            entry["min"] = ranged_step->m_min;
            entry["max"] = ranged_step->m_max;
            entry["step"] = ranged_step->m_step_size;
        } else if (const auto* step = dynamic_cast<const StepValidator<T>*>(validator)) {
            entry["step"] = step->m_step_size;
        }
    }
}

void FOGameRules::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    const auto cls = get_class_static();
    ClassDB::bind_static_method(cls, D_METHOD("list_rules"), &FOGameRules::list_rules);
    ClassDB::bind_static_method(cls, D_METHOD("set_rules", "values"), &FOGameRules::set_rules);
}

godot::Array FOGameRules::list_rules() {
    godot::Array result;
    try {
        for (const auto* rule : GetGameRules().GetSortedByCategoryAndRank()) {
            if (!rule)
                continue;
            godot::Dictionary entry;
            entry["name"] = ToGodot(rule->name);
            entry["category"] = ToGodot(rule->category);
            entry["type"] = ToGodot(TypeName(rule->type));
            entry["value"] = Value(*rule, rule->value);
            entry["default"] = Value(*rule, rule->default_value);
            entry["description"] = ToGodot(rule->description);
            const auto* validator = rule->validator.get();
            if (rule->type == GameRule::Type::INT) {
                AddLimits<int>(entry, validator);
                if (const auto* vis = dynamic_cast<const RangedValidator<Visibility>*>(validator)) {
                    entry["min"] = static_cast<int>(vis->m_min);
                    entry["max"] = static_cast<int>(vis->m_max);
                }
            } else if (rule->type == GameRule::Type::DOUBLE) {
                AddLimits<double>(entry, validator);
            } else if (rule->type == GameRule::Type::STRING) {
                if (const auto* discrete = dynamic_cast<const DiscreteValidator<std::string>*>(validator)) {
                    godot::PackedStringArray choices;
                    for (const auto& value : discrete->m_values)
                        choices.push_back(ToGodot(value));
                    entry["choices"] = choices;
                }
            }
            result.push_back(entry);
        }
    } catch (const std::exception& e) {
        ErrorLogger() << "FOGameRules::list_rules: " << e.what();
    }
    return result;
}

bool FOGameRules::set_rules(const godot::Dictionary& values) {
    try {
        auto& rules = GetGameRules();
        std::map<std::string, std::string> as_strings;
        const auto keys = values.keys();
        for (int64_t i = 0; i < keys.size(); ++i) {
            const std::string name = godot::String(keys[i]).utf8().get_data();
            if (!rules.RuleExists(name))
                return false;
            const godot::Variant& value = values[keys[i]];
            std::string text;
            if (value.get_type() == godot::Variant::BOOL)
                text = bool(value) ? "1" : "0";
            else
                text = godot::String(value).utf8().get_data();
            // Throws if the validator refuses it.
            if (const auto* validator = rules.GetValidator(name))
                validator->Validate(text);
            as_strings.emplace(name, std::move(text));
        }
        rules.SetFromStrings(as_strings);
        return true;
    } catch (const std::exception& e) {
        InfoLogger() << "FOGameRules::set_rules refused: " << e.what();
    }
    return false;
}
