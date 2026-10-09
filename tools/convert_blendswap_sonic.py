"""Converts the Sonic model "Sonic Hedgehog" (Blend Swap #90639, CC BY 3.0, fan art,
non-commercial) into one Roblox-ready mesh.

It puts Sonic in his T-pose, merges all body parts into one mesh under Roblox's
20,000-triangle limit, bakes every material (colours and eye textures) into a
single texture, and exports FBX + GLB for Roblox Studio's Avatar Setup.

Usage (with `pip install bpy`, or `blender -b -P ... -- ...`):
    python tools/convert_blendswap_sonic.py -- "path/to/Sonic the Hedghog.blend"
Outputs: models/SonicHedgehog.fbx, models/SonicHedgehog.glb, models/SonicHedgehog_color.png
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "models"))
TARGET_TRIS = 19000
TEXTURE_SIZE = 2048
ROOT_RIG = "Reference.001"
SKIP = {"Teeth"}  # hidden inside the head


def descendants_of(root):
    def inside(o):
        while o:
            if o == root:
                return True
            o = o.parent
        return False

    return [o for o in bpy.data.objects if inside(o)]


def main(blend_path):
    os.makedirs(OUT, exist_ok=True)
    # Never run scripts embedded in a downloaded .blend file.
    bpy.context.preferences.filepaths.use_scripts_auto_execute = False
    bpy.ops.wm.open_mainfile(filepath=blend_path, load_ui=False)
    bpy.ops.file.find_missing_files(directory=os.path.join(os.path.dirname(blend_path), "Image"))

    root = bpy.data.objects[ROOT_RIG]
    family = descendants_of(root) + [root]
    # T-pose the body but keep the artist's face pose (open eyes, eye direction):
    # reset every bone of the main rig to its rest pose except the face bones.
    def is_face_bone(bone):
        if "Eye" in bone.name:
            return True
        parent = bone.parent
        while parent:
            if parent.name == "Head":
                return True
            parent = parent.parent
        return False

    for pb in root.pose.bones:
        if not is_face_bone(pb.bone):
            pb.location = (0, 0, 0)
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.rotation_euler = (0, 0, 0)
            pb.rotation_axis_angle = (0, 0, 1, 0)
            pb.scale = (1, 1, 1)
    bpy.context.view_layer.update()
    sources = [o for o in family if o.type == "MESH" and len(o.data.polygons) and o.name not in SKIP]
    for o in sources:
        for m in o.modifiers:
            if m.type == "SUBSURF":
                m.levels = 1  # smooth, but light enough to reduce cleanly

    # The eyeballs look white in the original only thanks to a glossy shine,
    # which a flat texture can't keep, so whiten their base colour.
    eyeball = bpy.data.materials.get("Material.001")
    if eyeball and eyeball.node_tree:
        tree = eyeball.node_tree
        out = next(n for n in tree.nodes if n.type == "OUTPUT_MATERIAL")
        for n in tree.nodes:
            if n.type == "BSDF_DIFFUSE":
                n.inputs["Color"].default_value = (0.92, 0.93, 0.95, 1)
                tree.links.new(n.outputs["BSDF"], out.inputs["Surface"])

    # Bake a copy of every part, with modifiers applied, into one mesh.
    depsgraph = bpy.context.evaluated_depsgraph_get()
    copies = []
    for o in sources:
        mesh = bpy.data.meshes.new_from_object(o.evaluated_get(depsgraph), depsgraph=depsgraph)
        copy = bpy.data.objects.new(o.name + "_copy", mesh)
        copy.matrix_world = o.matrix_world.copy()
        # Give every part's texture map the same name so they survive the merge
        # (the eyes' iris textures need theirs).
        for layer in list(mesh.uv_layers)[1:]:
            mesh.uv_layers.remove(layer)
        if mesh.uv_layers:
            mesh.uv_layers[0].name = "OrigUV"
        bpy.context.scene.collection.objects.link(copy)
        copies.append(copy)
    bpy.ops.object.select_all(action="DESELECT")
    for c in copies:
        c.select_set(True)
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.join()
    body = bpy.context.active_object
    body.name = body.data.name = "SonicHedgehog"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # 0) Reduce to Roblox's triangle limit first (original UVs are carried along).
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    if tris > TARGET_TRIS:
        dec = body.modifiers.new("reduce", "DECIMATE")
        dec.ratio = TARGET_TRIS / tris
        bpy.ops.object.modifier_apply(modifier="reduce")

    # 1) Lay out a new UV map for the combined texture, keeping each part's
    #    original UVs for its own textures (eyes, shoes...).
    mesh = body.data
    original_uv = "OrigUV" if "OrigUV" in mesh.uv_layers else None
    bake_uv = mesh.uv_layers.new(name="BakeUV")
    mesh.uv_layers.active = bake_uv
    for layer in mesh.uv_layers:
        layer.active_render = layer.name == (original_uv or "BakeUV")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.006)
    bpy.ops.object.mode_set(mode="OBJECT")

    # 2) Bake every material's colour straight onto its own surface (no ray
    #    casting between parts, so hidden inner layers can't leak through).
    image = bpy.data.images.new("SonicHedgehog_color", TEXTURE_SIZE, TEXTURE_SIZE)
    for slot in body.material_slots:
        if not slot.material:
            continue
        slot.material = slot.material.copy()
        tree = slot.material.node_tree
        node = tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        uvnode = tree.nodes.new("ShaderNodeUVMap")
        uvnode.uv_map = "BakeUV"
        tree.links.new(uvnode.outputs["UV"], node.inputs["Vector"])
        for n in tree.nodes:
            n.select = False
        node.select = True
        tree.nodes.active = node
    if not all(slot.material for slot in body.material_slots) or not body.material_slots:
        fallback = bpy.data.materials.new("fallback_white")
        body.data.materials.append(fallback)

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    for o in sources:
        o.hide_render = True
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_selected_to_active=False, margin=16)
    image.filepath_raw = os.path.join(OUT, "SonicHedgehog_color.png")
    image.file_format = "PNG"
    image.save()

    # 3) One material with the baked texture and only the bake UVs.
    mat = bpy.data.materials.new("SonicHedgehog")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.45
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    mesh.materials.clear()
    mesh.materials.append(mat)
    for layer in list(mesh.uv_layers):
        if layer.name != "BakeUV":
            mesh.uv_layers.remove(layer)
    mesh.uv_layers["BakeUV"].active_render = True

    bpy.ops.object.shade_smooth()

    # Export only the finished mesh, standing on the ground at the origin.
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "SonicHedgehog.glb"), export_format="GLB", use_selection=True)
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "SonicHedgehog.fbx"), use_selection=True,
                             path_mode="COPY", embed_textures=True, apply_unit_scale=True)
    after = sum(len(p.vertices) - 2 for p in body.data.polygons)
    d = body.dimensions
    print(f"parts {len(sources)}; {tris} -> {after} triangles; size {d.x:.2f} x {d.y:.2f} x {d.z:.2f}")


main(sys.argv[sys.argv.index("--") + 1])
