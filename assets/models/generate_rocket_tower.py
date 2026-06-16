"""
generate_rocket_tower.py — run in Blender's Scripting tab (Blender 4.x).

Produces three GLBs + one texture atlas for the Missile (rocket silo) tower:

  rocket_silo_base.glb   — cylinder body + stripe rings + bore lip. No petals.
                           Sits on $Turret/Head in Godot. Static.

  rocket_silo_petal.glb  — a single iris petal, pivoted at its INNER edge so
                           Godot can rotate it on its local X axis to open/close.
                           GDScript instances 6 of these around the bore.

  rocket_body.glb        — inert rocket geometry only (silver body, red nose,
                           fins, nozzle bell). Flame/smoke are runtime GDScript
                           nodes, not part of this mesh.

  rocket_tower_diffuse.png — 512×512 shared texture atlas, baked-style:
                           vertical AO gradient + panel-line grid + edge
                           darkening + crisp hazard stripes. No flat blocks.

VISUAL STYLE: clean stylized / chunky. Unlike the other tower meshes (which are
bare and tinted by Godot), this tower carries its own texture + material, so the
look lives in BOTH the geometry polish (smooth shading + baked bevels) and the
richer procedural texture.

All coordinates: Y up, base at Y=0, forward −Z (Godot convention).
Run: Blender → Scripting tab → Open → Run Script
"""

import bpy
import bmesh
import math
import os

TOWER_DIR    = "/Users/samlawrence/Documents/src/carl/assets/models/towers"
TEXTURE_PATH = os.path.join(TOWER_DIR, "rocket_tower_diffuse.png")
TEX_SIZE     = 512
os.makedirs(TOWER_DIR, exist_ok=True)

# Shared silo dimensions — used by both base and petal functions.
SILO_OUTER_R = 0.30
SILO_INNER_R = 0.20
SILO_H       = 0.42
STRIPE_Y     = 0.30
STRIPE_H     = 0.08
IRIS_Y       = SILO_H
IRIS_H       = 0.022          # thin iris-blade thickness (was 0.055 — looked chunky)
PETAL_COUNT  = 6

ROCKET_R     = 0.060
ROCKET_H     = 0.40
NOSE_H       = 0.14
FIN_COUNT    = 4

# Geometry polish — bumped segments + baked bevel, matching generate_meshes.py.
SEG          = 24            # was 12/16 — round silhouettes read clean now
BEVEL_WIDTH  = 0.006
BEVEL_SEG    = 2
BEVEL_ANGLE  = math.radians(45.0)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        bpy.data.meshes.remove(block)
    for block in list(bpy.data.materials):
        bpy.data.materials.remove(block)


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


# COORDINATE NOTE (see generate_meshes.py for the full rationale):
# primitive_cylinder_add's axis is Blender-Z, and export_yup maps Blender
# (x,y,z) → glTF/Godot (x, z, −y), so **Blender-Z is "up" in the final mesh.**
# We stack vertically along Blender-Z; in-game horizontal (x, z) map to Blender
# X and −Y. Parameter names stay (x, y_base, z) = (horizontal, vertical, horiz).
def cyl(r1, r2, depth, seg=SEG, x=0, y_base=0, z=0):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=seg, radius=r1, depth=depth,
        location=(x, -z, y_base + depth / 2),
    )
    obj = bpy.context.active_object
    if r2 != r1:
        bpy.ops.object.mode_set(mode='EDIT')
        bm = bmesh.from_edit_mesh(obj.data)
        bm.verts.ensure_lookup_table()
        # Cylinder axis is Z; the top loop is at max-Z, radius plane is X/Y.
        top_z = (y_base + depth / 2) + depth / 2
        scale = r2 / r1 if r1 != 0 else 1.0
        for v in bm.verts:
            if abs(v.co.z - top_z) < 0.001:
                v.co.x *= scale
                v.co.y *= scale
        bmesh.update_edit_mesh(obj.data)
        bpy.ops.object.mode_set(mode='OBJECT')
    return obj


def box(sx, sy, sz, x=0, y_base=0, z=0):
    # Vertical size (sy) runs along Blender-Z to match the cylinders / export.
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, -z, y_base + sy / 2))
    obj = bpy.context.active_object
    obj.scale = (sx, sz, sy)
    bpy.ops.object.transform_apply(scale=True)
    return obj


def join_all():
    bpy.ops.object.select_all(action='SELECT')
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.join()
    return bpy.context.active_object


def shade_smooth_bevel(obj, smooth_angle=40.0):
    """Smooth shading + a small angle-limited bevel so edges catch light.
    Run AFTER UV unwrap so we don't disturb seams (bevel keeps existing UVs)."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth()
    # Blender 4.1+ removed mesh.use_auto_smooth — emulate angle-based smoothing by
    # flagging faces smooth and marking edges sharper than the threshold as flat.
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    thresh = math.radians(smooth_angle)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if len(e.link_faces) == 2:
            a = e.link_faces[0].normal.angle(e.link_faces[1].normal)
            e.smooth = a < thresh
    bm.to_mesh(me)
    bm.free()
    bev = obj.modifiers.new(name="Bevel", type='BEVEL')
    bev.width = BEVEL_WIDTH
    bev.segments = BEVEL_SEG
    bev.limit_method = 'ANGLE'
    bev.angle_limit = BEVEL_ANGLE
    bpy.ops.object.modifier_apply(modifier=bev.name)


def _mark_back_seam(obj):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(obj.data)
    bm.edges.ensure_lookup_table()
    bm.verts.ensure_lookup_table()
    max_z = max(v.co.z for v in bm.verts)
    seam_verts = {v.index for v in bm.verts if abs(v.co.z - max_z) < 0.001}
    for e in bm.edges:
        if e.verts[0].index in seam_verts and e.verts[1].index in seam_verts:
            e.seam = True
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.object.mode_set(mode='OBJECT')


def _mark_seam_by_angle(obj, angle_threshold_deg=30.0):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(obj.data)
    bm.edges.ensure_lookup_table()
    thresh = math.radians(angle_threshold_deg)
    for e in bm.edges:
        if len(e.link_faces) == 2:
            n1 = e.link_faces[0].normal
            n2 = e.link_faces[1].normal
            if n1.angle(n2) > thresh:
                e.seam = True
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.object.mode_set(mode='OBJECT')


def _unwrap_and_place(obj, u0, v0, u1, v1):
    """Unwrap and pack the island into the atlas region (u0,v0)-(u1,v1), where the
    region is given in the SAME coordinates the texture was painted in
    (generate_texture's _fill uses row 0 = bottom; (v0,v1) is bottom-to-top).

    glTF export flips V (V_gltf = 1 − V_blender), so to make the FINAL sampled
    region land on the painted (v0,v1) we place the Blender V at (1−v1, 1−v0)."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.unwrap(method='ANGLE_BASED', margin=0.01)
    bpy.ops.object.mode_set(mode='OBJECT')
    uv_layer = obj.data.uv_layers.active
    if uv_layer is None:
        return
    uvs = [uv_layer.data[li].uv for li in range(len(uv_layer.data))]
    min_u = min(uv.x for uv in uvs)
    max_u = max(uv.x for uv in uvs)
    min_v = min(uv.y for uv in uvs)
    max_v = max(uv.y for uv in uvs)
    rw = max_u - min_u or 1.0
    rh = max_v - min_v or 1.0
    tw = u1 - u0
    # Compensate for the glTF V-flip: target Blender V range is (1−v1, 1−v0).
    bv0 = 1.0 - v1
    th  = (1.0 - v0) - bv0
    for li in range(len(uv_layer.data)):
        uv = uv_layer.data[li].uv
        uv.x = u0 + (uv.x - min_u) / rw * tw
        uv.y = bv0 + (uv.y - min_v) / rh * th


def make_material(name, tex_img):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    # Keep metallic modest: a high-metallic surface needs strong environment
    # reflections to look like anything but a dark mirror, and the painted
    # panel/hazard texture should read as albedo. The game's procedural sky adds
    # the sheen; we don't need a chrome BSDF for it.
    bsdf.inputs['Metallic'].default_value  = 0.25
    bsdf.inputs['Roughness'].default_value = 0.45
    tex  = nodes.new('ShaderNodeTexImage')
    tex.image = tex_img
    tex.location = (-300, 0)
    out  = nodes.new('ShaderNodeOutputMaterial')
    out.location = (300, 0)
    links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return mat


def make_hazard_material(name):
    """Dedicated diagonal yellow/black hazard material on its own small image, so
    the silo's warning band can never sample the wrong region of the shared atlas.
    Tiled along U so the stripes wrap around the band cleanly."""
    sz = 64
    img = bpy.data.images.get(name)
    if img:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(name, sz, sz, alpha=True)
    px = [0.0] * (sz * sz * 4)
    sw = 12
    for y in range(sz):
        for x in range(sz):
            i = (y * sz + x) * 4
            px[i:i+4] = list(YELLOW if (x - y) % (sw * 2) < sw else BLACK)
    img.pixels = px

    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes; links = mat.node_tree.links
    nodes.clear()
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.inputs['Metallic'].default_value  = 0.15
    bsdf.inputs['Roughness'].default_value = 0.55
    tex = nodes.new('ShaderNodeTexImage'); tex.image = img; tex.location = (-300, 0)
    out = nodes.new('ShaderNodeOutputMaterial'); out.location = (300, 0)
    links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return mat


def make_solid_material(name, rgba, metallic=0.2, roughness=0.6):
    """A plain flat-colour material (no texture) — used for the dark recessed
    bore floor so it can't pick up stray atlas regions on its UVs."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = rgba
    bsdf.inputs['Metallic'].default_value   = metallic
    bsdf.inputs['Roughness'].default_value  = roughness
    out = nodes.new('ShaderNodeOutputMaterial')
    out.location = (300, 0)
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return mat


# ---------------------------------------------------------------------------
# Texture atlas — baked-style: gradients, panel lines, edge darkening, decals.
#
# UV island layout (normalised 0-1):
#   [0.00-0.50] × [0.50-1.00]  silo base body (silver + hazard band)
#   [0.00-0.25] × [0.25-0.50]  silo stripe relief rings
#   [0.25-0.50] × [0.25-0.50]  bore lip (dark silver)
#   [0.00-0.50] × [0.00-0.25]  petal (dark metallic)
#   [0.50-1.00] × [0.50-1.00]  rocket body (silver)
#   [0.50-0.75] × [0.25-0.50]  nose cone (red)
#   [0.75-1.00] × [0.00-0.50]  fins + nozzle (dark silver)
# ---------------------------------------------------------------------------

SILVER = (0.78, 0.80, 0.84, 1.0)
SILVER_HI = (0.90, 0.92, 0.95, 1.0)
SILVER_LO = (0.52, 0.55, 0.60, 1.0)
RED    = (0.82, 0.12, 0.12, 1.0)
RED_HI = (0.95, 0.28, 0.22, 1.0)
RED_LO = (0.50, 0.07, 0.07, 1.0)
YELLOW = (1.00, 0.80, 0.00, 1.0)
BLACK  = (0.08, 0.08, 0.09, 1.0)
DARK   = (0.26, 0.28, 0.32, 1.0)
DARK_HI = (0.36, 0.39, 0.44, 1.0)
DARK_LO = (0.16, 0.17, 0.20, 1.0)


def _lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(4))


def _px(px, x, y, color, w=TEX_SIZE):
    if x < 0 or y < 0 or x >= w or y >= w:
        return
    i = (y * w + x) * 4
    px[i:i+4] = color


def _vgrad(px, x0, y0, x1, y1, c_top, c_bot):
    """Vertical gradient — fakes top-lit AO across a UV island."""
    h = max(y1 - y0, 1)
    for y in range(y0, y1):
        t = (y - y0) / h
        c = _lerp(c_bot, c_top, t)   # y increases upward in our island fill order
        for x in range(x0, x1):
            _px(px, x, y, c)


def _edge_darken(px, x0, y0, x1, y1, lo, falloff=18):
    """Darken a margin inside the island border — reads as ambient occlusion at
    the seams between parts."""
    for y in range(y0, y1):
        for x in range(x0, x1):
            d = min(x - x0, x1 - 1 - x, y - y0, y1 - 1 - y)
            if d < falloff:
                i = (y * TEX_SIZE + x) * 4
                cur = px[i:i+4]
                t = 1.0 - d / falloff
                px[i:i+4] = _lerp(cur, lo, t * 0.55)


def _panel_lines(px, x0, y0, x1, y1, step=42, dark=DARK_LO):
    """Thin recessed panel-line grid — the single biggest 'machined' cue."""
    for y in range(y0, y1):
        for x in range(x0, x1):
            on_v = ((x - x0) % step) < 2
            on_h = ((y - y0) % step) < 2
            if on_v or on_h:
                i = (y * TEX_SIZE + x) * 4
                cur = px[i:i+4]
                px[i:i+4] = _lerp(cur, dark, 0.45)


def _hazard_band(px, x0, y0, x1, y1, sw=14):
    """Crisp diagonal hazard stripes with a recessed dark rail top and bottom."""
    period = sw * 2
    for y in range(y0, y1):
        edge = (y - y0) < 3 or (y1 - 1 - y) < 3
        for x in range(x0, x1):
            if edge:
                _px(px, x, y, DARK_LO)
            else:
                _px(px, x, y, YELLOW if (x - y) % period < sw else BLACK)


def _rivets(px, cx, cy, r=4, color=DARK_HI):
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r:
                _px(px, cx + dx, cy + dy, color)


def generate_texture():
    print("Generating rocket_tower_diffuse.png (baked-style) …")
    px = [0.0] * (TEX_SIZE * TEX_SIZE * 4)
    S  = TEX_SIZE
    H  = S // 2
    Q  = S // 4

    # ── Silo base body — upper-left quadrant ────────────────────────────────
    _vgrad(px, 0, H, H, S, SILVER_HI, SILVER_LO)
    _panel_lines(px, 0, H, H, S, step=46)
    # Hazard band sits ~mid of the island.
    band_y0 = H + int(H * 0.50)
    band_y1 = H + int(H * 0.66)
    _hazard_band(px, 0, band_y0, H, band_y1)
    # Row of rivets along the top rim of the silo body.
    for rx in range(24, H, 48):
        _rivets(px, rx, S - 22, 3)
    _edge_darken(px, 0, H, H, S, SILVER_LO)

    # ── Stripe relief rings — narrow island, hazard pattern ─────────────────
    _hazard_band(px, 0, Q, Q, H, sw=10)

    # ── Bore lip — dark machined ring ───────────────────────────────────────
    _vgrad(px, Q, Q, H, H, DARK_HI, DARK_LO)
    _edge_darken(px, Q, Q, H, H, DARK_LO, falloff=10)

    # ── Petal — dark metallic with a centre spine highlight ─────────────────
    _vgrad(px, 0, 0, H, Q, DARK_HI, DARK_LO)
    _panel_lines(px, 0, 0, H, Q, step=30, dark=BLACK)
    _edge_darken(px, 0, 0, H, Q, BLACK, falloff=8)

    # ── Rocket body — upper-right quadrant, silver, vertical-lit ────────────
    _vgrad(px, H, H, S, S, SILVER_HI, SILVER_LO)
    _panel_lines(px, H, H, S, S, step=40)
    _edge_darken(px, H, H, S, S, SILVER_LO)

    # ── Nose cone — red, hot top to deep base ───────────────────────────────
    _vgrad(px, H, Q, 3 * Q, H, RED_HI, RED_LO)
    _edge_darken(px, H, Q, 3 * Q, H, RED_LO, falloff=10)

    # ── Fins + nozzle — dark silver, gradient + panel lines ─────────────────
    _vgrad(px, 3 * Q, 0, S, H, DARK_HI, DARK_LO)
    _panel_lines(px, 3 * Q, 0, S, H, step=28, dark=BLACK)
    _edge_darken(px, 3 * Q, 0, S, H, BLACK, falloff=10)

    img = bpy.data.images.get("rocket_tower_diffuse")
    if img:
        bpy.data.images.remove(img)
    img = bpy.data.images.new("rocket_tower_diffuse", S, S, alpha=True)
    img.pixels = px
    img.filepath_raw = TEXTURE_PATH
    img.file_format  = 'PNG'
    img.save()
    print(f"  saved → {TEXTURE_PATH}")
    return img


# ---------------------------------------------------------------------------
# rocket_silo_base.glb  — cylinder + stripe bands + bore lip, NO petals
# ---------------------------------------------------------------------------

def make_silo_base(tex_img):
    """Silo body with a RECESSED well at the top (where the thin iris blades sit
    flat, below the rim) and a prominent raised HAZARD RIM ring around the
    opening. The rim gets its own UV island over the hazard-stripe region of the
    atlas, so the yellow/black band is always visible regardless of the body
    unwrap. The recess means the blades never poke above the rim."""
    print("tower/rocket_silo_base …")
    clear_scene()

    # Main body cylinder (the silver drum), with its top cap removed so we can
    # see down into the recessed well + blades. We delete the top face after.
    body = cyl(SILO_OUTER_R, SILO_OUTER_R, SILO_H, seg=SEG)
    body.name = "Body"

    # A separate hazard BAND ring around the upper outer wall — a thin proud
    # cylinder (open, no caps) wrapping the drum just below the lip. Its own
    # material/UV over the stripe region so the yellow/black always shows.
    band_h = 0.085
    band = cyl(SILO_OUTER_R + 0.012, SILO_OUTER_R + 0.012, band_h,
               seg=SEG, y_base=SILO_H - band_h - 0.02)
    band.name = "Band"

    # A dark floor disc set down inside the drum so the well reads as a recessed
    # pit, not a see-through tube.
    floor = cyl(SILO_INNER_R + 0.04, SILO_INNER_R + 0.04, 0.02,
                seg=SEG, y_base=SILO_H - 0.13)
    floor.name = "Floor"

    # Delete the top cap of the body and the caps of the band so we see inside and
    # the band reads as a ring, not a disc.
    for o in (body, band):
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.mode_set(mode='EDIT')
        bm = bmesh.from_edit_mesh(o.data)
        bm.faces.ensure_lookup_table()
        top_z = max(v.co.z for v in bm.verts)
        bot_z = min(v.co.z for v in bm.verts)
        kill = []
        for f in bm.faces:
            cz = sum(v.co.z for v in f.verts) / len(f.verts)
            if (abs(cz - top_z) < 0.002) or (o is band and abs(cz - bot_z) < 0.002):
                kill.append(f)
        bmesh.ops.delete(bm, geom=kill, context='FACES')
        bmesh.update_edit_mesh(o.data)
        bpy.ops.object.mode_set(mode='OBJECT')

    # Materials — SOLID/clean, no shared atlas on the body (the atlas unwrap kept
    # bleeding the red nose region onto the drum). The hazard band has its own
    # dedicated stripe image; the body and floor are clean metals.
    body.data.materials.append(make_solid_material(
        "silo_body", (0.62, 0.65, 0.70, 1.0), metallic=0.35, roughness=0.5))
    floor.data.materials.append(make_solid_material(
        "silo_floor", (0.09, 0.09, 0.11, 1.0), metallic=0.1, roughness=0.8))

    bpy.context.view_layer.objects.active = band
    band.data.materials.append(make_hazard_material("silo_band_haz"))
    _mark_back_seam(band)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.unwrap(method='ANGLE_BASED', margin=0.001)
    bpy.ops.object.mode_set(mode='OBJECT')

    # Join all three into one object (materials preserved as separate slots).
    bpy.ops.object.select_all(action='SELECT')
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    shade_smooth_bevel(obj, smooth_angle=42.0)

    export_glb(os.path.join(TOWER_DIR, "rocket_silo_base.glb"))


# ---------------------------------------------------------------------------
# rocket_silo_petal.glb  — one thin, SHORT iris blade for the recessed silo hatch.
#
# Each blade is a thin curved sliver hinged at the mesh origin, curling toward the
# bore. They are SHORT (tip reaches a mid radius, not the centre), so closed they
# form a ring of overlapping blades around a small central hole, lying flat in the
# silo's recessed well. Godot fans them by rotation.y into their slots and OPENS by
# dropping them straight down into the well (IRIS_SINK in td_tower.gd) with a small
# twist — pure in-plane rotation can't retract blades over a bore this size, so the
# hatch sinks away instead.
#
# COORDINATE CONVENTION.  Blender export_yup maps Blender (x,y,z) → glTF/Godot
# (x, z, −y); to land a glTF vertex (gx, gy, gz) we build Blender (gx, −gz, gy).
# ---------------------------------------------------------------------------

#   PETAL_R0    : hinge radius (outer, on the bore ring) — pivot is here.
#   PETAL_R1    : tip radius (how far the blade reaches inward). <0.02 ≈ closed bore.
#   PETAL_CURL  : total tangential sweep (radians) from hinge to tip — the spiral.
#   PETAL_HALF_W: half-width of the sliver across its centre-line.
# SHORT blades: closed = a ring of blades around a small central hole; opening
# spins them flat into the rim (pure in-plane). Tip reaches a mid radius (not the
# centre) so an in-plane spin genuinely swings each blade clear of the bore.
PETAL_R0     = SILO_INNER_R            # hinge on the bore ring
PETAL_R1     = 0.085                    # tip at a mid ring → small central hole
PETAL_CURL   = math.radians(30.0)      # gentle wrap so the blade retracts cleanly
PETAL_HALF_W = math.radians(180.0 / PETAL_COUNT) * SILO_INNER_R * 1.5


def make_silo_petal(tex_img):
    print("tower/rocket_silo_petal …")
    clear_scene()

    steps = 14                         # subdivisions along the curved blade
    mesh = bpy.data.meshes.new("Petal")
    bm   = bmesh.new()

    def gltf_to_blender(gx, gy, gz):
        # (gx, gy, gz)_glTF  ←  (gx, -gz, gy)_blender
        return (gx, -gz, gy)

    def ring(thickness_y):
        """One layer of the blade at the given glTF-Y (thickness) value.
        The centre-line spirals from the hinge (radius PETAL_R0, angle 0) inward
        to the tip (radius PETAL_R1, angle PETAL_CURL). At each step we offset
        ±PETAL_HALF_W perpendicular to the centre-line to give the sliver width,
        tapering the width slightly toward the tip so blades come to a soft point.
        Built so the hinge sits at the glTF origin (we subtract the hinge point)."""
        verts = []
        # Hinge centre in glTF X-Z, so we can translate the whole blade to origin.
        hx0 = PETAL_R0
        hz0 = 0.0
        for s in range(steps + 1):
            t   = s / steps
            r   = PETAL_R0 + (PETAL_R1 - PETAL_R0) * t
            ang = PETAL_CURL * t
            cx  = math.cos(ang) * r        # centre-line point (glTF X-Z plane)
            cz  = math.sin(ang) * r
            # Tangent of the centre-line → perpendicular gives the width direction.
            # d/dt of (cos(ang)*r, sin(ang)*r); approximate with the radial+angular parts.
            dr  = (PETAL_R1 - PETAL_R0)
            dx  = math.cos(ang) * dr - math.sin(ang) * r * PETAL_CURL
            dz  = math.sin(ang) * dr + math.cos(ang) * r * PETAL_CURL
            tl  = math.hypot(dx, dz) or 1.0
            # perpendicular (normalised)
            px, pz = -dz / tl, dx / tl
            hw  = PETAL_HALF_W * (1.0 - 0.40 * t)
            for sgn in (-1.0, 1.0):
                gx = cx + px * hw * sgn - hx0
                gz = cz + pz * hw * sgn - hz0
                verts.append(bm.verts.new(gltf_to_blender(gx, thickness_y, gz)))
        return verts

    bot = ring(0.0)
    top = ring(IRIS_H)

    for s in range(steps):
        bi = s * 2
        bm.faces.new([bot[bi+1], bot[bi+3], top[bi+3], top[bi+1]])  # one long side
        bm.faces.new([bot[bi+2], bot[bi],   top[bi],   top[bi+2]])  # other long side
        bm.faces.new([top[bi],   top[bi+1], top[bi+3], top[bi+2]])  # top face
        bm.faces.new([bot[bi+2], bot[bi+3], bot[bi+1], bot[bi]])    # bottom face
    bm.faces.new([bot[0], bot[1], top[1], top[0]])                  # hinge cap
    li = steps * 2
    bm.faces.new([bot[li+1], bot[li], top[li], top[li+1]])          # tip cap

    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("Petal", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    obj.data.materials.append(make_material("petal_mat", tex_img))
    _mark_seam_by_angle(obj, 40.0)
    _unwrap_and_place(obj, 0.00, 0.00, 0.50, 0.25)
    shade_smooth_bevel(obj, smooth_angle=36.0)

    export_glb(os.path.join(TOWER_DIR, "rocket_silo_petal.glb"))


# ---------------------------------------------------------------------------
# rocket_body.glb  — inert rocket geometry only, no VFX
# ---------------------------------------------------------------------------

def make_rocket_body(tex_img):
    print("tower/rocket_body …")
    clear_scene()

    cyl(ROCKET_R, ROCKET_R, ROCKET_H, seg=SEG)
    cyl(ROCKET_R, 0.002, NOSE_H, seg=SEG, y_base=ROCKET_H)

    for i in range(FIN_COUNT):
        angle = math.radians(i * 90.0 + 45.0)
        fx    = math.cos(angle) * (ROCKET_R + 0.045)
        fz    = math.sin(angle) * (ROCKET_R + 0.045)
        fin   = box(0.09, 0.11, 0.025, x=fx, y_base=0.0, z=fz)
        # The rocket's long axis is Blender-Z now, so spin the fins about Z (the
        # box() call already placed this fin at the in-game (fx, fz) position,
        # which maps to Blender (fx, -fz, …)).
        fin.rotation_euler.z = -angle
        bpy.ops.object.transform_apply(rotation=True)

    cyl(ROCKET_R + 0.018, ROCKET_R + 0.002, 0.055, seg=SEG, y_base=-0.055)

    obj = join_all()
    obj.data.materials.append(make_material("rocket_mat", tex_img))

    _mark_back_seam(obj)
    _mark_seam_by_angle(obj, 40.0)
    _unwrap_and_place(obj, 0.50, 0.50, 1.00, 1.00)

    # Remap nose cone faces to the red island.
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    uv_layer = bm.loops.layers.uv.active
    # Rocket long axis is Blender-Z now; the nose sits above ROCKET_H in Z.
    nose_loops = []
    for face in bm.faces:
        cz = sum(v.co.z for v in face.verts) / len(face.verts)
        if cz > ROCKET_H - 0.001:
            for loop in face.loops:
                nose_loops.append(loop)
    if nose_loops:
        us = [l[uv_layer].uv.x for l in nose_loops]
        vs = [l[uv_layer].uv.y for l in nose_loops]
        ru = (max(us) - min(us)) or 1.0
        rv = (max(vs) - min(vs)) or 1.0
        for l in nose_loops:
            uv = l[uv_layer].uv
            uv.x = 0.50 + (uv.x - min(us)) / ru * 0.25
            uv.y = 0.25 + (uv.y - min(vs)) / rv * 0.25
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.object.mode_set(mode='OBJECT')

    shade_smooth_bevel(obj, smooth_angle=38.0)

    export_glb(os.path.join(TOWER_DIR, "rocket_body.glb"))


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

tex_img = generate_texture()
make_silo_base(tex_img)
make_silo_petal(tex_img)
make_rocket_body(tex_img)

print()
print("Done.")
print(f"  {TEXTURE_PATH}")
for name in ("rocket_silo_base.glb", "rocket_silo_petal.glb", "rocket_body.glb"):
    print(f"  {os.path.join(TOWER_DIR, name)}")
print()
print("Iris constants for GDScript (in-plane / flat-rotating iris):")
print(f"  PETAL_COUNT  = {PETAL_COUNT}")
print(f"  PETAL_R0     = {PETAL_R0}  (hinge radius → IRIS_HINGE_R in td_tower.gd)")
print(f"  IRIS_H       = {IRIS_H}  (thin blade thickness)")
print(f"  blades open by sweeping rotation.y (IRIS_OPEN_SWEEP), not tilting up")
