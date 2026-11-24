extends Node2D
## Owns positional voices for one pedestal. Gameplay sends events, never per-enemy players.

enum Event { ATTACK, HIT_PLAYER, DEATH }

const HORDE_BUS: StringName = &"HordeSFX"
const ELITE_BUS: StringName = &"EliteSFX"
const HORDE_VOICES: int = 6
const ELITE_VOICES: int = 3
const HORDE_RANGE: float = 240.0
const ELITE_RANGE: float = 340.0
const DUCK_DB: float = -6.0

const FAMILIES: Dictionary[StringName, StringName] = {
	&"goblin": &"melee",
	&"skeleton": &"melee",
	&"bogslium": &"acid",
	&"ghost": &"supernatural",
	&"lizard_monk": &"supernatural",
	&"orc_archer": &"bow",
	&"batilisk": &"fire",
	&"spirit_ghost": &"supernatural",
}

const SOUNDS: Dictionary[StringName, Array] = {
	&"goblin": [
		preload("res://assets/audio/enemies/horde/goblin/attack.wav"),
		preload("res://assets/audio/enemies/horde/goblin/hit_player.wav"),
		preload("res://assets/audio/enemies/horde/goblin/death.wav"),
	],
	&"skeleton": [
		preload("res://assets/audio/enemies/horde/skeleton/attack.wav"),
		preload("res://assets/audio/enemies/horde/skeleton/hit_player.wav"),
		preload("res://assets/audio/enemies/horde/skeleton/death.wav"),
	],
	&"bogslium": [
		preload("res://assets/audio/enemies/horde/bogslium/attack.wav"),
		preload("res://assets/audio/enemies/horde/bogslium/hit_player.wav"),
		preload("res://assets/audio/enemies/horde/bogslium/death.wav"),
	],
	&"ghost": [
		preload("res://assets/audio/enemies/horde/ghost/attack.wav"),
		preload("res://assets/audio/enemies/horde/ghost/hit_player.wav"),
		preload("res://assets/audio/enemies/horde/ghost/death.wav"),
	],
	&"lizard_monk": [
		preload("res://assets/audio/enemies/horde/lizard_monk/attack.wav"),
		preload("res://assets/audio/enemies/horde/lizard_monk/hit_player.wav"),
		preload("res://assets/audio/enemies/horde/lizard_monk/death.wav"),
	],
	&"orc_archer": [
		preload("res://assets/audio/enemies/horde/orc_archer/attack.wav"),
		preload("res://assets/audio/enemies/horde/orc_archer/hit_player.wav"),
		preload("res://assets/audio/enemies/horde/orc_archer/death.wav"),
	],
	&"batilisk": [
		preload("res://assets/audio/enemies/horde/batilisk/attack.wav"),
		preload("res://assets/audio/enemies/horde/batilisk/hit_player.wav"),
		preload("res://assets/audio/enemies/horde/batilisk/death.wav"),
	],
	&"spirit_ghost": [
		preload("res://assets/audio/enemies/horde/spirit_ghost/attack.wav"),
		preload("res://assets/audio/enemies/horde/spirit_ghost/hit_player.wav"),
		preload("res://assets/audio/enemies/horde/spirit_ghost/death.wav"),
	],
}
const WINDOWS: Array[float] = [0.12, 0.095, 0.18]
const LEVELS: Array[float] = [-12.0, -7.0, -14.0]
const PRIORITIES: Array[float] = [0.0, 6.0, 3.0]

class Cue:
	var stream: AudioStream
	var point: Vector2
	var priority: float
	var level_db: float
	var window: float
	var group: StringName

class Voice:
	var speaker: AudioStreamPlayer2D
	var remaining: float = 0.0
	var priority: float
	var level_db: float

var listener: Node2D
var _horde: Array[Voice] = []
var _elites: Array[Voice] = []
var _pending: Dictionary[StringName, Cue] = {}
var _allowed_at: Dictionary[StringName, float] = {}
var _time: float = 0.0
var _elite_hold: float = 0.0
var _duck_db: float = 0.0


func _ready() -> void:
	process_physics_priority = 20


func _exit_tree() -> void:
	cancel()


func cancel() -> void:
	_pending.clear()
	_allowed_at.clear()
	_elite_hold = 0.0
	for voice: Voice in _horde + _elites:
		voice.speaker.stop()
		voice.speaker.stream = null
		voice.remaining = 0.0


func queue_horde(species: StringName, event: Event, point: Vector2, damage: float = 0.0) -> void:
	if not is_instance_valid(listener) or not SOUNDS.has(species):
		return
	var distance: float = listener.global_position.distance_to(point)
	if distance >= HORDE_RANGE:
		return
	var family: StringName = FAMILIES[species]
	# Give damage feedback one readable voice at the player, even when families overlap.
	var group: StringName = &"player_hit" if event == Event.HIT_PLAYER else StringName("%s/%d" % [family, event])
	if _time < float(_allowed_at.get(group, 0.0)):
		return
	var priority: float = PRIORITIES[event] + (1.0 - distance / HORDE_RANGE) + minf(damage, 18.0) * 0.08
	var current: Cue = _pending.get(group) as Cue
	if current != null and current.priority >= priority:
		return
	var cue: Cue = Cue.new()
	cue.stream = SOUNDS[species][event] as AudioStream
	cue.point = point
	cue.priority = priority
	cue.level_db = LEVELS[event]
	cue.group = group
	# The monk's second shot is scheduled 180 ms after the first.
	cue.window = 0.21 if event == Event.ATTACK and family == &"supernatural" else WINDOWS[event]
	_pending[group] = cue


func player_hit(point: Vector2, damage: float, species: StringName) -> void:
	queue_horde(species, Event.HIT_PLAYER, point, damage)


func play_elite(stream: AudioStream, point: Vector2, priority: float, level_db: float = -5.0) -> void:
	var cue: Cue = Cue.new()
	cue.stream = stream
	cue.point = point
	cue.priority = priority
	cue.level_db = level_db
	_play(cue, _elites, ELITE_VOICES, ELITE_BUS, ELITE_RANGE, 0.0)
	feature_elite(point, stream.get_length())


func feature_elite(point: Vector2, duration: float, radius: float = ELITE_RANGE) -> void:
	if is_instance_valid(listener) and listener.global_position.distance_to(point) < radius:
		_elite_hold = maxf(_elite_hold, duration)
		_duck_db = minf(_duck_db, -2.0)


func _physics_process(delta: float) -> void:
	_time += delta
	_elite_hold = maxf(_elite_hold - delta, 0.0)
	_duck_db = move_toward(_duck_db, DUCK_DB if _elite_hold > 0.0 else 0.0,
		(150.0 if _elite_hold > 0.0 else 24.0) * delta)
	for voice: Voice in _horde:
		voice.remaining = maxf(0.0, voice.remaining - delta)
		voice.speaker.volume_db = voice.level_db + _duck_db
	for voice: Voice in _elites:
		voice.remaining = maxf(0.0, voice.remaining - delta)
	if _pending.is_empty():
		return
	var cues: Array[Cue] = []
	cues.assign(_pending.values())
	_pending.clear()
	cues.sort_custom(func(left: Cue, right: Cue) -> bool: return left.priority > right.priority)
	for cue: Cue in cues:
		if _play(cue, _horde, HORDE_VOICES, HORDE_BUS, HORDE_RANGE, _duck_db):
			_allowed_at[cue.group] = _time + maxf(cue.window, cue.stream.get_length())


func _play(cue: Cue, pool: Array[Voice], limit: int, bus: StringName, radius: float, duck_db: float) -> bool:
	var slot: Voice = null
	var quietest: Voice = null
	for voice: Voice in pool:
		if voice.remaining <= 0.0:
			slot = voice
			break
		if quietest == null or voice.priority < quietest.priority:
			quietest = voice
	if slot == null and pool.size() < limit:
		slot = Voice.new()
		slot.speaker = AudioStreamPlayer2D.new()
		slot.speaker.bus = bus
		slot.speaker.max_distance = radius
		slot.speaker.panning_strength = 0.6
		add_child(slot.speaker)
		pool.append(slot)
	if slot == null:
		if quietest == null or quietest.priority >= cue.priority:
			return false
		slot = quietest
	slot.priority = cue.priority
	slot.level_db = cue.level_db
	slot.remaining = cue.stream.get_length()
	slot.speaker.stream = cue.stream
	slot.speaker.global_position = cue.point
	slot.speaker.volume_db = cue.level_db + duck_db
	slot.speaker.play()
	return true
