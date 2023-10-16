#include "GhostCam.h"
#include "mmlib.h"
#include "main.h"
#include "ghost_utils.h"

using namespace std;

GhostHat::GhostHat(EHandle hat, EHandle watchHat) {
	this->hat = hat;
	this->watchHat = watchHat;
}

GhostCam::GhostCam() {
	thirdPersonZoom = g_default_zoom;
}

GhostCam::GhostCam(CBasePlayer* plr) {
	init(plr);
}

void GhostCam::init(CBasePlayer* plr) {
	thirdPersonZoom = g_default_zoom;
	h_plr = plr;

	ghostId++;

	currentPlayerModel = getPlayerModel();

	RemoveEntity(h_cam);
	RemoveEntity(h_render_off);

	map<string, string> keys;
	keys["origin"] = vecToString(plr->pev->origin);
	keys["model"] = currentPlayerModel;
	keys["targetname"] = string(g_ent_prefix) + "cam_" + to_string(ghostId);
	keys["noise3"] = getPlayerUniqueId(plr->edict()); // for ghost collecting
	keys["rendermode"] = "1";
	keys["renderamt"] = to_string(g_renderamt);
	keys["spawnflags"] = "1";
	CBaseEntity* ghostCam = CreateEntity("monster_ghost", keys, true);

	if (!ghostCam) {
		println("Failed to create ghost entities");
		return;
	}

	ghostCam->pev->solid = SOLID_NOT;
	ghostCam->pev->movetype = MOVETYPE_NOCLIP;
	ghostCam->pev->takedamage = 0;
	ghostCam->pev->sequence = 0;
	ghostCam->pev->angles = plr->pev->v_angle;
	ghostCam->pev->iuser2 = plr->entindex(); // share owner with other plugins
	h_cam = ghostCam;

	isPlayerModel = string(STRING(ghostCam->pev->model)) != g_camera_model;
	if (isPlayerModel) {
		ghostCam->pev->noise = ALLOC_STRING(getPlayerUniqueId(plr->edict()).c_str()); // used by the emotes plugin to find this ent
	}

	map<string, string> rkeys;
	rkeys["target"] = string(STRING(ghostCam->pev->targetname));
	rkeys["origin"] = vecToString(plr->pev->origin);
	rkeys["targetname"] = string(g_ent_prefix) + "render_" + to_string(ghostId);
	rkeys["spawnflags"] = to_string(1 | 4 | 8 | 64); // no renderfx + no rendermode + no rendercolor + affect activator
	rkeys["renderamt"] = "0";
	CBaseEntity* hideGhostCam = CreateEntity("env_render_individual", rkeys, true);

	if (!hideGhostCam) {
		println("Failed to create ghost entities");
		return;
	}

	// making this ent "visible" so it can be used as a third person view target
	g_engfuncs.pfnSetModel(hideGhostCam->edict(), "sprites/saveme.spr");
	hideGhostCam->pev->rendermode = 1;
	hideGhostCam->pev->renderamt = 0;
	hideGhostCam->pev->movetype = MOVETYPE_NOCLIP;

	h_render_off = hideGhostCam;

	createCameraHat();

	if (showThirdPersonHelp) {
		PrintKeyBindingStringLong(plr, "+alt1 to toggle third-person\n+USE to spray");
		showThirdPersonHelp = false;
	}

	initialized = true;
	isThirdPerson = false;
	thirdPersonRot = Vector(0, 0, 0);
	thirdPersonZoom = g_default_zoom;
	lastOrigin = plr->pev->origin;
}

// true if this ghost should never be shown to this player
bool GhostCam::hiddenByOtherPlugin(CBasePlayer* plr) {
	CBaseEntity* cam = h_cam;
	if (cam) {
		return (cam->pev->iuser3 & (1 << (plr->entindex() & 31))) != 0;
	}

	return false;
}

void GhostCam::toggleThirdperson() {
	if (!isValid()) {
		return;
	}
	CBasePlayer* plr = (CBasePlayer*)(h_plr.GetEntity());
	CBaseEntity* hideGhostCam = h_render_off;

	isThirdPerson = !isThirdPerson;
	if (isThirdPerson) {
		g_engfuncs.pfnSetView(plr->edict(), hideGhostCam->edict());
		if (!hiddenByOtherPlugin(plr)) {
			Use(hideGhostCam->edict(), plr->edict(), plr->edict(), USE_OFF);
		}

		if (showCameraHelp) {
			PrintKeyBindingStringLong(plr, "Hold +DUCK to adjust camera");
			showCameraHelp = false;
		}

		// reset camera smoothing
		hideGhostCam->pev->origin = plr->pev->origin;
		hideGhostCam->pev->angles = plr->pev->v_angle;
		hideGhostCam->pev->angles.x *= -1;
		lastThirdPersonOrigin = plr->pev->origin;
	}
	else {
		g_engfuncs.pfnSetView(plr->edict(), plr->edict());
		Use(hideGhostCam->edict(), plr->edict(), plr->edict(), USE_ON);
	}

	// signal to TooManyPolys that the view is first person and the LD model shouldn't be rendered
	h_cam.GetEdict()->v.iuser1 = !isThirdPerson ? 1 : 0;
}

void GhostCam::debug(CBasePlayer* plr) {
	debug_plr(plr, h_plr);

	conPrintln(plr->edict(), "    cam ents: " + (h_cam.IsValid() ? string(STRING(h_cam.GetEntity()->pev->targetname)) : "null") +
		", " + (h_render_off.IsValid() ? string(STRING(h_render_off.GetEntity()->pev->targetname)) : "null") +
		", " + to_string(ghostHats.size()));

	conPrintln(plr->edict(), string("    initialized: ") + (initialized ? "true" : "false") +
		", isPlayerModel: " + (isPlayerModel ? "true" : "false"));
}

string GhostCam::getPlayerModel() {
	CBasePlayer* plr = (CBasePlayer*)(h_plr.GetEntity());

	if (!plr || !getPlayerState(plr).enablePlayerModel)
		return g_camera_model;

	char* p_PlayerInfo = g_engfuncs.pfnGetInfoKeyBuffer(plr->edict());
	string playerModel = toLowerCase(g_engfuncs.pfnInfoKeyValue(p_PlayerInfo,"model"));

	if (g_player_model_precache.count(playerModel)) {
		return "models/player/" + playerModel + "/" + playerModel + ".mdl";
	}

	return g_camera_model;
}

// custom keyvalues cause crashes, so this just searches for any models attached to the plater which are most likely hats
vector<edict_t*> GhostCam::getPlayerHats() {
	vector<edict_t*> hats;

	if (!h_plr.IsValid())
		return hats;

	CBaseEntity* plr = h_plr;

	edict_t* ent = NULL;
	do {
		ent = g_engfuncs.pfnFindEntityByString(ent, "classname", "info_target");
		if (isValidFindEnt(ent))
		{
			if (ent->v.aiment == plr->edict() && string(STRING(ent->v.model)).find("hat") != string::npos) {
				hats.push_back(ent);
			}
		}
	} while (isValidFindEnt(ent));

	return hats;
}

void GhostCam::createCameraHat() {
	for (int i = 0; i < ghostHats.size(); i++) {
		RemoveEntity(ghostHats[i].hat);
	}
	ghostHats.resize(0);

	vector<edict_t*> playerHats = getPlayerHats();
	if (playerHats.size() == 0) {
		return;
	}

	for (int i = 0; i < playerHats.size(); i++) {
		CBaseEntity* cam = h_cam;

		map<string, string> keys;
		keys["origin"] = vecToString(cam->pev->origin);
		keys["model"] = STRING(playerHats[i]->v.model);
		keys["targetname"] = STRING(cam->pev->targetname);
		keys["rendermode"] = "1";
		keys["renderamt"] = to_string(g_renderamt);
		keys["spawnflags"] = "1";
		CBaseEntity* camHat = CreateEntity("env_sprite", keys, true);

		if (!camHat) {
			println("Failed to create ghost entities");
			return;
		}

		camHat->pev->movetype = MOVETYPE_FOLLOW;
		camHat->pev->aiment = cam->edict();

		camHat->pev->sequence = playerHats[i]->v.sequence;
		camHat->pev->body = playerHats[i]->v.body;
		camHat->pev->framerate = playerHats[i]->v.framerate;
		camHat->pev->colormap = cam->pev->colormap;

		ghostHats.push_back(GhostHat(camHat, playerHats[i]));
	}
}

void GhostCam::updateVisibility(const vector<PlayerWithState>& playersWithStates) {
	if (!isValid()) {
		return;
	}

	CBaseEntity* plr = h_plr;
	CBaseEntity* hideGhostCam = h_render_off;

	for (int i = 0; i < playersWithStates.size(); i++)
	{
		CBasePlayer* statePlr = playersWithStates[i].plr;
		PlayerState* state = playersWithStates[i].state;

		if (statePlr->entindex() == plr->entindex())
			continue;

		if (state->shouldSeeGhosts(statePlr)) {
			if (!hiddenByOtherPlugin(statePlr)) {
				Use(hideGhostCam->edict(), statePlr->edict(), statePlr->edict(), USE_OFF);
			}
		}
		else {
			Use(hideGhostCam->edict(), statePlr->edict(), statePlr->edict(), USE_ON);
		}
	}

	// always hide observer's own camera
	if (!isThirdPerson)
		Use(hideGhostCam->edict(), plr->edict(), plr->edict(), USE_ON);
}

void GhostCam::updateModel() {
	if (!isValid()) {
		return;
	}

	CBasePlayer* plr = (CBasePlayer*)(h_plr.GetEntity());
	CBaseEntity* cam = h_cam;

	currentPlayerModel = getPlayerModel();
	g_engfuncs.pfnSetModel(cam->edict(), (g_use_player_models ? currentPlayerModel : g_camera_model).c_str());
	createCameraHat();

	isPlayerModel = string(STRING(cam->pev->model)) != g_camera_model;
	cam->pev->noise = ALLOC_STRING((isPlayerModel ? getPlayerUniqueId(plr->edict()) : "").c_str());
	if (!isPlayerModel) {
		cam->pev->sequence = 0;
	}
}

void GhostCam::toggleFlashlight() {
	CBaseEntity* cam = h_cam;
	if (cam) {
		cam->pev->effects |= 12;
	}
}

void GhostCam::sprayLogo() {
	if (!isValid()) {
		return;
	}
	CBasePlayer* plr = (CBasePlayer*)(h_plr.GetEntity());

	if (plr->m_flNextDecalTime > gpGlobals->time) {
		return;
	}

	MAKE_VECTORS(plr->pev->v_angle);
	Vector lookDir = gpGlobals->v_forward;
	TraceResult tr;
	TRACE_LINE(plr->pev->origin, plr->pev->origin + lookDir * 128, ignore_monsters, NULL, &tr);

	if (tr.flFraction < 1.0f) {
		println("HIT %s", STRING(tr.pHit->v.classname));
		plr->m_flNextDecalTime = gpGlobals->time + g_engfuncs.pfnCVarGetFloat("decalfrequency");
		te_playerdecal(tr.vecEndPos, plr->edict(), tr.pHit);
		PlaySound(plr->edict(), CHAN_STATIC, "player/sprayer.wav", 0.25f, 0.1f, plr->entindex(), 100);
	}

}

void GhostCam::shoot(bool medic) {
	if (!isValid()) {
		return;
	}
	CBaseEntity* plr = h_plr;
	CBaseEntity* cam = h_cam;

	MAKE_VECTORS(plr->pev->v_angle);
	Vector lookDir = gpGlobals->v_forward;

	vector<PlayerWithState> playersWithStates = getPlayersWithState();
	for (int i = 0; i < playersWithStates.size(); i++)
	{
		CBasePlayer* statePlr = playersWithStates[i].plr;
		PlayerState* dstate = playersWithStates[i].state;

		if (!dstate->shouldSeeGhosts(statePlr)) {
			continue;
		}

		if (medic) {
			te_projectile(plr->pev->origin + Vector(0, 0, -12), lookDir * 512, NULL, "sprites/saveme.spr", 1, MSG_ONE_UNRELIABLE, statePlr->edict());
			PlaySound(plr->edict(), CHAN_STATIC, "speech/saveme1.wav", 0.1f, 1.0f, 0, 100, statePlr->entindex());
		}
		else {
			te_projectile(plr->pev->origin + Vector(0, 0, -12), lookDir * 512, NULL, "sprites/grenade.spr", 1, MSG_ONE_UNRELIABLE, statePlr->edict());
			PlaySound(plr->edict(), CHAN_STATIC, "speech/grenade1.wav", 0.1f, 1.0f, 0, 100, statePlr->entindex());
		}
	}
}

bool GhostCam::isValid() {
	if (h_plr.IsValid()) {
		CBasePlayer* plr = (CBasePlayer*)(h_plr.GetEntity());
		if (!plr || !plr->IsConnected() || plr->IsAlive() || !plr->IsObserver()) {
			return false;
		}
	}
	else {
		return false;
	}

	return h_cam.IsValid() && h_render_off.IsValid();
}

void GhostCam::remove() {
	if (isThirdPerson) {
		toggleThirdperson();
	}
	if (h_cam.IsValid()) {
		CBaseEntity* cam = h_cam;

		vector<PlayerWithState> playersWithStates = getPlayersWithState();
		for (int i = 0; i < playersWithStates.size(); i++)
		{
			CBasePlayer* plr = playersWithStates[i].plr;
			PlayerState* state = playersWithStates[i].state;

			// poof effect
			if (state->shouldSeeGhosts(plr)) {
				int scale = isPlayerModel ? 10 : 4;
				te_smoke(cam->pev->origin - Vector(0, 0, 24), "sprites/steam1.spr", scale, 40, MSG_ONE_UNRELIABLE, plr->edict());
				PlaySound(cam->edict(), CHAN_STATIC, "player/pl_organic2.wav", 0.8f, 1.0f, 0, 50, plr->entindex());
			}
		}
	}
	
	RemoveEntity(h_render_off);
	RemoveEntity(h_cam);

	for (int i = 0; i < ghostHats.size(); i++) {
		RemoveEntity(ghostHats[i].hat);
	}

	initialized = false;
}

void GhostCam::think() {
	if (!isValid()) {
		if (initialized) {
			remove();
		}
		return;
	}

	CBasePlayer* plr = (CBasePlayer*)(h_plr.GetEntity());
	CBaseMonster* cam = (CBaseMonster*)(h_cam.GetEntity());
	CBaseEntity* thirdPersonTarget = h_render_off;

	for (int i = 0; i < ghostHats.size(); i++) {
		CBaseEntity* hat = ghostHats[i].hat;

		if (hat) {
			if (!ghostHats[i].watchHat.IsValid()) {
				createCameraHat(); // update hat model or delete it
			}
			else {
				hat->pev->colormap = plr->pev->colormap;
			}
		}
		else {
			// could search for hat ent here but that might lag.
			// it's needed to re-create the hat after doing "hat off" + "hat afro"
		}
	}


	// detect if player is in roaming mode
	/*
	edict_t* oberverTarget = plr->GetObserverTarget();
	if (oberverTarget) {
		bool freeRoam = oberverTarget->v.velocity.Length() > 1 && lastPlayerOrigin == plr->pev->origin;
		if (freeRoam) {
			freeRoamCount++;
			if (freeRoamCount >= 4) {
				// clear target to indicate player is free roaming
				plr.GetObserver().SetObserverTarget(null);
				freeRoamCount = 0;
			}
		}
		else {
			freeRoamCount = 0;
		}
	}
	*/

	MAKE_VECTORS(plr->pev->v_angle);
	Vector playerForward = gpGlobals->v_forward;

	// adjust third-person camera
	if (isThirdPerson && (plr->pev->button & IN_RELOAD) != 0) {
		thirdPersonRot = Vector(0, 0, 0);
		thirdPersonZoom = g_default_zoom;
	}
	if (isThirdPerson && (plr->pev->button & IN_DUCK) != 0) {
		if (showCameraCtrlHelp) {
			PrintKeyBindingStringLong(plr, "+FORWARD and +BACK to zoom\n+RELOAD to reset");
			showCameraCtrlHelp = false;
		}
		thirdPersonRot = thirdPersonRot + (plr->pev->v_angle - lastPlayerAngles);
		if (thirdPersonRot.y > 180) {
			thirdPersonRot.y -= 360;
		}
		else if (thirdPersonRot.y < -180) {
			thirdPersonRot.y += 360;
		}
		if ((plr->pev->button & IN_FORWARD) != 0) {
			thirdPersonZoom -= 16.0f;
		}
		if ((plr->pev->button & IN_BACK) != 0) {
			thirdPersonZoom += 16.0f;
		}
		if (thirdPersonZoom < g_min_zoom)
			thirdPersonZoom = g_min_zoom;
		else if (thirdPersonZoom > g_max_zoom) {
			thirdPersonZoom = g_max_zoom;
		}

		plr->pev->angles = lastPlayerAngles;
		plr->pev->v_angle = lastPlayerAngles;
		plr->pev->fixangle = FAM_FORCEVIEWANGLES;
		plr->pev->origin = lastPlayerOrigin;
	}
	lastPlayerAngles = plr->pev->v_angle;
	lastPlayerOrigin = plr->pev->origin;

	bool isPlayingEmote = cam->pev->iuser4 != 0;
	Vector modelTargetPos = plr->pev->origin;
	if (isPlayerModel && !isPlayingEmote) {
		// center player model head at view origin (wont work for tall/short models)
		modelTargetPos = modelTargetPos + gpGlobals->v_forward * -28 + gpGlobals->v_up * -9;
	}

	Vector delta = modelTargetPos - lastOrigin;
	cam->pev->velocity = delta * 0.05f * 100.0f;

	lastOrigin = cam->pev->origin;

	// update third-person perspective origin/angles
	if ((isThirdPerson || g_stress_test) && thirdPersonTarget) {
		Vector plrAngles = plr->pev->v_angle;

		// invert camera up/down rotation when camera is in front of the player (hard to control)
		/*
		if (thirdPersonRot.y > 90 || thirdPersonRot.y < -90)
			plrAngles.x *= -1;
		*/

		MAKE_VECTORS(plrAngles + thirdPersonRot);

		Vector offset = (gpGlobals->v_forward * 96 + gpGlobals->v_up * -24).Normalize() * thirdPersonZoom;

		Vector idealPos = modelTargetPos - offset;

		TraceResult tr;
		TRACE_LINE(modelTargetPos, idealPos, ignore_monsters, NULL, &tr);

		if (tr.fInOpen != 0) {
			//g_engfuncs.pfnSetView(plr->edict(), thirdPersonTarget->edict());

			Vector targetAngles = plrAngles + thirdPersonRot;

			float rot_x_diff = AngleDifference(targetAngles.x, thirdPersonTarget->pev->angles.x);
			float rot_y_diff = AngleDifference(targetAngles.y, thirdPersonTarget->pev->angles.y);

			Vector delta2 = tr.vecEndPos - lastThirdPersonOrigin;
			thirdPersonTarget->pev->velocity = delta2 * 0.05f * 100.0f;
			thirdPersonTarget->pev->avelocity = Vector(rot_x_diff * 10, rot_y_diff * 10, 0);
		}
		else {
			//g_engfuncs.pfnSetView(plr->edict(), plr->edict());
		}

		lastThirdPersonOrigin = thirdPersonTarget->pev->origin;
	}

	cam->pev->colormap = plr->pev->colormap;

	string hudName = string("Ghost:  ") + STRING(plr->pev->netname) +
		//"\nCorpse: " + (plr.GetObserver().HasCorpse() ? "Yes" : "No") +
		//"\nArmor:  " + int(plr->pev->armorvalue) +
		"\nMode:   " + to_string(getPlayerState(plr).visbilityMode);
	strncpy(netname, hudName.c_str(), 64);

	cam->pev->netname = MAKE_STRING(netname);

	// reverse angle looks better for the swimming animation (leaning into turns)
	float torsoAngle = AngleDifference(cam->pev->angles.y, plr->pev->v_angle.y) * (30.0f / 90.0f);
	torsoAngle = AngleDifference(cam->pev->angles.y, plr->pev->v_angle.y) * (30.0f / 90.0f);
	float ideal_z_rot = torsoAngle * 4;

	if (isPlayerModel) {
		if (cam->pev->sequence != 10 || cam->pev->framerate != 0.25f) {
			if (!isPlayingEmote) {
				// reset to swim animation if no emote is playing
				cam->m_Activity = ACT_RELOAD;
				cam->pev->sequence = 10;
				cam->pev->frame = 0;
				cam->ResetSequenceInfo();
				cam->pev->framerate = 0.25f;
			}
		}

		for (int k = 0; k < 4; k++) {
			cam->SetBoneController(k, torsoAngle);
		}
	}

	float angle_diff_x = AngleDifference(-plr->pev->v_angle.x, cam->pev->angles.x);
	float angle_diff_y = AngleDifference(plr->pev->v_angle.y, cam->pev->angles.y);
	float angle_diff_z = AngleDifference(ideal_z_rot, cam->pev->angles.z);
	cam->pev->avelocity = Vector(angle_diff_x * 10, angle_diff_y * 10, angle_diff_z * 10);

	if ((plr->pev->button & IN_USE) != 0) {
		sprayLogo();
	}
	if ((plr->pev->button & IN_ALT1) != 0 && nextThirdPersonToggle < gpGlobals->time) {
		nextThirdPersonToggle = gpGlobals->time + 0.5f;
		toggleThirdperson();
	}
	if (g_fun_mode && (plr->pev->button & IN_ATTACK) != 0) {
		shoot(true);
	}
	if (g_fun_mode && (plr->pev->button & IN_ATTACK2) != 0) {
		shoot(false);
	}
	if (g_fun_mode && (plr->pev->button & IN_ATTACK2) != 0) {
		shoot(false);
	}

	string newModel = getPlayerModel();
	if (newModel != currentPlayerModel) {
		updateModel();
	}

	if (g_stress_test) {
		plr->pev->v_angle = plr->pev->v_angle;
		plr->pev->v_angle.y += RANDOM_LONG(0, 10);
		plr->pev->v_angle.x += RANDOM_LONG(0, 10);
		plr->pev->fixangle = FAM_FORCEVIEWANGLES;
	}

	if (uint32(cam->pev->iuser3) != lastOtherPluginVisible) {
		updateVisibility(getPlayersWithState());
	}
	lastOtherPluginVisible = cam->pev->iuser3;
}
