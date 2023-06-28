#pragma once
#include "private_api.h"
#include <vector>
#include <string>

class PlayerState;

// to be used within a single server frame
class PlayerWithState {
public:
	CBasePlayer* plr;
	PlayerState* state;

	PlayerWithState(CBasePlayer* plr, PlayerState* state);
};

class GhostHat {
public:
	EHandle hat; // hat attached to the ghost entity
	EHandle watchHat; // hat created by the hats plugin

	GhostHat() {}

	GhostHat(EHandle hat, EHandle watchHat);
};

class GhostCam {
public:
	EHandle h_plr;
	EHandle h_cam;
	EHandle h_render_off; // also used as a thirdperson view target
	std::vector<GhostHat> ghostHats;
	bool initialized = false;
	bool isPlayerModel;
	bool isThirdPerson = false;
	float nextThirdPersonToggle = 0;
	Vector lastOrigin;
	Vector lastThirdPersonOrigin;
	Vector lastPlayerOrigin; // for third person zooming
	Vector lastPlayerAngles; // for rotating third person cam
	Vector thirdPersonRot;
	float thirdPersonZoom = 512;
	bool showCameraHelp = true;
	bool showCameraCtrlHelp = true;
	bool showThirdPersonHelp = true;
	std::string currentPlayerModel;
	//int freeRoamCount = 0; // use to detect if ghost is free roaming (since there's no method to check mode)

	uint32 isVisible; // bitfield indicating which players can see this ghost
	uint32 lastOtherPluginVisible; // last value of the visibility bitfield set by other plguins

	// avoiding the use of ALLOC_STRING every Think
	char netname[64];

	GhostCam();

	GhostCam(CBasePlayer* plr);

	void init(CBasePlayer* plr);

	// true if this ghost should never be shown to this player
	bool hiddenByOtherPlugin(CBasePlayer* plr);

	void toggleThirdperson();

	void debug(CBasePlayer* plr);

	std::string getPlayerModel();

	// custom keyvalues cause crashes, so this just searches for any models attached to the plater which are most likely hats
	std::vector<edict_t*> getPlayerHats();

	void createCameraHat();

	void updateVisibility(const std::vector<PlayerWithState>& playersWithStates);

	void updateModel();

	void toggleFlashlight();

	void sprayLogo();

	void shoot(bool medic);

	bool isValid();

	void remove();

	void think();
};