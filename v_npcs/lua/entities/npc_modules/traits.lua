--[[

    MODULAR STATUS & TRAIT SYSTEM

    Gives every V-NPC (and anything else that gets vored, since predators
    can become prey too) a small set of RPG-ish stats that change how
    digestion behaves for that specific entity:

        MetabolismSpeed - multiplies digestion/absorption power (how fast
                           THIS predator breaks prey down)
        AcidResistance   - divides the digestion damage THIS entity takes
                           when it is the one being digested (works for
                           NPCs, players, even other predators in chain-vore)
        MaxCapacity      - hard cap on how many prey can be alive in the
                           belly at once. 0 = unlimited (legacy behaviour)
        StaminaPenalty   - multiplies how much extra the predator slows
                           down per unit of prey weight carried

    Traits are stored per-entity (self.Traits), replicated to clients via
    NWFloats so the status menu / HUD can read them back, and are meant to
    be tweaked at runtime through the "Status Menu" (see
    autorun/client/vnpcs_status_menu.lua) or set once in ENT.VoreSettings.Traits
    on a per-NPC-type basis.

]]

local traits_enabled = CreateConVar("vnpcs_traits_enabled", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED})

ENT.DefaultTraits = ENT.DefaultTraits or {
    MetabolismSpeed = 1,
    AcidResistance  = 1,
    MaxCapacity     = 0,
    StaminaPenalty  = 1,
}

ENT.TraitBounds = ENT.TraitBounds or {
    MetabolismSpeed = {0.1, 6},
    AcidResistance  = {0.1, 6},
    MaxCapacity     = {0, 24},
    StaminaPenalty  = {0, 4},
}

ENT.TraitDescriptions = ENT.TraitDescriptions or {
    MetabolismSpeed = "How quickly this predator digests and absorbs prey.",
    AcidResistance  = "How resistant this entity is to being digested when it ends up as prey.",
    MaxCapacity     = "Max amount of living prey this predator can hold at once. 0 = unlimited.",
    StaminaPenalty  = "How much heavier prey slows this predator's movement speed.",
}

local TRAIT_NW = {
    MetabolismSpeed = "Trait_Metabolism",
    AcidResistance  = "Trait_AcidRes",
    MaxCapacity     = "Trait_MaxCap",
    StaminaPenalty  = "Trait_Stamina",
}
ENT.TraitNWNames = TRAIT_NW

function ENT:InitTraits()
    self.Traits = self.Traits or {}

    local base = (self.VoreSettings and self.VoreSettings.Traits) or {}
    for name, default in pairs(self.DefaultTraits) do
        local value = base[name]
        if value == nil then value = default end

        self.Traits[name] = value
        if SERVER then
            self:SetNWFloat(TRAIT_NW[name], value)
        end
    end
end

--gets a trait's value, respects the global kill-switch convar
function ENT:GetTrait(name)
    local default = self.DefaultTraits and self.DefaultTraits[name] or 1

    if not traits_enabled:GetBool() then
        return default
    end

    if CLIENT and TRAIT_NW[name] then
        return self:GetNWFloat(TRAIT_NW[name], default)
    end

    if not self.Traits then self:InitTraits() end
    local value = self.Traits[name]
    if value == nil then return default end
    return value
end

function ENT:SetTrait(name, value)
    if not self.DefaultTraits or self.DefaultTraits[name] == nil then return false end

    local bounds = self.TraitBounds[name]
    if bounds then
        value = math.Clamp(tonumber(value) or bounds[1], bounds[1], bounds[2])
    end

    if not self.Traits then self:InitTraits() end
    self.Traits[name] = value

    if SERVER and TRAIT_NW[name] then
        self:SetNWFloat(TRAIT_NW[name], value)
    end

    self:OnTraitChanged(name, value)
    return true
end

function ENT:OnTraitChanged(name, value) end --hook for custom npcs

function ENT:GetAllTraits()
    local out = {}
    if not self.DefaultTraits then return out end

    for name, _ in pairs(self.DefaultTraits) do
        out[name] = self:GetTrait(name)
    end
    return out
end

--[[ Helpers usable by anything (belly mechanics, players, props, etc) that
     may or may not actually have the trait system mixed in. ]]

function VNPC_GetTrait(ent, name, fallback)
    if IsValid(ent) and ent.GetTrait then
        local ok, value = pcall(ent.GetTrait, ent, name)
        if ok and value then return value end
    end
    return fallback or 1
end
