#pragma once
#include <extdll.h>
#include <string>
#include "main.h"
#include <map>
#include "meta_init.h"

using namespace std;

#define MSG_ChatMsg 74
#define MSG_TextMsg 75

#define println(fmt,...) {ALERT(at_console, (char*)(std::string(fmt) + "\n").c_str(), ##__VA_ARGS__); }

// prevent conflicts with auto-included headers
#define Min(a,b)            (((a) < (b)) ? (a) : (b))
#define Max(a,b)           (((a) > (b)) ? (a) : (b))

string replaceString(string subject, string search, string replace);

edict_t* getPlayerByUniqueId(string id);

string getPlayerUniqueId(edict_t* plr);

bool isValidPlayer(edict_t* plr);

string trimSpaces(string s);

string toLowerCase(string str);

string vecToString(Vector vec);

void ClientPrintAll(int msg_dest, const char* msg_name, const char* param1 = NULL, const char* param2 = NULL, const char* param3 = NULL, const char* param4 = NULL);

void ClientPrint(edict_t* client, int msg_dest, const char* msg_name, const char* param1 = NULL, const char* param2 = NULL, const char* param3 = NULL, const char* param4 = NULL);

void HudMessageAll(const hudtextparms_t& textparms, const char* pMessage, int dest = -1);

void HudMessage(edict_t* pEntity, const hudtextparms_t& textparms, const char* pMessage, int dest = -1);

char* UTIL_VarArgs(char* format, ...);

// never pass an std::string as the cname. The pointer needs to exist as long as the entity does.
// Otherwise, the classname will become corrupted.
CBaseEntity* CreateEntity(const char* cname, map<string, string> keyvalues=map<string,string>(), bool spawn = true);

void GetSequenceInfo(void* pmodel, entvars_t* pev, float* pflFrameRate, float* pflGroundSpeed);

int GetSequenceFlags(void* pmodel, entvars_t* pev);

float SetController(void* pmodel, entvars_t* pev, int iController, float flValue);

float clampf(float val, float min, float max);

int clamp(int val, int min, int max);

CBaseEntity* FindEntityForward(CBaseEntity* ent, float maxDist);

// true if ent returned by FindEntity* engine funcs is valid
bool isValidFindEnt(edict_t* ent);

void RemoveEntity(edict_t* ent);

PlayerState& getPlayerState(edict_t* plr);

PlayerState& getPlayerState(CBasePlayer* plr);

// gets currently connected players and their states
vector<PlayerWithState> getPlayersWithState();

void debug_plr(CBasePlayer* plr, EHandle h_plr);

void PrintKeyBindingString(EHandle h_plr, string text);

CBasePlayer* getPlayer(CBasePlayer* caller, string name);

// display the text for a second longer
void PrintKeyBindingStringLong(CBasePlayer* plr, string text);

void populatePlayerStates();

string format_float(float f);

float AngleDifference(float angle2, float angle1);

Vector VecBModelOrigin(entvars_t* pevBModel);

Vector UTIL_ClampVectorToBox(Vector input, Vector clampSize);

void conPrint(edict_t* plr, string text);
void conPrintln(edict_t* plr, string text);