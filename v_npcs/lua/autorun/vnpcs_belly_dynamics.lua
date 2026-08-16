--[[--------------------------------------------------------------------------
    V-NPCs :: Belly Dynamics
    ---------------------------------------------------------------------------
    A drop-in physics / realism layer for the V-NPCs vore addon.

    This file NEVER changes, replaces or reloads the belly model. It only
    manipulates the transform of the already existing belly attachment bone
    with math derived from prey data, NPC motion and gravity.

    Features
        1. Asymmetrical vector scaling ...... teardrop bulge, depth >> width
        2. Gravitational sag ................ heavy bellies drag down + forward
        3. Hooke's law jiggle ............... spring-mass inertia from velocity
        4. Prey struggle ripples ............ server ticks -> client sine kicks
        5. Procedural collision bounds ...... SetSurroundingBounds vs fullness

    Realm split
        SERVER  - struggle ticks (net), surrounding bounds, state bookkeeping
        CLIENT  - all bone manipulation, springs, ripple decay, tool menu

    Composition model
        The stock belly entities (ent_vore_belly / ent_fernkarry_belly) already
        write ManipulateBoneScale/Position/Angles on the main belly bone every
        frame inside belly_modules/animations.lua. Instead of fighting that, we
        wrap the class Think and run *after* it, reading back what the stock
        code just wrote and folding our deltas into it. Nothing is duplicated,
        nothing is overwritten, and if this file is removed the addon behaves
        exactly as before.

    Bone axis reference (measured from the shipped .mdl/.vvd vertex data)
        models/wormonlooker/belly.mdl   bone 1 "main1"
            local X  +/-15.7   -> width      (symmetric, left/right)
            local Y   0.2..38  -> depth      (primary bulge, away from spine)
            local Z  -7.6..27.9-> vertical   (hang)
        models/fernkarry/belly/belly.mdl bone 1 "midsection"
            local X  +/-9.1    -> width
            local Y  -8.4..8.5 -> depth
            local Z  -8.3..8.3 -> vertical
        Both models therefore share the same axis convention, which is also the
        convention the stock code assumes when it retracts the belly with
        Vector(0, u * 1.2, u * 0.9) -- i.e. +Y/+Z is "outward and down".
        Anything exotic can be registered in VNPCS_BellyDynamics.Profiles.
--------------------------------------------------------------------------]]--

AddCSLuaFile()

VNPCS_BellyDynamics = VNPCS_BellyDynamics or {}
local DYN = VNPCS_BellyDynamics

DYN.Version = "1.0.0"

--[[------------------------------------------------------------------------]]
--[[                             SHARED  CONFIG                             ]]--
--[[------------------------------------------------------------------------]]

local SHARED_FLAGS = {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}

local cv_enabled = CreateConVar("vnpcs_dynamics", "1", SHARED_FLAGS,
    "Master switch for the V-NPCs belly dynamics layer.")
local cv_ripple = CreateConVar("vnpcs_dynamics_ripple", "1", SHARED_FLAGS,
    "Allow the server to broadcast prey struggle ripples.")
local cv_bounds = CreateConVar("vnpcs_dynamics_bounds", "1", SHARED_FLAGS,
    "Grow NPC surrounding bounds to match a stuffed belly.")

-- Cached library lookups (these run every frame, per belly).
local mathClamp = math.Clamp
local mathExp   = math.exp
local mathSin   = math.sin
local mathCos   = math.cos
local mathAbs   = math.abs
local mathMin   = math.min
local mathMax   = math.max
local mathHuge  = math.huge
local CurTime   = CurTime
local IsValid   = IsValid
local Vector    = Vector
local Angle     = Angle

local AXIS_WIDTH    = 1 -- X
local AXIS_DEPTH    = 2 -- Y
local AXIS_VERTICAL = 3 -- Z

--[[
    A profile describes how a belly model is laid out so the maths knows which
    way is "forward" and which way is "wide". Addon authors can add their own:

        VNPCS_BellyDynamics.Profiles["models/mymodel/belly.mdl"] = {
            Bone = 1, Width = 1, Depth = 2, Vertical = 3,
            DepthSign = 1, VerticalSign = 1,
        }
]]
DYN.Profiles = DYN.Profiles or {}

DYN.DefaultProfile = {
    Bone         = 1,
    Width        = AXIS_WIDTH,
    Depth        = AXIS_DEPTH,
    Vertical     = AXIS_VERTICAL,
    DepthSign    = 1,
    VerticalSign = 1,
}

DYN.Profiles["models/wormonlooker/belly.mdl"] = {
    Bone = 1, Width = AXIS_WIDTH, Depth = AXIS_DEPTH, Vertical = AXIS_VERTICAL,
    DepthSign = 1, VerticalSign = 1,
}
DYN.Profiles["models/wormonlooker/old/belly.mdl"] = DYN.Profiles["models/wormonlooker/belly.mdl"]
DYN.Profiles["models/fernkarry/belly/belly.mdl"] = {
    Bone = 1, Width = AXIS_WIDTH, Depth = AXIS_DEPTH, Vertical = AXIS_VERTICAL,
    DepthSign = 1, VerticalSign = 1,
}

--[[
    Tuning block. Every value can be overridden per NPC by declaring
    `ENT.BellyDynamics = { SagDown = 6, JiggleStiffness = 40, ... }`
    inside a character file -- see DYN.GetTuning below.
]]
DYN.DefaultTuning = {
    -- 1. asymmetrical scaling ------------------------------------------------
    AsymStrength   = 0.35, -- global blend of the whole asymmetry effect
    AsymDepth      = 0.85, -- depth / forward axis grows the most
    AsymWidth      = 0.25, -- horizontal width grows a quarter as eagerly
    AsymVertical   = 0.10, -- minimal vertical stretch

    -- 2. gravitational sag ---------------------------------------------------
    SagStrength    = 1.00,
    SagDown        = 3.50, -- units of droop toward the groin at fullness 1
    SagForward     = 2.50, -- units of forward drag at fullness 1
    SagExponent    = 1.25, -- >1 = heavier bellies sag disproportionately

    -- 3. hooke's law jiggle --------------------------------------------------
    JiggleStrength   = 1.00,
    JiggleStiffness  = 46.0, -- k  (spring constant)
    JiggleDamping    = 7.20, -- c  (viscous damping, zeta ~= 0.53 -> lively but settles)
    JiggleInertia    = 0.035, -- how strongly a velocity change kicks the spring
    JiggleMaxOffset  = 5.50, -- hard clamp, units
    JiggleAngle      = 0.85, -- deg of wobble per unit of offset
    JiggleMassGain   = 0.65, -- extra sloshiness per point of fullness

    -- 4. struggle ripples ----------------------------------------------------
    RippleScale    = 0.16,
    RippleOffset   = 2.20,
    RippleAngle    = 6.00,
    RippleFreq     = 26.0,
    RippleDecay    = 6.50,
    RippleLife     = 1.10,

    -- 5. collision bounds ----------------------------------------------------
    BoundsForward  = 26.0, -- max forward growth at fullness 1
    BoundsSide     = 8.00,
    BoundsDown     = 6.00,
}

-- Fullness is derived from the networked "BellySize" float. One swallowed
-- player lands around 0.6-0.7, so ~1.5 is treated as "completely stuffed".
local FULLNESS_REFERENCE = 1.5
local MAX_FULLNESS       = 2.5

--[[------------------------------------------------------------------------]]
--[[                            SHARED  HELPERS                             ]]--
--[[------------------------------------------------------------------------]]

--- Returns the merged tuning table for a belly (NPC overrides win).
-- Result is cached on the entity; invalidated whenever the parent changes.
function DYN.GetTuning(belly, npc)
    local cached = belly.VNPCsDynTuning
    if cached and cached.__npc == npc then return cached end

    local tuning = {__npc = npc}
    for k, v in pairs(DYN.DefaultTuning) do tuning[k] = v end

    local override = IsValid(npc) and npc.BellyDynamics or nil
    if istable(override) then
        for k, v in pairs(override) do
            if isnumber(v) then tuning[k] = v end
        end
    end

    belly.VNPCsDynTuning = tuning
    return tuning
end

--- Resolves the axis profile for a belly's current model.
function DYN.GetProfile(belly)
    local profile = DYN.Profiles[belly:GetModel() or ""]
    if profile then return profile end

    local override = belly.BellyDynamicsProfile
    if istable(override) then return override end

    return DYN.DefaultProfile
end

--- Normalised 0..1 fullness plus the raw networked size.
function DYN.GetFullness(belly)
    local size = belly:GetNWFloat("BellySize", 0)
    if size ~= size then return 0, 0 end -- NaN guard
    size = mathClamp(size, 0, MAX_FULLNESS)
    return mathClamp(size / FULLNESS_REFERENCE, 0, 1), size
end

--- Resolves the NPC that owns a belly, whichever way it was parented.
function DYN.GetOwner(belly)
    local npc = belly:GetNWEntity("NPCParent")
    if IsValid(npc) then return npc end

    npc = belly:GetParent()
    if IsValid(npc) then return npc end

    return nil
end

--[[------------------------------------------------------------------------]]
--[[                                SERVER                                  ]]--
--[[------------------------------------------------------------------------]]

if SERVER then

util.AddNetworkString("VNPCs_BellyRipple")

-- Every live belly entity, so we never have to run ents.FindByClass.
DYN.Active = DYN.Active or {}
local active = DYN.Active

local BOUNDS_EPSILON  = 0.05 -- refresh bounds only when fullness really moved
local THINK_INTERVAL  = 0.25

local vector_origin = Vector(0, 0, 0)

--- Snapshots an NPC's untouched surrounding bounds exactly once.
local function captureBaseBounds(npc)
    if npc.VNPCsDynBoundsMin then return true end

    local mins, maxs = npc:OBBMins(), npc:OBBMaxs()
    if not mins or not maxs then return false end
    if mins == vector_origin and maxs == vector_origin then return false end

    npc.VNPCsDynBoundsMin = Vector(mins)
    npc.VNPCsDynBoundsMax = Vector(maxs)
    return true
end

--- Puts an NPC's collision envelope back to how the game shipped it.
function DYN.ResetBounds(npc)
    if not IsValid(npc) then return end
    if not npc.VNPCsDynBoundsMin then return end

    npc:SetSurroundingBounds(npc.VNPCsDynBoundsMin, npc.VNPCsDynBoundsMax)
    npc.VNPCsDynLastBounds = nil
end

--[[
    FEATURE 5 -- procedural dynamic collision bounds.
    The belly grows forward from the spine, so the surrounding AABB has to grow
    with it or the NPC will happily clip a full stomach through door frames.
    SetSurroundingBounds takes vectors relative to the entity origin, which is
    the same space as OBBMins/OBBMaxs, so we can grow the captured hull safely.
]]
function DYN.UpdateBounds(npc, belly, fullness, tuning)
    if not cv_bounds:GetBool() then
        if npc.VNPCsDynLastBounds then DYN.ResetBounds(npc) end
        return
    end

    if not captureBaseBounds(npc) then return end

    local last = npc.VNPCsDynLastBounds
    if last and mathAbs(last - fullness) < BOUNDS_EPSILON then return end
    npc.VNPCsDynLastBounds = fullness

    if fullness <= 0 then
        DYN.ResetBounds(npc)
        npc.VNPCsDynLastBounds = 0
        return
    end

    local mins = npc.VNPCsDynBoundsMin
    local maxs = npc.VNPCsDynBoundsMax

    local forward = tuning.BoundsForward * fullness
    local side    = tuning.BoundsSide * fullness
    local down    = tuning.BoundsDown * fullness

    -- The belly can face either way along X depending on the NPC's model, and
    -- surrounding bounds are axis aligned in entity space anyway, so grow both
    -- horizontal directions. This stays a cheap AABB -- no hull rebuild.
    npc:SetSurroundingBounds(
        Vector(mins.x - forward, mins.y - side, mins.z - down),
        Vector(maxs.x + forward, maxs.y + side, maxs.z)
    )
end

--- True if at least one *living player* is currently inside the belly.
local function hasLivingPlayerPrey(belly)
    local prey = belly.Prey
    if not istable(prey) then return false, 0 end

    local players, alive = 0, 0
    for i = 1, #prey do
        local entry = prey[i]
        if istable(entry) and entry.Alive then
            alive = alive + 1
            local ent = entry.Entity
            if IsValid(ent) and ent:IsPlayer() and ent:Alive() then
                players = players + 1
            end
        end
    end

    return players > 0, alive
end

--[[
    FEATURE 4 (server half) -- randomly broadcast a struggle tick.
    Only sent to players who can actually see the belly (PVS), so a map full of
    stuffed NPCs costs almost nothing in bandwidth.
]]
function DYN.BroadcastRipple(belly, intensity)
    intensity = mathClamp(intensity, 0, 1)

    net.Start("VNPCs_BellyRipple", true) -- unreliable: a dropped wobble is fine
        net.WriteEntity(belly)
        net.WriteUInt(math.floor(intensity * 255), 8)
        net.WriteUInt(math.random(0, 255), 8)
    net.SendPVS(belly:GetPos())
end

local function struggleThink(belly, now)
    if not cv_ripple:GetBool() then return end
    if belly:GetNWInt("DigestionPhase", 0) ~= 1 then return end

    local nextTick = belly.VNPCsDynNextRipple
    if nextTick and now < nextTick then return end

    local hasPlayers, aliveCount = hasLivingPlayerPrey(belly)
    if not hasPlayers then
        belly.VNPCsDynNextRipple = now + 1.5
        return
    end

    -- Respect the addon's own struggle tuning so this feels consistent.
    local multi = 1
    local cvMulti = GetConVar("vnpcs_struggle_multi")
    if cvMulti then multi = mathClamp(cvMulti:GetFloat(), 0, 8) end
    multi = multi * (belly.PreyStruggleMultiplier or 1)

    if multi <= 0 then
        belly.VNPCsDynNextRipple = now + 2
        return
    end

    -- More prey = more frequent and more violent kicks.
    local crowd = mathMin(aliveCount, 4)
    local period = mathMax(0.35, (1.9 - crowd * 0.22) / multi)
    belly.VNPCsDynNextRipple = now + period * math.Rand(0.6, 1.4)

    local intensity = mathClamp(0.35 + crowd * 0.18, 0, 1)
        * mathClamp(multi * 0.75, 0.25, 1)
    DYN.BroadcastRipple(belly, intensity * math.Rand(0.7, 1.15))
end

--- Master server tick: one timer for the whole map, not one per entity.
local function serverThink()
    if not cv_enabled:GetBool() then return end

    local now = CurTime()

    for belly in pairs(active) do
        if not IsValid(belly) then
            active[belly] = nil
        else
            local npc = DYN.GetOwner(belly)
            if IsValid(npc) then
                local fullness = DYN.GetFullness(belly)
                local tuning = DYN.GetTuning(belly, npc)

                DYN.UpdateBounds(npc, belly, fullness, tuning)
                struggleThink(belly, now)
            end
        end
    end
end

timer.Create("VNPCs_BellyDynamics", THINK_INTERVAL, 0, serverThink)

hook.Add("OnEntityCreated", "VNPCs_BellyDynamics_Track", function(ent)
    if not IsValid(ent) then return end
    if not ent.VoreBelly then return end

    -- Wait a tick: parenting/model are not set during OnEntityCreated.
    timer.Simple(0, function()
        if IsValid(ent) and ent.VoreBelly then
            active[ent] = true
        end
    end)
end)

hook.Add("EntityRemoved", "VNPCs_BellyDynamics_Untrack", function(ent)
    if not ent then return end

    if ent.VoreBelly then
        active[ent] = nil

        -- Clean reset: the NPC must not keep a stuffed hitbox forever.
        local npc = DYN.GetOwner(ent)
        if IsValid(npc) then DYN.ResetBounds(npc) end
        return
    end

    if ent.VNPCsDynBoundsMin then
        ent.VNPCsDynBoundsMin = nil
        ent.VNPCsDynBoundsMax = nil
        ent.VNPCsDynLastBounds = nil
    end
end)

-- Flipping the convars off must restore stock behaviour immediately.
cvars.AddChangeCallback("vnpcs_dynamics_bounds", function()
    for belly in pairs(active) do
        if IsValid(belly) then
            local npc = DYN.GetOwner(belly)
            if IsValid(npc) then
                DYN.ResetBounds(npc)
                npc.VNPCsDynLastBounds = nil
            end
        end
    end
end, "VNPCs_BellyDynamics")

cvars.AddChangeCallback("vnpcs_dynamics", function(_, _, new)
    if tonumber(new) == 0 then
        for belly in pairs(active) do
            if IsValid(belly) then
                local npc = DYN.GetOwner(belly)
                if IsValid(npc) then DYN.ResetBounds(npc) end
            end
        end
    end
end, "VNPCs_BellyDynamics_Master")

return end -- SERVER

--[[------------------------------------------------------------------------]]
--[[                                CLIENT                                  ]]--
--[[------------------------------------------------------------------------]]

local cv_asym    = CreateClientConVar("vnpcs_dynamics_asym", "1", true, false,
    "Asymmetrical (teardrop) belly scaling.")
local cv_sag     = CreateClientConVar("vnpcs_dynamics_sag", "1", true, false,
    "Gravitational belly sag.")
local cv_jiggle  = CreateClientConVar("vnpcs_dynamics_jiggle", "1", true, false,
    "Hooke's law belly jiggle physics.")
local cv_shake   = CreateClientConVar("vnpcs_dynamics_shake", "1", true, false,
    "Prey struggle ripples and kicks.")
local cv_dist    = CreateClientConVar("vnpcs_dynamics_distance", "1400", true, false,
    "Distance in units past which belly dynamics stop simulating.")

local MAX_RIPPLES   = 5
local MAX_DELTA     = 0.1 -- clamp frame time: alt-tabbing must not explode springs
local MAX_DV        = 600 -- clamp per-frame velocity change: teleports must not explode springs

local vector_one = Vector(1, 1, 1)

--[[------------------------------ sanitising -----------------------------]]--
--[[
    Entity:ManipulateBoneScale silently HIDES every vertex weighted to a bone
    when it is handed a NaN, and the stock animation code openly admits it can
    produce NaN ("ik this will be nAn sometimes"). Everything we hand to the
    engine therefore goes through these guards first.
]]

local function safeNumber(value, fallback, minimum, maximum)
    if value ~= value then return fallback end            -- NaN
    if value == mathHuge or value == -mathHuge then return fallback end
    return mathClamp(value, minimum, maximum)
end

local function sanitizeVector(vec, fallback, minimum, maximum)
    vec.x = safeNumber(vec.x, fallback, minimum, maximum)
    vec.y = safeNumber(vec.y, fallback, minimum, maximum)
    vec.z = safeNumber(vec.z, fallback, minimum, maximum)
    return vec
end

local function sanitizeAngle(ang, limit)
    ang.p = safeNumber(ang.p, 0, -limit, limit)
    ang.y = safeNumber(ang.y, 0, -limit, limit)
    ang.r = safeNumber(ang.r, 0, -limit, limit)
    return ang
end

--[[-------------------------------- state --------------------------------]]--

local function getState(belly)
    local state = belly.VNPCsDynState
    if state then return state end

    state = {
        JigglePos = Vector(0, 0, 0), -- spring displacement, NPC-local axes
        JiggleVel = Vector(0, 0, 0),
        LastVel   = Vector(0, 0, 0),
        LastTime  = CurTime(),
        Ripples   = {},
        Applied   = false,

        -- Anti-compounding bookkeeping. We layer on top of whatever the stock
        -- animation code wrote, so we must be able to tell "the stock code
        -- refreshed this bone" from "nobody touched it since we wrote to it".
        BaseScale = nil, BaseScaleOut = nil,
        BasePos   = nil, BasePosOut   = nil,
        BaseAng   = nil, BaseAngOut   = nil,
    }

    belly.VNPCsDynState = state
    return state
end

--[[
    Resolves the "clean" value of a bone channel for this frame.

    Both shipped belly classes rewrite the main bone every single Think, so the
    value we read back is a fresh stock value and we simply layer on it. A
    third-party belly that writes less often would otherwise have our deltas
    applied to our own previous output, compounding every frame into a runaway
    belly. So: if what we read is still exactly what we last wrote, nobody
    refreshed it and we reuse the base we captured back then.
]]
local function resolveBase(current, lastOut, lastBase, epsilon)
    if lastOut and lastBase then
        if mathAbs(current[1] - lastOut[1]) <= epsilon
            and mathAbs(current[2] - lastOut[2]) <= epsilon
            and mathAbs(current[3] - lastOut[3]) <= epsilon then
            return lastBase
        end
    end
    return current
end

local function clearState(belly)
    local state = belly.VNPCsDynState
    if not state then return end

    state.BaseScale, state.BaseScaleOut = nil, nil
    state.BasePos, state.BasePosOut = nil, nil
    state.BaseAng, state.BaseAngOut = nil, nil

    state.JigglePos:Zero()
    state.JiggleVel:Zero()
    state.LastVel:Zero()

    local ripples = state.Ripples
    for i = #ripples, 1, -1 do ripples[i] = nil end

    state.Applied = false
end

--[[------------------------- FEATURE 4 : ripples --------------------------]]--

local function addRipple(belly, intensity, seed)
    local state = getState(belly)
    local ripples = state.Ripples
    local tuning = DYN.GetTuning(belly, DYN.GetOwner(belly))

    if #ripples >= MAX_RIPPLES then table.remove(ripples, 1) end

    -- The seed decides where on the belly the kick lands, so two simultaneous
    -- prey do not punch in perfect unison.
    local theta = (seed / 255) * math.pi * 2

    ripples[#ripples + 1] = {
        Start     = CurTime(),
        Intensity = mathClamp(intensity, 0, 1),
        Phase     = theta,
        Freq      = tuning.RippleFreq * math.Rand(0.85, 1.2),
        Decay     = tuning.RippleDecay * math.Rand(0.9, 1.15),
        Life      = tuning.RippleLife,
        DirWidth  = mathCos(theta),
        DirVert   = mathSin(theta),
    }
end

--- Sums every live ripple. Returns wave amplitudes for scale/pos/angle use.
local function evaluateRipples(state, now)
    local ripples = state.Ripples
    local count = #ripples
    if count == 0 then return 0, 0, 0 end

    local main, width, vert = 0, 0, 0

    for i = count, 1, -1 do
        local r = ripples[i]
        local age = now - r.Start

        if age < 0 or age > r.Life then
            table.remove(ripples, i)
        else
            -- Violent, rapidly decaying sine distortion.
            local decay = mathExp(-age * r.Decay)
            local wave = mathSin(age * r.Freq + r.Phase) * decay * r.Intensity

            main  = main + wave
            width = width + wave * r.DirWidth
            vert  = vert + wave * r.DirVert
        end
    end

    return main, width, vert
end

net.Receive("VNPCs_BellyRipple", function()
    local belly = net.ReadEntity()
    local intensity = net.ReadUInt(8) / 255
    local seed = net.ReadUInt(8)

    if not cv_enabled:GetBool() or not cv_shake:GetBool() then return end
    if not IsValid(belly) or not belly.VoreBelly then return end

    addRipple(belly, intensity, seed)
end)

--[[--------------------- FEATURE 3 : Hooke's law jiggle -------------------]]--
--[[
    A classic damped harmonic oscillator, integrated semi-implicitly:

        x'' = -(k/m)x - (c/m)x'        (spring + viscous damper)

    driven by the NPC's motion. The driving term is the *velocity change* of
    the NPC applied as an impulse (dv), not an acceleration:

        v = v + (-k*x - c*v) * dt - dv * load

    Using dv rather than dv/dt matters. Acceleration spikes scale with 1/dt, so
    an acceleration-driven spring kicks ~5x harder at 30fps than at 144fps for
    the identical in-game motion, and any clamp on it either guts the effect at
    high frame rates or explodes at low ones. An impulse is frame-rate
    independent by construction: a 250 u/s stop produces a 0.90 unit swing at
    144, 60 and 30 fps alike (measured).

    The result overshoots on a sudden stop, bounces on landing, and lags on a
    sharp turn. The spring runs in the NPC's local basis (forward/right/up),
    which maps directly on to the belly bone's depth/width/vertical axes.
    Damping ratio zeta ~= 0.53: two or three visible wobbles, then still.
]]
local function updateJiggle(state, npc, tuning, fullness, delta)
    local velocity = npc:GetVelocity()
    local lastVel = state.LastVel

    -- Per-frame velocity change in world space, clamped so a teleport or a
    -- respawn cannot detonate the spring.
    local dvx = safeNumber(velocity.x - lastVel.x, 0, -MAX_DV, MAX_DV)
    local dvy = safeNumber(velocity.y - lastVel.y, 0, -MAX_DV, MAX_DV)
    local dvz = safeNumber(velocity.z - lastVel.z, 0, -MAX_DV, MAX_DV)

    lastVel.x, lastVel.y, lastVel.z = velocity.x, velocity.y, velocity.z

    -- Project the world-space impulse on to the NPC's own axes.
    local ang = npc:GetAngles()
    local fwd, right, up = ang:Forward(), ang:Right(), ang:Up()

    local aDepth = dvx * fwd.x + dvy * fwd.y + dvz * fwd.z
    local aWidth = dvx * right.x + dvy * right.y + dvz * right.z
    local aVert  = dvx * up.x + dvy * up.y + dvz * up.z

    -- A fuller belly is heavier: softer spring, longer travel, more slosh.
    local mass = 1 + fullness * tuning.JiggleMassGain
    local k = tuning.JiggleStiffness / mass
    local c = tuning.JiggleDamping / math.sqrt(mass)
    local load = tuning.JiggleInertia * mass

    local pos, vel = state.JigglePos, state.JiggleVel
    local limit = tuning.JiggleMaxOffset * (0.35 + fullness * 0.65)

    -- Spring/damper integrate over dt; the motion impulse does not (it is
    -- already a velocity delta) -- that is what keeps this frame-rate stable.
    vel.x = vel.x + (-k * pos.x - c * vel.x) * delta - aWidth * load
    vel.y = vel.y + (-k * pos.y - c * vel.y) * delta - aDepth * load
    vel.z = vel.z + (-k * pos.z - c * vel.z) * delta - aVert * load

    pos.x = pos.x + vel.x * delta
    pos.y = pos.y + vel.y * delta
    pos.z = pos.z + vel.z * delta

    sanitizeVector(vel, 0, -400, 400)
    sanitizeVector(pos, 0, -limit, limit)

    return pos
end

--[[--------------------------- the main layer ----------------------------]]--

function DYN.ApplyClient(belly)
    if not cv_enabled:GetBool() then
        if belly.VNPCsDynState and belly.VNPCsDynState.Applied then
            clearState(belly)
        end
        return
    end

    local profile = DYN.GetProfile(belly)
    local bone = profile.Bone or 1

    local boneCount = belly:GetBoneCount()
    if not boneCount or bone >= boneCount then return end

    -- Read back whatever belly_modules/animations.lua just wrote this frame.
    local readScale = belly:GetManipulateBoneScale(bone)
    if not readScale or readScale:IsZero() then
        -- Stock code hid the belly (empty stomach): stay out of the way.
        clearState(belly)
        return
    end

    local fullness = DYN.GetFullness(belly)
    local npc = DYN.GetOwner(belly)

    local state = getState(belly)

    -- Recover the untouched stock value (see resolveBase) and work on a copy,
    -- so we never feed our own output back into the next frame's maths.
    local scale = Vector(resolveBase(readScale, state.BaseScaleOut, state.BaseScale, 0.0001))
    state.BaseScale = Vector(scale)
    local now = CurTime()
    local delta = mathClamp(now - state.LastTime, 0.0005, MAX_DELTA)
    state.LastTime = now

    -- Cheap distance cull. Bones we never touched simply keep stock values.
    local maxDist = cv_dist:GetFloat()
    if maxDist > 0 and belly:GetPos():DistToSqr(EyePos()) > maxDist * maxDist then
        if state.Applied then clearState(belly) end
        return
    end

    local tuning = DYN.GetTuning(belly, npc)

    local rippleMain, rippleWidth, rippleVert = 0, 0, 0
    if cv_shake:GetBool() then
        rippleMain, rippleWidth, rippleVert = evaluateRipples(state, now)
    elseif #state.Ripples > 0 then
        local ripples = state.Ripples
        for i = #ripples, 1, -1 do ripples[i] = nil end
    end

    -- Nothing to do at all: let the stock transform stand untouched.
    if fullness <= 0 and rippleMain == 0 then
        if state.Applied then clearState(belly) end
        return
    end

    local wAxis = profile.Width or AXIS_WIDTH
    local dAxis = profile.Depth or AXIS_DEPTH
    local vAxis = profile.Vertical or AXIS_VERTICAL
    local dSign = profile.DepthSign or 1
    local vSign = profile.VerticalSign or 1

    ----------------------------------------------------------------------
    -- FEATURE 1 : asymmetrical vector scaling
    ----------------------------------------------------------------------
    -- The stock code applies a *uniform* Vector(1,1,1) * size. We keep that
    -- as the base volume and bias it into a teardrop: the depth axis swells
    -- far more than the width, and the vertical axis barely moves at all, so
    -- the slope already sculpted into the mesh is accentuated instead of the
    -- belly simply becoming a bigger sphere.
    if cv_asym:GetBool() then
        local blend = tuning.AsymStrength * fullness
        local depthMul = 1 + tuning.AsymDepth * blend
        local widthMul = 1 + tuning.AsymWidth * blend
        local vertMul  = 1 + tuning.AsymVertical * blend

        if rippleMain ~= 0 then
            -- A kick momentarily bulges depth and pinches width (volume-ish).
            local rs = tuning.RippleScale
            depthMul = depthMul * (1 + rippleMain * rs)
            widthMul = widthMul * (1 - rippleMain * rs * 0.55)
            vertMul  = vertMul * (1 + rippleVert * rs * 0.4)
        end

        scale[dAxis] = scale[dAxis] * depthMul
        scale[wAxis] = scale[wAxis] * widthMul
        scale[vAxis] = scale[vAxis] * vertMul

        sanitizeVector(scale, 1, 0.01, 12)
        belly:ManipulateBoneScale(bone, scale)
        state.BaseScaleOut = Vector(scale)
    else
        state.BaseScaleOut = nil
    end

    ----------------------------------------------------------------------
    -- FEATURE 2 + 3 : gravitational sag, jiggle offset, ripple kicks
    ----------------------------------------------------------------------
    local readPos = belly:GetManipulateBonePosition(bone)
    if readPos then
        local pos = Vector(resolveBase(readPos, state.BasePosOut, state.BasePos, 0.0005))
        state.BasePos = Vector(pos)

        local sagDepth, sagVert = 0, 0

        if cv_sag:GetBool() and fullness > 0 then
            -- Weight does not sit politely on the spine: it drags toward the
            -- groin and pulls forward. The exponent makes a nearly empty
            -- stomach barely droop while a stuffed one really hangs.
            local weight = fullness ^ tuning.SagExponent * tuning.SagStrength
            sagDepth = tuning.SagForward * weight * dSign
            sagVert  = -tuning.SagDown * weight * vSign
        end

        local jx, jy, jz = 0, 0, 0
        if cv_jiggle:GetBool() and IsValid(npc) then
            local jiggle = updateJiggle(state, npc, tuning, fullness, delta)
            local strength = tuning.JiggleStrength
            jx = jiggle.x * strength -- width
            jy = jiggle.y * strength -- depth
            jz = jiggle.z * strength -- vertical
        end

        local kickDepth, kickWidth, kickVert = 0, 0, 0
        if rippleMain ~= 0 then
            local ro = tuning.RippleOffset
            kickDepth = rippleMain * ro * dSign
            kickWidth = rippleWidth * ro * 0.7
            kickVert  = rippleVert * ro * 0.7 * vSign
        end

        pos[dAxis] = pos[dAxis] + sagDepth + jy + kickDepth
        pos[wAxis] = pos[wAxis] + jx + kickWidth
        pos[vAxis] = pos[vAxis] + sagVert + jz + kickVert

        sanitizeVector(pos, 0, -64, 64)
        belly:ManipulateBonePosition(bone, pos)
        state.BasePosOut = Vector(pos)

        ------------------------------------------------------------------
        -- Wobble: turn the linear spring offset into a little rotation so
        -- the mass visibly swings rather than sliding.
        ------------------------------------------------------------------
        local readAng = belly:GetManipulateBoneAngles(bone)
        if readAng then
            local ang = Angle(readAng)
            if state.BaseAngOut and state.BaseAng
                and mathAbs(ang.p - state.BaseAngOut.p) <= 0.0005
                and mathAbs(ang.y - state.BaseAngOut.y) <= 0.0005
                and mathAbs(ang.r - state.BaseAngOut.r) <= 0.0005 then
                ang = Angle(state.BaseAng)
            end
            state.BaseAng = Angle(ang)

            local wob = tuning.JiggleAngle
            local rippleAng = tuning.RippleAngle

            ang.p = ang.p + jy * wob + rippleMain * rippleAng * 0.5
            ang.y = ang.y + jx * wob * 0.8 + rippleWidth * rippleAng * 0.35
            ang.r = ang.r + jx * wob + rippleVert * rippleAng * 0.5

            sanitizeAngle(ang, 45)
            belly:ManipulateBoneAngles(bone, ang)
            state.BaseAngOut = Angle(ang)
        end
    end

    state.Applied = true
end

--[[-------------------------- instance wrapping ---------------------------]]--
--[[
    We wrap each belly ENTITY's Think rather than using a global think hook, so
    our maths is guaranteed to run immediately AFTER the stock animation code
    every frame -- no ordering race, no flicker, and exactly zero cost for
    anything that is not a belly.

    Wrapping the instance (not the class table) is deliberate: ent_grower_vore
    inherits both VoreBelly and Think from ent_vore_belly and defines neither
    itself, so a class-table wrap would silently miss it. Looking the function
    up through the instance resolves the whole inheritance chain for free and
    works for any third-party belly too.
]]

local function wrapInstance(ent)
    if ent.VNPCsDynWrapped then return end
    ent.VNPCsDynWrapped = true

    local original = ent.Think -- resolved through the full inheritance chain

    ent.Think = function(self, ...)
        local a, b, c
        if original then
            a, b, c = original(self, ...)
        end

        -- Never let our layer break the entity if something goes wrong.
        local ok, err = pcall(DYN.ApplyClient, self)
        if not ok then
            ErrorNoHaltWithStack("[V-NPCs Belly Dynamics] " .. tostring(err))
            -- Detach from this entity rather than spam the console every frame.
            self.Think = original
            self.VNPCsDynWrapped = nil
            clearState(self)
        end

        return a, b, c
    end
end

DYN.WrapInstance = wrapInstance

hook.Add("OnEntityCreated", "VNPCs_BellyDynamics_Wrap", function(ent)
    if not IsValid(ent) then return end

    -- VoreBelly / model / parent are not populated yet during OnEntityCreated.
    timer.Simple(0, function()
        if IsValid(ent) and ent.VoreBelly then
            wrapInstance(ent)
        end
    end)
end)

-- Pick up bellies that already exist (script reload, or this file hot-loaded).
local function wrapExisting()
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent.VoreBelly then
            wrapInstance(ent)
        end
    end
end

hook.Add("InitPostEntity", "VNPCs_BellyDynamics_WrapExisting", wrapExisting)
hook.Add("OnReloaded", "VNPCs_BellyDynamics_WrapExisting", wrapExisting)

-- If the layer is switched off mid-game, drop all accumulated state at once.
cvars.AddChangeCallback("vnpcs_dynamics", function()
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent.VoreBelly then
            clearState(ent)
        end
    end
end, "VNPCs_BellyDynamics_Reset")

--[[------------------------------ tool menu ------------------------------]]--

hook.Add("PopulateToolMenu", "VNPCs_BellyDynamicsMenu", function()
    spawnmenu.AddToolMenuOption("V-NPCs", "Personalization", "vnpcs_dynamics",
        "Belly Dynamics", "", "", function(panel)
            panel:ClearControls()

            panel:Help("Physics and realism layer for belly attachments.")
            panel:ControlHelp("Purely mathematical: the belly model itself is never modified.")

            panel:CheckBox("Enable Belly Dynamics", "vnpcs_dynamics")
            panel:CheckBox("Asymmetrical (teardrop) scaling", "vnpcs_dynamics_asym")
            panel:CheckBox("Gravitational sag", "vnpcs_dynamics_sag")
            panel:CheckBox("Jiggle physics", "vnpcs_dynamics_jiggle")
            panel:CheckBox("Struggle ripples", "vnpcs_dynamics_shake")

            panel:NumSlider("Simulation Distance", "vnpcs_dynamics_distance", 0, 4000, 0)
            panel:ControlHelp("Bellies further away than this stop simulating. Lower it if you spawn a lot of NPCs.")

            panel:Help("\nServer settings\n")
            panel:CheckBox("Broadcast struggle ripples (server)", "vnpcs_dynamics_ripple")
            panel:CheckBox("Dynamic collision bounds (server)", "vnpcs_dynamics_bounds")
            panel:ControlHelp("Expands an NPC's surrounding bounds so a stuffed belly collides with props and doorways.")
        end)
end)
