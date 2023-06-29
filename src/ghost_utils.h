#pragma once
#include <extdll.h>
#include <string>
#include "main.h"
#include <map>

using namespace std;

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