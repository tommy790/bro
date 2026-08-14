-- V-NPCs Dynamic Bone-Pose Noclip Detector (sh_vnpc_bone_pose_noclip.lua)
-- Watches live bone-pose animations and records when posed bones clip through the world, the floor, or the body.

CreateConVar("vnpcs_bone_pose_noclip_detect", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Dynamically detect noclipping caused by bone pose animations")
CreateConVar("vnpcs_bone_pose_noclip_debug", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Print and overlay live bone-pose noclip hits")
CreateConVar("vnpcs_bone_pose_noclip_interval", "0.15", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Seconds between bone-pose noclip scans per entity")

VNPC_BonePoseNoclipLog = VNPC_BonePoseNoclipLog or {}

local SAMPLE_BONES = {
    "ValveBiped.Bip01_Head1",
    "ValveBiped.Bip01_Neck1",
    "ValveBiped.Bip01_Pelvis",
    "ValveBiped.Bip01_Spine",
    "ValveBiped.Bip01_Spine1",
    "ValveBiped.Bip01_Spine2",
    "ValveBiped.Bip01_R_Hand",
    "ValveBiped.Bip01_L_Hand",
    "ValveBiped.Bip01_R_Forearm",
    "ValveBiped.Bip01_L_Forearm",
    "ValveBiped.Bip01_R_UpperArm",
    "ValveBiped.Bip01_L_UpperArm",
    "ValveBiped.Bip01_R_Foot",
    "ValveBiped.Bip01_L_Foot",
    "ValveBiped.Bip01_R_Calf",
    "ValveBiped.Bip01_L_Calf",
    "ValveBiped.Bip01_R_Thigh",
    "ValveBiped.Bip01_L_Thigh"
}

local BONE_CHAINS = {
    { "ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_R_Hand" },
    { "ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_L_Hand" },
    { "ValveBiped.Bip01_R_Thigh", "ValveBiped.Bip01_R_Calf", "ValveBiped.Bip01_R_Foot" },
    { "ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_L_Foot" },
    { "ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Head1" }
}

local ALT_BONE = {
    ["ValveBiped.Bip01_Head1"] = { "Head1", "Head", "head" },
    ["ValveBiped.Bip01_Neck1"] = { "Neck1", "Neck", "neck" },
    ["ValveBiped.Bip01_Pelvis"] = { "Pelvis", "pelvis" },
    ["ValveBiped.Bip01_Spine"] = { "Spine", "spine" },
    ["ValveBiped.Bip01_Spine1"] = { "Spine1", "spine1" },
    ["ValveBiped.Bip01_Spine2"] = { "Spine2", "spine2" },
    ["ValveBiped.Bip01_R_Hand"] = { "R_Hand", "r_hand" },
    ["ValveBiped.Bip01_L_Hand"] = { "L_Hand", "l_hand" },
    ["ValveBiped.Bip01_R_Forearm"] = { "R_Forearm", "r_forearm" },
    ["ValveBiped.Bip01_L_Forearm"] = { "L_Forearm", "l_forearm" },
    ["ValveBiped.Bip01_R_UpperArm"] = { "R_UpperArm", "r_upperarm" },
    ["ValveBiped.Bip01_L_UpperArm"] = { "L_UpperArm", "l_upperarm" },
    ["ValveBiped.Bip01_R_Foot"] = { "R_Foot", "r_foot" },
    ["ValveBiped.Bip01_L_Foot"] = { "L_Foot", "l_foot" },
    ["ValveBiped.Bip01_R_Calf"] = { "R_Calf", "r_calf" },
    ["ValveBiped.Bip01_L_Calf"] = { "L_Calf", "l_calf" },
    ["ValveBiped.Bip01_R_Thigh"] = { "R_Thigh", "r_thigh" },
    ["ValveBiped.Bip01_L_Thigh"] = { "L_Thigh", "l_thigh" }
}

local function lookupPoseBone(ent, name)
    local id = ent:LookupBone(name)
    if id and id >= 0 then return id, name end
    for _, alt in ipairs(ALT_BONE[name] or {}) do
        id = ent:LookupBone(alt)
        if id and id >= 0 then return id, alt end
    end
    return nil, name
end

local function boneWorldPos(ent, name)
    local id = lookupPoseBone(ent, name)
    if not id then return nil end
    local pos = ent:GetBonePosition(id)
    return pos
end

local function stripBoneName(name)
    return (name or ""):gsub("ValveBiped%.", ""):gsub("Bip01_", "")
end

function VNPC_IsBonePoseAnimationActive(ent)
    if not IsValid(ent) then return false end
    if ent.Vored or ent.VNPC_Vored then return false end
    local phase = (ent.GetNWInt and ent:GetNWInt("FacialPhase", -1)) or -1
    if phase > 0 then return true end
    if ent.VNPC_IsHumanOralSwallow or (ent.GetNWBool and ent:GetNWBool("VNPC_IsHumanOralSwallow")) then return true end
    if ent.VNPC_IsMatingBonePose or (ent.GetNWBool and ent:GetNWBool("VNPC_IsMatingBonePose")) then return true end
    if ent.VNPC_IsWillingUnbirthCrawl or (ent.GetNWBool and ent:GetNWBool("VNPC_IsWillingUnbirthCrawl")) then return true end
    if ent.VNPC_IsMountingHeavyPrey or (ent.GetNWBool and ent:GetNWBool("VNPC_IsMountingHeavyPrey")) then return true end
    if ent.VNPC_IsDrinkingWater or (ent.GetNWBool and ent:GetNWBool("VNPC_IsDrinkingWater")) then return true end
    if ent.VNPC_IsSleepCrawled or ent.VNPC_IsSleeping then return true end
    if (ent.VNPC_InChildbirthPose or 0) > CurTime() then return true end
    if ent.VNPC_IsBeingSwallowed then return true end
    if istable(ent.BoneBlendState) then
        for _, cur in pairs(ent.BoneBlendState) do
            if cur and cur.pos and cur.pos:LengthSqr() > 1 then return true end
            if cur and cur.ang and (math.abs(cur.ang.p) + math.abs(cur.ang.y) + math.abs(cur.ang.r)) > 2 then return true end
        end
    end
    return false
end

local function pushHit(hits, kind, bone, pos, detail, severity)
    table.insert(hits, {
        kind = kind,
        bone = bone,
        pos = pos and Vector(pos.x, pos.y, pos.z) or vector_origin,
        detail = detail or "",
        severity = math.Clamp(severity or 1, 0.1, 3)
    })
end

local function recordLog(ent, hits)
    local entry = {
        time = CurTime(),
        ent = ent:EntIndex(),
        class = ent.PrintName or ent:GetClass(),
        moveset = ent.VNPC_AssignedMoveset or "default",
        phase = (ent.GetNWInt and ent:GetNWInt("FacialPhase", -1)) or -1,
        hits = hits
    }
    table.insert(VNPC_BonePoseNoclipLog, entry)
    while #VNPC_BonePoseNoclipLog > 40 do
        table.remove(VNPC_BonePoseNoclipLog, 1)
    end
end

function VNPC_ScanBonePoseNoclip(ent)
    if not IsValid(ent) or not ent.LookupBone or not ent.GetBonePosition then return {} end
    if ent.SetupBones then pcall(ent.SetupBones, ent) end

    local hits = {}
    local phase = (ent.GetNWInt and ent:GetNWInt("FacialPhase", -1)) or -1
    local holdingBelly = VNPC_IsBellyHoldPoseActive and select(1, VNPC_IsBellyHoldPoseActive(ent, phase))
    local handsOnBodyOK = (phase == 2 or phase == 3 or ent.VNPC_IsSleeping or ((ent.VNPC_InChildbirthPose or 0) > CurTime()) or holdingBelly)
    local parts = VNPC_MeasureBodyParts and VNPC_MeasureBodyParts(ent) or nil
    local torsoR = (parts and parts.torso and parts.torso.radius) or 7
    local handR = (parts and parts.hand and parts.hand.radius) or 3
    local footH = (parts and parts.foot and parts.foot.height) or 3
    local armMax = (parts and parts.arm and parts.arm.length * 1.28) or 58
    local legMax = (parts and parts.leg and parts.leg.length * 1.28) or 72
    local selfDist = torsoR + handR + 2

    -- 1. Extreme ManipulateBonePosition offsets (teleport the mesh through world/body)
    if istable(ent.BoneBlendState) then
        for boneName, cur in pairs(ent.BoneBlendState) do
            if cur and cur.pos then
                local len = cur.pos:Length()
                if len >= 36 then
                    local pos = boneWorldPos(ent, boneName) or ent:GetPos()
                    pushHit(hits, "offset", boneName, pos, string.format("bone offset %.1f units", len), math.min(len / 36, 3))
                end
            end
        end
    end

    -- 2. Bone is inside a world brush
    for _, name in ipairs(SAMPLE_BONES) do
        local pos = boneWorldPos(ent, name)
        if pos then
            local tr = util.TraceLine({
                start = pos,
                endpos = pos + Vector(0, 0, 1),
                mask = MASK_SOLID_BRUSHONLY,
                filter = ent
            })
            if tr.StartSolid and not tr.HitSky then
                pushHit(hits, "solid", name, pos, "bone is inside world brush", 1.4)
            end
        end
    end

    -- 3. Limb segments cutting through world geometry
    for _, chain in ipairs(BONE_CHAINS) do
        for i = 1, #chain - 1 do
            local a = boneWorldPos(ent, chain[i])
            local b = boneWorldPos(ent, chain[i + 1])
            if a and b and a:DistToSqr(b) > 16 then
                local span = a:Distance(b)
                local tr = util.TraceLine({
                    start = a,
                    endpos = b,
                    mask = MASK_SOLID_BRUSHONLY,
                    filter = ent
                })
                if tr.Hit and not tr.HitSky and not tr.StartSolid then
                    local along = a:Distance(tr.HitPos)
                    if along > 5 and along < (span - 5) then
                        pushHit(hits, "world", chain[i + 1], tr.HitPos, string.format("%s -> %s cuts world", stripBoneName(chain[i]), stripBoneName(chain[i + 1])), 1.6)
                    end
                end
                local maxLen = (chain[i]:find("Thigh") or chain[i]:find("Calf") or chain[i + 1]:find("Foot")) and legMax or armMax
                if span > maxLen then
                    pushHit(hits, "stretch", chain[i + 1], b, string.format("%s stretched to %.1f units", stripBoneName(chain[i + 1]), span), math.min(span / maxLen, 3))
                end
            end
        end
    end

    -- 4. Feet / pelvis sunk through the floor
    local groundBones = {
        "ValveBiped.Bip01_R_Foot",
        "ValveBiped.Bip01_L_Foot",
        "ValveBiped.Bip01_Pelvis"
    }
    for _, name in ipairs(groundBones) do
        local pos = boneWorldPos(ent, name)
        if pos then
            local tr = util.TraceLine({
                start = pos + Vector(0, 0, 28),
                endpos = pos - Vector(0, 0, 72),
                mask = MASK_SOLID_BRUSHONLY,
                filter = ent
            })
            local sinkTol = math.max(6, footH * 0.9)
            if tr.Hit and not tr.HitSky and pos.z < (tr.HitPos.z - sinkTol) then
                local sunk = tr.HitPos.z - pos.z
                pushHit(hits, "ground", name, pos, string.format("sunk %.1f units under floor (part H %.1f)", sunk, footH), math.min(sunk / 10, 3))
            end
        end
    end

    -- 5. Hands / forearms noclipping through the torso (skip poses that rest hands on the belly)
    if not handsOnBodyOK then
        local torso = boneWorldPos(ent, "ValveBiped.Bip01_Spine2") or boneWorldPos(ent, "ValveBiped.Bip01_Spine1")
        local pelvis = boneWorldPos(ent, "ValveBiped.Bip01_Pelvis")
        local head = boneWorldPos(ent, "ValveBiped.Bip01_Head1")
        for _, name in ipairs({ "ValveBiped.Bip01_R_Hand", "ValveBiped.Bip01_L_Hand", "ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_L_Forearm" }) do
            local pos = boneWorldPos(ent, name)
            if pos and torso and pos:DistToSqr(torso) < (selfDist * selfDist) then
                pushHit(hits, "self", name, pos, string.format("limb inside torso (need %.1f wide)", selfDist), 1.2)
            elseif pos and pelvis and name:find("Hand") and pos:DistToSqr(pelvis) < ((selfDist * 0.85) * (selfDist * 0.85)) then
                pushHit(hits, "self", name, pos, "hand inside pelvis", 1.1)
            elseif pos and head and name:find("Hand") and phase ~= 1 and phase ~= 4 and pos:DistToSqr(head) < ((handR + 3) * (handR + 3)) then
                pushHit(hits, "self", name, pos, "hand inside head", 1.0)
            end
        end
    end

    return hits
end

function VNPC_DetectBonePoseNoclip(ent)
    if not IsValid(ent) then return {} end
    local enabled = GetConVar("vnpcs_bone_pose_noclip_detect")
    if enabled and not enabled:GetBool() then return {} end
    if not VNPC_IsBonePoseAnimationActive(ent) then
        ent.VNPC_BonePoseNoclipHits = nil
        ent.VNPC_BonePoseNoclipCount = 0
        return {}
    end

    local interval = GetConVar("vnpcs_bone_pose_noclip_interval")
    local wait = interval and interval:GetFloat() or 0.15
    if wait < 0.05 then wait = 0.05 end
    local now = CurTime()
    if (ent.VNPC_NextBonePoseNoclipScan or 0) > now then
        return ent.VNPC_BonePoseNoclipHits or {}
    end
    ent.VNPC_NextBonePoseNoclipScan = now + wait

    local hits = VNPC_ScanBonePoseNoclip(ent)
    ent.VNPC_BonePoseNoclipHits = hits
    ent.VNPC_BonePoseNoclipCount = #hits
    ent.VNPC_BonePoseNoclipLastTime = now

    if #hits > 0 then
        recordLog(ent, hits)
        local autoFix = GetConVar("vnpcs_bone_pose_fixed_on_noclip")
        if autoFix and autoFix:GetBool() and not ent.VNPC_UseFixedBonePose and VNPC_ApplyFixedBonePose then
            local serious = false
            for _, hit in ipairs(hits) do
                if hit.kind == "world" or hit.kind == "solid" or hit.kind == "ground" or hit.kind == "offset" or hit.kind == "self" then
                    serious = true
                    break
                end
            end
            if serious then
                VNPC_ApplyFixedBonePose(ent)
                if (ent.VNPC_NextBonePoseNoclipPrint or 0) <= now then
                    print(string.format("[V-NPCs] Switched #%d [%s] to generated fixed bone pose after noclip (used measured W/H)",
                        ent:EntIndex(), ent.PrintName or ent:GetClass()))
                end
            end
        end
        local debug = GetConVar("vnpcs_bone_pose_noclip_debug")
        if debug and debug:GetBool() and (ent.VNPC_NextBonePoseNoclipPrint or 0) <= now then
            ent.VNPC_NextBonePoseNoclipPrint = now + 2.5
            local parts = {}
            for i = 1, math.min(#hits, 4) do
                table.insert(parts, hits[i].kind .. ":" .. stripBoneName(hits[i].bone))
            end
            print(string.format("[V-NPCs] Bone-pose noclip on #%d [%s] moveset=%s phase=%s -> %s",
                ent:EntIndex(), ent.PrintName or ent:GetClass(), tostring(ent.VNPC_AssignedMoveset or "default"),
                tostring((ent.GetNWInt and ent:GetNWInt("FacialPhase", -1)) or -1), table.concat(parts, ", ")))
        end
    end
    return hits
end

function VNPC_GetBonePoseNoclipHits(ent)
    if not IsValid(ent) then return {} end
    return ent.VNPC_BonePoseNoclipHits or {}
end

local function isPoseCandidate(ent)
    if not IsValid(ent) or ent:Health() <= 0 then return false end
    if not (ent:IsNPC() or ent:IsNextBot() or ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator) then
        return false
    end
    return true
end

hook.Add("Think", "VNPC_BonePoseNoclip_Loop", function()
    local enabled = GetConVar("vnpcs_bone_pose_noclip_detect")
    if enabled and not enabled:GetBool() then return end
    local now = CurTime()
    if (VNPC_NextBonePoseNoclipThink or 0) > now then return end
    VNPC_NextBonePoseNoclipThink = now + 0.2

    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if isPoseCandidate(ent) and VNPC_IsBonePoseAnimationActive(ent) then
            VNPC_DetectBonePoseNoclip(ent)
        end
    end
end)

if CLIENT then
    hook.Add("PostDrawTranslucentRenderables", "VNPC_BonePoseNoclip_Overlay", function()
        local debug = GetConVar("vnpcs_bone_pose_noclip_debug")
        if not debug or not debug:GetBool() then return end
        local colors = {
            world = Color(255, 60, 60),
            solid = Color(255, 120, 40),
            ground = Color(255, 200, 40),
            self = Color(220, 80, 255),
            offset = Color(80, 180, 255),
            stretch = Color(80, 255, 180)
        }
        for _, ent in ipairs(ents.FindByClass("npc_*")) do
            local hits = IsValid(ent) and ent.VNPC_BonePoseNoclipHits or nil
            if not hits then continue end
            for _, hit in ipairs(hits) do
                local col = colors[hit.kind] or Color(255, 255, 255)
                render.SetColorMaterial()
                render.DrawSphere(hit.pos, 3 + (hit.severity or 1), 10, 10, Color(col.r, col.g, col.b, 160))
                local ang = EyeAngles()
                ang:RotateAroundAxis(ang:Forward(), 90)
                ang:RotateAroundAxis(ang:Right(), 90)
                cam.Start3D2D(hit.pos + Vector(0, 0, 6), ang, 0.12)
                    draw.SimpleText(hit.kind .. " " .. stripBoneName(hit.bone), "DermaDefaultBold", 0, 0, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                cam.End3D2D()
            end
        end
    end)
end

local function printStatus(ply)
    print("===============================================================")
    print("        V-NPCs DYNAMIC BONE-POSE NOCLIP DETECTOR STATUS        ")
    print("===============================================================")
    local on = GetConVar("vnpcs_bone_pose_noclip_detect")
    local dbg = GetConVar("vnpcs_bone_pose_noclip_debug")
    print(" - Detector Enabled: " .. tostring(on and on:GetBool()))
    print(" - Debug Overlay/Print: " .. tostring(dbg and dbg:GetBool()))
    print(" - Scan Interval: " .. tostring(GetConVar("vnpcs_bone_pose_noclip_interval"):GetFloat()) .. "s")
    print("-----------------------------------------")
    local posing, clipping = 0, 0
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if isPoseCandidate(ent) and VNPC_IsBonePoseAnimationActive(ent) then
            posing = posing + 1
            local hits = VNPC_DetectBonePoseNoclip(ent)
            if #hits > 0 then
                clipping = clipping + 1
                print(string.format(" -> #%d [%s] moveset=%s phase=%s | %d noclip hit(s)",
                    ent:EntIndex(), ent.PrintName or ent:GetClass(), tostring(ent.VNPC_AssignedMoveset or "default"),
                    tostring((ent.GetNWInt and ent:GetNWInt("FacialPhase", -1)) or -1), #hits))
                for _, hit in ipairs(hits) do
                    print(string.format("      [%s] %s @ (%.1f, %.1f, %.1f) %s",
                        hit.kind, hit.bone, hit.pos.x, hit.pos.y, hit.pos.z, hit.detail))
                end
            end
        end
    end
    print(string.format("Posing entities: %d | Currently noclipping: %d | Log entries: %d", posing, clipping, #VNPC_BonePoseNoclipLog))
    print("===============================================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Bone-pose noclip status printed to console. Posing: " .. posing .. " | Noclipping: " .. clipping)
    end
end

concommand.Add("vnpcs_bone_pose_noclip_status", function(ply)
    printStatus(ply)
end)

concommand.Add("vnpcs_test_bone_pose_noclip", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot() or target.IsDrGNextbot) then
        ply:ChatPrint("[V-NPCs] Aim at an NPC to scan its bone pose for noclipping!")
        return
    end
    target.VNPC_NextBonePoseNoclipScan = 0
    local hits = VNPC_ScanBonePoseNoclip(target)
    target.VNPC_BonePoseNoclipHits = hits
    target.VNPC_BonePoseNoclipCount = #hits
    if #hits == 0 then
        ply:ChatPrint("[V-NPCs] No bone-pose noclip detected on " .. tostring(target))
    else
        ply:ChatPrint("[V-NPCs] " .. #hits .. " bone-pose noclip hit(s) on " .. tostring(target) .. " (see console)")
        print(string.format("[V-NPCs] Forced bone-pose noclip scan on #%d [%s]:", target:EntIndex(), target.PrintName or target:GetClass()))
        for _, hit in ipairs(hits) do
            print(string.format("   [%s] %s @ (%.1f, %.1f, %.1f) %s", hit.kind, hit.bone, hit.pos.x, hit.pos.y, hit.pos.z, hit.detail))
        end
    end
end)
