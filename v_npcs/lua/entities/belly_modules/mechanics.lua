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
    if table.HasValue(self.Prey, prey) then return false end
    if prey.Vored then return false end
    if self.EatCondition then
        if not self:EatCondition(prey) then
            return false
        end
    end

    prey.Vored = true
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
    prey:SetNoDraw(true)

    if is_npc then
        prey:SetSchedule(SCHED_NPC_FREEZE)
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

    VNPC_SwallowAttachedEntities(self, prey)

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

        -- Check if already in our belly
        local alreadyIn = false
        for _, existing in ipairs(self.Prey) do
            if existing.Entity == preyEnt then
                alreadyIn = true
                break
            end
        end
        if alreadyIn then continue end

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

            if #self.Prey == 0 then
                self:ChangeDigestionPhase(0) --belly full of nothing
            end
        end
    end

    return absorbing
end

function ENT:AbsorbSpecificPrey(index)
    self.Prey[index].Absorbing = true 
    local prey = self.Prey[index].Entity

    if IsValid(prey) then
        --prey:SetParent(nil)
        prey.Vored = false
        VNPC_RemoveAttachedEntities(self, prey)
        prey:Remove()
    end
    self.Prey[index].Entity = nil
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

    digestionPower = digestionPower * dt * 2 --its x2 for legacy value support, dumb but..uhhhhh

    for i = #self.Prey, 1, -1 do
        local prey_table = self.Prey[i]
        if prey_table.Absorbing then continue end

        preyInTotal = preyInTotal + 1

        local prey = prey_table.Entity
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
            dmg_i:SetDamage(effectiveDmg)
            prey:TakeDamageInfo(dmg_i)

            totalHeal = totalHeal + effectiveDmg
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
    prey:SetNoDraw(false)
    VNPC_RegurgitateAttachedEntities(self, prey)

    SetFlags(prey, info.OldFlags)

    table.remove(self.Prey, index)

    prey.Vored = false

    

    self:OnRegurgitate(prey)
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
        local value = prey.Value
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
    for i,prey in ipairs(self.Prey) do
        local preyEnt = prey.Entity
        if preyEnt then
            if IsValid(preyEnt) then
                preyEnt:SetParent(nil)
                preyEnt.Vored = false 

                local dmg_i = DamageInfo()
                dmg_i:SetDamageType(DMG_REMOVENORAGDOLL)
                dmg_i:SetDamage(9999999)

                preyEnt:TakeDamageInfo(dmg_i)
                preyEnt:Remove()
            end
        end
    end
    table.Empty(self.Prey)
end

function ENT:SetNPC(npc)
    self.NPC = npc
    self:SetNWEntity("NPCParent", npc)
    if IsValid(npc) then
        self:SetParent(npc)
        self:SetOwner(npc)
    end
end