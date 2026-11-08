class_name CameraRig
extends Camera2D
## Tracks progress vertically while keeping plenty of upcoming lanes on screen.
## The robot sits ~68% down the screen, so in portrait ~11 rows ahead are visible
## and in landscape the same lane depth is kept while more side space is shown.

## Where the robot sits vertically. The D-pad mode lifts it a little so the pad
## never covers the lane just behind the robot.
func player_screen_frac() -> float:
	return 0.6 if GameState.settings.get("touch_mode", "swipe") == "dpad" and not GameState.last_device_pad else 0.68

var _shake := 0.0
var _rng := RandomNumberGenerator.new()


func view_size() -> Vector2:
	return get_viewport_rect().size


func target_for(world_y: float) -> float:
	return world_y - view_size().y * (player_screen_frac() - 0.5)


func snap_to(world_y: float) -> void:
	position = Vector2(0, target_for(world_y))


func follow(world_y: float, dt: float) -> void:
	var ty := target_for(world_y)
	position.x = 0.0
	position.y = lerpf(position.y, ty, 1.0 - exp(-dt * 7.0))
	if _shake > 0.0:
		var amt := _shake * float(GameState.settings["shake"])
		offset = Vector2(_rng.randf_range(-amt, amt), _rng.randf_range(-amt, amt))
		_shake = move_toward(_shake, 0.0, dt * 40.0)
	else:
		offset = Vector2.ZERO


func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func visible_rect() -> Rect2:
	var s := view_size()
	return Rect2(position + offset - s * 0.5, s)
