--[[
    Prey struggling and escape.

    `Regurgitate` existed since the first version of this addon but nothing ever
    called it, so once swallowed a player just watched a camera until they died.
    This gives prey agency: mashing movement keys builds an escape meter, and
    filling it spits you back out.

    Escape is resisted by the predator's digestion strength, by how full the
    belly is, and by how digested the prey already is -- so struggling is most
    effective right after being swallowed and becomes hopeless if you leave it
    too long.

    All authority lives on the server. The client only ever renders the meter
    that the server networks to it.
]]

local escape_enabled = CreateConVar("vnpcs_prey_escape", "1",
    {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED},
    "Let swallowed players struggle free by mashing movement keys.")

local escape_multi = CreateConVar("vnpcs_prey_escape_multi", "1",
    {FCVAR_ARCHIVE, FCVAR_REPLICATED},
    "Multiplier on how much progress each struggle input makes.")

local escape_npcs = CreateConVar("vnpcs_prey_escape_npcs", "0",
    {FCVAR_ARCHIVE, FCVAR_REPLICATED},
    "Let swallowed NPCs struggle free on their own too.")

local escape_cooldown = CreateConVar("vnpcs_prey_escape_cooldown", "8",
    {FCVAR_ARCHIVE, FCVAR_REPLICATED},
    "Seconds before a predator may re-swallow prey that just escaped.")

--[[
    Tuning. These were picked by simulating the escape curve against the
    digestion window rather than by feel, so that there is a real "only just
    made it" band instead of a pass/fail cliff.

    Against a default predator (DigestionStrength 2, which digests a 100 hp
    player in 25s) a steady mash rate of roughly:

        3/sec  -> digested, never escapes
        4/sec  -> escapes at 23s, right on the buzzer
        6/sec  -> escapes at 6.6s
        12/sec -> escapes at 2.6s

    Predators with DigestionStrength 3 or more are effectively inescapable at a
    human mash rate, which is intentional -- their digest window is shorter too.
    Server owners can open that up with vnpcs_prey_escape_multi.
]]

-- progress added by one key press, before any resistance is applied
ENT.StruggleGain = 0.05
-- progress lost per second while not struggling, scaled by sqrt(DigestionStrength)
ENT.StruggleDecay = 0.03
--[[
    Floor on how much a mostly digested prey's struggling still counts. Without a
    reasonably high floor the health falloff dominates and turns the whole
    mechanic into a cliff: below some mash rate the meter never leaves zero and
    the player gets no feedback at all.
]]
ENT.StruggleMinHealthFactor = 0.35

--[[     HOOKS      ]]

--prey pushed the meter up. progress is 0..1
function ENT:OnPreyStruggled(ent, progress) end
--prey filled the meter and got spat out
function ENT:OnPreyEscaped(ent) end

--[[               ]]

function ENT:IsEscapeEnabled()
    return escape_enabled:GetBool()
end

function ENT:GetPreyIndex(ent)
    self:InitBellyState()

    for index, entry in ipairs(self.Prey) do
        if entry.Entity == ent then return index, entry end
    end

    return nil
end

--[[
    How hard this belly is to escape from right now.

    Scales with the predator's digestion strength and with how many other things
    are in there with you, so a fed-up predator is genuinely harder to get out of.
]]
function ENT:GetEscapeResistance()
    local others = math.max(#self.Prey - 1, 0)
    local strength = math.max(self.DigestionStrength or 1, 0.1)

    return 1 + (strength - 1) * 0.35 + others * 0.25
end

--[[
    Adds struggle progress for `ent`. Returns the new progress, and whether that
    was enough to escape.
]]
function ENT:AddStruggle(ent, amount)
    if not SERVER then return 0, false end
    if not self:IsEscapeEnabled() then return 0, false end
    if not IsValid(ent) then return 0, false end

    local index, entry = self:GetPreyIndex(ent)
    if not entry then return 0, false end
    if entry.Absorbing then return 0, false end
    if not entry.Alive then return 0, false end

    -- a nearly digested prey has very little fight left
    local maxHealth = math.max(entry.MaxHealth or ent:GetMaxHealth() or 1, 1)
    local healthFactor = math.Clamp(ent:Health() / maxHealth, self.StruggleMinHealthFactor, 1)

    local gain = (amount or self.StruggleGain)
        * escape_multi:GetFloat()
        * healthFactor
        / self:GetEscapeResistance()

    entry.Escape = math.Clamp((entry.Escape or 0) + gain, 0, 1)
    entry.LastStruggle = CurTime()

    self:NetworkEscapeProgress(entry)
    self:OnPreyStruggled(ent, entry.Escape)

    if entry.Escape >= 1 then
        return 1, self:PreyEscape(index)
    end

    return entry.Escape, false
end

function ENT:NetworkEscapeProgress(entry)
    local ent = entry.Entity
    if not IsValid(ent) then return end

    -- only players have a HUD to show it on
    if ent:IsPlayer() then
        ent:SetNW2Float("VoreEscapeProgress", entry.Escape or 0)
    end
end

--[[
    Drains the meter and feeds the loudest struggler to the belly's animation so
    the flex springs react to real input instead of only to a random timer.
    Called from the belly think.
]]
function ENT:UpdateStruggle(dt)
    self:InitBellyState()

    if #self.Prey == 0 then
        if self:GetNWFloat("StruggleIntensity", 0) ~= 0 then
            self:SetNWFloat("StruggleIntensity", 0)
        end
        return
    end

    local enabled = self:IsEscapeEnabled()
    -- sqrt so a very strong predator does not make the meter unmovable
    local decay = self.StruggleDecay * math.sqrt(math.max(self.DigestionStrength or 1, 0.1)) * dt
    local loudest = 0

    for index = #self.Prey, 1, -1 do
        local entry = self.Prey[index]
        if not entry then continue end

        if enabled and escape_npcs:GetBool() and entry.Alive and not entry.Absorbing then
            local ent = entry.Entity
            if IsValid(ent) and not ent:IsPlayer() then
                -- NPCs cannot press keys, so they thrash on their own
                local _, escaped = self:AddStruggle(ent, self.StruggleGain * math.Rand(0.4, 1.2) * dt * 2)
                if escaped then continue end -- entry is gone, indices below are untouched
            end
        end

        local progress = entry.Escape or 0

        if progress > 0 then
            local drained = math.max(progress - decay, 0)
            if drained ~= progress then
                entry.Escape = drained
                self:NetworkEscapeProgress(entry)
            end

            if drained > loudest then loudest = drained end
        end
    end

    -- drives spring speed / flex range in belly_modules/animations.lua
    if math.abs(self:GetNWFloat("StruggleIntensity", 0) - loudest) > 0.01 then
        self:SetNWFloat("StruggleIntensity", loudest)
    end
end

--[[
    Spits `index` back out under its own power: regurgitate, then place and shove
    the prey clear of the predator and put a cooldown on being re-eaten so you
    are not simply swallowed again on the next melee swing.
]]
function ENT:PreyEscape(index)
    if not SERVER then return false end

    local entry = self.Prey[index]
    if not entry then return false end

    local prey = entry.Entity
    if not IsValid(prey) then return false end

    local npc = self.NPC
    local source = IsValid(npc) and npc or self
    local dir = source:GetForward()
    local origin = source:WorldSpaceCenter()

    if not self:Regurgitate(index) then return false end

    --[[
        Players are never parented while swallowed, so without this they would
        pop back to wherever they were standing when they got eaten.
    ]]
    -- built explicitly: {self, npc, prey} with a nil npc leaves a hole in the
    -- array part and the trace filter would silently drop entries after it
    local filter = {self, prey}
    if IsValid(npc) then filter[#filter + 1] = npc end

    local tr = util.TraceHull({
        start = origin,
        endpos = origin + dir * 42,
        mins = prey:OBBMins(),
        maxs = prey:OBBMaxs(),
        filter = filter
    })

    prey:SetPos(tr.HitPos)
    prey:SetVelocity(dir * 200 + Vector(0, 0, 170))

    local cooldown = math.max(escape_cooldown:GetFloat(), 0)
    prey.VoreEscapeCooldown = CurTime() + cooldown

    if IsValid(npc) then
        -- stop it immediately re-acquiring the thing that just crawled out
        npc:SetEntityRelationship(prey, D_NU, cooldown)

        if npc.Burp then
            npc:Burp(true)
        end
    end

    -- a wet churn, not PlayFinalDigestSound -- nothing died here
    self:PlayRandomGurgle()

    if prey:IsPlayer() then
        prey:SetNW2Float("VoreEscapeProgress", 0)
        net.Start("VoreEscaped")
        net.Send(prey)
    end

    self:OnPreyEscaped(prey)

    return true
end
