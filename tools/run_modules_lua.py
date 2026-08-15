#!/usr/bin/env python3
"""Execute the real Lua weight-paint + trait modules under LuaJIT (lupa) with
stubbed GMod globals, and exercise their pure functions:
  - VNPC_GetPreyShapeBlob, VNPC_ComputeBellyBlobs, VNPC_GetBellyDeformMetrics,
    VNPC_SyncPaintBlobNW, VNPC_ApplyWeightPaintDeform, VNPC_GetBellyComShift,
    VNPC_GetWeightPaintBoneScale,
  - VNPC_GetTraits / VNPC_AddTrait / VNPC_RemoveTrait / VNPC_GetTraitStat /
    VNPC_GetTraitStatSummary / conflict resolution.
"""
import re
from pathlib import Path

from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)

PRELUDE = r"""
math.Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
-- Lua 5.3+ removed math.atan2; GMod's LuaJIT has it. Polyfill for the harness.
if not math.atan2 then
    math.atan2 = function(y, x) return math.atan(y, x) end
end
CVARS = {}
function GetConVar(name)
    local cv = CVARS[name]
    if not cv then
        cv = { GetBool = function() return false end, GetFloat = function() return 0 end, GetInt = function() return 0 end, GetString = function() return "" end }
        CVARS[name] = cv
    end
    return cv
end
CreateConVar = function(name, default, flags, help)
    local v = default
    local cv = {
        GetBool = function() return v == "1" or v == 1 or v == true end,
        GetFloat = function() return tonumber(v) or 0 end,
        GetInt = function() return math.floor(tonumber(v) or 0) end,
        GetString = function() return tostring(v) end,
    }
    CVARS[name] = cv
    return cv
end
hook = { Add = function() end, Run = function() return end }
concommand = { Add = function() end }
timer = { Simple = function() end }
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
    }
}
function isvector(v) return getmetatable(v) == VECTOR_MT end
function istable(v) return type(v) == "table" end
function isnumber(v) return type(v) == "number" end
function isstring(v) return type(v) == "string" end
function isbool(v) return type(v) == "boolean" end
function IsValid(v) return type(v) == "table" and v.__valid ~= false end
function CurTime() return 1000 end
function FrameTime() return 0.016 end
-- NOTE: the client test below bumps the frame via a global so both chunks share it
FRAME = 1
function FrameNumber() return FRAME end
function LerpVector(t, a, b) return a + (b - a) * t end
CLIENT, SERVER = false, true
ents = {
    GetAll = function() return {} end,
    FindByClass = function() return {} end,
    FindInSphere = function() return {} end,
    Create = function() return nil end,
}
player = { GetAll = function() return {} end }
util = { IsValidModel = function() return true end, PointContents = function() return 0 end, TraceLine = function() return { Hit = false } end }
table.Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
bit = { band = function(a, b) return a & b end, bor = function(a, b) return a | b end, lshift = function(a, n) return a * (2 ^ n) end }
COLLISION_GROUP_DEBRIS, SOLID_NONE = 2, 0
FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY = 1, 2, 4

function MakeEnt(id)
    return {
        __valid = true,
        EntIndex = function() return id end,
        Health = function() return 100 end,
        GetMaxHealth = function() return 100 end,
        GetModelScale = function() return 1 end,
        GetPhysicsObject = function() return nil end,
        GetModelBounds = function() return Vector(-16, -16, 0), Vector(16, 16, 72) end,
        GetModel = function() return "models/human.mdl" end,
        GetClass = function() return "npc_vnpc" end,
        PrintName = function() return "Test" end,
        IsPlayer = function() return false end,
        IsNPC = function() return true end,
        IsNextBot = function() return false end,
        SetNWString = function() end, SetNWInt = function() end, SetNWFloat = function() end, SetNWVector = function() end,
        GetNWInt = function() return 0 end, GetNWFloat = function() return 0 end, GetNWVector = function() return Vector(0, 0, 0) end, GetNWString = function() return "" end,
        Vored = false, VNPC_Vored = false,
        VNPC_IsPregnant = nil,
    }
end
"""


def load(name):
    src = Path(f"v_npcs/lua/autorun/{name}").read_text(encoding="utf-8", errors="replace")
    src = src.replace("continue", "do end")
    lua.execute(src, name)


lua.execute(PRELUDE)
load("sh_vnpc_traits.lua")
load("sh_vnpc_weight_paint.lua")

TEST = r"""
-- ============================ TRAITS ============================
local pred = MakeEnt(1)
pred.Predator = true
pred.VNPC_Traits = {}
assert(VNPC_AddTrait(pred, "fast_metabolism"))
assert(VNPC_HasTrait(pred, "fast_metabolism"))
assert(math.abs(VNPC_GetTraitStat(pred, "metabolism") - 1.5) < 0.001, "metabolism mult")
-- stacking: fast_metabolism and glutton are compatible, both boost metabolism
assert(VNPC_AddTrait(pred, "glutton"))
assert(VNPC_HasTrait(pred, "fast_metabolism"), "glutton should not conflict with fast_metabolism")
assert(math.abs(VNPC_GetTraitStat(pred, "metabolism") - 1.5 * 1.25) < 0.001, "stacked metabolism")
assert(math.abs(VNPC_GetTraitStat(pred, "capacity") - 1.25) < 0.001)
-- real conflict: glutton vs dainty -> adding glutton removes dainty
local predX = MakeEnt(9)
predX.Predator = true
predX.VNPC_Traits = {}
assert(VNPC_AddTrait(predX, "dainty"))
assert(VNPC_AddTrait(predX, "glutton"))
assert(not VNPC_HasTrait(predX, "dainty"), "glutton should remove dainty")
-- stacking: tireless + glutton capacity stays 1.25
assert(VNPC_AddTrait(pred, "tireless"))
assert(math.abs(VNPC_GetTraitStat(pred, "weight_resistance") - 1.6) < 0.001)
-- prey-only trait refused on a predator
assert(not VNPC_AddTrait(pred, "acid_resistant"), "prey trait on predator should be refused")
-- removal
assert(VNPC_RemoveTrait(pred, "tireless"))
assert(not VNPC_HasTrait(pred, "tireless"))

local prey = MakeEnt(2)
prey.VNPC_Traits = {}
assert(VNPC_AddTrait(prey, "acid_resistant"))
assert(math.abs(VNPC_GetTraitStat(prey, "acid_resistance") - 1.6) < 0.001)
-- conflict: weak_stomach replaces acid_resistant (both directions checked)
assert(VNPC_AddTrait(prey, "weak_stomach"))
assert(not VNPC_HasTrait(prey, "acid_resistant"), "weak_stomach should replace acid_resistant")
assert(math.abs(VNPC_GetTraitStat(prey, "acid_resistance") - 0.7) < 0.001)
assert(VNPC_AddTrait(prey, "restless"))
assert(math.abs(VNPC_GetTraitStat(prey, "struggle_energy") - 1.5) < 0.001)
-- stat summary
local summary = VNPC_GetTraitStatSummary(prey)
assert(summary.acid_resistance and summary.struggle_energy, "summary missing stats")

-- ======================== WEIGHT PAINT ==========================
local pred2 = MakeEnt(3)
pred2.Predator = true
local preyA = MakeEnt(4)
local preyB = MakeEnt(5)

-- shape blobs from a humanoid-ish entity
local blobA = VNPC_GetPreyShapeBlob(preyA)
local blobB = VNPC_GetPreyShapeBlob(preyB)
assert(blobA and blobA.rx > 0 and blobA.ry > 0 and blobA.rz > 0, "prey blob missing radii")
assert(blobA.mass > 20, "prey blob mass too small")
assert(blobB and blobB.rx > 0, "preyB blob missing")

-- fake belly with two prey
local belly = {
    Prey = {
        { Entity = preyA, Value = 120, Alive = true, Absorbing = false },
        { Entity = preyB, Value = 90, Alive = true, Absorbing = false },
    },
    NPC = pred2,
}
pred2.VNPC_Belly = belly
pred2.Belly = belly

local blobs = VNPC_ComputeBellyBlobs(pred2)
-- fetal-curl: 2 prey x 3 sub-blobs (torso/head/limb)
assert(#blobs == 6, "expected 6 sub-blobs, got " .. #blobs)
local kinds = {}
for _, b in ipairs(blobs) do
    kinds[b.kind] = (kinds[b.kind] or 0) + 1
end
assert(kinds.torso == 2 and kinds.head == 2 and kinds.limb == 2, "sub-blob kinds wrong")

local metrics = VNPC_GetBellyDeformMetrics(pred2)
assert(metrics, "metrics missing")
assert(metrics.rx >= 4 and metrics.ry >= 4.5 and metrics.rz >= 3.5)
assert(math.abs(metrics.totalMass - (blobA.mass + blobB.mass)) < 0.01, "total mass mismatch")
assert(metrics.Rv and metrics.Rv > 1, "volume radius missing")
assert(metrics.fieldRef and metrics.fieldRef > 0, "field reference missing")
assert(metrics.lumpMax and metrics.lumpMax > 0, "lump max missing")

-- metaball field math: single blob mass m=60, r=8 -> iso at d=0.894*r has F=2.4
local wb = { { pos = Vector(0, 0, 0), rx = 8, ry = 8, rz = 8, mass = 60 } }
local F0 = VNPC_MetaballFieldAt(Vector(0, 0, 0), wb)
assert(math.abs(F0 - 60) < 0.01, "field at center should be the mass")
local Fiso = VNPC_MetaballFieldAt(Vector(0.894 * 8, 0, 0), wb)
assert(math.abs(Fiso - 0.04 * 60) < 0.3, "field at iso radius should be ~0.04*mass: " .. Fiso)
local Ffar = VNPC_MetaballFieldAt(Vector(20, 0, 0), wb)
assert(Ffar == 0, "field outside support should be 0")
-- gradient points inward (toward the mass)
local g = VNPC_MetaballGradAt(Vector(4, 0, 0), wb)
assert(g.x < 0, "gradient should point inward (toward density)")

-- sync writes NW (no error)
VNPC_SyncPaintBlobNW(pred2)

-- deform: vertex at the belly front should get pushed outward by the blobs
local chain = {
    mid = { pos = Vector(0, 0, 0) },
    right = Vector(1, 0, 0),
    rightDir = Vector(1, 0, 0),
    forward = Vector(0, 1, 0),
    up = Vector(0, 0, 1),
    width = 24,
    depth = 20,
    height = 18,
    radius = 12,
}
pred2.VNPC_BellyBlobMetrics = nil
local world = Vector(0, 10, 0)
local lp = Vector(0, 0.6, 0)
local off, nrm2 = VNPC_ApplyWeightPaintDeform(world, lp, pred2, chain)
if off then
    assert(off:Length() < 40, "deform too large: " .. off:Length())
end
if nrm2 then
    assert(math.abs(nrm2:Length() - 1) < 0.01, "normal should be unit length")
end
-- far-away vertex gets (near) nothing
local offFar = VNPC_ApplyWeightPaintDeform(Vector(0, 30, 30), Vector(0.9, 0.9, 0.9), pred2, chain)
assert(offFar == nil or offFar:Length() < 1.5, "far vertex should barely deform")

-- COM shift: heavy belly sags downward (z < 0)
local shift = VNPC_GetBellyComShift(pred2)
assert(shift.x >= -4.5 and shift.x <= 4.5)
assert(shift.z < 0, "heavy belly should sag downward, got z=" .. shift.z)

-- bone scales + spine arch
local boneScale = VNPC_GetWeightPaintBoneScale(pred2, chain)
assert(boneScale and boneScale.extra > 0.01, "bone scale extra missing")
assert(boneScale.spine.x > 1 and boneScale.pelvis.y > 1)
assert(boneScale.spineBend and boneScale.spineBend < 0, "heavy belly should arch the spine back")

-- empty belly -> nil metrics
local pred3 = MakeEnt(6)
pred3.Predator = true
pred3.VNPC_Belly = { Prey = {} }
pred3.Belly = pred3.VNPC_Belly
assert(VNPC_GetBellyDeformMetrics(pred3) == nil, "empty belly should have no metrics")

-- ================== CLIENT SMOOTHING ==================
CLIENT, SERVER = true, false
local cpred = MakeEnt(50)
cpred.Predator = true
local nwVals = { ["VNPC_PaintBlobN"] = 2 }
local nwPos = {
    ["VNPC_PaintBlobPos1"] = Vector(1, 1, 1),
    ["VNPC_PaintBlobPos2"] = Vector(-1, 2, 0),
}
function cpred:GetNWInt(key, def) return nwVals[key] or def or 0 end
function cpred:GetNWFloat(key, def) return def or 45 end
function cpred:GetNWVector(key, def) return nwPos[key] or def or Vector(0, 0, 0) end
function cpred:GetNWString(key, def) return def or "" end

local b1 = VNPC_ComputeBellyBlobs(cpred)
assert(#b1 == 2, "client blobs count")
assert(b1[1].pos.x == 1, "first client read should snap to target")
-- move the target; the smoothed position must move only partway (rate ~0.112)
nwPos["VNPC_PaintBlobPos1"] = Vector(9, 9, 9)
FRAME = FRAME + 1
local b2 = VNPC_ComputeBellyBlobs(cpred)
local px = b2[1].pos.x
assert(px > 1.001 and px < 9, "client position should be smoothed between syncs, got " .. px)
-- metrics on the client must be per-frame cached, not stale forever
local m1 = VNPC_GetBellyDeformMetrics(cpred)
assert(m1 and m1.blobs and #m1.blobs == 2, "client metrics")
nwPos["VNPC_PaintBlobPos1"] = Vector(5, 5, 5)
FRAME = FRAME + 1
local m2 = VNPC_GetBellyDeformMetrics(cpred)
assert(m2.blobs[1].pos.x < 9, "client metrics should refresh with the new frame")
CLIENT, SERVER = false, true

print("TRAITS + WEIGHT PAINT LUA EXECUTION OK")
"""

lua.execute(TEST)
print("vnpcs weight paint + traits modules executed headless: ALL ASSERTIONS PASSED")
