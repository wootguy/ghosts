#pragma once
#include "private_api.h"
#include "GhostCam.h"
#include <map>
#include <set>

class PlayerState {
public:
	GhostCam cam;
	int visbilityMode = 0;
	int viewingMonsterInfo = 0;
	float nextGhostCollect = 0;
	bool changedMode = false;
	bool enablePlayerModel = true;

	PlayerState();

	bool shouldSeeGhosts(CBasePlayer* plr);

	void debug(CBasePlayer* plr);
};

extern std::map<std::string, PlayerState> g_player_states;
extern std::set<std::string> g_player_model_precache;

extern float g_renderamt; // must be at least 128 or textures with transparency are invisible (gf_ump45)
extern float g_min_zoom;
extern float g_max_zoom;
extern float g_default_zoom;

extern int ghostId;
extern const char* g_camera_model;
extern const char* g_ent_prefix;
extern bool g_use_player_models;
extern bool g_stress_test;
extern bool g_fun_mode;

void update_ghost_visibility();
void delete_orphaned_ghosts();