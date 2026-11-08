class_name C
## Shared tuning constants. Everything that defines "the grid" lives here so the
## runtime, the validator and the tests all agree on the same geometry.

const TILE := 72.0                 # one grid cell, in world pixels
const COLS := 9                    # playable columns (0..8)
const CENTER_COL := 4
const PLAY_HALF_W := TILE * COLS * 0.5          # 324 px: playable half-width
const SPAWN_X := 1500.0            # vehicles spawn this far from centre (beyond any 16:9 view)
const DESPAWN_X := 1650.0

# Player
const HOP_TIME := 0.11             # seconds per single hop
const DASH_TIME := 0.20            # seconds per two-cell dash
const HOP_HEIGHT := 22.0           # visual arc height (never affects the hitbox)
const DASH_HEIGHT := 40.0
const PLAYER_HALF_W := 20.0        # honest hitbox: 40 px wide...
const PLAYER_HALF_H := 18.0        # ...36 px tall (rows are 72 px, so rows never overlap)
const MAX_DASH_CHARGES := 3

# Vehicles
const LANE_HALF_H := 22.0          # vehicle footprint is 44 px tall inside a 72 px lane
const HITBOX_INSET := 6.0          # bumpers are rounded: shave a few pixels from each end
const VEHICLE_ACCEL := 260.0       # px/s^2
const VEHICLE_DECEL := 520.0       # comfortable braking px/s^2
const QUEUE_GAP := 14.0            # bumper-to-bumper gap when queuing at a red light

# Fairness
const MIN_GAP_SECONDS := 1.0       # never less than this many seconds between vehicles in a lane
const MAX_LANES_WITHOUT_REFUGE := 4

# Row types
enum Row { SIDEWALK, ROAD, MEDIAN }

static func col_to_x(col: int) -> float:
	return (float(col) - CENTER_COL) * TILE

static func x_to_col(x: float) -> int:
	return clampi(int(round(x / TILE)) + CENTER_COL, 0, COLS - 1)

static func row_to_y(row: int) -> float:
	return -float(row) * TILE

static func in_play_x(x: float) -> bool:
	return absf(x) <= PLAY_HALF_W - TILE * 0.5 + 0.5
