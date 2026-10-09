"""Exports the original "Sonic Hedgehog" model (Blend Swap #90639) as-is for
Roblox: the artist's own parts, shape and main skeleton ("Reference.001").

Everything is kept as the artist built it: both skeletons (the body skeleton
and the separate mouth rig), every part's weights, and every part attached to
the same bone or object as in the original. Only these change:
- Each part's colours are painted into an image, since Roblox can't read
  Blender's colour settings.
- The skeleton is exported in its rest pose (arms out, as the artist built it).

Run:  python tools/export_original_sonic.py -- "path/to/Sonic the Hedghog.blend"
Output: models/SonicOriginal.fbx
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "models"))
SKELETON = "Reference.001"
TEXTURE_SIZE = 1024


def main(blend_path):
    os.makedirs(OUT, exist_ok=True)
    bpy.context.preferences.filepaths.use_scripts_auto_execute = False
    bpy.ops.wm.open_mainfile(filepath=blend_path, load_ui=False)
    bpy.ops.file.find_missing_files(directory=os.path.join(os.path.dirname(blend_path), "Image"))

    # Rest pose, no animation.
    for ob in bpy.data.objects:
        if ob.type == "ARMATURE":
            if ob.animation_data:
                ob.animation_data_clear()
            ob.data.pose_position = "REST"
    bpy.context.view_layer.update()

    skel = bpy.data.objects[SKELETON]

    def inside(o):
        while o:
            if o == skel:
                return True
            o = o.parent
        return False

    sources = [o for o in bpy.data.objects if o.type == "MESH" and inside(o) and len(o.data.polygons)]
    skeletons = [o for o in bpy.data.objects if o.type == "ARMATURE" and inside(o)]

    # The eyeballs' white comes from a shine; give them a plain white colour.
    eyeball = bpy.data.materials.get("Material.001")
    if eyeball and eyeball.node_tree:
        out = next(n for n in eyeball.node_tree.nodes if n.type == "OUTPUT_MATERIAL")
        for n in eyeball.node_tree.nodes:
            if n.type == "BSDF_DIFFUSE":
                n.inputs["Color"].default_value = (0.92, 0.93, 0.95, 1)
                eyeball.node_tree.links.new(n.outputs["BSDF"], out.inputs["Surface"])

    depsgraph = bpy.context.evaluated_depsgraph_get()
    finished = []
    for o in sources:
        # Shape with every modifier except the skeleton ones (rest pose anyway).
        saved = []
        for m in o.modifiers:
            if m.type == "ARMATURE":
                saved.append((m, m.show_viewport))
                m.show_viewport = False
        depsgraph.update()
        mesh = bpy.data.meshes.new_from_object(o.evaluated_get(depsgraph), preserve_all_data_layers=True,
                                               depsgraph=depsgraph)
        for m, shown in saved:
            m.show_viewport = shown
        depsgraph.update()

        name = o.name
        o.name = name + "_src"
        new = bpy.data.objects.new(name, mesh)
        mesh.name = name
        new.matrix_world = o.matrix_world.copy()
        bpy.context.scene.collection.objects.link(new)
        for g in o.vertex_groups:
            new.vertex_groups.new(name=g.name)

        # Attach it exactly like the original: same parent, same bone, same
        # skeleton modifiers.
        new.parent = o.parent
        new.parent_type = o.parent_type
        if o.parent_type == "BONE":
            new.parent_bone = o.parent_bone
        new.matrix_parent_inverse = o.matrix_parent_inverse.copy()
        new.matrix_world = o.matrix_world.copy()
        for m in o.modifiers:
            if m.type == "ARMATURE" and m.object:
                mod = new.modifiers.new(m.name, "ARMATURE")
                mod.object = m.object
                mod.use_vertex_groups = m.use_vertex_groups
                mod.use_bone_envelopes = m.use_bone_envelopes
        finished.append(new)

    # Paint each part's colours into its own image.
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    for o in bpy.data.objects:
        o.hide_render = o not in finished
    for new in finished:
        mesh = new.data
        uv_keep = mesh.uv_layers[0].name if mesh.uv_layers else None
        bake_uv = mesh.uv_layers.new(name="BakeUV")
        for layer in mesh.uv_layers:
            layer.active_render = layer.name == (uv_keep or "BakeUV")
        mesh.uv_layers.active = bake_uv
        bpy.ops.object.select_all(action="DESELECT")
        new.select_set(True)
        bpy.context.view_layer.objects.active = new
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.01)
        bpy.ops.object.mode_set(mode="OBJECT")

        image = bpy.data.images.new(new.name + "_color", TEXTURE_SIZE, TEXTURE_SIZE)
        for slot in new.material_slots:
            if not slot.material:
                slot.material = bpy.data.materials.new("plain")
            slot.material = slot.material.copy()
            slot.material.use_nodes = True
            tree = slot.material.node_tree
            node = tree.nodes.new("ShaderNodeTexImage")
            node.image = image
            uvn = tree.nodes.new("ShaderNodeUVMap")
            uvn.uv_map = "BakeUV"
            tree.links.new(uvn.outputs["UV"], node.inputs["Vector"])
            for n in tree.nodes:
                n.select = False
            node.select = True
            tree.nodes.active = node
        if not new.material_slots:
            new.data.materials.append(bpy.data.materials.new("plain"))
            continue
        bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_selected_to_active=False, margin=8)

        mat = bpy.data.materials.new(new.name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        mesh.materials.clear()
        mesh.materials.append(mat)
        for layer in list(mesh.uv_layers):
            if layer.name != "BakeUV":
                mesh.uv_layers.remove(layer)
        image.filepath_raw = os.path.join(OUT, "SonicOriginal_" + new.name + ".png")
        image.file_format = "PNG"
        image.save()

    # The skeletons live in hidden collections; Blender only exports visible
    # objects, so show them.
    for sk in skeletons:
        for coll in sk.users_collection:
            coll.hide_viewport = False
        sk.hide_viewport = False
        sk.hide_set(False)

    # Export only the skeletons and the finished parts.
    bpy.ops.object.select_all(action="DESELECT")
    for sk in skeletons:
        sk.select_set(True)
    for new in finished:
        new.select_set(True)
    bpy.context.view_layer.objects.active = skel
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(OUT, "SonicOriginal.fbx"),
        use_selection=True,
        object_types={"ARMATURE", "MESH"},
        add_leaf_bones=False,
        bake_anim=False,
        path_mode="COPY",
        embed_textures=True,
        apply_unit_scale=True,
    )
    tris = {n.name: sum(len(p.vertices) - 2 for p in n.data.polygons) for n in finished}
    print(f"exported {len(finished)} parts, skeletons {[(sk.name, len(sk.data.bones)) for sk in skeletons]}; biggest part "
          f"{max(tris, key=tris.get)} {max(tris.values())} triangles; total {sum(tris.values())}")


main(sys.argv[sys.argv.index("--") + 1])
