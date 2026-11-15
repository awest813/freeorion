#include <gdextension_interface.h>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#ifdef FREEORION_ANDROID
# include "../../util/AndroidEnvironment.h"
#endif

#include "FreeOrionNode.h"
#include "GodotI18n.h"
#include "GodotOptionsDB.h"
#include "government/FOGovernment.h"
#include "options/FOOptions.h"
#include "orders/FOOrders.h"
#include "pedia/FOPedia.h"
#include "production/FOProduction.h"
#include "research/FOResearch.h"
#include "saves/FOSaves.h"
#include "views/FOViews.h"

namespace {
    GodotOptionsDB* s_options_db = nullptr;
    FOOptions* s_fo_options = nullptr;
}

void initialize_freeorion_module(godot::ModuleInitializationLevel p_level) {
    if (p_level != godot::MODULE_INITIALIZATION_LEVEL_SCENE)
        return;

    GDREGISTER_CLASS(FreeOrionNode);
    GDREGISTER_CLASS(GodotI18n);
    GDREGISTER_ABSTRACT_CLASS(GodotOptionsDB);

    GDREGISTER_CLASS(FOSystem);
    GDREGISTER_CLASS(FOFleet);
    GDREGISTER_CLASS(FOPlanet);
    GDREGISTER_CLASS(FOShip);
    GDREGISTER_ABSTRACT_CLASS(FOUniverse);
    GDREGISTER_ABSTRACT_CLASS(FOOrders);
    GDREGISTER_ABSTRACT_CLASS(FOGovernment);
    GDREGISTER_ABSTRACT_CLASS(FOPedia);
    GDREGISTER_ABSTRACT_CLASS(FOProduction);
    GDREGISTER_ABSTRACT_CLASS(FOResearch);
    GDREGISTER_ABSTRACT_CLASS(FOSaves);
    GDREGISTER_ABSTRACT_CLASS(FOOptions);

    s_fo_options = memnew(FOOptions);
    godot::Engine::get_singleton()->register_singleton("FOOptions", s_fo_options);

    s_options_db = memnew(GodotOptionsDB);
    godot::Engine::get_singleton()->register_singleton("OptionsDB", s_options_db);
}

void uninitialize_freeorion_module(godot::ModuleInitializationLevel p_level) {
    if (p_level != godot::MODULE_INITIALIZATION_LEVEL_SCENE)
        return;

    if (s_fo_options) {
        if (godot::Engine* engine = godot::Engine::get_singleton())
            engine->unregister_singleton("FOOptions");
        godot::memdelete(s_fo_options);
        s_fo_options = nullptr;
    }

    if (s_options_db) {
        if (godot::Engine* engine = godot::Engine::get_singleton())
            engine->unregister_singleton("OptionsDB");
        godot::memdelete(s_options_db);
        s_options_db = nullptr;
    }
}

extern "C" GDExtensionBool GDE_EXPORT freeorion_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
                                                             const GDExtensionClassLibraryPtr p_library,
                                                             GDExtensionInitialization *r_initialization)
{
    godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

    init_obj.register_initializer(initialize_freeorion_module);
    init_obj.register_terminator(uninitialize_freeorion_module);
    init_obj.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);

    return init_obj.init();
}

#ifdef FREEORION_ANDROID
// Called by org.freeorion.godot.FreeOrionPlugin#setAndroidContext native function
extern "C" JNIEXPORT void JNICALL
Java_org_freeorion_godot_FreeOrionPlugin_setAndroidContext(JNIEnv* env, jclass, jobject context) {
    SetAndroidEnvironment(env, context, true);
}
#endif
