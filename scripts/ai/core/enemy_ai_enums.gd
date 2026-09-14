class_name EnemyAIEnums
extends RefCounted

enum Objective {
	IDLE,
	PRESSURE_TARGET,
	DEFEND_POSITION,
	RETREAT,
	DISABLED,
}

enum Intent {
	IDLE,
	APPROACH,
	ORBIT,
	HOLD,
	PREPARE,
	ATTACK,
	RECOVER,
	REPOSITION,
	RETREAT,
	DISABLED,
}

enum Role {
	MELEE,
	RANGED,
	SUPPORT,
	ELITE,
}
