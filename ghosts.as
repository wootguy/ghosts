#include "GhostCam"
#include "util"

int ghostId = 0;
dictionary g_player_states;

string g_camera_model = "models/as_ghosts/camera.mdl";
string g_ent_prefix = "plugin_ghost_";

dictionary g_player_model_precache;

CCVar@ cvar_use_player_models;
CCVar@ cvar_default_mode;

bool debug_mode = true;

bool g_first_map_load = true;
bool g_use_player_models = true;
bool g_force_visible = false;
bool g_fun_mode = false; // ghost wailing
bool g_stress_test = false;
float g_ghost_collect_delay = 0.5f; // protect against double-using

enum ghost_modes {
	MODE_HIDE = 0,
	MODE_SHOW,
	MODE_HIDE_IF_BLOCKING, // for when ghosts have chasecam enabled and are in front of the player's face
	MODE_HIDE_IF_ALIVE,
	MODE_TOTAL
};

class PlayerState
{
	// Never store player handle? It needs to be set to null on disconnect or else states start sharing
	// player handles and cause weird bugs or break states entirely. Check if disconnect is called
	// if player leaves during level change.

	GhostCam cam;
	int visbilityMode = cvar_default_mode.GetInt();
	int viewingMonsterInfo = 0;
	float nextGhostCollect = 0;
	bool changedMode = false;
	
	bool shouldSeeGhosts(CBasePlayer@ plr) {
		if (visbilityMode == MODE_SHOW || g_force_visible)
			return true;
			
		if (visbilityMode == MODE_HIDE_IF_BLOCKING)
			return true; // individual ghosts will be hidden later
			
		return visbilityMode == MODE_HIDE_IF_ALIVE && plr !is null && plr.GetObserver().IsObserver();
	}
	
	void debug(CBasePlayer@ plr) {		
		conPrintln(plr, "    mode: " + visbilityMode + ", info: " + viewingMonsterInfo);
	}
}

// to be used within a single server frame
class PlayerWithState {
	CBasePlayer@ plr;
	PlayerState@ state;
	
	PlayerWithState(CBasePlayer@ plr, PlayerState@ state) {
		@this.plr = @plr;
		@this.state = @state;
	}
}

void PluginInit()
{	
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "something something github" );
	
	g_Hooks.RegisterHook( Hooks::Player::ClientSay, @ClientSay );
	g_Hooks.RegisterHook( Hooks::Player::PlayerEnteredObserver, @PlayerEnteredObserver );
	g_Hooks.RegisterHook( Hooks::Player::PlayerLeftObserver, @PlayerLeftObserver );
	g_Hooks.RegisterHook( Hooks::Player::ClientPutInServer, @ClientJoin );
	g_Hooks.RegisterHook( Hooks::Player::ClientDisconnect, @ClientLeave );
	g_Hooks.RegisterHook( Hooks::Player::PlayerUse, @PlayerUse );
	
	@cvar_use_player_models = CCVar("player_models", 1, "show player models instead of cameras", ConCommandFlag::AdminOnly);
	@cvar_default_mode = CCVar("default_mode", MODE_HIDE_IF_BLOCKING, "ghost visibility mode", ConCommandFlag::AdminOnly);
	
	delete_ghosts();
	
	populatePlayerStates();
	
	g_Scheduler.SetInterval("ghostLoop", 0.05f, -1);
	
	create_ghosts();
}

void MapInit()
{
	ghostId = 0;
	g_Game.PrecacheModel(g_camera_model);
	
	// reset camera states
	array<string>@ stateKeys = g_player_states.getKeys();
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( g_player_states[stateKeys[i]] );
		state.cam = GhostCam();
		state.nextGhostCollect = 0;
	}
}

void MapActivate()
{
	if (g_first_map_load) {
		g_first_map_load = false;
		g_use_player_models = cvar_use_player_models.GetInt() != 0;
		
		// Reset player view mode to use server setting, unless mode was changed before the level changed
		array<string>@ stateKeys = g_player_states.getKeys();
		for (uint i = 0; i < stateKeys.length(); i++)
		{
			PlayerState@ state = cast<PlayerState@>( g_player_states[stateKeys[i]] );
			if (!state.changedMode) {
				state.visbilityMode = cvar_default_mode.GetInt();
			}
			
		}
	}
	
	g_player_model_precache.clear();
	
	CBaseEntity@ precacheEnt = g_EntityFuncs.FindEntityByTargetname(null, "PlayerModelPrecacheDyn");
	if (precacheEnt !is null) {			
		KeyValueBuffer@ pKeyvalues = g_EngineFuncs.GetInfoKeyBuffer( precacheEnt.edict() );
		CustomKeyvalues@ pCustom = precacheEnt.GetCustomKeyvalues();
		for (int i = 0; i < 64; i++) {
			CustomKeyvalue modelKeyvalue( pCustom.GetKeyvalue( "$s_model" + i ) );
			if (modelKeyvalue.Exists()) {
				string modelName = modelKeyvalue.GetString();
				g_player_model_precache[modelName] = true;
			}
		}
		
	} else {
		println("PlayerModelPrecacheDyn entity not found. Did you install the latest version of the PlayerModelPrecacheDyn plugin? Ghost player models aren't going to work without that.\n");
	}
}

bool isBlockingView(CBasePlayer@ plr, CBaseEntity@ ghost) {
	if (ghost is null)
		return false;
	Math.MakeVectors(plr.pev.v_angle);
	Vector delta = ghost.pev.origin - plr.pev.origin;
	float dist = delta.Length();
	return dist < 64 || DotProduct(g_Engine.v_forward, delta.Normalize()) > 0.3f && dist < 200;
}

void ghostLoop() {
	array<PlayerWithState@> playersWithStates = getPlayersWithState();
	
	// check if player is viewing monster info so spectators don't get in the way later	
	for (uint i = 0; i < playersWithStates.length(); i++)
	{
		CBasePlayer@ plr = playersWithStates[i].plr;
		PlayerState@ state = playersWithStates[i].state;
		
		if (!state.shouldSeeGhosts(plr)) {
			continue;
		}
		
		if (plr.IsAlive()) {
			Math.MakeVectors( plr.pev.v_angle );
			Vector lookDir = g_Engine.v_forward;
			
			CBaseEntity@ phit = g_Utility.FindEntityForward(plr, 4096);
			
			if (phit !is null && phit.IsMonster() && phit.IsAlive()) {
				state.viewingMonsterInfo = 10;
			} else if (state.viewingMonsterInfo > 0) {
				state.viewingMonsterInfo -= 1;
			}
		}
	}
	
	// make cameras solid for tracing
	for (uint i = 0; i < playersWithStates.length(); i++)
	{
		PlayerState@ state = playersWithStates[i].state;
		CBaseEntity@ cam = state.cam.h_cam;
		
		if (cam !is null) {
			cam.pev.solid = SOLID_BBOX;
			g_EntityFuncs.SetSize(cam.pev, Vector(-16, -16, -16), Vector(16, 16, 16));
		}
	}
	
	for (uint i = 0; i < playersWithStates.length(); i++)
	{
		CBasePlayer@ plr = playersWithStates[i].plr;
		PlayerState@ state = playersWithStates[i].state;

		state.cam.think();
		
		if (!state.shouldSeeGhosts(plr)) {
			continue;
		}
		
		// hide ghost if blocking view
		bool isGhostVisible = true;
		if (plr.IsAlive() && state.visbilityMode == MODE_HIDE_IF_BLOCKING && !g_force_visible) {
			for (uint k = 0; k < playersWithStates.length(); k++) {
				if (k == i) {
					continue;
				}

				PlayerState@ gstate = playersWithStates[k].state;
				if (gstate.cam.isValid()) {
					bool blockingView = isBlockingView(plr, gstate.cam.h_cam);
					CBaseEntity@ renderOff = gstate.cam.h_render_off;
					renderOff.Use(plr, plr, blockingView ? USE_ON : USE_OFF);
					isGhostVisible = !blockingView;
				}
			}
		}
		
		// show spectator info
		CBaseEntity@ cam = state.cam.h_cam;
		if (isGhostVisible) {
			Math.MakeVectors( plr.pev.v_angle );
			Vector lookDir = g_Engine.v_forward;
			
			CBaseEntity@ phit = null;
			bool isObserver = plr.GetObserver().IsObserver();
			if (isObserver && cam !is null) {
				TraceResult tr;
				g_Utility.TraceLine( plr.pev.origin, plr.pev.origin + lookDir*4096, dont_ignore_monsters, cam.edict(), tr );
				@phit = g_EntityFuncs.Instance( tr.pHit );
			} else {
				@phit = g_Utility.FindEntityForward(plr, 4096);
			}
			
			if (phit !is null) {
				HUDTextParams params;
				params.effect = 0;
				params.fadeinTime = 0;
				params.fadeoutTime = 0.1;
				params.holdTime = 1.5f;
				
				params.x = 0.04;
				params.y = 0.57;
				params.channel = 3;
				
				if (isObserver && phit.IsPlayer()) {
					CBasePlayer@ hitPlr = cast<CBasePlayer@>(phit);
					params.r1 = 6;
					params.g1 = 170;
					params.b1 = 94;
					
					string info = "Player:  " + phit.pev.netname +
								   "\nHealth:  " + int(phit.pev.health) +
								   "\nArmor:  " + int(plr.pev.armorvalue) +
								   "\nMode:   " + int(getPlayerState(hitPlr).visbilityMode);
					
					g_PlayerFuncs.HudMessage(plr, params, info);
				} else if (state.viewingMonsterInfo == 0 && string(phit.pev.targetname).Find(g_ent_prefix) == 0) {
					// show ghost info to living players, only if a monster is not in sight
					params.r1 = 163;
					params.g1 = 155;
					params.b1 = 255;
					
					string info = "" + phit.pev.netname;
					if (isObserver || true) {
						info += "\nMode:    " + getPlayerState(plr).visbilityMode;
					}
					g_PlayerFuncs.HudMessage(plr, params, info);
				}
				
				if (phit.IsMonster() && phit.IsAlive()) {
					state.viewingMonsterInfo = 2;
				} else if (state.viewingMonsterInfo > 0) {
					state.viewingMonsterInfo -= 1;
				}
			}
		}
	}
	
	// make ghosts nonsolid again
	for (uint i = 0; i < playersWithStates.length(); i++)
	{
		PlayerState@ state = playersWithStates[i].state;
		CBaseEntity@ cam = state.cam.h_cam;
		
		if (cam !is null) {
			cam.pev.solid = SOLID_NOT;
		}
	}
}

HookReturnCode PlayerEnteredObserver( CBasePlayer@ plr ) {
	PlayerState@ state = getPlayerState(plr);
	state.cam.init(plr);
	update_ghost_visibility();
	return HOOK_CONTINUE;
}

HookReturnCode PlayerLeftObserver( CBasePlayer@ plr ) {
	update_ghost_visibility();
	return HOOK_CONTINUE;
}

HookReturnCode ClientJoin( CBasePlayer@ plr ) {
	PlayerState@ state = getPlayerState(plr);
	update_ghost_visibility();
	return HOOK_CONTINUE;
}

HookReturnCode ClientLeave(CBasePlayer@ plr)
{
	delete_orphaned_ghosts();
	return HOOK_CONTINUE;
}

void update_ghost_visibility() {
	array<PlayerWithState@> playersWithStates = getPlayersWithState();
	for (uint i = 0; i < playersWithStates.length(); i++)
	{
		PlayerState@ state = playersWithStates[i].state;
		state.cam.updateVisibility(playersWithStates);
	}
}

void update_ghost_models() {
	array<PlayerWithState@> playersWithStates = getPlayersWithState();
	for (uint i = 0; i < playersWithStates.length(); i++)
	{
		PlayerState@ state = playersWithStates[i].state;
		state.cam.updateModel();
	}
	
	update_ghost_visibility();
}

void delete_ghosts() {

	// reset views so thirdperson view doesn't get stuck
	CBaseEntity@ ent = null;
	do {
		@ent = g_EntityFuncs.FindEntityByClassname(ent, "player"); 
		if (ent !is null)
		{
			CBasePlayer@ plr = cast<CBasePlayer@>(ent);
			if (plr !is null && plr.IsConnected() && plr.GetObserver().IsObserver()) {
				g_EngineFuncs.SetView( plr.edict(), plr.edict() );
			}
		}
	} while (ent !is null);

	// delete old ghost ents in case plugin was reloaded while map is running
	@ent = null;
	do {
		@ent = g_EntityFuncs.FindEntityByTargetname(ent, g_ent_prefix + "*"); 
		if (ent !is null)
		{
			g_EntityFuncs.Remove(ent);
		}
	} while (ent !is null);
}

void delete_orphaned_ghosts() {
	array<string>@ stateKeys = g_player_states.getKeys();
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( g_player_states[stateKeys[i]] );
		if (!state.cam.isValid()) {
			state.cam.remove();
		}
	}
}

void create_ghosts() {
	array<PlayerWithState@> playersWithStates = getPlayersWithState();
	for (uint i = 0; i < playersWithStates.length(); i++)
	{
		CBasePlayer@ plr = playersWithStates[i].plr;
		PlayerState@ state = playersWithStates[i].state;
		if (plr !is null && plr.GetObserver().IsObserver()) {
			state.cam.init(plr);
		}
	}
	
	update_ghost_visibility();
}

void delay_debug_all(EHandle h_plr, uint idx) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null)
		return;
	
	array<string>@ stateKeys = g_player_states.getKeys();
	
	if (idx < stateKeys.size()) {
		PlayerState@ dstate = cast<PlayerState@>( g_player_states[stateKeys[idx]] );
		conPrintln(plr, stateKeys[idx]);
		dstate.debug(plr);
		dstate.cam.debug(plr);
		
		g_Scheduler.SetTimeout("delay_debug_all", 0.05, h_plr, idx+1);
	} else {
		conPrintln(plr, "" + idx + " states");
	}
}

void reload_ghosts() {
	delete_ghosts();
	create_ghosts();
	update_ghost_visibility();
}

void doCommand(CBasePlayer@ plr, const CCommand@ args, bool inConsole) {
	PlayerState@ state = getPlayerState(plr);
	bool isAdmin = g_PlayerFuncs.AdminLevel(plr) >= ADMIN_YES;
	
	if (args.ArgC() >= 2)
	{
		if (args[1] == "version") {
			g_PlayerFuncs.SayText(plr, "ghosts plugin v2\n");
		}
		else if (args[1] == "renderamt" && args.ArgC() >= 3 && isAdmin) {
			g_renderamt = atof(args[2]);
			if (g_renderamt == -1)
				g_renderamt = 96; // default
			g_PlayerFuncs.SayText(plr, "Ghost renderamt is " + g_renderamt + "\n");
			reload_ghosts();
		}
		else if (args[1] == "force" && args.ArgC() >= 3 && isAdmin) {
			int newMode = atoi(args[2]);
			g_force_visible = newMode != 0;
			g_PlayerFuncs.SayText(plr, "Ghost visibility " + (g_force_visible ? "" : "not ") + "forced on\n");
			update_ghost_visibility();
		}
		else if (args[1] == "wail" && args.ArgC() >= 3 && isAdmin) {
			int newMode = atoi(args[2]);
			g_fun_mode = newMode != 0;
			g_PlayerFuncs.SayTextAll(plr, "Ghost wailing " + (g_fun_mode ? "enabled" : "disabled") + "\n");
		}
		else if (args[1] == "trace" && isAdmin) {
			
			array<PlayerWithState@> playersWithStates = getPlayersWithState();
			for (uint i = 0; i < playersWithStates.length(); i++)
			{
				CBasePlayer@ statePlr = playersWithStates[i].plr;
				PlayerState@ dstate = playersWithStates[i].state;
				
				if (state.shouldSeeGhosts(statePlr) && statePlr.GetObserver().IsObserver())
					te_beampoints(plr.pev.origin, statePlr.pev.origin);
			}
		}
		else if (args[1] == "reload" && isAdmin) {
			reload_ghosts();
			g_PlayerFuncs.SayText(plr, "Reloaded ghosts\n");
		}
		else if (args[1] == "reload_hard" && isAdmin) {
			int deleteCount = g_player_states.getSize();
			g_player_states.deleteAll();
			populatePlayerStates();
			reload_ghosts();
			
			g_PlayerFuncs.SayText(plr, "Reloaded ghosts and deleted " + deleteCount + " player states\n");
			return;
		}
		else if (args[1] == "debug" && args.ArgC() >= 3 && isAdmin) {			
			if (args[2] == "count") {
				conPrintln(plr, "" + g_player_states.getSize() + " player states");
			}
			else if (args[2] == "all") {
				delay_debug_all(EHandle(plr), 0);
			} else {
				CBasePlayer@ target = getPlayer(plr, args[2]);
				if (target !is null) {
					PlayerState@ targetState = getPlayerState(target);
					targetState.debug(plr);
					targetState.cam.debug(plr);
				}
			}
		}
		else if (args[1] == "players" && args.ArgC() >= 3) {
			if (!isAdmin) {
				g_PlayerFuncs.SayText(plr, "Only admins can use this command\n");
				return;
			}
			
			int newMode = atoi(args[2]);
			
			g_use_player_models = newMode != 0;
			
			update_ghost_models();
			g_PlayerFuncs.SayTextAll(plr, "Ghost player models " + (g_use_player_models ? "enabled" : "disabled") + "\n");
		}
		else if (isdigit(args[1])) {
			int newMode = atoi(args[1]);
			if (newMode < 0 || newMode >= MODE_TOTAL) {
				newMode = cvar_default_mode.GetInt();
			}
			state.visbilityMode = newMode;
			
			if (newMode == MODE_HIDE) {
				g_PlayerFuncs.SayText(plr, "Hiding ghosts\n");
			} else if (newMode == MODE_HIDE_IF_BLOCKING) {
				g_PlayerFuncs.SayText(plr, "Showing ghosts that don't block your view\n");
			} else if (newMode == MODE_HIDE_IF_ALIVE) {
				g_PlayerFuncs.SayText(plr, "Showing ghosts only while dead\n");
			} else if (newMode == MODE_SHOW) {
				g_PlayerFuncs.SayText(plr, "Showing ghosts\n");
			}
			
			state.changedMode = true;
			update_ghost_visibility();
		}

		if (debug_mode && isAdmin) {
			if (args[1] == "a") {
				plr.GetObserver().StartObserver(plr.pev.origin, plr.pev.v_angle, true);
			}
			if (args[1] == "b") {
				plr.EndRevive(0);
			}
			if (args[1] == "c") {
				te_beampoints(plr.pev.origin, state.cam.h_render_off.GetEntity().pev.origin);
				g_EngineFuncs.SetView( plr.edict(), state.cam.h_render_off.GetEntity().edict() );
			}
			if (args[1] == "d") {
				
				g_stress_test = !g_stress_test;
				
				array<PlayerWithState@> playersWithStates = getPlayersWithState();
				for (uint i = 0; i < playersWithStates.length(); i++)
				{
					CBasePlayer@ statePlr = playersWithStates[i].plr;
					
					if (statePlr.GetObserver().IsObserver()) {
						statePlr.GetObserver().SetObserverTarget(g_stress_test ? plr : null);
						statePlr.GetObserver().SetMode(g_stress_test ? OBS_CHASE_LOCKED : OBS_ROAMING);
					}
				}
				
				
			}
		}
		
	} else {
		KeyValueBuffer@ p_PlayerInfo = g_EngineFuncs.GetInfoKeyBuffer( plr.edict() );
		string playerModel = p_PlayerInfo.GetValue( "model" ).ToLowercase();
		
		bool modelPrecached = g_player_model_precache.exists(playerModel);
		string precachedString = "Your player model is" + (modelPrecached ? "" : " not") + " precached.";
		if (!g_use_player_models) {
			precachedString = "";
		}
		
		if (inConsole) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".ghosts 0" to hide ghosts.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".ghosts 1" to show ghosts.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".ghosts 2" to show ghosts that aren\'t blocking your view.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".ghosts 3" to show ghosts only while dead.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Your current mode is ' + state.visbilityMode + '. ' + precachedString + '\n');
		} else {
			g_PlayerFuncs.SayText(plr, 'Say ".ghosts 0" to hide ghosts.\n');
			g_PlayerFuncs.SayText(plr, 'Say ".ghosts 1" to show ghosts.\n');
			g_PlayerFuncs.SayText(plr, 'Say ".ghosts 2" to show ghosts that aren\'t blocking your view.\n');
			g_PlayerFuncs.SayText(plr, 'Say ".ghosts 3" to show ghosts only while dead.\n');
			g_PlayerFuncs.SayText(plr, 'Your current mode is ' + state.visbilityMode + '. ' + precachedString + '\n');
		}
		
	}
}

HookReturnCode ClientSay( SayParameters@ pParams ) {
	CBasePlayer@ plr = pParams.GetPlayer();
	const CCommand@ args = pParams.GetArguments();
	if (args.ArgC() > 0 and (args[0].Find(".ghosts") == 0 or (debug_mode && args[0].Find(".g") == 0 )) )
	{
		doCommand(plr, args, false);
		pParams.ShouldHide = true;
		return HOOK_HANDLED;
	}
	return HOOK_CONTINUE;
}

// this exists to prevent players +use'ing ghosts (which breaks animations)
// a custom entity could be used instead but that causes really weird bugs and makes testing harder
HookReturnCode PlayerUse( CBasePlayer@ pPlayer, uint& out uiFlags )
{
	if ( ( pPlayer.m_afButtonPressed & IN_USE ) == 0 ) {
		return HOOK_CONTINUE;
	}
	
	if (pPlayer.m_hTank.IsValid() || ( pPlayer.m_afPhysicsFlags & PFLAG_ONTRAIN ) != 0) {
		return HOOK_CONTINUE;
	}
	
	//
	// Half-Life +USE code
	//
	
	CBaseEntity@ pObject = null;
	CBaseEntity@ pClosest = null;
	Vector vecLOS;
	float flMaxDot = VIEW_FIELD_NARROW;
	float flDot;

	Math.MakeVectors(pPlayer.pev.v_angle);
	
	const int PLAYER_SEARCH_RADIUS = 96;
	while ((@pObject = g_EntityFuncs.FindEntityInSphere( pObject, pPlayer.pev.origin, PLAYER_SEARCH_RADIUS, "*", "classname" )) !is null)
	{
		if ((pObject.ObjectCaps() & (FCAP_IMPULSE_USE | FCAP_CONTINUOUS_USE | FCAP_ONOFF_USE)) != 0)
		{
			// !!!PERFORMANCE- should this check be done on a per case basis AFTER we've determined that
			// this object is actually usable? This dot is being done for every object within PLAYER_SEARCH_RADIUS
			// when player hits the use key. How many objects can be in that area, anyway? (sjb)
			vecLOS = (VecBModelOrigin( pObject.pev ) - (pPlayer.pev.origin + pPlayer.pev.view_ofs));
			
			// This essentially moves the origin of the target to the corner nearest the player to test to see 
			// if it's "hull" is in the view cone
			vecLOS = UTIL_ClampVectorToBox( vecLOS, pObject.pev.size * 0.5 );
			
			flDot = DotProduct (vecLOS, g_Engine.v_forward);
			if (flDot > flMaxDot )
			{// only if the item is in front of the user
				@pClosest = pObject;
				flMaxDot = flDot;
			}
		}
	}
	@pObject = @pClosest;

	// Found an object
	if (pObject !is null and string(pObject.pev.targetname).Find(g_ent_prefix) == 0)
	{
		// prevent using cyclers since that messes up their animations
		uiFlags |= PlrHook_SkipUse;
		string ghostId = pObject.pev.noise3;
		
		bool collectedGhostie = false;
		
		PlayerState@ state = getPlayerState(pPlayer);
		if (state.shouldSeeGhosts(pPlayer) && state.visbilityMode != MODE_HIDE_IF_BLOCKING) {
			for ( int i = 1; i <= g_Engine.maxClients; i++ )
			{
				CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex(i);
				if (p is null or !p.IsConnected()) {
					continue;
				}
				if (getPlayerUniqueId(p) == ghostId) {
					if (state.nextGhostCollect < g_Engine.time) {
						CBaseEntity@ observerTarget = p.GetObserver().GetObserverTarget();
						if (observerTarget !is null && observerTarget.entindex() == pPlayer.entindex()) {
							p.GetObserver().SetObserverTarget(null);
							p.GetObserver().SetMode(OBS_ROAMING);
							g_PlayerFuncs.SayText(pPlayer, "Dropped " + p.pev.netname + "\n");
							g_PlayerFuncs.SayText(p, "" + pPlayer.pev.netname + " dropped you\n");
						} else {
							p.GetObserver().SetObserverTarget(pPlayer);
							p.GetObserver().SetMode(OBS_CHASE_FREE);
							p.pev.angles.x = -15;
							p.pev.angles.y = pPlayer.pev.v_angle.y;
							p.pev.fixangle = FAM_FORCEVIEWANGLES;
							g_PlayerFuncs.SayText(pPlayer, "Collected " + p.pev.netname + "\n");
							g_PlayerFuncs.SayText(p, "" + pPlayer.pev.netname + " collected you\n");
						}
						
						state.nextGhostCollect = g_Engine.time + g_ghost_collect_delay;
					} else {
						float waitTime = state.nextGhostCollect - g_Engine.time;
						//g_PlayerFuncs.PrintKeyBindingString(pPlayer, "Wait " + format_float(waitTime) + " seconds\n");
					}
					
					collectedGhostie = true;
					break;
				}
			}
		}
		
		string snd = collectedGhostie ? "common/wpn_select.wav" : "common/wpn_denyselect.wav";
		g_SoundSystem.PlaySound( pPlayer.edict(), CHAN_ITEM, snd, 0.4f, 1.0f, pPlayer.entindex(), 100);
	}
	
	return HOOK_CONTINUE;
}

CClientCommand _ghost("ghosts", "Ghost commands", @consoleCmd );

void consoleCmd( const CCommand@ args ) {
	CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
	doCommand(plr, args, true);
}