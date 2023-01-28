class monster_ghost : ScriptBaseMonsterEntity
{	
	bool KeyValue( const string& in szKey, const string& in szValue )
	{
		return BaseClass.KeyValue( szKey, szValue );
	}
	
	void Spawn()
	{		
		pev.movetype = MOVETYPE_FLY;
		pev.solid = SOLID_NOT;
		
		g_EntityFuncs.SetModel(self, self.pev.model);		
		g_EntityFuncs.SetSize(self.pev, Vector( -16, -16, -36), Vector(16, 16, 36));
		g_EntityFuncs.SetOrigin( self, pev.origin);

		SetThink( ThinkFunction( CustomThink ) );
		
		pev.takedamage = DAMAGE_NO;
		pev.health = 1;
		
		self.MonsterInit();
		
		self.m_MonsterState = MONSTERSTATE_NONE;
		
		self.m_IdealActivity = ACT_RELOAD;
		self.ClearSchedule();
	}
	
	void CustomThink( void )
	{
		self.pev.nextthink = g_Engine.time + 0.1;

		self.StudioFrameAdvance();
		if (self.m_fSequenceFinished && !self.m_fSequenceLoops)
		{
			self.pev.animtime = g_Engine.time;
			self.pev.framerate = 1.0;
			self.m_fSequenceFinished = false;
			self.m_flLastEventCheck = g_Engine.time;
			self.pev.frame = 0;
		}
	}
};