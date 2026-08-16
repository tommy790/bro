# V-NPCs Remade Systems

Four system remakes added on top of the existing V-NPCs architecture.

---

## 1. Dynamic Weight Painting & Mesh Deform
**Files:** `lua/autorun/sh_vnpc_weight_paint.lua` (new), edits in
`lua/autorun/sh_vnpc_gpu_belly.lua` and `shaders/gpu_belly_deform.fxc`

Every swallowed entity becomes **volumetric mass blobs** built from its
*measured* body parts (`VNPC_MeasureBodyParts`: torso/head/pelvis width,
limb length, model scale) and physics mass. The belly is shaped by an
**implicit metaball field** instead of a bounding box:

- **Fetal-curl sub-blobs** — each prey contributes torso + head + limb blobs
  arranged in a hash-varied C-shape, so a curled person reads as curled, not
  as a sphere (physics still simulates one mass point per prey).
- **Merged blobby displacement** — the field `F(p) = sum(mass * (1-d^2)^2)`
  over all blobs drives per-vertex displacement: adjacent prey fuse into one
  continuous bulge (no more separate bumps with a valley), with **analytic
  field-gradient normals** for correct shading.
- **Per-axis ellipsoid** — the belly stretches along the blob bounding box
  per-axis (long prey = long belly, wide prey = wide belly; no max-axis
  ballooning), clamped against the volume-equivalent sphere so spread-out
  clusters don't over-inflate.
- **Volume-aware amplitude** — lump strength and the field reference scale
  with total prey mass; more prey = fuller, bumpier belly.
- **Gravity sag + heavy lean** — the belly center drops and pulls forward with
  mass, and the character's spine arches backward under heavy loads (gated to
  not fight bone-pose animations).
- **Client interpolation** — blob positions replicate at 5 Hz and are
  exponentially smoothed per frame (no jitter).
- **Shader parity** — the same field math ships as reference HLSL
  (`g_VoreBlob[12]` / `g_VoreBlobRadii[12]` / `g_VoreMetaParams`,
  `ApplyMetaBallField`) for custom VCS builds; the Lua mesh path remains the
  working renderer.

ConVars: `vnpcs_weight_paint_enabled`, `vnpcs_weight_paint_lumps`,
`vnpcs_weight_paint_metaballs`, `vnpcs_weight_paint_amp`,
`vnpcs_weight_paint_asymmetry`.
Status: `vnpcs_weight_paint_status`; test: `vnpcs_test_paint_blob [w] [h] [d]`.
Debug: `vnpcs_gpu_belly_debug 1` draws the blob cluster + center of mass.

## 2. Full Physics-Driven Digestion (Ragdoll Matrix)
**Files:** `lua/autorun/server/vnpcs_belly_physics.lua` (new)

Prey are no longer "an invisible inventory slot". A live mass-spring simulation
runs inside the belly volume (the integrator `VNPC_BellyPhysicsStep` is pure
math, mirror-tested by `test_belly_physics_sim.py`):

- Every swallowed prey is a **mass point** with gravity, drag, pairwise prey
  repulsion, soft-wall containment inside the measured belly ellipsoid, and
  **struggle impulses** scaled by personality *and* traits.
- The aggregate center of mass, slosh vector, and per-prey positions drive the
  weight-painted mesh, the visual belly jiggle, and slosh sounds.
- **Weight penalty:** a full belly slows the predator down
  (`VNPC_GetBellyWeightSlow`, integrated into DrGBase `GetAdjustedSpeeds`).
- **Ragdoll matrix visuals:** frozen `prop_ragdoll` copies of swallowed NPCs
  ride inside the belly (visible with the inside-camera). A prop_ragdoll's
  bones are owned by its physics objects (entity parenting alone leaves it
  frozen in the standing bind pose), so each copy is first curled into the
  addon's proven in-game sitting keyframe (`VNPC_ChildbirthSittingPoseKeyframe`
  — knees up, shins folded, arms wrapped) via rigid rest-geometry FK, then
  every bone physics object is driven to its prey mass position each tick,
  wobbling while the prey struggles.

ConVars: `vnpcs_belly_physics_enabled`, `vnpcs_belly_physics_rate`,
`vnpcs_belly_ragdoll_visual`, `vnpcs_belly_ragdoll_max`,
`vnpcs_belly_weight_slow`, `vnpcs_belly_struggle_kick`.
Status: `vnpcs_belly_physics_status`; tests: `vnpcs_belly_physics_sim`
(headless 6-second sim), `vnpcs_test_belly_kick`.
Headless mirror test: `python3 v_npcs/test_belly_physics_sim.py`.

## 3. Smart Nextbot AI & Navigation Mesh
**Files:** `lua/autorun/server/vnpcs_hunter_ai.lua` (new), edits in
`lua/autorun/server/vnpcs_smart_ai.lua`

Tactical layer on top of the DrGBase nextbots and female-model NPCs:

- **Noise tracking:** player footsteps and NPC footstep sounds create world
  noise events (`PlayerFootstep` / `EntityEmitSound`). Predators investigate
  loud noises, with range scaled by hunger and the *perception* trait. The
  *stealth* trait quiets whoever makes the noise.
- **Flashlight tracking:** a player's flashlight beam sweeping over a predator
  exposes them; the predator pinpoints and tracks that player (shy
  personalities retreat out of the beam, aggressive ones rush).
- **Ambush & stalking:** a state machine (`idle → investigate → stalk →
  ambush → rush`) with trace- and navmesh-validated ambush points outside the
  target's view cone; burst-out rush when the target's back is turned.
- **Pack cornering:** pack members get flank slots at ±120° around the target
  and close the net when all slots are reached.
- **Map hazards:** predators kick explosive barrels at targets (force + angular
  impulse, then retreat) and herd targets toward water.

ConVars: `vnpcs_hunter_ai_enabled`, `vnpcs_noise_tracking`,
`vnpcs_noise_base_range`, `vnpcs_flashlight_tracking`, `vnpcs_flashlight_range`,
`vnpcs_ambush_ai`, `vnpcs_pack_cornering`, `vnpcs_hazard_use`,
`vnpcs_hunter_debug`.
Status: `vnpcs_hunter_ai_status`; tests: `vnpcs_test_noise`, `vnpcs_test_ambush`.

## 4. Modular Status & Trait System
**Files:** `lua/autorun/sh_vnpc_traits.lua` (new),
`lua/autorun/client/cl_vnpc_trait_menu.lua` (new),
`lua/weapons/gmod_tool/stools/vnpc_traits.lua` (new toolgun), edits in
`lua/entities/belly_modules/mechanics.lua`, `lua/entities/npc_modules/drgbase.lua`,
`lua/autorun/sh_vnpc_hunger.lua`

Assignable RPG traits on top of personalities. Every trait is a set of stat
multipliers, and every system reads them through `VNPC_GetTraitStat(ent, stat)`:

| stat | effect |
| --- | --- |
| `metabolism` | digestion speed of a predator |
| `acid_resistance` | multiplier on digestion damage a prey takes (higher = tougher) |
| `capacity` | belly max capacity (value units, base `vnpcs_capacity_base`) |
| `weight_resistance` | divisor on the belly-weight movement penalty |
| `struggle_energy` | how hard a prey struggles in the belly (physics kicks) |
| `perception` | hearing + sight range (noise/flashlight tracking) |
| `night_vision` | sight at night |
| `stealth` | quiets footsteps/noise |
| `aggression` | hunt target scoring |

Traits include **Fast/Slow Metabolism, Big/Small Stomach, Iron/Delicate
Stomach, Tireless, Heavy Body, Glutton, Dainty, Keen Ears, Deaf, Night Hunter,
Sneaky, Brave Hunter, Cowardly, Acid Resistant, Weak Stomach, Tough, Restless,
Docile, Light-Footed, Clumsy, Starving, Well-Fed**. Conflicting traits replace
each other automatically. NPCs roll 1–2 traits at spawn (personality-biased).

**UI:** spawn menu → V-NPCs → **Status & Traits** (full editor with per-NPC
picklist and live stat summary), or the new **Trait Editor** toolgun (aim +
left-click). Server commands: `vnpcs_trait_add/remove/randomize/clear
<entindex|aimed> <trait_id>`, `vnpcs_trait_status`.

Capacity gating also feeds the AI: predators at capacity stop hunting and
digest (edits in `vnpcs_smart_ai.lua` / `vnpcs_hunter_ai.lua`).

ConVars: `vnpcs_traits_enabled`, `vnpcs_traits_random_chance`,
`vnpcs_capacity_enabled`, `vnpcs_capacity_base`.

---

## Testing
- Syntax check (GMod LuaJIT dialect, incl. `continue`): `python3 tools/check_lua_syntax.py v_npcs`
- Headless Lua execution of the physics module: `python3 tools/run_belly_physics_lua.py`
- Headless Lua execution of traits + weight paint: `python3 tools/run_modules_lua.py`
- Python mirror test of the integrator math: `python3 v_npcs/test_belly_physics_sim.py`

---

## v0.7 Systems

### Real-Time Dynamic Body Matrix (No More Rigging)
**Files:** `lua/autorun/sh_vnpc_body_expansion.lua`

Any standard model is analyzed on spawn (bones + measured body parts) and
expanded on-the-fly through per-region bone-scale envelopes — chest, hips,
thighs, calves, arms — driven by a single **bloat** value (swallowed prey +
drunk water + eaten food + monster growth). GMod cannot rewrite vertex weights
at runtime, so this approximates vertex morphing with the engine's actual
tools: virtual belly bones + `ManipulateBoneScale` on whatever bones exist.
Also exports the **layered stress map** (`VNPC_GetClothStress`) used by the
cloth tear system. ConVars: `vnpcs_body_expansion_enabled/_amp/_prey`.
**Default: OFF** — the GPU belly mesh creates the belly; bone inflation is
opt-in (enable `vnpcs_body_expansion_enabled` / `vnpcs_gpu_belly_bonescale`
only if you want the character's own bones to swell).
Status: `vnpcs_body_matrix_status`.

### Layered Cloth Tear
**Files:** `lua/autorun/client/cl_vnpc_cloth_tear.lua`

A fabric shell built from the NPC's own textures hugs the belly as stress
rises; at `vnpcs_cloth_tear_rip` the panelized shell separates along seam
lines (jagged torn edges, darkening) and peels down, revealing the skin belly.
No runtime cloth sim exists in GMod — this is the procedural panel-split
approximation. ConVars: `vnpcs_cloth_tear_enabled/_stress/_rip`.

### Adaptive Personality Matrix
**Files:** `lua/autorun/sh_vnpc_personality_matrix.lua`

Every NPC carries six behavioral axes (stealth/greed/shy/aggression/gentle/
playful) seeded from the legacy personality. All systems read effective params
through `VNPC_GetBehaviorParam()` (digestion speed, sight range, hunt-unseen
requirement, ambush/pin/camouflage willingness, struggle energy). Sliders in
the Status & Traits editor (or `vnpcs_matrix_set <ent> <axis> <0..1>`) mix
profiles on a single NPC — e.g. 90% stealth / 40% greed / 80% shy.

### Adaptive Environment AI
**Files:** `lua/autorun/server/vnpcs_env_ai.lua` + edits in `vnpcs_hunter_ai.lua`

Predators analyze map props at runtime (no pre-baked nodes): tables/desks →
cover + pinning surfaces, beds → prone camouflage while prey sleep, vents →
ambush perches, cabinets/crates → hiding. Stealthy/shy predators stalk to
cover points and crouch-camouflage on beds; aggressive ones pin targets
against tables before rushing. Debug: `vnpcs_env_debug 1`. ConVars:
`vnpcs_env_ai_enabled/_scan_radius/_debug`.

### Acoustical Sound Porting
**Files:** `lua/autorun/server/vnpcs_acoustics.lua`

Internal prey screams/struggle thumps are ported through the belly medium:
volume/pitch attenuation by fluid fill, delayed sub-bass echo, armored-model
absorption, and low-frequency footstep thumps that deepen while crawling.
GMod has no per-sound DSP, so this is pitch/volume/echo emulation. ConVars:
`vnpcs_acoustics_enabled/_muffle/_echo/_thump`. Status: `vnpcs_acoustics_status`.

### Tests
`python3 tools/run_v07_lua.py` — headless assertions for the body matrix
(bloat, region weights, stress thresholds, bone-scale apply/reset, axial
bias) and the personality matrix (defaults, clamping, serialization, behavior
params).
