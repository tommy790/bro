-- V-NPCs Camp Construction Engine (vnpcs_camp_construction.lua)
-- Shared placement, procedural perimeter layouts, and walkable roofed huts.
-- Does not modify sounds or the belly model.

VNPC_CAMP_WALL_MODELS = {
    "models/props_wasteland/wood_fence01a.mdl",
    "models/props_c17/fence01a.mdl"
}

VNPC_CAMP_FENCE_MODEL = "models/props_wasteland/wood_fence01a.mdl"
VNPC_CAMP_FENCE_ALT = "models/props_c17/fence01a.mdl"
VNPC_CAMP_ROOF_MODEL = "models/props_junk/wood_pallet001a.mdl"
VNPC_CAMP_BOARD_MODEL = "models/props_debris/wood_board04a.mdl"
VNPC_CAMP_FENCE_LENGTH = 120
VNPC_CAMP_HUT_HALF = 52
VNPC_CAMP_HUT_ROOF_CLEARANCE = 84
VNPC_CAMP_DOORWAY_WIDTH = 78

VNPC_ALL_TOWN_ROLES = { "builder", "sentry", "forager", "cook", "mate", "leader" }

function VNPC_PickValidCampModel(preferred, fallback)
    if preferred and util.IsValidModel(preferred) then return preferred end
    if fallback and util.IsValidModel(fallback) then return fallback end
    if util.IsValidModel(VNPC_CAMP_FENCE_MODEL) then return VNPC_CAMP_FENCE_MODEL end
    return VNPC_CAMP_FENCE_ALT
end

function VNPC_CampHash01(seed, salt)
    local x = math.abs(math.sin((tonumber(seed) or 1) * 12.9898 + (tonumber(salt) or 0) * 78.233) * 43758.5453)
    return x - math.floor(x)
end

function VNPC_CampHashInt(seed, salt, minV, maxV)
    if maxV < minV then minV, maxV = maxV, minV end
    return minV + math.floor(VNPC_CampHash01(seed, salt) * (maxV - minV + 1))
end

function VNPC_AssignFounderAllRoles(ent)
    if not IsValid(ent) then return end
    ent.VNPC_IsCampFounder = true
    ent.VNPC_IsCampLeader = true
    ent.VNPC_TownRole = "founder"
    ent.VNPC_TownRoles = ent.VNPC_TownRoles or {}
    for _, role in ipairs(VNPC_ALL_TOWN_ROLES) do
        ent.VNPC_TownRoles[role] = true
    end
    if not ent.VNPC_CampRole or ent.VNPC_CampRole == "stayer" then
        ent.VNPC_CampRole = "founder"
    end
end

function VNPC_HasTownRole(ent, role)
    if not IsValid(ent) or not role then return false end
    if ent.VNPC_IsCampFounder or ent.VNPC_TownRole == "founder" then return true end
    if istable(ent.VNPC_TownRoles) and ent.VNPC_TownRoles[role] then return true end
    if ent.VNPC_TownRole == role then return true end
    if role == "leader" and ent.VNPC_IsCampLeader then return true end
    if role == "forager" and (ent.VNPC_CampRole == "forager" or ent.VNPC_CampRole == "founder") then return true end
    return false
end

function VNPC_GetHutWorldPos(hut)
    if not hut then return nil end
    if isvector(hut) then return hut end
    if istable(hut) then
        if hut.interiorPos then return hut.interiorPos end
        if hut.pos then return hut.pos end
        if hut.props then
            for _, p in ipairs(hut.props) do
                if IsValid(p) then return p:GetPos() end
            end
        end
        return nil
    end
    if IsValid(hut) and hut.GetPos then
        return hut:GetPos()
    end
    return nil
end

function VNPC_GetHutInteriorPos(hut)
    local pos = VNPC_GetHutWorldPos(hut)
    if not pos then return nil end
    local ang = Angle(0, 0, 0)
    if istable(hut) and hut.ang then
        ang = hut.ang
    end
    return pos + ang:Forward() * 10 + Vector(0, 0, 8)
end

function VNPC_IsHutAlive(hut)
    if not hut then return false end
    if istable(hut) then
        if hut.props then
            for _, p in ipairs(hut.props) do
                if IsValid(p) then return true end
            end
            return false
        end
        return hut.pos ~= nil
    end
    return IsValid(hut)
end

function VNPC_RemoveHutStructure(hut)
    if not hut then return end
    if istable(hut) then
        if hut.props then
            for _, p in ipairs(hut.props) do
                if IsValid(p) then p:Remove() end
            end
        end
        if IsValid(hut.tableProp) then hut.tableProp:Remove() end
        if hut.walls then
            for _, w in ipairs(hut.walls) do
                if IsValid(w) then w:Remove() end
            end
        end
        return
    end
    if IsValid(hut) then hut:Remove() end
end

function VNPC_SnapCampPosToGround(pos, maxDrop)
    if not pos then return nil, nil end
    local tr = util.TraceLine({
        start = pos + Vector(0, 0, 64),
        endpos = pos - Vector(0, 0, maxDrop or 260),
        mask = MASK_SOLID_BRUSHONLY
    })
    if not tr.Hit or tr.StartSolid or tr.HitNormal.z < 0.62 then
        return nil, nil
    end
    return tr.HitPos, tr.HitNormal
end

function VNPC_IsWorldSpotBlocked(pos, hullMins, hullMaxs)
    if not pos then return true end
    local tr = util.TraceHull({
        start = pos + Vector(0, 0, 4),
        endpos = pos + Vector(0, 0, 4),
        mins = hullMins or Vector(-10, -10, 0),
        maxs = hullMaxs or Vector(10, 10, 72),
        mask = MASK_SOLID_BRUSHONLY
    })
    return tr.StartSolid == true
end

function VNPC_IsCampStructureProp(ent)
    if not IsValid(ent) then return false end
    return ent.VNPC_IsPreyCampWall
        or ent.VNPC_IsPreyCampHutPiece
        or ent.VNPC_IsCourtyardDefense
        or ent.VNPC_IsPreyCampFire
        or ent.VNPC_IsPredatorCampFire
        or ent.VNPC_IsPredatorCampBarricade
        or ent.VNPC_IsPredatorTent
        or ent.VNPC_IsPredatorCampWater
        or ent.VNPC_IsLeaderHutWall
        or ent.VNPC_IsLeaderTable
        or ent.VNPC_IsTownInfrastructure
        or ent.VNPC_IsCampRoof
end

function VNPC_CollectCampReservedSpots(camp)
    local spots = {}
    if not camp then return spots end
    if camp.pos then
        table.insert(spots, { pos = camp.pos, radius = 70 })
    end
    if IsValid(camp.campfire) then
        table.insert(spots, { pos = camp.campfire:GetPos(), radius = 95 })
    end
    if IsValid(camp.watersource) then
        table.insert(spots, { pos = camp.watersource:GetPos(), radius = 70 })
    end
    if IsValid(camp.leaderTable) then
        table.insert(spots, { pos = camp.leaderTable:GetPos(), radius = 55 })
    end
    if camp.leaderHut and camp.leaderHut.pos then
        table.insert(spots, { pos = camp.leaderHut.pos, radius = 110 })
    end
    for _, hut in ipairs(camp.huts or {}) do
        local hp = VNPC_GetHutWorldPos(hut)
        if hp then table.insert(spots, { pos = hp, radius = 115 }) end
    end
    for _, tent in ipairs(camp.tents or {}) do
        local tp = VNPC_GetHutWorldPos(tent)
        if tp then table.insert(spots, { pos = tp, radius = 115 }) end
    end
    return spots
end

function VNPC_IsNearReservedCampSpot(pos, camp, extraRadius)
    if not pos then return true end
    extraRadius = extraRadius or 0
    for _, spot in ipairs(VNPC_CollectCampReservedSpots(camp)) do
        local need = (spot.radius or 70) + extraRadius
        if pos:DistToSqr(spot.pos) < (need * need) then
            return true
        end
    end
    return false
end

function VNPC_IsCampBuildSpotClear(pos, minSep, camp, ignoreEnt)
    if not pos then return false end
    minSep = minSep or 78
    for _, ent in ipairs(ents.FindInSphere(pos, minSep)) do
        if ent ~= ignoreEnt and VNPC_IsCampStructureProp(ent) then
            if ent.VNPC_IsCampRoof then continue end
            if pos:DistToSqr(ent:GetPos()) < (minSep * minSep) then
                return false
            end
        end
    end
    if camp and VNPC_IsNearReservedCampSpot(pos, camp, 8) then
        return false
    end
    return true
end

function VNPC_FreezeCampProp(prop)
    if not IsValid(prop) then return end
    local phys = prop:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocity(Vector(0, 0, 0))
        phys:EnableMotion(false)
        phys:Sleep()
    end
end

function VNPC_GroundSnapSpawnedProp(prop, groundPos)
    if not IsValid(prop) or not groundPos then return end
    local minZ = prop:OBBMins().z
    local zOffset = (minZ < 0) and math.abs(minZ) or 0
    prop:SetPos(groundPos + Vector(0, 0, zOffset + 1))
end

function VNPC_LiftRoofAboveClearance(prop, floorZ, clearance)
    if not IsValid(prop) then return end
    clearance = clearance or VNPC_CAMP_HUT_ROOF_CLEARANCE
    local ang = prop:GetAngles()
    local mins, maxs = prop:OBBMins(), prop:OBBMaxs()
    local lowest = math.huge
    for _, x in ipairs({ mins.x, maxs.x }) do
        for _, y in ipairs({ mins.y, maxs.y }) do
            for _, z in ipairs({ mins.z, maxs.z }) do
                local world = prop:LocalToWorld(Vector(x, y, z))
                if world.z < lowest then lowest = world.z end
            end
        end
    end
    local desired = floorZ + clearance
    if lowest < desired then
        prop:SetPos(prop:GetPos() + Vector(0, 0, desired - lowest))
    end
    prop:SetAngles(ang)
end

function VNPC_SpawnFrozenCampProp(mdl, pos, ang, meta)
    if not pos then return nil end
    mdl = VNPC_PickValidCampModel(mdl, VNPC_CAMP_FENCE_MODEL)
    local prop = ents.Create("prop_physics")
    if not IsValid(prop) then return nil end
    prop:SetModel(mdl)
    prop:SetPos(pos)
    prop:SetAngles(ang or Angle(0, 0, 0))
    prop:Spawn()
    prop:Activate()
    if meta then
        for k, v in pairs(meta) do
            prop[k] = v
        end
    end
    if not meta or not meta.VNPC_IsCampRoof then
        VNPC_GroundSnapSpawnedProp(prop, pos)
    end
    VNPC_FreezeCampProp(prop)
    return prop
end

function VNPC_RotateOffset(x, y, yawDeg)
    local rad = math.rad(yawDeg or 0)
    local c, s = math.cos(rad), math.sin(rad)
    return Vector(x * c - y * s, x * s + y * c, 0)
end

function VNPC_BuildPolygonVerts(center, radii, yawOffset)
    local verts = {}
    local n = #radii
    if n < 3 then return verts end
    for i = 1, n do
        local ang = math.rad((yawOffset or 0) + (i - 1) * (360 / n))
        table.insert(verts, center + Vector(math.cos(ang) * radii[i], math.sin(ang) * radii[i], 0))
    end
    return verts
end

function VNPC_GenerateProceduralPerimeterVerts(camp)
    if not camp or not camp.pos then return {}, "none" end
    local seed = camp.layoutSeed or camp.id or math.random(100000, 999999)
    camp.layoutSeed = seed

    local center = camp.center or camp.pos
    local minRad = camp.isIndoors and 120 or 240
    local maxRad = camp.isIndoors and 340 or math.max(320, camp.territoryRadius or 350)
    local radius = math.Clamp(camp.territoryRadius or 320, minRad, maxRad)
    if camp.isPredatorCamp then
        radius = math.Clamp(radius * 0.55, 160, 280)
    end

    local layoutNames = { "rect", "irregular", "lshape", "hex", "trapezoid", "compound" }
    local layoutType = camp.layoutType or layoutNames[(seed % #layoutNames) + 1]
    camp.layoutType = layoutType
    local yaw = VNPC_CampHashInt(seed, 3, 0, 359)
    camp.layoutYaw = yaw

    local verts = {}
    if layoutType == "rect" then
        local w = radius * (0.72 + VNPC_CampHash01(seed, 4) * 0.38)
        local d = radius * (0.62 + VNPC_CampHash01(seed, 5) * 0.40)
        local corners = {
            Vector(w, d, 0), Vector(w, -d, 0), Vector(-w, -d, 0), Vector(-w, d, 0)
        }
        for _, c in ipairs(corners) do
            table.insert(verts, center + VNPC_RotateOffset(c.x, c.y, yaw))
        end
    elseif layoutType == "lshape" then
        local a = radius * (0.85 + VNPC_CampHash01(seed, 6) * 0.2)
        local b = radius * (0.40 + VNPC_CampHash01(seed, 7) * 0.18)
        local localVerts = {
            Vector(a, a, 0), Vector(a, -b, 0), Vector(b, -b, 0),
            Vector(b, -a, 0), Vector(-a, -a, 0), Vector(-a, a, 0)
        }
        for _, c in ipairs(localVerts) do
            table.insert(verts, center + VNPC_RotateOffset(c.x, c.y, yaw))
        end
    elseif layoutType == "hex" then
        local radii = {}
        for i = 1, 6 do
            radii[i] = radius * (0.86 + VNPC_CampHash01(seed, 10 + i) * 0.18)
        end
        verts = VNPC_BuildPolygonVerts(center, radii, yaw)
    elseif layoutType == "trapezoid" then
        local front = radius * (0.55 + VNPC_CampHash01(seed, 20) * 0.25)
        local back = radius * (0.80 + VNPC_CampHash01(seed, 21) * 0.28)
        local depth = radius * (0.70 + VNPC_CampHash01(seed, 22) * 0.25)
        local localVerts = {
            Vector(depth, back, 0), Vector(depth, -back, 0),
            Vector(-depth, -front, 0), Vector(-depth, front, 0)
        }
        for _, c in ipairs(localVerts) do
            table.insert(verts, center + VNPC_RotateOffset(c.x, c.y, yaw))
        end
    elseif layoutType == "compound" then
        local radii = {}
        for i = 1, 8 do
            local bulge = (i % 2 == 0) and 1.08 or 0.78
            radii[i] = radius * bulge * (0.90 + VNPC_CampHash01(seed, 30 + i) * 0.16)
        end
        verts = VNPC_BuildPolygonVerts(center, radii, yaw)
    else
        local n = VNPC_CampHashInt(seed, 40, 5, 8)
        local radii = {}
        for i = 1, n do
            radii[i] = radius * (0.68 + VNPC_CampHash01(seed, 50 + i) * 0.48)
        end
        verts = VNPC_BuildPolygonVerts(center, radii, yaw + VNPC_CampHashInt(seed, 41, -12, 12))
    end

    return verts, layoutType
end

function VNPC_PlanProceduralCampWalls(camp)
    if not camp or not camp.pos then return end

    local center = camp.pos
    local validMembers = 0
    local sumPos = Vector(0, 0, 0)
    for _, mem in ipairs(camp.members or {}) do
        if IsValid(mem) and mem:Health() > 0 then
            sumPos = sumPos + mem:GetPos()
            validMembers = validMembers + 1
        end
    end
    if validMembers > 0 then
        center = sumPos / validMembers
    end
    camp.center = center

    local verts, layoutType = VNPC_GenerateProceduralPerimeterVerts(camp)
    camp.plannedWalls = {}
    camp.layoutType = layoutType

    if #verts < 3 then return end

    local seed = camp.layoutSeed or camp.id or 1
    local gateSide = VNPC_CampHashInt(seed, 90, 1, #verts)
    camp.layoutGateSide = gateSide

    local upgrade = camp.breachAlertTime and (CurTime() - camp.breachAlertTime) < 180
    local fenceLen = VNPC_CAMP_FENCE_LENGTH

    for s = 1, #verts do
        local p1 = verts[s]
        local p2 = verts[(s % #verts) + 1]
        local sideLen = p1:Distance(p2)
        local numSegs = math.max(1, math.ceil(sideLen / fenceLen))
        local isGateSide = (s == gateSide)

        for seg = 1, numSegs do
            local t1 = (seg - 0.5) / numSegs
            local mid = LerpVector(t1, p1, p2)
            local floorPos = VNPC_SnapCampPosToGround(mid, 240)
            if not floorPos then continue end

            local wallDir = (p2 - p1)
            wallDir.z = 0
            if wallDir:LengthSqr() < 4 then continue end
            wallDir:Normalize()
            local wallAng = Angle(0, wallDir:Angle().y, 0)

            local isGate = false
            if isGateSide then
                local midSeg = math.max(1, math.floor((numSegs + 1) * 0.5))
                if numSegs <= 2 or math.abs(seg - midSeg) <= (numSegs >= 4 and 1 or 0) then
                    isGate = true
                end
            end

            if not isGate then
                if VNPC_IsNearReservedCampSpot(floorPos, camp, 20) then
                    continue
                end
                local tooClose = false
                for _, plan in ipairs(camp.plannedWalls) do
                    if plan.pos and not plan.isGate and floorPos:DistToSqr(plan.pos) < (72 * 72) then
                        tooClose = true
                        break
                    end
                end
                if tooClose then continue end
            end

            table.insert(camp.plannedWalls, {
                pos = floorPos,
                ang = wallAng,
                isGate = isGate,
                skipProp = isGate,
                built = false,
                isUpgrade = upgrade,
                layoutType = layoutType
            })
        end
    end
end

function VNPC_CountPendingCampWalls(camp)
    local pending, total = 0, 0
    for _, plan in ipairs(camp.plannedWalls or {}) do
        total = total + 1
        if not plan.built then pending = pending + 1 end
    end
    return pending, total
end

function VNPC_IsHutDoorwayBlocked(origin, ang, testPos, testZ)
    if not origin or not testPos then return false end
    local localPos = WorldToLocal(testPos, Angle(0, 0, 0), origin, Angle(0, ang.y, 0))
    if localPos.x > 18 then return false end
    if math.abs(localPos.y) > (VNPC_CAMP_DOORWAY_WIDTH * 0.5) then return false end
    if testZ and testZ >= (origin.z + 70) then return false end
    return true
end

function VNPC_FindClearHutSite(camp, extraSalt)
    if not camp or not camp.pos then return nil, nil end
    local seed = (camp.layoutSeed or camp.id or 1) + ((#(camp.huts or {}) + #(camp.tents or {})) * 97) + (extraSalt or 0)
    local center = camp.center or camp.pos
    local innerMin = camp.isIndoors and 55 or 90
    local innerMax = camp.isIndoors and 140 or math.max(130, math.floor((camp.territoryRadius or 320) * 0.32))

    for attempt = 1, 14 do
        local yaw = VNPC_CampHashInt(seed, 100 + attempt, 0, 359)
        local dist = VNPC_CampHashInt(seed, 200 + attempt, innerMin, innerMax)
        local rad = math.rad(yaw)
        local candidate = center + Vector(math.cos(rad) * dist, math.sin(rad) * dist, 0)
        local ground = VNPC_SnapCampPosToGround(candidate, 220)
        if not ground then continue end

        if IsValid(camp.campfire) and ground:DistToSqr(camp.campfire:GetPos()) < (130 * 130) then continue end
        if IsValid(camp.watersource) and ground:DistToSqr(camp.watersource:GetPos()) < (100 * 100) then continue end
        if IsValid(camp.leaderTable) and ground:DistToSqr(camp.leaderTable:GetPos()) < (130 * 130) then continue end

        local occupied = false
        for _, hut in ipairs(camp.huts or {}) do
            local hp = VNPC_GetHutWorldPos(hut)
            if hp and hp:DistToSqr(ground) < (170 * 170) then
                occupied = true
                break
            end
        end
        if occupied then continue end
        for _, tent in ipairs(camp.tents or {}) do
            local tp = VNPC_GetHutWorldPos(tent)
            if tp and tp:DistToSqr(ground) < (170 * 170) then
                occupied = true
                break
            end
        end
        if occupied then continue end

        for _, wall in ipairs(camp.walls or {}) do
            if IsValid(wall) and wall:GetPos():DistToSqr(ground) < (130 * 130) then
                occupied = true
                break
            end
        end
        if occupied then continue end
        for _, bar in ipairs(camp.barricades or {}) do
            if IsValid(bar) and bar:GetPos():DistToSqr(ground) < (130 * 130) then
                occupied = true
                break
            end
        end
        if occupied then continue end

        if VNPC_IsWorldSpotBlocked(ground + Vector(0, 0, 8), Vector(-28, -28, 0), Vector(28, 28, 76)) then
            continue
        end

        local face = (center - ground)
        face.z = 0
        if face:LengthSqr() < 4 then
            face = Vector(math.cos(rad), math.sin(rad), 0)
        end
        local ang = Angle(0, face:Angle().y, 0)
        local doorProbe = ground - ang:Forward() * 70 + Vector(0, 0, 16)
        local doorGround = VNPC_SnapCampPosToGround(doorProbe, 160)
        if not doorGround then continue end
        if VNPC_IsWorldSpotBlocked(doorGround + Vector(0, 0, 8), Vector(-18, -18, 0), Vector(18, 18, 72)) then
            continue
        end

        return ground + Vector(0, 0, 2), ang
    end
    return nil, nil
end

function VNPC_GetHutBuildPlan(origin, ang, includeDoorPosts)
    local fwd = ang:Forward()
    local right = ang:Right()
    local half = VNPC_CAMP_HUT_HALF
    local plan = {
        {
            id = "back",
            mdl = VNPC_CAMP_FENCE_MODEL,
            pos = origin + fwd * half + Vector(0, 0, 4),
            ang = Angle(0, ang.y, 0),
            roof = false
        },
        {
            id = "left",
            mdl = VNPC_CAMP_FENCE_MODEL,
            pos = origin + right * half + fwd * 6 + Vector(0, 0, 4),
            ang = Angle(0, ang.y + 90, 0),
            roof = false
        },
        {
            id = "right",
            mdl = VNPC_CAMP_FENCE_MODEL,
            pos = origin - right * half + fwd * 6 + Vector(0, 0, 4),
            ang = Angle(0, ang.y - 90, 0),
            roof = false
        },
        {
            id = "roof_a",
            mdl = VNPC_CAMP_FENCE_MODEL,
            pos = origin + right * 28 + Vector(0, 0, VNPC_CAMP_HUT_ROOF_CLEARANCE),
            ang = Angle(90, ang.y, 0),
            roof = true
        },
        {
            id = "roof_b",
            mdl = VNPC_CAMP_FENCE_MODEL,
            pos = origin - right * 28 + Vector(0, 0, VNPC_CAMP_HUT_ROOF_CLEARANCE),
            ang = Angle(90, ang.y, 0),
            roof = true
        }
    }
    if includeDoorPosts and util.IsValidModel(VNPC_CAMP_BOARD_MODEL) then
        local doorHalf = VNPC_CAMP_DOORWAY_WIDTH * 0.5 + 6
        table.insert(plan, {
            id = "post_l",
            mdl = VNPC_CAMP_BOARD_MODEL,
            pos = origin - fwd * (half - 4) + right * doorHalf + Vector(0, 0, 8),
            ang = Angle(0, ang.y, 0),
            roof = false,
            post = true
        })
        table.insert(plan, {
            id = "post_r",
            mdl = VNPC_CAMP_BOARD_MODEL,
            pos = origin - fwd * (half - 4) - right * doorHalf + Vector(0, 0, 8),
            ang = Angle(0, ang.y, 0),
            roof = false,
            post = true
        })
    end
    return plan
end

function VNPC_ApplyHutPieceMeta(prop, camp, isRoof)
    if not IsValid(prop) or not camp then return end
    prop.VNPC_PreyCampID = camp.isPreyCamp and camp.id or prop.VNPC_PreyCampID
    prop.VNPC_PredatorCampID = camp.isPredatorCamp and camp.id or prop.VNPC_PredatorCampID
    prop.VNPC_CampID = camp.id
    prop.VNPC_NoVore = true
    if camp.isPreyCamp then
        prop.VNPC_IsPreyCampHutPiece = true
    else
        prop.VNPC_IsPredatorTent = true
        prop.VNPC_IsPreyCampHutPiece = true
    end
    if isRoof then
        prop.VNPC_IsCampRoof = true
        prop.VNPC_IsLeaderHutWall = prop.VNPC_IsLeaderHutWall or false
    end
    prop:SetHealth(isRoof and 220 or 160)
end

function VNPC_ConstructWalkableHutPiece(camp, site)
    if not camp or not site or not site.pos or not site.ang then return false end
    site.props = site.props or {}
    site.plan = site.plan or VNPC_GetHutBuildPlan(site.pos, site.ang, true)
    site.stage = site.stage or 0

    while site.stage < #site.plan do
        site.stage = site.stage + 1
        local piece = site.plan[site.stage]
        if not piece then break end

        if camp.isIndoors and piece.roof then
            local trCeil = util.TraceLine({
                start = site.pos + Vector(0, 0, 10),
                endpos = site.pos + Vector(0, 0, 110),
                mask = MASK_SOLID_BRUSHONLY
            })
            if trCeil.Hit and not trCeil.HitSky and (trCeil.HitPos.z - site.pos.z) < 78 then
                continue
            end
        end

        if not piece.roof and VNPC_IsHutDoorwayBlocked(site.pos, site.ang, piece.pos, piece.pos.z) then
            continue
        end

        local spawnPos = piece.pos
        if not piece.roof then
            spawnPos = VNPC_SnapCampPosToGround(piece.pos, 180) or piece.pos
        end

        local prop = VNPC_SpawnFrozenCampProp(piece.mdl, spawnPos, piece.ang, {
            VNPC_IsCampRoof = piece.roof and true or nil
        })
        if not IsValid(prop) then
            return false
        end

        if piece.roof then
            VNPC_LiftRoofAboveClearance(prop, site.pos.z, VNPC_CAMP_HUT_ROOF_CLEARANCE)
            VNPC_FreezeCampProp(prop)
        end

        if not piece.roof and VNPC_IsHutDoorwayBlocked(site.pos, site.ang, prop:GetPos(), prop:GetPos().z) then
            prop:Remove()
            continue
        end

        VNPC_ApplyHutPieceMeta(prop, camp, piece.roof)
        if prop.EmitSound then
            prop:EmitSound("physics/wood/wood_box_impact_hard1.wav", 75, math.random(95, 105))
        end
        table.insert(site.props, prop)
        return true
    end

    return false
end

function VNPC_FinalizeHutSite(camp, site, extra)
    if not camp or not site then return nil end
    local hut = {
        id = #((camp.isPredatorCamp and camp.tents) or camp.huts or {}) + 1,
        pos = site.pos,
        ang = site.ang,
        interiorPos = site.pos + site.ang:Forward() * 8 + Vector(0, 0, 8),
        props = site.props or {},
        VNPC_IsPreyCampHut = not camp.isPredatorCamp,
        VNPC_IsPredatorTent = camp.isPredatorCamp and true or nil,
        VNPC_PreyCampID = camp.isPreyCamp and camp.id or nil,
        VNPC_PredatorCampID = camp.isPredatorCamp and camp.id or nil
    }
    if extra then
        for k, v in pairs(extra) do
            hut[k] = v
        end
    end
    return hut
end

function VNPC_ConstructCompleteWalkableHut(camp, site)
    if not camp or not site then return nil end
    site.plan = site.plan or VNPC_GetHutBuildPlan(site.pos, site.ang, true)
    site.stage = site.stage or 0
    local guard = 0
    while site.stage < #site.plan and guard < 12 do
        guard = guard + 1
        if not VNPC_ConstructWalkableHutPiece(camp, site) then
            break
        end
    end
    return VNPC_FinalizeHutSite(camp, site)
end
