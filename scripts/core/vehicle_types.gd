class_name VehicleTypes
## Static vehicle catalogue. Lengths are in world pixels along the lane.

const CAR := "car"
const MOTO := "moto"
const BUS := "bus"
const TRUCK := "truck"

const DEFS := {
	"car":   {"length": 104.0, "height": 15.0, "speed_mult": 1.0,  "rideable": false, "cab": 0.0},
	"moto":  {"length": 58.0,  "height": 18.0, "speed_mult": 1.0,  "rideable": false, "cab": 0.0},
	"bus":   {"length": 224.0, "height": 26.0, "speed_mult": 1.0,  "rideable": false, "cab": 0.0},
	# Delivery truck: the rear cargo box is a rideable roof, the front cab is solid.
	"truck": {"length": 184.0, "height": 24.0, "speed_mult": 1.0,  "rideable": true,  "cab": 56.0},
	# Riverfront floating platforms: the whole deck is rideable (no cab), water around them is lethal.
	"barge":     {"length": 216.0, "height": 10.0, "speed_mult": 1.0, "rideable": true, "cab": 0.0, "float": true},
	"container": {"length": 144.0, "height": 16.0, "speed_mult": 1.0, "rideable": true, "cab": 0.0, "float": true},
	"crate":     {"length": 80.0,  "height": 12.0, "speed_mult": 1.0, "rideable": true, "cab": 0.0, "float": true},
}

const CAR_COLORS := [
	Color("e8504a"), Color("f2b33d"), Color("3fa7d6"), Color("6cc551"),
	Color("b06ad9"), Color("f07f3c"), Color("e9e4d8"), Color("2f5d8a"),
]
const MOTO_COLORS := [Color("ff3d6e"), Color("2ad4c4"), Color("ffd23f"), Color("8a5cff")]
const BUS_COLORS := [Color("ffb627"), Color("2e9e6a"), Color("d94a3d")]
const TRUCK_COLORS := [Color("f3f1ea"), Color("6c8ebf")]
const BARGE_COLORS := [Color("3c4a5c"), Color("5a3f35"), Color("2f5146")]
const CONTAINER_COLORS := [Color("d9472b"), Color("2e7fc1"), Color("e8a53a"), Color("3e9a5b"), Color("8b4fb8")]
const CRATE_COLORS := [Color("b98a52"), Color("a07444")]

static func length_of(kind: String) -> float:
	return DEFS[kind]["length"]

static func is_float(kind: String) -> bool:
	return DEFS[kind].get("float", false)


static func is_rideable(kind: String) -> bool:
	return DEFS[kind]["rideable"]

static func pick_color(kind: String, rng: RandomNumberGenerator) -> Color:
	var pal: Array
	match kind:
		MOTO: pal = MOTO_COLORS
		BUS: pal = BUS_COLORS
		TRUCK: pal = TRUCK_COLORS
		"barge": pal = BARGE_COLORS
		"container": pal = CONTAINER_COLORS
		"crate": pal = CRATE_COLORS
		_: pal = CAR_COLORS
	return pal[rng.randi() % pal.size()]
