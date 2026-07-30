-- Shared networking and server collision bounds for smooth belly expansion.

local MIN_BELLY_SIZE = 1
local MAX_BELLY_SIZE = 4

if SERVER then
    concommand.Add("set_belly", function(ply, _, args)
        if not IsValid(ply) or not ply:IsPlayer() then return end

        local size = math.Clamp(tonumber(args[1]) or MIN_BELLY_SIZE,
            MIN_BELLY_SIZE, MAX_BELLY_SIZE)
        ply:SetNWFloat("SmoothBellySize", size)
    end)

    -- Bone hitboxes are not writable from Lua, and client-side hitbox edits
    -- cannot affect authoritative server traces. SetHull supplies the honest
    -- gameplay collision equivalent for the expanded player.
    hook.Add("Think", "SmoothBellyServerHull", function()
        for _, ply in ipairs(player.GetAll()) do
            local size = math.Clamp(ply:GetNWFloat("SmoothBellySize", MIN_BELLY_SIZE),
                MIN_BELLY_SIZE, MAX_BELLY_SIZE)
            local width = 16 * size
            local mins = Vector(-width, -width, 0)
            local maxs = Vector(width, width, 72)

            if ply._SmoothBellyHullSize ~= size then
                ply:SetHull(mins, maxs)
                ply:SetHullDuck(Vector(-width, -width, 0), Vector(width, width, 45))
                ply._SmoothBellyHullSize = size
            end
        end
    end)
end

if SERVER then
    util.AddNetworkString("BellyImpactDust")

    hook.Add("PlayerFootstep", "BellyHeavyFootsteps", function(ply, pos, foot, soundName, volume)
        local size = ply:GetNWFloat("SmoothBellySize", MIN_BELLY_SIZE)
        if size <= 1.5 then return end

        local loudness = math.min(volume * (1 + (size - 1) * 0.8), 1)
        local pitch = math.Clamp(100 - (size - 1) * 15, 60, 100)
        ply:EmitSound(soundName, 75, pitch, loudness, CHAN_BODY)

        if size > 2 and ply:GetVelocity():Length2DSqr() > 10000 then
            util.ScreenShake(pos, (size - 1) * 2, 5, 0.2, size * 80)
        end
        return true
    end)

    hook.Add("OnPlayerHitGround", "BellyHeavyLanding", function(ply, inWater, onFloater, speed)
        if inWater or speed < 150 then return end
        local size = ply:GetNWFloat("SmoothBellySize", MIN_BELLY_SIZE)
        if size <= 1.8 then return end

        local pos = ply:GetPos()
        util.ScreenShake(pos, math.min((speed / 100) * (size - 1), 10), 10, 0.4, size * 150)
        ply:EmitSound("Physics.HeavyMetal", 85, math.Clamp(80 - size * 5, 55, 80), 1)

        net.Start("BellyImpactDust")
            net.WriteVector(pos)
            net.WriteFloat(size)
        net.Broadcast()
    end)
end
