extends RefCounted

## Authored body sheets, attack ranges in world pixels and debris colors.
const TYPES: Dictionary = {
	"goblin": {
		"role": "melee",
		"bodies": [
			[preload("res://assets/enemies/open_world_horde/goblin/sprGoblin1.png"), Color("#4D6659"), Color("#7E659B")],
			[preload("res://assets/enemies/open_world_horde/goblin/sprGoblin3.png"), Color("#4D6659"), Color("#E1A845")],
		],
		"shot": preload("res://assets/enemies/open_world_horde/goblin/effects/sprAttackSpear.png"),
		"frames": 4, "reach": 36.0, "travel": 40.0, "speed": 160.0, "interval": 0.65,
	},
	"skeleton": {
		"role": "melee",
		"bodies": [
			[preload("res://assets/enemies/open_world_horde/skeleton/sprSkeleton1.png"), Color("#C4C6B8"), Color("#867066")],
			[preload("res://assets/enemies/open_world_horde/skeleton/sprSkeleton3.png"), Color("#7E659B"), Color("#63C4CC")],
		],
		"shot": preload("res://assets/enemies/open_world_horde/skeleton/effects/sprAttackSwing.png"),
		"frames": 4, "reach": 28.0, "travel": 32.0, "speed": 160.0, "interval": 0.55,
	},
	"bogslium": {
		"role": "support",
		"bodies": [
			[preload("res://assets/enemies/open_world_horde/bogslium/sprBogslium2.png"), Color("#4D6659"), Color("#739A70")],
			[preload("res://assets/enemies/open_world_horde/bogslium/sprBogslium3.png"), Color("#4D6659"), Color("#739A70")],
		],
		"shot": preload("res://assets/enemies/open_world_horde/bogslium/effects/sprAcidProjectile.png"),
		"frames": 10, "reach": 104.0, "travel": 132.0, "speed": 83.0, "interval": 0.9,
	},
	"ghost": {
		"role": "support",
		"bodies": [
			[preload("res://assets/enemies/open_world_horde/ghost/sprGhost1.png"), Color("#BAC9CD"), Color("#BAC9CD")],
		],
		"shot": preload("res://assets/enemies/open_world_horde/ghost/effects/sprGhostOrb.png"),
		"frames": 8, "reach": 192.0, "travel": 224.0, "speed": 81.0, "interval": 1.15,
	},
	"lizard_monk": {
		"role": "support",
		"bodies": [
			[preload("res://assets/enemies/open_world_horde/lizard_monk/sprLizardMonk1.png"), Color("#5C3A6F"), Color("#739A70")],
			[preload("res://assets/enemies/open_world_horde/lizard_monk/sprLizardMonk3.png"), Color("#7B234C"), Color("#E1A845")],
		],
		"shot": preload("res://assets/enemies/open_world_horde/lizard_monk/effects/sprMagicBolt.png"),
		"frames": 4, "reach": 152.0, "travel": 182.0, "speed": 150.0, "interval": 1.45,
	},
	"orc_archer": {
		"role": "ranged",
		"bodies": [
			[preload("res://assets/enemies/open_world_horde/orc_archer/sprOrcArcher1.png"), Color("#94AD39"), Color("#825646")],
			[preload("res://assets/enemies/open_world_horde/orc_archer/sprOrcArcher3.png"), Color("#94AD39"), Color("#B23657")],
		],
		"shot": preload("res://assets/enemies/open_world_horde/orc_archer/effects/sprArrow.png"),
		"frames": 6, "reach": 184.0, "travel": 218.0, "speed": 215.0, "interval": 0.95,
	},
	"batilisk": {
		"role": "ranged",
		"bodies": [
			[preload("res://assets/enemies/open_world_horde/batilisk/sprBatilisk2.png"), Color("#6D4E4B"), Color("#C4C6B8")],
			[preload("res://assets/enemies/open_world_horde/batilisk/sprBatilisk3.png"), Color("#5C3A6F"), Color("#E47259")],
		],
		"shot": preload("res://assets/enemies/open_world_horde/batilisk/effects/sprFirebolt.png"),
		"frames": 4, "reach": 144.0, "travel": 174.0, "speed": 157.0, "interval": 0.8,
	},
}

const ROLE_WEIGHTS: Dictionary = {"melee": 1.0, "ranged": 2.0, "support": 3.0}
const ROLE_ENTRY_SECONDS: Dictionary = {"support": 0.0, "ranged": 0.8, "melee": 1.6}
const POOLS: Dictionary = {
	"room_2_forest_west": ["goblin", "bogslium", "orc_archer"],
	"room_2_forest_east": ["goblin", "lizard_monk", "orc_archer", "batilisk"],
	"room_2_river_south": ["goblin", "bogslium", "batilisk"],
	"room_2_river_north": ["skeleton", "bogslium", "ghost", "orc_archer"],
	"room_2_castle_west": ["goblin", "ghost", "lizard_monk", "orc_archer"],
	"room_2_castle_east": ["skeleton", "lizard_monk", "orc_archer", "batilisk"],
}


static func pick(encounter_id: String, elapsed: float, random: RandomNumberGenerator) -> String:
	var pool: Array = POOLS[encounter_id]
	var roles: Dictionary = {}
	for species: String in pool:
		var role: String = TYPES[species].role
		if elapsed >= float(ROLE_ENTRY_SECONDS[role]):
			if not roles.has(role):
				roles[role] = []
			(roles[role] as Array).append(species)
	var total: float = 0.0
	for role: String in roles:
		total += float(ROLE_WEIGHTS[role])
	var draw: float = random.randf() * total
	for role: String in roles:
		draw -= float(ROLE_WEIGHTS[role])
		if draw <= 0.0:
			var members: Array = roles[role]
			return str(members[random.randi_range(0, members.size() - 1)])
	return str(pool[0])
