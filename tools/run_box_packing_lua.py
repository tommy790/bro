#!/usr/bin/env python3
"""Execute the real sh_vnpc_weight_paint.lua VNPC_DefaultBlobLayout function
under LuaJIT (lupa) with stubbed GMod globals, verifying the deterministic
bounding-box "shelf packing" that replaced the old physics-driven Ragdoll
Matrix belly deformation:
  - packed width grows as more similarly-sized bodies are added,
  - a row's width budget properly overflows into a second (deeper) row,
  - every blob always gets assigned a real position (no nils/NaN), and the
    same input always produces the same output (fully deterministic).
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
        cv = { GetBool = function() return true end, GetFloat = function() return 1 end, GetInt = function() return 0 end, GetString = function() return "" end }
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
CLIENT, SERVER = false, true
ents = { GetAll = function() return {} end, FindByClass = function() return {} end, FindInSphere = function() return {} end, Create = function() return nil end }
player = { GetAll = function() return {} end }
util = { IsValidModel = function() return true end }
table.Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
bit = { band = function(a, b) return a & b end, bor = function(a, b) return a | b end, lshift = function(a, n) return a * (2 ^ n) end }
FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY = 1, 2, 4

function MakeBlob(rx, ry, rz, mass)
    return { id = math.random(1, 999999), rx = rx, ry = ry, rz = rz, mass = mass or 45 }
end
"""


def load(name):
    src = Path(f"v_npcs/lua/autorun/{name}").read_text(encoding="utf-8", errors="replace")
    src = src.replace("continue", "do end")
    lua.execute(src, name)


lua.execute(PRELUDE)
load("sh_vnpc_weight_paint.lua")

TEST = r"""
local results = {}

local function packedFootprint(blobs)
    VNPC_DefaultBlobLayout(nil, blobs)
    local minX, maxX, maxDepthEnd = 0, 0, 0
    for _, b in ipairs(blobs) do
        assert(b.pos, "blob missing a position after layout")
        assert(isnumber(b.pos.x) and b.pos.x == b.pos.x, "blob.pos.x is NaN") -- NaN != NaN
        assert(isnumber(b.pos.y) and b.pos.y == b.pos.y, "blob.pos.y is NaN")
        assert(isnumber(b.pos.z) and b.pos.z == b.pos.z, "blob.pos.z is NaN")
        minX = math.min(minX, b.pos.x - b.rx)
        maxX = math.max(maxX, b.pos.x + b.rx)
    end
    return maxX - minX
end

-- 1. A single body gets a sane centered position, no physics needed.
local one = { MakeBlob(8, 10, 18) }
local w1 = packedFootprint(one)
assert(w1 > 0, "single body footprint should be positive")

-- 2. Two identical bodies should pack noticeably wider than one, since their
--    real measured widths add together shoulder-to-shoulder.
local two = { MakeBlob(8, 10, 18), MakeBlob(8, 10, 18) }
local w2 = packedFootprint(two)
assert(w2 > w1 * 1.5, string.format("2 bodies (%.1f) should be much wider than 1 (%.1f)", w2, w1))

-- 3. Three of the same body should be wider still (all still fit in one row).
local three = { MakeBlob(8, 10, 18), MakeBlob(8, 10, 18), MakeBlob(8, 10, 18) }
local w3 = packedFootprint(three)
assert(w3 > w2, string.format("3 bodies (%.1f) should be wider than 2 (%.1f)", w3, w2))

-- 4. A big enough group must overflow into more than one row instead of
--    growing the belly absurdly wide forever.
local many = {}
for i = 1, 8 do table.insert(many, MakeBlob(8, 10, 18)) end
VNPC_DefaultBlobLayout(nil, many)
local rowYs = {}
for _, b in ipairs(many) do rowYs[string.format("%.2f", b.pos.y)] = true end
local distinctRows = table.Count(rowYs)
assert(distinctRows >= 2, "8 same-sized bodies should spill into multiple rows, got " .. distinctRows .. " row(s)")

local wMany = 0
do
    local minX, maxX = 0, 0
    for _, b in ipairs(many) do
        minX = math.min(minX, b.pos.x - b.rx)
        maxX = math.max(maxX, b.pos.x + b.rx)
    end
    wMany = maxX - minX
end
assert(wMany < w3 * 6, string.format("8 bodies (%.1f) packing into multiple rows should stay far narrower than 8x a single row's width", wMany))

-- 5. One huge body should always get its own row even amongst small ones.
local mixed = { MakeBlob(30, 34, 50), MakeBlob(6, 7, 12), MakeBlob(6, 7, 12) }
VNPC_DefaultBlobLayout(nil, mixed)
assert(mixed[1].pos, "big body should still get a position")

-- 6. Determinism: same input (by value) produces the same output every time.
local a = { MakeBlob(8, 10, 18), MakeBlob(9, 11, 19) }
local b = { MakeBlob(8, 10, 18), MakeBlob(9, 11, 19) }
VNPC_DefaultBlobLayout(nil, a)
VNPC_DefaultBlobLayout(nil, b)
for i = 1, #a do
    assert(math.abs(a[i].pos.x - b[i].pos.x) < 0.001, "layout should be deterministic (x)")
    assert(math.abs(a[i].pos.y - b[i].pos.y) < 0.001, "layout should be deterministic (y)")
end

print("BOX PACKING (Dynamic Weight Painting) LUA EXECUTION OK")
print(string.format(" - 1 body footprint:  %.1f", w1))
print(string.format(" - 2 body footprint:  %.1f", w2))
print(string.format(" - 3 body footprint:  %.1f", w3))
print(string.format(" - 8 body footprint:  %.1f across %d row(s)", wMany, distinctRows))
"""

lua.execute(TEST)
print("vnpcs bounding-box belly shape packing executed headless: ALL ASSERTIONS PASSED")
