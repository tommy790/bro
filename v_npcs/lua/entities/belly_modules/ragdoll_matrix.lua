--[[

    FULL PHYSICS-DRIVEN DIGESTION ("RAGDOLL MATRIX")

    Source's engine doesn't really support simulating a full ragdoll bouncing
    around *inside* a deforming, skinned mesh cavity, so instead of hiding
    that limitation this keeps a lightweight simulated physics state per
    living prey: a spring-damped position bounded to the belly's interior
    that's actually driven by the prey's real input (movement keys for
    players, semi-random flailing for NPCs/props).

    That simulated position feeds three things:
        1. belly_modules/animations.lua - shifts/jostles the belly mesh so it
           visibly bounces where the prey currently "is"
        2. nearby physics props / players get gently shoved, so the belly
           behaves like an actual solid object with something moving in it
        3. digestion FX (screen shake, footsteps) can react to how hard the
           prey is currently struggling

]]

local ragdoll_enabled    = CreateConVar("vnpcs_ragdoll_matrix", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED})
local ragdoll_collision  = CreateConVar("vnpcs_ragdoll_collision", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED})
local ragdoll_force_mul  = CreateConVar("vnpcs_ragdoll_force", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED})

if SERVER then

--how hard a live prey pushes back on the "stomach wall" per second
function ENT:GetStruggleInput(prey, info)
    if not info.Alive then return vector_origin end

    if prey:IsPlayer() then
        local ok, cmd = pcall(prey.GetCurrentCommand, prey)
        if not ok or not cmd then return vector_origin end

        local ok2, forward, side = pcall(function() return cmd:GetForwardMove(), cmd:GetSideMove() end)
        if not ok2 then return vector_origin end

        local input = Vector(forward or 0, side or 0, 0)
        if input:Length() < 40 then return vector_origin end

        input = input / 400 --usercmd move values are roughly +-400
        return Vector(
            math.Clamp(input.x, -1, 1) * 46,
            math.Clamp(input.y, -1, 1) * 46,
            0
        )
    end

    --npcs, props, nextbots: irregular flailing, refreshed every so often
    local now = CurTime()
    if now >= (info.NextImpulse or 0) then
        info.NextImpulse = now + math.Rand(0.15, 0.55)
        info.CurrentImpulse = VectorRand() * 40
        info.CurrentImpulse.z = info.CurrentImpulse.z * 0.35
    end

    return info.CurrentImpulse or vector_origin
end

function ENT:PushNearbyPhysics(localOffset, force)
    if not localOffset or not force or force < 0.2 then return end
    if not ragdoll_collision:GetBool() then return end

    local worldPos = self:LocalToWorld(localOffset)
    local radius = 28 + force * 14

    for _, ent in ipairs(ents.FindInSphere(worldPos, radius)) do
        if ent == self or ent == self.NPC then continue end
        if ent.Vored then continue end --don't fling stuff that's already prey

        local dir = ent:GetPos() - worldPos
        if dir:Length() < 1 then dir = VectorRand() end
        dir = dir:GetNormalized()

        if ent:IsPlayer() then
            if ent:GetMoveType() == MOVETYPE_NOCLIP then continue end
            ent:SetVelocity(dir * force * 55 * ragdoll_force_mul:GetFloat())
        else
            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then
                phys:Wake()
                phys:ApplyForceCenter(dir * force * phys:GetMass() * 80 * ragdoll_force_mul:GetFloat())
            end
        end
    end
end

function ENT:UpdateRagdollMatrix()
    if not ragdoll_enabled:GetBool() then
        self:SetNWVector("RagOffset", vector_origin)
        self:SetNWFloat("RagForce", 0)
        return
    end

    if #self.Prey == 0 then
        self:SetNWVector("RagOffset", vector_origin)
        self:SetNWFloat("RagForce", 0)
        return
    end

    local now = CurTime()
    local dt = now - (self._lastRagTime or now)
    self._lastRagTime = now
    if dt <= 0 or dt > 0.35 then dt = 0.05 end

    local interiorRadius = 18 + self:GetBellySize() * 34

    local focusPos, focusForce = vector_origin, 0

    for _, info in ipairs(self.Prey) do
        if info.Absorbing then continue end
        local prey = info.Entity
        if not IsValid(prey) then continue end

        info.Rag = info.Rag or {Pos = Vector(0,0,0), Vel = Vector(0,0,0), NextImpulse = 0}
        local rag = info.Rag

        local struggle = self:GetStruggleInput(prey, info)

        --spring back towards the center of the belly + struggle force - damping
        local accel = struggle * 5 - rag.Pos * 4.5 - rag.Vel * 3.2
        rag.Vel = rag.Vel + accel * dt
        rag.Pos = rag.Pos + rag.Vel * dt

        if rag.Pos:Length() > interiorRadius then
            rag.Pos = rag.Pos:GetNormalized() * interiorRadius
            rag.Vel = rag.Vel * -0.35 --bounce off the "stomach wall"
        end

        local magnitude = rag.Vel:Length()
        if magnitude > focusForce then
            focusForce = magnitude
            focusPos = rag.Pos
        end
    end

    local normalizedForce = math.Clamp(focusForce / 220, 0, 1)

    self:SetNWVector("RagOffset", focusPos)
    self:SetNWFloat("RagForce", normalizedForce)

    if normalizedForce > 0.35 then
        self:PushNearbyPhysics(focusPos, normalizedForce)

        if self.NPC and IsValid(self.NPC) and normalizedForce > 0.7 and math.random() < 0.05 then
            util.ScreenShake(self.NPC:GetPos(), normalizedForce * 1.5, 5, 0.15, 200)
        end
    end
end

end --SERVER
