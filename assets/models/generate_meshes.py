"""
generate_meshes.py — run this in Blender's Scripting tab (Blender 3.x or 4.x).

Generates all tower base/head meshes and enemy meshes for the carl tower-defense
game and exports them as .glb files into assets/models/towers and
assets/models/enemies.

Run: open Blender → Scripting tab → Open this file → Run Script.
"""

import bpy
import bmesh
import math
import mathutils
import os

TOWER_DIR = "/Users/samlawrence/Documents/src/carl/assets/models/towers"
ENEMY_DIR = "/Users/samlawrence/Documents/src/carl/assets/models/enemies"
os.makedirs(TOWER_DIR, exist_ok=True)
os.makedirs(ENEMY_DIR, exist_ok=True)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        bpy.data.meshes.remove(block)


def export_glb(filepath: str):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print(f"  exported → {filepath}")


def add_cylinder(radius_bot, radius_top, depth, segments=12, location=(0,0,0)):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=segments,
        radius=radius_bot,
        depth=depth,
        location=location,
    )
    obj = bpy.context.active_object
    # Taper top if needed by scaling top loop verts
    if radius_top != radius_bot:
        bpy.ops.object.mode_set(mode='EDIT')
        bm = bmesh.from_edit_mesh(obj.data)
        bm.verts.ensure_lookup_table()
        top_y = depth / 2
        scale = radius_top / radius_bot if radius_bot != 0 else 1.0
        for v in bm.verts:
            if abs(v.co.y - top_y) < 0.001:
                v.co.x *= scale
                v.co.z *= scale
        bmesh.update_edit_mesh(obj.data)
        bpy.ops.object.mode_set(mode='OBJECT')
    return obj


def add_box(sx, sy, sz, location=(0,0,0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.active_object
    obj.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(scale=True)
    return obj


def add_sphere(radius, u=10, v=8, location=(0,0,0)):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=u, ring_count=v, radius=radius, location=location
    )
    return bpy.context.active_object


def join_all():
    """Join all mesh objects in the scene into one."""
    bpy.ops.object.select_all(action='SELECT')
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.join()
    return bpy.context.active_object


# Blender primitive_cylinder_add places the cylinder centered on the given
# location with Y as up. We want objects to sit with base at Y=0, so we pass
# location=(x, depth/2, z).

def cyl(r1, r2, depth, seg=12, x=0, y_base=0, z=0):
    return add_cylinder(r1, r2, depth, segments=seg,
                        location=(x, y_base + depth/2, z))


def box(sx, sy, sz, x=0, y_base=0, z=0):
    return add_box(sx, sy, sz, location=(x, y_base + sy/2, z))


def sphere(r, u=10, v=8, x=0, y=0, z=0):
    return add_sphere(r, u, v, location=(x, y, z))


# ---------------------------------------------------------------------------
# TOWER BASE
# ---------------------------------------------------------------------------

def make_tower_base():
    print("tower/base …")
    clear_scene()
    cyl(0.60, 0.50, 0.60, seg=8)           # main frustum, base at y=0
    cyl(0.54, 0.54, 0.06, seg=8, y_base=0.60)  # shoulder lip on top
    join_all()
    export_glb(os.path.join(TOWER_DIR, "base.glb"))


# ---------------------------------------------------------------------------
# CANNON — split into two meshes so GDScript can color them independently:
#   cannon_body.glb  → always grey: boxy armour housing + gun barrel tube
#   cannon_cap.glb   → elemental color: octagonal lid that sits on the housing
#
# Coordinate conventions (same as all other meshes):
#   Y is up.  Base of the assembled turret head sits at Y=0.
#   Gun barrel points along −Z (forward).
#   Both meshes share the same local origin so they align when placed on
#   $Turret/Barrel (body) and $Turret/Head (cap) in the Godot scene.
#
# Body height: 0.28 units.  Cap sits at Y=0.28, height 0.10.
# ---------------------------------------------------------------------------

CANNON_BODY_H  = 0.28   # height of the main housing
CANNON_CAP_H   = 0.10   # height of the elemental cap disc
CANNON_BODY_W  = 0.54   # X width of housing
CANNON_BODY_D  = 0.48   # Z depth of housing


def make_cannon_body():
    """
    Grey housing + gun barrel.  Assigned to $Turret/Barrel in Godot (made
    visible for cannon; hidden for other tower types).
    """
    print("tower/cannon_body …")
    clear_scene()

    # ── Main housing box, base at Y=0 ──────────────────────────────────────
    box(CANNON_BODY_W, CANNON_BODY_H, CANNON_BODY_D)

    # ── Armour cheek-plates: two thick slabs on the sides, slightly proud ──
    # They overlap the housing sides and read as bolted armour panels.
    cheek_w = 0.08
    cheek_h = CANNON_BODY_H * 0.72
    cheek_d = CANNON_BODY_D * 0.60
    for sx in (-1, 1):
        box(cheek_w, cheek_h, cheek_d,
            x=sx * (CANNON_BODY_W * 0.5 + cheek_w * 0.35),
            y_base=CANNON_BODY_H * 0.14)

    # ── Barrel collar: a short cylinder ring where the tube exits the front ─
    collar_r  = 0.13
    collar_h  = 0.06
    cyl(collar_r, collar_r, collar_h, seg=12,
        y_base=CANNON_BODY_H * 0.28,
        z=-(CANNON_BODY_D * 0.5))

    # ── Gun barrel: round tube pointing along −Z, exits collar center ───────
    barrel_r     = 0.075
    barrel_len   = 0.60
    barrel_z     = -(CANNON_BODY_D * 0.5 + barrel_len * 0.5)
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=10, radius=barrel_r, depth=barrel_len,
        location=(0, CANNON_BODY_H * 0.28, barrel_z),
        rotation=(math.radians(90), 0, 0),
    )

    # ── Muzzle brake: two thin disc rings at the barrel tip ─────────────────
    brake_z = -(CANNON_BODY_D * 0.5 + barrel_len - 0.04)
    for dz in (0.0, 0.07):
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=10, radius=barrel_r + 0.035, depth=0.025,
            location=(0, CANNON_BODY_H * 0.28, brake_z - dz),
            rotation=(math.radians(90), 0, 0),
        )

    join_all()
    export_glb(os.path.join(TOWER_DIR, "cannon_body.glb"))


def make_cannon_cap():
    """
    Elemental cap disc — sits on top of the housing at Y=CANNON_BODY_H.
    Assigned to $Turret/Head in Godot; GDScript tints this with the
    elemental color (grey pre-upgrade, then fire/frost/shock/poison).
    The 16-segment octagonal profile is visually distinct from the boxy
    housing so the two pieces read as separate at a glance.
    """
    print("tower/cannon_cap …")
    clear_scene()

    cap_r = CANNON_BODY_W * 0.52   # slightly wider than the housing top

    # ── Main cap disc ────────────────────────────────────────────────────────
    cyl(cap_r, cap_r * 0.88, CANNON_CAP_H, seg=16, y_base=CANNON_BODY_H)

    # ── Central raised dome — the 'eye' that glows with element color ────────
    dome_r = cap_r * 0.36
    sphere(dome_r, u=12, v=8,
           y=CANNON_BODY_H + CANNON_CAP_H + dome_r * 0.55)

    join_all()
    export_glb(os.path.join(TOWER_DIR, "cannon_cap.glb"))


# ---------------------------------------------------------------------------
# FROST HEAD  — hex prism + dome + 4 crystal spikes
# ---------------------------------------------------------------------------

def make_frost_head():
    print("tower/frost_head …")
    clear_scene()

    # Hex prism body centered at origin
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=6, radius=0.28, depth=0.30, location=(0, 0, 0)
    )

    # Dome on top
    sphere(0.18, u=8, v=6, y=0.24)

    # Four crystal spikes: thin elongated boxes tilted 40° upward, spun N/S/E/W
    for angle_deg in [0, 90, 180, 270]:
        angle_rad = math.radians(angle_deg)
        tilt = math.radians(50)   # from vertical → 50° = mostly upward but leaning out
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
        obj = bpy.context.active_object
        obj.scale = (0.06, 0.28, 0.06)
        bpy.ops.object.transform_apply(scale=True)
        # Rotate spike: tilt out from vertical then spin around Y
        obj.rotation_euler = (0, tilt, angle_rad)
        bpy.ops.object.transform_apply(rotation=True)
        # Offset so base is near body edge
        obj.location = (
            math.sin(angle_rad) * 0.22,
            0.05,
            math.cos(angle_rad) * 0.22,
        )

    join_all()
    export_glb(os.path.join(TOWER_DIR, "frost_head.glb"))


# ---------------------------------------------------------------------------
# BEAM HEAD  — tapered obelisk + coil ring + emitter cap
# ---------------------------------------------------------------------------

def make_beam_head():
    print("tower/beam_head …")
    clear_scene()

    # Obelisk: tapered octagonal prism, base at y=0
    cyl(0.18, 0.08, 0.55, seg=8)

    # Coil ring: flattened sphere acting as a torus ring near the top
    add_sphere(1.0, u=16, v=8, location=(0, 0.48, 0))
    obj = bpy.context.active_object
    obj.scale = (0.21, 0.045, 0.21)
    bpy.ops.object.transform_apply(scale=True)

    # Emitter cap at tip
    sphere(0.07, u=8, v=6, y=0.585)

    join_all()
    export_glb(os.path.join(TOWER_DIR, "beam_head.glb"))


# ---------------------------------------------------------------------------
# BOMB HEAD  — wide housing box + angled mortar tube
# ---------------------------------------------------------------------------

def make_bomb_head():
    print("tower/bomb_head …")
    clear_scene()

    # Wide box housing centered at origin
    add_box(0.60, 0.28, 0.55, location=(0, 0, 0))

    # Mortar tube: fat cylinder, angled 30° toward −Z from vertical
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=10, radius=0.13, depth=0.48,
        location=(0, 0.34, -0.08),
        rotation=(math.radians(30), 0, 0),
    )
    # Slight taper on top
    obj = bpy.context.active_object
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    for v in bm.verts:
        if v.co.y > 0.22:
            v.co.x *= 0.85
            v.co.z *= 0.85
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.object.mode_set(mode='OBJECT')

    join_all()
    export_glb(os.path.join(TOWER_DIR, "bomb_head.glb"))


# ---------------------------------------------------------------------------
# GRUNT  — boxy humanoid
# ---------------------------------------------------------------------------

def make_grunt():
    print("enemy/grunt …")
    clear_scene()

    box(0.42, 0.50, 0.30, y_base=0.30)          # torso
    add_box(0.32, 0.32, 0.32, location=(0, 1.06, 0))  # head
    box(0.14, 0.28, 0.20, x= 0.13, y_base=0.0)  # left leg
    box(0.14, 0.28, 0.20, x=-0.13, y_base=0.0)  # right leg
    box(0.10, 0.34, 0.14, x= 0.28, y_base=0.35) # left arm
    box(0.10, 0.34, 0.14, x=-0.28, y_base=0.35) # right arm

    join_all()
    export_glb(os.path.join(ENEMY_DIR, "grunt.glb"))


# ---------------------------------------------------------------------------
# HEALER  — rounded body + cross on back
# ---------------------------------------------------------------------------

def make_healer():
    print("enemy/healer …")
    clear_scene()

    # Tapered cylinder body
    cyl(0.30, 0.26, 0.65, seg=12, y_base=0.20)

    # Dome top
    sphere(0.28, u=12, v=8, y=0.85)
    obj = bpy.context.active_object
    # Delete bottom half of the dome (verts below y=0.85)
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(obj.data)
    del_faces = [f for f in bm.faces if f.calc_center_median().y < 0.85]
    bmesh.ops.delete(bm, geom=del_faces, context='FACES')
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.object.mode_set(mode='OBJECT')

    # Cross emblem on back (Z offset places it on the body surface)
    box(0.06, 0.24, 0.04, y_base=0.58, z=0.31)  # vertical bar
    box(0.20, 0.06, 0.04, y_base=0.67, z=0.31)  # horizontal bar

    join_all()
    export_glb(os.path.join(ENEMY_DIR, "healer.glb"))


# ---------------------------------------------------------------------------
# GUNNER  — heavy boxy humanoid with shoulder gun
# ---------------------------------------------------------------------------

def make_gunner():
    print("enemy/gunner …")
    clear_scene()

    box(0.46, 0.54, 0.32, y_base=0.30)           # torso
    add_box(0.30, 0.30, 0.30, location=(0, 1.10, 0))  # head
    box(0.14, 0.30, 0.22, x= 0.14, y_base=0.0)   # left leg
    box(0.14, 0.30, 0.22, x=-0.14, y_base=0.0)   # right leg
    box(0.10, 0.34, 0.14, x=-0.30, y_base=0.37)  # left arm (no gun)
    box(0.10, 0.20, 0.14, x= 0.30, y_base=0.54)  # right arm (short, connects to gun)
    box(0.14, 0.14, 0.18, x= 0.32, y_base=0.67)  # gun housing on right shoulder

    # Gun barrel: cylinder pointing −Z from the housing
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=8, radius=0.045, depth=0.55,
        location=(0.32, 0.74, -0.365),
        rotation=(math.radians(90), 0, 0),
    )

    join_all()
    export_glb(os.path.join(ENEMY_DIR, "gunner.glb"))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

print("=== generating carl meshes ===")
make_tower_base()
make_cannon_body()   # replaces make_cannon_head() — split into body + cap
make_cannon_cap()
make_frost_head()
make_beam_head()
make_bomb_head()
make_grunt()
make_healer()
make_gunner()
print("=== done ===")
