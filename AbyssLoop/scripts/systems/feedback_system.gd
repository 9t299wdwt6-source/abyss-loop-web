extends Node
class_name FeedbackSystem

const SAMPLE_RATE := 22050

var _cooldowns: Dictionary = {}
var _active_players: Array[AudioStreamPlayer] = []

func _process(delta: float) -> void:
	for kind_value in _cooldowns.keys():
		var kind := str(kind_value)
		_cooldowns[kind] = maxf(0.0, float(_cooldowns[kind]) - delta)
const TONE_PROFILES := {
	"damage": {"frequency": 185.0, "duration": 0.065, "gain": 0.20},
	"event": {"frequency": 392.0, "duration": 0.10, "gain": 0.17},
	"loot": {"frequency": 660.0, "duration": 0.11, "gain": 0.18},
	"level": {"frequency": 784.0, "duration": 0.15, "gain": 0.18},
	"boss": {"frequency": 260.0, "duration": 0.16, "gain": 0.22},
	"objective": {"frequency": 880.0, "duration": 0.18, "gain": 0.20}
}

func play_feedback(kind: String) -> void:
	if not TONE_PROFILES.has(kind):
		return
	if float(_cooldowns.get(kind, 0.0)) > 0.0:
		return
	_cooldowns[kind] = float(ContentRegistry.BALANCE.get("feedback_damage_cooldown", 0.22)) if kind == "damage" else 0.12
	var max_players := maxi(1, int(ContentRegistry.BALANCE.get("max_feedback_tones", 4)))
	while _active_players.size() >= max_players:
		var oldest: AudioStreamPlayer = _active_players.pop_front()
		if is_instance_valid(oldest):
			oldest.stop()
			oldest.queue_free()
	var profile: Dictionary = TONE_PROFILES[kind]
	var duration := clampf(float(profile.get("duration", 0.1)), 0.04, 0.25)
	var samples := maxi(1, int(round(SAMPLE_RATE * duration)))
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	var frequency := float(profile.get("frequency", 440.0))
	var gain := clampf(float(profile.get("gain", 0.15)), 0.0, 0.3)
	for sample_index in range(samples):
		var progress := float(sample_index) / float(samples)
		var envelope := minf(1.0, progress * 16.0) * (1.0 - progress)
		var value := int(round(sin(TAU * frequency * float(sample_index) / float(SAMPLE_RATE)) * envelope * gain * 9000.0))
		pcm.encode_s16(sample_index * 2, clampi(value, -32768, 32767))
	var tone := AudioStreamWAV.new()
	tone.format = AudioStreamWAV.FORMAT_16_BITS
	tone.mix_rate = SAMPLE_RATE
	tone.stereo = false
	tone.data = pcm
	var player := AudioStreamPlayer.new()
	player.bus = "SFX"
	player.stream = tone
	add_child(player)
	_active_players.append(player)
	player.finished.connect(_on_player_finished.bind(player))
	player.play()

func _on_player_finished(player: AudioStreamPlayer) -> void:
	_active_players.erase(player)
	if is_instance_valid(player):
		player.queue_free()
