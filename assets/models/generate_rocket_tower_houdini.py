"""
generate_rocket_tower_houdini.py
High-resolution rocket tower assets for the carl TD game, generated via Houdini.

HOW TO USE
----------
Option A — Script mode (Houdini Python shell):
    1. Open Houdini.
    2. Open the Python Shell (Windows → Python Shell).
    3. Paste this entire file (or exec it with execfile / drag-drop).
    4. Call the functions you want, e.g.:
           build_rocket_silo_head()
           build_rocket_body()
       They will create geometry nodes in /obj and export .glb files.

Option B — Manual walkthrough:
    Follow the step-by-step comments prefixed "MANUAL:" in each function.
    Each MANUAL comment maps directly to a Houdini SOP or parameter.

All meshes use Y-up, base at Y=0, forward along −Z (Godot convention).
Subdivision is set high (for the high-res version) but you can lower
`SUBDIV_LEVEL` for a faster game-ready export if desired.

Exports go to the same tower asset directory as the Blender versions.
"""

import hou
import os
import math

TOWER_DIR = "/Users/samlawrence/Documents/src/carl/assets/models/towers"
os.makedirs(TOWER_DIR, exist_ok=True)

# Resolution control: 0 = low/game-res, 1-2 = high-res for renders/Houdini review
SUBDIV_LEVEL = 2


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _get_or_create_geo(name: str) -> hou.ObjNode:
    """Return existing geo node or create a fresh one at /obj/<name>."""
    obj = hou.node("/obj")
    existing = obj.node(name)
    if existing:
        existing.destroy()
    geo = obj.createNode("geo", name)
    # Delete the default file SOP Houdini adds
    for child in geo.children():
        child.destroy()
    return geo


def _export_glb(geo_node: hou.ObjNode, filename: str):
    """Export the geometry as a .glb via Houdini's ROP."""
    filepath = os.path.join(TOWER_DIR, filename)
    rop = geo_node.parent().createNode("ropnet")
    gltf = rop.createNode("gltf")
    gltf.parm("soppath").set(geo_node.path() + "/OUT")
    gltf.parm("filename").set(filepath)
    gltf.parm("execute").pressButton()
    rop.destroy()
    print(f"  exported → {filepath}")


def _add_subdivide(sop: hou.SopNode, level: int = SUBDIV_LEVEL) -> hou.SopNode:
    sub = sop.parent().createNode("subdivide")
    sub.setInput(0, sop)
    sub.parm("iterations").set(level)
    return sub


# ---------------------------------------------------------------------------
# ROCKET SILO HEAD  (high-res)
#
# MANUAL WALKTHROUGH:
#   1. /obj → create Geometry node "rocket_silo_head"
#   2. Inside: Add Tube SOP (Primitive Type=Polygon, Axis=Y, Rad=0.30/0.30,
#              Height=0.42, Rows=32, Cols=32) — the main silo body.
#   3. Add Transform SOP: translate Y by +0.21 so base sits at Y=0.
#   4. Warning stripe ring: Add Torus SOP (Rows=32, Cols=32, Rad X=0.31, Rad Y=0.04,
#              Outer Rad=0.04). Transform: translate Y=0.30.
#   5. Iris petals: For each of 6 petals, add a Box SOP, scale to thin wedge shape
#              (sx=0.09, sy=0.06, sz=0.045), then rotate around Y by (i*60)+15 degrees
#              and translate outward to R≈0.22. Merge all 6.
#   6. Inner bore lip: Add Tube SOP (Rad=0.215/0.215, H=0.03), translate Y=0.39.
#   7. Merge everything → Subdivide (2 iterations) → null named OUT.
#   8. Export via ROP GLTF to rocket_silo_head.glb.
# ---------------------------------------------------------------------------

SILO_OUTER_R = 0.30
SILO_INNER_R = 0.20
SILO_H       = 0.42
STRIPE_Y     = 0.30
PETAL_COUNT  = 6


def build_rocket_silo_head():
    print("Building rocket_silo_head (Houdini) …")
    geo = _get_or_create_geo("rocket_silo_head")

    # A. Main silo body cylinder
    tube_body = geo.createNode("tube")
    tube_body.parm("type").set(0)   # polygon
    tube_body.parm("cap").set(1)
    tube_body.parm("rad1").set(SILO_OUTER_R)
    tube_body.parm("rad2").set(SILO_OUTER_R)
    tube_body.parm("height").set(SILO_H)
    tube_body.parm("rows").set(32)
    tube_body.parm("cols").set(32)
    xf_body = geo.createNode("xform")
    xf_body.setInput(0, tube_body)
    xf_body.parmTuple("t").set((0, SILO_H / 2, 0))

    # B. Warning stripe torus ring
    torus = geo.createNode("torus")
    torus.parm("rows").set(32)
    torus.parm("cols").set(32)
    torus.parm("radx").set(SILO_OUTER_R + 0.012)
    torus.parm("rady").set(0.032)
    xf_torus = geo.createNode("xform")
    xf_torus.setInput(0, torus)
    xf_torus.parmTuple("t").set((0, STRIPE_Y, 0))

    # C. Iris petals: thin box wedges around the opening
    petal_nodes = []
    for i in range(PETAL_COUNT):
        angle_deg = i * (360.0 / PETAL_COUNT) + 15.0
        angle_rad = math.radians(angle_deg)
        box_sop   = geo.createNode("box")
        box_sop.parmTuple("size").set((0.09, 0.06, 0.042))
        xf = geo.createNode("xform")
        xf.setInput(0, box_sop)
        radial_dist = (SILO_OUTER_R + SILO_INNER_R) * 0.5
        xf.parmTuple("t").set((
            math.cos(angle_rad) * radial_dist,
            SILO_H + 0.04,
            math.sin(angle_rad) * radial_dist,
        ))
        xf.parmTuple("r").set((0, angle_deg, 0))
        petal_nodes.append(xf)

    # Merge petals
    merge_petals = geo.createNode("merge")
    for idx, p in enumerate(petal_nodes):
        merge_petals.setInput(idx, p)

    # D. Inner bore lip
    tube_lip = geo.createNode("tube")
    tube_lip.parm("type").set(0)
    tube_lip.parm("cap").set(1)
    tube_lip.parm("rad1").set(SILO_INNER_R + 0.015)
    tube_lip.parm("rad2").set(SILO_INNER_R + 0.015)
    tube_lip.parm("height").set(0.03)
    tube_lip.parm("rows").set(32)
    tube_lip.parm("cols").set(32)
    xf_lip = geo.createNode("xform")
    xf_lip.setInput(0, tube_lip)
    xf_lip.parmTuple("t").set((0, SILO_H - 0.015, 0))

    # Merge everything
    merge_all = geo.createNode("merge")
    merge_all.setInput(0, xf_body)
    merge_all.setInput(1, xf_torus)
    merge_all.setInput(2, merge_petals)
    merge_all.setInput(3, xf_lip)

    # Subdivide for high-res
    sub = _add_subdivide(merge_all)

    # Output null
    out = geo.createNode("null", "OUT")
    out.setInput(0, sub)
    out.setDisplayFlag(True)
    out.setRenderFlag(True)

    geo.layoutChildren()
    _export_glb(geo, "rocket_silo_head_hires.glb")
    print("  rocket_silo_head done.")


# ---------------------------------------------------------------------------
# ROCKET BODY  (high-res)
#
# MANUAL WALKTHROUGH:
#   1. /obj → create Geometry node "rocket_body"
#   2. Main body: Tube SOP (Rad=0.06, H=0.40, Rows=24, Cols=24), Transform Y+0.20
#   3. Nose cone: Tube SOP (Rad1=0.06, Rad2=0.001, H=0.14, Rows=24, Cols=24),
#              Transform Y+0.47 (sits on top of body).
#   4. Fins (4×): Box SOP (sx=0.09, sy=0.11, sz=0.025), rotate Y by i*90+45°,
#              translate radially outward so inner edge touches body; merge.
#   5. Nozzle bell: Tube SOP (Rad1=0.078, Rad2=0.062, H=0.055, open/no end caps),
#              Transform Y-0.0275 (flares at base).
#   6. Merge all → Subdivide (2) → null OUT → export rocket_body_hires.glb
# ---------------------------------------------------------------------------

ROCKET_R = 0.060
ROCKET_H = 0.40
NOSE_H   = 0.14
FIN_COUNT = 4


def build_rocket_body():
    print("Building rocket_body (Houdini) …")
    geo = _get_or_create_geo("rocket_body")

    # A. Main body cylinder (tail at Y=0, nose end at Y=ROCKET_H)
    tube_body = geo.createNode("tube")
    tube_body.parm("type").set(0)
    tube_body.parm("cap").set(1)
    tube_body.parm("rad1").set(ROCKET_R)
    tube_body.parm("rad2").set(ROCKET_R)
    tube_body.parm("height").set(ROCKET_H)
    tube_body.parm("rows").set(24)
    tube_body.parm("cols").set(24)
    xf_body = geo.createNode("xform")
    xf_body.setInput(0, tube_body)
    xf_body.parmTuple("t").set((0, ROCKET_H / 2, 0))

    # B. Nose cone (tapered to point)
    tube_nose = geo.createNode("tube")
    tube_nose.parm("type").set(0)
    tube_nose.parm("cap").set(1)
    tube_nose.parm("rad1").set(ROCKET_R)
    tube_nose.parm("rad2").set(0.002)
    tube_nose.parm("height").set(NOSE_H)
    tube_nose.parm("rows").set(24)
    tube_nose.parm("cols").set(24)
    xf_nose = geo.createNode("xform")
    xf_nose.setInput(0, tube_nose)
    xf_nose.parmTuple("t").set((0, ROCKET_H + NOSE_H / 2, 0))

    # C. Four stabiliser fins
    fin_nodes = []
    for i in range(FIN_COUNT):
        angle_deg = i * 90.0 + 45.0
        angle_rad = math.radians(angle_deg)
        box_sop = geo.createNode("box")
        box_sop.parmTuple("size").set((0.09, 0.11, 0.025))
        xf = geo.createNode("xform")
        xf.setInput(0, box_sop)
        radial = ROCKET_R + 0.045
        xf.parmTuple("t").set((
            math.cos(angle_rad) * radial,
            0.055,
            math.sin(angle_rad) * radial,
        ))
        xf.parmTuple("r").set((0, angle_deg, 0))
        fin_nodes.append(xf)

    merge_fins = geo.createNode("merge")
    for idx, f in enumerate(fin_nodes):
        merge_fins.setInput(idx, f)

    # D. Engine nozzle bell at the base
    tube_nozzle = geo.createNode("tube")
    tube_nozzle.parm("type").set(0)
    tube_nozzle.parm("cap").set(0)   # open ends
    tube_nozzle.parm("rad1").set(ROCKET_R + 0.018)  # wide base
    tube_nozzle.parm("rad2").set(ROCKET_R + 0.002)  # narrow top
    tube_nozzle.parm("height").set(0.055)
    tube_nozzle.parm("rows").set(16)
    tube_nozzle.parm("cols").set(24)
    xf_nozzle = geo.createNode("xform")
    xf_nozzle.setInput(0, tube_nozzle)
    xf_nozzle.parmTuple("t").set((0, -0.0275, 0))

    # Merge everything
    merge_all = geo.createNode("merge")
    merge_all.setInput(0, xf_body)
    merge_all.setInput(1, xf_nose)
    merge_all.setInput(2, merge_fins)
    merge_all.setInput(3, xf_nozzle)

    sub = _add_subdivide(merge_all)

    out = geo.createNode("null", "OUT")
    out.setInput(0, sub)
    out.setDisplayFlag(True)
    out.setRenderFlag(True)

    geo.layoutChildren()
    _export_glb(geo, "rocket_body_hires.glb")
    print("  rocket_body done.")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__" or True:   # always runs when exec'd in Houdini shell
    build_rocket_silo_head()
    build_rocket_body()
    print("Done — high-res rocket tower assets exported.")
