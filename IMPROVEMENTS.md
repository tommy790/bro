# V-NPCs — Improvement Plan

A prioritized review of the addon as of `1a66f74`. Tiers are ordered by
"how much pain does this cause a player right now".

**Status: Tier 0, the render-target leak (0.7) and struggle-to-escape (1.1) are
implemented.** Everything marked ✅ below has been fixed on this branch; the rest
of Tier 1-3 is still open. See the commits for the diffs.

---

## Tier 0 — Correctness bugs that break multiplayer / multi-NPC play — ✅ DONE

These are not style issues. Each one is reproducible with two NPCs on a map.

### 0.1 ✅ `ENT.Prey` is a **shared class table** — all bellies share one prey list
`v_npcs/lua/entities/belly_modules/mechanics.lua:14`

```lua
ENT.Prey = {}   -- lives on the shared ENT table, never re-created per instance
```

Nothing ever does `self.Prey = {}` in `Initialize`. Because `self.Prey` resolves
through `__index` to the class table, **every belly entity in the map inserts
into the same table**. Consequences:

- Spawn two predators; feed one. Both bellies inflate.
- `GetCollectivePreyValue()` returns the global total, so belly size, speed
  penalty and weight gain are all cross-contaminated.
- `DigestPrey` runs the same prey once per belly per tick → digestion speed
  scales with the number of NPCs alive.
- `WipeAllPrey()` on one belly's removal kills prey inside *other* predators.

**Fix**

```lua
function ENT:Initialize()
    self.Prey = {}
    ...
end
```

and audit every `ENT.X = {}` at file scope. Same class-table sharing affects:

| Field | File |
|---|---|
| `ENT.Prey` | `belly_modules/mechanics.lua:14` |
| `ENT.LoadedSounds` | `belly_modules/sounds.lua:43` |
| `ENT.DigestSounds` / `ENT.AbsorbSounds` | `belly_modules/sounds.lua:44-45` |
| `ENT.CurrentFlexes` | `npc_vore_base.lua:173` |
| `ENT.VoreSettings` / `ENT.Speeds` | `npc_vore_base.lua` |

A cheap guard: a shared `ENT:InitInstanceTables()` that deep-copies the declared
defaults into the instance, called first thing in `Initialize`.

### 0.2 ✅ Second predator spawned has **no digestion/absorb sounds** (and errors)
`v_npcs/lua/entities/belly_modules/sounds.lua:145-165`

`CreateSounds()` dedupes against `self.LoadedSounds`, which is the shared class
table (see 0.1). The first belly marks every sound path as loaded, so the second
belly builds `self.DigestSounds = {}`. Then:

```lua
local index = math.random(1, #self.DigestSounds)   -- math.random(1, 0)
```

throws `bad argument #2 to 'random' (interval is empty)` the first time it
digests. The `LoadedSounds` dedupe is trying to solve a *per-instance* problem
with *global* state — it should just be removed, and `StartDigestionSound`
should early-out on an empty list regardless.

### 0.3 ✅ `EntityEmitSound` hook indexes a NULL entity on every sound in the game
`v_npcs/lua/autorun/vnpcs.lua:35`

```lua
local parent = ent:GetParent()
if ent.Vored or parent.Vored then    -- parent is NULL for unparented entities
```

Reading a field off a NULL entity raises `Tried to use a NULL entity!`. This hook
fires for *every sound emitted by anything, everywhere*, so it's both an error
spam source and a per-sound cost. Fix:

```lua
local parent = ent:GetParent()
if not (ent.Vored or (IsValid(parent) and parent.Vored)) then return end
```

Also consider gating the whole hook behind a counter of currently-vored entities
so it costs nothing when nobody is swallowed.

### 0.4 ✅ `WipeAllPrey` calls `:Remove()` on players
`v_npcs/lua/entities/belly_modules/mechanics.lua:380`

```lua
preyEnt:TakeDamageInfo(dmg_i)
preyEnt:Remove()          -- preyEnt may be a Player
```

`Entity:Remove()` on a `Player` is explicitly unsupported and causes anything
from a broken player slot to a server crash. Branch on `IsPlayer()` and use
`:Kill()` (or better: release them, see 1.1).

**There was a second instance**, found later while building 1.1, on a much
hotter path: `AbsorbSpecificPrey` (`mechanics.lua`) does the same
`prey:Remove()` when a prey's health reaches zero. That is the *ordinary*
"finished digesting" path, so it is the one players actually hit — every player
digested by any NPC was being `Remove()`d. Both sites are now guarded.

A digested player is deliberately still not *released*: they stay nodraw'd
inside with the belly camera and the "You have been digested..." HUD until they
respawn, which is what `PlayerSpawn` in `autorun/server/convars.lua` already
cleans up.

### 0.5 ✅ Regurgitated NPCs stay frozen forever; regurgitated players keep the belly cam
`v_npcs/lua/entities/belly_modules/mechanics.lua:296`

`AddPrey` does `prey:NextThink(CurTime() + 1e9)` and, for players, sends
`UGotVored` which installs `CalcView`/`HUDPaint`/`CreateMove` hooks. `Regurgitate`
restores solidity/movetype/nodraw but **never**:

- restores `NextThink` → the NPC is a statue for the rest of the map,
- clears `SCHED_NPC_FREEZE`,
- sends `StopVoreClient` → the player is stuck in the belly camera outside the belly,
- re-enables weapon switching (`PlayerSwitchWeapon` still returns `true` until
  `ply.Vored` is cleared… which it does, OK, but the client hooks stay).

Every exit path (regurgitate, predator death, prey death, disconnect,
`PlayerSpawn`) should go through one `ReleasePrey(entry, reason)` function that
is the *only* place restoring state.

**Fixed** by `ENT:ReleasePreyEntity(prey, oldFlags)` in `mechanics.lua`, now used
by both `Regurgitate` and `WipeAllPrey`. `Regurgitate` additionally drops the
digestion phase back to 0 and refreshes `AliveFactor`; `belly_modules/npc.lua`
was widened from `new == 0 and old == 2` to `new == 0` so the digestion loop is
stopped when the last prey is spat out rather than absorbed.

### 0.6 ✅ `properties.Add("vnpcs_eatme")` trusts the client
`v_npcs/lua/autorun/vnpcs.lua:18`

```lua
Receive = function(self, len, ply)
    local ent = net.ReadEntity()
    ent:ClearPatrols()                       -- no IsValid, no Filter re-check
    ent:SetEntityRelationship(ply, D_HT, 99999)
```

The `Filter` only runs clientside. A crafted net message with any entity index
either errors the server or lets a client aggro/rewrite relationships on
arbitrary entities. Always re-run the filter serverside:

```lua
Receive = function(self, len, ply)
    local ent = net.ReadEntity()
    if not IsValid(ent) or not self:Filter(ent, ply) then return end
    if not gamemode.Call("CanProperty", ply, "vnpcs_eatme", ent) then return end
    ...
end
```

### 0.7 ✅ Render targets are allocated per belly and never reclaimed
`v_npcs/lua/autorun/client/vnpcs_belly_rt.lua:285`

```lua
nextUID = nextUID + 1
local rt = GetRenderTarget("vnpcs_belly_rt_" .. belly:EntIndex() .. "_" .. nextUID, 512, 512)
```

GMod caches render targets by name for the lifetime of the map and never frees
them. Spawning and deleting 40 NPCs over a session permanently allocates 40
512×512 RTs (~40 MB) plus 40 clientside models. Two fixes, both worth doing:

1. **Pool** RTs: keep a free list of `N` RTs (say 16) and hand them out to
   whichever bellies are actually visible this frame.
2. **Share by signature**: the capture only depends on
   `model+skin+bodygroups+material+color+flexes+pose`. Ten Loonas with identical
   appearance should share one texture. Key the cache on `buildSignature()`
   instead of on the belly entity — this collapses most servers to 2-3 RTs total.

**Implemented**, both of the above plus two more:

3. **Deterministic slot names.** RTs are now named
   `vnpcs_belly_rt_<size>_<index>`, so the set of names the addon can ever ask
   for is fixed. Previously the name embedded an ever-incrementing UID, so every
   spawn asked the engine for a brand new one. Slots are reclaimed by LRU (an
   entry drawn this frame is never evicted, so there is no capture thrash).
4. **One shared clone.** Captures all run sequentially inside a single
   `PostRender` pass, so a single reused `ClientsideModel` is enough — a belly no
   longer owns a hidden entity for its whole lifetime.
5. **Draw-driven work.** The per-frame `Think` hook is gone entirely.
   `GetMaterial` is only called from `ENT:Draw`, so a belly that is not on screen
   now costs literally nothing. This also removes the `forceTPose`-every-frame
   problem listed in Tier 2.

Simulated over a 2000-step spawn/remove session with ~6 distinct looks on screen:

| | render targets | materials | clone entities | RT VRAM |
|---|---|---|---|---|
| before | 1237 (unbounded) | 1237 | 474 | ~1237 MB |
| after | 8 | 8 | 1 | 8 MB |

Ceiling after the change is `max slots (32) x distinct sizes (4) = 128` RTs even
if a user cycles every convar, versus unbounded growth before.

New convars: `vnpcs_belly_rt` (on/off), `vnpcs_belly_rt_slots` (default 8),
`vnpcs_belly_rt_size` (128/256/512/1024). `vnpcs_belly_rt_stats` prints pool
usage. When every slot is busy the extra bellies fall back to their plain
material rather than thrashing, and say so once in console.

### 0.8 ✅ 10 NPCs error on spawn: `ENT.VoreSettings = {}` wipes the base defaults

Found while fixing the above. `table.Inherit` is **shallow**:

```lua
function table.Inherit( t, base )
    for k, v in pairs( base ) do
        if ( t[ k ] == nil ) then t[ k ] = v end
    end
```

So an NPC writing `ENT.VoreSettings = {}` (which all 27 of them do) shadows the
base table wholesale and loses every default inside it. The one that matters is
`FlexFaces`: `SetFacialExpression` does `self.VoreSettings.FlexFaces[phase]`, and
`CustomInitialize` calls it on spawn, so these NPCs threw
"attempt to index a nil value" the moment they were spawned:

`vnpcs_alyx`, `vnpcs_alyx2`, `vnpcs_femalevort`, `vnpcs_loona`, `vnpcs_moss`,
`vnpcs_swaptest`, `vnpcs_sybil`, `vnpcs_vonlycaon`, `vnpcs_vort`, `vnpcs_zorobom`.

**Fix**: `ENT:ResolveVoreSettings()` in `npc_vore_base.lua` walks the registered
class chain (`scripted_ents.GetStored(...).t` → `BaseClass` → …) and merges
base-first into a per-instance table, so derived values win and unset ones fall
back. Called from `CustomInitialize` (server) and `CustomThink` (client), cached
via `_VoreSettingsResolved`. `faces.lua` also guards a missing `FlexFaces`
instead of erroring.

Note the merge is shallow by design; nested tables like `BoneOffsets` stay shared
by reference, which is fine today because the only thing written into them
(`info.BoneID`) is model-specific and instances of a class share a model.

### 0.9 ✅ `faces.lua` mutated a shared table while iterating it

`SetFacialExpression` assigned `self.VoreFlexTargets = flexFaces[phase]` — a
reference to the **class-level** table — and then wrote resolved flex IDs back
into it inside the `pairs()` loop over that same table. Two bugs at once:
inserting keys during a `pairs()` traversal is undefined behaviour in Lua, and
the class table permanently accumulated flex IDs that then got applied to every
other model sharing the base defaults. Resolved targets now go into a fresh
per-instance table.

---

## Tier 1 — Missing gameplay that people will actually ask for

### 1.1 ✅ Prey has **zero agency** — `Regurgitate` is dead code
`grep -rn Regurgitate` returns only its own definition. Nothing in the addon ever
calls it. Once swallowed, a player watches a camera until they die. This is the
single biggest feature gap.

Proposed struggle loop:

- Prey holds/mashes `+use` (or WASD) → accumulates `struggle` on the server.
- Struggle applies to a per-prey `escapeProgress`, resisted by predator
  `DigestionStrength` and current belly fullness; drain over time.
- Crossing 1.0 forces a `Regurgitate` with a spit-out animation, an impulse, and
  a cooldown before that predator can re-eat the same target.
- Struggling drives the existing belly flex springs harder and plays the already
  present `Sounds.Struggle` set — the visuals are already built, they're just
  driven by an RNG timer today (`belly_modules/animations.lua:StruggleAnimation`).
- Convars: `vnpcs_prey_escape 1`, `vnpcs_prey_escape_multi 1`.

**Implemented** in `belly_modules/struggle.lua`, plus a server input hook
(`autorun/server/vore_struggle.lua`) and a HUD meter in `player_vored.lua`.

Input is read server-side from `GM:KeyPress`, which fires once per press rather
than continuously while held — so it rewards mashing, cannot be cheesed by
taping a key down, and there is no net message for a client to forge. A 0.06s
floor between counted presses keeps bind-spam from outrunning an honest player.

Escape is resisted by the predator's `DigestionStrength`, by how many other
things are in the belly, and by how digested the prey already is. Struggling
feeds `StruggleIntensity` to the belly, which drives the existing flex springs
harder and more often, so a fighting player visibly thrashes the belly instead
of the animation running purely off a random timer.

The constants were picked by simulating the escape curve against the digestion
window rather than by feel, specifically to avoid a pass/fail cliff. Against a
default predator (`DigestionStrength` 2, which digests a 100 hp player in 25s):

| mash rate | outcome |
|---|---|
| 3/sec | digested, never escapes |
| 4/sec | escapes at 23s — right on the buzzer |
| 6/sec | escapes at 6.6s |
| 12/sec | escapes at 2.6s |

An earlier tuning had a hard cliff at ~5/sec where the meter simply never left
zero, which gave the player no feedback at all; the health-falloff floor
(`StruggleMinHealthFactor`) is what turns that into a gradient.

Predators with `DigestionStrength` 3+ are effectively inescapable at a human
mash rate, which is intentional — their digest window is shorter too. Server
owners can open that up with `vnpcs_prey_escape_multi`.

On escape the prey is placed clear of the predator with a hull trace, shoved,
and given a `vnpcs_prey_escape_cooldown` grace period during which that predator
both refuses to re-swallow it and drops it as an enemy.

Convars: `vnpcs_prey_escape`, `vnpcs_prey_escape_multi`,
`vnpcs_prey_escape_npcs` (default off — lets swallowed NPCs thrash free too),
`vnpcs_prey_escape_cooldown`. New entity hooks: `OnPreyStruggled(ent, progress)`
and `OnPreyEscaped(ent)`.

Note the alternate `ent_fernkarry_belly` has its own inline copy of the struggle
animation code, so it gets the mechanic but not the intensity-driven visuals —
another argument for 3.4.

### 1.2 Digestion abuses `Entity:Health()`
`mechanics.lua:135`

```lua
if prey:Health() < 25 then prey:SetHealth(25) end  -- "super binary and hardcoded"
```

Using entity health as the digestion timer means: a nearly-dead NPC gets *healed*
on swallow, a 1000 HP boss takes 8 minutes, props get a fake health pool, and any
other addon writing health desyncs the belly. Track digestion in the prey entry
(`entry.Integrity` 0..1, driven by `DigestionStrength` and prey mass) and only
apply damage to the entity as a *presentation* of that value.

### 1.3 No prey cap / no size sanity
Nothing limits how many entities fit or how big they can be. A player can feed an
NPC 50 barrels; `GetCollectivePreyValue()` explodes, `GetBellySize()` goes to
`scale^0.5` of a huge number, the bone scale becomes absurd and the clip-fix
trace hull becomes map-sized. Add `MaxPrey`, `MaxPreyValue`, and reject
(or "too big to swallow") beyond it.

### 1.4 Prey measurement is wrong for long thin objects
`mechanics.lua:36`

```lua
return max_bounds:Length() * ent:GetModelScale()
```

A 200-unit plank reads as "huge", a fat crate reads as small. Use a volumetric
measure:

```lua
local mins, maxs = ent:GetModelBounds()
local size = maxs - mins
local volume = math.abs(size.x * size.y * size.z) * scale^3
return volume ^ (1/3)
```

### 1.5 Predator death does nothing interesting
Killing a predator removes the belly → `OnRemove` → `WipeAllPrey` → everything
inside dies. A convar `vnpcs_release_on_death` that regurgitates living prey
(and drops a gooey ragdoll for the digested) is a 20-line change once 1.1 exists.

---

## Tier 2 — Performance

Measured against a realistic scene (8 NPCs, 1 belly each).

| Cost | Where | Fix |
|---|---|---|
| `ents.Iterator()` **every frame per NPC** for head-look | `npc_modules/client.lua:67` | `ents.FindInSphere(eyePos, max_dist)`, throttled to 4 Hz with a cached target |
| `ents.FindInSphere(pos, 35)` **every think per NPC** for doors | `npc_modules/drgbase.lua:141` (the comment already says "THIS IS SCARY") | throttle to 0.25 s, and skip entirely unless moving |
| ~~`forceTPose(clone)` every frame for every belly~~ | `vnpcs_belly_rt.lua` | ✅ **done** — the Think hook is gone; the single shared clone is only posed immediately before a capture |
| `util.TraceHull` per belly per frame for the floor clip fix | `belly_modules/animations.lua` | run at 10 Hz and interpolate the spring between samples; skip when the belly is small or off-screen |
| 6 × `GetNW*` string lookups per belly per frame | `belly_modules/animations.lua:Think` | see 3.1 (`SetupDataTables`) |
| `SetHull` loop over all players every `Think` | `lua/autorun/sh_belly_system.lua` | it already caches with `_SmoothBellyHullSize`, but the loop itself should be a per-player hook |

Also: nothing checks visibility. Bellies keep running springs, traces and sound
logic while behind the player (RT captures are now draw-driven and no longer
part of this). Gate the expensive clientside work
on `belly:IsDormant()` / a PVS + frustum check.

---

## Tier 3 — Architecture & maintainability

### 3.1 Replace `NW` vars with `SetupDataTables`
There are 18 `SetNW*` writes and 24 `GetNW*` reads. Legacy NW vars are
string-keyed, unpredicted, and re-sent to every player. `SetupDataTables` gives
typed accessors (`self:GetBellySize()`), automatic client prediction, and no hash
lookup in the per-frame path:

```lua
function ENT:SetupDataTables()
    self:NetworkVar("Float", 0, "BellySize")
    self:NetworkVar("Float", 1, "BaseScale")
    self:NetworkVar("Int",   0, "DigestionPhase")
    self:NetworkVar("Int",   1, "AliveFactor")
    self:NetworkVar("Entity",0, "Predator")
end
```

### 3.2 Centralize the 24 convars
They're currently declared in 8 different files, and 8 of them are declared
*twice* (`vnpcs_patrol_full`, `vnpcs_fat_multi`, `vnpcs_struggle_multi`, …).
Move them all into `lua/vnpcs/sh_config.lua` with a single declarative table:

```lua
VNPCs.Config = {
    { "vnpcs_digestion_multi", 1, "Global digestion speed multiplier" },
    ...
}
```

Then generate both the convars **and** the tool menu from that table —
`autorun/client/tool_menu.lua` (332 lines) is currently a hand-maintained mirror
of the convar list and will drift.

### 3.3 The `force_*` / `*_multi` convar pattern is copy-pasted 6 times
```lua
local power = self.Thing
if force_thing:GetBool() then power = global_multi:GetFloat()
else power = power * global_multi:GetFloat() end
```
appears in `mechanics.lua` (×2), `ent_vore_belly.lua`, `weight_gain.lua`,
`animations.lua` (×2). One helper:

```lua
function VNPCs.Resolve(value, forceCvar, multiCvar)
    local m = multiCvar:GetFloat()
    return forceCvar:GetBool() and m or value * m
end
```

### 3.4 The 40 NPC files are ~90 % identical
`vnpcs_loona.lua` and `vnpcs_roxy.lua` differ in about 25 meaningful lines out of
130+; the ValveBiped weight-gain bone list, `WeightGainSettings`, clavicle
`BoneOffsets` and the `Butt`/`Breast` definers are verbatim copies across most
files. Two changes make new NPCs trivial and let you fix a bug once instead of
40 times:

1. **Presets**: `VNPCs.Presets.ValveBipedFemale` supplying bones, settings and
   definers; NPCs override only what differs.
2. **Data registration**: `VNPCs.Register("loona", { PrintName = "Loona", Model = ..., Belly = {...} })`
   that builds the `ENT` table, so an NPC file is pure data with no
   `AddCSLuaFile()`/`DrGBase.AddNextbot` boilerplate to forget.

Add a `VNPCs.Validate(ENT)` dev-mode pass that warns on missing bones, unknown
flex names and bad model paths at spawn — most "NPC is broken" reports are one
of those three.

### 3.5 The root `lua/` folder is a second, unrelated addon
`lua/autorun/cl_belly_system.lua` + `sh_belly_system.lua` implement a *player*
belly (hull resizing, footsteps, jiggle) with no connection to `v_npcs`. It ships
its own `autorun`, a global `set_belly` concommand with **no admin check**, and a
`Think`-loop over all players. Decide: fold it into V-NPCs as the player-predator
module (there is obvious overlap with the belly spring code in
`belly_modules/animations.lua`), or move it to its own repo. Leaving two
`lua/autorun` trees in one repository will bite whoever packages this.

### 3.6 Repo hygiene
- No `README.md`: no install steps, no DrGBase dependency note, no convar list,
  no "how to add an NPC" guide. This is the highest-leverage single file to add.
- No `LICENSE`.
- No linting. `glualint` in a GitHub Action would have caught the shared-table
  bugs' cousins (unused locals, shadowed upvalues like the `belly_fat_loss`
  self-shadow in `belly_modules/npc.lua:LoseWeight`).
- 20 stray `print()` calls, several tagged by the author ("get rid of this one
  day", `print(ent, ent:GetClass())` in `EatEntity`). Replace with
  `VNPCs.Debug(...)` gated on `vnpcs_debug`.
- Magic numbers with no names: `0.013`, `0.007`, `3.5`, `36 * newSize`,
  `ughhhhhh`. Hoist into a documented `VNPCs.Tuning` table — these are the
  values people actually want to tweak.

### 3.7 Sound lifetime
`CSoundPatch` objects in `DigestSounds`/`AbsorbSounds` are never `:Stop()`ed;
`StopAllSounds()` iterates the *filename* table and calls `self:StopSound(name)`,
which does not stop a patch. Removing a belly mid-digestion can leave a looping
gurgle playing until map change. Stop patches explicitly in `OnRemove`.

---

## Suggested order of work

1. ~~Per-instance tables, NULL-entity hook, player `:Remove()`, property
   validation, unified release path~~ — **done** (Tier 0).
2. ~~RT pooling/sharing and the per-frame `forceTPose`~~ — **done** (0.7).
3. ~~Struggle-to-escape (1.1)~~ — **done**.
4. Digestion decoupled from `Entity:Health()` (1.2) and prey caps (1.3). 1.2 is
   now the most valuable remaining item: struggle strength keys off prey health,
   so the health hack distorts the escape curve too.
5. `SetupDataTables` + centralized config + generated tool menu (3.1, 3.2).
6. Presets/registration refactor for the NPC files (3.4), README (3.6).
