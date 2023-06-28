#include "meta_helper.h"
#include "misc_utils.h"

using namespace std;

void hook_angelscript(string hook, string cmdname, void (*callback)()) {
	REG_SVR_COMMAND((char*)cmdname.c_str(), callback);
	g_engfuncs.pfnServerCommand((char*)("as_command .RegisterHook \"" + hook + "\" \"" + cmdname + "\";").c_str());
	g_engfuncs.pfnServerExecute();
}

int readCustomKeyvalueInteger(edict_t* ent, string keyName) {
	int oldVal = ent->v.iuser4;

	g_engfuncs.pfnServerCommand((char*)("as_command .CustomKeyRead " + to_string(ENTINDEX(ent)) + " " + keyName + " 0;").c_str());
	g_engfuncs.pfnServerExecute();
	int retVal = ent->v.iuser4;

	ent->v.iuser4 = oldVal;

	return retVal;
}

float readCustomKeyvalueFloat(edict_t* ent, string keyName) {
	float oldVal = ent->v.fuser4;

	g_engfuncs.pfnServerCommand((char*)("as_command .CustomKeyRead " + to_string(ENTINDEX(ent)) + " " + keyName + " 1;").c_str());
	g_engfuncs.pfnServerExecute();
	float retVal = ent->v.fuser4;

	ent->v.iuser4 = oldVal;

	return retVal;
}

string readCustomKeyvalueString(edict_t* ent, string keyName) {
	string_t oldVal = ent->v.noise3;

	g_engfuncs.pfnServerCommand((char*)("as_command .CustomKeyRead " + to_string(ENTINDEX(ent)) + " " + keyName + " 2;").c_str());
	g_engfuncs.pfnServerExecute();
	string retVal = STRING(ent->v.noise3);

	ent->v.noise3 = oldVal;

	return retVal;
}

Vector readCustomKeyvalueVector(edict_t* ent, string keyName) {
	Vector oldVal = ent->v.vuser4;

	g_engfuncs.pfnServerCommand((char*)("as_command .CustomKeyRead " + to_string(ENTINDEX(ent)) + " " + keyName + " 3;").c_str());
	g_engfuncs.pfnServerExecute();
	Vector retVal = ent->v.vuser4;

	ent->v.vuser4 = oldVal;

	return retVal;
}

void TakeDamage(edict_t* victim, edict_t* inflictor, edict_t* attacker, float damage, int damageType) {
	string s_victim = to_string(ENTINDEX(victim));
	string s_inflictor = to_string(ENTINDEX(inflictor));
	string s_attacker = to_string(ENTINDEX(attacker));
	string s_damage = to_string(damage);
	string s_damageType = to_string(damageType);
	string args = s_victim + " " + s_inflictor + " " + s_attacker + " " + s_damage + " " + s_damageType;
	
	g_engfuncs.pfnServerCommand((char*)("as_command .TakeDamage " + args + ";").c_str());
	g_engfuncs.pfnServerExecute();
}

void Use(edict_t* target, edict_t* activator, edict_t* caller, int useType) {
	string s_target = to_string(ENTINDEX(target));
	string s_activator = to_string(ENTINDEX(activator));
	string s_caller = to_string(ENTINDEX(caller));
	string s_useType = to_string(useType);
	string args = s_target + " " + s_activator + " " + s_caller + " " + s_useType;

	g_engfuncs.pfnServerCommand((char*)("as_command .Use " + args + ";").c_str());
	g_engfuncs.pfnServerExecute();
}

void PrecacheSound(string snd) {
	g_engfuncs.pfnServerCommand((char*)("as_command .PrecacheSound " + snd + ";").c_str());
	g_engfuncs.pfnServerExecute();
}

void PrecacheModel(string mdl) {
	g_engfuncs.pfnServerCommand((char*)("as_command .PrecacheModel " + mdl + ";").c_str());
	g_engfuncs.pfnServerExecute();
}