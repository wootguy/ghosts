#pragma once
#include "edict.h"
#include "CBaseEntity.h"

class EHandle
{
private:
	edict_t* m_pent;
	int		 m_serialnumber;

public:
	EHandle() {
		m_pent = NULL;
		m_serialnumber = -1;
	}

	EHandle(edict_t* ent) {
		m_pent = ent;
		m_serialnumber = m_pent ? m_pent->serialnumber : -1;
	}

	EHandle(CBaseEntity* ent) {
		m_pent = ent ? ent->pev->pContainingEntity : NULL;
		m_serialnumber = m_pent ? m_pent->serialnumber : -1;
	}

	edict_t* GetEdict() {
		if (IsValid()) {
			return m_pent;
		}
		return NULL;
	}

	CBaseEntity* GetEntity() {
		if (IsValid()) {
			return (CBaseEntity*)m_pent->pvPrivateData;
		}
		return NULL;
	}

	bool IsValid() {
		return m_pent && m_pent->serialnumber == m_serialnumber && !m_pent->free;
	}

	operator CBaseEntity* () { return GetEntity(); }
	operator edict_t* () { return GetEdict(); }
};