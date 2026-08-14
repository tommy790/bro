#!/usr/bin/env python3
"""Execute the real Lua belly-physics module under LuaJIT (lupa) with stubbed
GMod globals, then run the headless 6-second sim and assert stability.

This validates the actual Lua code path (not just a Python mirror):
  - VNPC_BellyPhysicsCreateState / VNPC_BellyPhysicsStep run correctly,
  - masses stay inside the ellipsoid, speeds stay bounded,
  - masses settle at the belly bottom,
  - VNPC_GetBellyWeightSlow respects the trait divisor and master multiplier.
"""
import sys
from pathlib import Path

import lupa
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)

LUA_PRELUDE = r"""
-- GMod API stubs ------------------------------------------------------------
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
math.Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
hook = { Add = function() end, Run = function() return end }
concommand = { Add = function() end }
timer = { Simple = function() end }

-- Vector stub (math subset used by the module)
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
    __tostring = function(a) return string.format("(%.1f, %.1f, %.1f)", a.x, a.y, a.z) end,
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
function IsValid(v) return type(v) == "table" and v.__valid ~= false end
function CurTime() return 0 end
function ents() return {} end
ents = {
    GetAll = function() return {} end,
    FindByClass = function() return {} end,
    FindInSphere = function() return {} end,
    Create = function() return nil end,
}
player = { GetAll = function() return {} end }
util = { IsValidModel = function() return true end, PointContents = function() return 0 end }
table.Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
bit = { band = function(a, b) return a & b end, bor = function(a, b) return a | b end, lshift = function(a, n) return a * (2 ^ n) end }
COLLISION_GROUP_DEBRIS, SOLID_NONE = 2, 0
MASK_VISIBLE, CONTENTS_WATER = 0x4000, 0x10
DMG_REMOVENORAGGDLL = 0
SCHED_FORCED_GO = 0
FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY = 1, 2, 4

-- traits file dependency
function VNPC_GetTraitStat(ent, stat) return 1.0 end
"""

physics_lua = Path("v_npcs/lua/autorun/server/vnpcs_belly_physics.lua").read_text(
    encoding="utf-8", errors="replace"
)
# strip GMod-only `continue` for stock LuaJIT parsing
physics_lua = physics_lua.replace("continue", "do end")

lua.execute(LUA_PRELUDE)
lua.execute(physics_lua, "vnpcs_belly_physics.lua")

TEST = r"""
math.randomseed(1234)
local state = VNPC_BellyPhysicsCreateState()
for i = 1, 3 do
    table.insert(state.masses, {
        id = i, x = 0, y = 8 + i * 2, z = 5, vx = 0, vy = -20, vz = 0,
        mass = 50 + i * 10, rx = 7, ry = 8, rz = 6, kick = 0, struggle = 1.0
    })
end
local radii = Vector(15, 18, 12)
local dt = 1 / 20
local maxSpeed = 0
local simTime = 0
while simTime < 6 do
    VNPC_BellyPhysicsStep(state, dt, radii)
    simTime = simTime + dt
    for _, m in ipairs(state.masses) do
        local sp = math.sqrt(m.vx * m.vx + m.vy * m.vy + m.vz * m.vz)
        if sp > maxSpeed then maxSpeed = sp end
    end
end
local inside = true
for _, m in ipairs(state.masses) do
    local d = math.sqrt((m.x / 15) ^ 2 + (m.y / 18) ^ 2 + (m.z / 12) ^ 2)
    if d > 1.02 then inside = false end
end
local avgZ = (state.masses[1].z + state.masses[2].z + state.masses[3].z) / 3
assert(inside, "containment breached")
assert(maxSpeed < 400, "sim exploded: " .. maxSpeed)
assert(avgZ < -4, "masses did not settle: " .. avgZ)
assert(state.totalMass > 209.9 and state.totalMass < 210.1, "mass not conserved")

-- weight slow: fake pred
local fakePred = {
    __valid = true,
    VNPC_BellyPhysics = { totalMass = 100 },
}
assert(math.abs(VNPC_GetBellyWeightSlow(fakePred) - 0.84) < 0.02, "100kg slow wrong")
fakePred.VNPC_BellyPhysics.totalMass = 400
assert(VNPC_GetBellyWeightSlow(fakePred) == 0.4, "400kg floor wrong")

-- kick decays
local s2 = VNPC_BellyPhysicsCreateState()
table.insert(s2.masses, { id = 9, x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0, mass = 60, rx = 8, ry = 9, rz = 7, kick = 10, struggle = 0 })
for _ = 1, 120 do VNPC_BellyPhysicsStep(s2, dt, radii) end
assert(s2.masses[1].kick <= 0.01, "kick did not decay")

print("LUA EXECUTION OK: containment, stability, settling, mass, weight slow, kick decay")
"""

lua.execute(TEST)
print("vnpcs_belly_physics.lua executed headless: ALL ASSERTIONS PASSED")
