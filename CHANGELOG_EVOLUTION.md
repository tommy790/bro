# V-NPCs — "Evolution" Update

This pass reworks four core systems in the V-NPCs addon. Nothing here needs
new models/materials — everything is built on top of the existing
`ent_vore_belly` / `npc_vore_base` / DrGBase-nextbot architecture so every
current V-NPC gets the upgrade for free.

## 1. Dynamic Weight Painting & Mesh Deform

**Files:** `v_npcs/lua/entities/belly_modules/basic_visual.lua`,
`v_npcs/lua/entities/belly_modules/animations.lua`,
`v_npcs/lua/entities/ent_fernkarry_belly.lua`,
`v_npcs/lua/entities/belly_modules/mechanics.lua`

The belly no longer just inflates as one uniform blob, and this is now a
purely geometric, deterministic system — no physics simulation involved
(an earlier "Ragdoll Matrix" physics-jostle approach was tried here and
removed; see below).

Every prey swallowed records its own `HalfExtents` (its actual bounding
box) when it's eaten, shrinking as it digests. `ENT:GetBellyShapeVector()`
(in `basic_visual.lua`) takes every currently-living prey's box and packs
them "shoulder to shoulder" into rows, like laying boxes down on a shelf:

- Up to 3 bodies pack side-by-side into a row — their widths add together,
  so 2 similarly-sized prey genuinely reads as a wider belly instead of a
  rounder single blob.
- A 4th+ body spills into a new row, which adds *depth* instead of making
  the belly absurdly wide.
- The packed footprint is compared against what a single body of
  equivalent bulk would need, producing a width/depth/height bias vector
  around `(1,1,1)` that's replicated to clients as `BellyShape`.

`animations.lua` (and `ent_fernkarry_belly.lua`'s own copy of the same
logic) smoothly blends the belly's bone scale towards that shape every
frame. Because the whole thing is a deterministic function of who's
currently inside — not a live simulation — there's nothing to desync,
jitter, or feel "off"; the only smoothing is the client-side Lerp on the
networked vector.

New convar: `vnpcs_shape_deform` (default on) toggles the whole system off
back to legacy uniform inflation. `vnpcs_traits_enabled` separately gates
whether trait-driven digestion (see #4) affects digestion speed/capacity.

## 2. Full Physics-Driven Digestion ("Ragdoll Matrix") — removed

An earlier pass added a `belly_modules/ragdoll_matrix.lua` module that kept
a per-prey spring-damped simulated struggle position, driven by real player
input, to jostle the belly bone position/scale in real time. In practice
this didn't hold up — the animated jostle/wobble felt unreliable rather
than convincing — so it's been removed entirely in favor of the purely
geometric bounding-box system in #1 above, which gives a more convincing
"there's actually something specific in there" read without any live
simulation to fight with. `prey_table.Rag`/`NextImpulse` and the
`RagOffset`/`RagOffset2`/`RagForce`/`RagForce2` networked vars are gone;
`vnpcs_ragdoll_matrix`/`vnpcs_ragdoll_collision`/`vnpcs_ragdoll_force` no
longer exist.

## 3. Smart Nextbot AI & Navigation Mesh


**File:** `v_npcs/lua/entities/npc_modules/smart_ai.lua`

Adds a tactics layer on top of DrGBase's own chase/patrol logic:

- **Sound tracking** — hooks `PlayerFootstep`; sprinting carries further
  than walking. V-NPCs within range get `SpotEntity`'d without needing a
  direct sightline.
- **Flashlight tracking** — a flashlight beam pointed roughly at a V-NPC
  within range and with a clear trace will catch its attention.
- **Pack hunting** — V-NPCs hunting the same target register into a shared
  pack. The closest hunter chases normally; the rest periodically peel off
  and use the map's navmesh (`navmesh.GetNearestNavArea` /
  `GetClosestPointOnArea`) to flank/surround the target instead of all
  approaching in a single file.
- **Ambushes** — idle V-NPCs occasionally pick an adjacent-but-unseen nav
  area near their patrol route (`CNavArea:GetAdjacentAreas` /
  `GetRandomPoint`) and wait there, springing the moment a player gets
  close and has line of sight.

Everything nav-mesh related is defensive (`pcall`'d) and falls back to the
existing straight-line behaviour if a map has no `.nav` file generated.

New convars: `vnpcs_smart_ai`, `vnpcs_smart_ai_hearing`,
`vnpcs_smart_ai_packhunt`, `vnpcs_smart_ai_ambush`, `vnpcs_smart_ai_navmesh`.
Per-NPC-type tuning lives in `ENT.VoreSettings.SmartAI` (hearing range,
flashlight spot range, and per-behaviour on/off).

**Fail-safe:** the whole pack/ambush/hearing pass runs inside `pcall`. If it
throws 3 times in a row for a given NPC (broken/missing `.nav` file, a
DrGBase update that changes how `MoveTowards`/`AddPatrolPos` behave, etc.)
that NPC permanently trips a circuit breaker, clears any half-finished
maneuver, logs it once, and falls back to DrGBase's plain, foolproof
direct-chase for the rest of its life — instead of erroring or silently
no-op'ing every 0.3s forever.

## 4. Modular Status & Trait System

**Files:** `v_npcs/lua/entities/npc_modules/traits.lua`,
`v_npcs/lua/autorun/vnpcs.lua`, `v_npcs/lua/autorun/client/vnpcs_status_menu.lua`

Every V-NPC now carries four networked, per-entity traits:

| Trait | Effect |
| --- | --- |
| **Metabolism Speed** | Multiplies this predator's digestion & absorption power. |
| **Acid Resistance** | Divides the digestion damage *this entity* takes when it's the one being digested — matters for players, NPCs, and chain-vore between predators. |
| **Max Capacity** | Hard cap on concurrent living prey (0 = unlimited), enforced via the belly's `EatCondition`. |
| **Stamina Penalty** | Multiplies how much extra a heavier belly slows the predator's walk/run speed. |

Right-click any V-NPC predator and choose **"Vore Status..."** to open the
in-game status menu and tune these live with sliders. Default per-NPC-type
values can also be set in code via `ENT.VoreSettings.Traits = { ... }`.

Master kill switch: `vnpcs_traits_enabled` (falls back to legacy 1:1
behaviour when off).

---

### Quick convar reference

```
vnpcs_shape_deform          1   -- bounding-box belly shape system on/off
vnpcs_traits_enabled        1   -- master switch for the trait system
vnpcs_smart_ai              1   -- master switch for the Smart AI layer
vnpcs_smart_ai_hearing      1   -- footstep/flashlight detection
vnpcs_smart_ai_packhunt     1   -- flanking/surrounding
vnpcs_smart_ai_ambush       1   -- ambush behaviour
vnpcs_smart_ai_navmesh      1   -- allow navmesh queries (needs nav_generate on the map)
```

All of these are also exposed in the spawnmenu under **V-NPCs > Personalization > Settings**.
