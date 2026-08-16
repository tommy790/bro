--[[
    Active ragdoll prey bodies.

    When enabled, a swallowed prey's *body* becomes a real physics ragdoll driven
    by an active motor (see entities/vnpcs_ragdoll_motor.lua) instead of the prey
    entity simply being hidden. The ragdoll is the authoritative physical
    representation: it is what simulates, what is contained by the stomach walls,
    and what the belly's flex grid reads from.

    On players the original entity is unavoidably retained as a hidden shell --
    a Player cannot be removed and re-created, it owns the client connection and
    the belly camera. On NPCs the same approach is used for consistency and so
    that regurgitation can hand back the original AI rather than a fresh copy.

    Clients read the ragdoll's bones directly (it is a networked entity), so the
    belly deformation costs no extra networking at all -- see
    belly_modules/animations.lua.

    Disabled by default. This is a physics feature that needs in-game tuning, and
    the addon must keep working without it.
]]

local ragdolls_enabled = CreateConVar("vnpcs_activeragdoll", "0",
    {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED},
    "Give swallowed prey a real active-ragdoll body instead of hiding it. Experimental.")

CreateConVar("vnpcs_activeragdoll_strength", "1",
    {FCVAR_ARCHIVE, FCVAR_REPLICATED},
    "Muscle strength of struggling prey ragdolls.")

CreateConVar("vnpcs_activeragdoll_damping", "0.8",
    {FCVAR_ARCHIVE, FCVAR_REPLICATED},
    "Motor damping. Raise this if ragdolls jitter.")

local ragdoll_budget = CreateConVar("vnpcs_activeragdoll_budget", "4",
    {FCVAR_ARCHIVE, FCVAR_REPLICATED},
    "Maximum simultaneous prey ragdolls per belly. Each one is a full physics body.")

-- how many ragdoll slots are networked to clients for flex feedback
VNPCS_RAGDOLL_SLOTS = 4

function ENT:IsActiveRagdollEnabled()
    return ragdolls_enabled:GetBool()
end

--[[
    Publishes the live ragdolls so the client can read their bones for belly
    deformation. Slot count is fixed and small, which doubles as the budget.
]]
function ENT:UpdateRagdollSlots()
    local slot = 0

    for _, entry in ipairs(self.Prey) do
        if IsValid(entry.Ragdoll) and slot < VNPCS_RAGDOLL_SLOTS then
            slot = slot + 1
            self:SetNWEntity("PreyRagdoll" .. slot, entry.Ragdoll)
        end
    end

    for empty = slot + 1, VNPCS_RAGDOLL_SLOTS do
        self:SetNWEntity("PreyRagdoll" .. empty, NULL)
    end

    self:SetNWInt("PreyRagdollCount", slot)
end

function ENT:CountActiveRagdolls()
    local count = 0

    for _, entry in ipairs(self.Prey) do
        if IsValid(entry.Ragdoll) then count = count + 1 end
    end

    return count
end

--[[
    Builds the physics body for a prey entry. Returns the ragdoll, or nil if
    active ragdolls are off, over budget, or the model has no ragdoll physics.
]]
function ENT:CreatePreyRagdoll(entry)
    if not SERVER then return nil end
    if not self:IsActiveRagdollEnabled() then return nil end

    local prey = entry.Entity
    if not IsValid(prey) then return nil end

    local model = prey:GetModel()
    if not model or model == "" then return nil end

    if self:CountActiveRagdolls() >= math.max(ragdoll_budget:GetInt(), 0) then
        return nil
    end

    local ragdoll = ents.Create("prop_ragdoll")
    if not IsValid(ragdoll) then return nil end

    ragdoll:SetModel(model)
    ragdoll:SetPos(self:WorldSpaceCenter())
    ragdoll:SetAngles(Angle(0, 0, 0))
    ragdoll:Spawn()
    ragdoll:Activate()

    -- a model with no ragdoll physics is useless to us; fall back to hiding
    if ragdoll:GetPhysicsObjectCount() <= 1 then
        ragdoll:Remove()
        return nil
    end

    ragdoll:SetSkin(prey:GetSkin() or 0)
    for id = 0, (prey:GetNumBodyGroups() or 1) - 1 do
        ragdoll:SetBodygroup(id, prey:GetBodygroup(id) or 0)
    end
    ragdoll:SetColor(prey:GetColor())
    ragdoll:SetMaterial(prey:GetMaterial() or "")

    --[[
        The body lives inside a stomach: it must not collide with the world, the
        predator, or anything else. Containment is handled analytically by the
        motor instead.
    ]]
    ragdoll:SetCollisionGroup(COLLISION_GROUP_WORLD)
    ragdoll:SetOwner(self)
    ragdoll:DrawShadow(false)

    -- the animated puppet the motor drives the ragdoll towards
    local puppet = ents.Create("prop_dynamic")
    if not IsValid(puppet) then
        ragdoll:Remove()
        return nil
    end

    puppet:SetModel(model)
    puppet:SetPos(self:WorldSpaceCenter())
    puppet:SetAngles(Angle(0, 0, 0))
    puppet:Spawn()
    puppet:SetNoDraw(true)
    puppet:SetSolid(SOLID_NONE)
    puppet:SetMoveType(MOVETYPE_NONE)
    puppet:DrawShadow(false)
    puppet:SetCollisionGroup(COLLISION_GROUP_WORLD)

    local motor = ents.Create("vnpcs_ragdoll_motor")
    if not IsValid(motor) then
        ragdoll:Remove()
        puppet:Remove()
        return nil
    end

    motor:SetupMotor(ragdoll, puppet, self, prey)
    motor.StruggleSequences = prey.PreyStruggleSequences
    motor:SetPos(self:WorldSpaceCenter())
    motor:Spawn()
    motor:Activate()
    motor:SelectStruggleSequence()

    entry.Ragdoll = ragdoll
    entry.RagdollMotor = motor

    self:UpdateRagdollSlots()

    return ragdoll
end

function ENT:RemovePreyRagdoll(entry)
    if not entry then return end

    -- the motor owns both the puppet and the ragdoll and cleans them up
    if IsValid(entry.RagdollMotor) then
        entry.RagdollMotor:Remove()
    else
        if IsValid(entry.Ragdoll) then entry.Ragdoll:Remove() end
    end

    entry.Ragdoll = nil
    entry.RagdollMotor = nil

    self:UpdateRagdollSlots()
end

function ENT:RemoveAllPreyRagdolls()
    self:InitBellyState()

    for _, entry in ipairs(self.Prey) do
        self:RemovePreyRagdoll(entry)
    end
end
