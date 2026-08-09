--[[
    Shared ConVars and Helpers for Female Model NPCs Vore
]]

CreateConVar("vnpcs_female_model_vore", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Give female model NPCs vore capabilities")
CreateConVar("vnpcs_female_model_vore_range", "600", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Prey detection range for female model NPCs")
CreateConVar("vnpcs_female_model_vore_grab_range", "75", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Grab range for female model NPCs")

VNPC_FIXED_FEMALE_BELLY_OFFSET = Vector(0, 3.5, 0)
VNPC_FIXED_FEMALE_BELLY_ANGLES = Angle(0, 90, 90)

CreateConVar("vnpcs_female_model_vore_offset_x", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Belly X offset for female model NPCs")
CreateConVar("vnpcs_female_model_vore_offset_y", "3.5", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Belly Y offset for female model NPCs")
CreateConVar("vnpcs_female_model_vore_offset_z", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Belly Z offset for female model NPCs")

CreateConVar("vnpcs_belly_rt_enabled", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Enable Belly RT texturing")
CreateConVar("vnpcs_belly_rt_size", "512", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Belly RT texture resolution (128, 256, 512, 1024)")
CreateConVar("vnpcs_belly_rt_max_captures", "99", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Max Belly RT captures per frame when idle")
CreateConVar("vnpcs_belly_rt_battle_captures", "99", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Max Belly RT captures per frame during battle")
CreateConVar("vnpcs_belly_rt_poll_rate", "0.15", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Poll rate (seconds) for Belly RT signature changes")
CreateConVar("vnpcs_belly_rt_battle_poll_rate", "0.05", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Poll rate (seconds) during battle")

if SERVER then
    util.AddNetworkString("VNPCS_BellyRT_Command")
end

concommand.Add("vnpcs_belly_rt_battle_preset", function(ply)
    GetConVar("vnpcs_belly_rt_size"):SetInt(256)
    GetConVar("vnpcs_belly_rt_max_captures"):SetInt(99)
    GetConVar("vnpcs_belly_rt_battle_captures"):SetInt(99)
    GetConVar("vnpcs_belly_rt_poll_rate"):SetFloat(0.3)
    GetConVar("vnpcs_belly_rt_battle_poll_rate"):SetFloat(0.1)
    if SERVER then
        net.Start("VNPCS_BellyRT_Command")
        net.WriteString("clear")
        net.Broadcast()
    elseif VNPCS_BellyRT and VNPCS_BellyRT.ClearAll then
        VNPCS_BellyRT.ClearAll()
    end
    local msg = "[V-NPCs] Applied Large Battle RT Preset (256px, unlimited captures/frame, optimized polling)."
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
end)

concommand.Add("vnpcs_belly_rt_default_preset", function(ply)
    GetConVar("vnpcs_belly_rt_size"):SetInt(512)
    GetConVar("vnpcs_belly_rt_max_captures"):SetInt(99)
    GetConVar("vnpcs_belly_rt_battle_captures"):SetInt(99)
    GetConVar("vnpcs_belly_rt_poll_rate"):SetFloat(0.15)
    GetConVar("vnpcs_belly_rt_battle_poll_rate"):SetFloat(0.05)
    if SERVER then
        net.Start("VNPCS_BellyRT_Command")
        net.WriteString("clear")
        net.Broadcast()
    elseif VNPCS_BellyRT and VNPCS_BellyRT.ClearAll then
        VNPCS_BellyRT.ClearAll()
    end
    local msg = "[V-NPCs] Restored Default Belly RT Settings (512px, unlimited captures/frame)."
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
end)

concommand.Add("vnpcs_belly_rt_refresh", function(ply)
    if SERVER then
        net.Start("VNPCS_BellyRT_Command")
        net.WriteString("refresh")
        net.Broadcast()
    elseif VNPCS_BellyRT and VNPCS_BellyRT.RefreshAll then
        VNPCS_BellyRT.RefreshAll()
    end
    local msg = "[V-NPCs] Marked all Belly RT textures dirty for refresh."
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
end)

concommand.Add("vnpcs_belly_rt_clear", function(ply)
    if SERVER then
        net.Start("VNPCS_BellyRT_Command")
        net.WriteString("clear")
        net.Broadcast()
    elseif VNPCS_BellyRT and VNPCS_BellyRT.ClearAll then
        VNPCS_BellyRT.ClearAll()
    end
    local msg = "[V-NPCs] Cleared all Belly RT cached states and duplicate models."
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
end)

if CLIENT then
    net.Receive("VNPCS_BellyRT_Command", function()
        local cmd = net.ReadString()
        if cmd == "refresh" and VNPCS_BellyRT and VNPCS_BellyRT.RefreshAll then
            VNPCS_BellyRT.RefreshAll()
        elseif cmd == "clear" and VNPCS_BellyRT and VNPCS_BellyRT.ClearAll then
            VNPCS_BellyRT.ClearAll()
        end
    end)
end

function VNPC_GetFixedFemaleBellyOffset(ent)
    local x = GetConVar("vnpcs_female_model_vore_offset_x"):GetFloat() or 0
    local y = GetConVar("vnpcs_female_model_vore_offset_y"):GetFloat() or 3.5
    local z = GetConVar("vnpcs_female_model_vore_offset_z"):GetFloat() or 0
    return Vector(x, y, z)
end

VNPC_FemaleBoneCache = VNPC_FemaleBoneCache or {}

function VNPC_HasFemaleModelBones(ent)
    if not IsValid(ent) then return false end
    local mdl = string.lower(ent:GetModel() or "")
    if mdl ~= "" and VNPC_FemaleBoneCache[mdl] ~= nil then
        return VNPC_FemaleBoneCache[mdl]
    end

    if ent.SetupBones then pcall(ent.SetupBones, ent) end
    if not ent.LookupBone or not ent.GetBoneCount then return false end
    
    local female_bone_names = {
        "ValveBiped.Bip01_L_Breast0",
        "ValveBiped.Bip01_L_Breast1",
        "ValveBiped.Bip01_R_Breast0",
        "ValveBiped.Bip01_R_Breast1",
        "ValveBiped.Bip01_L_Breast",
        "ValveBiped.Bip01_R_Breast",
        "ValveBiped.Bip01_Spinebut",
        "ValveBiped.Bip01_SpineBut",
        "ValveBiped.Bip01_lpectoral",
        "ValveBiped.Bip01_rpectoral",
        "Bip01_L_Breast0",
        "Bip01_R_Breast0",
        "Bip01_L_Breast",
        "Bip01_R_Breast",
        "Bip01_lpectoral",
        "Bip01_rpectoral",
        "L_Breast",
        "R_Breast",
        "l_breast",
        "r_breast",
        "breast0",
        "breast1",
        "boob_l",
        "boob_r",
        "lpectoral",
        "rpectoral"
    }

    for _, bone_name in ipairs(female_bone_names) do
        local bone = ent:LookupBone(bone_name)
        if bone and bone >= 0 then
            if mdl ~= "" then VNPC_FemaleBoneCache[mdl] = true end
            return true
        end
    end

    local count = ent:GetBoneCount() or 0
    for i = 0, count - 1 do
        local name = string.lower(ent:GetBoneName(i) or "")
        if name:find("breast") or name:find("boob") or name:find("spinebut") or name:find("lpectoral") or name:find("rpectoral") or name:find("ponytail") or name:find("pigtail") or name:find("skirt") or name:find("dress") or name:find("mamma") or name:find("bust") then
            if mdl ~= "" then VNPC_FemaleBoneCache[mdl] = true end
            return true
        end
    end

    if count > 0 and mdl ~= "" then
        VNPC_FemaleBoneCache[mdl] = false
    end
    return false
end

function VNPC_IsFemaleModelNPC(ent)
    if not IsValid(ent) or not ent:IsNPC() then return false end
    if ent.IsDrGNextbot or ent.Base == "npc_vore_base" then return false end
    if ent:GetClass():find("func_") or ent:IsWeapon() or ent:IsPlayer() then return false end
    if VNPC_HasFemaleModelBones(ent) then return true end
    local mdl = string.lower(ent:GetModel() or "")
    return (mdl:find("female") or mdl:find("alyx") or mdl:find("mossman")) ~= nil
end

function VNPC_ClearPatrols(ent)
    if not IsValid(ent) then return end
    if ent.ClearPatrols and isfunction(ent.ClearPatrols) then
        pcall(ent.ClearPatrols, ent)
    elseif ent.ClearSchedule then
        pcall(ent.ClearSchedule, ent)
    elseif ent.SetSchedule then
        pcall(ent.SetSchedule, ent, SCHED_IDLE_STAND)
    end
end

-- Female Model Faces (Vore Flex Phases) and Head Turning
VNPC_FEMALE_EYE_BONE = "ValveBiped.Bip01_Head1"

VNPC_FEMALE_FLEX_FACES = {
    [0] = { -- Neutral (rest)
        ["right_puckerer"] = 0, ["left_puckerer"] = 0,
        ["right_stretcher"] = 0, ["left_stretcher"] = 0,
        ["right_mouth_drop"] = 0, ["left_mouth_drop"] = 0,
        ["right_corner_puller"] = 0, ["left_corner_puller"] = 0,
        ["jaw_drop"] = 0, ["jaw_sideways"] = 0.5,
        ["left_lid_closer"] = 0, ["mouth_sideways"] = 0.5,
        ["blink"] = 0,
        ["right_lid_tightener"] = 0, ["right_lid_droop"] = 0, ["left_lid_droop"] = 0,
        ["right_inner_raiser"] = 0, ["right_lowerer"] = 0, ["left_inner_raiser"] = 0,
        ["smile"] = 0.1, ["smirk"] = 0
    },
    [1] = { -- Swallowing
        ["right_puckerer"] = 0, ["left_puckerer"] = 0,
        ["right_stretcher"] = 1, ["left_stretcher"] = 1,
        ["right_mouth_drop"] = 0.7, ["left_mouth_drop"] = 0.7,
        ["right_corner_puller"] = 0.7, ["left_corner_puller"] = 0.7,
        ["jaw_drop"] = 1.5, ["jaw_sideways"] = 0.5,
        ["left_lid_closer"] = 0, ["mouth_sideways"] = 0.5,
        ["blink"] = 1,
        ["open_mouth"] = 1.0, ["smile"] = 0, ["smirk"] = 0
    },
    [2] = { -- Digesting / Absorbing
        ["right_puckerer"] = 0, ["left_puckerer"] = 0,
        ["right_stretcher"] = 0, ["left_stretcher"] = 0,
        ["right_mouth_drop"] = 0, ["left_mouth_drop"] = 0,
        ["right_corner_puller"] = 0, ["left_corner_puller"] = 0,
        ["jaw_drop"] = 0, ["jaw_sideways"] = 0.5, ["mouth_sideways"] = 0.5,
        ["left_lid_closer"] = 0, ["blink"] = 0,
        ["right_inner_raiser"] = 0.5, ["left_inner_raiser"] = 0.5,
        ["right_lowerer"] = 0, ["right_lid_droop"] = 0.8, ["left_lid_droop"] = 0.8,
        ["smile"] = 0.5, ["smirk"] = 0.4
    },
    [3] = { -- Burping
        ["jaw_drop"] = 1.7,
        ["right_mouth_drop"] = 0.9, ["left_mouth_drop"] = 0.9,
        ["jaw_sideways"] = 0.5, ["left_lid_closer"] = 0.5, ["mouth_sideways"] = 0.5,
        ["blink"] = 0,
        ["right_lid_tightener"] = 1, ["right_lid_droop"] = 1, ["left_lid_droop"] = 1,
        ["right_inner_raiser"] = 1, ["right_lowerer"] = 1, ["left_inner_raiser"] = 0,
        ["open_mouth"] = 0.8, ["smile"] = 0, ["smirk"] = 0
    },
    [4] = { -- Gulping / Glupping
        ["mouth_sideways"] = 0.5, ["blink"] = 1,
        ["jaw_drop"] = 0.5, ["smile"] = 0.2
    }
}

function VNPC_FemaleCustomHeadTurn(ent, yaw, pitch, roll)
    return Angle(pitch * 0.8, -yaw * 0.9, roll * 0.5)
end

function VNPC_ApplyFemaleModelFacesAndTurn(ent)
    if not IsValid(ent) then return end
    ent.EyeBone = ent.EyeBone or VNPC_FEMALE_EYE_BONE
    ent.VoreSettings = ent.VoreSettings or {}
    ent.VoreSettings.FlexFaces = VNPC_FEMALE_FLEX_FACES
    if CLIENT then
        ent.CustomHeadTurn = function(self, yaw, pitch, roll)
            return VNPC_FemaleCustomHeadTurn(self, yaw, pitch, roll)
        end
    end
end

hook.Add("OnEntityCreated", "VNPC_AutoFemaleModelFacesAndTurn", function(ent)
    timer.Simple(0.1, function()
        if not IsValid(ent) then return end
        if VNPC_IsFemaleModelNPC(ent) or ent.VNPC_FemaleModelVore then
            VNPC_ApplyFemaleModelFacesAndTurn(ent)
        end
    end)
end)

-- Weight Gain Bones & Settings for Female Model NPCs (matching VNPCs)
VNPC_FEMALE_WEIGHT_GAIN_BONES = {
    "ValveBiped.Bip01_L_Breast0",
    "ValveBiped.Bip01_L_Breast1",
    "ValveBiped.Bip01_R_Breast0",
    "ValveBiped.Bip01_R_Breast1",
    "ValveBiped.Bip01_lpectoral",
    "ValveBiped.Bip01_rpectoral",
    "ValveBiped.Bip01_Lpectoral",
    "ValveBiped.Bip01_Rpectoral",
    "ValveBiped.Bip01_L_Thigh",
    "ValveBiped.Bip01_R_Thigh",
    "ValveBiped.Bip01_L_Calf",
    "ValveBiped.Bip01_R_Calf",
    "ValveBiped.Bip01_L_Forearm",
    "ValveBiped.Bip01_R_Forearm",
    "ValveBiped.Bip01_Spinebut",
    "ValveBiped.Bip01_Pelvis",
    "ValveBiped.Bip01_Spine",
    "ValveBiped.Bip01_Spine1",
    "ValveBiped.Bip01_Spine4"
}

VNPC_FEMALE_WEIGHT_GAIN_SETTINGS = {
    MaxBoob = 2.2,
    MaxThigh = 1.5,
    MaxCalf = 1.3,
    MaxArm = 1.1,
    MaxSpine = 1.1,
    MaxWaist = 1.3,
    MaxSpine4 = 2,
    BoobMultiplier = 1.5,
    ThighMultiplier = 1,
    CalfMultiplier = 0.7,
    ArmMultiplier = 0.5,
    SpineMultiplier = 0.2,
    WaistMultiplier = 0.4
}

local function VNPC_WhatIsBone(boneName, definers) 
    boneName = string.lower(boneName)
    if definers then
        for ident, _ in pairs(definers) do
            if boneName:find(string.lower(ident)) then
                return ident
            end
        end
    end
    if boneName:find("breast") or boneName:find("boob") or boneName:find("pectoral") or boneName:find("pec") or boneName:find("lpectoral") or boneName:find("rpectoral") then
        return "Boob"
    elseif boneName:find("thigh") or boneName:find("leg_bone1") then
        return "Thigh"
    elseif boneName:find("calf") or boneName:find("leg_bone3") then
        return "Calf"
    elseif boneName:find("arm") then
        return "Arm"
    elseif boneName:find("pelvis") or boneName:find("hips") or boneName:find("butt") then
        return "Waist"
    elseif boneName:find("spine") then
        return "Spine"
    end
    return "Unknown"
end

local pectoral_bone_names = {
    "ValveBiped.Bip01_L_Pectoral",
    "ValveBiped.Bip01_R_Pectoral",
    "ValveBiped.Bip01_L_Pectoral0",
    "ValveBiped.Bip01_R_Pectoral0",
    "Bip01_L_Pectoral",
    "Bip01_R_Pectoral",
    "L_Pectoral",
    "R_Pectoral",
    "l_pectoral",
    "r_pectoral",
    "pectoral0",
    "pectoral1",
    "pec_l",
    "pec_r",
    "ValveBiped.Bip01_lpectoral",
    "ValveBiped.Bip01_rpectoral",
    "ValveBiped.Bip01_Lpectoral",
    "ValveBiped.Bip01_Rpectoral",
    "Bip01_lpectoral",
    "Bip01_rpectoral",
    "lpectoral",
    "rpectoral",
    "Lpectoral",
    "Rpectoral"
}

function VNPC_EnsurePectoralBonesInWeightGain(ent, bones)
    if not IsValid(ent) or not bones then return end
    if ent._VNPCCheckedPectoralBones then return end
    ent._VNPCCheckedPectoralBones = true

    local existing = {}
    for _, name in ipairs(bones) do
        existing[string.lower(name)] = true
    end

    for _, name in ipairs(pectoral_bone_names) do
        local boneID = ent:LookupBone(name)
        if boneID and not existing[string.lower(name)] then
            table.insert(bones, name)
            existing[string.lower(name)] = true
        end
    end

    local count = ent:GetBoneCount() or 0
    for i = 0, count - 1 do
        local name = ent:GetBoneName(i)
        if name then
            local lower_name = string.lower(name)
            if (lower_name:find("pectoral") or lower_name:find("pec_") or lower_name:find("_pec") or lower_name:find("lpectoral") or lower_name:find("rpectoral")) and not existing[lower_name] then
                table.insert(bones, name)
                existing[lower_name] = true
            end
        end
    end
end

function VNPC_DoVisualBonescale(ent, _bonescale)
    if not IsValid(ent) then return end
    local setting = (ent.VoreSettings and ent.VoreSettings.WeightGainSettings) or VNPC_FEMALE_WEIGHT_GAIN_SETTINGS
    local definers = ent.VoreSettings and ent.VoreSettings.WeightGainDefiners
    local bones = (ent.VoreSettings and ent.VoreSettings.WeightGainBones) or VNPC_FEMALE_WEIGHT_GAIN_BONES
    VNPC_EnsurePectoralBonesInWeightGain(ent, bones)

    for _, boneName in ipairs(bones) do
        local boneID = ent:LookupBone(boneName)
        if not boneID then continue end

        local is = VNPC_WhatIsBone(boneName, definers)
        local multiplier = 0.5
        local max = 1.5
        if setting[is.."Multiplier"] then
            multiplier = tonumber(setting[is.."Multiplier"]) or 0.5
        end
        if setting["Max"..is] then
            max = tonumber(setting["Max"..is]) or 1.5
        end

        local actual_scale = _bonescale + (multiplier - 1) * (_bonescale - 1)
        local scaleVec, posAdjust
        if definers and definers[is] then
            scaleVec, posAdjust = definers[is](actual_scale, max) 
        elseif is == "Boob" then
            local boobScale = math.min(actual_scale, 2.8 * max)
            scaleVec = Vector(boobScale, boobScale, boobScale)
        elseif is == "Waist" then
            scaleVec = Vector(
                math.min(actual_scale, 1.3 * max),
                math.min(actual_scale, 1.4 * max),
                math.min(actual_scale, 1.6 * max)
            )
        elseif is == "Spine" then
            scaleVec = Vector(
                math.min(actual_scale, 1.6 * max),
                math.min(actual_scale, 1),
                math.min(actual_scale, 1.6 * max)
            )
        else
            scaleVec = Vector(
                math.min(actual_scale, 1),
                math.min(actual_scale, 1.6 * max),
                math.min(actual_scale, 1.6 * max)
            )
        end

        ent:ManipulateBoneScale(boneID, scaleVec)
        if posAdjust then
            ent:ManipulateBonePosition(boneID, posAdjust, true)
        end
    end
end

if CLIENT then
    hook.Add("Think", "VNPC_FemaleModelVore_ClientWeightGain", function()
        local _dt = FrameTime()
        for _, ent in ipairs(ents.FindByClass("npc_*")) do
            if not IsValid(ent) then continue end
            if not (VNPC_IsFemaleModelNPC(ent) or ent.VNPC_FemaleModelVore) then continue end

            local current_scale = ent:GetNWFloat("Bonescale", 1)
            local oldVisual = ent.VisualBonescale

            local sped = 3
            local bonescale_lerp = 1 - math.exp(-sped * _dt)
            ent.VisualBonescale = Lerp(bonescale_lerp, ent.VisualBonescale or current_scale, current_scale)

            if oldVisual ~= ent.VisualBonescale then
                VNPC_DoVisualBonescale(ent, ent.VisualBonescale)
            end
        end
    end)
end

-- Native Vore Gesture Animations
VNPC_NATIVE_GESTURES = {
    ["swallow"] = {
        acts = {
            ACT_GMOD_GESTURE_TAUNT_ZOMBIE,
            ACT_HL2MP_GESTURE_RELOAD_MELEE,
            ACT_GMOD_GESTURE_MELEE_ATTACK_SWING,
            ACT_HL2MP_GESTURE_RANGE_ATTACK_MELEE,
            ACT_GESTURE_MELEE_ATTACK1
        },
        sequences = {
            "gesture_melee_attack1", "swing", "g_melee_hit", "taunt_zombie", "cheer"
        }
    },
    ["burp"] = {
        acts = {
            ACT_HL2MP_GESTURE_TAUNT_CHEST_THUMP,
            ACT_HL2MP_GESTURE_TAUNT_SALUTE,
            ACT_GMOD_GESTURE_TAUNT_CHEER,
            ACT_SIGNAL_HALT,
            ACT_FLINCH_CHEST
        },
        sequences = {
            "chest_thump", "taunt_chest_thump", "salute", "gesture_signal_halt", "flinch_chest"
        }
    },
    ["rub_belly"] = {
        acts = {
            ACT_FLINCH_STOMACH,
            ACT_HL2MP_GESTURE_TAUNT_CHEST_THUMP,
            ACT_SIGNAL_HALT
        },
        sequences = {
            "flinch_stomach", "stomach_flinch", "gesture_flinch_stomach", "idle_subtle"
        }
    },
    ["struggle_flinch"] = {
        acts = {
            ACT_FLINCH_STOMACH,
            ACT_FLINCH_PHYSICS,
            ACT_FLINCH_CHEST
        },
        sequences = {
            "flinch_stomach", "gesture_flinch_stomach", "flinch_01", "flinch_02"
        }
    }
}

VNPC_NativeSequenceCache = VNPC_NativeSequenceCache or {}

local GESTURE_DISCOVERY_KEYWORDS = {
    ["swallow"] = {
        "swallow", "gulp", "eat", "vore", "bite", "chew", "consume", "attack_melee", "melee_attack", "swing", "slash"
    },
    ["burp"] = {
        "burp", "belch", "thump", "chest", "pat", "salute", "taunt", "cheer", "halt", "signal"
    },
    ["rub_belly"] = {
        "rub", "belly", "stomach", "caress", "pat", "idle_subtle", "subtle", "flinch_stomach", "stomach_flinch"
    },
    ["struggle_flinch"] = {
        "flinch_stomach", "stomach_flinch", "stomach", "belly", "flinch", "hit", "react", "pain", "hurt"
    }
}

function VNPC_DiscoverNativeSequence(ent, gesture_type)
    if not IsValid(ent) then return -1, nil end
    local mdl = string.lower(ent:GetModel() or "")
    if mdl ~= "" and VNPC_NativeSequenceCache[mdl] and VNPC_NativeSequenceCache[mdl][gesture_type] then
        local cached = VNPC_NativeSequenceCache[mdl][gesture_type]
        if cached == -1 then return -1, nil end
        return cached.id, cached.name
    end

    local gesture_info = VNPC_NATIVE_GESTURES[gesture_type]
    if gesture_info and gesture_info.sequences then
        for _, seq_name in ipairs(gesture_info.sequences) do
            local seq = ent:LookupSequence(seq_name)
            if seq and seq >= 0 then
                if mdl ~= "" then
                    VNPC_NativeSequenceCache[mdl] = VNPC_NativeSequenceCache[mdl] or {}
                    VNPC_NativeSequenceCache[mdl][gesture_type] = { id = seq, name = seq_name }
                end
                return seq, seq_name
            end
        end
    end

    -- Scan sequence list by keywords
    local keywords = GESTURE_DISCOVERY_KEYWORDS[gesture_type]
    if keywords and ent.GetSequenceList then
        local seq_list = ent:GetSequenceList()
        if seq_list and istable(seq_list) then
            for _, seq_name in ipairs(seq_list) do
                local lower_seq = string.lower(seq_name)
                for _, kw in ipairs(keywords) do
                    if lower_seq:find(kw) then
                        local seq = ent:LookupSequence(seq_name)
                        if seq and seq >= 0 then
                            if mdl ~= "" then
                                VNPC_NativeSequenceCache[mdl] = VNPC_NativeSequenceCache[mdl] or {}
                                VNPC_NativeSequenceCache[mdl][gesture_type] = { id = seq, name = seq_name }
                            end
                            return seq, seq_name
                        end
                    end
                end
            end
        end
    end

    -- Scan by sequence count if GetSequenceList is not available
    if keywords and ent.GetSequenceCount and ent.GetSequenceName then
        local count = ent:GetSequenceCount() or 0
        for seq_id = 0, count - 1 do
            local seq_name = ent:GetSequenceName(seq_id)
            if seq_name then
                local lower_seq = string.lower(seq_name)
                for _, kw in ipairs(keywords) do
                    if lower_seq:find(kw) then
                        if mdl ~= "" then
                            VNPC_NativeSequenceCache[mdl] = VNPC_NativeSequenceCache[mdl] or {}
                            VNPC_NativeSequenceCache[mdl][gesture_type] = { id = seq_id, name = seq_name }
                        end
                        return seq_id, seq_name
                    end
                end
            end
        end
    end

    if mdl ~= "" then
        VNPC_NativeSequenceCache[mdl] = VNPC_NativeSequenceCache[mdl] or {}
        VNPC_NativeSequenceCache[mdl][gesture_type] = -1
    end
    return -1, nil
end

-- Bone-Pose Vore Animations Engine
CreateConVar("vnpcs_bone_pose_animations", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Enable procedural bone-pose vore animations")

VNPC_BONE_POSE_ANIMATIONS = {
    ["swallow"] = {
        pose_params = {
            ["head_pitch"] = -15,
            ["aim_pitch"] = -15,
            ["mouth"] = 1.0,
            ["jaw_drop"] = 1.0
        },
        bone_angles = {
            ["ValveBiped.Bip01_Head1"] = Angle(-15, 0, 0),
            ["ValveBiped.Bip01_Spine2"] = Angle(-8, 0, 0)
        },
        duration = 1.2
    },
    ["burp"] = {
        pose_params = {
            ["head_pitch"] = -10,
            ["mouth"] = 0.8,
            ["jaw_drop"] = 1.0
        },
        bone_angles = {
            ["ValveBiped.Bip01_Head1"] = Angle(-10, 0, 0),
            ["ValveBiped.Bip01_Spine2"] = Angle(5, 0, 0)
        },
        duration = 1.0
    },
    ["rub_belly"] = {
        pose_params = {
            ["aim_pitch"] = 10
        },
        bone_angles = {
            ["ValveBiped.Bip01_Spine1"] = Angle(3, 0, 0)
        },
        duration = 2.0
    },
    ["struggle_flinch"] = {
        pose_params = {
            ["body_yaw"] = 5
        },
        bone_angles = {
            ["ValveBiped.Bip01_Spine2"] = Angle(6, 0, 5),
            ["ValveBiped.Bip01_Spine1"] = Angle(-4, 0, -3)
        },
        duration = 0.5
    }
}

function VNPC_PlayBonePoseAnimation(ent, anim_type)
    if not IsValid(ent) then return false end
    local enabled = GetConVar("vnpcs_bone_pose_animations")
    if enabled and not enabled:GetBool() then return false end

    local anim = VNPC_BONE_POSE_ANIMATIONS[anim_type]
    if not anim then return false end

    if anim.pose_params and ent.SetPoseParameter then
        for param, val in pairs(anim.pose_params) do
            pcall(ent.SetPoseParameter, ent, param, val)
        end
    end

    local applied_bones = {}
    if anim.bone_angles then
        for bone_name, ang in pairs(anim.bone_angles) do
            local boneID = ent:LookupBone(bone_name)
            if boneID and boneID >= 0 then
                ent:ManipulateBoneAngles(boneID, ang)
                table.insert(applied_bones, boneID)
            end
        end
    end

    local duration = anim.duration or 1.0
    timer.Simple(duration, function()
        if not IsValid(ent) then return end
        if anim.pose_params and ent.SetPoseParameter then
            for param, _ in pairs(anim.pose_params) do
                pcall(ent.SetPoseParameter, ent, param, 0)
            end
        end
        for _, boneID in ipairs(applied_bones) do
            if IsValid(ent) and ent.ManipulateBoneAngles then
                ent:ManipulateBoneAngles(boneID, Angle(0, 0, 0))
            end
        end
    end)

    return true
end

function VNPC_PlayNativeVoreGesture(ent, gesture_type)
    if not IsValid(ent) then return false end
    -- Replace vore sequences with bone poses
    return VNPC_PlayBonePoseAnimation(ent, gesture_type)
end

-- Additional ConVars for female model vore enhancements
CreateConVar("vnpcs_female_model_vore_eat_corpses", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Allow female model NPCs to eat corpses and ragdolls")
CreateConVar("vnpcs_female_model_vore_ragdoll_range", "150", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Ragdoll scan range for female model NPCs")
CreateConVar("vnpcs_female_model_vore_regurgitate_dmg", "0.3", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Damage fraction threshold to trigger regurgitation")
CreateConVar("vnpcs_female_model_vore_debug_overlay", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Enable 3D debug overlay for female model vore NPCs")

if CLIENT then
    hook.Add("CalcView", "VNPC_FemaleModelVore_InternalView", function(ply, pos, angles, fov)
        if not IsValid(ply) or not (ply.Vored or ply.VNPC_Vored) then return end
        local parent = ply:GetParent()
        if IsValid(parent) and (parent.VNPC_FemaleModelVore or VNPC_IsFemaleModelNPC(parent)) then
            local t = CurTime() * 2
            local offset = Vector(math.sin(t) * 2, math.cos(t) * 2, math.sin(t * 0.7))
            local ang_offset = Angle(math.sin(t * 1.5), math.cos(t * 1.2), math.sin(t) * 3)
            return {
                origin = parent:GetPos() + Vector(0, 0, 35) + offset,
                angles = angles + ang_offset,
                fov = fov - 10,
                drawviewer = true
            }
        end
    end)

    hook.Add("HUDPaint", "VNPC_FemaleModelVore_SwallowedHUD", function()
        local ply = LocalPlayer()
        if not IsValid(ply) or not (ply.Vored or ply.VNPC_Vored) then return end
        local parent = ply:GetParent()
        if IsValid(parent) and (parent.VNPC_FemaleModelVore or VNPC_IsFemaleModelNPC(parent)) then
            local w, h = ScrW(), ScrH()
            surface.SetDrawColor(180, 20, 40, 60)
            surface.DrawRect(0, 0, w, h)
            draw.SimpleText("YOU HAVE BEEN SWALLOWED", "DermaLarge", w * 0.5, h * 0.15, Color(255, 80, 80, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            local pred_name = parent.PrintName or parent:GetClass()
            draw.SimpleText("Predator: " .. pred_name, "DermaDefaultBold", w * 0.5, h * 0.20, Color(255, 200, 200, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end)

    hook.Add("EntityEmitSound", "VNPC_FemaleModelVore_MuffleAudio", function(info)
        local ply = LocalPlayer()
        if not IsValid(ply) or not (ply.Vored or ply.VNPC_Vored) then return end
        local parent = ply:GetParent()
        if IsValid(parent) and (parent.VNPC_FemaleModelVore or VNPC_IsFemaleModelNPC(parent)) then
            info.DSP = 15 -- Muffled underwater DSP
            return true
        end
    end)

    hook.Add("PostDrawTranslucentRenderables", "VNPC_FemaleModelVore_DebugOverlay", function()
        local debug_cv = GetConVar("vnpcs_female_model_vore_debug_overlay")
        if not debug_cv or not debug_cv:GetBool() then return end
        
        for _, npc in ipairs(ents.FindByClass("npc_*")) do
            if not IsValid(npc) or not npc.VNPC_FemaleModelVore then continue end
            local pos = npc:WorldSpaceCenter()
            local ang = EyeAngles()
            ang:RotateAroundAxis(ang:Forward(), 90)
            ang:RotateAroundAxis(ang:Right(), 90)
            
            cam.Start3D2D(pos + Vector(0, 0, 30), ang, 0.2)
                draw.SimpleText("VNPC: " .. npc:GetClass(), "DermaDefaultBold", 0, 0, Color(255, 255, 0), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                local bsize = IsValid(npc.VNPC_Belly) and (npc.VNPC_Belly.BaseScale or 0) or 0
                draw.SimpleText(string.format("Belly Size: %.2f", bsize), "DermaDefault", 0, 16, Color(255, 150, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                local prey_count = (IsValid(npc.VNPC_Belly) and npc.VNPC_Belly.Prey) and #npc.VNPC_Belly.Prey or 0
                draw.SimpleText(string.format("Prey Count: %d", prey_count), "DermaDefault", 0, 32, Color(255, 100, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            cam.End3D2D()
        end
    end)
end

-- Clumped Prey Group Vore
CreateConVar("vnpcs_clumped_vore_enabled", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Enable clumped prey group vore")
CreateConVar("vnpcs_clumped_vore_radius", "75", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Search radius around target for clumped prey")
CreateConVar("vnpcs_clumped_vore_max_group", "4", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Max prey items swallowed in a clumped group")

function VNPC_GetClumpedPreyGroup(pred, target)
    local group = { target }
    if not IsValid(pred) or not IsValid(target) then return group end
    local enabled = GetConVar("vnpcs_clumped_vore_enabled")
    if enabled and not enabled:GetBool() then return group end

    local radius = GetConVar("vnpcs_clumped_vore_radius"):GetFloat() or 75
    local max_count = GetConVar("vnpcs_clumped_vore_max_group"):GetInt() or 4

    for _, ent in ipairs(ents.FindInSphere(target:GetPos(), radius)) do
        if #group >= max_count then break end
        if IsValid(ent) and ent ~= pred and ent ~= target and not ent.Vored and not ent.VNPC_Vored then
            local is_valid_prey = (ent:IsPlayer() or ent:IsNPC() or (ent:GetClass() == "prop_ragdoll" or ent.VNPC_IsCorpse))
            if is_valid_prey then
                if pred.EatCondition and not pred:EatCondition(ent) then continue end
                if pred.IsFemaleModel and not pred:IsFemaleModel() then continue end
                table.insert(group, ent)
            end
        end
    end
    return group
end

-- Universal Bone-Pose Vore Animations Engine (AnimatedBoneList & Keyframes)
local function VNPC_LerpAngle(t, ang1, ang2)
    return Angle(
        Lerp(t, ang1.p, ang2.p),
        Lerp(t, ang1.y, ang2.y),
        Lerp(t, ang1.r, ang2.r)
    )
end

VNPC_DefaultAnimatedBoneList = {
    [0] = { -- rest
        ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_Spine"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_Spine1"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_R_Clavicle"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_R_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_L_Clavicle"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_L_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_R_Thigh"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_R_Calf"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_L_Thigh"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_L_Calf"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_Pelvis"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) }
    },
    [1] = { -- swallow
        ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(0, 30, 0) },
        ["ValveBiped.Bip01_Spine"] = { pos = Vector(0, 0, 0), ang = Angle(0, -10, 0) },
        ["ValveBiped.Bip01_Spine1"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_R_Clavicle"] = { pos = Vector(0, 0, 0), ang = Angle(0, 30, 0) },
        ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(40, 0, 0) },
        ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(150, 50, 130) },
        ["ValveBiped.Bip01_R_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(-10, 0, 100) },
        ["ValveBiped.Bip01_L_Clavicle"] = { pos = Vector(0, 0, 0), ang = Angle(0, -30, 0) },
        ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(-40, 0, 0) },
        ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-150, 50, -130) },
        ["ValveBiped.Bip01_L_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(10, 0, -100) },
        ["ValveBiped.Bip01_R_Thigh"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_R_Calf"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_L_Thigh"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_L_Calf"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_Pelvis"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) }
    },
    [2] = { -- full
        ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(-20, -30, 0) },
        ["eye_L"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 12) },
        ["eye_R"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 12) },
        ["ValveBiped.Bip01_Spine1"] = { pos = Vector(0, 0, 0), ang = Angle(0, -10, 0) },
        ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(-10, 30, -30) },
        ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(10, 10, -90) },
        ["ValveBiped.Bip01_R_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(-100, 40, 60) },
        ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(20, 20, -40) },
        ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(5, 20, -40) },
        ["ValveBiped.Bip01_L_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(-100, 40, 40) },
        ["ValveBiped.Bip01_R_Thigh"] = { pos = Vector(0, 0, 0), ang = Angle(20, -120, 0) },
        ["ValveBiped.Bip01_R_Calf"] = { pos = Vector(0, 0, 0), ang = Angle(-10, 90, 0) },
        ["ValveBiped.Bip01_R_Foot"] = { pos = Vector(0, 0, 0), ang = Angle(0, 50, 0) },
        ["ValveBiped.Bip01_L_Thigh"] = { pos = Vector(0, 0, 0), ang = Angle(-30, -120, 0) },
        ["ValveBiped.Bip01_L_Calf"] = { pos = Vector(2, 0, 0), ang = Angle(-15, 90, 0) },
        ["ValveBiped.Bip01_L_Foot"] = { pos = Vector(0, 0, 0), ang = Angle(0, 40, 0) },
        ["ValveBiped.Bip01_Pelvis"] = { pos = Vector(0, 0, -39.5), ang = Angle(0, 0, -15) }
    },
    [3] = { -- burp
        ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(-20, 20, 0) },
        ["eye_L"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 12) },
        ["eye_R"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 12) },
        ["ValveBiped.Bip01_Spine1"] = { pos = Vector(0, 0, 0), ang = Angle(0, -10, 0) },
        ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(-10, 30, -30) },
        ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(10, 10, -90) },
        ["ValveBiped.Bip01_R_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(-100, 40, 60) },
        ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(20, 20, -40) },
        ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(5, 20, -40) },
        ["ValveBiped.Bip01_L_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(-100, 40, 40) },
        ["ValveBiped.Bip01_R_Thigh"] = { pos = Vector(0, 0, 0), ang = Angle(20, -120, 0) },
        ["ValveBiped.Bip01_R_Calf"] = { pos = Vector(0, 0, 0), ang = Angle(-10, 90, 0) },
        ["ValveBiped.Bip01_R_Foot"] = { pos = Vector(0, 0, 0), ang = Angle(0, 50, 0) },
        ["ValveBiped.Bip01_L_Thigh"] = { pos = Vector(0, 0, 0), ang = Angle(-30, -120, 0) },
        ["ValveBiped.Bip01_L_Calf"] = { pos = Vector(2, 0, 0), ang = Angle(-15, 90, 0) },
        ["ValveBiped.Bip01_L_Foot"] = { pos = Vector(0, 0, 0), ang = Angle(0, 40, 0) },
        ["ValveBiped.Bip01_Pelvis"] = { pos = Vector(0, 0, -40), ang = Angle(0, 0, -15) }
    },
    [4] = { -- final gulp
        ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(-10, -10, 10) },
        ["ValveBiped.Bip01_Spine"] = { pos = Vector(0, 0, 0), ang = Angle(0, -10, 0) },
        ["ValveBiped.Bip01_Spine1"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_R_Clavicle"] = { pos = Vector(0, 0, 0), ang = Angle(0, 50, 0) },
        ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(70, 0, 0) },
        ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(150, -10, 0) },
        ["ValveBiped.Bip01_R_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(-10, 0, 90) },
        ["ValveBiped.Bip01_L_Clavicle"] = { pos = Vector(0, 0, 0), ang = Angle(0, -30, 0) },
        ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(-20, 0, 0) },
        ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-170, 50, -130) },
        ["ValveBiped.Bip01_L_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(-20, 0, -120) },
        ["ValveBiped.Bip01_R_Thigh"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_R_Calf"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_L_Thigh"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_L_Calf"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_Pelvis"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) }
    }
}

VNPC_ShyAnimatedBoneList = VNPC_DefaultAnimatedBoneList
VNPC_SHY_ANIMATED_BONE_LIST = VNPC_DefaultAnimatedBoneList

VNPC_BonfieAnimatedBoneList = {
    [0] = { -- rest
        ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_R_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_L_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["EyesLeft"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["EyesRight"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) }
    },
    [1] = { -- swallow
        ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(0, 10, 0) },
        ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(80, -10, 0) },
        ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(25, -100, 50) },
        ["ValveBiped.Bip01_R_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(30, -20, 20) },
        ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(-50, 20, 0) },
        ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-145, 40, -180) },
        ["ValveBiped.Bip01_L_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(-15, -20, -30) },
        ["EyesLeft"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["EyesRight"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) }
    },
    [2] = { -- full
        length = 1.0,
        keyframes = {
            [0.00] = {
                ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(0, -20, 0) },
                ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(10, -10, 0) },
                ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(155, 40, 150) },
                ["ValveBiped.Bip01_R_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(-10, -60, 20) },
                ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(-10, -10, 0) },
                ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-145, 40, -150) },
                ["ValveBiped.Bip01_L_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(5, -63, -15) },
                ["EyesLeft"] = { pos = Vector(-0.7, 0, 0), ang = Angle(0, 0, 0) },
                ["EyesRight"] = { pos = Vector(-0.7, 0, 0), ang = Angle(0, 0, 0) }
            },
            [0.50] = {
                ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(0, -20, 0) },
                ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(10, -10, 0) },
                ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(155, 40, 150) },
                ["ValveBiped.Bip01_R_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(-10, -60, 20) },
                ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(-10, -10, 0) },
                ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-145, 40, -150) },
                ["ValveBiped.Bip01_L_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(5, -63, -15) },
                ["EyesLeft"] = { pos = Vector(-0.7, 0, 0), ang = Angle(0, 0, 0) },
                ["EyesRight"] = { pos = Vector(-0.7, 0, 0), ang = Angle(0, 0, 0) }
            },
            [1.00] = {
                ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(0, -20, 0) },
                ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(10, -10, 0) },
                ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(155, 40, 150) },
                ["ValveBiped.Bip01_R_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(-10, -60, 20) },
                ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(-10, -10, 0) },
                ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-145, 40, -150) },
                ["ValveBiped.Bip01_L_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(5, -63, -15) },
                ["EyesLeft"] = { pos = Vector(-0.7, 0, 0), ang = Angle(0, 0, 0) },
                ["EyesRight"] = { pos = Vector(-0.7, 0, 0), ang = Angle(0, 0, 0) }
            }
        }
    },
    [3] = { -- burp
        ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(0, 5, 0) },
        ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(10, -10, 0) },
        ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(155, 30, 150) },
        ["ValveBiped.Bip01_R_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(-10, 30, 0) },
        ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(-10, -10, 0) },
        ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-145, 30, -150) },
        ["ValveBiped.Bip01_L_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(5, 30, 0) },
        ["EyesLeft"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["EyesRight"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) }
    },
    [4] = { -- final gulp
        ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(-10, 0, 0) },
        ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(40, -50, 0) },
        ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(5, -115, 0) },
        ["ValveBiped.Bip01_R_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(35, 70, 30) },
        ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(-70, 20, 0) },
        ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-145, 40, -180) },
        ["ValveBiped.Bip01_L_Hand"] = { pos = Vector(0, 0, 0), ang = Angle(0, -40, 0) },
        ["EyesLeft"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["EyesRight"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) }
    }
}

VNPC_BallerPuppyAnimatedBoneList = {
    [0] = { -- rest
        ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["eye_L"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["eye_R"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) },
        ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 0) }
    },
    [1] = { -- swallow
        ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(0, 20, 0) },
        ["eye_L"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, -12) },
        ["eye_R"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, -12) },
        ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(70, -30, 60) },
        ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-150, 40, -60) },
        ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(-90, -40, -60) },
        ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(150, 70, 60) }
    },
    [2] = { -- full
        ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(0, -30, 0) },
        ["eye_L"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 12) },
        ["eye_R"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 12) },
        ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(30, 40, -20) },
        ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(8, -100, -20) },
        ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(-30, 40, 20) },
        ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-8, -100, 20) }
    },
    [3] = { -- burp
        length = 1.0,
        keyframes = {
            [0.00] = {
                ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(0, 10, 0) },
                ["eye_L"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, -12) },
                ["eye_R"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, -12) },
                ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(35, 40, -20) },
                ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(8, -100, -20) },
                ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(-20, -60, 0) },
                ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(0, -90, -60) }
            },
            [0.50] = {
                ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(0, 10, 0) },
                ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(35, 40, -20) },
                ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(8, -100, -20) },
                ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(-20, -60, 0) },
                ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(0, -90, -60) }
            },
            [1.00] = {
                ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(0, 10, 0) },
                ["eye_L"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, -12) },
                ["eye_R"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, -12) },
                ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(35, 40, -20) },
                ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(8, -100, -20) },
                ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(-20, -60, 0) },
                ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(0, -90, -60) }
            }
        }
    },
    [4] = { -- final gulp
        ["ValveBiped.Bip01_Head1"] = { pos = Vector(0, 0, 0), ang = Angle(0, -10, 0) },
        ["eye_L"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 12) },
        ["eye_R"] = { pos = Vector(0, 0, 0), ang = Angle(0, 0, 12) },
        ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(20, -20, 70) },
        ["ValveBiped.Bip01_R_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(-140, 50, -110) },
        ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(0, 0, 0), ang = Angle(-40, -10, -30) },
        ["ValveBiped.Bip01_L_Forearm"] = { pos = Vector(0, 0, 0), ang = Angle(160, 80, 100) }
    }
}

VNPC_BoneMovesets = VNPC_BoneMovesets or {}
VNPC_BoneMovesets["default"] = VNPC_DefaultAnimatedBoneList
VNPC_BoneMovesets["bonfie"] = VNPC_BonfieAnimatedBoneList
VNPC_BoneMovesets["ballerpuppy"] = VNPC_BallerPuppyAnimatedBoneList

function VNPC_RegisterBoneMoveset(name, movesetTable)
    if not name or not istable(movesetTable) then return end
    VNPC_BoneMovesets = VNPC_BoneMovesets or {}
    VNPC_BoneMovesets[string.lower(name)] = movesetTable
end

CreateConVar("vnpcs_random_movesets", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Randomize 5-phase bone animation movesets for V-NPC predators")

function VNPC_AssignRandomMoveset(ent)
    if not IsValid(ent) then return end
    if ent.VNPC_AssignedMoveset then return end
    local keys = {}
    for k, v in pairs(VNPC_BoneMovesets or {}) do
        if istable(v) then
            table.insert(keys, k)
        end
    end
    if #keys > 0 then
        local pick = keys[math.random(1, #keys)]
        ent.VNPC_AssignedMoveset = pick
    end
end

function VNPC_GetAnimatedBoneList(ent)
    if not IsValid(ent) then return VNPC_DefaultAnimatedBoneList end
    if ent.AnimatedBoneList and istable(ent.AnimatedBoneList) then
        return ent.AnimatedBoneList
    end
    if ent.VoreSettings and ent.VoreSettings.AnimatedBoneList and istable(ent.VoreSettings.AnimatedBoneList) then
        return ent.VoreSettings.AnimatedBoneList
    end
    local pers = nil
    if VNPC_GetPredatorPersonality then
        pers = VNPC_GetPredatorPersonality(ent)
    else
        pers = ent.VNPC_PredatorPersonality or (ent.VoreSettings and ent.VoreSettings.PredatorPersonality)
    end
    if pers == "shy" and VNPC_ShyAnimatedBoneList then
        return VNPC_ShyAnimatedBoneList
    end
    local cvar = GetConVar("vnpcs_random_movesets")
    if cvar and cvar:GetBool() then
        if not ent.VNPC_AssignedMoveset then
            VNPC_AssignRandomMoveset(ent)
        end
        if ent.VNPC_AssignedMoveset and VNPC_BoneMovesets[ent.VNPC_AssignedMoveset] then
            return VNPC_BoneMovesets[ent.VNPC_AssignedMoveset]
        end
    end
    return VNPC_DefaultAnimatedBoneList
end

function VNPC_InterpolateKeyframes(keyframes, tNorm, boneName)
    local closestBefore, closestAfter = nil, nil
    for k, _ in pairs(keyframes) do
        if k <= tNorm then
            if (not closestBefore) or k > closestBefore then closestBefore = k end
        end
        if k >= tNorm then
            if (not closestAfter) or k < closestAfter then closestAfter = k end
        end
    end
    closestBefore = closestBefore or closestAfter
    closestAfter  = closestAfter  or closestBefore
    local frame1 = keyframes[closestBefore] or {}
    local frame2 = keyframes[closestAfter]  or {}
    local a = (closestAfter - closestBefore)
    local f = (a > 0) and ((tNorm - closestBefore) / a) or 0
    local b1 = frame1[boneName]
    local b2 = frame2[boneName]
    if not b1 and not b2 then
        return vector_origin, angle_zero
    end
    local pos1 = b1 and b1.pos or vector_origin
    local pos2 = b2 and b2.pos or pos1
    local ang1 = b1 and b1.ang or angle_zero
    local ang2 = b2 and b2.ang or ang1
    return LerpVector(f, pos1, pos2), VNPC_LerpAngle(f, ang1, ang2)
end

function VNPC_AnimatedBoneOffsets(ent)
    if not IsValid(ent) then return end
    local enabled = GetConVar("vnpcs_bone_pose_animations")
    if enabled and not enabled:GetBool() then return end

    if not ent.BoneBlendState then
        ent.BoneBlendState = {}
    end
    local phase = ent:GetNWInt("FacialPhase", -1)
    local animList = VNPC_GetAnimatedBoneList(ent)
    local data = animList[phase] or animList[0]

    if phase ~= ent.LastFacialPhase then
        ent.FacialPhaseStartTime = CurTime()
        ent.LastFacialPhase = phase
    end

    local boneCount = ent:GetBoneCount() or 0
    local speed = (phase == 1 or phase == 3 or phase == 4) and 14 or 8
    local is_hunting_or_moving = false
    if IsValid(ent:GetEnemy()) then
        is_hunting_or_moving = true
    elseif ent.IsMoving and ent:IsMoving() then
        is_hunting_or_moving = true
    elseif ent.GetVelocity and ent:GetVelocity():Length2DSqr() > 25 then
        is_hunting_or_moving = true
    end

    for i = 0, boneCount - 1 do
        local boneName = ent:GetBoneName(i)
        if not boneName then continue end
        local tgtPos, tgtAng = vector_origin, angle_zero
        if data and data.keyframes and data.length then
            local elapsed = CurTime() - (ent.FacialPhaseStartTime or 0)
            local tNorm = elapsed / data.length
            tNorm = math.abs((tNorm % 2) - 1)
            tgtPos, tgtAng = VNPC_InterpolateKeyframes(data.keyframes, tNorm, boneName)
        elseif data then
            local tgt = (data.pose and data.pose[boneName]) or data[boneName]
            if not tgt and not boneName:find("ValveBiped%.") then
                tgt = (data.pose and data.pose["ValveBiped." .. boneName]) or data["ValveBiped." .. boneName]
            elseif not tgt and boneName:find("ValveBiped%.") then
                local stripped = boneName:gsub("ValveBiped%.", "")
                tgt = (data.pose and data.pose[stripped]) or data[stripped]
            end
            if tgt then
                tgtPos = tgt.pos or vector_origin
                tgtAng = tgt.ang or angle_zero
            end
        end

        local is_leg_or_pelvis = boneName:find("Pelvis") or boneName:find("Thigh") or boneName:find("Calf") or boneName:find("Foot") or boneName:find("Leg") or boneName:find("leg") or boneName:find("thigh") or boneName:find("calf") or boneName:find("foot") or boneName:find("pelvis")
        if is_hunting_or_moving and is_leg_or_pelvis then
            tgtPos, tgtAng = vector_origin, angle_zero
        end

        local cur = ent.BoneBlendState[boneName]
        if not cur then
            cur = {pos = vector_origin, ang = angle_zero}
            ent.BoneBlendState[boneName] = cur
        end
        cur.pos = LerpVector(FrameTime() * speed, cur.pos, tgtPos)
        cur.ang = VNPC_LerpAngle(FrameTime() * speed, cur.ang, tgtAng)
        ent:ManipulateBonePosition(i, cur.pos)
        ent:ManipulateBoneAngles(i, cur.ang)
    end
end
