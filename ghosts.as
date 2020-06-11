#include "GhostCam"
#include "util"

int ghostId = 0;
dictionary g_player_states;

string g_camera_model = "models/as_ghosts/camera.mdl";
string g_ent_prefix = "plugin_ghost";

dictionary g_player_model_precache;

CCVar@ cvar_use_player_models;
CCVar@ cvar_default_mode;

bool debug_mode = false;

enum ghost_modes {
	MODE_HIDE = 0,
	MODE_SHOW,
	MODE_HIDE_IF_ALIVE,
	MODE_TOTAL
};

class PlayerState
{
	EHandle plr;
	GhostCam cam;
	int visbilityMode = cvar_default_mode.GetInt();
	int viewingMonsterInfo = 0;
	
	bool shouldSeeGhosts() {
		if (visbilityMode == MODE_SHOW)
			return true;
			
		CBasePlayer@ statePlr = cast<CBasePlayer@>(plr.GetEntity());
		return visbilityMode == MODE_HIDE_IF_ALIVE && statePlr !is null && statePlr.GetObserver().IsObserver();
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
	
	@cvar_use_player_models = CCVar("player_models", 1, "show player models instead of cameras", ConCommandFlag::AdminOnly);
	@cvar_default_mode = CCVar("default_mode", MODE_HIDE_IF_ALIVE, "ghost visibility mode", ConCommandFlag::AdminOnly);
	
	populatePlayerStates();
	
	g_Scheduler.SetInterval("ghostLoop", 0.05, -1);
}

void MapInit()
{
	ghostId = 0;
	g_Game.PrecacheModel(g_camera_model);
}

void MapActivate()
{
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
		if (cvar_use_player_models.GetInt() != 0) {
			println("PlayerModelPrecacheDyn entity not found. Did you install the latest version of the PlayerModelPrecacheDyn plugin? Ghost player models aren't going to work without that.\n");
		}
	}
}

void ghostLoop() {
	array<string>@ stateKeys = g_player_states.getKeys();
	
	// check if player is viewing monster info so spectators don't get in the way later
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( g_player_states[stateKeys[i]] );
		
		if (!state.shouldSeeGhosts()) {
			continue;
		}
		
		CBasePlayer@ plr = cast<CBasePlayer@>(state.plr.GetEntity());
		if (plr !is null && plr.IsAlive()) {			
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
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( g_player_states[stateKeys[i]] );
		CBaseEntity@ cam = state.cam.h_cam;
		
		if (cam !is null) {
			cam.pev.solid = SOLID_BBOX;
			g_EntityFuncs.SetSize(cam.pev, Vector(-16, -16, -16), Vector(16, 16, 16));
		}
	}
	
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( g_player_states[stateKeys[i]] );
		state.cam.think();
		
		if (!state.shouldSeeGhosts()) {
			continue;
		}
		
		// show spectator info
		CBasePlayer@ plr = cast<CBasePlayer@>(state.plr.GetEntity());
		CBaseEntity@ cam = state.cam.h_cam;
		if (plr !is null) {
			Math.MakeVectors( plr.pev.v_angle );
			Vector lookDir = g_Engine.v_forward;
			
			CBaseEntity@ phit = null;
			bool shouldShowInfo = false;
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
						params.r1 = 6;
						params.g1 = 170;
						params.b1 = 94;
						
						string info = "Player:  " + phit.pev.netname +
									   "\nHealth:  " + int(phit.pev.health) +
									   "\nArmor:  " + int(plr.pev.armorvalue) +
									   "\nScore:    " + int(phit.pev.frags);
						
						g_PlayerFuncs.HudMessage(plr, params, info);
				} else if (state.viewingMonsterInfo == 0 && string(phit.pev.targetname).Find(g_ent_prefix) == 0) {
					// show ghost info to living players, only if a monster is not in sight
					params.r1 = 163;
					params.g1 = 155;
					params.b1 = 255;
					
					g_PlayerFuncs.HudMessage(plr, params, phit.pev.netname);
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
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( g_player_states[stateKeys[i]] );
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
	getPlayerState(plr);
	update_ghost_visibility();
	return HOOK_CONTINUE;
}

void update_ghost_visibility() {
	array<string>@ stateKeys = g_player_states.getKeys();
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ s = cast<PlayerState@>( g_player_states[stateKeys[i]] );
		s.cam.updateVisibility();
	}
}

void doCommand(CBasePlayer@ plr, const CCommand@ args, bool inConsole) {
	PlayerState@ state = getPlayerState(plr);
	
	if (args.ArgC() >= 2)
	{
		if (args[1] == "version") {
			g_PlayerFuncs.SayText(plr, "ghosts plugin v2 WIP\n");
		}
		else if (isdigit(args[1])) {
			int newMode = atoi(args[1]);
			if (newMode < 0 || newMode >= MODE_TOTAL) {
				newMode = cvar_default_mode.GetInt();
			}
			state.visbilityMode = newMode;
			
			if (newMode == MODE_HIDE) {
				g_PlayerFuncs.SayText(plr, "Hiding ghosts\n");
			} else if (newMode == MODE_HIDE_IF_ALIVE) {
				g_PlayerFuncs.SayText(plr, "Showing ghosts only while dead\n");
			} else if (newMode == MODE_SHOW) {
				g_PlayerFuncs.SayText(plr, "Showing ghosts\n");
			}
			
			update_ghost_visibility();
		}

		if (debug_mode) {
			if (args[1] == "a") {
				plr.GetObserver().StartObserver(plr.pev.origin, plr.pev.v_angle, true);
			}
			if (args[1] == "b") {
				plr.EndRevive(0);
			}
		}
		
	} else {
		KeyValueBuffer@ p_PlayerInfo = g_EngineFuncs.GetInfoKeyBuffer( plr.edict() );
		string playerModel = p_PlayerInfo.GetValue( "model" ).ToLowercase();
		
		bool modelPrecached = g_player_model_precache.exists(playerModel);
		string precachedString = "Your player model is" + (modelPrecached ? "" : " not") + " precached.";
		if (cvar_use_player_models.GetInt() == 0) {
			precachedString = "";
		}
		
		if (inConsole) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".ghosts 0" to hide ghosts.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".ghosts 1" to show ghosts.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".ghosts 2" to show ghosts only while dead.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Your current mode is ' + state.visbilityMode + '. ' + precachedString + '\n');
		} else {
			g_PlayerFuncs.SayText(plr, 'Say ".ghosts 0" to hide ghosts.\n');
			g_PlayerFuncs.SayText(plr, 'Say ".ghosts 1" to show ghosts.\n');
			g_PlayerFuncs.SayText(plr, 'Say ".ghosts 2" to show ghosts only while dead.\n');
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

CClientCommand _ghost("ghosts", "Ghost commands", @consoleCmd );

void consoleCmd( const CCommand@ args ) {
	CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
	doCommand(plr, args, true);
}