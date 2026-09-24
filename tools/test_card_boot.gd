extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("card boot: scene")
	change_scene_to_file("res://battle/battle_scene.tscn")
	await process_frame
	await process_frame
	print("card boot: start battle")
	current_scene.call("_start_battle")
	print("card boot: battle started")
	await create_timer(1.0).timeout
	print("card boot: timer finished")
	quit()
