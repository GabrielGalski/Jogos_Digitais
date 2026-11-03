extends RefCounted
## One creation boundary for models; input, art recipes and hit logic stay separate.

const PROJECTILE: Script = preload("res://scripts/combat/manifestations/procedural_projectile.gd")
const CHANNEL: Script = preload("res://scripts/combat/manifestations/procedural_channel.gd")


static func projectile(model: ProceduralManifestationModel, attack: CardAttack, parent: Node,
		origin: Vector2, aim: Vector2, effects: CombatEffects, player: CollisionObject2D,
		sprites: ProceduralWeaponSpriteFactory) -> Node2D:
	var actor: Node2D = PROJECTILE.new() as Node2D
	actor.name = "Projectile_" + String(model.code())
	parent.add_child(actor)
	actor.global_position = origin
	actor.call("configure", model, attack, effects, player, aim, sprites)
	return actor


static func channel(model: ProceduralManifestationModel, parent: Node,
		player: CollisionObject2D, sprites: ProceduralWeaponSpriteFactory) -> Node2D:
	var actor: Node2D = CHANNEL.new() as Node2D
	actor.name = "Channel_" + String(model.code())
	parent.add_child(actor)
	actor.call("configure", model, sprites, player)
	return actor
