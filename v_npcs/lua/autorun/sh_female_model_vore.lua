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

function VNPC_GetFixedFemaleBellyOffset(ent)
    local x = GetConVar("vnpcs_female_model_vore_offset_x"):GetFloat() or 0
    local y = GetConVar("vnpcs_female_model_vore_offset_y"):GetFloat() or 3.5
    local z = GetConVar("vnpcs_female_model_vore_offset_z"):GetFloat() or 0
    return Vector(x, y, z)
end

function VNPC_IsFemaleModelNPC(ent)
    if not IsValid(ent) or not ent:IsNPC() then return false end
    if ent.IsDrGNextbot or ent.Base == "npc_vore_base" then return false end
    if ent:GetClass():find("func_") or ent:IsWeapon() or ent:IsPlayer() then return false end
    local mdl = string.lower(ent:GetModel() or "")
    return (mdl:find("female") or mdl:find("alyx") or mdl:find("mossman")) ~= nil
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
