# Rocket Tower — Blender Guide

The script `generate_rocket_tower.py` handles everything automatically — modeling, iris
petals, UV unwrapping, UV island placement, geometry polish (smooth shading + a small
angle-limited bevel), and texture generation. Run it in Blender's Scripting tab (or
headless: `Blender --background --python generate_rocket_tower.py`) and it outputs
`rocket_silo_base.glb`, `rocket_silo_petal.glb`, `rocket_body.glb`, and
`rocket_tower_diffuse.png` with no manual steps required.

**Visual style — clean stylized / chunky.** The texture is generated baked-style
(`generate_texture()`): per-island vertical AO gradients, a panel-line grid, edge
darkening, rivets, and crisp diagonal hazard stripes — not flat color blocks. Material
metallic is kept modest (0.25) so that painted albedo reads; the game's procedural sky
supplies the metallic sheen. Bump `SEG`, `BEVEL_WIDTH`, or the texture helpers to taste.

**After regenerating, let Godot reimport.** The `.glb` embeds its texture; Godot extracts
it to `*_rocket_tower_diffuse.png` and caches under `.godot/imported/`. If the silo still
looks like the old texture, run `Godot --path . --headless --import` (or just open the
editor) to force re-extraction before judging the result.

**Iris petals.** `make_silo_petal` builds one blade hinged at its origin, tapering
inward (local −X) toward the bore centre, arc-width on Z, thin on Y — built in
glTF convention so `export_yup` lands it as a flat blade (not a vertical fin).
Godot (`td_tower._build_iris_petals`) places 6 hinges on the inner bore ring at
`IRIS_Y` (= the silo top rim, which is +SILO_H/2 because the silo_base GLB is
centred on its origin), fans them by `rotation.y`, and drives `rotation.x` between
closed (0°, flat over the bore) and open (≈+80°, tilted up/out). Alternating
petals get a small Y-stagger in GDScript so the coplanar blades overlap and seal.
Tune coverage via `PETAL_HALF_W` / `PETAL_LEN` / the taper factor in the script,
and `IRIS_STAGGER` / `IRIS_Y` / the open-close angles in `td_tower.gd`.

---

## Reference: Manual Modeling from Scratch

### Rocket Silo Head (`rocket_silo_head.glb`)

**1. Main cylinder body**
- Add → Mesh → Cylinder: 16 verts, radius 0.30, depth 0.42. Tab into Edit mode, select all, **S Y** to confirm it sits with base at Y=0 (or just move it up by 0.21).
- Bevel the top edge loop (Ctrl+B, 1 segment, small amount ~0.01) so it catches light cleanly.

**2. Warning stripe ring**
- Select the edge loop roughly 70% up the cylinder (Loop Cut, Ctrl+R).
- Slide two more cuts close together above and below it.
- Select the band of faces between the two outer cuts → **I** (inset) slightly, then **E** (extrude) outward ~0.012 units. This gives a proud relief band for the stripe.
- You'll want **two** such bands spaced ~0.08 apart — the yellow/black pattern is a material in Godot, but the raised geometry reads as the stripe even without color.

**3. Camera iris (the most important part visually)**
- With the top face of the cylinder open (delete the top N-gon), add a new circle mesh (Shift+A → Circle, 6 verts) at the top, radius 0.20 (inner bore).
- For each of the 6 petals: select one vertex pair, extrude outward to radius 0.29, then form a thin wedge shape — each petal covers ~43° with a small gap.
- Slightly tilt each petal ~8° inward (rotate on local X/Z) so they look like they're about to close over the bore.
- The petals should overlap slightly like real camera blades — rotate alternating petals a little above/below each other for depth.
- Add a thin inner lip ring (cylinder, radius 0.215, height 0.03) sitting just inside the bore.

**4. Polish**
- Shade smooth on everything. Add a Bevel modifier (Angle mode, 30°) before export so edges catch light without being sharp. Apply before GLB export.

---

### Rocket Body (`rocket_body.glb`)

**1. Main body**
- Cylinder, 12 verts, radius 0.06, depth 0.40. Base at Y=0.

**2. Nose cone**
- Extrude the top cap up 0.14 units, then scale the top edge to ~0 (S → 0). Smooth with a couple of loop cuts near the base of the cone so the taper curves slightly rather than being totally flat.

**3. Fins (do one, array the rest)**
- Add a plane, shape into a swept-back fin profile in front view — slightly wider at the base, narrowing toward the tip, with a gentle backward rake. Thickness ~0.025 via Solidify modifier.
- Add an Array modifier: count 4, Object Offset (use an Empty rotated 90° around Y). Apply both modifiers.
- Position so the inner edge sits flush against the body at the tail.

**4. Engine nozzle bell**
- Short cylinder (radius 0.078 at base → 0.062 at top, height 0.055) below Y=0. Delete inner faces — it should be an open bell shape.
- Add a loop cut near the flare opening and pull it slightly outward for the characteristic bell curve.

**5. Export**
- Apply all modifiers. In the GLB export dialog: **Y Up**, **Apply Transforms**, no animations. Keep poly count reasonable (the script targets ~500 tris for in-game; you can go higher for the Houdini version).

---

## UV Unwrap

### Rocket Silo Head

The goal is to keep the stripe band on a clean rectangular UV strip so you can paint crisp yellow/black diagonals without distortion.

**1. Seam placement**
- Enter Edit mode, Edge Select mode.
- Mark a single vertical seam running down the back of the main cylinder (the side facing away from the camera in your isometric view — roughly +Z in world space). This lets the cylinder unroll into a clean rectangle.
- Mark seams along the top and bottom edges of the stripe band's raised faces, isolating it as its own UV island.
- Mark seams around the base of the iris petal ring, separating petals from the cylinder body.

**2. Unwrap the cylinder body**
- Select all cylinder body faces (excluding petals and stripe band).
- UV → Unwrap (or just U → Unwrap). The single back seam makes this unroll into a near-perfect rectangle — your stripe band island should sit cleanly in the middle of it.

**3. Stripe band island**
- Select only the stripe band faces. U → Unwrap.
- In the UV editor, scale this island horizontally (S → X) to stretch it wide across the texture. You want the band to occupy a tall thin horizontal strip so painted diagonal stripes look correct at game scale.
- Rotate it 90° if needed so the "across the cylinder" direction runs along U (horizontal in texture space).

**4. Iris petals**
- Each petal can share UV space — they're identical geometry. Select one petal, unwrap it, then select all other petals and use **UV → Copy and Paste UVs** (or manually overlap them in the UV editor). Stack all 6 petal islands on top of each other to save texture space.

**5. Top/bottom caps**
- Select the top inner bore ring and bottom cap faces. U → Project from View (top orthographic). Small islands — push them to a corner of the texture.

---

### Rocket Body

The body has two distinct color zones: silver (body + fins + nozzle) and red (nose cone). Keep them in separate UV islands so you can paint a hard color boundary.

**1. Seam placement**
- One vertical seam down the back of the main cylinder body.
- A horizontal seam at the base of the nose cone (where it meets the body cylinder) — this is the silver/red boundary. Critical: keep this seam clean so the color split is sharp in-game.
- Seams along the root edge of each fin where it meets the body, and along the fin tip edges.
- One seam around the nozzle bell opening.

**2. Body cylinder**
- Same as silo: single back seam → clean rectangle. Place this island in the lower-left quadrant of the texture.

**3. Nose cone**
- Select all nose cone faces. U → Unwrap. It will unroll into a triangle fan or a tapered rectangle depending on your loop count.
- Place it adjacent to the body island with a small gap. Paint this entire island red.

**4. Fins (share UV space)**
- Unwrap one fin fully. Stack all 4 fins on top of each other in the UV editor — they're identical so this is free texel density. Push to a corner.

**5. Nozzle bell**
- Small island — Project from View (side orthographic) or just Unwrap with a back seam. Push to a corner near the fins.

---

## Texture Layout

For a 512×512 texture (enough for this game's scale):

```
┌─────────────────────────────────────────┐
│                                         │
│   SILO BODY CYLINDER (tall rectangle)   │  ← paint warning stripes here
│   ~60% of texture width                 │     diagonal yellow/black bands
│                                         │
├──────────────┬──────────────────────────┤
│  STRIPE BAND │  ROCKET BODY CYLINDER    │
│  (isolated)  │  (silver)                │
├──────────────┼──────────────────────────┤
│  IRIS PETALS │  NOSE CONE               │
│  (stacked)   │  (red)                   │
├──────────────┴──────────────────────────┤
│  CAPS / NOZZLE / FINS (small corners)   │
└─────────────────────────────────────────┘
```

---

## Painting the Warning Stripes

Once the stripe band island is a clean horizontal strip in UV space:

1. In Texture Paint mode, set stripe color to **#FFD700** (hazard yellow).
2. Fill the entire band island yellow.
3. Switch to black (**#1A1A1A**). Use the **Stencil** brush with a diagonal stripe stencil, or simply paint diagonal bands manually at ~45°.
4. Stripes should be roughly equal width yellow and black — classic industrial hazard pattern.
5. Add a subtle noise/scratch layer on the silver areas (low opacity grey brush, large radius) to break up the flat metal look.

---

## Export with Texture

In the GLB exporter:
- **Include → Selected Objects** (or All)
- **Data → Mesh → UVs** ✓
- **Materials → Export** → set to **Export**
- Bake your texture to an Image Texture node connected to the Base Color in each material before export, or Godot will only get the procedural material (which loses the painted stripes).

The easiest Godot-compatible pipeline: **Image Texture node → Principled BSDF Base Color** in Blender, with the painted PNG saved next to the GLB. Godot's GLB importer will pick it up automatically.
