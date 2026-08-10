-- V-NPCs Interactive Belly-Listening & "Hear Stomach" Action Engine (vnpcs_belly_listen.lua)
-- Crouching USE interaction lets players and willing prey listen to internal stomach acoustics and share comfort healing

local listen_enabled = CreateConVar("vnpcs_belly_listen_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable interactive crouching USE belly-listening on predators")
local listen_dist = CreateConVar("vnpcs_listen_distance", "85.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Maximum distance to initiate and maintain belly-listening")
local listen_heal = CreateConVar("vnpcs_listen_heal_rate", "2.0", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Comfort health regeneration per second for listener and predator")
local listen_interval = CreateConVar("vnpcs_listen_sound_interval", "5.5", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Interval in seconds between internal stomach acoustic samples")

function VNPC_IsAnyoneListeningToBelly(pred)
    if not IsValid(pred) then return false end
    for _, ply in ipairs(player.GetAll()) do
        if ply.VNPC_IsListeningToBelly == pred then
            return true
        end
    end
    return false
end

function VNPC_StartBellyListening(ply, pred)
    if not listen_enabled:GetBool() then return false end
    if not IsValid(ply) or not IsValid(pred) then return false end

    local belly = pred.VNPC_Belly or pred.Belly
    if not IsValid(belly) then return false end

    local hasPrey = (belly.Prey and #belly.Prey > 0) or (belly.DigestionPhase and belly.DigestionPhase > 0) or (belly.BaseScale and belly.BaseScale > 0.08)
    if not hasPrey then
        ply:ChatPrint("[V-NPCs] That predator's belly is empty right now!")
        return false
    end

    ply.VNPC_IsListeningToBelly = pred
    pred.VNPC_BellyListener = ply
    ply.VNPC_NextListenSoundTime = 0
    ply.VNPC_ListenDuration = 0
    pred.VNPC_LullabyPurrActive = false

    ply:ChatPrint("[V-NPCs] You press your ear against " .. pred:GetClass() .. "'s warm belly... Listening to internal stomach acoustics!")

    if pred.EmitSound then
        pred:EmitSound("belly/snd_digestpassive.wav", 65, math.random(95, 105))
    end

    return true
end

function VNPC_StopBellyListening(ply, quiet)
    if not IsValid(ply) then return end
    local pred = ply.VNPC_IsListeningToBelly
    ply.VNPC_IsListeningToBelly = nil
    ply.VNPC_ListenDuration = 0
    if IsValid(pred) then
        pred.VNPC_LullabyPurrActive = false
        if pred.VNPC_BellyListener == ply then
            pred.VNPC_BellyListener = nil
        end
    end
    if not quiet and IsValid(ply) then
        ply:ChatPrint("[V-NPCs] You stop listening to the predator's belly.")
    end
end

-- Hook into player USE keypress while crouching
hook.Add("KeyPress", "VNPC_BellyListen_KeyPress", function(ply, key)
    if not listen_enabled:GetBool() then return end
    if key ~= IN_USE then return end
    if not IsValid(ply) or not ply:Alive() then return end

    if ply.VNPC_IsListeningToBelly then
        VNPC_StopBellyListening(ply, false)
        return
    end

    if not ply:Crouching() then return end

    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) then return end

    local distSqr = ply:GetPos():DistToSqr(target:GetPos())
    local maxDist = listen_dist:GetFloat()
    if distSqr > (maxDist * maxDist) then return end

    if target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator then
        VNPC_StartBellyListening(ply, target)
    end
end)

-- Main active listening audio foley and comfort healing loop
hook.Add("Think", "VNPC_BellyListen_ActiveLoop", function()
    if not listen_enabled:GetBool() then return end

    local now = CurTime()
    local maxDist = listen_dist:GetFloat() + 20
    local maxDistSqr = maxDist * maxDist
    local healRate = listen_heal:GetFloat() * 0.5

    for _, ply in ipairs(player.GetAll()) do
        local pred = ply.VNPC_IsListeningToBelly
        if not IsValid(pred) then continue end

        -- Check validity and distance constraints
        if not ply:Alive() or not pred:Health() or pred:Health() <= 0 or not ply:Crouching() or ply:GetPos():DistToSqr(pred:GetPos()) > maxDistSqr then
            VNPC_StopBellyListening(ply, false)
            continue
        end

        -- Lullaby Purr check (8+ seconds of continuous listening)
        ply.VNPC_ListenDuration = (ply.VNPC_ListenDuration or 0) + 0.5
        local isLullaby = (ply.VNPC_ListenDuration >= 8.0)
        if isLullaby and not pred.VNPC_LullabyPurrActive then
            pred.VNPC_LullabyPurrActive = true
            ply:ChatPrint("[V-NPCs] " .. pred:GetClass() .. " begins a contented Lullaby Purr... Comfort healing doubled (+4 HP/s) and prey struggle soothed!")
            if pred.EmitSound then
                pred:EmitSound("vore_stomach/absorption_loop1.wav", 75, 110)
            end
        end
        local healRateEff = healRate * (pred.VNPC_LullabyPurrActive and 2.0 or 1.0)

        -- Comfort health regeneration for both listener and predator
        if (ply.VNPC_NextListenHealTime or 0) <= now then
            ply.VNPC_NextListenHealTime = now + 0.5
            local pMax = ply:GetMaxHealth() or 100
            if ply:Health() < pMax then
                ply:SetHealth(math.min(pMax, ply:Health() + healRateEff))
            end
            local eMax = pred:GetMaxHealth() or 100
            if pred:Health() < eMax then
                pred:SetHealth(math.min(eMax, pred:Health() + healRateEff))
            end
        end

        -- Periodic high-fidelity internal stomach acoustics
        if (ply.VNPC_NextListenSoundTime or 0) <= now then
            ply.VNPC_NextListenSoundTime = now + (pred.VNPC_LullabyPurrActive and (listen_interval:GetFloat() * 0.75) or listen_interval:GetFloat())
            local sounds = {
                "vore_stomach/digestion_loop1.wav",
                "vore_stomach/absorption_loop1.wav",
                "belly/snd_digestpassive.wav",
                "belly/snd_slosh1.wav",
                "belly/snd_slosh2.wav"
            }
            local snd = sounds[math.random(1, #sounds)]
            ply:EmitSound(snd, 70, math.random(90, 105))
        end
    end
end)

concommand.Add("vnpcs_listen_status", function(ply)
    print("=========================================")
    print("[V-NPCs] Interactive Belly-Listening Status")
    print("Enabled: " .. tostring(listen_enabled:GetBool()))
    print("Max Distance: " .. tostring(listen_dist:GetFloat()) .. " units")
    print("Heal Rate: " .. tostring(listen_heal:GetFloat()) .. " HP/sec")
    print("Sound Interval: " .. tostring(listen_interval:GetFloat()) .. "s")
    print("-----------------------------------------")
    local count = 0
    for _, p in ipairs(player.GetAll()) do
        if IsValid(p.VNPC_IsListeningToBelly) then
            count = count + 1
            print(string.format(" -> Listener [%s] listening to %s", p:Nick(), p.VNPC_IsListeningToBelly:GetClass()))
        end
    end
    print("Total active belly listeners: " .. count)
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Belly listening status printed to console. Active listeners: " .. count)
    end
end)

concommand.Add("vnpcs_test_belly_listen", function(ply)
    if not IsValid(ply) then return end
    if ply.VNPC_IsListeningToBelly then
        VNPC_StopBellyListening(ply, false)
        return
    end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target.IsDrGNextbot or target.VNPC_FemaleModelVore or target.Predator) then
        ply:ChatPrint("[V-NPCs] Please aim at a female V-NPC predator to test belly listening!")
        return
    end
    VNPC_StartBellyListening(ply, target)
end)
