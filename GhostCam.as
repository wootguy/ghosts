float g_renderamt = 96;

class GhostCam
{
	EHandle h_plr;
	EHandle h_cam;
	EHandle h_render_off; // also used as a thirdperson view target
	EHandle h_hat;
	EHandle h_watch_hat; // hat entity created by the hats plugin
	bool initialized = false;
	bool isPlayerModel;
	bool isThirdPerson = false;
	float nextThirdPersonToggle = 0;
	Vector lastOrigin;
	Vector lastThirdPersonOrigin;
	
	GhostCam() {}
	
	GhostCam(CBasePlayer@ plr) {
		init(plr);
	}
	
	void init(CBasePlayer@ plr) {
		h_plr = plr;
		
		isPlayerModel = g_use_player_models;
		
		ghostId++;
		
		dictionary keys;
		keys["origin"] = plr.pev.origin.ToString();
		keys["model"] = isPlayerModel ? getPlayerModel() : g_camera_model;
		keys["targetname"] = g_ent_prefix + ghostId;
		keys["netname"] = string(plr.pev.netname);
		keys["rendermode"] = "1";
		keys["renderamt"] = "" + g_renderamt;
		keys["spawnflags"] = "1";
		CBaseEntity@ ghostCam = g_EntityFuncs.CreateEntity("cycler", keys, true);		
		ghostCam.pev.solid = SOLID_NOT;
		ghostCam.pev.movetype = MOVETYPE_NOCLIP;
		ghostCam.pev.takedamage = 0;
		h_cam = ghostCam;

		dictionary rkeys;
		rkeys["target"] = string(ghostCam.pev.targetname);
		rkeys["origin"] = plr.pev.origin.ToString();
		rkeys["targetname"] = g_ent_prefix + "render_" + ghostId;
		rkeys["spawnflags"] = "" + (1 | 4 | 8 | 64); // no renderfx + no rendermode + no rendercolor + affect activator
		rkeys["renderamt"] = "0";
		CBaseEntity@ hideGhostCam = g_EntityFuncs.CreateEntity("env_render_individual", rkeys, true);
		
		// making this ent "visible" so it can be used as a third person view target
		g_EntityFuncs.SetModel(hideGhostCam, "sprites/saveme.spr");
		hideGhostCam.pev.rendermode = 1;
		hideGhostCam.pev.renderamt = 0;
		hideGhostCam.pev.movetype = MOVETYPE_NOCLIP;
		
		h_render_off = hideGhostCam;

		createCameraHat();
		
		initialized = true;
		isThirdPerson = false;
	}
	
	void toggleThirdperson() {
		if (!isValid()) {
			return;
		}
		CBaseEntity@ plr = h_plr;
		CBaseEntity@ hideGhostCam = h_render_off;
		
		isThirdPerson = !isThirdPerson;
		if (isThirdPerson) {
			g_EngineFuncs.SetView( h_plr.GetEntity().edict(), h_render_off.GetEntity().edict() );
			hideGhostCam.Use(plr, plr, USE_OFF);
		} else {
			g_EngineFuncs.SetView( h_plr.GetEntity().edict(), h_plr.GetEntity().edict() );
			hideGhostCam.Use(plr, plr, USE_ON);
		}
	}
	
	void debug(CBasePlayer@ plr) {
		debug_plr(plr, h_plr);
		
		conPrintln(plr, "    cam ents: " + (h_cam.IsValid() ? string(h_cam.GetEntity().pev.targetname) : "null") +
				", " + (h_render_off.IsValid() ? string(h_render_off.GetEntity().pev.targetname) : "null") +
				", " + (h_hat.IsValid() ? string(h_hat.GetEntity().pev.targetname) : "null") + 
				", " + (h_watch_hat.IsValid() ? "valid" : "null"));
		
		conPrintln(plr, "    initialized: " + (initialized ? "true" : "false") + 
						", isPlayerModel: " + (isPlayerModel ? "true" : "false"));
	}
	
	string getPlayerModel() {
		CBaseEntity@ plr = h_plr;
		if (plr is null)
			return "models/player.mdl";
	
		KeyValueBuffer@ p_PlayerInfo = g_EngineFuncs.GetInfoKeyBuffer( plr.edict() );
		string playerModel = p_PlayerInfo.GetValue( "model" ).ToLowercase();
		
		if (g_player_model_precache.exists(playerModel)) {
			return "models/player/" + playerModel + "/" + playerModel + ".mdl";
		}
		
		return "models/player.mdl";
	}
	
	// custom keyvalues cause crashes, so this just searches for any model attached to the plater which is most likely a hat.
	CBaseEntity@ getPlayerHat() {
		if (!h_plr.IsValid())
			return null;
			
		CBaseEntity@ plr = h_plr;
	
		CBaseEntity@ ent = null;
		do {
			@ent = g_EntityFuncs.FindEntityByClassname(ent, "info_target"); 
			if (ent !is null)
			{
				if (@ent.pev.aiment == @plr.edict() && string(ent.pev.model).Find("hat") != String::INVALID_INDEX) {
					return ent;
				}
			}
		} while (ent !is null);
		
		return null;
	}
	
	void createCameraHat() {
		g_EntityFuncs.Remove(h_hat);
		h_watch_hat = null;
		
		CBaseEntity@ playerHat = getPlayerHat();
		if (playerHat is null) {
			return;
		}
	
		CBaseEntity@ cam = h_cam;
	
		dictionary keys;
		keys["origin"] = cam.pev.origin.ToString();
		keys["model"] = "" + playerHat.pev.model;
		keys["targetname"] = string(cam.pev.targetname);
		keys["rendermode"] = "1";
		keys["renderamt"] = "" + g_renderamt;
		keys["spawnflags"] = "1";
		CBaseEntity@ camHat = g_EntityFuncs.CreateEntity("env_sprite", keys, true);	

		camHat.pev.movetype = MOVETYPE_FOLLOW;
		@camHat.pev.aiment = cam.edict();
		
		camHat.pev.sequence = playerHat.pev.sequence;
		camHat.pev.body = playerHat.pev.body;
		camHat.pev.framerate = playerHat.pev.framerate;
		camHat.pev.colormap = cam.pev.colormap;
		
		h_watch_hat = playerHat;
		h_hat = camHat;
	}
	
	void updateVisibility() {
		if (!isValid()) {
			return;
		}
		
		CBaseEntity@ plr = h_plr;
		CBaseEntity@ hideGhostCam = h_render_off;
		
		array<string>@ stateKeys = g_player_states.getKeys();
		for (uint i = 0; i < stateKeys.length(); i++)
		{
			PlayerState@ state = cast<PlayerState@>( g_player_states[stateKeys[i]] );
			CBasePlayer@ statePlr = cast<CBasePlayer@>(state.h_plr.GetEntity());
			
			if (statePlr is null)
				continue;
			
			if (statePlr.entindex() == plr.entindex())
				continue;
			
			if (state.shouldSeeGhosts()) {
				hideGhostCam.Use(statePlr, statePlr, USE_OFF);
			} else {
				hideGhostCam.Use(statePlr, statePlr, USE_ON);
			}
		}
		
		// always hide observer's own camera
		if (!isThirdPerson)
			hideGhostCam.Use(plr, plr, USE_ON);
	}
	
	void updateModel() {
		if (!isValid()) {
			return;
		}
		
		isPlayerModel = g_use_player_models;
		CBaseEntity@ cam = h_cam;
		
		g_EntityFuncs.Remove(h_hat);
		g_EntityFuncs.SetModel(cam, g_use_player_models ? getPlayerModel() : g_camera_model);
		createCameraHat();
	}
	
	void toggleFlashlight() {
		CBaseEntity@ cam = h_cam;
		if (cam !is null) {
			cam.pev.effects |= 12;
		}
	}
	
	void sprayLogo() {
		if (!isValid()) {
			return;
		}
		CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
		
		if (plr.m_flNextDecalTime > g_Engine.time) {
			return;
		}
		
		Math.MakeVectors( plr.pev.v_angle );
		Vector lookDir = g_Engine.v_forward;
		TraceResult tr;
		g_Utility.TraceLine( plr.pev.origin, plr.pev.origin + lookDir*128, ignore_monsters, null, tr );
		
		if (tr.flFraction < 1.0f) {
			plr.m_flNextDecalTime = g_Engine.time + g_EngineFuncs.CVarGetPointer( "decalfrequency" ).value;
			g_Utility.PlayerDecalTrace(tr, plr.entindex(), 0, true);
			g_SoundSystem.PlaySound( plr.edict(), CHAN_STATIC, "player/sprayer.wav", 0.25f, 0.1f, plr.entindex(), 100);
		}
		
	}
	
	void shoot() {
		if (!isValid()) {
			return;
		}
		CBaseEntity@ plr = h_plr;
		CBaseEntity@ cam = h_cam;

		Math.MakeVectors( plr.pev.v_angle );
		Vector lookDir = g_Engine.v_forward;
		
		te_projectile(plr.pev.origin, lookDir*512, null, "sprites/saveme.spr", 1);
		//te_projectile(plr.pev.origin, lookDir*512, null, "sprites/saveme.spr", 1);
		//te_projectile(plr.pev.origin, lookDir*512, null, "sprites/grenade.spr", 1);
		
		g_SoundSystem.PlaySound( plr.edict(), CHAN_STATIC, "fgrunt/medic.wav", 0.1f, 0.1f, plr.entindex(), 90);
		
		/*
		TraceResult tr;
		g_Utility.TraceLine( plr.pev.origin, plr.pev.origin + lookDir*4096, dont_ignore_monsters, cam.edict(), tr );
		if (tr.flFraction < 1.0f) {
			g_Utility.Sparks(tr.vecEndPos);
			
		}
		te_tracer(plr.pev.origin + Vector(0,0,-8), tr.vecEndPos);
		*/
	}
	
	bool isValid() {
		if (h_plr.IsValid()) {
			CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
			if (plr is null or !plr.IsConnected() or plr.IsAlive() or !plr.GetObserver().IsObserver()) {
				return false;
			}
		} else {
			return false;
		}
		
		return h_cam.IsValid() && h_render_off.IsValid();
	}
	
	void remove() {
		if (isThirdPerson) {
			toggleThirdperson();
		}
		if (h_cam.IsValid()) {
			CBaseEntity@ cam = h_cam;
			
			array<string>@ stateKeys = g_player_states.getKeys();
			for (uint i = 0; i < stateKeys.length(); i++)
			{
				PlayerState@ state = cast<PlayerState@>( g_player_states[stateKeys[i]] );
				CBaseEntity@ plr = state.h_plr;
				if (plr !is null && state.shouldSeeGhosts()) {
					int scale = isPlayerModel ? 10 : 4;
					te_smoke(cam.pev.origin - Vector(0,0,24), "sprites/steam1.spr", scale, 40, MSG_ONE_UNRELIABLE, plr.edict());
					g_SoundSystem.PlaySound( cam.edict(), CHAN_STATIC, "player/pl_organic2.wav", 0.8f, 1.0f, 0, 50, plr.entindex());
				}
			}			
		}
	
		g_EntityFuncs.Remove(h_render_off);
		g_EntityFuncs.Remove(h_hat);
		g_EntityFuncs.Remove(h_cam);
		
		initialized = false;
	}
	
	void think() {
		if (!isValid()) {
			if (initialized) {
				remove();
			}
			return;
		}
	
		CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
		CBaseMonster@ cam = cast<CBaseMonster@>(h_cam.GetEntity());
		CBaseEntity@ thirdPersonTarget = h_render_off;
		CBaseEntity@ hat = h_hat;
		
		if (hat !is null) {
			if (!h_watch_hat.IsValid()) {
				createCameraHat(); // update hat model or delete it
			} else {
				hat.pev.colormap = plr.pev.colormap;	
			}
		} else {
			// could search for hat ent here but that might lag.
			// it's needed to re-create the hat after doing "hat off" + "hat afro"
		}
		
		cam.pev.colormap = plr.pev.colormap;
		
		{
			Vector delta = plr.pev.origin - lastOrigin; 
			cam.pev.velocity = delta*0.05f*100.0f;
			
			lastOrigin = cam.pev.origin;
		}
		
		Math.MakeVectors( plr.pev.v_angle );
		
		if (thirdPersonTarget !is null) {
			if (isThirdPerson) {
				Vector idealPos = plr.pev.origin - g_Engine.v_forward*96 + g_Engine.v_up*16;
				
				TraceResult tr;
				g_Utility.TraceLine( plr.pev.origin, idealPos, ignore_monsters, null, tr );
				
				if (tr.fInOpen != 0) {
					g_EngineFuncs.SetView( plr.edict(), thirdPersonTarget.edict() );
					//thirdPersonTarget.pev.origin = tr.vecEndPos;
					//thirdPersonTarget.pev.angles = plr.pev.v_angle;
					
					float rot_x_diff = AngleDifference(plr.pev.v_angle.x, thirdPersonTarget.pev.angles.x);
					float rot_y_diff = AngleDifference(plr.pev.v_angle.y, thirdPersonTarget.pev.angles.y);
					
					Vector delta = tr.vecEndPos - lastThirdPersonOrigin; 
					thirdPersonTarget.pev.velocity = delta*0.05f*100.0f;
					thirdPersonTarget.pev.avelocity = Vector(rot_x_diff*10, rot_y_diff*10, 0);
				} else {
					g_EngineFuncs.SetView( plr.edict(), plr.edict() );
				}
			} else {
				thirdPersonTarget.pev.origin = plr.pev.origin;
			}
			
			lastThirdPersonOrigin = thirdPersonTarget.pev.origin;
		}
		
		cam.pev.netname = "Ghost:  " + plr.pev.netname +
					    "\nCorpse: " + (plr.GetObserver().HasCorpse() ? "Yes" : "No") +
					    "\nArmor:  " + int(plr.pev.armorvalue) +
					    "\nScore:    " + int(plr.pev.frags);
		
		if (isPlayerModel) {
			if (cam.pev.sequence != 10 || cam.pev.framerate != 0.25f) {
				cam.pev.sequence = 10;
				cam.pev.framerate = 0.25f;
			}
		
			
			
			// rotate lower body slower than upper body
			//float torsoAngle = AngleDifference(angle_y, cam.pev.angles.y) * (30.0f / 90.0f);
			// reverse angle looks better for the swimming animation (leaning into turns)
			float torsoAngle = AngleDifference(cam.pev.angles.y, plr.pev.v_angle.y) * (30.0f / 90.0f);
			torsoAngle = AngleDifference(cam.pev.angles.y, plr.pev.v_angle.y) * (30.0f / 90.0f);
		
			for (int k = 0; k < 4; k++) {
				cam.SetBoneController(k, torsoAngle);
			}
		}
		
		float angle_diff_x = AngleDifference(-plr.pev.v_angle.x, cam.pev.angles.x);
		float angle_diff_y = AngleDifference(plr.pev.v_angle.y, cam.pev.angles.y);
		cam.pev.avelocity = Vector(angle_diff_x*10, angle_diff_y*10, 0);
		
		if ((plr.pev.button & IN_USE) != 0) {
			sprayLogo();
		}
		if ((plr.pev.button & IN_ALT1) != 0 && nextThirdPersonToggle < g_Engine.time) {
			nextThirdPersonToggle = g_Engine.time + 0.5f;
			toggleThirdperson();
		}
		if (false && (plr.pev.button & IN_ATTACK) != 0) {
			shoot();
		}
	}
}