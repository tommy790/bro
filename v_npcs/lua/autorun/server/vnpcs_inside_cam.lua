-- V-NPCs 1st-Person Inside-Belly Camera & Escape Rhythm Mini-Game Engine (vnpcs_inside_cam.lua)
-- Server-side network handlers, struggle damage calculation, and emergency regurgitation trigger

util.AddNetworkString("VNPC_ToggleInsideCam")
util.AddNetworkString("VNPC_StrugglePunch")
util.AddNetworkString("VNPC_EscapeProgress")

local minigame_enabled = CreateConVar("vnpcs_minigame_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable the rhythmic escape struggle mini-game for swallowed players")
local punch_damage = CreateConVar("vnpcs_minigame_punch_damage", "8.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Internal damage dealt to predator per perfect heartbeat struggle hit")

net.Receive("VNPC_StrugglePunch", function(len, ply)
    if not minigame_enabled:GetBool() then return end
    if not IsValid(ply) or not ply:Alive() then return end

    local hitScore = net.ReadUInt(3) -- 2 = Perfect Hit, 1 = Good Hit, 0 = Miss

    -- Find the belly that swallowed this player
    local belly = ply.VNPC_VoredBelly or ply:GetParent()
    if not IsValid(belly) or not belly.Prey then return end

    local pred = belly.NPC or belly:GetOwner() or belly:GetParent()
    if not IsValid(pred) then return end

    local progress = 0
    if hitScore == 2 then
        progress = 20 -- Perfect Heartbeat Hit (~5 hits to escape!)
    elseif hitScore == 1 then
        progress = 10 -- Good Hit (~10 hits to escape)
    else
        progress = 2  -- Glancing miss / weak punch
    end

    ply.VNPC_EscapeMeter = math.Clamp((ply.VNPC_EscapeMeter or 0) + progress, 0, 100)

    -- Send progress update back to client HUD
    net.Start("VNPC_EscapeProgress")
    net.WriteFloat(ply.VNPC_EscapeMeter)
    net.Send(ply)

    -- Foley and kicking bulge on predator
    if pred.EmitSound then
        pred:EmitSound("physics/body/body_medium_impact_hard1.wav", 80, math.random(85, 108))
    end

    -- Deal internal struggle damage non-lethally down to 30 HP
    if pred:Health() > 30 then
        local dmg = punch_damage:GetFloat() * (hitScore == 2 and 1.0 or 0.5)
        if pred.VNPC_LullabyPurrActive then
            dmg = dmg * 0.5 -- Lullaby Purr soothes struggling prey!
        end
        pred:TakeDamage(dmg, ply, ply)
    end

    -- Check if player successfully filled the Escape Meter (>= 100%)
    if ply.VNPC_EscapeMeter >= 100 then
        ply.VNPC_EscapeMeter = 0

        -- Trigger emergency regurgitation
        if pred.SetFacialExpression then
            pcall(pred.SetFacialExpression, pred, 3)
            timer.Simple(1.35, function()
                if IsValid(pred) and pred.SetFacialExpression then
                    pcall(pred.SetFacialExpression, pred, 0)
                end
            end)
        end
        if pred.EmitSound then
            pred:EmitSound("burps/burp" .. math.random(1, 23) .. ".wav", 90, math.random(92, 105))
        end

        local foundIndex = nil
        for idx, info in ipairs(belly.Prey) do
            if info.Entity == ply then
                foundIndex = idx
                break
            end
        end

        if foundIndex and belly.Regurgitate then
            belly:Regurgitate(foundIndex)
            ply:ChatPrint("[V-NPCs] PERFECT STRUGGLE! You punched your way out of " .. pred:GetClass() .. "'s stomach alive!")
        else
            ply:SetParent(nil)
            ply:SetNoDraw(false)
            ply:RemoveFlags(FL_NOTARGET)
            ply:SetPos(pred:GetPos() + pred:GetForward() * 40 + Vector(0,0,15))
            ply:ChatPrint("[V-NPCs] You fought your way free from the predator's belly!")
        end
    end
end)

concommand.Add("vnpcs_minigame_status", function(ply)
    print("=========================================")
    print("[V-NPCs] 1st-Person Inside-Belly Cam & Mini-Game Status")
    print("Mini-Game Enabled: " .. tostring(minigame_enabled:GetBool()))
    print("Punch Damage: " .. tostring(punch_damage:GetFloat()) .. " HP")
    print("-----------------------------------------")
    local count = 0
    for _, p in ipairs(player.GetAll()) do
        if (p.VNPC_EscapeMeter or 0) > 0 then
            count = count + 1
            print(string.format(" -> Swallowed Player [%s] | Escape Meter: %d%%", p:Nick(), p.VNPC_EscapeMeter))
        end
    end
    print("Total active escape struggles: " .. count)
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Mini-game status printed to console. Active struggles: " .. count)
    end
end)

concommand.Add("vnpcs_test_escape", function(ply)
    if not IsValid(ply) then return end
    ply.VNPC_EscapeMeter = 100
    local belly = ply.VNPC_VoredBelly or ply:GetParent()
    if IsValid(belly) and belly.Prey then
        for idx, info in ipairs(belly.Prey) do
            if info.Entity == ply then
                belly:Regurgitate(idx)
                ply:ChatPrint("[V-NPCs] Tested emergency escape regurgitation!")
                return
            end
        end
    end
    ply:ChatPrint("[V-NPCs] You are not currently swallowed inside a belly!")
end)
