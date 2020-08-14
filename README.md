# godot-splerger
Mesh splitting and merging script for Godot 3.2

## Installation
Either install as an addon, or simply copy splerger.gd to your project, and it should be available to use.

## Instructions
All functionality is inside the Splerger class. You must create a splerger object before doing anything else:
```
var splerger = Splerger.new()
```
## Merging
```
func merge_meshinstances(var mesh_array,
var attachment_node : Node,
var use_local_space : bool = false,
var delete_originals : bool = true):
```
* mesh_array is an array of MeshInstances to be merged
* attachment node is where you want the merged MeshInstance to be added
* use_local_space will not change the coordinate space of the meshes, however it assumes they all share the same local transform as the first mesh instance in the array
* delete_originals - determines whether the original mesh instances will be deleted

e.g.
```
	var splerger = Splerger.new()
	
	var mergelist = []
	mergelist.push_back($Level/Level/Sponza_15_roof_00)
	mergelist.push_back($Level/Level/Sponza_15_roof_10)
	mergelist.push_back($Level/Level/Sponza_15_roof_20)
	mergelist.push_back($Level/Level/Sponza_15_roof_30)
	mergelist.push_back($Level/Level/Sponza_15_roof_40)
	mergelist.push_back($Level/Level/Sponza_15_roof_50)
	mergelist.push_back($Level/Level/Sponza_15_roof_60)
	splerger.merge_meshinstances(mergelist, $Level)
```
_Note only supports single surface meshes so far._
## Splitting by Surface
If a MeshInstance contains more than one surface (material), you can split it into constituent meshes by surface.
```
func split_by_surface(orig_mi : MeshInstance,
attachment_node : Node,
use_local_space : bool = false):
```
## Splitting by Grid
Meshes that are large cannot be culled well, and will either by rendered in their entirety or not at all. Sometimes it is more efficient to split large meshes by their location. Splerger can do this automatically by applying a 3d grid, with a grid size specified for the x and z coordinates, and separately for the y coordinate (height).
```
func split(mesh_instance : MeshInstance,
attachment_node : Node,
grid_size : float,
grid_size_y : float,
use_local_space : bool = false,
delete_orig : bool = true):
```
_Note only supports single surface meshes so far._
## Splitting many meshes by Grid
You can also split multiple MeshInstance with one command:
```
func split_branch(node : Node,
attachment_node : Node,
grid_size : float,
grid_size_y : float = 0.0,
use_local_space : bool = false):
```
This will search recursively and find all the MeshInstances in the scene graph that are children / grandchildren of 'node', and perform a split by grid on them.

# Whole scene functions
## Recursive find and split meshes with multi-surfaces
This will search recursively and each mesh with more than 1 surface it will call `split_by_surface`, attaching the new meshes to the parent of the split mesh.
```
func split_multi_surface_meshes_recursive(var node : Node):
```

## Recursive find mesh siblings with matching materials and merge them
```
func merge_suitable_meshes_recursive(var node : Node):
```

## Recursive find meshes with matching materials and merge (even in different branches)
```
func merge_suitable_meshes_across_branches(var root : Spatial):
```

# Notes
Although this script will perform splitting and merging, because the process can be slow, it is recommended that you apply this as a preprocess and save the resulting MeshInstances for use in game. See here:

https://godotengine.org/qa/903/how-to-save-a-scene-at-run-time

For an explanation of how to save nodes / branches as scenes.

When splitting by grid, the grid origin is the origin of the AABB bound in world space. The grid sizes are in world space. Note that split by grid does not split faces, and large faces than span more than one grid square will be assigned to only one grid square. There is also no duplication of faces, so the number of faces rendered when all the sub meshes are rendered is the same as the number in the original mesh.
