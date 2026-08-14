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

function VNPC_HL2Campaign_InitCouplesAndFamily()
    local enabled = GetConVar("vnpcs_hl2_campaign_mode")
    if enabled and not enabled:GetBool() then return end

    local allNPCs = ents.FindByClass("npc_*")
    local elis = {}
    local alyxes = {}
    local citizenFemales = {}
    local citizenMales = {}

    for _, npc in ipairs(allNPCs) do
        if not IsValid(npc) or npc:Health() <= 0 or npc.Vored or npc.VNPC_Vored then continue end

        local cls = string.lower(npc:GetClass() or "")
        local mdl = string.lower(npc:GetModel() or "")

        if cls == "npc_eli" or mdl:find("eli") then
            table.insert(elis, npc)
        elseif cls == "npc_alyx" or mdl:find("alyx") then
            table.insert(alyxes, npc)
        end

        if cls:find("citizen") or cls:find("rebel") or cls:find("refugee") or cls:find("mossman") or cls:find("alyx") then
            local isFemale = mdl:find("female") or mdl:find("alyx") or mdl:find("mossman") or mdl:find("f_")
            if isFemale then
                table.insert(citizenFemales, npc)
            else
                table.insert(citizenMales, npc)
            end
        end
    end

    -- 1. Link Eli Vance as Alyx Vance's father
    for _, eli in ipairs(elis) do
        for _, alyx in ipairs(alyxes) do
            eli.VNPC_WildChild = alyx
            alyx.VNPC_FatherRef = eli
            eli.VNPC_IsFatherOfAlyx = true
            alyx.VNPC_IsDaughterOfEli = true
        end
    end

    -- 2. Link co-located citizens at the start of the game as Mates (e.g. female and male sitting at couch)
    for _, f in ipairs(citizenFemales) do
        if IsValid(f.VNPC_WildMate) or IsValid(f.VNPC_LovedPartner) then continue end
        local fPos = f:GetPos()

        for _, m in ipairs(citizenMales) do
            if not IsValid(m) or m == f or IsValid(m.VNPC_WildMate) or IsValid(m.VNPC_LovedPartner) then continue end
            if m:GetPos():DistToSqr(fPos) <= (260 * 260) then
                f.VNPC_WildMate = m
                m.VNPC_WildMate = f
                f.VNPC_LovedPartner = m
                m.VNPC_LovedPartner = f
                f.VNPC_CampaignMate = true
                m.VNPC_CampaignMate = true
                break
            end
        end
    end
end

hook.Add("Think", "VNPCS_HL2Campaign_DirectorLoop", function()
    local enabled = GetConVar("vnpcs_hl2_campaign_mode")
    if enabled and not enabled:GetBool() then return end

    local now = CurTime()

    if (now - (VNPC_LastCampaignFamilyInit or 0)) >= 3.0 then
        VNPC_LastCampaignFamilyInit = now
        VNPC_HL2Campaign_InitCouplesAndFamily()
    end

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
            if VNPC_IsFamilyOrMate and VNPC_IsFamilyOrMate(npc, enemy) then continue end
            if not (npc.VNPC_IsWildWanderer and npc.VNPC_WildType == "predator") and VNPC_IsProtectedChildPrey and VNPC_IsProtectedChildPrey(enemy) then continue end
            if VNPC_IsPreyEmissary and VNPC_IsPreyEmissary(enemy) then continue end
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

                -- Campaign Squad Coordination: alert nearby friendly predators to assist in surrounding the enemy
                for _, ally in ipairs(ents.FindInSphere(npc:GetPos(), 300)) do
                    if IsValid(ally) and ally ~= npc and ally ~= enemy and ally:Health() > 0 and (ally.VNPC_FemaleModelVore or ally.IsDrGNextbot or ally.Predator) then
                        if not IsValid(ally:GetEnemy()) then
                            if ally.SetEnemy then pcall(ally.SetEnemy, ally, enemy) end
                            if ally.SetSchedule then pcall(ally.SetSchedule, ally, SCHED_CHASE_ENEMY) end
                        end
                    end
                end
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
    if VNPC_IsFamilyOrMate and VNPC_IsFamilyOrMate(attacker, target) then return end
    if not (attacker.VNPC_IsWildWanderer and attacker.VNPC_WildType == "predator") and VNPC_IsProtectedChildPrey and VNPC_IsProtectedChildPrey(target) then return end
    if VNPC_IsPreyEmissary and VNPC_IsPreyEmissary(target) then return end

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
    local cMates = 0
    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(npc) and (npc.VNPC_CampaignMate or IsValid(npc.VNPC_WildMate) or IsValid(npc.VNPC_LovedPartner)) then
            cMates = cMates + 1
        end
    end
    print(" - Active Campaign Mates / Couples: " .. math.floor(cMates / 2) .. " couples linked")
    print("===============================================================")
end)

concommand.Add("vnpcs_test_hl2_family", function(ply)
    VNPC_HL2Campaign_InitCouplesAndFamily()
    local cMates = 0
    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(npc) and (npc.VNPC_CampaignMate or IsValid(npc.VNPC_WildMate) or IsValid(npc.VNPC_LovedPartner)) then
            cMates = cMates + 1
        end
    end
    print("[V-NPCs] Initialized HL2 Campaign family relationships and couples (Eli as Alyx's father, couch/map citizens as mates). Total mates linked: " .. math.floor(cMates / 2))
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] HL2 Campaign couples and family relationships initialized! Mates linked: " .. math.floor(cMates / 2))
    end
end)
