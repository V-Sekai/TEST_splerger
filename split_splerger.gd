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


func split_branch(
	node: Node,
	attachment_node: Node,
	grid_size: float = 0.64,
	grid_size_y: float = 0.64,
	use_local_space: bool = false
):
	var si: _SplitInfo = _SplitInfo.new()
	si.grid_size = grid_size
	si.grid_size_y = grid_size_y
	si.use_local_space = use_local_space

	var meshlist = []
	var splitlist = []

	_find_meshes_recursive(node, meshlist, si)

	# record which meshes have been successfully split .. for these we will
	# remove the original mesh
	splitlist.resize(meshlist.size())

	for m in range(meshlist.size()):
		print("mesh " + meshlist[m].get_name())

		if split(meshlist[m], attachment_node, grid_size, grid_size_y, use_local_space) == true:
			splitlist[m] = true

	for m in range(meshlist.size()):
		if splitlist[m] == true:
			var mi = meshlist[m]
			mi.get_parent().remove_child(mi)
			#mi.queue_delete()

	print("split_branch FINISHED.")
	pass


func _get_num_splits_x(si: _SplitInfo) -> int:
	var splits = int(floor(si.aabb.size.x / si.grid_size))
	if splits < 1:
		splits = 1
	return splits


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


func _find_meshes_recursive(node: Node, meshlist, si: _SplitInfo):
	# is it a mesh?
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		si.aabb = _calc_aabb(mi)
		print("mesh " + mi.get_name() + "\n\tAABB " + str(si.aabb))

		var splits_x = _get_num_splits_x(si)
		var splits_y = _get_num_splits_y(si)
		var splits_z = _get_num_splits_z(si)

		if (splits_x + splits_y + splits_z) > 3:
			meshlist.push_back(mi)
			print("\tfound mesh to split : " + mi.get_name())
			print(
				"\t\tsplits_x : " + str(splits_x) + " _y " + str(splits_y) + " _z " + str(splits_z)
			)
			#print("\tAABB is " + str(aabb))

	for c in range(node.get_child_count()):
		_find_meshes_recursive(node.get_child(c), meshlist, si)


# split a mesh according to the grid size
func split(
	mesh_instance: MeshInstance3D,
	attachment_node: Node,
	grid_size: float,
	grid_size_y: float,
	use_local_space: bool = false,
	delete_orig: bool = false
):
	# save all the info we can into a class to avoid passing it around
	var si: _SplitInfo = _SplitInfo.new()
	si.grid_size = grid_size
	si.grid_size_y = grid_size_y
	si.use_local_space = use_local_space

	# calculate the AABB
	si.aabb = _calc_aabb(mesh_instance)
	si.x_splits = _get_num_splits_x(si)
	si.y_splits = _get_num_splits_y(si)
	si.z_splits = _get_num_splits_z(si)

	print(
		(
			mesh_instance.get_name()
			+ " : x_splits "
			+ str(si.x_splits)
			+ " y_splits "
			+ str(si.y_splits)
			+ " z_splits "
			+ str(si.z_splits)
		)
	)

	## no need to split .. should never happen
	if (si.x_splits + si.y_splits + si.z_splits) == 3:
		print("WARNING - not enough splits, ignoring")
		return false

	var mesh = mesh_instance.mesh

	var mdt = MeshDataTool.new()
	mdt.create_from_surface(mesh, 0)

	var nVerts = mdt.get_vertex_count()
	if nVerts == 0:
		return true

	# new .. create pre transformed to world space verts, no need to transform for each split
	var world_verts = PackedVector3Array([Vector3(0, 0, 0)])
	world_verts.resize(nVerts)
	var xform = mesh_instance.global_transform
	for n in range(nVerts):
		world_verts.set(n, xform * mdt.get_vertex(n))

	print("\tnVerts " + str(nVerts))

	# only allow faces to be assigned to one of the splits
	# i.e. prevent duplicates in more than 1 split
	var nFaces = mdt.get_face_count()
	var faces_assigned = []
	faces_assigned.resize(nFaces)

	# each split
	for z in range(si.z_splits):
		for y in range(si.y_splits):
			for x in range(si.x_splits):
				_split_mesh(
					mdt, mesh_instance, x, y, z, si, attachment_node, faces_assigned, world_verts
				)

	return true


#class UniqueVert:
#	var m_OrigInd : int


func _split_mesh(
	mdt: MeshDataTool,
	orig_mi: MeshInstance3D,
	grid_x: float,
	grid_y: float,
	grid_z: float,
	si: _SplitInfo,
	attachment_node: Node,
	faces_assigned,
	world_verts: PackedVector3Array
):
	print("\tsplit " + str(grid_x) + ", " + str(grid_y) + ", " + str(grid_z))

	# find the subregion of the aabb
	var xgap = si.aabb.size.x / si.x_splits
	var ygap = si.aabb.size.y / si.y_splits
	var zgap = si.aabb.size.z / si.z_splits
	var pos = si.aabb.position
	pos.x += grid_x * xgap
	pos.y += grid_y * ygap
	pos.z += grid_z * zgap
	var aabb = AABB(pos, Vector3(xgap, ygap, zgap))

	# godot intersection doesn't work on borders ...
	aabb = aabb.grow(0.1)

	if m_bDebug_Split:
		print("\tAABB : " + str(aabb))

	var nVerts = mdt.get_vertex_count()
	var nFaces = mdt.get_face_count()

	# find all faces that overlap the new aabb and add them to a new mesh
	var faces = []

	var face_aabb: AABB

#	var bDebug = false
#	if m_bDebug_Split && (grid_x == 0) && (grid_z == 0):
#		bDebug = true
#	var sz = ""

	var xform = orig_mi.global_transform

	for f in range(nFaces):
		#if (f % 2000) == 0:
		#	print (".")
		#if bDebug:
		#	sz = "face " + str(f) + "\n"

		for i in range(3):
			var ind = mdt.get_face_vertex(f, i)
			#var vert = mdt.get_vertex(ind)
			#vert = xform.xform(vert)
			var vert = world_verts[ind]

			#if bDebug:
			#	sz += "v" + str(i) + " " + str(vert) + "\n"

			if i == 0:
				face_aabb = AABB(vert, Vector3(0, 0, 0))
			else:
				face_aabb = face_aabb.expand(vert)

		#if bDebug:
		#	print(sz)

		# does this face overlap the aabb?
		if aabb.intersects(face_aabb):
			# only allow one split to contain a face
			if faces_assigned[f] != true:
				faces.push_back(f)
				faces_assigned[f] = true

	if faces.size() == 0:
		print("\tno faces, ignoring...")
		return

	# find unique verts
	var new_inds = []
	var unique_verts = []

	#print ("mapping start")
	# use a mapping of original to unique indices to speed up finding unique verts
	var ind_mapping = []
	ind_mapping.resize(mdt.get_vertex_count())
	for i in range(mdt.get_vertex_count()):
		ind_mapping[i] = -1

	for n in range(faces.size()):
		var f = faces[n]
		for i in range(3):
			var ind = mdt.get_face_vertex(f, i)

			var new_ind = _find_or_add_unique_vert(ind, unique_verts, ind_mapping)
			new_inds.push_back(new_ind)

	#print ("mapping end")

	var tmpMesh = ArrayMesh.new()

	#print(orig_mi.get_name() + " orig mat count " + str(orig_mi.mesh.get_surface_count()))
	#var mat = orig_mi.get_surface_material(0)
	var mat = orig_mi.mesh.surface_get_material(0)

	#var mat = Node3DMaterial.new()
	#mat = mat_orig
	#var color = Color(0.1, 0.8, 0.1)
	#mat.albedo_color = color

	var st : SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)

	for u in unique_verts.size():
		var n = unique_verts[u]

		var vert = mdt.get_vertex(n)
		var norm = mdt.get_vertex_normal(n)
		var col = mdt.get_vertex_color(n)
		var uv = mdt.get_vertex_uv(n)
#		var uv2 = mdt.get_vertex_uv2(n)
#		var tang = mdt.get_vertex_tangent(n)

		if si.use_local_space == false:
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
	for i in new_inds.size():
		st.add_index(new_inds[i])

	#print ("commit start")

	st.commit(tmpMesh)

	var new_mi : MeshInstance3D = MeshInstance3D.new()
	new_mi.mesh = tmpMesh
	
	if new_mi.mesh.get_surface_count():
		new_mi.set_surface_override_material(0, mat)

	new_mi.set_name(orig_mi.get_name() + "_" + str(grid_x) + str(grid_z))

	if si.use_local_space:
		new_mi.transform = orig_mi.transform

	# add the new mesh as a child
	attachment_node.add_child(new_mi)
	new_mi.owner = attachment_node.owner


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


static func split_by_surface(
	orig_mi: MeshInstance3D, attachment_node: Node, use_local_space: bool = false
):
	print("split_by_surface " + orig_mi.get_name())

	var mesh = orig_mi.mesh

	var surface_count : int = mesh.get_surface_count()
	
	for s in range(surface_count):
		var mdt = MeshDataTool.new()
		mdt.create_from_surface(mesh, s)

		var nVerts = mdt.get_vertex_count()
		if not nVerts:
			continue

		_split_mesh_by_surface(mdt, orig_mi, attachment_node, s, use_local_space)

	# delete orig mesh
	orig_mi.get_parent().remove_child(orig_mi)
#	orig_mi.queue_delete()


static func split_multi_surface_meshes(node: Node):
	var children : Array[Node] = node.find_children("*", "MeshInstance3D")
	for mesh_instance_3d in children:
		split_by_surface(mesh_instance_3d, mesh_instance_3d.get_parent())


func _list_mesh_instances(node, list):
	if node is MeshInstance3D:
		if node.get_child_count() == 0:
			var mi: MeshInstance3D = node
			if mi.get_surface_material_count() <= 1:
				list.push_back(node)

	for c in range(node.get_child_count()):
		_list_mesh_instances(node.get_child(c), list)


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
