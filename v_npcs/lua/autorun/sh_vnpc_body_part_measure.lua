-- V-NPCs Body-Part Measure & Fixed Bone-Pose Generator (sh_vnpc_body_part_measure.lua)
-- Measures prey/pred part width and height, then builds a clip-safe 5-phase bone pose from those sizes.

CreateConVar("vnpcs_body_part_measure", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Measure predator and prey body-part width/height for clip-safe bone poses")
CreateConVar("vnpcs_bone_pose_fixed_on_noclip", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Switch a noclipping bone-pose animation over to the generated fixed pose")

VNPC_BodyPartCache = VNPC_BodyPartCache or {}
VNPC_FixedPoseCache = VNPC_FixedPoseCache or {}

local BONE_ALTS = {
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
    ["ValveBiped.Bip01_R_Clavicle"] = { "R_Clavicle", "r_clavicle" },
    ["ValveBiped.Bip01_L_Clavicle"] = { "L_Clavicle", "l_clavicle" },
    ["ValveBiped.Bip01_R_Foot"] = { "R_Foot", "r_foot" },
    ["ValveBiped.Bip01_L_Foot"] = { "L_Foot", "l_foot" },
    ["ValveBiped.Bip01_R_Calf"] = { "R_Calf", "r_calf" },
    ["ValveBiped.Bip01_L_Calf"] = { "L_Calf", "l_calf" },
    ["ValveBiped.Bip01_R_Thigh"] = { "R_Thigh", "r_thigh" },
    ["ValveBiped.Bip01_L_Thigh"] = { "L_Thigh", "l_thigh" }
}

local function findBone(ent, name)
    if not IsValid(ent) or not ent.LookupBone then return nil end
    local id = ent:LookupBone(name)
    if id and id >= 0 then return id end
    for _, alt in ipairs(BONE_ALTS[name] or {}) do
        id = ent:LookupBone(alt)
        if id and id >= 0 then return id end
    end
    return nil
end

local function bonePos(ent, name)
    local id = findBone(ent, name)
    if not id or not ent.GetBonePosition then return nil end
    return ent:GetBonePosition(id)
end

local function boneDist(ent, a, b)
    local pa, pb = bonePos(ent, a), bonePos(ent, b)
    if not pa or not pb then return nil end
    return pa:Distance(pb)
end

local function emptyPart(length, width, height)
    length = math.max(0.1, tonumber(length) or 8)
    width = math.max(0.1, tonumber(width) or 4)
    height = math.max(0.1, tonumber(height) or 4)
    return {
        length = length,
        width = width,
        height = height,
        radius = math.max(width, height) * 0.5
    }
end

local function mergeHitbox(into, mins, maxs)
    if not mins or not maxs then return into end
    local size = maxs - mins
    local hx, hy, hz = math.abs(size.x), math.abs(size.y), math.abs(size.z)
    local dims = { hx, hy, hz }
    table.sort(dims)
    into.length = math.max(into.length or 0, dims[3] or 0)
    into.width = math.max(into.width or 0, dims[2] or 0)
    into.height = math.max(into.height or 0, dims[1] or 0)
    into.radius = math.max(into.width, into.height) * 0.5
    return into
end

local function collectHitboxes(ent)
    local byBone = {}
    if not ent.GetHitBoxCount or not ent.GetHitBoxBone or not ent.GetHitBoxBounds then
        return byBone
    end
    local sets = 1
    if ent.GetHitboxSetCount then
        sets = math.max(1, ent:GetHitboxSetCount() or 1)
    end
    for s = 0, sets - 1 do
        local count = ent:GetHitBoxCount(s) or 0
        for i = 0, count - 1 do
            local bone = ent:GetHitBoxBone(i, s)
            local mins, maxs = ent:GetHitBoxBounds(i, s)
            if bone and bone >= 0 and mins and maxs then
                local name = ent:GetBoneName(bone) or tostring(bone)
                byBone[name] = mergeHitbox(byBone[name] or emptyPart(0, 0, 0), mins, maxs)
                byBone[bone] = byBone[name]
            end
        end
    end
    return byBone
end

local function hitboxFor(ent, hitboxes, name)
    local id = findBone(ent, name)
    if id and hitboxes[id] and (hitboxes[id].width or 0) > 0.2 then
        return hitboxes[id]
    end
    if hitboxes[name] and (hitboxes[name].width or 0) > 0.2 then
        return hitboxes[name]
    end
    for _, alt in ipairs(BONE_ALTS[name] or {}) do
        if hitboxes[alt] and (hitboxes[alt].width or 0) > 0.2 then
            return hitboxes[alt]
        end
    end
    return nil
end

local function finishPart(part, fallbackLen, fallbackW, fallbackH)
    local p = part or emptyPart(fallbackLen, fallbackW, fallbackH)
    if (p.length or 0) < 0.5 then p.length = fallbackLen end
    if (p.width or 0) < 0.5 then p.width = fallbackW end
    if (p.height or 0) < 0.5 then p.height = fallbackH end
    p.radius = math.max(p.width, p.height) * 0.5
    return p
end

function VNPC_GetBodyPartCacheKey(ent)
    if not IsValid(ent) then return "invalid" end
    local mdl = string.lower(ent:GetModel() or "unknown")
    local scale = ent.GetModelScale and ent:GetModelScale() or 1
    return mdl .. "@" .. string.format("%.2f", scale)
end

function VNPC_MeasureBodyParts(ent)
    if not IsValid(ent) then return nil end
    local enabled = GetConVar("vnpcs_body_part_measure")
    if enabled and not enabled:GetBool() then return nil end

    local key = VNPC_GetBodyPartCacheKey(ent)
    if VNPC_BodyPartCache[key] then
        return VNPC_BodyPartCache[key]
    end

    if ent.SetupBones then pcall(ent.SetupBones, ent) end
    local scale = (ent.GetModelScale and ent:GetModelScale()) or 1
    local hitboxes = collectHitboxes(ent)

    local bodyH = 72 * scale
    if ent.GetModelBounds then
        local mins, maxs = ent:GetModelBounds()
        if mins and maxs then
            bodyH = math.max(24, math.abs(maxs.z - mins.z) * scale)
        end
    end
    local headToFoot = boneDist(ent, "ValveBiped.Bip01_Head1", "ValveBiped.Bip01_R_Foot")
        or boneDist(ent, "ValveBiped.Bip01_Head1", "ValveBiped.Bip01_L_Foot")
    if headToFoot and headToFoot > 20 then
        bodyH = math.max(bodyH, headToFoot)
    end

    local function measured(nameA, nameB, fbLen, fbW, fbH)
        local len = boneDist(ent, nameA, nameB) or fbLen
        local hb = hitboxFor(ent, hitboxes, nameA) or hitboxFor(ent, hitboxes, nameB)
        if hb then
            return finishPart({
                length = math.max(len, hb.length or 0),
                width = hb.width,
                height = hb.height
            }, fbLen, fbW, fbH)
        end
        return finishPart(emptyPart(len, fbW, fbH), fbLen, fbW, fbH)
    end

    local head = measured("ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Neck1", 8 * scale, 7.2 * scale, 8.5 * scale)
    local neck = measured("ValveBiped.Bip01_Neck1", "ValveBiped.Bip01_Spine2", 5 * scale, 4.5 * scale, 5 * scale)
    local torsoH = boneDist(ent, "ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_Spine2")
        or boneDist(ent, "ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_Head1")
        or (20 * scale)
    local torsoW = boneDist(ent, "ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_R_UpperArm")
        or boneDist(ent, "ValveBiped.Bip01_L_Clavicle", "ValveBiped.Bip01_R_Clavicle")
        or (14 * scale)
    local torsoHB = hitboxFor(ent, hitboxes, "ValveBiped.Bip01_Spine2") or hitboxFor(ent, hitboxes, "ValveBiped.Bip01_Spine1")
    local torso = finishPart({
        length = torsoH,
        width = math.max(torsoW, torsoHB and torsoHB.width or 0),
        height = math.max(torsoH * 0.55, torsoHB and torsoHB.height or 0)
    }, 20 * scale, 14 * scale, 16 * scale)

    local pelvisW = boneDist(ent, "ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_R_Thigh") or (12 * scale)
    local pelvis = finishPart({
        length = 8 * scale,
        width = pelvisW,
        height = 7 * scale
    }, 8 * scale, 12 * scale, 7 * scale)
    local pelvisHB = hitboxFor(ent, hitboxes, "ValveBiped.Bip01_Pelvis")
    if pelvisHB then pelvis = finishPart(pelvisHB, pelvis.length, pelvis.width, pelvis.height) end

    local upperArm = measured("ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_R_Forearm", 12 * scale, 4.2 * scale, 4.2 * scale)
    local forearm = measured("ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_R_Hand", 11 * scale, 3.4 * scale, 3.4 * scale)
    local hand = measured("ValveBiped.Bip01_R_Hand", "ValveBiped.Bip01_R_Hand", 4 * scale, 3.2 * scale, 2.4 * scale)
    local thigh = measured("ValveBiped.Bip01_R_Thigh", "ValveBiped.Bip01_R_Calf", 16 * scale, 5.5 * scale, 5.5 * scale)
    local calf = measured("ValveBiped.Bip01_R_Calf", "ValveBiped.Bip01_R_Foot", 15 * scale, 4.2 * scale, 4.2 * scale)
    local foot = measured("ValveBiped.Bip01_R_Foot", "ValveBiped.Bip01_R_Foot", 7 * scale, 4.0 * scale, 3.2 * scale)

    local armLen = upperArm.length + forearm.length
    local legLen = thigh.length + calf.length
    local clearance = (torso.width * 0.5) + math.max(hand.radius, forearm.radius) + 3

    local parts = {
        key = key,
        model = ent:GetModel() or "",
        scale = scale,
        bodyHeight = bodyH,
        head = head,
        neck = neck,
        torso = torso,
        pelvis = pelvis,
        upperArm = upperArm,
        forearm = forearm,
        hand = hand,
        thigh = thigh,
        calf = calf,
        foot = foot,
        arm = { length = armLen, width = math.max(upperArm.width, forearm.width), height = math.max(upperArm.height, forearm.height), radius = math.max(upperArm.radius, forearm.radius) },
        leg = { length = legLen, width = math.max(thigh.width, calf.width), height = math.max(thigh.height, calf.height), radius = math.max(thigh.radius, calf.radius) },
        clearance = clearance
    }

    VNPC_BodyPartCache[key] = parts
    ent.VNPC_BodyParts = parts
    return parts
end

local function poseBone(pos, ang)
    return { pos = pos or Vector(0, 0, 0), ang = ang or Angle(0, 0, 0) }
end

function VNPC_GenerateFixedBonePose(ent, parts)
    parts = parts or VNPC_MeasureBodyParts(ent)
    if not parts then return nil end

    local torsoR = parts.torso.radius
    local handR = parts.hand.radius
    local headH = parts.head.height
    local armL = math.max(parts.arm.length, 8)
    local thighL = math.max(parts.thigh.length, 8)
    local clear = math.max(parts.clearance or (torsoR + handR + 3), 6)

    -- Keep hands outside the torso: outward yaw from measured widths.
    local armOut = math.Clamp(math.deg(math.atan(clear / armL)), 12, 30)
    local armLift = math.Clamp(18 + (22 / armL) * 6, 16, 28)
    local foreBend = -math.Clamp(22 + (torsoR - 6) * 0.6, 18, 38)
    -- Taller heads get a milder tilt so the chin does not punch through the chest.
    local headTilt = math.Clamp(10 + (10 / math.max(headH, 6)) * 5, 8, 20)
    -- Sit only as far as the legs allow, never a 40-unit pelvis drop through the floor.
    local sitDrop = -math.Clamp(parts.leg.length * 0.18, 5, 14)
    local thighSit = -math.Clamp(28 + thighL * 0.35, 28, 48)
    local calfSit = math.Clamp(40 + parts.calf.length * 0.4, 36, 62)
    local hipSpread = math.Clamp(parts.pelvis.width * 0.55, 8, 18)

    local rest = {
        ["ValveBiped.Bip01_Head1"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_Spine"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_Spine1"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_Spine2"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_Pelvis"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_R_Clavicle"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_L_Clavicle"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_R_UpperArm"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_L_UpperArm"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_R_Forearm"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_L_Forearm"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_R_Hand"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_L_Hand"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_R_Thigh"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_L_Thigh"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_R_Calf"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_L_Calf"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_R_Foot"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_L_Foot"] = poseBone(nil, Angle(0, 0, 0))
    }

    local swallow = {
        ["ValveBiped.Bip01_Head1"] = poseBone(nil, Angle(0, headTilt + 6, 0)),
        ["ValveBiped.Bip01_Spine"] = poseBone(nil, Angle(0, -6, 0)),
        ["ValveBiped.Bip01_Spine1"] = poseBone(nil, Angle(0, -2, 0)),
        ["ValveBiped.Bip01_R_Clavicle"] = poseBone(nil, Angle(0, 8, 0)),
        ["ValveBiped.Bip01_L_Clavicle"] = poseBone(nil, Angle(0, -8, 0)),
        ["ValveBiped.Bip01_R_UpperArm"] = poseBone(nil, Angle(armLift, -armOut, 10)),
        ["ValveBiped.Bip01_L_UpperArm"] = poseBone(nil, Angle(-armLift, -armOut, -10)),
        ["ValveBiped.Bip01_R_Forearm"] = poseBone(nil, Angle(foreBend, 10, 0)),
        ["ValveBiped.Bip01_L_Forearm"] = poseBone(nil, Angle(foreBend, -10, 0)),
        ["ValveBiped.Bip01_R_Hand"] = poseBone(nil, Angle(0, 8, 0)),
        ["ValveBiped.Bip01_L_Hand"] = poseBone(nil, Angle(0, -8, 0)),
        ["ValveBiped.Bip01_Pelvis"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_R_Thigh"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_L_Thigh"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_R_Calf"] = poseBone(nil, Angle(0, 0, 0)),
        ["ValveBiped.Bip01_L_Calf"] = poseBone(nil, Angle(0, 0, 0))
    }

    local full = {
        ["ValveBiped.Bip01_Head1"] = poseBone(nil, Angle(-8, -headTilt, 0)),
        ["ValveBiped.Bip01_Spine"] = poseBone(nil, Angle(0, -6, 0)),
        ["ValveBiped.Bip01_Spine1"] = poseBone(nil, Angle(0, -6, 0)),
        ["ValveBiped.Bip01_R_UpperArm"] = poseBone(nil, Angle(armLift - 4, -armOut + 4, 8)),
        ["ValveBiped.Bip01_L_UpperArm"] = poseBone(nil, Angle(-(armLift - 4), -armOut + 4, -8)),
        ["ValveBiped.Bip01_R_Forearm"] = poseBone(nil, Angle(foreBend - 6, 12, -8)),
        ["ValveBiped.Bip01_L_Forearm"] = poseBone(nil, Angle(foreBend - 6, -12, 8)),
        ["ValveBiped.Bip01_R_Hand"] = poseBone(nil, Angle(8, 10, 12)),
        ["ValveBiped.Bip01_L_Hand"] = poseBone(nil, Angle(8, -10, -12)),
        ["ValveBiped.Bip01_R_Thigh"] = poseBone(nil, Angle(hipSpread * 0.35, thighSit, 0)),
        ["ValveBiped.Bip01_L_Thigh"] = poseBone(nil, Angle(-hipSpread * 0.35, thighSit, 0)),
        ["ValveBiped.Bip01_R_Calf"] = poseBone(nil, Angle(0, calfSit, 0)),
        ["ValveBiped.Bip01_L_Calf"] = poseBone(nil, Angle(0, calfSit, 0)),
        ["ValveBiped.Bip01_R_Foot"] = poseBone(nil, Angle(0, 18, 0)),
        ["ValveBiped.Bip01_L_Foot"] = poseBone(nil, Angle(0, 18, 0)),
        ["ValveBiped.Bip01_Pelvis"] = poseBone(Vector(0, 0, sitDrop), Angle(0, 0, -6))
    }

    local burp = {
        ["ValveBiped.Bip01_Head1"] = poseBone(nil, Angle(-6, headTilt, 0)),
        ["ValveBiped.Bip01_Spine1"] = poseBone(nil, Angle(0, -5, 0)),
        ["ValveBiped.Bip01_R_UpperArm"] = poseBone(nil, Angle(armLift - 6, -armOut + 2, 8)),
        ["ValveBiped.Bip01_L_UpperArm"] = poseBone(nil, Angle(-(armLift - 6), -armOut + 2, -8)),
        ["ValveBiped.Bip01_R_Forearm"] = poseBone(nil, Angle(foreBend, 10, 0)),
        ["ValveBiped.Bip01_L_Forearm"] = poseBone(nil, Angle(foreBend, -10, 0)),
        ["ValveBiped.Bip01_R_Thigh"] = poseBone(nil, Angle(hipSpread * 0.35, thighSit, 0)),
        ["ValveBiped.Bip01_L_Thigh"] = poseBone(nil, Angle(-hipSpread * 0.35, thighSit, 0)),
        ["ValveBiped.Bip01_R_Calf"] = poseBone(nil, Angle(0, calfSit, 0)),
        ["ValveBiped.Bip01_L_Calf"] = poseBone(nil, Angle(0, calfSit, 0)),
        ["ValveBiped.Bip01_Pelvis"] = poseBone(Vector(0, 0, sitDrop), Angle(0, 0, -6))
    }

    local gulp = {
        ["ValveBiped.Bip01_Head1"] = poseBone(nil, Angle(-4, -8, 4)),
        ["ValveBiped.Bip01_Spine"] = poseBone(nil, Angle(0, -5, 0)),
        ["ValveBiped.Bip01_R_Clavicle"] = poseBone(nil, Angle(0, 8, 0)),
        ["ValveBiped.Bip01_L_Clavicle"] = poseBone(nil, Angle(0, -8, 0)),
        ["ValveBiped.Bip01_R_UpperArm"] = poseBone(nil, Angle(armLift - 2, -armOut, 8)),
        ["ValveBiped.Bip01_L_UpperArm"] = poseBone(nil, Angle(-(armLift - 2), -armOut, -8)),
        ["ValveBiped.Bip01_R_Forearm"] = poseBone(nil, Angle(foreBend, 8, 0)),
        ["ValveBiped.Bip01_L_Forearm"] = poseBone(nil, Angle(foreBend, -8, 0)),
        ["ValveBiped.Bip01_Pelvis"] = poseBone(nil, Angle(0, 0, 0))
    }

    -- One-shot swallow uses the same clearance-scaled grab/lift so prey and pred widths stay apart.
    local swallowShot = {
        length = 5.0,
        oneshot = true,
        keyframes = {
            [0.00] = {
                ["ValveBiped.Bip01_Head1"] = poseBone(nil, Angle(0, headTilt, 0)),
                ["ValveBiped.Bip01_Spine1"] = poseBone(nil, Angle(0, -3, 0)),
                ["ValveBiped.Bip01_R_UpperArm"] = poseBone(nil, Angle(armLift + 4, -armOut, 12)),
                ["ValveBiped.Bip01_L_UpperArm"] = poseBone(nil, Angle(-(armLift + 4), -armOut, -12)),
                ["ValveBiped.Bip01_R_Forearm"] = poseBone(nil, Angle(foreBend - 4, 12, -8)),
                ["ValveBiped.Bip01_L_Forearm"] = poseBone(nil, Angle(foreBend - 4, -12, 8))
            },
            [0.40] = {
                ["ValveBiped.Bip01_Head1"] = poseBone(nil, Angle(0, headTilt + 8, 0)),
                ["ValveBiped.Bip01_Spine1"] = poseBone(nil, Angle(0, -5, 0)),
                ["ValveBiped.Bip01_R_UpperArm"] = poseBone(nil, Angle(armLift + 6, -armOut - 2, 12)),
                ["ValveBiped.Bip01_L_UpperArm"] = poseBone(nil, Angle(-(armLift + 6), -armOut - 2, -12)),
                ["ValveBiped.Bip01_R_Forearm"] = poseBone(nil, Angle(foreBend - 8, 14, -10)),
                ["ValveBiped.Bip01_L_Forearm"] = poseBone(nil, Angle(foreBend - 8, -14, 10))
            },
            [1.00] = {
                ["ValveBiped.Bip01_Head1"] = poseBone(nil, Angle(-4, -6, 0)),
                ["ValveBiped.Bip01_Spine1"] = poseBone(nil, Angle(0, -3, 0)),
                ["ValveBiped.Bip01_R_UpperArm"] = poseBone(nil, Angle(armLift, -armOut, 8)),
                ["ValveBiped.Bip01_L_UpperArm"] = poseBone(nil, Angle(-armLift, -armOut, -8)),
                ["ValveBiped.Bip01_R_Forearm"] = poseBone(nil, Angle(foreBend, 10, 0)),
                ["ValveBiped.Bip01_L_Forearm"] = poseBone(nil, Angle(foreBend, -10, 0))
            }
        }
    }

    return {
        [0] = rest,
        [1] = swallowShot,
        [2] = full,
        [3] = burp,
        [4] = gulp,
        swallowStatic = swallow,
        parts = parts
    }
end

function VNPC_GetFixedBonePose(ent)
    if not IsValid(ent) then return nil end
    local parts = VNPC_MeasureBodyParts(ent)
    if not parts then return nil end
    local key = parts.key
    if VNPC_FixedPoseCache[key] then
        return VNPC_FixedPoseCache[key]
    end
    local pose = VNPC_GenerateFixedBonePose(ent, parts)
    if pose then
        VNPC_FixedPoseCache[key] = pose
        ent.VNPC_FixedBonePose = pose
        ent.VNPC_FixedBonePoseKey = key
    end
    return pose
end

function VNPC_ApplyFixedBonePose(ent)
    if not IsValid(ent) then return false end
    local pose = VNPC_GetFixedBonePose(ent)
    if not pose then return false end
    ent.VNPC_UseFixedBonePose = true
    ent.VNPC_AssignedMoveset = "fixed"
    ent.VNPC_FixedBonePose = pose
    return true
end

function VNPC_GetBodyPartClearance(ent, partName)
    local parts = VNPC_MeasureBodyParts(ent)
    if not parts then return 8, 8 end
    local part = parts[partName] or parts.torso
    return part.width or 8, part.height or 8
end

if VNPC_RegisterBoneMoveset then
    -- Placeholder so vnpcs_set_moveset fixed works; real pose is generated per model.
    VNPC_RegisterBoneMoveset("fixed", { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} })
end

concommand.Add("vnpcs_body_parts_status", function(ply)
    print("===============================================================")
    print("     V-NPCs BODY PART WIDTH / HEIGHT + FIXED POSE STATUS       ")
    print("===============================================================")
    print(" - Measure Enabled: " .. tostring(GetConVar("vnpcs_body_part_measure"):GetBool()))
    print(" - Auto-fix on noclip: " .. tostring(GetConVar("vnpcs_bone_pose_fixed_on_noclip"):GetBool()))
    print("-----------------------------------------")
    local count = 0
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(ent) and (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator or ent:IsNPC()) then
            local parts = VNPC_MeasureBodyParts(ent)
            if parts then
                count = count + 1
                print(string.format(" -> #%d [%s] scale=%.2f bodyH=%.1f fixed=%s",
                    ent:EntIndex(), ent.PrintName or ent:GetClass(), parts.scale, parts.bodyHeight,
                    tostring(ent.VNPC_UseFixedBonePose or ent.VNPC_AssignedMoveset == "fixed")))
                print(string.format("      head W/H %.1f/%.1f | torso W/H %.1f/%.1f | arm L/W/H %.1f/%.1f/%.1f | leg L/W/H %.1f/%.1f/%.1f | clear %.1f",
                    parts.head.width, parts.head.height, parts.torso.width, parts.torso.height,
                    parts.arm.length, parts.arm.width, parts.arm.height,
                    parts.leg.length, parts.leg.width, parts.leg.height, parts.clearance))
            end
        end
    end
    print("Measured entities: " .. count .. " | Cached models: " .. table.Count(VNPC_BodyPartCache))
    print("===============================================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Body-part measure status printed to console. Measured: " .. count)
    end
end)

concommand.Add("vnpcs_test_body_parts", function(ply)
    if not IsValid(ply) then return end
    local target = ply:GetEyeTrace().Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot() or target.IsDrGNextbot) then
        ply:ChatPrint("[V-NPCs] Aim at a pred or prey NPC to measure body-part width and height!")
        return
    end
    VNPC_BodyPartCache[VNPC_GetBodyPartCacheKey(target)] = nil
    local parts = VNPC_MeasureBodyParts(target)
    if not parts then
        ply:ChatPrint("[V-NPCs] Could not measure body parts on " .. tostring(target))
        return
    end
    ply:ChatPrint(string.format("[V-NPCs] %s torso W/H %.1f/%.1f | head %.1f/%.1f | arm L %.1f | clear %.1f",
        tostring(target), parts.torso.width, parts.torso.height, parts.head.width, parts.head.height, parts.arm.length, parts.clearance))
    print(string.format("[V-NPCs] Body parts for #%d [%s]:", target:EntIndex(), target.PrintName or target:GetClass()))
    for _, key in ipairs({ "head", "neck", "torso", "pelvis", "upperArm", "forearm", "hand", "thigh", "calf", "foot", "arm", "leg" }) do
        local p = parts[key]
        if p then
            print(string.format("   %-9s  L=%5.1f  W=%5.1f  H=%5.1f  R=%5.1f", key, p.length, p.width, p.height, p.radius))
        end
    end
end)

concommand.Add("vnpcs_test_fixed_pose", function(ply)
    if not IsValid(ply) then return end
    local target = ply:GetEyeTrace().Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsNextBot() or target.IsDrGNextbot) then
        ply:ChatPrint("[V-NPCs] Aim at a predator to apply the generated fixed bone pose!")
        return
    end
    VNPC_FixedPoseCache[VNPC_GetBodyPartCacheKey(target)] = nil
    if VNPC_ApplyFixedBonePose(target) then
        local parts = target.VNPC_BodyParts
        ply:ChatPrint(string.format("[V-NPCs] Applied generated fixed pose on %s (torso W/H %.1f/%.1f, clearance %.1f)",
            tostring(target), parts and parts.torso.width or 0, parts and parts.torso.height or 0, parts and parts.clearance or 0))
    else
        ply:ChatPrint("[V-NPCs] Failed to generate a fixed bone pose on " .. tostring(target))
    end
end)
