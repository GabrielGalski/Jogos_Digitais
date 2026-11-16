extends RefCounted
## Source poses are documented from 1; SpriteFrames clip indices start at 0.
const POSES: Array[Dictionary] = [
	{"pose":1,"action":"ready"},
	{"pose":2,"action":"anticipation"},
	{"pose":3,"action":"raise_arms_start"},
	{"pose":4,"action":"raise_arms"},
	{"pose":5,"action":"overhead_start"},
	{"pose":6,"action":"overhead_hold"},
	{"pose":7,"action":"ground_impact","event":"volley"},
	{"pose":8,"action":"impact_follow_through"},
	{"pose":9,"action":"recovery_start"},
	{"pose":10,"action":"recovery"},
	{"pose":11,"action":"return_to_ready"},
]
const CLIPS: Dictionary = {
	"cast":[5], "charge":[0,1,2,3,4,5],
	"slam":[5,6,7,8,9,10,0,1,2,3,4],
	"jump_prepare":[2,3], "fall":[6], "land":[7,8,9,10],
}
const CHARGE_DURATION: float = 0.58
const SLAM_IMPACT_FRAME: int = 1
const VOLLEY_INTERVALS: Array[float] = [0.82,0.62,0.72]
const MUZZLE: Vector2 = Vector2(0,-6)


static func manifest() -> Dictionary:
	var clips: Dictionary = {}
	for clip: String in CLIPS:
		var poses: Array[int] = []
		for index: int in CLIPS[clip]: poses.append(index+1)
		clips[clip] = poses
	return {"source_numbering":"one_based","poses":POSES,"clips":clips,
		"clip_index_numbering":"zero_based","impact_pose":7,"slam_impact_clip_index":SLAM_IMPACT_FRAME,
		"volley_intervals_seconds":{"ice":VOLLEY_INTERVALS[0],"fire":VOLLEY_INTERVALS[1],"lightning":VOLLEY_INTERVALS[2]}}
