"""Converts the Blend Swap Sonic models into one Roblox-ready mesh each:
"Sonic Hedgehog" (#90639) and "Super Sonic" (#92091), both CC BY 3.0, fan art,
non-commercial.

It puts Sonic in his T-pose, merges all body parts into one mesh under Roblox's
20,000-triangle limit, bakes every material (colours and eye textures) into a
single texture, and exports FBX + GLB for Roblox Studio's Avatar Setup.

With "parts" as the last argument it instead cuts Sonic into the 15 Roblox
R15 body pieces (Head, UpperTorso, LeftUpperArm, ...), lowers his arms to his
sides and exports them as separate meshes. The game attaches those pieces to
Roblox's standard skeleton, so no Avatar Setup is needed.

Usage (with `pip install bpy`, or `blender -b -P ... -- ...`):
    python tools/convert_blendswap_sonic.py -- "path/to/Sonic the Hedghog.blend"
    python tools/convert_blendswap_sonic.py -- "path/to/Super Sonic (2).blend" SuperSonic gold
    python tools/convert_blendswap_sonic.py -- "path/to/Sonic the Hedghog.blend" SonicParts none parts
    python tools/convert_blendswap_sonic.py -- "path/to/Super Sonic (2).blend" SuperSonicParts gold parts
Outputs: models/<name>.fbx, models/<name>.glb, models/<name>_color.png (name defaults to SonicHedgehog)
"""

import json
import math
import os
import sys

import bpy
import bmesh  # noqa: E402  (must come after bpy)
from mathutils import Matrix, Vector, kdtree

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "models"))
TARGET_TRIS = 19000
TEXTURE_SIZE = 2048
ROOT_RIG = "Reference.001"
SKIP = {"Teeth"}  # hidden inside the head
# Roblox R15 body pieces, and which bone of the model's rig each one follows.
R15_PARTS = ["Head", "UpperTorso", "LowerTorso",
             "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
             "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]
BONE_TO_PART = {
    "Head": "Head", "Neck": "Head", "Spine1": "UpperTorso", "Spine": "LowerTorso",
    "Hips": "LowerTorso", "master bone": "LowerTorso",
    # The rig's "_L" bones are on Sonic's own left.
    "UpperArm_L": "LeftUpperArm", "ForeArm_L": "LeftLowerArm", "Hand_L": "LeftHand",
    "UpperArm_R": "RightUpperArm", "ForeArm_R": "RightLowerArm", "Hand_R": "RightHand",
    "Thigh_L": "LeftUpperLeg", "Calf_L": "LeftLowerLeg", "Foot_L": "LeftFoot",
    "Thigh_R": "RightUpperLeg", "Calf_R": "RightLowerLeg", "Foot_R": "RightFoot",
}


def part_for_bone(bone_name):
    """Which R15 piece a bone of the model's rig belongs to (walks up to a known bone)."""
    ref = bpy.data.objects[ROOT_RIG].data.bones
    bone = ref.get(bone_name)
    if bone is None:
        rig = bpy.data.objects.get("rig")
        if rig and bone_name in rig.data.bones:
            return "Head"  # the face/mouth rig
        return None
    while bone:
        if bone.name in BONE_TO_PART:
            return BONE_TO_PART[bone.name]
        bone = bone.parent
    return None


def face_parts(obj, mesh):
    """R15 piece index for every face of `mesh` (an evaluated copy of `obj`)."""
    fallback = None
    if obj.parent_type == "BONE" and obj.parent_bone:
        fallback = part_for_bone(obj.parent_bone)
    group_part = {}
    for g in obj.vertex_groups:
        part = part_for_bone(g.name)
        if part:
            group_part[g.index] = R15_PARTS.index(part)
    vert_weights = []
    for v in mesh.vertices:
        w = {}
        for g in v.groups:
            if g.group in group_part and g.weight > 0:
                k = group_part[g.group]
                w[k] = w.get(k, 0) + g.weight
        vert_weights.append(w)
    labels = []
    for poly in mesh.polygons:
        total = {}
        for vi in poly.vertices:
            for k, wt in vert_weights[vi].items():
                total[k] = total.get(k, 0) + wt
        if total:
            labels.append(max(total, key=total.get))
        else:
            labels.append(R15_PARTS.index(fallback) if fallback else -1)
    # Faces with no information take the object's most common piece.
    known = [l for l in labels if l >= 0]
    common = max(set(known), key=known.count) if known else R15_PARTS.index("UpperTorso")
    return [l if l >= 0 else common for l in labels]


# Lip control moves (in studs) that open a confident smirk on the Super Sonic file.
SMIRK = {
    "MCH_Mouth_Lip_Low.L": (0.0, 0.0, -0.07),
    "MCH_Mouth_Lip_Low.R": (0.0, 0.0, -0.05),
    "MCH_Mouth_Lip_High.L": (0.0, 0.0, 0.02),
    "MCH_Mouth_Lip.L": (0.05, 0.0, 0.07),
    "MCH_Mouth_Lip.R": (-0.02, 0.0, 0.02),
}
# Eyelid bone poses from the Sonic Hedgehog file (eyes open, determined look).
OPEN_EYES = [
    ("BrowA_C.001", (0.85, 0.036, 0.0, 0.525), (1, 1, 1)),
    ("BrowA_C.002", (0.955, -0.02, 0.0, -0.295), (0.499, 0.499, 0.499)),
    ("mad", (0.716, 0.047, 0.0, 0.0), (1, 1, 1)),
    ("top r", (0.989, -0.01, 0.0, 0.0), (1, 1, 1)),
    ("top l", (0.962, -0.021, 0.0, 0.0), (1, 1, 1)),
]


def descendants_of(root):
    def inside(o):
        while o:
            if o == root:
                return True
            o = o.parent
        return False

    return [o for o in bpy.data.objects if inside(o)]


def main(blend_path, name="SonicHedgehog", fur=None, mode=None):
    parts_mode = mode == "parts"
    os.makedirs(OUT, exist_ok=True)
    # Never run scripts embedded in a downloaded .blend file.
    bpy.context.preferences.filepaths.use_scripts_auto_execute = False
    bpy.ops.wm.open_mainfile(filepath=blend_path, load_ui=False)
    bpy.ops.file.find_missing_files(directory=os.path.dirname(blend_path))  # textures shipped alongside
    # Some textures are linked as "name (2).png" but shipped as "name.png".
    for img in bpy.data.images:
        path = bpy.path.abspath(img.filepath)
        if img.filepath and not os.path.exists(path):
            alt = os.path.join(os.path.dirname(blend_path), os.path.basename(path).replace(" (2)", ""))
            if os.path.exists(alt):
                img.filepath = alt
                img.reload()

    # Freeze any animation into a fixed pose, so it can't override the pose
    # changes below (it would undo the smirk and open eyes).
    bpy.context.scene.frame_set(bpy.context.scene.frame_current)
    for ob in bpy.data.objects:
        if ob.type == "ARMATURE":
            frozen = {pb.name: pb.matrix_basis.copy() for pb in ob.pose.bones}
            if ob.animation_data:
                ob.animation_data_clear()
            for pb in ob.pose.bones:
                pb.matrix_basis = frozen[pb.name]

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

    # Super Sonic's gold comes from a glow effect in the original, not the base
    # colour (which is dark blue), so set the fur's base colour to gold.
    if fur == "gold":
        tree = bpy.data.materials["Fur"].node_tree
        out = next(n for n in tree.nodes if n.type == "OUTPUT_MATERIAL")
        for n in tree.nodes:
            if n.type == "BSDF_DIFFUSE":
                n.inputs["Color"].default_value = (1.0, 0.68, 0.08, 1)
                tree.links.new(n.outputs["BSDF"], out.inputs["Surface"])
        # Super Sonic has red eyes: colour the iris pieces solid red.
        for mat_name in ("Material.004", "new"):
            m = bpy.data.materials.get(mat_name)
            if not m:
                continue
            mout = next(n for n in m.node_tree.nodes if n.type == "OUTPUT_MATERIAL")
            red = m.node_tree.nodes.new("ShaderNodeBsdfDiffuse")
            red.inputs["Color"].default_value = (0.55, 0.01, 0.02, 1)
            m.node_tree.links.new(red.outputs["BSDF"], mout.inputs["Surface"])
        # Its mouth is posed shut, so give him Sonic's face/mouth-rig pose (saved
        # from the Sonic Hedgehog file) and open a smirk with the lip controls.
        face_pose = os.path.join(HERE, "sonic_face_pose.json")
        if os.path.exists(face_pose):
            with open(face_pose) as f:
                for arm_name, bones in json.load(f).items():
                    ob = bpy.data.objects.get(arm_name)
                    for bone_name, m in bones.items():
                        pb = ob.pose.bones.get(bone_name) if ob else None
                        if pb:
                            pb.matrix_basis = Matrix(m)
            bpy.context.view_layer.update()
        rig = bpy.data.objects.get("rig")
        if rig:
            for bone_name, offset in SMIRK.items():
                pb = rig.pose.bones.get(bone_name)
                if pb:
                    pb.matrix = Matrix.Translation(offset) @ pb.matrix
                    bpy.context.view_layer.update()
        # This file was saved with the eyelids shut: open them like in the
        # Sonic Hedgehog file (these bones move the eyelids).
        for bone, quat, scale in OPEN_EYES:
            pb = root.pose.bones.get(bone)
            if pb:
                pb.rotation_quaternion = quat
                pb.scale = scale
        bpy.context.view_layer.update()

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
        mesh = bpy.data.meshes.new_from_object(o.evaluated_get(depsgraph), preserve_all_data_layers=True, depsgraph=depsgraph)
        if parts_mode:
            labels = face_parts(o, mesh)
            attr = mesh.attributes.new("r15", "INT", "FACE")
            attr.data.foreach_set("value", labels)
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
    body.name = body.data.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Turn him around: Roblox imports these files facing the other way, which
    # makes Avatar Setup build a skeleton that runs backwards.
    body.rotation_euler = (0, 0, math.pi)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)

    # Remember which piece each face belongs to, by position, so the labels
    # survive the triangle reduction below.
    if parts_mode:
        values = [0] * len(body.data.polygons)
        body.data.attributes["r15"].data.foreach_get("value", values)
        face_tree = kdtree.KDTree(len(body.data.polygons))
        for poly in body.data.polygons:
            face_tree.insert(poly.center, poly.index)
        face_tree.balance()

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
    image = bpy.data.images.new(name + "_color", TEXTURE_SIZE, TEXTURE_SIZE)
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
    image.filepath_raw = os.path.join(OUT, name + "_color.png")
    image.file_format = "PNG"
    image.save()

    # 3) One material with the baked texture and only the bake UVs.
    mat = bpy.data.materials.new(name)
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

    if parts_mode:
        labels = [values[face_tree.find(poly.center)[1]] for poly in mesh.polygons]
        export_parts(body, labels, name, tris)
        return

    # Export only the finished mesh, standing on the ground at the origin.
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", use_selection=True)
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, name + ".fbx"), use_selection=True,
                             path_mode="COPY", embed_textures=True, apply_unit_scale=True)
    after = sum(len(p.vertices) - 2 for p in body.data.polygons)
    d = body.dimensions
    print(f"parts {len(sources)}; {tris} -> {after} triangles; size {d.x:.2f} x {d.y:.2f} x {d.z:.2f}")


def export_parts(body, labels, name, tris_before):
    """Split the finished mesh into R15 pieces, lower the arms, and export."""
    pieces = {}
    for index, part in enumerate(R15_PARTS):
        if index not in labels:
            continue
        obj = body.copy()
        obj.data = body.data.copy()
        obj.name = obj.data.name = part
        bpy.context.scene.collection.objects.link(obj)
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if labels[f.index] != index], context="FACES")
        bm.to_mesh(obj.data)
        bm.free()
        pieces[part] = obj
    bpy.data.objects.remove(body, do_unlink=True)

    # A few fingertip faces get labelled as torso/head; out at arm height and
    # far to the side they can only be arm bits left behind, so drop them.
    # (The chest and hips are never more than ~1 unit wide either side; the
    # head is left alone because its quills do reach out to the sides.)
    for part, limit in (("Head", 1.85), ("UpperTorso", 1.0), ("LowerTorso", 1.0)):
        obj = pieces.get(part)
        if not obj:
            continue
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        stray = [f for f in bm.faces
                 if abs(f.calc_center_median().x) > limit and 3.4 < f.calc_center_median().z < 4.4]
        bmesh.ops.delete(bm, geom=stray, context="FACES")
        bm.to_mesh(obj.data)
        bm.free()

    # Roblox's standard skeleton stands with its arms down, so swing each arm
    # (upper arm, lower arm, hand) down around the shoulder, a little out.
    for side in ("Left", "Right"):
        chain = [pieces.get(side + n) for n in ("UpperArm", "LowerArm", "Hand")]
        upper = chain[0]
        if not upper:
            continue
        verts = [upper.matrix_world @ v.co for v in upper.data.vertices]
        outward = 1 if sum(v.x for v in verts) / len(verts) > 0 else -1
        shoulder = min(verts, key=lambda v: abs(v.x))
        pivot = Vector((shoulder.x, sum(v.y for v in verts) / len(verts), sum(v.z for v in verts) / len(verts)))
        turn = (Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(80 * outward), 4, "Y")
                @ Matrix.Translation(-pivot))
        for obj in chain:
            if obj:
                obj.data.transform(turn)
                obj.data.update()

    bpy.ops.object.select_all(action="DESELECT")
    for obj in pieces.values():
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    for obj in pieces.values():
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", use_selection=True)
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, name + ".fbx"), use_selection=True,
                             path_mode="COPY", embed_textures=True, apply_unit_scale=True)
    summary = ", ".join(f"{p} {sum(len(f.vertices) - 2 for f in o.data.polygons)}" for p, o in pieces.items())
    print(f"pieces {len(pieces)} from {tris_before} triangles: {summary}")


args = [a for a in sys.argv[sys.argv.index("--") + 1:]]
if len(args) >= 3 and args[2] == "none":
    args[2] = None
main(*args)
