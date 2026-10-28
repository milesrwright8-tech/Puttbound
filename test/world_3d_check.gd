extends SceneTree
## Finite smoke checks for Puttbound's actual playable loop.

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(str(ProjectSettings.get_setting("application/run/main_scene"))) as PackedScene
	_check(packed != null, "active Puttbound scene must load")
	if packed == null:
		_finish()
		return
	var world: Node = packed.instantiate()
	root.add_child(world)
	await process_frame
	_check(world is Node3D, "active world must be Node3D")
	_check(world.get_node_or_null("FollowCamera") is Camera3D, "Puttbound must create a follow camera")
	_check(world.get("holes").size() == 30, "course catalog must contain 30 holes")
	world.call("_start_hole", 0)
	await process_frame
	var ball := world.get_node_or_null("Course/PuttBall") as RigidBody3D
	var cup := world.get_node_or_null("Course/CupGoal") as Area3D
	_check(ball != null, "a playable hole must create a physical ball")
	_check(cup != null, "a playable hole must create a goal cup")
	if ball != null:
		var start := ball.global_position
		world.call("_shoot", Vector3(0, 0, 1), 0.45)
		await physics_frame
		await physics_frame
		_check(ball.linear_velocity.length() > 0.01 or ball.global_position.distance_to(start) > 0.01, "a released shot must move the ball")
	var hit_audio := world.get_node_or_null("PuttHit") as AudioStreamPlayer
	if hit_audio != null:
		hit_audio.stop()
	world.free()
	await process_frame
	_finish()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[puttbound] PASS: 30-hole catalog, camera, course goal, ball physics and shot loop")
		quit(0)
		return
	for failure: String in _failures:
		push_error("[puttbound] " + failure)
	quit(1)
