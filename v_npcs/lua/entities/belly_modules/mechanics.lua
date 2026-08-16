--[[
DIGESTION PHASES

0 = Base, no explict logic for this
1 = Alive prey, struggling within the stomach
2 = All Digested prey, absorption happening 

]]

ENT.DigestionPhase = 0
ENT.DigestionStrength = 2
ENT.AbsorptionPower = 2

--[[
    NOTE: do NOT declare `ENT.Prey = {}` here.

    A table declared on the ENT class table is shared by every instance of that
    class, so every belly in the map would insert into the same prey list.
    `InitBellyState` below creates the list on the entity's own table instead.
]]
ENT.VoreBelly = true
--[[ 
    {
        Value : number; --goes down while absorbing
        TrueValue : number; --this isnt affected
        Entity : ENT; --entity, will turn nil when dead 
        Alive : boolean; --is an object or not
        Absorbing : boolean; --getting absorbed
        OldFlags : {

        };
    }
]]

local global_digestion_multi = CreateConVar("vnpcs_digestion_multi", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED})
local global_absorption_multi = CreateConVar("vnpcs_absorption_multi", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED})

local force_digestion = CreateConVar("vnpcs_global_digestion", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED})
local force_absorption = CreateConVar("vnpcs_global_absorption", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED})

--[[
    How "much" a prey is, for belly size and digestion time.

    This used to be `maxs:Length()`, which measures the distance to a corner of
    the bounding box: a 200-unit plank read as bigger than a player while a fat
    crate read as tiny. A cube root of the box volume is a fair stand-in for
    mass regardless of shape.

    PREY_VALUE_CALIBRATION keeps the resulting numbers on the same scale as the
    old measurement for a human-sized prey, so belly sizes and every tuning
    constant derived from them stay where they were.
]]
local PREY_VALUE_CALIBRATION = 1.8

local function getModelBounds(ent)
    local mins, maxs = ent:GetModelBounds()
    local size = maxs - mins
    local scale = ent:GetModelScale() or 1

    local volume = math.abs(size.x * size.y * size.z) * (scale * scale * scale)
    if volume <= 0 then return 1 end

    return math.pow(volume, 1/3) * PREY_VALUE_CALIBRATION
end

local function GetFlags(ent)
    return {
        Solid = ent:GetSolid(),
        MoveType = ent:GetMoveType(),
        Flags = ent:GetFlags();
    }
end

local function SetFlags(ent, flags)
    ent:SetSolid(flags.Solid)
    ent:SetMoveType(flags.MoveType)
    ent:RemoveEFlags(EFL_NOCLIP_ACTIVE)
    ent:SetFlags(flags.Flags)
end

--[[     STATE      ]]

--[[
    Creates the per-instance prey list on the entity's own table.

    `rawget` deliberately bypasses the class metatable so an inherited (shared)
    table is never mistaken for an instance one. Idempotent and cheap, so it is
    safe to call from every entry point rather than relying on subclasses
    remembering to call it from Initialize.
]]
function ENT:InitBellyState()
    local tbl = self:GetTable()
    local prey = rawget(tbl, "Prey")

    if not prey then
        prey = {}
        tbl.Prey = prey
    end

    return prey
end

--[[     HOOKS      ]]

--when a prey gets eaten
function ENT:OnPreyAdded(prey_index, value, npc) end --number, number, ent

--digested prey getting absorbed
function ENT:OnPreyAbsorbing(power, old_value, new_value) end --number, number, number
--a prey finally absorbed it all, theyre gone!!!
function ENT:OnPreyAbsorbed() end

--when a prey is getting digested, still alive
function ENT:OnPreyDigesting(prey_index, dmg) end --number, number
--prey died or got fully digested
function ENT:OnPreyKilled() end
--digestion phase, 1 == alive prey, 2 == all dead prey, 0 == nothing in belly
function ENT:OnDigestionPhaseChanged(new, old) end --number, number

function ENT:OnRegurgitate(ent) end

--[[               ]]


function ENT:ChangeDigestionPhase(new) --this is here just for the hook
    local old = self.DigestionPhase
    self.DigestionPhase = new

    self:SetNWInt("DigestionPhase", new)
    if self.NPC then
        self:SetNWInt("DigestionPhase", new)
    end

    self:OnDigestionPhaseChanged(new, old)
end

function ENT:AddPrey(prey)
    self:InitBellyState()

    if table.HasValue(self.Prey, prey) then return false end
    if prey.Vored then return false end

    -- something that just struggled free gets a grace period
    if prey.VoreEscapeCooldown and CurTime() < prey.VoreEscapeCooldown then return false end

    if self.EatCondition then
        if not self:EatCondition(prey) then
            return false
        end
    end

    prey.Vored = true 
    local is_player, is_npc, is_nextbot = prey:IsPlayer(), prey:IsNPC(), prey:IsNextBot()

    if is_player then
        net.Start("UGotVored")
        net.WriteEntity(self)
        net.WriteEntity(self.NPC)
        net.Send(prey)
        --prey:RemoveAllItems() --dogshit fix but we roll
        prey:SetActiveWeapon(nil)
        if prey:InVehicle() then --goodbye vehicle
            prey:ExitVehicle()
        end
    elseif is_npc or is_nextbot then
        prey:NextThink(CurTime() + 1e9) --makes it never think ever
    end

    prey:SetVelocity(Vector(0,0,0))

    local old_flags = GetFlags(prey)
    --PrintTable(old_flags)

	prey:SetSolid(0)
    prey:SetMoveType(MOVETYPE_NONE)
    prey:AddEFlags(EFL_NOCLIP_ACTIVE)
    prey:AddFlags(FL_NOTARGET)
    prey:SetNoDraw(true)

    if is_npc then
        prey:SetSchedule(SCHED_NPC_FREEZE)
        prey:DropWeapon()
        prey:SetEnemy(nil)
    end

    if not is_player then
        prey:SetPos(self:GetPos())
        prey:SetParent(self)

        --[[
            only npcs get parented because they cant see,
            aka if a player is under the map or out of bounds entities arent rendered and sometimes players do that when they get parented so ya
        ]]
    end

    local preyValue = getModelBounds(prey)
    local isAlive = is_npc or is_player or is_nextbot or false

    --[[
        Digestion no longer runs on the entity's health, so the two hacks that
        used to live here are gone: bumping every prey to at least 25 hp (which
        *healed* wounded NPCs on the way in) and giving props a fake health pool.
        See GetDigestionTime.
    ]]

    local prey_table = {
        Value = preyValue;
        TrueValue = preyValue;
        Alive = isAlive;
        Entity = prey;
        Absorbing = false;
        OldFlags = old_flags;
        Escape = 0;                        --struggle progress, 0..1
        Integrity = 1;                     --1 = whole, 0 = fully broken down
        MaxHealth = math.max(prey:Health(), 1); --health on the way in, mirrored from Integrity
    }

    --[[
        Back reference so an input hook can find the belly holding this entity
        without searching every belly in the map.
    ]]
    prey.VorePredatorBelly = self

    local prey_index = table.insert(self.Prey, prey_table)

    -- give it a real physics body if active ragdolls are on (no-op otherwise)
    if self.CreatePreyRagdoll then
        self:CreatePreyRagdoll(prey_table)
    end

    self:ChangeDigestionPhase(1)
    self:OnPreyAdded(prey_index, preyValue, prey)
    self:SetNWInt("AliveFactor", self:GetAliveFactor()) --uhhh probably shouldnt be in mechanics but idc, this number is used for animations

    return true 
end

function ENT:AbsorbPrey(dt)
    self:InitBellyState()

    if #self.Prey == 0 then
        return false
    end

    local absorbing = false
    local absorptionPower = self.AbsorptionPower
    if force_absorption:GetBool() then
        absorptionPower = global_absorption_multi:GetFloat()
    else
        absorptionPower = absorptionPower * global_absorption_multi:GetFloat()
    end

    for i = #self.Prey, 1, -1 do
        local prey_table = self.Prey[i]
        if not prey_table.Absorbing then continue end
        absorbing = true

        local abosorbPreyPower = absorptionPower * dt * 2
        local oldPreyValue = prey_table.Value

        if oldPreyValue < 40 then
            abosorbPreyPower = abosorbPreyPower * 3
        end

        abosorbPreyPower = (math.min(oldPreyValue, abosorbPreyPower))

        prey_table.Value = oldPreyValue - abosorbPreyPower
        self:OnPreyAbsorbing(abosorbPreyPower, oldPreyValue, prey_table.Value) 

        if prey_table.Value <= 0 then
            table.remove(self.Prey, i)
            self:OnPreyAbsorbed()

            if #self.Prey == 0 then
                self:ChangeDigestionPhase(0) --belly full of nothing
            end
        end
    end

    return absorbing
end

function ENT:AbsorbSpecificPrey(index)
    local entry = self.Prey[index]
    if not entry then return end

    entry.Absorbing = true

    if self.RemovePreyRagdoll then
        self:RemovePreyRagdoll(entry)
    end

    local prey = entry.Entity

    if IsValid(prey) then
        prey.Vored = false
        prey.VorePredatorBelly = nil

        --[[
            Same rule as WipeAllPrey: never Remove() a Player -- it is
            unsupported and can break the player slot. This is the ordinary
            "prey finished digesting" path, so it is the one players actually
            hit.

            They are deliberately NOT released here. A digested player stays
            nodraw'd inside with the belly camera and the "You have been
            digested..." HUD until they respawn, and PlayerSpawn in
            autorun/server/convars.lua does the real cleanup.
        ]]
        if prey:IsPlayer() then
            if prey:Alive() then prey:Kill() end
        else
            prey:Remove()
        end
    end

    entry.Entity = nil
    self:OnPreyKilled()
    self:SetNWInt("AliveFactor", self:GetAliveFactor()) --uhhh probably shouldnt be in mechanics but idc, this number is used for animations

    if self.DigestionPhase ~= 2 then
        local allAbosrbing = true 
        for i,v in ipairs(self.Prey) do
            if not v.Absorbing then
                allAbosrbing = false
                break
            end
        end
        
        if allAbosrbing then
            self:ChangeDigestionPhase(2) --belly to absorb
        end
    end
end

--[[
    Seconds to fully digest `entry`, at the current settings.

    Digestion is a clock driven by how big the prey is, not by how much health
    it happens to have. That fixes three things at once: a 1000 hp boss no
    longer takes eight minutes while a 5 hp headcrab vanishes instantly, props
    no longer need a fake health pool, and another addon healing the prey can no
    longer stall or desync the belly.

    Calibrated against the old behaviour: a human-sized prey (value ~75) in a
    DigestionStrength 1 belly took 100hp / 2dps = 50 seconds, and still does.
]]
local REFERENCE_DIGEST_TIME = 50
local REFERENCE_PREY_VALUE = 75

function ENT:GetDigestionTime(entry)
    local strength = self.DigestionStrength or 1
    if force_digestion:GetBool() then
        strength = global_digestion_multi:GetFloat()
    else
        strength = strength * global_digestion_multi:GetFloat()
    end

    strength = math.max(strength, 0.01)

    local mass = math.max(entry.TrueValue or REFERENCE_PREY_VALUE, 1)

    return (REFERENCE_DIGEST_TIME / strength) * (mass / REFERENCE_PREY_VALUE)
end

--[[
    Mirrors Integrity onto a living prey's health, so death, damage hooks and
    anything else watching health still behave normally -- health is now a
    *presentation* of digestion rather than its source of truth.

    Because the target is recomputed from Integrity every tick rather than
    subtracted, healing the prey mid-digestion just gets re-applied next tick
    instead of permanently extending the timer.
]]
function ENT:ApplyDigestionDamage(entry, prey)
    local maxHealth = math.max(entry.MaxHealth or 1, 1)
    local target = maxHealth * math.max(entry.Integrity, 0)
    local current = prey:Health()
    local damage = current - target

    if damage <= 0 then return end

    local dmg_i = DamageInfo()
    local npc = self.NPC
    if IsValid(npc) then
        dmg_i:SetAttacker(npc)
        dmg_i:SetInflictor(npc)
    end
    dmg_i:SetDamageType(DMG_REMOVENORAGDOLL)
    dmg_i:SetDamage(damage)

    prey:TakeDamageInfo(dmg_i)
end

function ENT:DigestPrey(dt)
    self:InitBellyState()

    if #self.Prey == 0 then return 0, 0, 0 end

    local livingPrey = 0
    local preyInTotal = 0
    local totalDigested = 0

    for i = #self.Prey, 1, -1 do
        local entry = self.Prey[i]
        if entry.Absorbing then continue end

        preyInTotal = preyInTotal + 1

        local prey = entry.Entity
        if not IsValid(prey) then
            self:AbsorbSpecificPrey(i)
            continue
        end

        local before = entry.Integrity or 1
        local after = math.max(before - dt / self:GetDigestionTime(entry), 0)
        entry.Integrity = after

        local consumed = before - after
        -- "how much matter was broken down", which is what feeds the predator
        totalDigested = totalDigested + consumed * (entry.TrueValue or 0)

        if entry.Alive then
            self:ApplyDigestionDamage(entry, prey)

            if prey:Health() > 0 then
                livingPrey = livingPrey + 1
            end
        end

        self:OnPreyDigesting(i, consumed)

        --[[
            Living prey is only finished once it is actually dead, so anything
            genuinely invulnerable (godmode, buddha) stays in the belly rather
            than being deleted out from under its own protection -- which is how
            the health-driven version behaved too.
        ]]
        if entry.Alive then
            if prey:Health() <= 0 then
                self:AbsorbSpecificPrey(i)
            end
        elseif after <= 0 then
            self:AbsorbSpecificPrey(i)
        end
    end

    return livingPrey, preyInTotal, totalDigested
end

function ENT:ReleasePreyEntity(prey, oldFlags)
    if not IsValid(prey) then return end

    -- the physics body only exists while swallowed
    if self.GetPreyIndex and self.RemovePreyRagdoll then
        local _, entry = self:GetPreyIndex(prey)
        if entry then self:RemovePreyRagdoll(entry) end
    end

    prey.Vored = false
    prey.VorePredatorBelly = nil

    if prey:IsPlayer() then
        prey:SetNW2Float("VoreEscapeProgress", 0)
    end

    prey:SetParent(nil)
    prey:SetNoDraw(false)
    prey:SetVelocity(Vector(0, 0, 0))

    if oldFlags then
        SetFlags(prey, oldFlags)
    else
        prey:RemoveEFlags(EFL_NOCLIP_ACTIVE)
        prey:RemoveFlags(FL_NOTARGET)
    end

    if prey:IsPlayer() then
        -- release the CalcView / HUD / weapon lock installed by AddPrey
        net.Start("StopVoreClient")
        net.Send(prey)
    elseif prey:IsNPC() then
        prey:NextThink(CurTime())
        prey:SetSchedule(SCHED_IDLE_STAND)
    elseif prey:IsNextBot() then
        prey:NextThink(CurTime())
    end
end

function ENT:Regurgitate(index)
    self:InitBellyState()

    local info = self.Prey[index]
    if not info then return false end
    if info.Absorbing then return false end

    local prey = info.Entity

    if not prey then return false end
    if not IsValid(prey) then return false end

    table.remove(self.Prey, index)

    self:ReleasePreyEntity(prey, info.OldFlags)

    if #self.Prey == 0 then
        self:ChangeDigestionPhase(0)
    end

    self:SetNWInt("AliveFactor", self:GetAliveFactor())

    self:OnRegurgitate(prey)
    return true
end

function ENT:RegurgitateENT(ent)
    self:InitBellyState()

    for index, info in ipairs(self.Prey) do
        if not info.Entity then continue end
        if info.Absorbing then continue end

        if info.Entity == ent then
            return self:Regurgitate(index)
        end
    end

    return false
end

function ENT:GetCollectivePreyValue() --: number
    self:InitBellyState()

    local total = 0

    for _, prey in ipairs(self.Prey) do
        local value = prey.Value
        total = total + value
    end

    return total
end

function ENT:GetAliveFactor() --: number
    self:InitBellyState()

    local total = 0

    for _, prey in ipairs(self.Prey) do
        local isAlive = prey.Alive
        if isAlive then
            total = total + 1
        end
    end

    return total
end

function ENT:SetDigestionPower(num)
    self.DigestionStrength = num
end

function ENT:SetAbsorbPower(num)
    self.AbsorptionPower = num
end

function ENT:WipeAllPrey()
    self:InitBellyState()

    if self.RemoveAllPreyRagdolls then
        self:RemoveAllPreyRagdolls()
    end

    for i, prey in ipairs(self.Prey) do
        local preyEnt = prey.Entity
        if preyEnt and IsValid(preyEnt) then
            preyEnt:SetParent(nil)
            preyEnt.Vored = false

            local dmg_i = DamageInfo()
            dmg_i:SetDamageType(DMG_REMOVENORAGDOLL)
            dmg_i:SetDamage(9999999)
            preyEnt:TakeDamageInfo(dmg_i)

            --[[
                Entity:Remove() on a Player is unsupported and can break the
                player slot or crash the server. Kill them and hand control
                back instead; the damage above has already finished them off in
                practice, Kill() is the belt-and-braces path.
            ]]
            if preyEnt:IsPlayer() then
                if preyEnt:Alive() then
                    preyEnt:Kill()
                end

                self:ReleasePreyEntity(preyEnt, prey.OldFlags)
            else
                preyEnt:Remove()
            end
        end
    end

    table.Empty(self.Prey)
end

function ENT:SetNPC(npc)
    self.NPC = npc
    self:SetNWEntity("NPCParent", npc)
end