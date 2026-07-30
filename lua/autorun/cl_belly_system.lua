if not CLIENT then return end

local currentSize = {}
local bellyVelocity = {}
local bellyOffset = {}
local MIN_BELLY_SIZE = 1
local EPSILON = 0.001

local function validBone(bone)
    return bone ~= nil and bone >= 0
end

hook.Add("UpdateAnimation", "SmoothBellyExpansion", function(ply)
    if not IsValid(ply) then return end

    local idx = ply:EntIndex()
    local target = math.Clamp(ply:GetNWFloat("SmoothBellySize", MIN_BELLY_SIZE),
        MIN_BELLY_SIZE, 4)
    local current = currentSize[idx] or MIN_BELLY_SIZE

    -- Exponential smoothing is framerate independent and does not snap when
    -- the target changes or when a player first enters the PVS.
    local blend = 1 - math.exp(-2.5 * FrameTime())
    current = Lerp(blend, current, target)
    if math.abs(current - target) < EPSILON then current = target end
    currentSize[idx] = current

    -- Spring-mass-damper jiggle. Movement and vertical impacts drive the
    -- belly, while the size-dependent inertia makes larger bellies settle more
    -- slowly. The timestep cap keeps hitches from exploding the simulation.
    local dt = math.min(FrameTime(), 0.1)
    local offset = bellyOffset[idx] or 0
    local jiggleVelocity = bellyVelocity[idx] or 0
    if current > 1.05 and dt > 0 then
        local movement = ply:GetVelocity()
        local forwardMotion = movement:Dot(ply:GetAimVector())
        local externalForce = -forwardMotion * 0.02 + movement.z * 0.05
        local acceleration = (-15 * offset - 3.5 * jiggleVelocity
            + externalForce) / current

        jiggleVelocity = jiggleVelocity + acceleration * dt
        offset = math.Clamp(offset + jiggleVelocity * dt, -5, 5)
        bellyVelocity[idx] = jiggleVelocity
        bellyOffset[idx] = offset
    else
        offset = 0
        bellyVelocity[idx] = 0
        bellyOffset[idx] = 0
    end

    local spine1 = ply:LookupBone("ValveBiped.Bip01_Spine")
    local spine2 = ply:LookupBone("ValveBiped.Bip01_Spine1")

    if validBone(spine1) then
        if current > 1 + EPSILON then
            ply:ManipulateBoneScale(spine1, Vector(current * 1.3, current * 1.2, current * 0.9))
            local forward = (current - 1) * 4 + offset * 0.5
            local drop = offset * -0.2 - (current - 1) * 2
            ply:ManipulateBonePosition(spine1, Vector(forward, 0, drop))
        else
            ply:ManipulateBoneScale(spine1, Vector(1, 1, 1))
            ply:ManipulateBonePosition(spine1, Vector(0, 0, 0))
        end
    end

    if validBone(spine2) then
        if current > 1 + EPSILON then
            ply:ManipulateBoneScale(spine2, Vector(current * 1.1, current * 1.05, 1))
        else
            ply:ManipulateBoneScale(spine2, Vector(1, 1, 1))
        end
    end
end)

hook.Add("EntityRemoved", "CleanupBellyTable", function(ent)
    if ent:IsPlayer() then
        local idx = ent:EntIndex()
        currentSize[idx] = nil
        bellyVelocity[idx] = nil
        bellyOffset[idx] = nil
    end
end)

-- Keep the first-person camera outside the expanded torso.  Only the origin is
-- moved, so the view angles (and therefore aim traces) remain unchanged.
hook.Add("CalcView", "BellyCameraOffset", function(ply, pos, angles, fov)
    if not IsValid(ply) or ply:ShouldDrawLocalPlayer() then return end

    local current = currentSize[ply:EntIndex()] or MIN_BELLY_SIZE
    if current <= 1.1 then return end

    local amount = current - MIN_BELLY_SIZE
    return {
        origin = pos + angles:Forward() * math.max(-amount * 8, -24)
            + angles:Up() * math.min(amount * 4, 12),
        angles = angles,
        fov = fov,
        drawviewer = false
    }
end)

-- Lift and slightly advance the viewmodel so hands and weapons do not appear
-- buried in the expanded torso.  This is cosmetic only; weapon aim is not
-- changed because the returned angles are identical to the original angles.
hook.Add("CalcViewModelView", "BellyViewmodelOffset", function(_, _, _, _, pos, ang)
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local current = currentSize[ply:EntIndex()] or MIN_BELLY_SIZE
    if current <= 1.1 then return end

    local amount = current - MIN_BELLY_SIZE
    local newPos = pos + ang:Forward() * math.min(amount * 2, 6)
        + ang:Up() * math.min(amount * 1.5, 4.5)
    return newPos, ang
end)

net.Receive("BellyImpactDust", function()
    local pos = net.ReadVector()
    local size = math.Clamp(net.ReadFloat(), 1.8, 4)
    local emitter = ParticleEmitter(pos)
    if not emitter then return end

    local count = math.floor(size * 8)
    for i = 1, count do
        local angle = (i / count) * math.pi * 2
        local outward = Vector(math.cos(angle), math.sin(angle), 0) * (size * 60)
        local particle = emitter:Add("particles/smokey", pos + Vector(0, 0, 2))
        if particle then
            particle:SetVelocity(outward + Vector(0, 0, math.random(5, 20)))
            particle:SetDieTime(math.Rand(0.6, 1.2))
            particle:SetStartAlpha(math.random(100, 150))
            particle:SetEndAlpha(0)
            particle:SetStartSize(math.random(10, 20) * size * 0.5)
            particle:SetEndSize(math.random(30, 50) * size)
            particle:SetRoll(math.Rand(-180, 180))
            particle:SetRollDelta(math.Rand(-1, 1))
            particle:SetColor(140, 135, 125)
            particle:SetLighting(true)
            particle:SetAirResistance(40)
        end
    end
    emitter:Finish()
end)
