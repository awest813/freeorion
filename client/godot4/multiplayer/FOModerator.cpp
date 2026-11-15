#include "FOModerator.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

#include "../GodotClientApp.h"
#include "../../ClientNetworking.h"
#include "../../../network/Message.h"
#include "../../../network/Networking.h"
#include "../../../universe/Planet.h"
#include "../../../universe/System.h"
#include "../../../util/Logger.h"
#include "../../../util/ModeratorAction.h"

namespace {
    // Send \a action if this client is a moderator in a connected game.
    bool Send(const Moderator::ModeratorAction& action) {
        auto* app = GodotClientApp::GetApp();
        if (!app || !Networking::is_mod(*app) || !app->Networking().IsTxConnected())
            return false;
        try {
            app->Networking().SendMessage(ModeratorActionMessage(action));
            return true;
        } catch (const std::exception& e) {
            ErrorLogger() << "FOModerator: " << e.what();
        }
        return false;
    }

    template <typename Enum>
    godot::PackedStringArray Names(Enum first, Enum end) {
        godot::PackedStringArray names;
        for (auto value = first; value != end; value = Enum(static_cast<int>(value) + 1)) {
            const auto name = to_string(value);
            names.push_back(godot::String::utf8(name.data(), static_cast<int>(name.size())));
        }
        return names;
    }

    template <typename Enum>
    Enum Parse(const godot::String& text, Enum first, Enum end, Enum fallback) {
        for (auto value = first; value != end; value = Enum(static_cast<int>(value) + 1))
            if (text == godot::String(std::string{to_string(value)}.c_str()))
                return value;
        return fallback;
    }
}

void FOModerator::_bind_methods() {
    using godot::ClassDB, godot::D_METHOD;
    const auto cls = get_class_static();
    ClassDB::bind_static_method(cls, D_METHOD("get_role"), &FOModerator::get_role);
    ClassDB::bind_static_method(cls, D_METHOD("get_choices"), &FOModerator::get_choices);
    ClassDB::bind_static_method(cls, D_METHOD("destroy", "object_id"), &FOModerator::destroy);
    ClassDB::bind_static_method(cls, D_METHOD("set_owner", "object_id", "empire_id"), &FOModerator::set_owner);
    ClassDB::bind_static_method(cls, D_METHOD("add_starlane", "system_a", "system_b"), &FOModerator::add_starlane);
    ClassDB::bind_static_method(cls, D_METHOD("remove_starlane", "system_a", "system_b"), &FOModerator::remove_starlane);
    ClassDB::bind_static_method(cls, D_METHOD("create_system", "x", "y", "star_type"), &FOModerator::create_system);
    ClassDB::bind_static_method(cls, D_METHOD("create_planet", "system_id", "planet_type", "planet_size"),
                                &FOModerator::create_planet);
}

godot::String FOModerator::get_role() {
    const auto* app = GodotClientApp::GetApp();
    if (!app || app->CurrentTurn() == INVALID_GAME_TURN)
        return {};
    if (Networking::is_mod(*app))
        return "moderator";
    if (Networking::is_obs(*app))
        return "observer";
    return "player";
}

godot::Dictionary FOModerator::get_choices() {
    godot::Dictionary choices;
    choices["star_types"] = Names(StarType::STAR_BLUE, StarType::NUM_STAR_TYPES);
    choices["planet_types"] = Names(PlanetType::PT_SWAMP, PlanetType::NUM_PLANET_TYPES);
    choices["planet_sizes"] = Names(PlanetSize::SZ_TINY, PlanetSize::NUM_PLANET_SIZES);
    return choices;
}

bool FOModerator::destroy(int object_id)
{ return Send(Moderator::DestroyUniverseObject(object_id)); }

bool FOModerator::set_owner(int object_id, int empire_id)
{ return Send(Moderator::SetOwner(object_id, empire_id)); }

bool FOModerator::add_starlane(int system_a, int system_b)
{ return system_a != system_b && Send(Moderator::AddStarlane(system_a, system_b)); }

bool FOModerator::remove_starlane(int system_a, int system_b)
{ return system_a != system_b && Send(Moderator::RemoveStarlane(system_a, system_b)); }

bool FOModerator::create_system(double x, double y, const godot::String& star_type) {
    const auto type = Parse(star_type, StarType::STAR_BLUE, StarType::NUM_STAR_TYPES, StarType::STAR_YELLOW);
    return Send(Moderator::CreateSystem(x, y, type));
}

bool FOModerator::create_planet(int system_id, const godot::String& planet_type, const godot::String& planet_size) {
    const auto type = Parse(planet_type, PlanetType::PT_SWAMP, PlanetType::NUM_PLANET_TYPES, PlanetType::PT_BARREN);
    const auto size = Parse(planet_size, PlanetSize::SZ_TINY, PlanetSize::NUM_PLANET_SIZES, PlanetSize::SZ_MEDIUM);
    return Send(Moderator::CreatePlanet(system_id, type, size));
}
