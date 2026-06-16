"""
generate_meshes.py — run this in Blender's Scripting tab (Blender 4.x).

Generates all tower base/head meshes and enemy meshes for the carl tower-defense
game and exports them as .glb files into assets/models/towers and
assets/models/enemies.

Run: open Blender → Scripting tab → Open this file → Run Script.

VISUAL STYLE: clean stylized / chunky.
  Every exported mesh is passed through finalize(), which:
    - shades it smooth,
    - adds a small baked Bevel so edges catch light without being razor sharp,
    - bakes ambient-occlusion-style darkening into a COLOR_0 vertex layer
      (creases/contact areas go dark, exposed faces stay light).
  The tower head/body meshes carry NO material — Godot tints them at runtime via
  material_override. For the baked AO to show, those runtime materials enable
  `vertex_color_use_as_albedo` (see scripts/td_tower.gd). The AO multiplies
  against the elemental colour, giving the flat-tinted caps free depth.

  Round forms use higher segment counts than before so silhouettes read clean
  at the isometric game zoom instead of looking faceted.

COORDINATE CONVENTION (read before editing the helpers!):
  export uses export_yup=True → Blender (x,y,z) maps to glTF/Godot (x, z, −y),
  so **Blender-Z is "up" in the final mesh.** TOWER helpers (cyl/box/sphere)
  stack vertically along Blender-Z to match, because the tower scene places head/
  base meshes with no rotation. ENEMY builders use the separate e_cyl/e_box/
  e_sphere helpers, which keep the ORIGINAL Blender-Y stacking, because
  scenes/td_enemy.tscn rotates the enemy mesh −90° about X to stand it upright.
  Do not unify them — matching the enemies to the towers lays them on their side.
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

# Segment counts — bumped from the old 8/12/16 so curved silhouettes read clean.
SEG_LOW  = 16   # was 8  — frusta, hex-ish bodies
SEG_MED  = 24   # was 12 — barrels, collars, general cylinders
SEG_HIGH = 32   # was 16 — domes, caps, anything prominent

# Bevel applied by finalize() — small enough to stay chunky, big enough to catch light.
BEVEL_WIDTH    = 0.012
BEVEL_SEGMENTS = 2
BEVEL_ANGLE    = math.radians(45.0)   # only bevel hard-ish edges, leave smooth curves

# Ambient-occlusion bake strength (0 = none, 1 = full). Multiplies into vertex colour.
AO_STRENGTH = 0.55


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
        export_vertex_color='ACTIVE',   # carry the baked AO COLOR_0 layer
    )
    print(f"  exported → {filepath}")


def add_cylinder(radius_bot, radius_top, depth, segments=SEG_MED, location=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=segments,
        radius=radius_bot,
        depth=depth,
        location=location,
    )
    obj = bpy.context.active_object
    # Taper top if needed by scaling the top loop verts. The cylinder axis is
    # Blender-Z, so the top loop is at max-Z and the radius plane is X/Y.
    if radius_top != radius_bot:
        bpy.ops.object.mode_set(mode='EDIT')
        bm = bmesh.from_edit_mesh(obj.data)
        bm.verts.ensure_lookup_table()
        top_z = location[2] + depth / 2
        scale = radius_top / radius_bot if radius_bot != 0 else 1.0
        for v in bm.verts:
            if abs(v.co.z - top_z) < 0.001:
                v.co.x *= scale
                v.co.y *= scale
        bmesh.update_edit_mesh(obj.data)
        bpy.ops.object.mode_set(mode='OBJECT')
    return obj


def add_box(sx, sy, sz, location=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.active_object
    obj.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(scale=True)
    return obj


def add_sphere(radius, u=SEG_MED, v=SEG_LOW, location=(0, 0, 0)):
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


# COORDINATE NOTE — the export is the key. primitive_cylinder_add builds its
# axis along Blender-Z, and export_glb uses export_yup=True, which maps Blender
# (x, y, z) → glTF/Godot (x, z, −y). So **Blender-Z is "up" in the final Godot
# mesh.** Anything we want to stack vertically in-game must be offset along
# Blender-Z, and a cylinder's height already runs along Z (no rotation needed).
#
# The y_base / vertical convention below therefore drives the Blender-Z
# coordinate; x and z (the in-game horizontal plane) map to Blender-X and
# Blender-(−Y). We keep the parameter names (x, y_base, z) so existing call
# sites read naturally as "(horizontal x, vertical base, horizontal z)".

def cyl(r1, r2, depth, seg=SEG_MED, x=0, y_base=0, z=0):
    # Stack along Blender-Z (the cylinder's axis and the export's up-axis);
    # the in-game z offset maps to Blender-(−Y).
    return add_cylinder(r1, r2, depth, segments=seg,
                        location=(x, -z, y_base + depth / 2))


def box(sx, sy, sz, x=0, y_base=0, z=0):
    # Cube is symmetric; build it so its vertical size (sy) runs along Blender-Z
    # to match the cylinders and the export's up-axis.
    obj = add_box(sx, sz, sy, location=(x, -z, y_base + sy / 2))
    return obj


def sphere(r, u=SEG_MED, v=SEG_LOW, x=0, y=0, z=0):
    # In-game (x, y, z) → Blender (x, −z, y) so the vertical y maps to Blender-Z.
    return add_sphere(r, u, v, location=(x, -z, y))


def tube_fwd(r1, r2, length, seg=SEG_MED, x=0, y=0, z_center=0.0):
    """A cylinder lying horizontally along the in-game forward axis (−z), centred
    at in-game (x, y, z_center). Used for gun barrels. In-game −z maps to Blender
    +Y, so we rotate the default Z-axis cylinder 90° about Blender-X to lie along
    Blender-Y, then place it (in-game z → Blender −Y)."""
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=seg, radius=r1, depth=length,
        location=(x, -z_center, y),
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    obj = bpy.context.active_object
    bpy.ops.object.transform_apply(rotation=True)
    if r2 != r1:
        # Axis is now Blender-Y; the forward tip is at min-Y (in-game −z).
        bpy.ops.object.mode_set(mode='EDIT')
        bm = bmesh.from_edit_mesh(obj.data)
        bm.verts.ensure_lookup_table()
        tip_y = min(v.co.y for v in bm.verts)
        scale = r2 / r1 if r1 != 0 else 1.0
        for v in bm.verts:
            if abs(v.co.y - tip_y) < 0.001:
                v.co.x *= scale
                v.co.z *= scale
        bmesh.update_edit_mesh(obj.data)
        bpy.ops.object.mode_set(mode='OBJECT')
    return obj


# --- Enemy-convention helpers ------------------------------------------------
# Enemies are authored Blender-Z-up and the enemy SCENE rotates the mesh −90°
# about X to stand it upright (scenes/td_enemy.tscn). That is the opposite of
# the tower meshes (which the tower scene places with no rotation, so they must
# export already Y-up). To keep both families correct through one export path,
# enemy builders use these helpers, which preserve the ORIGINAL convention:
# a piece's vertical size runs along Blender-Y and y_base stacks along Blender-Y.
def e_cyl(r1, r2, depth, seg=SEG_MED, x=0, y_base=0, z=0):
    return add_cylinder(r1, r2, depth, segments=seg,
                        location=(x, y_base + depth / 2, z))


def e_box(sx, sy, sz, x=0, y_base=0, z=0):
    return add_box(sx, sy, sz, location=(x, y_base + sy / 2, z))


def e_sphere(r, u=SEG_MED, v=SEG_LOW, x=0, y=0, z=0):
    return add_sphere(r, u, v, location=(x, y, z))


# ---------------------------------------------------------------------------
# finalize() — the polish pass every tower mesh runs through.
#
# 1. Smooth shading with an auto-smooth angle so flat panels stay crisp while
#    curved bodies read round.
# 2. A baked Bevel modifier (small, angle-limited) so hard edges catch a
#    highlight instead of looking like raw primitives.
# 3. Baked ambient-occlusion into a COLOR_0 vertex layer — cheap fake AO that
#    darkens creases and contact points. Godot multiplies this against the
#    runtime elemental tint (vertex_color_use_as_albedo), so flat-coloured caps
#    gain depth for free.  Computed analytically per-vertex (occlusion ≈ how
#    enclosed the vertex is by nearby geometry) so it works headless with no
#    render bake.
# ---------------------------------------------------------------------------

def _auto_smooth(obj, angle_deg=40.0):
    """Shade smooth but keep sharp edges sharp. Blender 4.1+ removed the mesh
    `use_auto_smooth` flag, so we emulate angle-based auto-smooth directly: flag
    each face smooth, then mark edges sharper than the threshold as flat so
    panels stay crisp while curved bodies read round."""
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    thresh = math.radians(angle_deg)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if len(e.link_faces) == 2:
            a = e.link_faces[0].normal.angle(e.link_faces[1].normal)
            e.smooth = a < thresh
    bm.to_mesh(me)
    bm.free()


def _bake_vertex_ao(obj):
    """Approximate AO per vertex and write it to a COLOR_0 layer.

    Occlusion estimate: for each vertex, sample neighbouring geometry and
    darken vertices that sit low (near the base / contact ground), inside
    concave creases, or surrounded by many faces. This is a stylised, fully
    analytic approximation — no ray bake needed, so it runs headless and fast.
    """
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()

    ys = [v.co.y for v in bm.verts]
    y_min, y_max = (min(ys), max(ys)) if ys else (0.0, 1.0)
    y_span = max(y_max - y_min, 1e-5)

    color_layer = bm.loops.layers.color.get("AO") or bm.loops.layers.color.new("AO")

    ao = {}
    for v in bm.verts:
        # 1. Height term: lower geometry is more occluded (contact shadow at base).
        h = (v.co.y - y_min) / y_span               # 0 at base, 1 at top
        height_occ = (1.0 - h) ** 1.4

        # 2. Concavity term: a vertex whose face normals point inward (away from
        #    its own outward direction) sits in a crease → more occluded.
        if v.link_faces:
            avg_n = mathutils.Vector((0, 0, 0))
            for f in v.link_faces:
                avg_n += f.normal
            avg_n /= len(v.link_faces)
            radial = mathutils.Vector((v.co.x, 0.0, v.co.z))
            if radial.length > 1e-4 and avg_n.length > 1e-4:
                radial.normalize()
                # how much the surface faces inward vs. outward in the XZ plane
                concavity = max(0.0, -avg_n.normalized().dot(radial)) * 0.5
            else:
                concavity = 0.0
            # Many-faced verts (junctions where parts meet) read as crevices.
            junction = min(len(v.link_faces) / 12.0, 1.0) * 0.25
        else:
            concavity = 0.0
            junction = 0.0

        occ = max(height_occ * 0.7, concavity + junction)
        ao[v.index] = 1.0 - AO_STRENGTH * min(occ, 1.0)

    for face in bm.faces:
        for loop in face.loops:
            shade = ao[loop.vert.index]
            loop[color_layer] = (shade, shade, shade, 1.0)

    bm.to_mesh(me)
    bm.free()


def finalize(obj=None, smooth_angle=40.0):
    """Run the full polish pass on a single joined object and return it."""
    if obj is None:
        obj = join_all()
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    # Bevel modifier — angle-limited so only hard edges round off.
    bev = obj.modifiers.new(name="Bevel", type='BEVEL')
    bev.width = BEVEL_WIDTH
    bev.segments = BEVEL_SEGMENTS
    bev.limit_method = 'ANGLE'
    bev.angle_limit = BEVEL_ANGLE
    bpy.ops.object.modifier_apply(modifier=bev.name)

    _auto_smooth(obj, smooth_angle)
    _bake_vertex_ao(obj)
    return obj


# ---------------------------------------------------------------------------
# TOWER BASE — chunkier, two-step pedestal with a chamfered collar.
# ---------------------------------------------------------------------------

def make_tower_base():
    print("tower/base …")
    clear_scene()
    cyl(0.62, 0.50, 0.46, seg=SEG_LOW)               # main frustum, base at y=0
    cyl(0.56, 0.56, 0.10, seg=SEG_LOW, y_base=0.46)  # shoulder ring
    cyl(0.50, 0.46, 0.10, seg=SEG_MED, y_base=0.56)  # raised turret seat
    finalize()
    export_glb(os.path.join(TOWER_DIR, "base.glb"))


# ---------------------------------------------------------------------------
# CANNON / MACHINE GUN — ONE unified head mesh (cannon_head.glb): armoured
# housing + forward gun barrel + cap disc + glowing eye dome, all connected so
# nothing floats apart when the turret aims. (Previously split into cannon_body +
# cannon_cap, which visibly detached when the turret rotated.) The whole head is
# tinted with the elemental colour and gains depth from baked vertex AO.
#
# Coordinate conventions (same as all other tower meshes):
#   vertical = the helpers' y_base axis; gun barrel points forward (in-game −z).
# ---------------------------------------------------------------------------

CANNON_BODY_H  = 0.28
CANNON_CAP_H   = 0.10
CANNON_BODY_W  = 0.54
CANNON_BODY_D  = 0.48


def make_cannon_head():
    """ONE unified turret head: armoured housing + forward gun barrel + cap disc
    + glowing eye dome, all connected so nothing floats apart when the turret
    aims. Assigned to $Turret/Head in Godot (the split body mesh is retired); the
    whole head is tinted with the elemental colour and gains depth from baked AO.

    Built in the new convention: vertical runs along the helpers' y_base; the gun
    points forward along in-game −z (tube_fwd handles that axis)."""
    print("tower/cannon_head …")
    clear_scene()

    # Main housing box, base at Y=0.
    box(CANNON_BODY_W, CANNON_BODY_H, CANNON_BODY_D)

    # Armour cheek-plates: two thick slabs on the sides, slightly proud.
    cheek_w = 0.09
    cheek_h = CANNON_BODY_H * 0.74
    cheek_d = CANNON_BODY_D * 0.62
    for sx in (-1, 1):
        box(cheek_w, cheek_h, cheek_d,
            x=sx * (CANNON_BODY_W * 0.5 + cheek_w * 0.30),
            y_base=CANNON_BODY_H * 0.13)

    # Barrel collar where the tube exits the front (a short ring around the bore).
    barrel_y = CANNON_BODY_H * 0.42
    cyl(0.13, 0.12, 0.07, seg=SEG_MED, y_base=barrel_y - 0.035,
        z=-(CANNON_BODY_D * 0.5))

    # Gun barrel: round tube pointing forward (in-game −z), rooted in the housing.
    barrel_r, barrel_len = 0.072, 0.62
    barrel_center = -(CANNON_BODY_D * 0.5 + barrel_len * 0.5 - 0.06)
    tube_fwd(barrel_r, barrel_r, barrel_len, seg=SEG_MED,
             y=barrel_y, z_center=barrel_center)

    # Muzzle brake: two slightly wider rings near the barrel tip.
    tip_z = barrel_center - barrel_len * 0.5
    for dz in (0.02, 0.08):
        tube_fwd(barrel_r + 0.03, barrel_r + 0.03, 0.025, seg=SEG_MED,
                 y=barrel_y, z_center=tip_z + dz)

    # Cap disc sits on top of the housing.
    cap_r = CANNON_BODY_W * 0.50
    cyl(cap_r, cap_r * 0.86, CANNON_CAP_H, seg=SEG_HIGH, y_base=CANNON_BODY_H)

    # Recessed rim ring for a layered, machined look.
    cyl(cap_r * 0.66, cap_r * 0.66, 0.03, seg=SEG_HIGH,
        y_base=CANNON_BODY_H + CANNON_CAP_H)

    # Central raised dome — the 'eye' that glows with element colour.
    dome_r = cap_r * 0.38
    sphere(dome_r, u=SEG_HIGH, v=SEG_LOW,
           y=CANNON_BODY_H + CANNON_CAP_H + dome_r * 0.45)

    finalize()
    export_glb(os.path.join(TOWER_DIR, "cannon_head.glb"))


# ---------------------------------------------------------------------------
# FROST HEAD  — hex prism + dome + 4 crystal spikes
# ---------------------------------------------------------------------------

def make_frost_head():
    print("tower/frost_head …")
    clear_scene()

    # Hex prism body centered at origin.
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=6, radius=0.28, depth=0.30, location=(0, 0, 0)
    )

    # Dome on top.
    sphere(0.18, u=SEG_MED, v=SEG_LOW, y=0.24)

    # Four crystal spikes: thin elongated boxes tilted out, spun N/S/E/W.
    for angle_deg in [0, 90, 180, 270]:
        angle_rad = math.radians(angle_deg)
        tilt = math.radians(50)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
        obj = bpy.context.active_object
        obj.scale = (0.06, 0.28, 0.06)
        bpy.ops.object.transform_apply(scale=True)
        obj.rotation_euler = (0, tilt, angle_rad)
        bpy.ops.object.transform_apply(rotation=True)
        obj.location = (
            math.sin(angle_rad) * 0.22,
            0.05,
            math.cos(angle_rad) * 0.22,
        )

    # Keep crystal spikes faceted (sharp) — use a low smooth angle so the bevel
    # only kisses the edges and the crystals stay crisp.
    finalize(smooth_angle=24.0)
    export_glb(os.path.join(TOWER_DIR, "frost_head.glb"))


# ---------------------------------------------------------------------------
# BEAM HEAD  — tapered obelisk + coil ring + emitter cap
# ---------------------------------------------------------------------------

def make_beam_head():
    print("tower/beam_head …")
    clear_scene()

    # Obelisk: tapered octagonal prism, base at y=0.
    cyl(0.18, 0.08, 0.55, seg=SEG_LOW)

    # Two stacked coil rings near the top (flattened spheres) for a tesla read.
    for cy_y, cr in ((0.40, 0.20), (0.48, 0.165)):
        add_sphere(1.0, u=SEG_HIGH, v=SEG_LOW, location=(0, cy_y, 0))
        obj = bpy.context.active_object
        obj.scale = (cr, 0.038, cr)
        bpy.ops.object.transform_apply(scale=True)

    # Emitter cap at tip.
    sphere(0.07, u=SEG_MED, v=SEG_LOW, y=0.585)

    finalize()
    export_glb(os.path.join(TOWER_DIR, "beam_head.glb"))


# ---------------------------------------------------------------------------
# BOMB HEAD  — wide housing box + angled mortar tube
# ---------------------------------------------------------------------------

def make_bomb_head():
    print("tower/bomb_head …")
    clear_scene()

    # Wide box housing centered at origin.
    add_box(0.60, 0.28, 0.55, location=(0, 0, 0))

    # Mortar tube: fat cylinder, angled 30° toward −Z from vertical.
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=SEG_MED, radius=0.13, depth=0.48,
        location=(0, 0.34, -0.08),
        rotation=(math.radians(30), 0, 0),
    )
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

    finalize()
    export_glb(os.path.join(TOWER_DIR, "bomb_head.glb"))


# ---------------------------------------------------------------------------
# ENEMIES — kept boxy/stylised; finalize() gives them smooth shading + AO so
# they sit in the same visual language as the towers.
# ---------------------------------------------------------------------------

def make_grunt():
    print("enemy/grunt …")
    clear_scene()
    e_box(0.42, 0.50, 0.30, y_base=0.30)               # torso
    add_box(0.32, 0.32, 0.32, location=(0, 1.06, 0))   # head
    e_box(0.14, 0.28, 0.20, x= 0.13, y_base=0.0)       # left leg
    e_box(0.14, 0.28, 0.20, x=-0.13, y_base=0.0)       # right leg
    e_box(0.10, 0.34, 0.14, x= 0.28, y_base=0.35)      # left arm
    e_box(0.10, 0.34, 0.14, x=-0.28, y_base=0.35)      # right arm
    finalize(smooth_angle=30.0)
    export_glb(os.path.join(ENEMY_DIR, "grunt.glb"))


def make_healer():
    print("enemy/healer …")
    clear_scene()

    e_cyl(0.30, 0.26, 0.65, seg=SEG_MED, y_base=0.20)   # tapered body
    e_sphere(0.28, u=SEG_MED, v=SEG_LOW, y=0.85)        # dome top
    obj = bpy.context.active_object
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(obj.data)
    del_faces = [f for f in bm.faces if f.calc_center_median().y < 0.85]
    bmesh.ops.delete(bm, geom=del_faces, context='FACES')
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.object.mode_set(mode='OBJECT')

    e_box(0.06, 0.24, 0.04, y_base=0.58, z=0.31)        # cross — vertical bar
    e_box(0.20, 0.06, 0.04, y_base=0.67, z=0.31)        # cross — horizontal bar
    finalize(smooth_angle=40.0)
    export_glb(os.path.join(ENEMY_DIR, "healer.glb"))


def make_gunner():
    print("enemy/gunner …")
    clear_scene()
    e_box(0.46, 0.54, 0.32, y_base=0.30)               # torso
    add_box(0.30, 0.30, 0.30, location=(0, 1.10, 0))   # head
    e_box(0.14, 0.30, 0.22, x= 0.14, y_base=0.0)       # left leg
    e_box(0.14, 0.30, 0.22, x=-0.14, y_base=0.0)       # right leg
    e_box(0.10, 0.34, 0.14, x=-0.30, y_base=0.37)      # left arm
    e_box(0.10, 0.20, 0.14, x= 0.30, y_base=0.54)      # right arm (to gun)
    e_box(0.14, 0.14, 0.18, x= 0.32, y_base=0.67)      # shoulder gun housing
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=SEG_LOW, radius=0.045, depth=0.55,
        location=(0.32, 0.74, -0.365),
        rotation=(math.radians(90), 0, 0),
    )
    finalize(smooth_angle=30.0)
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
