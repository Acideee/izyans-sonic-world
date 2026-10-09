"""Generates src/shared/SonicModel.json: the cartoon Sonic body, built from
rounded Roblox parts that are welded onto an invisible R15 skeleton.

Each piece: part (R15 limb it rides on), shape (sphere | cylinder | block),
size [x,y,z] studs, pos [x,y,z] offset from that limb's centre in its own
space (-Z is the front), rot [x,y,z] degrees (CFrame.Angles order), tint.
Cylinders run along X, like Roblox's cylinder parts.

Run:  python3 tools/make_sonic_model.py
"""
import json, math, os

pieces = []

def add(part, shape, size, pos, rot=(0, 0, 0), tint="blue", name=None):
    pieces.append({
        "name": name or tint,
        "part": part, "shape": shape,
        "size": [round(v, 3) for v in size],
        "pos": [round(v, 3) for v in pos],
        "rot": [round(v, 2) for v in rot],
        "tint": tint,
    })

def norm(v):
    l = math.sqrt(sum(c * c for c in v))
    return [c / l for c in v]

def aim(t):
    """Euler angles (deg, CFrame.Angles order) that turn +Z to point along t."""
    t = norm(t)
    ry = math.asin(max(-1, min(1, t[0])))
    rx = math.atan2(-t[1], t[2])
    return (math.degrees(rx), math.degrees(ry), 0)

# ---------------------------------------------------------------- head
HEAD_C = (0, 0.45, 0.1)          # centre of the big round head
add("Head", "sphere", (2.5, 2.4, 2.4), HEAD_C, name="Head")

# Quills: tapered chains of overlapping ellipsoids that sweep back and flick up.
QUILLS = [
    # base offset from head centre, direction, length, base width, upward curl
    ((0, 0.75, 0.55), (0, 0.25, 1), 2.2, 1.45, 0.2),
    ((0, 0.05, 0.75), (0, -0.2, 1), 2.6, 1.6, 0.28),
    ((0, -0.6, 0.6), (0, -0.75, 1), 2.1, 1.3, 0.38),
    ((0.6, 0.3, 0.55), (0.55, 0.0, 1), 1.7, 1.1, 0.18),
    ((-0.6, 0.3, 0.55), (-0.55, 0.0, 1), 1.7, 1.1, 0.18),
]
SEGMENTS = 14
for base, d, length, w0, curl in QUILLS:
    d = norm(d)
    b = [HEAD_C[i] + base[i] for i in range(3)]
    for k in range(SEGMENTS):
        s = (k + 0.5) / SEGMENTS
        p = [b[i] + d[i] * length * s for i in range(3)]
        p[1] += curl * length * s * s
        tan = [d[i] * length for i in range(3)]
        tan[1] += 2 * curl * length * s
        w = w0 * (1 - 0.9 * s)
        seg = length / SEGMENTS * 4.0
        add("Head", "sphere", (w, w * 0.8, seg), p, aim(tan), name="Quill")

# Ears
for side in (1, -1):
    add("Head", "sphere", (0.5, 0.95, 0.38), (side * 0.78, 1.55, 0.05), (0, 0, -side * 22), name="Ear")
    add("Head", "sphere", (0.28, 0.6, 0.1), (side * 0.76, 1.5, -0.15), (0, 0, -side * 22), "peach", "InnerEar")

# Face
add("Head", "sphere", (1.45, 0.95, 1.0), (0, 0.02, -0.82), tint="peach", name="Muzzle")
for side in (1, -1):
    add("Head", "sphere", (0.78, 1.12, 0.46), (side * 0.3, 0.62, -0.98), (0, side * 12, side * 4), "white", "Eye")
    add("Head", "sphere", (0.4, 0.66, 0.16), (side * 0.22, 0.58, -1.18), (0, side * 12, 0), "iris", "Iris")
    add("Head", "sphere", (0.2, 0.36, 0.1), (side * 0.2, 0.6, -1.25), (0, side * 12, 0), "black", "Pupil")
    add("Head", "sphere", (0.1, 0.15, 0.05), (side * 0.15, 0.72, -1.29), (0, side * 12, 0), "white", "Shine")
add("Head", "sphere", (0.34, 0.26, 0.3), (0, 0.36, -1.3), tint="black", name="Nose")
add("Head", "sphere", (0.75, 0.1, 0.14), (0.1, -0.16, -1.3), (0, 0, -12), "mouth", "Smile")

# ---------------------------------------------------------------- body
add("UpperTorso", "sphere", (1.55, 1.8, 1.15), (0, -0.05, 0.05), name="Chest")
add("UpperTorso", "sphere", (1.15, 1.35, 0.42), (0, -0.15, -0.43), tint="peach", name="Belly")
add("LowerTorso", "sphere", (1.45, 0.85, 1.05), (0, 0.05, 0.05), name="Hips")
add("LowerTorso", "sphere", (0.5, 0.42, 0.75), (0, 0.15, 0.62), (-30, 0, 0), name="Tail")

# Arms: thin peach arms pulled in towards the body, big white gloves.
for limb, side in (("Right", 1), ("Left", -1)):
    x = -side * 0.5
    add(limb + "UpperArm", "sphere", (0.48, 0.48, 0.48), (x, 0.3, 0), tint="peach", name="Shoulder")
    add(limb + "UpperArm", "cylinder", (1.0, 0.42, 0.42), (x, -0.08, 0), (0, 0, 90), "peach", "Arm")
    add(limb + "LowerArm", "cylinder", (1.05, 0.4, 0.4), (x, 0, 0), (0, 0, 90), "peach", "Arm")
    add(limb + "Hand", "cylinder", (0.32, 0.78, 0.78), (x, 0.3, 0), (0, 0, 90), "white", "Cuff")
    add(limb + "Hand", "sphere", (0.85, 0.8, 0.85), (x, -0.15, 0), tint="white", name="Glove")

# Legs: thin blue legs, white socks, big red shoes with a white strap and gold buckle.
for limb, side in (("Right", 1), ("Left", -1)):
    add(limb + "UpperLeg", "cylinder", (1.25, 0.48, 0.48), (0, 0, 0), (0, 0, 90), name="Leg")
    add(limb + "LowerLeg", "cylinder", (1.2, 0.44, 0.44), (0, 0, 0), (0, 0, 90), name="Leg")
    add(limb + "LowerLeg", "cylinder", (0.3, 0.62, 0.62), (0, -0.55, 0), (0, 0, 90), "white", "Sock")
    add(limb + "Foot", "sphere", (1.0, 0.8, 1.95), (0, 0.12, -0.38), tint="red", name="Shoe")
    add(limb + "Foot", "sphere", (0.95, 0.22, 0.55), (0, 0.42, -0.3), (-12, 0, 0), "white", "Strap")
    add(limb + "Foot", "sphere", (0.12, 0.24, 0.24), (side * 0.47, 0.38, -0.3), tint="gold", name="Buckle")
    add(limb + "Foot", "block", (0.95, 0.12, 1.75), (0, -0.25, -0.38), tint="sole", name="Sole")

model = {
    "colors": {
        "blue": [25, 75, 230], "peach": [245, 200, 150], "white": [252, 252, 252],
        "iris": [40, 175, 70], "black": [15, 15, 20], "mouth": [70, 25, 25],
        "red": [220, 25, 35], "gold": [255, 205, 40], "sole": [235, 235, 235],
    },
    "superColors": {"blue": [255, 214, 40], "iris": [215, 30, 40]},
    "pieces": pieces,
}
out = os.path.join(os.path.dirname(__file__), "..", "src", "shared", "SonicModel.json")
with open(out, "w") as f:
    json.dump(model, f, indent=1)
print(f"wrote {len(pieces)} pieces to {os.path.normpath(out)}")
