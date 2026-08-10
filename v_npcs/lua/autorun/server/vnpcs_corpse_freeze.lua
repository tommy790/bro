-- V-NPCs Corpse & Ragdoll Physics Freezing Engine (vnpcs_corpse_freeze.lua)
-- Automatically freezes physics bones on settled corpses/ragdolls when keep-corpses is enabled, preventing physics lag when spawning multiple corpses.

CreateConVar("vnpcs_freeze_corpses", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Automatically freeze physics on resting corpses/ragdolls when keep corpses is enabled to prevent testing lag")
CreateConVar("vnpcs_freeze_corpses_delay", "2.5", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Seconds after spawning/settling before a corpse ragdoll is automatically frozen")

function VNPC_FreezeRagdollPhysics(ent)
    if not IsValid(ent) or ent.VNPC_IsFrozenCorpse then return end
    if not (ent:GetClass() == "prop_ragdoll" or ent.VNPC_IsCorpse) then return end

    local count = ent:GetPhysicsObjectCount() or 0
    if count == 0 then
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:Sleep()
            phys:EnableMotion(false)
        end
    else
        for i = 0, count - 1 do
            local phys = ent:GetPhysicsObjectNum(i)
            if IsValid(phys) then
                phys:Sleep()
                phys:EnableMotion(false)
            end
        end
    end
    ent.VNPC_IsFrozenCorpse = true
end

function VNPC_UnfreezeRagdollPhysics(ent)
    if not IsValid(ent) or not ent.VNPC_IsFrozenCorpse then return end
    local count = ent:GetPhysicsObjectCount() or 0
    if count == 0 then
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableMotion(true)
            phys:Wake()
        end
    else
        for i = 0, count - 1 do
            local phys = ent:GetPhysicsObjectNum(i)
            if IsValid(phys) then
                phys:EnableMotion(true)
                phys:Wake()
            end
        end
    end
    ent.VNPC_IsFrozenCorpse = false
end

hook.Add("Think", "VNPCS_CorpseFreeze_Loop", function()
    local enabled = GetConVar("vnpcs_freeze_corpses")
    if enabled and not enabled:GetBool() then return end

    local now = CurTime()
    if (VNPC_NextCorpseFreezeThink or 0) > now then return end
    VNPC_NextCorpseFreezeThink = now + 1.0

    local delay = GetConVar("vnpcs_freeze_corpses_delay"):GetFloat() or 2.5

    for _, ent in ipairs(ents.FindByClass("prop_ragdoll")) do
        if not IsValid(ent) or ent.Vored or ent.VNPC_Vored or ent.VNPC_IsBeingSwallowed or ent.VNPC_IsFrozenCorpse then continue end

        if not ent.VNPC_SpawnSettledTime then
            ent.VNPC_SpawnSettledTime = now
            ent.VNPC_LastSettledPos = ent:GetPos()
            continue
        end

        -- Check if ragdoll has stopped moving
        local curPos = ent:GetPos()
        if curPos:DistToSqr(ent.VNPC_LastSettledPos or curPos) > 16 then
            ent.VNPC_SpawnSettledTime = now
            ent.VNPC_LastSettledPos = curPos
            continue
        end

        if now - ent.VNPC_SpawnSettledTime >= delay then
            VNPC_FreezeRagdollPhysics(ent)
        end
    end
end)

-- Automatically unfreeze when picked up by Physgun / Gravity Gun
hook.Add("OnPhysgunPickup", "VNPCS_CorpseFreeze_OnPhysgun", function(ply, ent)
    if IsValid(ent) and ent.VNPC_IsFrozenCorpse then
        VNPC_UnfreezeRagdollPhysics(ent)
    end
end)

hook.Add("GravGunOnPickedUp", "VNPCS_CorpseFreeze_OnGravGun", function(ply, ent)
    if IsValid(ent) and ent.VNPC_IsFrozenCorpse then
        VNPC_UnfreezeRagdollPhysics(ent)
    end
end)

concommand.Add("vnpcs_corpse_freeze_status", function(ply)
    print("===============================================================")
    print("        V-NPCs CORPSE & RAGDOLL PHYSICS FREEZING STATUS        ")
    print("===============================================================")
    print(" - Corpse Freezing Enabled: " .. tostring(GetConVar("vnpcs_freeze_corpses"):GetBool()))
    print(" - Freeze Settled Delay: " .. tostring(GetConVar("vnpcs_freeze_corpses_delay"):GetFloat()) .. " sec")
    local frozenCount, totalCount = 0, 0
    for _, ent in ipairs(ents.FindByClass("prop_ragdoll")) do
        if IsValid(ent) and not ent.Vored and not ent.VNPC_Vored then
            totalCount = totalCount + 1
            if ent.VNPC_IsFrozenCorpse then
                frozenCount = frozenCount + 1
            end
        end
    end
    print(string.format(" - Active Corpses/Ragdolls: %d total (%d frozen, %d active physics)", totalCount, frozenCount, totalCount - frozenCount))
    print("===============================================================")
end)
