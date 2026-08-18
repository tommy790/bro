-- V-NPCs Female Player Vore System (vnpcs_player_vore.lua)
-- Gives female player models dynamic vore bellies, allowing players to swallow enemy predators, NPCs, and players alive!

CreateConVar("vnpcs_player_vore_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable vore bellies and swallowing abilities for female player models")
CreateConVar("vnpcs_player_swallow_range", "130", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Distance in units within which a female player can swallow an aimed target")

local function isFemalePlayerModel(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return false end
    local mdl = string.lower(ply:GetModel() or "")
    if mdl:find("female") or mdl:find("alyx") or mdl:find("mossman") or mdl:find("girl") or mdl:find("woman") or mdl:find("lady") or mdl:find("group01") or mdl:find("group02") or mdl:find("group03") then
        return true
    end
    if VNPC_IsFemaleModelNPC and VNPC_IsFemaleModelNPC(ply) then
        return true
    end
    return false
end

function VNPC_AttachPlayerVoreBelly(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local enabled = GetConVar("vnpcs_player_vore_enabled")
    if enabled and not enabled:GetBool() then return end

    if not isFemalePlayerModel(ply) then return end
    if IsValid(ply.VNPC_Belly or ply.Belly) then return end

    -- Attach Belly entity to female player
    if VNPC_AttachFemaleModelVore then
        VNPC_AttachFemaleModelVore(ply)
    end
end

hook.Add("PlayerSpawn", "VNPCS_PlayerVore_OnSpawn", function(ply)
    timer.Simple(0.5, function()
        if IsValid(ply) and ply:Alive() then
            VNPC_AttachPlayerVoreBelly(ply)
        end
    end)
end)

hook.Add("PlayerSetModel", "VNPCS_PlayerVore_OnSetModel", function(ply)
    timer.Simple(0.5, function()
        if IsValid(ply) and ply:Alive() then
            VNPC_AttachPlayerVoreBelly(ply)
        end
    end)
end)

concommand.Add("vnpcs_player_swallow", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local enabled = GetConVar("vnpcs_player_vore_enabled")
    if enabled and not enabled:GetBool() then
        ply:ChatPrint("[V-NPCs] Player Vore is currently disabled (vnpcs_player_vore_enabled 0).")
        return
    end

    if not IsValid(ply.VNPC_Belly or ply.Belly) then
        VNPC_AttachPlayerVoreBelly(ply)
    end

    local belly = ply.VNPC_Belly or ply.Belly
    if not IsValid(belly) then
        ply:ChatPrint("[V-NPCs] You must have a female player model to swallow prey!")
        return
    end

    local range = GetConVar("vnpcs_player_swallow_range"):GetFloat() or 130
    local tr = util.TraceLine({
        start = ply:GetShootPos(),
        endpos = ply:GetShootPos() + ply:GetAimVector() * range,
        filter = { ply, belly }
    })

    local target = tr.Entity
    if not IsValid(target) then
        -- Try a small sphere trace if thin line trace missed
        for _, ent in ipairs(ents.FindInSphere(ply:GetShootPos() + ply:GetAimVector() * (range * 0.5), range * 0.5)) do
            if IsValid(ent) and ent ~= ply and ent ~= belly and not ent.Vored and not ent.VNPC_Vored then
                if ent.VNPC_DigestedBone or ent.VNPC_BoneOwner or ent.VNPC_NoVore then continue end
                if ent:IsNPC() or ent:IsPlayer() or ent.IsDrGNextbot or ent:GetClass() == "prop_ragdoll" or ent.VNPC_IsCorpse then
                    target = ent
                    break
                end
            end
        end
    end

    if not IsValid(target) or target.Vored or target.VNPC_Vored then
        ply:ChatPrint("[V-NPCs] No valid prey found in aim range (" .. math.floor(range) .. " units).")
        return
    end

    if not (target:IsNPC() or target:IsPlayer() or target.IsDrGNextbot or target:GetClass() == "prop_ragdoll" or target.VNPC_IsCorpse) then
        ply:ChatPrint("[V-NPCs] Target [" .. (target.PrintName or target:GetClass()) .. "] is not edible prey.")
        return
    end

    if VNPC_IsProtectedChildPrey and VNPC_IsProtectedChildPrey(target) then
        ply:ChatPrint("[V-NPCs] You cannot swallow a growing baby citizen!")
        return
    end

    -- Swallow the target into player's belly!
    if belly.AddPrey and belly:AddPrey(target) then
        if VNPC_PlayGulpSound then
            VNPC_PlayGulpSound(ply, 90, math.random(95, 105), true)
        else
            ply:EmitSound("gulps/g" .. math.random(1, 10) .. ".wav", 90, math.random(95, 105), 1, CHAN_VOICE)
        end
        ply:ChatPrint("[V-NPCs] Swallowed [" .. (target.PrintName or target:GetClass()) .. "] alive!")
    else
        ply:ChatPrint("[V-NPCs] Could not swallow target right now.")
    end
end)

concommand.Add("vnpcs_player_burp", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local belly = ply.VNPC_Belly or ply.Belly
    if IsValid(belly) and belly.Burp then
        pcall(belly.Burp, belly, true)
        ply:ChatPrint("[V-NPCs] *Burp!*")
    else
        ply:EmitSound("burps/burp" .. math.random(1, 6) .. ".wav", 80, 100)
    end
end)

concommand.Add("vnpcs_player_regurgitate", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local belly = ply.VNPC_Belly or ply.Belly
    if not IsValid(belly) or not belly.Prey or #belly.Prey == 0 then
        ply:ChatPrint("[V-NPCs] Your belly is empty.")
        return
    end

    if belly.Regurgitate then
        local preyName = IsValid(belly.Prey[#belly.Prey].Entity) and (belly.Prey[#belly.Prey].Entity.PrintName or belly.Prey[#belly.Prey].Entity:GetClass()) or "prey"
        belly:Regurgitate(#belly.Prey)
        ply:ChatPrint("[V-NPCs] Regurgitated [" .. preyName .. "] alive!")
    end
end)

concommand.Add("vnpcs_player_status", function(ply)
    print("===============================================================")
    print("            V-NPCs FEMALE PLAYER VORE STATUS                   ")
    print("===============================================================")
    for _, p in ipairs(player.GetAll()) do
        local belly = p.VNPC_Belly or p.Belly
        local count = IsValid(belly) and (belly.Prey and #belly.Prey or 0) or 0
        local val = IsValid(belly) and (belly.GetCollectivePreyValue and math.floor(belly:GetCollectivePreyValue()) or 0) or 0
        local hasBelly = IsValid(belly) and "YES" or "NO"
        print(string.format(" - Player [%s]: Has Belly = %s | Swallowed Prey = %d (Total Value = %d)", p:Nick(), hasBelly, count, val))
    end
    print("===============================================================")
end)
