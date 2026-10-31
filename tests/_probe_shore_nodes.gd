extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var area: Node3D = (load("res://scenes/tests/shore_test_area.tscn") as PackedScene).instantiate()
	root.add_child(area)
	await process_frame
	_dump(area, area)
	quit(0)


func _dump(node: Node, area: Node3D) -> void:
	for child: Node in node.get_children():
		if child is Node3D:
			var p: Vector3 = (child as Node3D).global_position
			if absf(p.x - area.global_position.x) < 3.2 and p.z > -7.0 and p.z < 5.0:
				var mesh: MeshInstance3D = child as MeshInstance3D
				var size: String = ""
				if mesh != null and mesh.mesh is BoxMesh:
					size = " box=%s" % (mesh.mesh as BoxMesh).size
				print("near: ", child.name, " @", p, size, " type=", child.get_class())
		_dump(child, area)
