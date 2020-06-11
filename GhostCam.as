
class GhostCam
{
	EHandle h_plr;
	EHandle h_cam;
	EHandle h_render_off;
	EHandle h_hat;
	EHandle h_watch_hat; // hat entity created by the hats plugin
	float renderAmt = 64;
	bool initialized = false;
	Vector lastOrigin;
	
	GhostCam() {}
	
	GhostCam(CBasePlayer@ plr) {
		init(plr);
	}
	
	void init(CBasePlayer@ plr) {
		h_plr = plr;
	
		KeyValueBuffer@ p_PlayerInfo = g_EngineFuncs.GetInfoKeyBuffer( plr.edict() );
		string playerModel = p_PlayerInfo.GetValue( "model" ).ToLowercase();
		
		if (g_player_model_precache.exists(playerModel)) {
			playerModel = "models/player/" + playerModel + "/" + playerModel + ".mdl";
		} else {
			playerModel = "models/player.mdl";
		}
		
		dictionary keys;
		keys["origin"] = plr.pev.origin.ToString();
		keys["model"] = cvar_use_player_models.GetInt() != 0 ? playerModel : g_camera_model;
		keys["targetname"] = g_ent_prefix + ghostId++;
		keys["netname"] = string(plr.pev.netname);
		keys["rendermode"] = "1";
		keys["renderamt"] = "" + renderAmt;
		keys["spawnflags"] = "1";
		CBaseEntity@ ghostCam = g_EntityFuncs.CreateEntity("cycler", keys, true);		
		ghostCam.pev.solid = SOLID_NOT;
		ghostCam.pev.movetype = MOVETYPE_NOCLIP;
		ghostCam.pev.takedamage = 0;
		h_cam = ghostCam;

		dictionary rkeys;
		rkeys["target"] = string(ghostCam.pev.targetname);
		rkeys["spawnflags"] = "" + (1 | 4 | 8 | 64); // no renderfx + no rendermode + no rendercolor + affect activator
		rkeys["renderamt"] = "0";
		CBaseEntity@ hideGhostCam = g_EntityFuncs.CreateEntity("env_render_individual", rkeys, true);
		h_render_off = hideGhostCam;

		createCameraHat();
		
		initialized = true;
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
		keys["renderamt"] = "" + renderAmt;
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
			CBasePlayer@ statePlr = cast<CBasePlayer@>(state.plr.GetEntity());
			
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
		hideGhostCam.Use(plr, plr, USE_ON);
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
		if (h_cam.IsValid()) {
			CBaseEntity@ cam = h_cam;
			
			array<string>@ stateKeys = g_player_states.getKeys();
			for (uint i = 0; i < stateKeys.length(); i++)
			{
				PlayerState@ state = cast<PlayerState@>( g_player_states[stateKeys[i]] );
				CBaseEntity@ plr = state.plr;
				if (plr !is null && state.shouldSeeGhosts()) {
					int scale = cvar_use_player_models.GetInt() != 0 ? 10 : 4;
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
		cam.pev.origin = plr.pev.origin;
		
		cam.pev.netname = "Ghost:  " + plr.pev.netname +
					    "\nCorpse: " + (plr.GetObserver().HasCorpse() ? "Yes" : "No") +
					    "\nArmor:  " + int(plr.pev.armorvalue) +
					    "\nScore:    " + int(plr.pev.frags);
		
		if (cvar_use_player_models.GetInt() != 0) {
			cam.pev.sequence = 10;
			cam.pev.framerate = 0.25f;
		
			float angle_y = plr.pev.v_angle.y;
			float angle_x = -plr.pev.v_angle.x;
			
			// rotate lower body slower than upper body
			//float torsoAngle = AngleDifference(angle_y, cam.pev.angles.y) * (30.0f / 90.0f);
			// reverse angle looks better for the swimming animation (leaning into turns)
			float torsoAngle = AngleDifference(cam.pev.angles.y, angle_y) * (30.0f / 90.0f);
			cam.pev.angles.y -= torsoAngle*0.75f;
			torsoAngle = AngleDifference(cam.pev.angles.y, angle_y) * (30.0f / 90.0f);
		
			for (int k = 0; k < 4; k++) {
				cam.SetBoneController(k, torsoAngle);
			}

			//cam.SetBlending(0, angle_x);
			cam.pev.angles.x = angle_x;
			
			
			// attachement point isn't consistent across all models
			/*
			Vector attachPoint;
			Vector attachAngles;
			cam.GetAttachment(4, attachPoint, attachAngles);
			cam.pev.origin = cam.pev.origin + (cam.pev.origin - attachPoint);
			*/
			
			//cam.pev.frame = 0;
			//cam.ResetSequenceInfo();
			//cam.pev.framerate = 1.0f;
		} else {
			cam.pev.angles = plr.pev.v_angle;
			cam.pev.angles.x = -cam.pev.angles.x;
		}
		
		if ((plr.pev.button & IN_USE) != 0) {
			sprayLogo();
		}
		if (false && (plr.pev.button & IN_ATTACK2) != 0) {
			shoot();
		}
	}
}