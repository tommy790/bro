-- V-NPCs Dynamic Belly Slosh Sound Engine (vnpcs_slosh_sounds.lua)
-- Plays realistic belly sloshing foley when full or fat predators move

local slosh_enabled = CreateConVar("vnpcs_slosh_sounds_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable belly sloshing sound effects during locomotion")
local slosh_volume = CreateConVar("vnpcs_slosh_volume", "75", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Base volume for belly sloshing sounds (0-100)")
local slosh_interval = CreateConVar("vnpcs_slosh_interval", "0.6", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Base interval in seconds between slosh sounds when moving")

function VNPC_GetPredatorFullness(ent)
    if not IsValid(ent) then return 0 end
    local belly = ent.VNPC_Belly or ent.Belly
    if not IsValid(belly) then return 0 end

    local fullness = 0
    if belly.Prey and #belly.Prey > 0 then
        fullness = fullness + #belly.Prey
    end
    if belly.DigestionPhase and belly.DigestionPhase > 0 then
        fullness = fullness + 0.5
    end
    if belly.BaseScale and belly.BaseScale > 0.05 then
        -- Integrate with existing belly fat system
        fullness = fullness + (belly.BaseScale * 2.0)
    end
    return fullness
end

function VNPC_EmitBellySlosh(ent)
    if not slosh_enabled:GetBool() then return end
    if not IsValid(ent) then return end

    local fullness = VNPC_GetPredatorFullness(ent)
    if fullness <= 0 then return end

    local vel = ent:GetVelocity():Length2D()
    if vel <= 25 then return end

    local speedFactor = math.Clamp(vel / 150, 0.5, 2.0)
    local baseVol = slosh_volume:GetFloat()
    local vol = math.Clamp(baseVol * speedFactor, 35, 100)
    local pitch = math.Clamp(math.floor(105 - (fullness * 6)), 70, 115)

    local belly = ent.VNPC_Belly or ent.Belly
    if IsValid(belly) and belly.PlayRandomSlosh then
        belly:PlayRandomSlosh(pitch, vol)
    else
        local snd = "belly/snd_slosh" .. math.random(1, 3) .. ".wav"
        ent:EmitSound(snd, vol, pitch, 1.0, CHAN_BODY)
    end
end

hook.Add("Think", "VNPC_BellySlosh_LocomotionLoop", function()
    if not slosh_enabled:GetBool() then return end

    local now = CurTime()
    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) then continue end
        if not (ent:IsNPC() or ent:IsPlayer() or ent:IsNextBot()) then continue end

        local belly = ent.VNPC_Belly or ent.Belly
        if not IsValid(belly) then continue end

        local fullness = VNPC_GetPredatorFullness(ent)
        if fullness <= 0 then continue end

        local vel = ent:GetVelocity():Length2D()
        if vel > 25 then
            if not ent.VNPC_NextSloshTime or now >= ent.VNPC_NextSloshTime then
                VNPC_EmitBellySlosh(ent)
                local speedFactor = math.Clamp(vel / 150, 0.6, 2.0)
                ent.VNPC_NextSloshTime = now + (slosh_interval:GetFloat() / speedFactor)
            end
        else
            ent.VNPC_NextSloshTime = nil
        end
    end
end)

concommand.Add("vnpcs_slosh_status", function(ply)
    local enabled = slosh_enabled:GetBool()
    print("=========================================")
    print("[V-NPCs] Belly Slosh Sound Engine Status")
    print("Enabled: " .. tostring(enabled))
    print("Volume: " .. tostring(slosh_volume:GetFloat()))
    print("Interval: " .. tostring(slosh_interval:GetFloat()) .. "s")
    print("-----------------------------------------")
    local count = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and (ent:IsNPC() or ent:IsPlayer() or ent:IsNextBot()) then
            local fullness = VNPC_GetPredatorFullness(ent)
            if fullness > 0 then
                count = count + 1
                print(string.format(" -> [%d] %s | Fullness: %.2f | Velocity: %.1f", ent:EntIndex(), ent:GetClass(), fullness, ent:GetVelocity():Length2D()))
            end
        end
    end
    print("Total slosh-ready predators: " .. count)
    print("=========================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Slosh status printed to console. Active: " .. count)
    end
end)

concommand.Add("vnpcs_test_slosh", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local target = tr.Entity
    if not IsValid(target) or not (target:IsNPC() or target:IsPlayer() or target:IsNextBot()) then
        target = ply
    end
    VNPC_EmitBellySlosh(target)
    ply:ChatPrint("[V-NPCs] Tested slosh sound on " .. tostring(target))
end)
