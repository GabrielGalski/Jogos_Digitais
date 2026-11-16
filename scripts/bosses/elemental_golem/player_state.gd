extends RefCounted
## Narrow transfer contract shared by the boss entrance, retry and return trip.

static func capture(player: Player, heal: bool = false) -> Dictionary:
	var shooter: Node = player.get_node("BoosterShooter")
	return {"health":player.max_health if heal else player.health,"max_health":player.max_health,
		"dash_charges":Player.MAX_DASH_CHARGES if heal else player.dash_charges,
		"dash_recovery":0.0 if heal else player.dash_recovery,
		"card_runtime":shooter.get("card_runtime"),"cooldown":0.0 if heal else shooter.get("cooldown")}


static func apply(player: Player, data: Dictionary) -> void:
	if data.is_empty(): return
	player.max_health = float(data.get("max_health",player.max_health))
	player.health = clampf(float(data.get("health",player.max_health)),0.0,player.max_health)
	player.dash_charges = clampi(int(data.get("dash_charges",Player.MAX_DASH_CHARGES)),0,Player.MAX_DASH_CHARGES)
	player.dash_recovery = float(data.get("dash_recovery",0.0))
	var shooter: Node = player.get_node("BoosterShooter")
	if data.has("card_runtime"): shooter.set("card_runtime",data.card_runtime)
	shooter.set("cooldown",float(data.get("cooldown",0.0)))
	player.health_changed.emit(player.health,player.max_health)
