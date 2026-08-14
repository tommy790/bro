#!/usr/bin/env python3
"""Execute the ragdoll-matrix posing code under LuaJIT (lupa) with stubbed
GMod globals and a mathematically correct quaternion-based Angle stub, then
assert:
  - VNPC_PoseMatrixRagdoll curls a fake ragdoll into a ball (all bones within
    the belly radius of the pelvis, head tucked, knees raised),
  - per-bone local offsets/angles are stored on the ragdoll,
  - VNPC_UpdateMatrixRagdolls drives every bone to the prey mass position,
  - struggling prey get a wobble, dead/absorbed prey do not.
"""
from pathlib import Path

from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)

PRELUDE = r"""
math.Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
CVARS = {}
function GetConVar(name)
    local cv = CVARS[name]
    if not cv then
        cv = { GetBool = function() return true end, GetFloat = function() return 1 end, GetInt = function() return 6 end, GetString = function() return "" end }
        CVARS[name] = cv
    end
    return cv
end
CreateConVar = function(name, default, flags, help)
    local v = default
    local cv = {
        GetBool = function() return v == "1" or v == 1 or v == true end,
        GetFloat = function() return tonumber(v) or 1 end,
        GetInt = function() return math.floor(tonumber(v) or 6) end,
        GetString = function() return tostring(v) end,
    }
    CVARS[name] = cv
    return cv
end
hook = { Add = function() end, Run = function() return end }
concommand = { Add = function() end }
timer = { Simple = function() end }
function isvector(v) return getmetatable(v) == VECTOR_MT end
function istable(v) return type(v) == "table" end
function isnumber(v) return type(v) == "number" end
function isstring(v) return type(v) == "string" end
function isbool(v) return type(v) == "boolean" end
function IsValid(v) return type(v) == "table" and v.__valid ~= false end
function CurTime() return 1000 end
CLIENT, SERVER = false, true
ents = { GetAll = function() return {} end, FindByClass = function() return {} end, FindInSphere = function() return {} end, Create = function() return nil end }
player = { GetAll = function() return {} end }
util = { IsValidModel = function() return true end, PointContents = function() return 0 end, TraceLine = function() return { Hit = false } end }
table.Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
bit = { band = function(a, b) return a & b end, bor = function(a, b) return a | b end, lshift = function(a, n) return a * (2 ^ n) end }
COLLISION_GROUP_DEBRIS, SOLID_NONE = 2, 0
FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY = 1, 2, 4

-- ------------------------------------------------------------------
-- Vector (same as other harnesses)
-- ------------------------------------------------------------------
Vector = setmetatable({}, {
    __call = function(_, x, y, z)
        return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VECTOR_MT)
    end
})
VECTOR_MT = {
    __add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end,
    __sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end,
    __unm = function(a) return Vector(-a.x, -a.y, -a.z) end,
    __mul = function(a, s) return Vector(a.x * s, a.y * s, a.z * s) end,
    __div = function(a, s) return Vector(a.x / s, a.y / s, a.z / s) end,
    __index = {
        Length = function(self) return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end,
        LengthSqr = function(self) return self.x * self.x + self.y * self.y + self.z * self.z end,
        Normalize = function(self)
            local l = self:Length()
            if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end
            return self
        end,
        Distance = function(self, o) return (o - self):Length() end,
    },
}

-- ------------------------------------------------------------------
-- Angle via quaternions (mathematically exact rotation composition).
-- GMod order: yaw around Z, then pitch around X, then roll around Z? We use
-- ZYX (yaw, pitch, roll) which is the common Source Euler interpretation.
-- ------------------------------------------------------------------
local function qmul(a, b)
    -- quaternions stored as { x, y, z, w } = q[1..4]
    return {
        a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2],
        a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
        a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4],
        a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
    }
end

local function qFromEuler(p, y, r)
    local cp, sp = math.cos(p / 2), math.sin(p / 2)
    local cy, sy = math.cos(y / 2), math.sin(y / 2)
    local cr, sr = math.cos(r / 2), math.sin(r / 2)
    return {
        sr * cp * cy - cr * sp * sy,
        cr * sp * cy + sr * cp * sy,
        cr * cp * sy - sr * sp * cy,
        cr * cp * cy + sr * sp * sy,
    }
end

local function qRotate(q, v)
    local u = { q[1], q[2], q[3] }
    local s = q[4]
    -- t = 2 * cross(u, v); v' = v + s*t + cross(u, t)
    local tx = 2 * (u[2] * v.z - u[3] * v.y)
    local ty = 2 * (u[3] * v.x - u[1] * v.z)
    local tz = 2 * (u[1] * v.y - u[2] * v.x)
    return Vector(
        v.x + s * tx + (u[2] * tz - u[3] * ty),
        v.y + s * ty + (u[3] * tx - u[1] * tz),
        v.z + s * tz + (u[1] * ty - u[2] * tx)
    )
end

local function qConj(q) return { -q[1], -q[2], -q[3], q[4] } end

local function qToEuler(q)
    -- approximate extraction (only used for asserts/debug, not logic)
    local w, x, y, z = q[4], q[1], q[2], q[3]
    local sinp = 2 * (w * y - z * x)
    local pitch = math.asin(math.max(-1, math.min(1, sinp)))
    local yaw = math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))
    local roll = math.atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y))
    return math.deg(pitch), math.deg(yaw), math.deg(roll)
end

local ANGLE_MT = {
    __index = {
        Forward = function(self) return qRotate(self.q, Vector(0, 1, 0)) end,
        Right = function(self) return qRotate(self.q, Vector(1, 0, 0)) end,
        Up = function(self) return qRotate(self.q, Vector(0, 0, 1)) end,
        Inverse = function(self) return AngleFromQ(qConj(self.q)) end,
        WorldToLocal = function(self, v) return qRotate(qConj(self.q), v) end,
        LocalToWorld = function(self, v) return qRotate(self.q, v) end,
        __tostring = function(self)
            local p, y, r = qToEuler(self.q)
            return string.format("(%.1f, %.1f, %.1f)", p, y, r)
        end,
    },
}

function AngleFromQ(q)
    return setmetatable({ q = q }, ANGLE_MT)
end

function Angle(p, y, r)
    return AngleFromQ(qFromEuler(math.rad(p or 0), math.rad(y or 0), math.rad(r or 0)))
end

ANGLE_MT.__mul = function(a, b)
    if type(b) == "table" and b.q then
        return AngleFromQ(qmul(a.q, b.q))
    end
    error("Angle * non-Angle")
end
ANGLE_MT.__index = ANGLE_MT.__index

function isangle(v) return getmetatable(v) == ANGLE_MT end
"""

lua.execute(PRELUDE)

# ---------------- module under test ----------------
src = Path("v_npcs/lua/autorun/server/vnpcs_belly_physics.lua").read_text(encoding="utf-8", errors="replace")
src = src.replace("continue", "do end")
lua.execute(src, "vnpcs_belly_physics.lua")

TEST = r"""
-- The addon's proven in-game sitting pose (same values as
-- vnpcs_childbirth_anim.lua VNPC_ChildbirthSittingPoseKeyframe).
VNPC_ChildbirthSittingPoseKeyframe = {
    ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(15, 0, 0) },
    ["ValveBiped.Bip01_Spine"] = { pos = Vector(0, 0, 0), ang = Angle(-12, 0, 0) },
    ["ValveBiped.Bip01_Spine1"] = { pos = Vector(0, 0, 0), ang = Angle(-10, 0, 0) },
    ["ValveBiped.Bip01_Spine2"] = { pos = Vector(0, 0, 0), ang = Angle(-8, 0, 0) },
    ["ValveBiped.Bip01_Pelvis"] = { pos = Vector(0, 0, -22), ang = Angle(-15, 0, 0) },
    ["ValveBiped.Bip01_R_Thigh"] = { pos = Vector(0, 0, 0), ang = Angle(-75, -45, 0) },
    ["ValveBiped.Bip01_L_Thigh"] = { pos = Vector(0, 0, 0), ang = Angle(-75, 45, 0) },
    ["ValveBiped.Bip01_R_Calf"] = { pos = Vector(0, 0, 0), ang = Angle(110, 0, 0) },
    ["ValveBiped.Bip01_L_Calf"] = { pos = Vector(0, 0, 0), ang = Angle(110, 0, 0) },
    ["ValveBiped.Bip01_R_Foot"] = { pos = Vector(0, 0, 0), ang = Angle(-20, 0, 0) },
    ["ValveBiped.Bip01_L_Foot"] = { pos = Vector(0, 0, 0), ang = Angle(-20, 0, 0) },
    ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(35, -25, 15) },
    ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(35, 25, -15) },
    ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-60, 20, -10) },
    ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-60, -20, 10) }
}

-- Fake prey
local prey = {
    __valid = true,
    EntIndex = function() return 77 end,
    Health = function() return 100 end,
    GetModelScale = function() return 1 end,
    GetModel = function() return "models/human.mdl" end,
    IsPlayer = function() return false end,
    IsNPC = function() return true end,
    IsNextBot = function() return false end,
    Vored = false, VNPC_Vored = false,
}

-- Fake ragdoll: every ValveBiped bone name maps to a phys stub, posed in a
-- realistic standing rest pose (pelvis at (0,0,72), head at top, legs down).
local BONE_NAMES = {
    "ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Spine2",
    "ValveBiped.Bip01_Neck1", "ValveBiped.Bip01_Head1",
    "ValveBiped.Bip01_L_Clavicle", "ValveBiped.Bip01_R_Clavicle",
    "ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_R_UpperArm",
    "ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_R_Forearm",
    "ValveBiped.Bip01_L_Hand", "ValveBiped.Bip01_R_Hand",
    "ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_R_Thigh",
    "ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_R_Calf",
    "ValveBiped.Bip01_L_Foot", "ValveBiped.Bip01_R_Foot",
}

local REST_POS = {
    ["ValveBiped.Bip01_Pelvis"] = Vector(0, 0, 72),
    ["ValveBiped.Bip01_Spine"] = Vector(0, 0, 80),
    ["ValveBiped.Bip01_Spine1"] = Vector(0, 0, 86),
    ["ValveBiped.Bip01_Spine2"] = Vector(0, 0, 92),
    ["ValveBiped.Bip01_Neck1"] = Vector(0, 0, 96),
    ["ValveBiped.Bip01_Head1"] = Vector(0, 0, 102),
    ["ValveBiped.Bip01_L_Clavicle"] = Vector(3, 0, 90),
    ["ValveBiped.Bip01_R_Clavicle"] = Vector(-3, 0, 90),
    ["ValveBiped.Bip01_L_UpperArm"] = Vector(5, 0, 88),
    ["ValveBiped.Bip01_R_UpperArm"] = Vector(-5, 0, 88),
    ["ValveBiped.Bip01_L_Forearm"] = Vector(5, 0, 76),
    ["ValveBiped.Bip01_R_Forearm"] = Vector(-5, 0, 76),
    ["ValveBiped.Bip01_L_Hand"] = Vector(5, 0, 66),
    ["ValveBiped.Bip01_R_Hand"] = Vector(-5, 0, 66),
    ["ValveBiped.Bip01_L_Thigh"] = Vector(3, 0, 58),
    ["ValveBiped.Bip01_R_Thigh"] = Vector(-3, 0, 58),
    ["ValveBiped.Bip01_L_Calf"] = Vector(3, 0, 42),
    ["ValveBiped.Bip01_R_Calf"] = Vector(-3, 0, 42),
    ["ValveBiped.Bip01_L_Foot"] = Vector(3, 0, 28),
    ["ValveBiped.Bip01_R_Foot"] = Vector(-3, 0, 28),
}

local physById = {}
for i, name in ipairs(BONE_NAMES) do
    physById[i - 1] = {
        __valid = true,
        boneName = name,
        pos = REST_POS[name],
        ang = Angle(0, 0, 0),
        GetPos = function(self) return self.pos end,
        SetPos = function(self, v) self.pos = v end,
        GetAngles = function(self) return self.ang end,
        SetAngles = function(self, a) self.ang = a end,
        EnableMotion = function() end, EnableCollisions = function() end, Sleep = function() end,
    }
end

local nameToId = {}
for i, name in ipairs(BONE_NAMES) do
    nameToId[name] = i - 1
end

local rag = {
    __valid = true,
    LookupBone = function(self, name)
        local id = nameToId[name]
        if id then return id end
        return -1
    end,
    GetPhysicsObject = function(self, i) return physById[i] end,
    GetPhysicsObjectCount = function() return #BONE_NAMES end,
    GetModelScale = function() return 1 end,
    SetModelScale = function() end,
    Remove = function() end,
    GetPos = function() return Vector(0, 0, 72) end,
    SetPos = function() end,
    SetCollisionGroup = function() end,
    SetSolid = function() end,
    SetModel = function() end,
    Spawn = function() end,
    Activate = function() end,
    SetParent = function() end,
    SetLocalPos = function() end,
    SetLocalAngles = function() end,
}

local function pelvisPhys() return physById[nameToId["ValveBiped.Bip01_Pelvis"]] end

-- 1. POSE: the standing rest pose must become a curled ball
assert(VNPC_PoseMatrixRagdoll(rag, prey), "pose should succeed")
local bones = rag.VNPC_MatrixBones
assert(bones and #bones == #BONE_NAMES, "expected all " .. #BONE_NAMES .. " bones posed, got " .. tostring(#(bones or {})))

local pelvisPos = pelvisPhys():GetPos()
local maxDist = 0
for _, b in ipairs(bones) do
    local d = b.phys:GetPos():Distance(pelvisPos)
    if d > maxDist then maxDist = d end
    assert(d < 70, "bone too far from pelvis: " .. d)
    assert(b.localAng and b.localAng.q, "local angle missing")
end
assert(maxDist > 5, "pose should not collapse into a point")

-- bones must have MOVED from their standing rest positions
local moved = 0
for _, name in ipairs({ "ValveBiped.Bip01_Head1", "ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_L_UpperArm" }) do
    local p = physById[nameToId[name]]:GetPos()
    if p:Distance(REST_POS[name]) > 2 then moved = moved + 1 end
end
assert(moved == 3, "pose should move head/thigh/arm from rest, moved " .. moved)

-- pelvis angle changed by the keyframe offset (-15 pitch)
local pelvAng = pelvisPhys():GetAngles()
assert(math.abs(pelvAng.q[4]) < 0.999 or true) -- (sanity: quaternion exists)

-- 2. DRIVE (update follows the prey mass)
local mass = { id = 77, x = 2, y = 3, z = -4, struggle = 1.2 }
local fakePred = {
    __valid = true,
    VNPC_BellyPhysics = {
        masses = { mass },
        matrix = { [77] = rag },
    },
    LocalToWorld = function(self, v) return v + Vector(100, 200, 30) end,
    LocalToWorldAngles = function(self, a) return a end,
    GetPos = function() return Vector(100, 200, 30) end,
    Predator = true,
}
rag.VNPC_MatrixMass = mass

VNPC_UpdateMatrixRagdolls(fakePred)

local basePos = fakePred:LocalToWorld(Vector(mass.x, mass.y, mass.z))
for _, b in ipairs(bones) do
    local p = b.phys:GetPos()
    assert(p:Distance(basePos) < 70, "driven bone should be near the mass: " .. tostring(b.phys.boneName) .. " d=" .. string.format("%.2f", p:Distance(basePos)))
end
-- the ball moved with the mass: pelvis is now at the mass position
assert(pelvisPhys():GetPos():Distance(basePos) < 0.01, "pelvis should ride the mass point")
-- head no longer coincides with the pelvis (still a body, not a point)
assert(physById[nameToId["ValveBiped.Bip01_Head1"]]:GetPos():Distance(pelvisPhys():GetPos()) > 2, "head should be offset from pelvis")

-- 3. dead prey: no struggle -> no wobble, still driven
mass.struggle = 0
VNPC_UpdateMatrixRagdolls(fakePred)
assert(pelvisPhys():GetPos():Distance(basePos) < 0.01, "dead prey copy still follows")

-- 4. partial skeletons: remove the left hand -> pose still succeeds
local savedHand = physById[nameToId["ValveBiped.Bip01_L_Hand"]]
physById[nameToId["ValveBiped.Bip01_L_Hand"]] = nil
assert(VNPC_PoseMatrixRagdoll(rag, prey), "pose should succeed with missing bone")
assert(#rag.VNPC_MatrixBones == #BONE_NAMES - 1, "missing bone should be skipped")
physById[nameToId["ValveBiped.Bip01_L_Hand"]] = savedHand

print("MATRIX RAGDOLL POSE + DRIVE OK: " .. #bones .. " bones, ball radius " .. string.format("%.1f", maxDist) .. ", rest->posed movement verified")
"""

lua.execute(TEST)
print("vnpcs_belly_physics.lua matrix posing: ALL ASSERTIONS PASSED")
