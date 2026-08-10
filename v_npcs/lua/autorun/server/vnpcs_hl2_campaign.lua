-- V-NPCs Half-Life 2 Campaign Compatibility & Constant Vore Director (vnpcs_hl2_campaign.lua)
-- Protects HL2 campaign cutscenes and scripted sequences from animation breaking while ensuring constant vore in all campaign battles.

CreateConVar("vnpcs_hl2_campaign_mode", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable Half-Life 2 Campaign compatibility mode (prevents animation breaking in cutscenes and ensures constant vore in campaign battles)")
CreateConVar("vnpcs_hl2_campaign_grab_range", "160", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Grab/swallow range for predators in Half-Life 2 Campaign mode")

function VNPC_IsHL2ScriptedScene(ent)
    if not IsValid(ent) then return false end
    if ent.GetNPCState and ent:GetNPCState() == NPC_STATE_SCRIPT then return true end
    if ent.GetClass and ent:GetClass() == "scripted_sequence" then return true end
    if ent.GetSequenceName and ent.GetSequence then
        local seqName = string.lower(ent:GetSequenceName(ent:GetSequence()) or "")
        if seqName:find("script") or seqName:find("scene") or seqName:find("chore") or seqName:find("idle_subtle") or seqName:find("sit") or seqName:find("type") or seqName:find("console") then
            return true
        end
    end
    return false
end

hook.Add("Think", "VNPCS_HL2Campaign_DirectorLoop", function()
    local enabled = GetConVar("vnpcs_hl2_campaign_mode")
    if enabled and not enabled:GetBool() then return end

    local now = CurTime()

    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if not IsValid(npc) or npc.Vored or npc.VNPC_Vored or npc.VNPC_Surrendered then continue end
        if VNPC_IsHL2ScriptedScene(npc) then continue end
        if (npc.VNPC_NextCampaignThink or 0) > now then continue end
        npc.VNPC_NextCampaignThink = now + 0.5

        -- Auto-attach vore belly to female NPCs in campaign if not already attached
        if not npc.VNPC_FemaleModelVore and VNPC_AttachFemaleModelVore then
            local mdl = string.lower(npc:GetModel() or "")
            local isFemale = mdl:find("female") or mdl:find("alyx") or mdl:find("mossman") or mdl:find("girl") or mdl:find("woman")
            if isFemale or (npc.IsFemaleModel and npc:IsFemaleModel()) then
                VNPC_AttachFemaleModelVore(npc)
            end
        end

        if not (npc.VNPC_FemaleModelVore or npc.IsDrGNextbot or npc.Predator) then continue end

        -- Ensure constant vore in campaign battles by driving predators to rush and swallow enemies
        local enemy = npc:GetEnemy()
        if IsValid(enemy) and enemy ~= npc and not enemy.Vored and not enemy.VNPC_Vored then
            local dist = npc:GetPos():Distance(enemy:GetPos())
            local campGrab = GetConVar("vnpcs_hl2_campaign_grab_range"):GetFloat() or 160

            if dist <= campGrab then
                -- Swallow enemy alive!
                if npc.EatEntity then
                    npc:EatEntity(enemy)
                elseif IsValid(npc.VNPC_Belly or npc.Belly) then
                    local belly = npc.VNPC_Belly or npc.Belly
                    if belly.AddPrey then belly:AddPrey(enemy) end
                end
            elseif dist <= 800 then
                -- Suppress ranged shooting so the predator sprints directly into swallow reach
                if npc.CapabilitiesRemove then
                    pcall(npc.CapabilitiesRemove, npc, CAP_WEAPON_RANGE_ATTACK1)
                    npc.VNPC_CampaignRemovedRange = true
                end
                if npc.SetSchedule then pcall(npc.SetSchedule, npc, SCHED_CHASE_ENEMY) end
            end
        else
            if npc.CapabilitiesAdd and npc.VNPC_CampaignRemovedRange then
                pcall(npc.CapabilitiesAdd, npc, CAP_WEAPON_RANGE_ATTACK1)
                npc.VNPC_CampaignRemovedRange = nil
            end
        end
    end
end)

hook.Add("EntityTakeDamage", "VNPCS_HL2Campaign_ConstantVoreDamage", function(target, dmginfo)
    local enabled = GetConVar("vnpcs_hl2_campaign_mode")
    if enabled and not enabled:GetBool() then return end

    local attacker = dmginfo:GetAttacker()
    if not IsValid(attacker) or not IsValid(target) then return end
    if not (target:IsNPC() or target:IsPlayer() or target:IsNextBot()) then return end
    if target.Vored or target.VNPC_Vored then return end

    if attacker.VNPC_FemaleModelVore or attacker.IsDrGNextbot or attacker.Predator then
        local dmg = dmginfo:GetDamage()
        local curHP = target:Health()
        if curHP - dmg <= 20 then
            -- Prevent lethal gunfire in campaign battles so every defeated enemy is swallowed alive!
            dmginfo:SetDamage(math.max(0, curHP - 20))
        end
    end
end)

concommand.Add("vnpcs_hl2_campaign_status", function(ply)
    print("===============================================================")
    print("         V-NPCs HALF-LIFE 2 CAMPAIGN COMPATIBILITY REPORT      ")
    print("===============================================================")
    print(" - HL2 Campaign Mode Enabled: " .. tostring(GetConVar("vnpcs_hl2_campaign_mode"):GetBool()))
    print(" - Campaign Swallow Range: " .. tostring(GetConVar("vnpcs_hl2_campaign_grab_range"):GetFloat()) .. " units")
    local count = 0
    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(npc) and (npc.VNPC_FemaleModelVore or npc.IsDrGNextbot or npc.Predator) then
            count = count + 1
            local enemyName = IsValid(npc:GetEnemy()) and (npc:GetEnemy().PrintName or npc:GetEnemy():GetClass()) or "NONE"
            local scripted = VNPC_IsHL2ScriptedScene(npc) and "YES (Bone Poses Suppressed)" or "NO (Active Combat/Patrol)"
            print(string.format(" - Campaign Predator #%d [%s]: Scripted Scene = %s | Target Enemy = %s", npc:EntIndex(), npc.PrintName or npc:GetClass(), scripted, enemyName))
        end
    end
    if count == 0 then
        print(" - Active Campaign Predators: NONE currently spawned")
    end
    print("===============================================================")
end)
