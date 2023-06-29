#include "ghost_utils.h"
#include "mmlib.h"

PlayerState& getPlayerState(edict_t* plr) {
	string steamId = getPlayerUniqueId(plr);

	if (g_player_states.find(steamId) == g_player_states.end()) {
		g_player_states[steamId] = PlayerState();
	}

	return g_player_states[steamId];
}

PlayerState& getPlayerState(CBasePlayer* plr) {
	return getPlayerState(plr->edict());
}

// gets currently connected players and their states
vector<PlayerWithState> getPlayersWithState() {
	vector<PlayerWithState> playersWithState;

	for (int i = 1; i <= gpGlobals->maxClients; i++) {
		edict_t* ent = INDEXENT(i);

		if (!isValidPlayer(ent)) {
			continue;
		}

		playersWithState.push_back(PlayerWithState((CBasePlayer*)GET_PRIVATE(ent), &getPlayerState(ent)));
	}

	return playersWithState;
}

void conPrint(edict_t* plr, string text) { ClientPrint(plr, HUD_PRINTCONSOLE, text.c_str()); }
void conPrintln(edict_t* plr, string text) { ClientPrint(plr, HUD_PRINTCONSOLE, (text + "\n").c_str()); }

void debug_plr(CBasePlayer* plr, EHandle h_plr) {
	CBasePlayer* statePlr = (CBasePlayer*)h_plr.GetEntity();
	conPrintln(plr->edict(), "    plr: " + (h_plr.IsValid() ? string(STRING(statePlr->pev->netname)) +
		(statePlr->IsConnected() ? ", connected" : ", disconnected") +
		", " + to_string(statePlr->entindex()) : "null"));
}

void PrintKeyBindingString(EHandle h_plr, string text) {
	if (isValidPlayer(h_plr)) {
		ClientPrint(h_plr, HUD_PRINTCENTER, text.c_str());
	}
}

// display the text for a second longer
void PrintKeyBindingStringLong(CBasePlayer* plr, string text)
{
	PrintKeyBindingString(EHandle(plr), text);
	g_Scheduler.SetTimeout(PrintKeyBindingString, 1, EHandle(plr), text);
}

// get player by name, partial name, or steamId
CBasePlayer* getPlayer(CBasePlayer* caller, string name)
{
	if (!caller) {
		return NULL;
	}

	name = toLowerCase(name);
	int partialMatches = 0;
	CBasePlayer* partialMatch;
	for (int i = 1; i <= gpGlobals->maxClients; i++) {
		edict_t* ent = INDEXENT(i);

		if (!isValidPlayer(ent)) {
			continue;
		}

		CBasePlayer* plr = (CBasePlayer*)(GET_PRIVATE(ent));
		string plrName = toLowerCase(string(STRING(plr->pev->netname)));
		string plrId = toLowerCase(getPlayerUniqueId(ent));
		if (plrName == name)
			return plr;
		else if (plrId == name)
			return plr;
		else if (plrName.find(name) != string::npos)
		{
			partialMatch = plr;
			partialMatches++;
		}
	}

	if (partialMatches == 1) {
		return partialMatch;
	}
	else if (partialMatches > 1) {
		ClientPrint(caller->edict(), HUD_PRINTTALK, ("There are " + to_string(partialMatches) + " players that have \"" + name + "\" in their name.Be more specific.").c_str());
	}
	else {
		ClientPrint(caller->edict(), HUD_PRINTTALK, ("There is no player named \"" + name + "\"").c_str());
	}

	return NULL;
}

void populatePlayerStates()
{
	for (int i = 1; i <= gpGlobals->maxClients; i++) {
		edict_t* ent = INDEXENT(i);

		if (!isValidPlayer(ent)) {
			continue;
		}

		getPlayerState(ent);
	}
}

string format_float(float f)
{
	uint32_t decimal = uint32_t(((f - int(f)) * 10)) % 10;
	return to_string(int(f)) + "." + to_string(decimal);
}

float AngleDifference(float angle2, float angle1) {
	float diff = int(angle2 - angle1 + 180) % 360 - 180;
	return diff < -180 ? diff + 360 : diff;
}

Vector VecBModelOrigin(entvars_t* pevBModel)
{
	return pevBModel->absmin + (pevBModel->size * 0.5);
}

Vector UTIL_ClampVectorToBox(Vector input, Vector clampSize)
{
	Vector sourceVector = input;

	if (sourceVector.x > clampSize.x)
		sourceVector.x -= clampSize.x;
	else if (sourceVector.x < -clampSize.x)
		sourceVector.x += clampSize.x;
	else
		sourceVector.x = 0;

	if (sourceVector.y > clampSize.y)
		sourceVector.y -= clampSize.y;
	else if (sourceVector.y < -clampSize.y)
		sourceVector.y += clampSize.y;
	else
		sourceVector.y = 0;

	if (sourceVector.z > clampSize.z)
		sourceVector.z -= clampSize.z;
	else if (sourceVector.z < -clampSize.z)
		sourceVector.z += clampSize.z;
	else
		sourceVector.z = 0;

	return sourceVector.Normalize();
}