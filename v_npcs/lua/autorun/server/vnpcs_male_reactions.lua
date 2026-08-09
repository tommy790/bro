-- V-NPCs Friendly Male Belly Reaction System (vnpcs_male_reactions.lua)
-- Friendly male NPCs (Citizens, Barney, Rebels) notice, look at, and comment on friendly females' full bellies.

CreateConVar("vnpcs_male_reactions_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable friendly male NPCs reacting to and commenting on friendly females' full bellies")
CreateConVar("vnpcs_male_reactions_range", "220", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Distance within which male friendlies notice and react to a female's belly")

local maleBellyReactions = {
    "vo/npc/male01/nice.wav",
    "vo/npc/male01/fantastic01.wav",
    "vo/npc/male01/goodgod.wav",
    "vo/npc/male01/whoa.wav",
    "vo/npc/male01/impressed.wav",
    "vo/npc/male01/ohboy.wav",
    "vo/npc/male01/oneforme.wav",
    "vo/npc/male01/question05.wav",
    "vo/npc/male01/yeah02.wav",
    "vo/npc/barney/ba_ohyeah.wav",
    "vo/npc/barney/ba_another.wav"
}

local femaleBellyResponses = {
    "vo/npc/female01/excuseme01.wav",
    "vo/npc/female01/excuseme02.wav",
    "vo/npc/alyx/giggle01.wav",
    "vo/npc/alyx/giggle02.wav",
    "vo/npc/female01/yeah02.wav"
}

local function isMaleNPC(ent)
    if not IsValid(ent) or not ent:IsNPC() then return false end
    if ent.Vored or ent.VNPC_Vored or ent.VNPC_Surrendered then return false end
    -- Check that entity does not have a vore belly
    if IsValid(ent.VNPC_Belly or ent.Belly) then return false end
    local mdl = string.lower(ent:GetModel() or "")
    if mdl:find("female") or mdl:find("alyx") or mdl:find("mossman") or mdl:find("girl") or mdl:find("woman") then
        return false
    end
    return (mdl:find("male") or mdl:find("barney") or mdl:find("group01") or mdl:find("group02") or mdl:find("group03") or mdl:find("citizen") or mdl:find("rebel") or mdl:find("refugee")) ~= nil
end

local function isFriendlyFemaleWithBelly(ent, male)
    if not IsValid(ent) or ent == male or ent.Vored or ent.VNPC_Vored then return false end
    local belly = ent.VNPC_Belly or ent.Belly
    if not IsValid(belly) then return false end
    local preyCount = belly.Prey and #belly.Prey or 0
    if preyCount == 0 and (belly.DigestionPhase or 0) == 0 then return false end

    -- Check friendliness between male and female
    local rel = D_LI
    if male.GetRelationship and IsValid(ent) then
        rel = male:GetRelationship(ent)
    end
    if rel == D_LI or rel == D_NU then
        return true
    end
    return false
end

function VNPC_TriggerMaleBellyReaction(male, female)
    if not IsValid(male) or not IsValid(female) then return end
    local enabled = GetConVar("vnpcs_male_reactions_enabled")
    if enabled and not enabled:GetBool() then return end

    local now = CurTime()
    if now < (male.VNPC_NextBellyReaction or 0) then return end
    male.VNPC_NextBellyReaction = now + math.random(12, 22)

    local dist = male:GetPos():Distance(female:GetPos())

    -- Look toward the female and her full belly
    if male.SetTarget then pcall(male.SetTarget, male, female) end
    if male.SetSchedule and not IsValid(male:GetEnemy()) then
        pcall(male.SetSchedule, male, SCHED_TARGET_FACE)
    end

    -- Play a friendly amazed voice line
    local snd = maleBellyReactions[math.random(1, #maleBellyReactions)]
    if snd then
        male:EmitSound(snd, 75, math.random(95, 105))
    end

    -- If very close, play an admiring gesture and prompt a proud response from the female
    if dist <= 95 and not IsValid(male:GetEnemy()) then
        if male.AddGesture then
            pcall(male.AddGesture, male, ACT_GMOD_GESTURE_AGREE)
        end

        timer.Simple(1.2, function()
            if IsValid(female) and not IsValid(female:GetEnemy()) then
                local belly = female.VNPC_Belly or female.Belly
                if IsValid(belly) and belly.Burp and math.random(1, 2) == 1 then
                    -- Proud belly burp response!
                    pcall(belly.Burp, belly, true)
                else
                    local resp = femaleBellyResponses[math.random(1, #femaleBellyResponses)]
                    if resp then
                        female:EmitSound(resp, 75, math.random(98, 102))
                    end
                end
            end
        end)
    end
end

hook.Add("Think", "VNPCS_MaleBellyReactions_Loop", function()
    local enabled = GetConVar("vnpcs_male_reactions_enabled")
    if enabled and not enabled:GetBool() then return end

    local now = CurTime()
    local range = GetConVar("vnpcs_male_reactions_range"):GetFloat() or 220

    for _, male in ipairs(ents.FindByClass("npc_*")) do
        if not isMaleNPC(male) then continue end
        if (male.VNPC_NextBellyReactionCheck or 0) > now then continue end
        male.VNPC_NextBellyReactionCheck = now + 1.5

        if IsValid(male:GetEnemy()) then continue end -- Do not interrupt active combat

        for _, female in ipairs(ents.FindInSphere(male:GetPos(), range)) do
            if isFriendlyFemaleWithBelly(female, male) then
                VNPC_TriggerMaleBellyReaction(male, female)
                break
            end
        end
    end
end)

concommand.Add("vnpcs_male_reactions_status", function(ply)
    print("===============================================================")
    print("         V-NPCs FRIENDLY MALE BELLY REACTION STATUS            ")
    print("===============================================================")
    print(" - Male Reactions Enabled: " .. tostring(GetConVar("vnpcs_male_reactions_enabled"):GetBool()))
    print(" - Reaction Detection Range: " .. tostring(GetConVar("vnpcs_male_reactions_range"):GetFloat()) .. " units")
    local count = 0
    for _, male in ipairs(ents.FindByClass("npc_*")) do
        if isMaleNPC(male) then
            count = count + 1
            local cd = math.max(0, math.floor((male.VNPC_NextBellyReaction or 0) - CurTime()))
            print(string.format(" - Male Friendly #%d [%s]: Next Reaction Cooldown = %d sec", male:EntIndex(), male.PrintName or male:GetClass(), cd))
        end
    end
    if count == 0 then
        print(" - Active Friendly Male NPCs: NONE currently spawned")
    end
    print("===============================================================")
end)
