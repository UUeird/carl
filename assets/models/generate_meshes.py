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
# CANNON HEAD  — box body + round barrel along −Z
# Turret sits at y=0.85 in the scene; head is centered at local origin.
# ---------------------------------------------------------------------------

def make_cannon_head():
    print("tower/cannon_head …")
    clear_scene()

    # Box head centered at origin
    add_box(0.55, 0.38, 0.50, location=(0, 0, 0))

    # Barrel: cylinder pointing along Z, rotated so it faces −Z
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=8, radius=0.085, depth=0.65,
        location=(0, 0.05, -0.575),
        rotation=(math.radians(90), 0, 0),
    )

    join_all()
    export_glb(os.path.join(TOWER_DIR, "cannon_head.glb"))


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
make_cannon_head()
make_frost_head()
make_beam_head()
make_bomb_head()
make_grunt()
make_healer()
make_gunner()
print("=== done ===")
