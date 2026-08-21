extends Node

signal world_changed(is_upside: bool)

@export var active_music_volume_db := -2.0
@export var silent_music_volume_db := -60.0
@export var crossfade_duration := 0.35

@onready var dungeon: Node3D = get_node("../Dungeon")
@onready var normal_music: AudioStreamPlayer = $NormalMusic
@onready var upside_music: AudioStreamPlayer = $UpsideMusic

var is_upside := false
var music_tween: Tween
var music_transition_id := 0
var normal_music_position := 0.0
var upside_music_position := 0.0


func _ready() -> void:
	_enable_loop(normal_music.stream)
	_enable_loop(upside_music.stream)
	normal_music.volume_db = active_music_volume_db
	upside_music.volume_db = silent_music_volume_db
	upside_music.stop()
	_apply_world(false, true)
	call_deferred("_start_music")


func _start_music() -> void:
	# O início deferido evita que o driver de áudio descarte play() durante a
	# montagem inicial da cena em algumas configurações do Windows.
	_play_from_saved_position(normal_music, normal_music_position)
	upside_music.stop()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"switch_world"):
		if event is InputEventKey and event.echo:
			return
		toggle_world()
		get_viewport().set_input_as_handled()


func toggle_world() -> void:
	_apply_world(not is_upside)


func _apply_world(upside: bool, immediate := false) -> void:
	if not immediate and upside == is_upside:
		return

	var outgoing_music := upside_music if is_upside else normal_music
	var incoming_music := upside_music if upside else normal_music
	if not immediate:
		_save_music_position(outgoing_music)

	is_upside = upside
	if dungeon.has_method("set_world"):
		dungeon.call("set_world", is_upside)

	if music_tween != null and music_tween.is_valid():
		music_tween.kill()
	music_transition_id += 1

	var normal_target := silent_music_volume_db if is_upside else active_music_volume_db
	var upside_target := active_music_volume_db if is_upside else silent_music_volume_db
	if immediate:
		normal_music.volume_db = normal_target
		upside_music.volume_db = upside_target
	else:
		_play_from_saved_position(incoming_music, _get_saved_music_position(incoming_music))
		incoming_music.volume_db = silent_music_volume_db
		music_tween = create_tween().set_parallel(true)
		music_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		music_tween.tween_property(normal_music, "volume_db", normal_target, crossfade_duration)
		music_tween.tween_property(upside_music, "volume_db", upside_target, crossfade_duration)
		var transition_id := music_transition_id
		music_tween.finished.connect(
			_finish_music_transition.bind(outgoing_music, transition_id),
			CONNECT_ONE_SHOT
		)

	world_changed.emit(is_upside)


func _save_music_position(player: AudioStreamPlayer) -> void:
	if not player.playing:
		return
	var saved_position := player.get_playback_position()
	if player == normal_music:
		normal_music_position = saved_position
	else:
		upside_music_position = saved_position


func _get_saved_music_position(player: AudioStreamPlayer) -> float:
	return normal_music_position if player == normal_music else upside_music_position


func _play_from_saved_position(player: AudioStreamPlayer, saved_position: float) -> void:
	var stream_length := player.stream.get_length()
	var safe_position := fmod(saved_position, stream_length) if stream_length > 0.0 else 0.0
	player.play(maxf(safe_position, 0.0))


func _finish_music_transition(player: AudioStreamPlayer, transition_id: int) -> void:
	if transition_id != music_transition_id:
		return
	player.stop()
	player.volume_db = silent_music_volume_db


func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * wav.mix_rate))
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
