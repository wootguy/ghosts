#include "main.h"
#include "meta_init.h"
#include "misc_utils.h"
#include "meta_utils.h"
#include "private_api.h"
#include <set>
#include <map>
#include "Scheduler.h"
#include <vector>
#include "StartSound.h"
#include "meta_helper.h"
#include "temp_ents.h"

// TODO:
// friend/enemy HUD info

// Description of plugin
plugin_info_t Plugin_info = {
	META_INTERFACE_VERSION,	// ifvers
	"Ghosts",	// name
	"1.0",	// version
	__DATE__,	// date
	"w00tguy",	// author
	"https://github.com/wootguy/",	// url
	"GHOSTS",	// logtag, all caps please
	PT_ANYTIME,	// (when) loadable
	PT_ANYPAUSE,	// (when) unloadable
};

map<string, PlayerState> g_player_states;

int ghostId = 0;

set<string> g_player_model_precache;

cvar_t* cvar_use_player_models;
cvar_t* cvar_default_mode;

bool debug_mode = false;

const char* g_camera_model = "models/as_ghosts/camera.mdl";
const char* g_ent_prefix = "plugin_ghost_";

bool g_first_map_load = true;
bool g_use_player_models = true;
bool g_force_visible = false;
bool g_fun_mode = false; // ghost wailing
bool g_stress_test = false;

float g_renderamt = 128; // must be at least 128 or textures with transparency are invisible (gf_ump45)
float g_min_zoom = 0;
float g_max_zoom = 1024;
float g_default_zoom = 96;

bool oldObserverStates[33]; // for enter/leave observer "hooks"

ScheduledFunction map_activate_sched;

enum ghost_modes {
	MODE_HIDE = 0,
	MODE_SHOW,
	MODE_HIDE_IF_BLOCKING, // for when ghosts have chasecam enabled and are in front of the player's face
	MODE_HIDE_IF_ALIVE,
	MODE_TOTAL
};

PlayerState::PlayerState() {
	visbilityMode = cvar_default_mode->value;
}

bool PlayerState::shouldSeeGhosts(CBasePlayer* plr) {
	if (visbilityMode == MODE_SHOW || g_force_visible)
		return true;

	if (visbilityMode == MODE_HIDE_IF_BLOCKING)
		return true; // individual ghosts will be hidden later

	return visbilityMode == MODE_HIDE_IF_ALIVE && plr && plr->IsObserver();
}

void PlayerState::debug(CBasePlayer* plr) {
	conPrintln(plr->edict(), "    mode: " + to_string(visbilityMode) + ", info: " + to_string(viewingMonsterInfo));
}

PlayerWithState::PlayerWithState(CBasePlayer* plr, PlayerState* state) {
	this->plr = plr;
	this->state = state;
}

set<string> g_disabled_maps = {
	"fallguys_s2",
	"fallguys_s3" // for some reason crashing a lot on this map, but still can't reproduce
};

void loadCrossPluginModelPrecache() {
	g_player_model_precache.clear();

	edict_t* precacheEnt = g_engfuncs.pfnFindEntityByString(NULL, "targetname", "TooManyPolys");
	if (isValidFindEnt(precacheEnt)) {
		for (int i = 0; i < 64; i++) {
			string modelName = readCustomKeyvalueString(precacheEnt, "$s_model" + to_string(i));
			g_player_model_precache.insert(modelName);
		}
	}
	else {
		println("TooManyPolys entity not found. Did you install the latest version of the TooManyPolys plugin? Ghost player models aren't going to work without that.\n");
	}
}

void MapActivate() {
	if (gpGlobals->time < 2.0f) {
		g_Scheduler.SetTimeout(MapActivate, 2.0f - gpGlobals->time);
		return;
	}

	if (g_first_map_load) {
		g_first_map_load = false;
		g_use_player_models = cvar_use_player_models->value != 0;

		// Reset player view mode to use server setting, unless mode was changed before the level changed
		for (auto iter : g_player_states)
		{
			PlayerState& state = iter.second;
			if (!state.changedMode) {
				state.visbilityMode = cvar_default_mode->value;
			}
		}
	}

	loadCrossPluginModelPrecache();
}

void MapInit(edict_t* pEdictList, int edictCount, int maxClients) {
	ghostId = 0;
	PrecacheModel((char*)g_camera_model);

	// reset camera states
	for (auto iter : g_player_states)
	{
		PlayerState& state = iter.second;
		state.cam = GhostCam();
		state.nextGhostCollect = 0;
	}

	g_Scheduler.RemoveTimer(map_activate_sched);
	map_activate_sched = g_Scheduler.SetTimeout(MapActivate, 2);

	memset(oldObserverStates, 0, sizeof(bool) * 33);

	RETURN_META(MRES_IGNORED);
}

void MapInit_post(edict_t* pEdictList, int edictCount, int maxClients) {
	loadSoundCacheFile();
	RETURN_META(MRES_IGNORED);
}

bool isBlockingView(CBasePlayer* plr, CBaseEntity* ghost) {
	if (!ghost)
		return false;
	MAKE_VECTORS(plr->pev->v_angle);
	Vector delta = ghost->pev->origin - plr->pev->origin;
	float dist = delta.Length();
	return dist < 64 || DotProduct(gpGlobals->v_forward, delta.Normalize()) > 0.3f && dist < 200;
}

void ghostLoop() {
	vector<PlayerWithState> playersWithStates = getPlayersWithState();

	// check if player is viewing monster info so spectators don't get in the way later	
	for (int i = 0; i < playersWithStates.size(); i++)
	{
		CBasePlayer* plr = playersWithStates[i].plr;
		PlayerState* state = playersWithStates[i].state;

		if (!state->shouldSeeGhosts(plr)) {
			continue;
		}

		if (plr->IsAlive()) {
			MAKE_VECTORS(plr->pev->v_angle);
			Vector lookDir = gpGlobals->v_forward;

			CBaseEntity* phit = FindEntityForward(plr, 4096);

			bool isViewingMonsterInfo = false;
			if (phit) {
				bool seeGhostEnt = string(STRING(phit->pev->targetname)).find(g_ent_prefix) == 0;
				bool seeMonster = phit->IsMonster() && !seeGhostEnt;
				isViewingMonsterInfo = seeMonster && phit->IsAlive();
			}

			if (isViewingMonsterInfo) {
				state->viewingMonsterInfo = 10;
			}
			else if (state->viewingMonsterInfo > 0) {
				state->viewingMonsterInfo -= 1;
			}
		}
	}

	// make cameras solid for tracing
	for (int i = 0; i < playersWithStates.size(); i++)
	{
		PlayerState* state = playersWithStates[i].state;
		CBaseEntity* cam = state->cam.h_cam;

		if (cam) {
			cam->pev->solid = SOLID_BBOX;
			SET_SIZE(cam->edict(), Vector(-16, -16, -16), Vector(16, 16, 16));
			cam->pev->iuser2 = 0; // for some reason iuser2 disables monster info and tracing
		}
	}

	for (int i = 0; i < playersWithStates.size(); i++)
	{
		CBasePlayer* plr = playersWithStates[i].plr;
		PlayerState* state = playersWithStates[i].state;

		state->cam.think();

		if (!state->shouldSeeGhosts(plr)) {
			continue;
		}

		CBaseEntity* cam = state->cam.h_cam;

		// hide ghost if blocking view
		bool isGhostVisible = true;
		bool shouldShowIfNonBlocking = plr->IsAlive() && state->visbilityMode == MODE_HIDE_IF_BLOCKING;
		if (shouldShowIfNonBlocking && !g_force_visible) {
			for (int k = 0; k < playersWithStates.size(); k++) {
				if (k == i) {
					continue;
				}

				PlayerState* gstate = playersWithStates[k].state;
				if (gstate->cam.isValid()) {
					CBaseEntity* gcam = gstate->cam.h_cam;
					bool blockingView = isBlockingView(plr, gcam);
					bool shouldRender = !blockingView && !gstate->cam.hiddenByOtherPlugin(plr);

					CBaseEntity* renderOff = gstate->cam.h_render_off;
					Use(renderOff->edict(), plr->edict(), plr->edict(), shouldRender ? USE_OFF : USE_ON);
					isGhostVisible = shouldRender;
				}
			}
		}

		// show spectator info
		if (isGhostVisible) {
			MAKE_VECTORS(plr->pev->v_angle);
			Vector lookDir = gpGlobals->v_forward;
			
			CBaseEntity* phit = NULL;
			bool isObserver = plr->IsObserver();
			if (isObserver && cam) {
				TraceResult tr;
				cam->pev->solid = SOLID_NOT; // can't ignore custom entity in traceline
				TRACE_LINE(plr->pev->origin, plr->pev->origin + lookDir * 4096, dont_ignore_monsters, NULL, &tr);
				cam->pev->solid = SOLID_BBOX;
				phit = (CBaseEntity*)GET_PRIVATE(tr.pHit);
			}
			else {
				phit = FindEntityForward(plr, 4096);
			}

			if (phit) {
				hudtextparms_t params;
				memset(&params, 0, sizeof(hudtextparms_t));
				params.effect = 0;
				params.fadeinTime = 0;
				params.fadeoutTime = 0.1;
				params.holdTime = 1.5f;

				params.x = 0.04;
				params.channel = 3;

				bool seeGhostEnt = string(STRING(phit->pev->targetname)).find(g_ent_prefix) == 0;
				bool seePlayer = phit->IsPlayer() && phit->IsAlive();
				bool seeMonster = phit->IsMonster() && phit->IsAlive() && !seeGhostEnt;
				bool seeBreakable = phit->IsBreakable();

				if (isObserver && !seeGhostEnt && (seeMonster || seePlayer || seeBreakable)) {
					if (seePlayer) {
						params.y = 0.57;
						CBasePlayer* hitPlr = (CBasePlayer*)(phit);

						params.r1 = 6;
						params.g1 = 170;
						params.b1 = 94;

						if (hitPlr && hitPlr->IsConnected()) {
							PlayerState& hitState = getPlayerState(hitPlr->edict());
							string info = string("Player:  ") + STRING(hitPlr->pev->netname) +
								"\nHealth:  " + to_string(int(hitPlr->pev->health)) +
								"\nArmor:  " + to_string(int(hitPlr->pev->armorvalue)) +
								"\nMode:   " + to_string(int(hitState.visbilityMode));

							HudMessage(plr->edict(), params, info.c_str());
						}
					}
					else if (seeBreakable) {
						params.y = 0.582;
						params.r1 = 255;
						params.g1 = 16;
						params.b1 = 16;
						string name = STRING(phit->pev->netname);
						if (name.size() == 0) {
							name = "Breakable";
						}

						string info = name +
							"\nHealth:  " + to_string(int(phit->pev->health));

						HudMessage(plr->edict(), params, info.c_str());
					}
					else if (seeMonster) {
						CBaseMonster* hitMon = (CBaseMonster*)(phit);
						/*
						int rel = plr.IRelationship(hitMon);
						bool isFriendly = rel == R_AL || rel == R_NO;

						params.y = 0.582;
						if (isFriendly) {
							params.r1 = 6;
							params.g1 = 170;
							params.b1 = 94;
						}
						else {
							params.r1 = 255;
							params.g1 = 16;
							params.b1 = 16;
						}
						string relStr = isFriendly ? "Friend:  " : "Enemy:  ";
						*/

						params.y = 0.582;
						params.r1 = 255;
						params.g1 = 16;
						params.b1 = 16;
						string relStr = "";

						if (hitMon && hitMon->IsAlive()) {
							string info = relStr + STRING(hitMon->m_FormattedName) +
								"\nHealth:  " + to_string(int(hitMon->pev->health)) +
								"\nFrags:    " + to_string(int(hitMon->pev->frags));

							HudMessage(plr->edict(), params, info.c_str());
						}
					}

				}
				else if (state->viewingMonsterInfo == 0 && seeGhostEnt) {
					// show ghost info to living players, only if a monster is not in sight
					params.r1 = 163;
					params.g1 = 155;
					params.b1 = 255;
					params.y = 0.582;

					HudMessage(plr->edict(), params, STRING(phit->pev->netname));
				}

				if (seeMonster && phit->IsAlive()) {
					state->viewingMonsterInfo = 2;
				}
				else if (state->viewingMonsterInfo > 0) {
					state->viewingMonsterInfo -= 1;
				}
			}
		}
	}

	// make ghosts nonsolid again
	for (int i = 0; i < playersWithStates.size(); i++)
	{
		PlayerState* state = playersWithStates[i].state;
		CBaseEntity* cam = state->cam.h_cam;

		if (cam) {
			cam->pev->solid = SOLID_NOT;
			cam->pev->iuser2 = playersWithStates[i].plr->entindex();
		}
	}

	// update visibility info for other plugins
	for (int i = 0; i < playersWithStates.size(); i++)
	{
		PlayerState* state = playersWithStates[i].state;
		CBaseEntity* cam = state->cam.h_cam;

		state->cam.isVisible = 0;

		if (!state->cam.h_cam.IsValid()) {
			continue;
		}

		if (state->cam.isThirdPerson) {
			state->cam.isVisible |= (1 << (playersWithStates[i].plr->entindex() & 31));
		}

		for (int k = 0; k < playersWithStates.size(); k++) {
			if (k == i) {
				continue;
			}

			PlayerState* otherState = playersWithStates[k].state;
			CBasePlayer* otherPlr = playersWithStates[k].plr;

			if (!otherState->shouldSeeGhosts(otherPlr)) {
				continue;
			}

			bool isVisible = g_force_visible;
			if (otherState->visbilityMode == MODE_HIDE_IF_BLOCKING) {
				if (!otherPlr->IsAlive() || !isBlockingView(otherPlr, cam)) {
					isVisible = true;
				}
			}
			else if (otherState->visbilityMode == MODE_HIDE_IF_ALIVE) {
				if (!otherPlr->IsAlive()) {
					isVisible = true;
				}
			}
			else if (otherState->visbilityMode == MODE_SHOW) {
				isVisible = true;
			}

			if (isVisible) {
				state->cam.isVisible |= (1 << (otherPlr->entindex() & 31));
			}
		}

		cam->pev->iuser4 = state->cam.isVisible;
	}
}

void PlayerEnteredObserver(edict_t* plr) {
	PlayerState& state = getPlayerState(plr);

	if (state.cam.isValid()) {
		// spamming an observer bind can somehow call EnteredObserver twice before LeftObserver is called :s
		state.cam.remove();
	}

	if (g_disabled_maps.count(STRING(gpGlobals->mapname)))
		return;

	state.cam.init((CBasePlayer*)GET_PRIVATE(plr));

	update_ghost_visibility();
}

void PlayerLeftObserver(edict_t* plr) {
	update_ghost_visibility();
}

void ClientJoin(edict_t* plr) {
	PlayerState& state = getPlayerState(plr);
	update_ghost_visibility();
	oldObserverStates[ENTINDEX(plr)] = false;
	RETURN_META(MRES_IGNORED);
}

void ClientLeave(edict_t* plr) {
	delete_orphaned_ghosts();
	oldObserverStates[ENTINDEX(plr)] = false;
	RETURN_META(MRES_IGNORED);
}

void update_ghost_visibility() {
	vector<PlayerWithState> playersWithStates = getPlayersWithState();
	for (int i = 0; i < playersWithStates.size(); i++) {
		PlayerState* state = playersWithStates[i].state;
		state->cam.updateVisibility(playersWithStates);
	}
}

void update_ghost_models() {
	vector<PlayerWithState> playersWithStates = getPlayersWithState();
	for (int i = 0; i < playersWithStates.size(); i++)
	{
		PlayerState* state = playersWithStates[i].state;
		state->cam.updateModel();
	}

	update_ghost_visibility();
}

void delete_ghosts() {

	// reset views so thirdperson view doesn't get stuck
	for (int i = 1; i <= gpGlobals->maxClients; i++) {
		edict_t* ent = INDEXENT(i);

		if (!isValidPlayer(ent)) {
			continue;
		}

		CBasePlayer* plr = (CBasePlayer*)GET_PRIVATE(ent);
		if (plr->IsObserver()) {
			g_engfuncs.pfnSetView(plr->edict(), plr->edict());
		}
	}

	// delete old ghost ents in case plugin was reloaded while map is running
	edict_t* ent = NULL;
	do {
		ent = g_engfuncs.pfnFindEntityByString(ent, "targetname", (string(g_ent_prefix) + "*").c_str());
		if (isValidFindEnt(ent))
		{
			//println("DELETE A GHOST %s", STRING(ent->v.targetname));
			RemoveEntity(ent);
		}
	} while (isValidFindEnt(ent));
}

void delete_orphaned_ghosts() {
	for (auto iter : g_player_states)
	{
		PlayerState& state = iter.second;
		if (!state.cam.isValid()) {
			state.cam.remove();
		}
	}
}

void create_ghosts() {
	if (g_disabled_maps.count(STRING(gpGlobals->mapname))) {
		return;
	}

	vector<PlayerWithState> playersWithStates = getPlayersWithState();
	println("Create ghosts for %d players", playersWithStates.size());
	for (int i = 0; i < playersWithStates.size(); i++)
	{
		CBasePlayer* plr = playersWithStates[i].plr;
		PlayerState* state = playersWithStates[i].state;
		if (plr && plr->IsObserver()) {
			state->cam.init(plr);
		}
	}

	update_ghost_visibility();
}


void delay_debug_all(EHandle h_plr, int idx) {
	/*
	CBasePlayer* plr = (CBasePlayer*)(h_plr.GetEntity());
	if (!plr)
		return;

	vector<string>* stateKeys = g_player_states.getKeys();

	if (idx < stateKeys.size()) {
		PlayerState* dstate = cast<PlayerState*>(g_player_states[stateKeys[idx]]);
		conPrintln(plr, stateKeys[idx]);
		dstate.debug(plr);
		dstate.cam.debug(plr);

		g_Scheduler.SetTimeout("delay_debug_all", 0.05, h_plr, idx + 1);
	}
	else {
		conPrintln(plr, "" + idx + " states");
	}
	*/
}

void reload_ghosts() {
	delete_ghosts();
	create_ghosts();
	update_ghost_visibility();
}

bool doCommand(edict_t* plr) {
	PlayerState& state = getPlayerState(plr);
	bool isAdmin = AdminLevel(plr) >= ADMIN_YES;

	CommandArgs args = CommandArgs();
	args.loadArgs();

	if (args.ArgC() == 0 || args.ArgV(0).find(".ghosts") != 0) {
		return false;
	}

	if (args.ArgC() >= 2)
	{
		if (args.ArgV(1) == "version") {
			ClientPrint(plr, HUD_PRINTTALK, "ghosts plugin v2\n");
		}
		else if (args.ArgV(1) == "model" && args.ArgC() >= 3) {
			int newMode = atoi(args.ArgV(2).c_str());
			state.enablePlayerModel = newMode != 0;

			if (!g_use_player_models) {
				ClientPrint(plr, HUD_PRINTTALK, "Can't change model mode. The server is forcing camera models.\n");
			}
			else {
				if (state.enablePlayerModel) {
					string text = "Your ghost model is now your player model";

					char* p_PlayerInfo = g_engfuncs.pfnGetInfoKeyBuffer(plr);
					string playerModel = toLowerCase(g_engfuncs.pfnInfoKeyValue(p_PlayerInfo, "model"));
					bool modelPrecached = g_player_model_precache.count(playerModel);

					text += modelPrecached ? "" : " (not precached yet)";
					ClientPrint(plr, HUD_PRINTTALK, (text + "\n").c_str());
				}
				else {
					ClientPrint(plr, HUD_PRINTTALK, "Your ghost model is now a camera.\n");
				}

				update_ghost_models();
			}
		}
		else if (args.ArgV(1) == "renderamt" && args.ArgC() >= 3 && isAdmin) {
			g_renderamt = atof(args.ArgV(2).c_str());
			if (g_renderamt == -1)
				g_renderamt = 96; // default
			ClientPrintAll(HUD_PRINTTALK, ("Ghost transparency is now " + to_string(g_renderamt) + " / 255\n").c_str());
			reload_ghosts();
		}
		else if (args.ArgV(1) == "force" && args.ArgC() >= 3 && isAdmin) {
			int newMode = atoi(args.ArgV(2).c_str());
			g_force_visible = newMode != 0;
			ClientPrintAll(HUD_PRINTTALK, ("Ghost visibility " + string(g_force_visible ? "" : "not ") + "forced on\n").c_str());
			update_ghost_visibility();
		}
		else if (args.ArgV(1) == "wail" && args.ArgC() >= 3 && isAdmin) {
			int newMode = atoi(args.ArgV(2).c_str());
			g_fun_mode = newMode != 0;
			ClientPrintAll(HUD_PRINTTALK, ("Ghost wailing " + string(g_fun_mode ? "enabled" : "disabled") + "\n").c_str());
		}
		else if (args.ArgV(1) == "trace" && isAdmin) {

			vector<PlayerWithState> playersWithStates = getPlayersWithState();
			for (int i = 0; i < playersWithStates.size(); i++)
			{
				CBasePlayer* statePlr = playersWithStates[i].plr;
				PlayerState* dstate = playersWithStates[i].state;

				if (state.shouldSeeGhosts(statePlr) && statePlr->IsObserver())
					te_beampoints(plr->v.origin, statePlr->pev->origin);
			}
		}
		else if (args.ArgV(1) == "reload" && isAdmin) {
			reload_ghosts();
			ClientPrintAll(HUD_PRINTTALK, "Reloaded ghosts\n");
		}
		else if (args.ArgV(1) == "reload_hard" && isAdmin) {
			int deleteCount = g_player_states.size();
			g_player_states.clear();
			populatePlayerStates();
			reload_ghosts();

			ClientPrintAll(HUD_PRINTTALK, ("Reloaded ghosts and deleted " + to_string(deleteCount) + " player states\n").c_str());
		}
		else if (args.ArgV(1) == "debug" && args.ArgC() >= 3 && isAdmin) {
			if (args.ArgV(2) == "count") {
				conPrintln(plr, to_string(g_player_states.size()) + " player states");
			}
			else if (args.ArgV(2) == "all") {
				delay_debug_all(EHandle(plr), 0);
			}
			else {
				CBasePlayer* target = getPlayer((CBasePlayer*)GET_PRIVATE(plr), args.ArgV(2));
				if (target) {
					PlayerState& targetState = getPlayerState(target);
					targetState.debug((CBasePlayer*)GET_PRIVATE(plr));
					targetState.cam.debug((CBasePlayer*)GET_PRIVATE(plr));
				}
			}
		}
		else if (args.ArgV(1) == "players" && args.ArgC() >= 3) {
			if (!isAdmin) {
				ClientPrint(plr, HUD_PRINTTALK, "Only admins can use this command\n");
				return true;
			}

			int newMode = atoi(args.ArgV(2).c_str());

			g_use_player_models = newMode != 0;

			update_ghost_models();
			ClientPrintAll(HUD_PRINTTALK, ("Ghost player models " + string(g_use_player_models ? "enabled" : "disabled") + "\n").c_str());
		}
		else if (args.ArgV(1).size() && isdigit(args.ArgV(1)[0])) {
			int newMode = atoi(args.ArgV(1).c_str());
			if (newMode < 0 || newMode >= MODE_TOTAL) {
				newMode = cvar_default_mode->value;
			}
			state.visbilityMode = newMode;

			if (newMode == MODE_HIDE) {
				ClientPrint(plr, HUD_PRINTTALK, "Hiding ghosts\n");
			}
			else if (newMode == MODE_HIDE_IF_BLOCKING) {
				ClientPrint(plr, HUD_PRINTTALK, "Showing ghosts that don't block your view\n");
			}
			else if (newMode == MODE_HIDE_IF_ALIVE) {
				ClientPrint(plr, HUD_PRINTTALK, "Showing ghosts only while dead\n");
			}
			else if (newMode == MODE_SHOW) {
				ClientPrint(plr, HUD_PRINTTALK, "Showing ghosts\n");
			}

			state.changedMode = true;
			update_ghost_visibility();
		}
		/*
		if (debug_mode && isAdmin) {
			if (args.ArgV(1) == "d") {

				g_stress_test = !g_stress_test;

				vector<PlayerWithState*> playersWithStates = getPlayersWithState();
				for (int i = 0; i < playersWithStates.size(); i++)
				{
					CBasePlayer* statePlr = playersWithStates[i].plr;

					if (statePlr.GetObserver().IsObserver()) {
						statePlr.GetObserver().SetObserverTarget(g_stress_test ? plr : null);
						statePlr.GetObserver().SetMode(g_stress_test ? OBS_CHASE_LOCKED : OBS_ROAMING);
					}
				}
			}
		}
		*/
	}
	else {
		char* p_PlayerInfo = g_engfuncs.pfnGetInfoKeyBuffer(plr);
		string playerModel = toLowerCase(g_engfuncs.pfnInfoKeyValue(p_PlayerInfo, "model"));

		bool modelPrecached = g_player_model_precache.count(playerModel);
		string precachedString = "Your player model is" + string(modelPrecached ? "" : " not") + " precached.";
		if (!g_use_player_models) {
			precachedString = "";
		}

		if (args.isConsoleCmd) {
			ClientPrint(plr, HUD_PRINTCONSOLE, "----------------------------------Ghost Commands----------------------------------\n\n");
			ClientPrint(plr, HUD_PRINTCONSOLE, "Type \".ghosts <0,1,2,3>\" to change ghost visibility mode.\n");
			ClientPrint(plr, HUD_PRINTCONSOLE, "    0 = never show ghosts.\n");
			ClientPrint(plr, HUD_PRINTCONSOLE, "    1 = always show ghosts.\n");
			ClientPrint(plr, HUD_PRINTCONSOLE, "    2 = show ghosts that aren\"t blocking your view.\n");
			ClientPrint(plr, HUD_PRINTCONSOLE, "    3 = show ghosts only while dead.\n\n");
			ClientPrint(plr, HUD_PRINTCONSOLE, "Type \".ghosts model <0,1>\" to change ghost model mode.\n");
			ClientPrint(plr, HUD_PRINTCONSOLE, "    0 = always use camera model.\n");
			ClientPrint(plr, HUD_PRINTCONSOLE, "    1 = use player model, if available (the server must have it installed).\n\n");
			if (isAdmin) {
				ClientPrint(plr, HUD_PRINTCONSOLE, "Type \".ghosts wail <0,1>\" to toggle ghost wailing (click to shoot sprites).\n");
				ClientPrint(plr, HUD_PRINTCONSOLE, "Type \".ghosts players <0,1>\" to toggle ghost player models.\n");
			}

			ClientPrint(plr, HUD_PRINTCONSOLE, ("\nYour current mode is " + to_string(state.visbilityMode) + ". " + precachedString + "\n").c_str());
			ClientPrint(plr, HUD_PRINTCONSOLE, "\n----------------------------------------------------------------------------------\n");

		}
		else {
			ClientPrint(plr, HUD_PRINTTALK, "Say \".ghosts <0,1,2,3>\" to change ghost visibility mode.\n");
			ClientPrint(plr, HUD_PRINTTALK, "Say \".ghosts model <0,1>\" to change ghost model mode.\n");
			ClientPrint(plr, HUD_PRINTTALK, "Type \".ghosts\" in console for more info\n");
		}

		if (g_disabled_maps.count(STRING(gpGlobals->mapname))) {
			ClientPrint(plr, HUD_PRINTTALK, "Ghosts are disabled on this map.\n");
		}
	}

	return true;
}

// called before angelscript hooks
void ClientCommand(edict_t* pEntity) {
	META_RES ret = doCommand(pEntity) ? MRES_SUPERCEDE : MRES_IGNORED;
	RETURN_META(ret);
}

void StartFrame() {
	g_Scheduler.Think();

	for (int i = 1; i <= gpGlobals->maxClients; i++) {
		edict_t* ent = INDEXENT(i);
		CBasePlayer* plr = (CBasePlayer*)GET_PRIVATE(ent);

		if (!isValidPlayer(ent) || !plr) {
			continue;
		}

		bool newState = plr->IsObserver();
		
		if (newState && !oldObserverStates[i]) {
			PlayerEnteredObserver(ent);
		}
		else if (!newState && oldObserverStates[i]) {
			PlayerLeftObserver(ent);
		}

		oldObserverStates[i] = newState;
	}

	RETURN_META(MRES_IGNORED);
}

void PluginInit() {
	cvar_use_player_models = RegisterCVar("ghosts.player_models", "1", 1, 0);
	cvar_default_mode = RegisterCVar("ghosts.default_mode", (char*)to_string(MODE_HIDE_IF_BLOCKING).c_str(), MODE_HIDE_IF_BLOCKING, 0);

	delete_ghosts();

	populatePlayerStates();

	for (int i = 1; i <= gpGlobals->maxClients; i++) {
		edict_t* ent = INDEXENT(i);
		CBasePlayer* plr = (CBasePlayer*)GET_PRIVATE(ent);

		if (!isValidPlayer(ent) || !plr) {
			continue;
		}

		oldObserverStates[i] = plr->IsObserver();
	}

	g_Scheduler.SetInterval(ghostLoop, 0.05f, -1);

	// can't check map name on first frame
	g_Scheduler.SetTimeout(create_ghosts, 0.0f);

	g_dll_hooks.pfnClientCommand = ClientCommand;
	g_dll_hooks.pfnClientDisconnect = ClientLeave;
	g_dll_hooks.pfnServerActivate = MapInit;
	g_dll_hooks_post.pfnServerActivate = MapInit_post;
	g_dll_hooks.pfnStartFrame = StartFrame;

	if (gpGlobals->time > 4) {
		loadSoundCacheFile();
		loadCrossPluginModelPrecache();
	}
}

void PluginExit() {}