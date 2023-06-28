#include "meta_init.h"
#include <string>

// use these functions to communicate with the MetaHelper angelscript plugin

// call a metamod function whenever an angelscript hook is triggered
// valid hook types: TakeDamage
void hook_angelscript(std::string hook, std::string cmdname, void (*callback)());

// read a custom keyvalue from an entity
int readCustomKeyvalueInteger(edict_t* ent, std::string keyName);
float readCustomKeyvalueFloat(edict_t* ent, std::string keyName);
std::string readCustomKeyvalueString(edict_t* ent, std::string keyName);
Vector readCustomKeyvalueVector(edict_t* ent, std::string keyName);

void TakeDamage(edict_t* victim, edict_t* inflictor, edict_t* attacker, float damage, int damageType);
void Use(edict_t* target, edict_t* activator, edict_t* caller, int useType);

// sven has a special version of PrecacheSound, but metamod only has access to the engine func.
// This requires the MetaHelper angelscript plugin to be installed.
// Do not call this outside of MapInit/ServerActivate.
// This also includes the PrecacheGeneric call
void PrecacheSound(std::string snd);

// the engine function works, but if you recompile the plugin
// then you'll get a fatal precache error when reloading.
// Using the sven version of PrecacheModel fixes that.
void PrecacheModel(std::string mdl);