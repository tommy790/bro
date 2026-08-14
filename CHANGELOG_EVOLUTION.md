# V-NPCs — "Evolution" Update

This pass reworks four core systems in the V-NPCs addon. Nothing here needs
new models/materials — everything is built on top of the existing
`ent_vore_belly` / `npc_vore_base` / DrGBase-nextbot architecture so every
current V-NPC gets the upgrade for free.

## 1. Dynamic Weight Painting & Mesh Deform

**Files:** `v_npcs/lua/entities/belly_modules/basic_visual.lua`,
`v_npcs/lua/entities/belly_modules/animations.lua`,
`v_npcs/lua/entities/belly_modules/mechanics.lua`

The belly no longer just inflates as one uniform blob. Every prey swallowed
records its own `HalfExtents` (its actual bounding box) when it's eaten.
`ENT:GetBellyShapeVector()` averages those extents (weighted by how much of
each prey is still left) into a width/depth/height bias, replicated to
clients as `BellyShape`. `animations.lua` blends the belly's bone scale
towards that shape every frame, so a short, wide prey pushes the belly out
sideways while a tall one bulges it up and forward — no bespoke "belly
shape" per creature required.

New convar: `vnpcs_traits_enabled` gates whether trait-driven digestion
(see #4) feeds into this and the other systems.

## 2. Full Physics-Driven Digestion ("Ragdoll Matrix")

**File:** `v_npcs/lua/entities/belly_modules/ragdoll_matrix.lua`

Source doesn't support simulating a real ragdoll bouncing around inside a
deforming skinned mesh cavity, so this implements the same *effect* through
a lightweight simulated physics state per living prey:

- A spring-damped position bounded to the belly's interior radius.
- Driven by **real input**: players' actual movement keys (mashing WASD
  while trapped) for players, semi-random flailing impulses for NPCs/props.
- The dominant (currently most active) prey's simulated position/force is
  networked (`RagOffset`, `RagForce`) and used to jostle/shift the belly
  bone position and add extra "bounce" scale in `animations.lua`.
- When the struggle is strong enough, nearby physics props and players get
  gently shoved (`ENT:PushNearbyPhysics`) so the belly behaves like an
  actual solid object with something moving inside it, plus an occasional
  screen shake.

**Why not literally teleport the prey's ragdoll to a hidden box outside the
map and read its physics impulses back?** That's a real, commonly-used
trick, but it carries its own risks: extreme/void coordinates can lose
float precision or land inside a level's kill-Z / `trigger_hurt` volume,
and a relocated NPC still needs its AI `Think` re-enabled to actually
struggle — which fights with the rest of the addon deliberately disabling
it when eaten (`prey:NextThink(CurTime() + 1e9)` in `mechanics.lua`). The
purely virtual spring simulation here gets the same visible result — belly
bounce driven by real player input — without ever moving, un-solidifying,
or re-enabling anything on the real entity, so none of those failure modes
can happen. It's a deliberately more conservative version of the same idea.

New convars: `vnpcs_ragdoll_matrix`, `vnpcs_ragdoll_collision`,
`vnpcs_ragdoll_force`.

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
vnpcs_traits_enabled        1   -- master switch for the trait system
vnpcs_ragdoll_matrix        1   -- Ragdoll Matrix simulation on/off
vnpcs_ragdoll_collision     1   -- lets a struggling belly push nearby physics/players
vnpcs_ragdoll_force         1   -- multiplier for that push force
vnpcs_smart_ai              1   -- master switch for the Smart AI layer
vnpcs_smart_ai_hearing      1   -- footstep/flashlight detection
vnpcs_smart_ai_packhunt     1   -- flanking/surrounding
vnpcs_smart_ai_ambush       1   -- ambush behaviour
vnpcs_smart_ai_navmesh      1   -- allow navmesh queries (needs nav_generate on the map)
```

All of these are also exposed in the spawnmenu under **V-NPCs > Personalization > Settings**.
