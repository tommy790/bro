# V-NPCs Remade Systems

Four system remakes added on top of the existing V-NPCs architecture.

---

## 1. Dynamic Weight Painting & Mesh Deform
**Files:** `lua/autorun/sh_vnpc_weight_paint.lua` (new), edits in
`lua/autorun/sh_vnpc_gpu_belly.lua`

Every swallowed entity becomes a **volumetric shape blob** built from its
*measured* body parts (`VNPC_MeasureBodyParts`: torso/head/pelvis width,
limb length, model scale) and physics mass. The old "one rigid teardrop belly"
is replaced by a procedurally deformed mesh:

- **Blob bounding box drives the belly ellipsoid** — a long prey makes a long
  belly, a wide prey makes a wide belly, multiple prey stack into a bigger one.
- **Per-vertex gaussian weight painting** adds a lump for every prey that
  tracks its live simulated position inside the belly (see system 2), so the
  belly visibly bulges where the prey actually is.
- **Asymmetric skeleton stretching** — the generated belly bones shift toward
  the center of mass, and the character's own spine/pelvis/thigh bones are
  scaled per-axis and per-side, so even stock models without belly bones grow a
  lopsided, prey-shaped belly instead of a fixed shape.

ConVars: `vnpcs_weight_paint_enabled`, `vnpcs_weight_paint_lumps`,
`vnpcs_weight_paint_amp`, `vnpcs_weight_paint_asymmetry`.
Status: `vnpcs_weight_paint_status`; test: `vnpcs_test_paint_blob [w] [h] [d]`.

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
  ride inside the belly (visible with the inside-camera), each driven to its
  physics position, wobbling while the prey struggles.

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
