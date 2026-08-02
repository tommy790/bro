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
