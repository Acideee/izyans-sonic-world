"""Builds a smooth, textured Sonic character model in Blender for Roblox.

Shapes (rounded body, tapered curved quills, eyes, gloves, shoes) are built
from code, fused into ONE smooth mesh, reduced to fit Roblox's triangle limit,
and the colours are baked into a texture. Sonic stands in an A-pose so Roblox
Studio's Avatar Setup can rig him automatically.

Run with Blender's Python module (pip install bpy) or Blender itself:
    python tools/blender_sonic.py            (needs `bpy`)
    blender -b -P tools/blender_sonic.py
Outputs go to models/: SonicCharacter.glb, SonicCharacter.fbx, SonicCharacter_color.png
"""

import math
import os

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "models"))
TARGET_TRIS = 18000  # Roblox allows up to 20,000 triangles per mesh
TEXTURE_SIZE = 2048

# Blender is Z-up. Sonic faces -Y (towards Blender's front view); +Y is his back.
COLORS = {
    "blue": (25, 75, 230),
    "peach": (245, 200, 150),
    "white": (250, 250, 250),
    "iris": (40, 180, 70),
    "black": (12, 12, 16),
    "mouth": (80, 25, 25),
    "red": (215, 20, 30),
    "gold": (255, 200, 40),
    "sole": (225, 225, 225),
}


def srgb_to_linear(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def make_material(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*[srgb_to_linear(v) for v in rgb], 1)
    bsdf.inputs["Roughness"].default_value = 0.5
    return mat


MATS = {}
PARTS = []


def tag(obj, color):
    if color not in MATS:
        MATS[color] = make_material("src_" + color, COLORS[color])
    obj.data.materials.clear()
    obj.data.materials.append(MATS[color])
    PARTS.append(obj)
    return obj


def ellipsoid(center, size, color, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=32, radius=1, location=center, rotation=[math.radians(r) for r in rot])
    obj = bpy.context.active_object
    obj.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    bpy.ops.object.shade_smooth()
    return tag(obj, color)


def limb(a, b, radius_a, radius_b, color):
    """Rounded tube from a to b (cone + ball ends)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cone_add(vertices=40, radius1=radius_a, radius2=radius_b, depth=d.length, location=(a + b) / 2)
    obj = bpy.context.active_object
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = d.normalized().to_track_quat("Z", "Y")
    tag(obj, color)
    ellipsoid(a, (radius_a * 2,) * 3, color)
    ellipsoid(b, (radius_b * 2,) * 3, color)


def spike(points, base_radius, color, tip=0.03, taper=True):
    """Smooth curved spike: a bezier tube whose thickness tapers to a point."""
    curve = bpy.data.curves.new("spike", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = base_radius
    curve.bevel_resolution = 8
    curve.resolution_u = 16
    curve.use_fill_caps = True
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    n = len(points)
    for i, p in enumerate(points):
        bp = spline.bezier_points[i]
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
        t = i / (n - 1)
        bp.radius = max(tip, (1 - t) ** 1.15) if taper else 1.0
    obj = bpy.data.objects.new("spike", curve)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    # Round off the flat end caps so they fuse nicely.
    ellipsoid(points[0], (base_radius * 2,) * 3, color)
    if not taper:
        ellipsoid(points[-1], (base_radius * 2,) * 3, color)
    return tag(obj, color)


def add(v, w):
    return tuple(v[i] + w[i] for i in range(3))


def build_sonic():
    # ----------------------------------------------------------- legs & shoes
    for s in (1, -1):
        x = 0.36 * s
        limb((x, 0, 0.62), (x * 1.05, 0, 1.45), 0.13, 0.15, "blue")  # shin
        limb((x * 1.05, 0, 1.45), (x * 0.85, 0, 2.2), 0.15, 0.19, "blue")  # thigh
        ellipsoid((x, 0, 0.62), (0.42, 0.42, 0.22), "white")  # sock cuff
        ellipsoid((x * 1.08, -0.3, 0.27), (0.62, 1.35, 0.55), "red")  # shoe
        ellipsoid((x * 1.08, -0.2, 0.45), (0.58, 0.42, 0.22), "white", rot=(-15, 0, 0))  # strap
        ellipsoid((x * 1.08 + 0.29 * s, -0.2, 0.44), (0.1, 0.18, 0.16), "gold")  # buckle
        ellipsoid((x * 1.08, -0.3, 0.05), (0.6, 1.3, 0.12), "sole")  # sole

    # ----------------------------------------------------------- body
    ellipsoid((0, 0.02, 2.32), (0.82, 0.62, 0.62), "blue")  # hips
    ellipsoid((0, 0.02, 2.85), (0.92, 0.68, 1.15), "blue")  # chest
    ellipsoid((0, -0.2, 2.72), (0.66, 0.36, 0.95), "peach")  # belly
    spike([(0, 0.25, 2.25), (0, 0.48, 2.18), (0, 0.62, 2.28)], 0.12, "blue")  # tail
    for s in (1, -1):  # two small quills on the back
        spike([(0.16 * s, 0.25, 3.05), (0.26 * s, 0.6, 2.85), (0.3 * s, 0.85, 2.85)], 0.17, "blue")

    # ----------------------------------------------------------- arms (A-pose, 45° down)
    for s in (1, -1):
        shoulder = Vector((0.42 * s, 0, 3.22))
        down = Vector((0.72 * s, 0, -0.69)).normalized()
        elbow = shoulder + down * 0.72
        wrist = elbow + down * 0.66
        limb(shoulder, elbow, 0.11, 0.1, "peach")
        limb(elbow, wrist, 0.1, 0.095, "peach")
        cuff_c = wrist + down * 0.06
        bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=0.2, depth=0.16, location=cuff_c)
        cuff = bpy.context.active_object
        cuff.rotation_mode = "QUATERNION"
        cuff.rotation_quaternion = down.to_track_quat("Z", "Y")
        tag(cuff, "white")
        ellipsoid(cuff_c + down * 0.26, (0.5, 0.42, 0.48), "white")  # glove

    # ----------------------------------------------------------- head
    head = Vector((0, 0, 4.0))
    ellipsoid(head, (1.62, 1.55, 1.5), "blue")
    # Face: Sonic's look comes from eyes that join in the middle, a blue brow
    # slanting down over them, pupils looking ahead together, and a smirk.
    ellipsoid(head + Vector((0, -0.56, -0.27)), (0.9, 0.62, 0.58), "peach")  # muzzle
    ellipsoid(head + Vector((0, -0.92, -0.06)), (0.24, 0.2, 0.18), "black")  # nose
    spike([head + Vector(p) for p in [(-0.12, -0.855, -0.36), (0.08, -0.85, -0.37), (0.22, -0.8, -0.32), (0.3, -0.73, -0.24)]],
          0.024, "mouth", taper=False)  # smirk
    for s in (1, -1):
        eye = ellipsoid(head + Vector((0.13 * s, -0.58, 0.2)), (0.52, 0.42, 0.82), "white", rot=(0, -10 * s, -12 * s))
        # Slice the top of the eye along a line sloping down towards the nose,
        # so the blue head forms Sonic's determined brow.
        inner = head + Vector((0.0, 0, 0.36))
        outer = head + Vector((0.42 * s, 0, 0.53))
        along = (outer - inner).normalized()
        up = Vector((-along.z * s, 0, abs(along.x))).normalized()
        if up.z < 0:
            up = -up
        bpy.ops.mesh.primitive_cube_add(size=1, location=(inner + outer) / 2 + up * 0.5)
        cutter = bpy.context.active_object
        cutter.scale = (2.0, 2.0, 1.0)
        cutter.rotation_euler = (0, math.atan2(-(outer.z - inner.z), outer.x - inner.x), 0)
        cut = eye.modifiers.new("brow", "BOOLEAN")
        cut.operation = "DIFFERENCE"
        cut.object = cutter
        bpy.context.view_layer.objects.active = eye
        bpy.ops.object.modifier_apply(modifier="brow")
        bpy.data.objects.remove(cutter, do_unlink=True)
        ellipsoid(head + Vector((0.16 * s - 0.035, -0.765, 0.15)), (0.24, 0.1, 0.4), "iris", rot=(0, -10 * s, 0))
        ellipsoid(head + Vector((0.16 * s - 0.045, -0.805, 0.15)), (0.12, 0.06, 0.24), "black", rot=(0, -10 * s, 0))
        ellipsoid(head + Vector((0.16 * s - 0.075, -0.825, 0.22)), (0.05, 0.03, 0.07), "white")
        # ears
        bpy.ops.mesh.primitive_cone_add(vertices=40, radius1=0.25, radius2=0.02, depth=0.62,
                                        location=head + Vector((0.44 * s, 0.05, 0.78)), rotation=(0, math.radians(18 * s), 0))
        ear = bpy.context.active_object
        bpy.ops.object.shade_smooth()
        tag(ear, "blue")
        bpy.ops.mesh.primitive_cone_add(vertices=40, radius1=0.15, radius2=0.01, depth=0.42,
                                        location=head + Vector((0.44 * s, -0.1, 0.76)), rotation=(0, math.radians(18 * s), 0))
        inner = bpy.context.active_object
        inner.scale = (1, 0.45, 1)
        bpy.ops.object.shade_smooth()
        tag(inner, "peach")

    # Quills: long, curved, sweeping back and down with the tips flicking up.
    H = (0, 0, 4.0)
    quills = [
        ([(0, 0.15, 0.55), (0, 0.95, 0.62), (0, 1.75, 0.95)], 0.42),
        ([(0, 0.45, 0.1), (0, 1.3, -0.05), (0, 2.05, 0.18)], 0.46),
        ([(0, 0.4, -0.38), (0, 1.1, -0.72), (0, 1.8, -0.62)], 0.38),
        ([(0.32, 0.3, 0.32), (0.62, 1.0, 0.2), (0.82, 1.55, 0.42)], 0.3),
        ([(-0.32, 0.3, 0.32), (-0.62, 1.0, 0.2), (-0.82, 1.55, 0.42)], 0.3),
        ([(0.3, 0.3, -0.25), (0.55, 0.95, -0.55), (0.7, 1.4, -0.45)], 0.26),
        ([(-0.3, 0.3, -0.25), (-0.55, 0.95, -0.55), (-0.7, 1.4, -0.45)], 0.26),
    ]
    for pts, r in quills:
        spike([add(H, p) for p in pts], r, "blue")


def fuse_and_bake():
    # Duplicate every source part and fuse the copies into one smooth surface.
    bpy.ops.object.select_all(action="DESELECT")
    for obj in PARTS:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = PARTS[0]
    bpy.ops.object.duplicate()
    bpy.ops.object.join()
    body = bpy.context.active_object
    body.name = "SonicCharacter"
    body.data.name = "SonicCharacter"
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    remesh = body.modifiers.new("fuse", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = 0.018
    remesh.adaptivity = 0
    bpy.ops.object.modifier_apply(modifier="fuse")

    # Iron out the tiny "staircase" ridges left by the voxel fusing.
    smooth = body.modifiers.new("smooth", "LAPLACIANSMOOTH")
    smooth.iterations = 12
    smooth.lambda_factor = 0.6
    smooth.use_volume_preserve = True
    bpy.ops.object.modifier_apply(modifier="smooth")

    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    dec = body.modifiers.new("reduce", "DECIMATE")
    dec.ratio = min(1.0, TARGET_TRIS / max(tris, 1))
    bpy.ops.object.modifier_apply(modifier="reduce")
    polish = body.modifiers.new("polish", "LAPLACIANSMOOTH")
    polish.iterations = 6
    polish.lambda_factor = 0.5
    polish.use_volume_preserve = True
    bpy.ops.object.modifier_apply(modifier="polish")
    bpy.ops.object.shade_smooth()

    # UVs + an image to paint the colours into.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")

    image = bpy.data.images.new("SonicCharacter_color", TEXTURE_SIZE, TEXTURE_SIZE)
    mat = bpy.data.materials.new("SonicCharacter")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.45
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nodes.active = tex
    body.data.materials.clear()
    body.data.materials.append(mat)

    # Bake the colours of the original parts onto the fused mesh.
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    bpy.ops.object.select_all(action="DESELECT")
    for obj in PARTS:
        obj.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.bake(
        type="DIFFUSE",
        pass_filter={"COLOR"},
        use_selected_to_active=True,
        cage_extrusion=0.06,
        max_ray_distance=0.2,
        margin=8,
    )
    image.filepath_raw = os.path.join(OUT, "SonicCharacter_color.png")
    image.file_format = "PNG"
    image.save()

    # Keep only the finished character for export.
    for obj in PARTS:
        bpy.data.objects.remove(obj, do_unlink=True)
    return body, tris


def main():
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_sonic()
    body, before = fuse_and_bake()
    after = sum(len(p.vertices) - 2 for p in body.data.polygons)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "SonicCharacter.glb"), export_format="GLB", use_selection=True)
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "SonicCharacter.fbx"), use_selection=True,
                             path_mode="COPY", embed_textures=True, apply_unit_scale=True)
    dims = body.dimensions
    print(f"fused {before} -> {after} triangles; size {dims.x:.2f} x {dims.y:.2f} x {dims.z:.2f}")


main()
