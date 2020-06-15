float g_renderamt = 96;
float g_min_zoom = 0;
float g_max_zoom = 1024;
float g_default_zoom = 96;

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
	Vector lastPlayerOrigin; // for third person zooming
	Vector lastPlayerAngles; // for rotating third person cam
	Vector thirdPersonRot;
	float thirdPersonZoom = g_default_zoom;
	bool showCameraHelp = true;
	bool showCameraCtrlHelp = true;
	bool showThirdPersonHelp = true;
	string currentPlayerModel;
	int freeRoamCount = 0; // use to detect if ghost is free roaming (since there's no method to check mode)
	
	GhostCam() {}
	
	GhostCam(CBasePlayer@ plr) {
		init(plr);
	}
	
	void init(CBasePlayer@ plr) {
		h_plr = plr;
		
		ghostId++;
		
		currentPlayerModel = getPlayerModel();
		
		dictionary keys;
		keys["origin"] = plr.pev.origin.ToString();
		keys["model"] = isPlayerModel ? currentPlayerModel : g_camera_model;
		keys["targetname"] = g_ent_prefix + ghostId;
		keys["noise3"] = getPlayerUniqueId(plr); // set an id on the ent for internal use only
		keys["rendermode"] = "1";
		keys["renderamt"] = "" + g_renderamt;
		keys["spawnflags"] = "1";
		CBaseEntity@ ghostCam = g_EntityFuncs.CreateEntity("cycler", keys, true);
		ghostCam.pev.solid = SOLID_NOT;
		ghostCam.pev.movetype = MOVETYPE_NOCLIP;
		ghostCam.pev.takedamage = 0;
		ghostCam.pev.angles = plr.pev.v_angle;
		h_cam = ghostCam;

		isPlayerModel = string(ghostCam.pev.model) != g_camera_model;
		if (isPlayerModel) {
			ghostCam.pev.noise = getPlayerUniqueId(plr); // used by the emotes plugin to find this ent
		}

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
		
		if (showThirdPersonHelp) {
			g_PlayerFuncs.PrintKeyBindingString(plr, "+alt1 to toggle third-person\n+USE to spray");
			showThirdPersonHelp = false;
		}
		
		initialized = true;
		isThirdPerson = false;
		thirdPersonRot = Vector(0,0,0);
		thirdPersonZoom = g_default_zoom;
		lastOrigin = plr.pev.origin;
	}
	
	void toggleThirdperson() {
		if (!isValid()) {
			return;
		}
		CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
		CBaseEntity@ hideGhostCam = h_render_off;
		
		isThirdPerson = !isThirdPerson;
		if (isThirdPerson) {
			g_EngineFuncs.SetView( h_plr.GetEntity().edict(), h_render_off.GetEntity().edict() );
			hideGhostCam.Use(plr, plr, USE_OFF);
			
			if (showCameraHelp) {
				g_PlayerFuncs.PrintKeyBindingString(plr, "Hold +DUCK to adjust camera");
				showCameraHelp = false;
			}
			
			// reset camera smoothing
			hideGhostCam.pev.origin = plr.pev.origin;
			hideGhostCam.pev.angles = plr.pev.v_angle;
			hideGhostCam.pev.angles.x *= -1;
			lastThirdPersonOrigin = plr.pev.origin;
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
			return g_camera_model;
	
		KeyValueBuffer@ p_PlayerInfo = g_EngineFuncs.GetInfoKeyBuffer( plr.edict() );
		string playerModel = p_PlayerInfo.GetValue( "model" ).ToLowercase();
		
		if (g_player_model_precache.exists(playerModel)) {
			return "models/player/" + playerModel + "/" + playerModel + ".mdl";
		}
		
		return g_camera_model;
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
	
	void updateVisibility(array<PlayerWithState@> playersWithStates) {
		if (!isValid()) {
			return;
		}
		
		CBaseEntity@ plr = h_plr;
		CBaseEntity@ hideGhostCam = h_render_off;
		
		for (uint i = 0; i < playersWithStates.length(); i++)
		{
			CBasePlayer@ statePlr = playersWithStates[i].plr;
			PlayerState@ state = playersWithStates[i].state;
			
			if (statePlr.entindex() == plr.entindex())
				continue;

			if (state.shouldSeeGhosts(statePlr)) {
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
		
		CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
		CBaseEntity@ cam = h_cam;
		
		currentPlayerModel = getPlayerModel();
		g_EntityFuncs.Remove(h_hat);
		g_EntityFuncs.SetModel(cam, g_use_player_models ? currentPlayerModel : g_camera_model);
		createCameraHat();
		
		isPlayerModel = string(cam.pev.model) != g_camera_model;
		cam.pev.noise = isPlayerModel ? getPlayerUniqueId(plr) : "";
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
	
	void shoot(bool medic) {
		if (!isValid()) {
			return;
		}
		CBaseEntity@ plr = h_plr;
		CBaseEntity@ cam = h_cam;

		Math.MakeVectors( plr.pev.v_angle );
		Vector lookDir = g_Engine.v_forward;
		
		array<PlayerWithState@> playersWithStates = getPlayersWithState();
		for (uint i = 0; i < playersWithStates.length(); i++)
		{
			CBasePlayer@ statePlr = playersWithStates[i].plr;
			PlayerState@ dstate = playersWithStates[i].state;
			
			if (!dstate.shouldSeeGhosts(statePlr)) {
				continue;
			}
			
			if (medic) {
				te_projectile(plr.pev.origin + Vector(0,0, -12), lookDir*512, null, "sprites/saveme.spr", 1,  MSG_ONE_UNRELIABLE, statePlr.edict());
				g_SoundSystem.PlaySound( plr.edict(), CHAN_STATIC, "speech/saveme1.wav", 0.1f, 1.0f, 0, 100, statePlr.entindex());
			} else {
				te_projectile(plr.pev.origin + Vector(0,0, -12), lookDir*512, null, "sprites/grenade.spr", 1,  MSG_ONE_UNRELIABLE, statePlr.edict());
				g_SoundSystem.PlaySound( plr.edict(), CHAN_STATIC, "speech/grenade1.wav", 0.1f, 1.0f, 0, 100, statePlr.entindex());
			}
		}
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
			
			array<PlayerWithState@> playersWithStates = getPlayersWithState();
			for (uint i = 0; i < playersWithStates.length(); i++)
			{
				CBasePlayer@ plr = playersWithStates[i].plr;
				PlayerState@ state = playersWithStates[i].state;
				
				// poof effect
				if (state.shouldSeeGhosts(plr)) {
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
		
		// detect if player is in roaming mode
		CBaseEntity@ oberverTarget = plr.GetObserver().GetObserverTarget();
		if (oberverTarget !is null) {
			bool freeRoam = oberverTarget.pev.velocity.Length() > 1 && lastPlayerOrigin == plr.pev.origin;
			if (freeRoam) {
				freeRoamCount++;
				if (freeRoamCount >= 4) {
					// clear target to indicate player is free roaming
					plr.GetObserver().SetObserverTarget(null);
					freeRoamCount = 0;
				}
			} else {
				freeRoamCount = 0;
			}		
		}
		
		Math.MakeVectors( plr.pev.v_angle );
		Vector playerForward = g_Engine.v_forward;
		
		// adjust third-person camera
		if (isThirdPerson && (plr.pev.button & IN_RELOAD) != 0) {
			thirdPersonRot = Vector(0,0,0);
			thirdPersonZoom = g_default_zoom;
		}
		if (isThirdPerson && (plr.pev.button & IN_DUCK) != 0) {
			if (showCameraCtrlHelp) {
				g_PlayerFuncs.PrintKeyBindingString(plr, "+FORWARD and +BACK to zoom\n+RELOAD to reset");
				showCameraCtrlHelp = false;
			}
			thirdPersonRot = thirdPersonRot + (plr.pev.v_angle - lastPlayerAngles);
			if (thirdPersonRot.y > 180) {
				thirdPersonRot.y -= 360;
			} else if (thirdPersonRot.y < -180) {
				thirdPersonRot.y += 360;
			}
			if ((plr.pev.button & IN_FORWARD) != 0) {
				thirdPersonZoom -= 16.0f;
			}
			if ((plr.pev.button & IN_BACK) != 0) {
				thirdPersonZoom += 16.0f;
			}
			if (thirdPersonZoom < g_min_zoom)
				thirdPersonZoom = g_min_zoom;
			else if (thirdPersonZoom > g_max_zoom) {
				thirdPersonZoom = g_max_zoom;
			}
			
			plr.pev.angles = lastPlayerAngles;
			plr.pev.v_angle = lastPlayerAngles;
			plr.pev.fixangle = FAM_FORCEVIEWANGLES;
			plr.pev.origin = lastPlayerOrigin;
		}
		lastPlayerAngles = plr.pev.v_angle;
		lastPlayerOrigin = plr.pev.origin;
		
		bool isPlayingEmote = string(cam.pev.noise1) == "emote";
		Vector modelTargetPos = plr.pev.origin;
		if (isPlayerModel && !isPlayingEmote) {
			// center player model head at view origin (wont work for tall/short models)
			modelTargetPos = modelTargetPos + g_Engine.v_forward*-28 + g_Engine.v_up*-9;
		}
		
		Vector delta = modelTargetPos - lastOrigin; 
		cam.pev.velocity = delta*0.05f*100.0f;
		
		lastOrigin = cam.pev.origin;
		
		// update third-person perspective origin/angles
		if ((isThirdPerson || g_stress_test) && thirdPersonTarget !is null) {			
			Vector plrAngles = plr.pev.v_angle;
			
			// invert camera up/down rotation when camera is in front of the player (hard to control)
			/*
			if (thirdPersonRot.y > 90 || thirdPersonRot.y < -90) 
				plrAngles.x *= -1;
			*/
					
			Math.MakeVectors(plrAngles + thirdPersonRot);
			
			Vector offset = (g_Engine.v_forward*96 + g_Engine.v_up*-24).Normalize() * thirdPersonZoom;
			
			Vector idealPos = modelTargetPos - offset;
			
			TraceResult tr;
			g_Utility.TraceLine( modelTargetPos, idealPos, ignore_monsters, null, tr );
			
			if (tr.fInOpen != 0) {
				g_EngineFuncs.SetView( plr.edict(), thirdPersonTarget.edict() );
				
				Vector targetAngles = plrAngles + thirdPersonRot;
				
				float rot_x_diff = AngleDifference(targetAngles.x, thirdPersonTarget.pev.angles.x);
				float rot_y_diff = AngleDifference(targetAngles.y, thirdPersonTarget.pev.angles.y);
				
				Vector delta2 = tr.vecEndPos - lastThirdPersonOrigin; 
				thirdPersonTarget.pev.velocity = delta2*0.05f*100.0f;
				thirdPersonTarget.pev.avelocity = Vector(rot_x_diff*10, rot_y_diff*10, 0);
			} else {
				g_EngineFuncs.SetView( plr.edict(), plr.edict() );
			}
			
			lastThirdPersonOrigin = thirdPersonTarget.pev.origin;
		}
		
		cam.pev.colormap = plr.pev.colormap;
		cam.pev.netname = "Ghost:  " + plr.pev.netname +
					    "\nCorpse: " + (plr.GetObserver().HasCorpse() ? "Yes" : "No") +
						"\nArmor:  " + int(plr.pev.armorvalue);
		
		// reverse angle looks better for the swimming animation (leaning into turns)
		float torsoAngle = AngleDifference(cam.pev.angles.y, plr.pev.v_angle.y) * (30.0f / 90.0f);
		torsoAngle = AngleDifference(cam.pev.angles.y, plr.pev.v_angle.y) * (30.0f / 90.0f);
		float ideal_z_rot = torsoAngle*4;
		
		if (isPlayerModel) {
			if (cam.pev.sequence != 10 || cam.pev.framerate != 0.25f) {
				if (!isPlayingEmote) {
					// reset to swim animation if no emote is playing
					cam.m_Activity = ACT_RELOAD;
					cam.pev.sequence = 10;
					cam.pev.frame = 0;
					cam.ResetSequenceInfo();
					cam.pev.framerate = 0.25f;
				}
			}
		
			for (int k = 0; k < 4; k++) {
				cam.SetBoneController(k, torsoAngle);
			}
		}
		
		float angle_diff_x = AngleDifference(-plr.pev.v_angle.x, cam.pev.angles.x);
		float angle_diff_y = AngleDifference(plr.pev.v_angle.y, cam.pev.angles.y);
		float angle_diff_z = AngleDifference(ideal_z_rot, cam.pev.angles.z);
		cam.pev.avelocity = Vector(angle_diff_x*10, angle_diff_y*10, angle_diff_z*10);
		
		if ((plr.pev.button & IN_USE) != 0) {
			sprayLogo();
		}
		if ((plr.pev.button & IN_ALT1) != 0 && nextThirdPersonToggle < g_Engine.time) {
			nextThirdPersonToggle = g_Engine.time + 0.5f;
			toggleThirdperson();
		}
		if (g_fun_mode && (plr.pev.button & IN_ATTACK) != 0) {
			shoot(true);
		}
		if (g_fun_mode && (plr.pev.button & IN_ATTACK2) != 0) {
			shoot(false);
		}
		if (g_fun_mode && (plr.pev.button & IN_ATTACK2) != 0) {
			shoot(false);
		}
		
		string newModel = getPlayerModel();
		if (newModel != currentPlayerModel) {
			updateModel();
		}
		
		if (g_stress_test) {
			plr.pev.v_angle = plr.pev.v_angle;
			plr.pev.v_angle.y += Math.RandomLong(0, 10);
			plr.pev.v_angle.x += Math.RandomLong(0, 10);
			plr.pev.fixangle = FAM_FORCEVIEWANGLES;
		}
	}
}