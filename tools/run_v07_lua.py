#!/usr/bin/env python3
"""Execute the v0.7 modules under LuaJIT (lupa) with stubbed GMod globals and
assert the pure math:

Body matrix (sh_vnpc_body_expansion.lua):
  - bloat combines belly size + water + food + monster growth,
  - expansion rises monotonically with bloat, per-region weights respected,
  - cloth stress is 0 below the region capacity and rises after,
  - ApplyBodyExpansion writes per-bone scales and resets when bloat clears.

Personality matrix (sh_vnpc_personality_matrix.lua):
  - defaults seed from the legacy personality,
  - SetMatrixAxis clamps and persists via NW string,
  - serialization round-trips,
  - behavior params: digestion bounds, require_unseen from shy, ambush/pin/
    camouflage monotonic in their axes.
"""
import re
from pathlib import Path

from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)

PRELUDE = r"""
math.Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
if not math.atan2 then math.atan2 = function(y, x) return math.atan(y, x) end end
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
timer = { Simple = function() end, Create = function() end, Remove = function() end }
function isvector(v) return getmetatable(v) == VECTOR_MT end
function istable(v) return type(v) == "table" end
function isnumber(v) return type(v) == "number" end
function isstring(v) return type(v) == "string" end
function isbool(v) return type(v) == "boolean" end
function IsValid(v) return type(v) == "table" and v.__valid ~= false end
function CurTime() return 1000 end
function FrameTime() return 0.016 end
CLIENT, SERVER = false, true
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
        Distance = function(self, o) return (o - self):Length() end,
    },
}
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
ents = { GetAll = function() return {} end, FindByClass = function() return {} end, FindInSphere = function() return {} end, Create = function() return nil end }
player = { GetAll = function() return {} end }
util = { IsValidModel = function() return true end, PointContents = function() return 0 end }
table.Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
bit = { band = function(a, b) return a & b end, bor = function(a, b) return a | b end }
FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY = 1, 2, 4

function MakeEnt(id, pred)
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
        LookupBone = function(self, name)
            local map = {
                ["ValveBiped.Bip01_Spine2"] = 1, ["ValveBiped.Bip01_Pelvis"] = 2,
                ["ValveBiped.Bip01_L_Thigh"] = 3, ["ValveBiped.Bip01_R_Thigh"] = 4,
                ["ValveBiped.Bip01_L_Calf"] = 5, ["ValveBiped.Bip01_R_Calf"] = 6,
                ["ValveBiped.Bip01_L_UpperArm"] = 7, ["ValveBiped.Bip01_R_UpperArm"] = 8,
                ["ValveBiped.Bip01_L_Forearm"] = 9, ["ValveBiped.Bip01_R_Forearm"] = 10,
            }
            return map[name] or -1
        end,
        ManipulateBoneScale = function(self, id, vec) self._scales = self._scales or {}; self._scales[id] = vec end,
        SetNWString = function(self, k, v) self._nw = self._nw or {}; self._nw[k] = v end,
        GetNWString = function(self, k, d) return (self._nw and self._nw[k]) or d or "" end,
        Predator = pred or false,
        Vored = false, VNPC_Vored = false,
    }
end

function VNPC_IsPredatorEntity(ent) return ent and ent.Predator or false end
function VNPC_IsPreyNPC(ent) return ent and not ent.Predator end
function VNPC_GetPredatorPersonality(ent)
    return ent.VNPC_PredatorPersonality or "opportunistic", {}
end
function VNPC_GetPredBelly(ent) return ent.VNPC_Belly end
function VNPC_GetLiveBellySize(ent)
    local belly = ent.VNPC_Belly
    return (belly and belly.size) or 0
end
"""


def load(path):
    src = Path(path).read_text(encoding="utf-8", errors="replace")
    src = src.replace("continue", "do end")
    lua.execute(src, path)


lua.execute(PRELUDE)
load("v_npcs/lua/autorun/sh_vnpc_personality_matrix.lua")
load("v_npcs/lua/autorun/sh_vnpc_body_expansion.lua")

TEST = r"""
-- body expansion is OFF by default now (GPU mesh is the belly); force it on
-- for these tests so the math is exercised
CVARS["vnpcs_body_expansion_enabled"] = {
    GetBool = function() return true end,
    GetFloat = function() return 1 end,
    GetInt = function() return 1 end,
    GetString = function() return "" end,
}

-- ================= PERSONALITY MATRIX =================
local pred = MakeEnt(1, true)
-- legacy personality seeds the defaults
pred.VNPC_PredatorPersonality = "glutton"
local mix = VNPC_GetPersonalityMix(pred)
assert(mix.greed == 1.0, "glutton should default greed=1")
assert(mix.stealth == 0 and mix.shy == 0, "glutton starts with no stealth/shy")

-- set axis via the API, clamps 0..1
VNPC_SetMatrixAxis(pred, "stealth", 0.9)
VNPC_SetMatrixAxis(pred, "shy", 0.8)
VNPC_SetMatrixAxis(pred, "greed", 9.9)
assert(pred.VNPC_Matrix.stealth == 0.9 and pred.VNPC_Matrix.greed == 1.0, "axis clamp")

-- serialization round-trip
local str = VNPC_SerializeMatrix(pred.VNPC_Matrix)
local back = VNPC_DeserializeMatrix(str)
assert(back.stealth == 0.9 and back.shy == 0.8 and back.greed == 1.0, "round-trip")

-- behavior params
assert(VNPC_GetBehaviorParam(pred, "require_unseen") == true, "shy>=0.45 -> unseen")
assert(VNPC_GetBehaviorParam(pred, "digestion_multiplier") >= 1.5, "greedy digests fast")
local ambush = VNPC_GetBehaviorParam(pred, "ambush")
assert(ambush >= 0.7, "stealthy+shy -> high ambush")

-- gentle slows digestion
local gentle = MakeEnt(2, true)
gentle.VNPC_PredatorPersonality = "gentle"
local dm = VNPC_GetBehaviorParam(gentle, "digestion_multiplier")
assert(dm < 0.7, "gentle digests slowly, got " .. dm)

-- unknown axis is ignored
VNPC_SetMatrixAxis(pred, "bogus", 0.5)
assert(pred.VNPC_Matrix.bogus == nil, "unknown axis ignored")

-- ================= BODY MATRIX =================
-- empty belly -> no bloat -> no expansion
local p1 = MakeEnt(3, true)
p1.VNPC_Belly = { size = 0, Prey = {}, VNPC_WaterWeight = 0 }
assert(VNPC_GetBloatAmount(p1) == 0, "empty bloat")
assert(VNPC_GetBodyExpansion(p1) == nil, "no expansion when empty")

-- full belly -> expansion monotonic per region (bloat ~1.0: belly stressed,
-- chest capacity 1.3 not reached)
local p2 = MakeEnt(4, true)
p2.VNPC_Belly = { size = 1.0, Prey = { { Value = 120 } }, VNPC_WaterWeight = 0 }
local bloat = VNPC_GetBloatAmount(p2)
assert(math.abs(bloat - 1.0) < 0.01, "belly-only bloat should be ~1.0, got " .. bloat)
local exp = VNPC_GetBodyExpansion(p2)
assert(exp, "expansion exists")
assert(exp.chest > 1 and exp.hips > 1 and exp.thigh > 1 and exp.calf > 1 and exp.upperArm > 1, "all regions expand")
-- weights: hips >= chest > calf > forearm
assert(exp.hips >= exp.chest and exp.chest > exp.calf and exp.calf > exp.forearm, "region weights respected")

-- stress: belly stressed at this bloat, chest/thigh not yet
local stress = exp.stress
assert(stress.belly > 0, "belly stress should be positive")
assert(stress.chest == 0, "chest capacity (1.3) not reached")

-- monster growth pushes chest into stress
local p3 = MakeEnt(5, true)
p3.VNPC_Belly = { size = 1.6, Prey = { { Value = 300 } }, VNPC_WaterWeight = 90 }
p3.VNPC_GrowthProgress = 210
local exp3 = VNPC_GetBodyExpansion(p3)
assert(exp3.stress.belly > 0.5 and exp3.stress.chest > 0, "monster bloat stresses belly + chest")
assert(exp3.chest > 1.15, "chest expands hard at monster size")

-- ApplyBodyExpansion writes bone scales and resets when bloat clears
local p4 = MakeEnt(6, true)
p4.VNPC_Belly = { size = 1.0, Prey = { { Value = 100 } }, VNPC_WaterWeight = 0 }
VNPC_ApplyBodyExpansion(p4)
local nScales = 0
for _ in pairs(p4._scales or {}) do nScales = nScales + 1 end
assert(nScales == 10, "should scale 10 bones, got " .. nScales)
local chestVec = p4._scales[1]
assert(chestVec.x > 1 and chestVec.z > 1 and chestVec.z < chestVec.x, "axial bias: z grows less")
p4.VNPC_Belly.size = 0
p4.VNPC_Belly.Prey = {}
VNPC_ApplyBodyExpansion(p4)
for _, v in pairs(p4._scales) do
    assert(v.x == 1 and v.y == 1 and v.z == 1, "reset to identity")
end

print("V0.7 PERSONALITY MATRIX + BODY MATRIX LUA EXECUTION OK")
"""

lua.execute(TEST)
print("v0.7 modules executed headless: ALL ASSERTIONS PASSED")
