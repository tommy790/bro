-- V-NPCs Layered Soft-Body Cloth Tear (cl_vnpc_cloth_tear.lua)
-- v0.7: layered material interaction. The character's expanding skin layer is
-- the GPU belly mesh; ON TOP of it this module draws a fabric shell built
-- from the NPC's own textures. A per-region STRESS MAP (sh_vnpc_body_expansion.lua)
-- tracks tension between the expanding skin and the clothing:
--
--   * stress < 0.30 : clothing fits, no shell drawn (belly reads as clothed)
--   * stress 0.30+  : the fabric shell appears, hugging the belly and chest
--   * stress 0.55+  : panels begin to separate along vertical seam lines,
--                     showing the skin belly through the gaps
--   * stress 0.80+  : panels peel open wide with jagged torn edges, and the
--                     shell slides down to expose the bare top of the belly
--
-- Engine note: GMod has no runtime cloth sim or per-material vertex tearing,
-- so this is a procedural approximation - a panelized mesh whose seams open
-- along the stress lines, drawn with the entity's own clothing material.

CreateConVar("vnpcs_cloth_tear_enabled", "1", {FCVAR_ARCHIVE}, "Draw the layered fabric shell that tears open along stress lines at high bloat")
CreateConVar("vnpcs_cloth_tear_stress", "0.30", {FCVAR_ARCHIVE}, "Stress threshold where the straining fabric shell becomes visible")
CreateConVar("vnpcs_cloth_tear_rip", "0.55", {FCVAR_ARCHIVE}, "Stress threshold where the fabric starts ripping open along seams")

if not CLIENT then return end

-- Panelized unit sphere: 3 lat bands x 6 lon segments = 18 fabric panels.
-- Each panel is stored as a strip of grid verts so it can be displaced as one
-- piece (seam opening) plus jagged per-vertex tear noise.
local PANEL_LAT, PANEL_LON = 3, 6
local SHELL_VERTS, SHELL_PANELS = {}, {}

local function buildShellGeometry()
    local LAT, LON = PANEL_LAT * 3, PANEL_LON * 4 -- grid density inside panels
    SHELL_VERTS = {}
    SHELL_PANELS = {}
    for i = 0, LAT do
        local phi = (i / LAT) * math.pi
        local sp, cp = math.sin(phi), math.cos(phi)
        for j = 0, LON - 1 do
            local th = (j / LON) * math.pi * 2
            local x, y, z = sp * math.cos(th), sp * math.sin(th), cp
            local down = math.Clamp((-z + 0.15) * 0.55, 0, 1)
            table.insert(SHELL_VERTS, {
                pos = Vector(x * (0.96 + down * 0.18), y * (1.02 + down * 0.14), z * 0.9 - 0.06),
                nrm = Vector(x, y, z),
                u = j / LON,
                v = i / LAT
            })
        end
    end
    local function idx(i, j)
        return i * LON + (j % LON) + 1
    end
    -- build panels: each covers latBand x lonSeg cells of the grid
    local cellsPerBand = math.floor(LAT / PANEL_LAT)
    local cellsPerSeg = math.floor(LON / PANEL_LON)
    for band = 0, PANEL_LAT - 1 do
        for seg = 0, PANEL_LON - 1 do
            local tris = {}
            local i0 = band * cellsPerBand
            local i1 = math.min(LAT, i0 + cellsPerBand)
            local j0 = seg * cellsPerSeg
            local j1 = j0 + cellsPerSeg
            for i = i0, i1 - 1 do
                for j = j0, j1 - 1 do
                    local a, b, c, d = idx(i, j), idx(i, j + 1), idx(i + 1, j), idx(i + 1, j + 1)
                    table.insert(tris, { a, b, c })
                    table.insert(tris, { b, d, c })
                end
            end
            table.insert(SHELL_PANELS, {
                band = band,
                seg = seg,
                tris = tris,
                seed = band * 7 + seg * 13
            })
        end
    end
end

local function shellMaterial(ent)
    if IsValid(ent) and ent.GetMaterials then
        local mats = ent:GetMaterials()
        if istable(mats) then
            for _, name in ipairs(mats) do
                if isstring(name) and name ~= "" and not name:find("eyeball") and not name:find("eye") and not name:find("skin") then
                    local mat = Material(name)
                    if mat and not mat:IsError() then
                        return mat
                    end
                end
            end
        end
    end
    return Material("vnpcs/gpu_belly")
end

local function hash01(a)
    local n = math.sin(a * 12.9898) * 43758.5453
    return n - math.floor(n)
end

hook.Add("PostDrawOpaqueRenderables", "VNPC_ClothTear_DrawShell", function()
    local enabled = GetConVar("vnpcs_cloth_tear_enabled")
    if enabled and not enabled:GetBool() then return end
    if not SHELL_VERTS then buildShellGeometry() end

    local meshOn = GetConVar("vnpcs_gpu_belly_mesh")
    if meshOn and not meshOn:GetBool() then return end

    local stressCv = GetConVar("vnpcs_cloth_tear_stress")
    local ripCv = GetConVar("vnpcs_cloth_tear_rip")
    local showAt = stressCv and stressCv:GetFloat() or 0.30
    local ripAt = ripCv and ripCv:GetFloat() or 0.55
    local now = CurTime()

    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if not IsValid(ent) or ent:IsDormant() or (ent.GetNoDraw and ent:GetNoDraw()) then continue end
        if not (ent.Predator or ent.VNPC_FemaleModelVore or ent.IsDrGNextbot or ent.VNPC_Belly or ent.Belly) then continue end

        local chain = ent.VNPC_VirtualBellyBones
        if not chain or not chain.mid or not chain.mid.pos then continue end
        if (chain.size or 0) < 0.05 then continue end

        local bellyStress = 0
        if VNPC_GetClothStress then
            bellyStress = VNPC_GetClothStress(ent, "belly")
        end
        if bellyStress < showAt then continue end

        -- how far the fabric has ripped: 0 = intact, 1 = fully peeled open
        local rip = math.Clamp((bellyStress - ripAt) / (1.0 - ripAt + 0.15), 0, 1)
        local gap = rip * 4.5 + (1 - rip) * 0.35
        local peel = rip * 0.9

        local mat = shellMaterial(ent)
        render.SetMaterial(mat)

        local mid = chain.mid
        local rx = chain.width * 0.5 * 1.07
        local ry = chain.depth * 0.5 * 1.09
        local rz = chain.height * 0.5 * 1.05
        local right, fwd, up = chain.right, chain.forward, chain.up

        for _, panel in ipairs(SHELL_PANELS) do
            -- deterministic per-panel tear noise, slow drift
            local wob = math.sin(now * 0.7 + panel.seed) * 0.35 * rip
            local seamOpen = gap * (0.6 + hash01(panel.seed) * 0.8) + wob

            mesh.Begin(MATERIAL_TRIANGLES, #panel.tris)
            for t = 1, #panel.tris do
                local tri = panel.tris[t]
                for k = 1, 3 do
                    local v = SHELL_VERTS[tri[k]]
                    local lp = v.pos
                    local world = mid.pos + right * (lp.x * rx) + fwd * (lp.y * ry) + up * (lp.z * rz)

                    -- seam opening: push the panel's edge verts outward along
                    -- their own normal; panels peel down as rip increases
                    local edge = math.max(0, 1 - v.u * 2 - 0.35) -- left-ish edge factor
                    edge = math.max(edge, math.max(0, v.u * 2 - 1 - 0.35))
                    -- band edges (top/bottom of panel)
                    local vEdge = math.max(0, 1 - v.v * 2 - 0.25)
                    vEdge = math.max(vEdge, math.max(0, v.v * 2 - 1 - 0.25))
                    edge = math.max(edge, vEdge * 0.7)

                    local jag = (hash01(panel.seed + t) - 0.5) * 1.6 * rip
                    local openAmt = seamOpen * edge + jag
                    if openAmt > 0 then
                        world = world + v.nrm * openAmt
                    end
                    -- peel: whole panel slides down-forward, exposing the top
                    world = world - up * (peel * 3.2 * (1 - v.v))
                    world = world + fwd * (peel * 1.6 * (1 - v.v))

                    -- torn edge darkening
                    local edgeDark = math.Clamp(openAmt * 0.18, 0, 0.6)
                    local c = 255 * (1 - edgeDark * 0.4)
                    mesh.Position(world)
                    mesh.Normal(v.nrm)
                    mesh.TexCoord(0, v.u, v.v)
                    mesh.Color(c, c * 0.97, c * 0.94, 255)
                    mesh.AdvanceVertex()
                end
            end
            mesh.End()
        end
    end
end)
