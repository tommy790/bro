# V-NPCs Remade Systems

Four system remakes added on top of the existing V-NPCs architecture.

---

## 1. Dynamic Weight Painting & Mesh Deform
**Files:** `lua/autorun/sh_vnpc_weight_paint.lua`, edits in
`lua/autorun/sh_vnpc_gpu_belly.lua`

Every swallowed entity becomes a **volumetric shape blob** built from its
*measured* body parts (`VNPC_MeasureBodyParts`: torso/head/pelvis width,
limb length, model scale) and physics mass. The old "one rigid teardrop belly"
is replaced by a procedurally deformed mesh, and blob **positions** are laid
out by a deterministic bounding-box packer rather than a live simulation
(see system 2 for why):

- **Blob bounding box drives the belly ellipsoid** — a long prey makes a long
  belly, a wide prey makes a wide belly, multiple prey stack into a bigger one.
- **Shelf packing (`VNPC_DefaultBlobLayout`)** lays bodies out shoulder-to-
  shoulder along the belly's width using each blob's *real measured width* -
  their widths add together, so 2+ similarly-sized prey genuinely reads as a
  wider belly instead of a rounder single blob. An adaptive row-width budget
  (not a fixed headcount) means a row overflows into a second, deeper row
  once it can't realistically fit another body, instead of the belly getting
  absurdly wide. It's pure math: the same prey list always produces the same
  layout, so it can't desync, jitter, or freeze mid-pose.
- **Per-vertex gaussian weight painting** adds a lump for every prey at its
  packed position inside the belly, so the belly visibly bulges where each
  prey actually is.
- **Asymmetric skeleton stretching** — the generated belly bones shift toward
  the center of mass, and the character's own spine/pelvis/thigh bones are
  scaled per-axis and per-side, so even stock models without belly bones grow a
  lopsided, prey-shaped belly instead of a fixed shape.

ConVars: `vnpcs_weight_paint_enabled`, `vnpcs_weight_paint_lumps`,
`vnpcs_weight_paint_amp`, `vnpcs_weight_paint_asymmetry`.
Status: `vnpcs_weight_paint_status`; test: `vnpcs_test_paint_blob [w] [h] [d]`.
Headless packing test: `python3 tools/run_box_packing_lua.py`.

## 2. Full Physics-Driven Digestion — replaced with bounding-box shape (#1)
**Files:** `lua/autorun/server/vnpcs_belly_physics.lua`

This used to be a full mass-spring physics simulation per swallowed prey,
plus frozen `prop_ragdoll` copies driven bone-by-bone (hand-rolled quaternion
FK) to visually ride inside the belly. It didn't hold up in practice: the
ragdoll posing crashed repeatedly (`bad argument #2 to __mul` in the
quaternion math, copies frozen in their bind pose on some skeletons), and
independently of that, the physics simulation's output never actually
reached the belly mesh in the first place — a field-name mismatch
(`sh_vnpc_weight_paint.lua` read `m.pos`/`m.vel`, but the simulation stored
`m.x, m.y, m.z`/`m.vx, m.vy, m.vz`) meant the "live jiggle" was silently
never applied, and blob positions were *already* falling back to the
deterministic layout the whole time.

Given that, the whole physics/ragdoll engine has been removed rather than
patched. What survives in `vnpcs_belly_physics.lua` is just the movement
weight penalty:

- **Weight penalty:** a full belly slows the predator down
  (`VNPC_GetBellyWeightSlow`, integrated into DrGBase `GetAdjustedSpeeds`),
  now computed directly from `VNPC_GetBellyDeformMetrics`'s total mass
  instead of a per-tick simulation.
- Belly shape/lump positioning is entirely handled by the bounding-box
  packer in system #1 above.
- The dedicated locomotion-based belly slosh sound system
  (`vnpcs_slosh_sounds.lua`) is unrelated to this and untouched — it never
  depended on the physics simulation.

ConVars: `vnpcs_belly_physics_enabled`, `vnpcs_belly_weight_slow`.
Status: `vnpcs_belly_physics_status`.

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
- Headless Lua execution of traits + weight paint: `python3 tools/run_modules_lua.py`
- Headless Lua execution of the bounding-box belly shape packer: `python3 tools/run_box_packing_lua.py`
- Swallow animation keyframe alignment check: `python3 v_npcs/test_swallow_alignment_sim.py`
