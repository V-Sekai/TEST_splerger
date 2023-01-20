extends RefCounted


class _SplitInfo:
	var grid_size: float = 0
	var grid_size_y: float = 0
	var aabb: AABB
	var x_splits: int = 0
	var y_splits: int = 1
	var z_splits: int = 0
	var use_local_space: bool = false

var m_bDebug_Split = false


func _get_num_splits_y(si: _SplitInfo) -> int:
	if si.grid_size_y <= 0.00001:
		return 1

	var splits = int(floor(si.aabb.size.y / si.grid_size_y))
	if splits < 1:
		splits = 1
	return splits


func _get_num_splits_z(si: _SplitInfo) -> int:
	var splits = int(floor(si.aabb.size.z / si.grid_size))
	if splits < 1:
		splits = 1
	return splits



func _find_or_add_unique_vert(orig_index: int, unique_verts, ind_mapping):
	# already exists in unique verts
	if ind_mapping[orig_index] != -1:
		return ind_mapping[orig_index]

	# else add to list of unique verts
	var new_index = unique_verts.size()
	unique_verts.push_back(orig_index)

	# record this for next time
	ind_mapping[orig_index] = new_index

	return new_index


func merge_suitable_meshes_across_branches(root: Node3D):
	var master_list = []
	_list_mesh_instances(root, master_list)

	var mat_list = []
	var sub_list = []

	# identify materials
	for n in range(master_list.size()):
		var mat
		if master_list[n].get_surface_material_count() > 0:
			mat = master_list[n].mesh.surface_get_material(0)

		# is the material in the mat list already?
		var mat_id = -1

		for m in range(mat_list.size()):
			if mat_list[m] == mat:
				mat_id = m
				break

		# first instance of material
		if mat_id == -1:
			mat_id = mat_list.size()
			mat_list.push_back(mat)
			sub_list.push_back([])

		# mat id is the sub list to add to
		var sl = sub_list[mat_id]
		sl.push_back(master_list[n])
		print("adding " + master_list[n].get_name() + " to material sublist " + str(mat_id))

	# at this point the sub lists are complete, and we can start merging them
	for n in range(sub_list.size()):
		var sl = sub_list[n]

		if sl.size() > 1:
			var new_mi: MeshInstance3D = merge_meshinstances(sl, root)

			# compensate for local transform on the parent node
			# (as the new verts will be in global space)
			var tr: Transform3D = root.global_transform
			tr = tr.inverse()
			new_mi.transform = tr


func _list_mesh_instances(node, list):
	if node is MeshInstance3D:
		if node.get_child_count() == 0:
			var mi: MeshInstance3D = node
			if mi.get_surface_material_count() <= 1:
				list.push_back(node)

	for c in range(node.get_child_count()):
		_list_mesh_instances(node.get_child(c), list)


func merge_suitable_meshes_recursive(node: Node):
	# try merging child mesh instances
	_merge_suitable_child_meshes(node)

	# iterate through children
	for c in range(node.get_child_count()):
		merge_suitable_meshes_recursive(node.get_child(c))


func _merge_suitable_child_meshes(node: Node):
	if node is Node3D:
		var spat: Node3D = node

		var child_list = []
		for c in range(node.get_child_count()):
			_find_suitable_meshes(child_list, node.get_child(c))

		if child_list.size() > 1:
			var new_mi: MeshInstance3D = merge_meshinstances(child_list, node)

			# compensate for local transform on the parent node
			# (as the new verts will be in global space)
			var tr: Transform3D = spat.global_transform
			tr = tr.inverse()
			new_mi.transform = tr


func _find_suitable_meshes(child_list, node: Node):
	# don't want to merge meshes with children
	if node.get_child_count():
		return

	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		# must have only one surface
		if mi.get_surface_material_count() <= 1:
			print("found mesh instance " + mi.get_name())

			var mat_this = mi.mesh.surface_get_material(0)

			if child_list.size() == 0:
				if mat_this:
					print("\tadding first to list")
					child_list.push_back(mi)
				return

			# already exists in child list
			# must be compatible meshes
			var mat_existing = child_list[0].mesh.surface_get_material(0)

			if mat_this == mat_existing:
				print("\tadding to list")
				child_list.push_back(mi)


func merge_meshinstances(
	mesh_array, attachment_node: Node, use_local_space: bool = false, delete_originals: bool = true
):
	if mesh_array.size() < 2:
		printerr("merge_meshinstances array must contain at least 2 meshes")
		return

	var tmpMesh = ArrayMesh.new()

	var first_mi = mesh_array[0]

	var mat
	if first_mi is MeshInstance3D:
		mat = first_mi.mesh.surface_get_material(0)
	else:
		printerr("merge_meshinstances array must contain mesh instances")
		return

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)

	var vertex_count: int = 0

	for n in range(mesh_array.size()):
		vertex_count = _merge_meshinstance(st, mesh_array[n], use_local_space, vertex_count)

	st.commit(tmpMesh)

	var new_mi = MeshInstance3D.new()
	new_mi.mesh = tmpMesh

	if new_mi.mesh.get_surface_count():
		new_mi.set_surface_override_material(0, mat)

	if use_local_space:
		new_mi.transform = first_mi.transform

	var sz = first_mi.get_name() + "_merged"
	new_mi.set_name(sz)

	# add the new mesh as a child
	attachment_node.add_child(new_mi)
	new_mi.owner = attachment_node.owner

	if delete_originals:
		for n in range(mesh_array.size()):
			var mi = mesh_array[n]
			var parent = mi.get_parent()
			if parent:
				parent.remove_child(mi)
			mi.queue_free()

	# return the new mesh instance as it can be useful to change transform
	return new_mi


func _merge_meshinstance(
	st: SurfaceTool, mi: MeshInstance3D, use_local_space: bool, vertex_count: int
):
	if mi == null:
		printerr("_merge_meshinstance - not a mesh instance, ignoring")
		return vertex_count

	print("merging meshinstance : " + mi.get_name())
	var mesh = mi.mesh

	var mdt = MeshDataTool.new()

	# only surface 0 for now
	mdt.create_from_surface(mesh, 0)

	var nVerts = mdt.get_vertex_count()
	var nFaces = mdt.get_face_count()

	var xform = mi.global_transform

	for n in nVerts:
		var vert = mdt.get_vertex(n)
		var norm = mdt.get_vertex_normal(n)
		var col = mdt.get_vertex_color(n)
		var uv = mdt.get_vertex_uv(n)
#		var uv2 = mdt.get_vertex_uv2(n)
#		var tang = mdt.get_vertex_tangent(n)

		if use_local_space == false:
			vert = xform * vert
			norm = xform.basis * norm
			norm = norm.normalized()
#			tang = xform.basis * tang

		if norm:
			st.set_normal(norm)
		if col:
			st.set_color(col)
		if uv:
			st.set_uv(uv)
#		if uv2:
#			st.set_uv2(uv2)
#		if tang:
#			st.set_tangent(tang)
		st.add_vertex(vert)

	# indices
	for f in nFaces:
		for i in range(3):
			var ind = mdt.get_face_vertex(f, i)

			# index must take into account the vertices of previously added meshes
			st.add_index(ind + vertex_count)

	# new running vertex count
	return vertex_count + nVerts


static func _split_mesh_by_surface(
	mdt: MeshDataTool,
	orig_mi: MeshInstance3D,
	attachment_node: Node,
	surf_id: int,
	use_local_space: bool
):
	var nVerts = mdt.get_vertex_count()
	var nFaces = mdt.get_face_count()

	var tmpMesh = ArrayMesh.new()

	var mat = orig_mi.mesh.surface_get_material(surf_id)

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)

	var xform = orig_mi.global_transform

	for n in mdt.get_vertex_count():
		var vert = mdt.get_vertex(n)
		var norm = mdt.get_vertex_normal(n)
		var col = mdt.get_vertex_color(n)
		var uv = mdt.get_vertex_uv(n)
#		var uv2 = mdt.get_vertex_uv2(n)
#		var tang = mdt.get_vertex_tangent(n)

		if use_local_space == false:
			vert = xform * vert
			norm = xform.basis * norm
			norm = norm.normalized()
#			tang = xform.basis * tang

		if norm:
			st.set_normal(norm)
		if col:
			st.set_color(col)
		if uv:
			st.set_uv(uv)
#		if uv2:
#			st.set_uv2(uv2)
#		if tang:
#			st.set_tangent(tang)
		st.add_vertex(vert)

	for f in mdt.get_face_count():
		for i in range(3):
			var ind = mdt.get_face_vertex(f, i)
			st.add_index(ind)

	st.commit(tmpMesh)

	var new_mi = MeshInstance3D.new()
	new_mi.mesh = tmpMesh
	
	if new_mi.mesh.get_surface_count():		
		new_mi.set_surface_override_material(0, mat)

	if use_local_space:
		new_mi.transform = orig_mi.transform

	var sz = orig_mi.get_name() + "_" + str(surf_id)
	if mat:
		if mat.resource_name != "":
			sz += "_" + mat.resource_name
	new_mi.set_name(sz)

	# add the new mesh as a child
	attachment_node.add_child(new_mi)
	new_mi.owner = attachment_node.owner


func _check_aabb(aabb: AABB):
	assert(aabb.size.x >= 0)
	assert(aabb.size.y >= 0)
	assert(aabb.size.z >= 0)


func _calc_aabb(mesh_instance: MeshInstance3D):
	var aabb: AABB = mesh_instance.get_transformed_aabb()
	# godot intersection doesn't work on borders ...
	aabb = aabb.grow(0.1)
	return aabb
	

static func _set_owner_recursive(node, owner):
	if node != owner:
		node.set_owner(owner)

	for i in range(node.get_child_count()):
		_set_owner_recursive(node.get_child(i), owner)


static func save_scene(node, filename):
	var owner = node.get_owner()
	_set_owner_recursive(node, node)

	var packed_scene = PackedScene.new()
	packed_scene.pack(node)
	ResourceSaver.save(packed_scene, filename)
