#include "temp_ents.h"
#include "const.h"

void te_beaments(edict_t* start, edict_t* end,
	const char* sprite, int frameStart,
	int frameRate, int life, int width, int noise,
	Color c, int scroll,
	int msgType, edict_t* dest) {

	MESSAGE_BEGIN(msgType, SVC_TEMPENTITY, NULL, dest);
	WRITE_BYTE(TE_BEAMENTS);
	WRITE_SHORT(ENTINDEX(start));
	WRITE_SHORT(ENTINDEX(end));
	WRITE_SHORT(g_engfuncs.pfnModelIndex(sprite));
	WRITE_BYTE(frameStart);
	WRITE_BYTE(frameRate);
	WRITE_BYTE(life);
	WRITE_BYTE(width);
	WRITE_BYTE(noise);
	WRITE_BYTE(c.r);
	WRITE_BYTE(c.g);
	WRITE_BYTE(c.b);
	WRITE_BYTE(c.a); // actually brightness
	WRITE_BYTE(scroll);
	MESSAGE_END();
}

void te_beampoints(Vector start, Vector end,
	const char* sprite, uint8_t frameStart,
	uint8_t frameRate, uint8_t life, uint8_t width, uint8_t noise,
	Color c, uint8_t scroll, int msgType, edict_t* dest)
{
	MESSAGE_BEGIN(msgType, SVC_TEMPENTITY, NULL, dest);
	WRITE_BYTE(TE_BEAMPOINTS);
	WRITE_COORD(start.x);
	WRITE_COORD(start.y);
	WRITE_COORD(start.z);
	WRITE_COORD(end.x);
	WRITE_COORD(end.y);
	WRITE_COORD(end.z);
	WRITE_SHORT(g_engfuncs.pfnModelIndex(sprite));
	WRITE_BYTE(frameStart);
	WRITE_BYTE(frameRate);
	WRITE_BYTE(life);
	WRITE_BYTE(width);
	WRITE_BYTE(noise);
	WRITE_BYTE(c.r);
	WRITE_BYTE(c.g);
	WRITE_BYTE(c.b);
	WRITE_BYTE(c.a); // actually brightness
	WRITE_BYTE(scroll);
	MESSAGE_END();
}

void te_tracer(Vector start, Vector end, int msgType, edict_t* dest)
{
	MESSAGE_BEGIN(msgType, SVC_TEMPENTITY, NULL, dest);
	WRITE_BYTE(TE_TRACER);
	WRITE_COORD(start.x);
	WRITE_COORD(start.y);
	WRITE_COORD(start.z);
	WRITE_COORD(end.x);
	WRITE_COORD(end.y);
	WRITE_COORD(end.z);
	MESSAGE_END();
}

void te_killbeam(edict_t* target, int msgType, edict_t* dest)
{
	MESSAGE_BEGIN(msgType, SVC_TEMPENTITY, NULL, dest);
	WRITE_BYTE(TE_KILLBEAM);
	WRITE_SHORT(ENTINDEX(target));
	MESSAGE_END();
}

void te_playerdecal(Vector pos, edict_t* plr, edict_t* brushEnt, int msgType, edict_t* dest)
{
	MESSAGE_BEGIN(msgType, SVC_TEMPENTITY, NULL, dest);
	WRITE_BYTE(TE_PLAYERDECAL);
	WRITE_BYTE(ENTINDEX(plr));
	WRITE_COORD(pos.x);
	WRITE_COORD(pos.y);
	WRITE_COORD(pos.z);
	WRITE_SHORT(brushEnt ? ENTINDEX(brushEnt) : 0);
	WRITE_BYTE(0); // decal index does not apply here but it's still required
	MESSAGE_END();
}

void te_projectile(Vector pos, Vector velocity, edict_t* owner,
	const char* model, uint8_t life, int msgType, edict_t* dest)
{
	int ownerId = owner ? ENTINDEX(owner) : 0;
	MESSAGE_BEGIN(msgType, SVC_TEMPENTITY, NULL, dest);
	WRITE_BYTE(TE_PROJECTILE);
	WRITE_COORD(pos.x);
	WRITE_COORD(pos.y);
	WRITE_COORD(pos.z);
	WRITE_COORD(velocity.x);
	WRITE_COORD(velocity.y);
	WRITE_COORD(velocity.z);
	WRITE_SHORT(g_engfuncs.pfnModelIndex(model));
	WRITE_BYTE(life);
	WRITE_BYTE(ownerId);
	MESSAGE_END();
}

void te_smoke(Vector pos, const char* sprite, int scale, int frameRate, int msgType, edict_t* dest)
{
	MESSAGE_BEGIN(msgType, SVC_TEMPENTITY, NULL, dest);
	WRITE_BYTE(TE_SMOKE);
	WRITE_COORD(pos.x);
	WRITE_COORD(pos.y);
	WRITE_COORD(pos.z);
	WRITE_SHORT(g_engfuncs.pfnModelIndex(sprite));
	WRITE_BYTE(scale);
	WRITE_BYTE(frameRate);
	MESSAGE_END();
}