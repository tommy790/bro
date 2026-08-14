--[[
DIGESTION PHASES

0 = Base, no explict logic for this
1 = Alive prey, struggling within the stomach
2 = All Digested prey, absorption happening 

]]

ENT.DigestionPhase = 0
ENT.DigestionStrength = 2
ENT.AbsorptionPower = 2

ENT.Prey = {}
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

local function getModelBounds(ent, scale)
    if VNPC_CalculatePreyValue then
        return VNPC_CalculatePreyValue(ent, scale)
    end
    local _, max_bounds = ent:GetModelBounds()
    return max_bounds:Length() * (scale or ent:GetModelScale() or 1)
end

local function GetFlags(ent)
    local solid, move, flags = SOLID_BBOX, MOVETYPE_STEP, 0
    if ent.GetSolid then
        local ok, v = pcall(ent.GetSolid, ent)
        if ok then solid = v end
    end
    if ent.GetMoveType then
        local ok, v = pcall(ent.GetMoveType, ent)
        if ok then move = v end
    end
    if ent.GetFlags then
        local ok, v = pcall(ent.GetFlags, ent)
        if ok then flags = v or 0 end
    end
    return {
        Solid = solid,
        MoveType = move,
        Flags = flags
    }
end

local function SetFlags(ent, flags)
    if not IsValid(ent) then return end
    flags = istable(flags) and flags or {}

    if ent.SetSolid then
        ent:SetSolid(flags.Solid ~= nil and flags.Solid or SOLID_BBOX)
    end
    if ent.SetMoveType then
        local mt = flags.MoveType
        if mt == nil then
            mt = ent:IsPlayer() and MOVETYPE_WALK or MOVETYPE_STEP
        end
        ent:SetMoveType(mt)
    end
    if ent.RemoveEFlags then
        ent:RemoveEFlags(EFL_NOCLIP_ACTIVE)
    end

    -- GMod entities have AddFlags/RemoveFlags, not SetFlags.
    local want = flags.Flags
    if ent.SetFlags and want ~= nil then
        local ok = pcall(ent.SetFlags, ent, want)
        if ok then return end
    end
    if want ~= nil and ent.GetFlags and ent.AddFlags and ent.RemoveFlags and bit then
        local current = ent:GetFlags() or 0
        local extra = bit.band(current, bit.bnot(want))
        if extra ~= 0 then pcall(ent.RemoveFlags, ent, extra) end
        local missing = bit.band(want, bit.bnot(current))
        if missing ~= 0 then pcall(ent.AddFlags, ent, missing) end
    elseif ent.RemoveFlags then
        ent:RemoveFlags(FL_NOTARGET)
    end
end

--[[     HOOKS      ]]

CreateConVar("vnpcs_capacity_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enforce a max belly capacity per predator (modular trait system can raise/lower it)")
CreateConVar("vnpcs_capacity_base", "1600", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Base belly capacity in prey-value units (~1 human = 100-250 value)")

-- Max capacity in prey-value units for a belly, scaled by the predator's
-- capacity trait (big_stomach, small_stomach, glutton, ...) and level bonus.
function VNPC_GetBellyCapacity(belly, npc)
    local cv = GetConVar("vnpcs_capacity_enabled")
    if cv and not cv:GetBool() then return math.huge end
    local base = GetConVar("vnpcs_capacity_base")
    local cap = base and base:GetFloat() or 1600

    if VNPC_GetTraitStat and IsValid(npc) then
        cap = cap * VNPC_GetTraitStat(npc, "capacity")
    end
    if IsValid(belly) and belly.VNPC_LevelCapacityBonus then
        cap = cap + belly.VNPC_LevelCapacityBonus * 120
    end
    return math.max(50, cap)
end

function VNPC_GetBellyRemainingCapacity(belly)
    if not IsValid(belly) or not istable(belly.Prey) then return 0 end
    local cap = VNPC_GetBellyCapacity(belly, belly.NPC)
    local used = 0
    for _, info in ipairs(belly.Prey) do
        if istable(info) and not info.Absorbing then
            used = used + (info.Value or 0)
        end
    end
    return math.max(0, cap - used)
end

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

function VNPC_HideSwallowedPrey(prey, belly)
    if not IsValid(prey) then return end
    prey:SetNoDraw(true)
    prey:AddEffects(EF_NODRAW)
    prey:SetRenderMode(RENDERMODE_NONE)
    prey:SetColor(Color(0, 0, 0, 0))
    prey:DrawShadow(false)
    prey:SetSolid(SOLID_NONE)
    prey:SetMoveType(MOVETYPE_NONE)
    if IsValid(belly) and not prey:IsPlayer() then
        prey:SetPos(belly:GetPos())
        prey:SetParent(belly)
    end
end

function VNPC_UnhideRegurgitatedPrey(prey)
    if not IsValid(prey) then return end
    prey:SetNoDraw(false)
    prey:RemoveEffects(EF_NODRAW)
    prey:SetRenderMode(RENDERMODE_NORMAL)
    prey:SetColor(Color(255, 255, 255, 255))
    prey:DrawShadow(true)
end

hook.Add("Think", "VNPCS_SwallowedPrey_SafetyLoop", function()
    local now = CurTime()
    if (VNPC_NextPreySafetyThink or 0) > now then return end
    VNPC_NextPreySafetyThink = now + 0.5

    for _, belly in ipairs(ents.GetAll()) do
        if IsValid(belly) and belly.Prey and istable(belly.Prey) then
            local seen = {}
            for i = #belly.Prey, 1, -1 do
                local info = belly.Prey[i]
                local prey = info and info.Entity
                if not prey or not IsValid(prey) then
                    if info and not info.Absorbing then
                        table.remove(belly.Prey, i)
                    end
                    continue
                end

                if seen[prey] then
                    table.remove(belly.Prey, i)
                    continue
                end
                seen[prey] = true

                if prey:Health() <= 0 and not info.Absorbing and belly.AbsorbSpecificPrey then
                    if not (info.WombPrey or info.NoDigest or prey.VNPC_IsWombPrey or prey.VNPC_IsUnbornBaby) then
                        pcall(belly.AbsorbSpecificPrey, belly, i)
                    end
                    continue
                end

                if not prey.VNPC_IsBeingSwallowed then
                    prey:SetNoDraw(true)
                    prey:AddEffects(EF_NODRAW)
                    prey:SetRenderMode(RENDERMODE_NONE)
                    prey:SetColor(Color(0, 0, 0, 0))
                    prey:DrawShadow(false)
                    prey:SetSolid(SOLID_NONE)
                    prey:SetMoveType(MOVETYPE_NONE)
                    if not prey:IsPlayer() and prey:GetParent() ~= belly then
                        prey:SetParent(belly)
                        prey:SetPos(belly:GetPos())
                    end
                end
            end
        end
    end
end)

hook.Add("CreateEntityRagdoll", "VNPC_PreventSwallowedPreyRagdoll", function(owner, ragdoll)
    if IsValid(owner) and (owner.Vored or owner.VNPC_Vored or owner.VNPC_IsDeadAndAbsorbed) then
        if IsValid(ragdoll) then
            ragdoll.Vored = true
            ragdoll.VNPC_Vored = true
            ragdoll.VNPC_IsDeadAndAbsorbed = true
            ragdoll:SetNoDraw(true)
            ragdoll:SetSolid(0)
            timer.Simple(0, function()
                if IsValid(ragdoll) then ragdoll:Remove() end
            end)
        end
        return false
    end
end)

hook.Add("EntityTakeDamage", "VNPC_ProtectSwallowedPreyFromExternalDamage", function(target, dmginfo)
    if IsValid(target) and (target.Vored or target.VNPC_Vored or target.VNPC_IsDeadAndAbsorbed) then
        if dmginfo:GetDamageType() == DMG_REMOVENORAGDOLL or dmginfo:GetDamage() >= 999999 then
            return
        end
        dmginfo:SetDamage(0)
        return true
    end
end)

hook.Add("OnEntityCreated", "VNPC_PreventSwallowedDuplicateRagdoll", function(ent)
    timer.Simple(0, function()
        if not IsValid(ent) then return end
        if ent.VNPC_RagdollMatrix then return end -- kept for safety; the belly-physics ragdoll-copy system that set this flag has been removed, so this is now a dead/no-op guard
        if ent:GetClass() == "prop_ragdoll" or ent.VNPC_IsCorpse then
            local owner = ent:GetOwner()
            if IsValid(owner) and (owner.Vored or owner.VNPC_Vored or owner.VNPC_IsDeadAndAbsorbed) then
                ent.Vored = true
                ent.VNPC_Vored = true
                ent.VNPC_IsDeadAndAbsorbed = true
                ent:Remove()
                return
            end
            local parent = ent:GetParent()
            if IsValid(parent) and (parent:GetClass() == "ent_vore_belly" or parent.Vored or parent.VNPC_Vored) then
                ent.Vored = true
                ent.VNPC_Vored = true
                ent.VNPC_IsDeadAndAbsorbed = true
                ent:Remove()
                return
            end
            for _, belly in ipairs(ents.FindByClass("ent_vore_belly")) do
                if IsValid(belly) and belly.Prey and istable(belly.Prey) then
                    for _, pTable in ipairs(belly.Prey) do
                        if pTable and (not IsValid(pTable.Entity) or pTable.Entity:Health() <= 0 or pTable.Entity.VNPC_IsDeadAndAbsorbed) then
                            if ent:GetPos():DistToSqr(belly:GetPos()) < (120 * 120) then
                                ent.Vored = true
                                ent.VNPC_Vored = true
                                ent.VNPC_IsDeadAndAbsorbed = true
                                ent:Remove()
                                return
                            end
                        end
                    end
                end
            end
        end
    end)
end)

function VNPC_SwallowAttachedEntities(belly, prey)
    if not IsValid(belly) or not IsValid(prey) then return end

    local preyBelly = prey.VNPC_Belly or prey.Belly or prey.belly
    if IsValid(preyBelly) and preyBelly ~= belly then
        preyBelly.VNPC_OriginalParent = prey
        preyBelly:SetNoDraw(true)
        preyBelly:SetSolid(SOLID_NONE)
        preyBelly:SetMoveType(MOVETYPE_NONE)
        preyBelly:SetParent(belly)
        if VNPCS_BellyRT and VNPCS_BellyRT.MarkDirty then
            pcall(VNPCS_BellyRT.MarkDirty, preyBelly)
        end
    end

    if prey.GetActiveWeapon then
        local wep = prey:GetActiveWeapon()
        if IsValid(wep) then
            wep.VNPC_OriginalParent = prey
            wep:SetNoDraw(true)
            wep:SetSolid(SOLID_NONE)
            wep:SetMoveType(MOVETYPE_NONE)
            wep:SetParent(belly)
        end
    end
    if prey.GetWeapons then
        for _, wep in ipairs(prey:GetWeapons() or {}) do
            if IsValid(wep) then
                wep.VNPC_OriginalParent = prey
                wep:SetNoDraw(true)
                wep:SetSolid(SOLID_NONE)
                wep:SetMoveType(MOVETYPE_NONE)
                wep:SetParent(belly)
            end
        end
    end

    if prey.GetChildren then
        for _, child in ipairs(prey:GetChildren() or {}) do
            if IsValid(child) and child ~= belly then
                child.VNPC_OriginalParent = prey
                child:SetNoDraw(true)
                child:SetSolid(SOLID_NONE)
                child:SetMoveType(MOVETYPE_NONE)
                child:SetParent(belly)
            end
        end
    end
end

function VNPC_RegurgitateAttachedEntities(belly, prey)
    if not IsValid(belly) or not IsValid(prey) then return end

    local preyBelly = prey.VNPC_Belly or prey.Belly or prey.belly
    if IsValid(preyBelly) and preyBelly:GetParent() == belly then
        preyBelly:SetParent(prey)
        preyBelly:SetNoDraw(false)
        if VNPCS_BellyRT and VNPCS_BellyRT.MarkDirty then
            pcall(VNPCS_BellyRT.MarkDirty, preyBelly)
        end
    end

    if prey.GetActiveWeapon then
        local wep = prey:GetActiveWeapon()
        if IsValid(wep) and wep:GetParent() == belly then
            wep:SetParent(prey)
            wep:SetNoDraw(false)
        end
    end
    if prey.GetWeapons then
        for _, wep in ipairs(prey:GetWeapons() or {}) do
            if IsValid(wep) and wep:GetParent() == belly then
                wep:SetParent(prey)
                wep:SetNoDraw(false)
            end
        end
    end

    if belly.GetChildren then
        for _, child in ipairs(belly:GetChildren() or {}) do
            if IsValid(child) and child.VNPC_OriginalParent == prey then
                child:SetParent(prey)
                child:SetNoDraw(false)
                child.VNPC_OriginalParent = nil
            end
        end
    end
end

function VNPC_RemoveAttachedEntities(belly, prey)
    if not IsValid(belly) or not prey then return end
    if belly.GetChildren then
        for _, child in ipairs(belly:GetChildren() or {}) do
            if IsValid(child) and child.VNPC_OriginalParent == prey then
                child:Remove()
            end
        end
    end
end

function ENT:AddPrey(prey)
    if not IsValid(prey) then return false end
    if prey.VNPC_DigestedBone or prey.VNPC_BoneOwner or prey.VNPC_NoVore then return false end
    if IsValid(self.NPC) and VNPC_IsFamilyOrMate and VNPC_IsFamilyOrMate(self.NPC, prey) then return false end
    if not (IsValid(self.NPC) and self.NPC.VNPC_IsWildWanderer and self.NPC.VNPC_WildType == "predator") and VNPC_IsProtectedChildPrey and VNPC_IsProtectedChildPrey(prey) then return false end
    if VNPC_IsPreyEmissary and VNPC_IsPreyEmissary(prey) then return false end
    if VNPC_IsAssassinUndercover and IsValid(self.NPC) and VNPC_IsAssassinUndercover(self.NPC) then return false end
    do
        local pred = self.NPC
        local sameCamp = prey.VNPC_PreyCampID and IsValid(pred) and pred.VNPC_PreyCampID and prey.VNPC_PreyCampID == pred.VNPC_PreyCampID
        if sameCamp then
            local nightRaid = pred.VNPC_AssassinAllowCampSwallow
                or (VNPC_IsAssassinNightHunting and VNPC_IsAssassinNightHunting(pred))
            if not nightRaid then
                return false
            end
        end
    end
    for _, info in ipairs(self.Prey) do
        if info and info.Entity == prey then return false end
    end
    if prey.VNPC_IsDeadAndAbsorbed or prey.Vored or prey.VNPC_Vored then return false end
    if self.EatCondition then
        if not self:EatCondition(prey) then
            return false
        end
    end

    -- Max capacity gate (checked BEFORE any state mutation so a refused meal
    -- never leaves the prey vored/hidden). The trait system (capacity stat) and
    -- leveling (VNPC_LevelCapacityBonus) modify the limit.
    if VNPC_GetBellyCapacity then
        local capacity = VNPC_GetBellyCapacity(self, self.NPC)
        local used = self:GetCollectivePreyValue() or 0
        local incoming = getModelBounds(prey)
        if (used + incoming) > capacity then
            hook.Run("VNPC_OnBellyFull", self.NPC or self:GetOwner(), self, prey)
            return false
        end
    end

    prey.Vored = true
    if VNPC_UnfreezeRagdollPhysics then
        VNPC_UnfreezeRagdollPhysics(prey)
    end
    if VNPC_FeedHunger then
        VNPC_FeedHunger(self.NPC or self:GetOwner() or self, 40)
    end 
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

    if is_npc then
        prey:SetSchedule(SCHED_NPC_FREEZE)
        prey:SetEnemy(nil)
    end

    VNPC_SwallowAttachedEntities(self, prey)

    -- Keep the prey model visible for the oral swallow animation; hide only if it cannot start.
    prey.VNPC_IsBeingSwallowed = true
    local startedIngest = false
    if VNPC_StartIngestionAnimation then
        startedIngest = VNPC_StartIngestionAnimation(self.NPC or self:GetOwner() or self, prey, self) and true or false
    end
    if not startedIngest then
        prey.VNPC_IsBeingSwallowed = nil
        VNPC_HideSwallowedPrey(prey, self)
        if not is_player then
            prey:SetPos(self:GetPos())
            prey:SetParent(self)
        end
    end

    if prey:Health() < 25 then --fix for objects/npcs getting instantly digested, uhhhh super binary and hardcoded
        prey:SetHealth(25)
    end
    local preyValue = getModelBounds(prey)

    local isAlive = is_npc or is_player or is_nextbot or false
    if not isAlive then
        prey:SetHealth(preyValue * 3.5)
    end

    local prey_table = {
        Value = preyValue;
        TrueValue = preyValue;
        Alive = isAlive;
        Entity = prey;
        Absorbing = false;
        OldFlags = old_flags;
    }

    local prey_index = table.insert(self.Prey, prey_table)

    self:ChangeDigestionPhase(1)
    self:OnPreyAdded(prey_index, preyValue, prey)
    self:SetNWInt("AliveFactor", self:GetAliveFactor()) --uhhh probably shouldnt be in mechanics but idc, this number is used for animations

    hook.Run("VNPC_OnPreySwallowed", self.NPC or self:GetOwner() or self, prey, self)
    self:TransferPreyFrom(prey)

    return true 
end

function ENT:AddPreyGroup(prey_list)
    if not istable(prey_list) then return self:AddPrey(prey_list) end
    local count = 0
    for _, prey in ipairs(prey_list) do
        if IsValid(prey) and not prey.Vored and not prey.VNPC_Vored then
            if self:AddPrey(prey) then
                count = count + 1
            end
        end
    end
    return count > 0, count
end

function ENT:TransferPreyFrom(otherPredOrBelly)
    if not IsValid(otherPredOrBelly) then return 0 end
    local oldBelly = otherPredOrBelly
    if not oldBelly.Prey and isfunction(otherPredOrBelly.GetBelly) then
        oldBelly = otherPredOrBelly:GetBelly()
    elseif not oldBelly.Prey then
        oldBelly = otherPredOrBelly.Belly or otherPredOrBelly.VNPC_Belly
    end
    if not IsValid(oldBelly) or not oldBelly.Prey or not istable(oldBelly.Prey) then return 0 end
    if #oldBelly.Prey == 0 then return 0 end

    local transferCount = 0
    local toTransfer = {}
    for i = #oldBelly.Prey, 1, -1 do
        local p_table = oldBelly.Prey[i]
        if p_table and IsValid(p_table.Entity) then
            table.insert(toTransfer, p_table)
            table.remove(oldBelly.Prey, i)
        else
            table.remove(oldBelly.Prey, i)
        end
    end

    for _, p_table in ipairs(toTransfer) do
        local preyEnt = p_table.Entity
        if not IsValid(preyEnt) or preyEnt == self or preyEnt == self.NPC then continue end
        if p_table.WombPrey or p_table.NoDigest or preyEnt.VNPC_IsWombPrey or preyEnt.VNPC_IsUnbornBaby then
            -- Keep unborn babies in the swallowed mother's own belly.
            table.insert(oldBelly.Prey, p_table)
            continue
        end

        -- Check if already in our belly
        local alreadyIn = false
        for _, existing in ipairs(self.Prey) do
            if existing.Entity == preyEnt then
                alreadyIn = true
                break
            end
        end
        if alreadyIn then continue end

        -- Capacity gate during transfers too
        if VNPC_GetBellyCapacity then
            local capacity = VNPC_GetBellyCapacity(self, self.NPC)
            local used = self:GetCollectivePreyValue() or 0
            local incoming = p_table.Value or 10
            if (used + incoming) > capacity then
                table.insert(oldBelly.Prey, p_table)
                continue
            end
        end

        -- Update player notification / parenting
        local is_player = preyEnt:IsPlayer()
        if is_player then
            net.Start("UGotVored")
            net.WriteEntity(self)
            net.WriteEntity(self.NPC)
            net.Send(preyEnt)
        else
            preyEnt:SetPos(self:GetPos())
            preyEnt:SetParent(self)
        end

        local new_index = table.insert(self.Prey, p_table)
        self:OnPreyAdded(new_index, p_table.Value or 10, preyEnt)
        transferCount = transferCount + 1
    end

    if #oldBelly.Prey == 0 then
        oldBelly:ChangeDigestionPhase(0)
        if IsValid(oldBelly.NPC) and oldBelly.NPC.OnDigestionPhaseChanged then
            oldBelly.NPC:OnDigestionPhaseChanged(0, oldBelly.DigestionPhase or 1)
        end
    end

    if transferCount > 0 then
        self:ChangeDigestionPhase(1)
        self:SetNWInt("AliveFactor", self:GetAliveFactor())
    end

    return transferCount
end

function VNPC_TransferPrey(fromEnt, toEnt)
    if not IsValid(fromEnt) or not IsValid(toEnt) then return 0 end

    local fromBelly = fromEnt
    if not fromBelly.Prey and isfunction(fromEnt.GetBelly) then
        fromBelly = fromEnt:GetBelly()
    elseif not fromBelly.Prey then
        fromBelly = fromEnt.Belly or fromEnt.VNPC_Belly
    end

    local toBelly = toEnt
    if not toBelly.Prey and isfunction(toEnt.GetBelly) then
        toBelly = toEnt:GetBelly()
    elseif not toBelly.Prey then
        toBelly = toEnt.Belly or toEnt.VNPC_Belly
    end

    if not IsValid(fromBelly) or not IsValid(toBelly) then return 0 end
    if not fromBelly.Prey or not istable(fromBelly.Prey) or #fromBelly.Prey == 0 then return 0 end
    if not toBelly.Prey or not istable(toBelly.Prey) then return 0 end
    if fromBelly == toBelly then return 0 end

    if toBelly.TransferPreyFrom then
        return toBelly:TransferPreyFrom(fromBelly)
    end
    return 0
end

function ENT:AbsorbPrey(dt)
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

            if VNPC_ScheduleDigestedBoneSpit then
                VNPC_ScheduleDigestedBoneSpit(self.NPC or self:GetOwner() or self:GetParent(), self)
            end

            if #self.Prey == 0 then
                self:ChangeDigestionPhase(0) --belly full of nothing
            end
        end
    end

    return absorbing
end

function ENT:AbsorbSpecificPrey(index)
    local info = self.Prey[index]
    if not info or info.Absorbing then return end
    if info.WombPrey or info.NoDigest or (IsValid(info.Entity) and (info.Entity.VNPC_IsWombPrey or info.Entity.VNPC_IsUnbornBaby)) then
        return
    end
    info.Absorbing = true 
    local prey = info.Entity

    if IsValid(prey) then
        prey.Vored = true
        prey.VNPC_Vored = true
        prey.VNPC_IsDeadAndAbsorbed = true
        prey.m_bRagdollCreated = true
        prey.NoRagdoll = true
        if prey.AddFlags then pcall(prey.AddFlags, prey, FL_DISSOLVING) end
        VNPC_RemoveAttachedEntities(self, prey)
        prey:Remove()
    end
    info.Entity = nil
    self:OnPreyKilled()

    if IsValid(self.NPC) then
        if self.NPC.VNPC_IsGrowingBaby then
            self.NPC.VNPC_GrowthProgress = math.Clamp((self.NPC.VNPC_GrowthProgress or 0.0) + 35.0, 0, 100)
            print("[V-NPCs] Baby Female Growth (Digestion Finished): Baby " .. tostring(self.NPC) .. " digested small prey in her stomach (+35 Growth -> " .. self.NPC.VNPC_GrowthProgress .. "/100)!")
        else
            if VNPC_PredatorMonsterGrowth then
                VNPC_PredatorMonsterGrowth(self.NPC, 1)
            end
        end
        if VNPC_AddPredatorXP then
            VNPC_AddPredatorXP(self.NPC, 100, "Absorbed prey in stomach")
        end
    end

    if VNPC_ScheduleDigestedBoneSpit then
        VNPC_ScheduleDigestedBoneSpit(self.NPC or self:GetOwner() or self:GetParent(), self)
    end

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

function ENT:DigestPrey(dt)
    if #self.Prey == 0 then return 0, 0, 0 end
    local npc = self.NPC
    local livingPrey = 0
    local preyInTotal = 0
    local totalHeal = 0

    local digestionPower = self.DigestionStrength
    if force_digestion:GetBool() then
        digestionPower = global_digestion_multi:GetFloat()
    else
        digestionPower = digestionPower * global_digestion_multi:GetFloat()
    end
    if VNPC_GetPredatorPersonality and IsValid(self.NPC) then
        local _, pred_data = VNPC_GetPredatorPersonality(self.NPC)
        if pred_data and pred_data.digestion_multiplier then
            digestionPower = digestionPower * pred_data.digestion_multiplier
        end
    end
    -- Modular trait system: metabolism speed of the predator scales digestion rate
    if VNPC_GetTraitStat and IsValid(self.NPC) then
        digestionPower = digestionPower * VNPC_GetTraitStat(self.NPC, "metabolism")
    end

    digestionPower = digestionPower * dt * 2 --its x2 for legacy value support, dumb but..uhhhhh

    for i = #self.Prey, 1, -1 do
        local prey_table = self.Prey[i]
        if prey_table.Absorbing then continue end

        preyInTotal = preyInTotal + 1

        local prey = prey_table.Entity
        if prey_table.WombPrey or prey_table.NoDigest or (IsValid(prey) and (prey.VNPC_IsWombPrey or prey.VNPC_IsUnbornBaby)) then
            if IsValid(prey) and prey:Health() > 0 then
                livingPrey = livingPrey + 1
            end
            continue
        end
        if not IsValid(prey) then
            self:AbsorbSpecificPrey(i)
            continue
        end
            
        local oldHealth = prey:Health()
        if oldHealth > 0 then
            livingPrey = livingPrey + 1
                    
            local dmg_i = DamageInfo()
            if npc then
                dmg_i:SetAttacker(npc)
			    dmg_i:SetInflictor(npc)
            end
			dmg_i:SetDamageType(DMG_REMOVENORAGDOLL)
            local effectiveDmg = digestionPower
            if VNPC_GetPreyPersonality and IsValid(prey) then
                local _, prey_data = VNPC_GetPreyPersonality(prey)
                if prey_data and prey_data.digestion_resistance then
                    effectiveDmg = effectiveDmg * prey_data.digestion_resistance
                end
            end
            -- Modular trait system: acid resistance of the prey reduces digestion damage
            if VNPC_GetTraitStat and IsValid(prey) then
                effectiveDmg = effectiveDmg * (1.0 / math.max(VNPC_GetTraitStat(prey, "acid_resistance"), 0.05))
            end
            dmg_i:SetDamage(effectiveDmg)
            prey:TakeDamageInfo(dmg_i)

            totalHeal = totalHeal + effectiveDmg
            if not IsValid(prey) or prey:Health() <= 0 then
                self:AbsorbSpecificPrey(i)
                continue
            end
            if oldHealth == prey:Health() and not prey_table.Alive then
                prey:SetHealth(oldHealth - digestionPower)
            end

            self:OnPreyDigesting(i, digestionPower)
        else
            self:AbsorbSpecificPrey(i)
        end
    end

    return livingPrey, preyInTotal, totalHeal
end

function ENT:Regurgitate(index)
    local info = self.Prey[index]
    if not info then return false end
    if info.Absorbing then return false end

    local prey = info.Entity

    if not prey then return false end
    if not IsValid(prey) then return false end

    prey:SetVelocity(Vector(0,0,0))
    prey:SetParent(nil)
    VNPC_UnhideRegurgitatedPrey(prey)
    VNPC_RegurgitateAttachedEntities(self, prey)

    SetFlags(prey, info.OldFlags)
    prey.VNPC_IsBeingSwallowed = nil
    prey.VNPC_IngestionDepth = nil
    if prey.NextThink then pcall(prey.NextThink, prey, CurTime()) end

    table.remove(self.Prey, index)

    prey.Vored = false
    prey.VNPC_Vored = false
    prey.VNPC_IsDeadAndAbsorbed = nil

    

    self:OnRegurgitate(prey)

    if VNPC_StartRegurgitationAnimation then
        VNPC_StartRegurgitationAnimation(self.NPC or self:GetOwner() or self:GetParent(), prey, self)
    end
    return true
end

function ENT:RegurgitateENT(ent)
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
    local total = 0

    for _, prey in ipairs(self.Prey) do
        local value = prey.Value or 0
        local ent = prey.Entity
        if IsValid(ent) and ent.VNPC_IsBeingSwallowed and ent.VNPC_IngestionDepth then
            value = value * math.Clamp(ent.VNPC_IngestionDepth, 0, 1)
        end
        total = total + value
    end

    return total
end

function ENT:GetAliveFactor() --: number
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
    local keep = {}
    for i,prey in ipairs(self.Prey) do
        local preyEnt = prey.Entity
        if prey.WombPrey or prey.NoDigest or (IsValid(preyEnt) and (preyEnt.VNPC_IsWombPrey or preyEnt.VNPC_IsUnbornBaby)) then
            table.insert(keep, prey)
            continue
        end
        if preyEnt then
            if IsValid(preyEnt) then
                preyEnt:SetParent(nil)
                preyEnt.VNPC_IsDeadAndAbsorbed = true
                preyEnt.Vored = true
                preyEnt.VNPC_Vored = true
                preyEnt.m_bRagdollCreated = true
                preyEnt.NoRagdoll = true
                if preyEnt.AddFlags then pcall(preyEnt.AddFlags, preyEnt, FL_DISSOLVING) end
                VNPC_RemoveAttachedEntities(self, preyEnt)
                preyEnt:Remove()
            end
        end
    end
    self.Prey = keep
    if #self.Prey == 0 then
        self:ChangeDigestionPhase(0)
    end
end

function ENT:SetNPC(npc)
    self.NPC = npc
    self:SetNWEntity("NPCParent", npc)
    if IsValid(npc) then
        self:SetParent(npc)
        self:SetOwner(npc)
    end
end