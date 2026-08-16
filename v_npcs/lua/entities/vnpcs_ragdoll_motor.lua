AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.Spawnable = false
ENT.PrintName = "V-NPCs Prey Ragdoll Motor"

--[[
    Active ragdoll motor for swallowed prey.

    This is the torque-motor half of the active ragdoll, in the same shape real
    Euphoria-style systems use: a hidden "puppet" entity plays a struggle
    animation, and every physics object on the prey ragdoll is driven toward its
    corresponding puppet bone by a motor whose strength we modulate. Nothing is
    keyframed onto the ragdoll itself -- it is physics the whole way down, so it
    collides, braces and gets shoved around like a body rather than a puppet.

    The motor primitive is PhysObj:ComputeShadowControl, run from a motion
    controller. That is the only way to get per-joint motor behaviour out of
    Source from Lua.

    Strength is driven from two values the belly already tracks:

      Integrity       -- fresh prey braces hard, and goes limp on its own as it
                         digests. The "life draining out" arc is emergent rather
                         than animated.
      StruggleIntensity -- mashing spikes the motor and switches behaviour state.

    Containment is analytic rather than collision-based: the belly model has no
    interior hull, so physics objects are clamped inside an ellipsoid. That is
    cheaper and far more stable than real collision, and the penetration depth
    falls straight out as a value the belly's flex grid can consume.

    NOTE: this is a first pass. The damping/strength constants below almost
    certainly need in-game iteration -- Source's constraint solver is prone to
    jitter under motor forces, and that cannot be tuned without playtesting.
    Everything is exposed as a convar for exactly that reason.
]]

if CLIENT then return end

--[[
    Resolved lazily: these convars are created by belly_modules/activeragdoll.lua,
    which is not guaranteed to have loaded when this entity file runs.
]]
local cvarStrength, cvarDamping

local function motorStrength()
    cvarStrength = cvarStrength or GetConVar("vnpcs_activeragdoll_strength")
    return cvarStrength and cvarStrength:GetFloat() or 1
end

local function motorDamping()
    cvarDamping = cvarDamping or GetConVar("vnpcs_activeragdoll_damping")
    return cvarDamping and cvarDamping:GetFloat() or 0.8
end

--[[
    Sequences to look for on the prey, best first. There is no standard "being
    swallowed" animation, so these are ordinary sequences that read as flailing.
    An NPC can override the list with ENT.PreyStruggleSequences.
]]
local STRUGGLE_SEQUENCES = {
    "swim_all",
    "swimming",
    "swim",
    "jump",
    "cower",
    "flinch01",
    "idle_all_scared",
    "idle_all_angry",
    "idle_all_01",
    "idle01",
    "idle"
}

function ENT:Initialize()
    local ragdoll = self.Ragdoll

    if not IsValid(ragdoll) then
        self:Remove()
        return
    end

    self:SetModel("models/hunter/blocks/cube025x025x025.mdl")
    self:SetNoDraw(true)
    self:SetSolid(SOLID_NONE)
    self:SetMoveType(MOVETYPE_NONE)
    self:DrawShadow(false)

    self.ShadowParams = {}
    self.Contacts = {}
    self.Strength = 1
    self.PhysBones = {}

    --[[
        A prop_ragdoll is not a scripted entity, so it cannot own a motion
        controller itself. This entity owns it on the ragdoll's behalf and adds
        each of its physics objects.
    ]]
    self:StartMotionController()

    for index = 0, ragdoll:GetPhysicsObjectCount() - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(index)
        if IsValid(phys) then
            phys:EnableGravity(false)
            phys:EnableDrag(false)
            phys:SetDamping(1.2, 3)
            phys:Wake()

            self:AddToMotionController(phys)

            self.PhysBones[phys:GetIndex()] = ragdoll:TranslatePhysBoneToBone(index)
        end
    end
end

function ENT:SetupMotor(ragdoll, puppet, belly, prey)
    self.Ragdoll = ragdoll
    self.Puppet = puppet
    self.Belly = belly
    self.Prey = prey
end

--[[
    Picks the animation the puppet drives the ragdoll towards.
]]
function ENT:SelectStruggleSequence()
    local puppet = self.Puppet
    if not IsValid(puppet) then return end

    local candidates = self.StruggleSequences or STRUGGLE_SEQUENCES

    for _, name in ipairs(candidates) do
        local seq = puppet:LookupSequence(name)
        if seq and seq >= 0 then
            puppet:ResetSequence(seq)
            puppet:SetCycle(math.Rand(0, 1))
            return seq
        end
    end

    puppet:ResetSequence(0)
    return 0
end

--[[
    Motor strength, 0 (limp) to 1 (bracing hard).

    Integrity sets the ceiling, so a mostly digested prey physically cannot
    fight hard any more; struggle input drives it up towards that ceiling.
]]
function ENT:UpdateStrength()
    local belly = self.Belly
    local prey = self.Prey

    local integrity = 1
    local intensity = 0

    if IsValid(belly) then
        intensity = math.Clamp(belly:GetNWFloat("StruggleIntensity", 0), 0, 1)

        if belly.GetPreyIndex and IsValid(prey) then
            local _, entry = belly:GetPreyIndex(prey)
            if entry then integrity = math.Clamp(entry.Integrity or 1, 0, 1) end
        end
    end

    -- a body that is falling apart cannot brace, however hard the player mashes
    local ceiling = integrity * integrity
    local target = math.Clamp((0.25 + intensity * 0.85) * ceiling, 0, 1)

    -- ease so the body tenses and slackens rather than snapping between states
    self.Strength = Lerp(0.12, self.Strength or 0, target)

    return self.Strength
end

function ENT:GetContainment()
    local belly = self.Belly
    if not IsValid(belly) then return nil end

    local size = math.max(belly:GetNWFloat("BellySize", 0), 0.2)
    local center = belly:WorldSpaceCenter()

    -- the belly bone scales roughly uniformly; these are in belly-local units
    local radius = 14 + size * 22

    return center, Vector(radius, radius * 0.85, radius * 0.8)
end

--[[
    Called once per physics object per physics tick. This is the motor.
]]
function ENT:PhysicsSimulate(phys, deltatime)
    if not IsValid(phys) then return SIM_NOTHING end

    local ragdoll = self.Ragdoll
    local puppet = self.Puppet

    if not IsValid(ragdoll) or not IsValid(puppet) then
        self:Remove()
        return SIM_NOTHING
    end

    local bone = self.PhysBones[phys:GetIndex()]
    if not bone then return SIM_NOTHING end

    local targetPos, targetAng = puppet:GetBonePosition(bone)
    if not targetPos then return SIM_NOTHING end

    local strength = self.Strength or 0
    local params = self.ShadowParams

    --[[
        secondstoarrive is the muscle: a low value is a stiff joint that snaps to
        the animation, a high one is a slack joint that drifts. Scaling it by
        strength is what makes the body tense up and go limp.
    ]]
    local baseStrength = motorStrength()
    local damping = motorDamping()

    params.secondstoarrive = math.Clamp(0.85 - strength * baseStrength * 0.7, 0.08, 1.5)
    params.pos = targetPos
    params.angle = targetAng
    params.maxangular = 3000 * strength + 200
    params.maxangulardamp = 8000
    params.maxspeed = 1200 * strength + 100
    params.maxspeeddamp = 4000
    params.dampfactor = damping
    params.teleportdistance = 0 -- never teleport; a limb outside the belly must be pushed back, not warped
    params.deltatime = deltatime

    phys:Wake()
    phys:ComputeShadowControl(params)

    -- keep the body inside the stomach, and record how hard it is pressing out
    local center, radii = self:GetContainment()
    if center then
        local pos = phys:GetPos()
        local delta = pos - center

        local nx = delta.x / radii.x
        local ny = delta.y / radii.y
        local nz = delta.z / radii.z
        local dist = math.sqrt(nx * nx + ny * ny + nz * nz)

        if dist > 1 then
            local penetration = dist - 1

            phys:SetPos(center + delta / dist, true)

            local normal = delta:GetNormalized()
            local vel = phys:GetVelocity()
            local outward = vel:Dot(normal)

            if outward > 0 then
                -- bleed off outward speed so limbs push and slide rather than escape
                phys:SetVelocity(vel - normal * outward * 1.35)
            end

            self.Contacts[phys:GetIndex()] = {
                normal = normal,
                depth = math.min(penetration, 1),
                time = CurTime()
            }
        else
            self.Contacts[phys:GetIndex()] = nil
        end
    end

    return SIM_NOTHING
end

function ENT:Think()
    local ragdoll = self.Ragdoll
    local puppet = self.Puppet

    if not IsValid(ragdoll) or not IsValid(puppet) or not IsValid(self.Belly) then
        self:Remove()
        return
    end

    self:UpdateStrength()

    local center = self:GetContainment()
    if center then
        --[[
            Keep the puppet centred on the belly so its bone positions are valid
            targets in world space. It is never drawn or networked.
        ]]
        puppet:SetPos(center)

        -- struggle animation plays faster the harder the prey is fighting
        puppet:SetPlaybackRate(0.35 + (self.Strength or 0) * 1.3)
        puppet:FrameAdvance(FrameTime())
    end

    self:NextThink(CurTime())
    return true
end

function ENT:OnRemove()
    if IsValid(self.Puppet) then self.Puppet:Remove() end
    if IsValid(self.Ragdoll) then self.Ragdoll:Remove() end
end
