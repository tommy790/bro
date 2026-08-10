-- V-NPCs Advanced Multi-Factor Prey Valuation System (sh_vnpc_prey_value.lua)
-- Calculates dynamic nutritional and volumetric value for prey based on volume, bounding diagonal, health, physics mass, classification, and accumulated stomach prey.

CreateConVar("vnpcs_advanced_prey_value", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable advanced multi-factor prey valuation (volume, mass, health, and accumulated prey)")
CreateConVar("vnpcs_prey_value_scale", "1.0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Global scaling multiplier for advanced prey values")

function VNPC_CalculatePreyValue(ent, override_scale)
    if not IsValid(ent) then return 10, "Invalid" end

    local enabled = GetConVar("vnpcs_advanced_prey_value")
    local scale = tonumber(override_scale) or (ent.GetModelScale and ent:GetModelScale()) or 1
    if not isnumber(scale) then scale = 1 end

    local mins, maxs = Vector(-16, -16, 0), Vector(16, 16, 72)
    if ent.GetModelBounds then
        local r1, r2 = ent:GetModelBounds()
        if isvector(r1) and isvector(r2) then
            mins, maxs = r1, r2
        end
    end

    local dim = (maxs - mins) * scale
    if not isvector(dim) then
        dim = Vector(32, 32, 72) * scale
    end

    if enabled and not enabled:GetBool() then
        local l = dim:Length()
        return l, "Legacy Bounding Diagonal"
    end

    local diag = dim:Length()

    -- 1. Bounding volume contribution (normalized against standard human volume ~ 32x32x72 = 73728)
    local vol = math.max(1, (dim.x or 32) * (dim.y or 32) * (dim.z or 72))
    local vol_factor = math.sqrt(vol / 73728.0) * 35.0

    -- 2. Diagonal size contribution
    local diag_factor = diag * 0.65

    -- 3. Health & Toughness contribution
    local hp_factor = 0
    if ent.GetMaxHealth and ent:GetMaxHealth() > 0 then
        hp_factor = math.Clamp(ent:GetMaxHealth() * 0.15, 0, 150)
    end

    -- 4. Physics mass contribution
    local mass_factor = 0
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        mass_factor = math.Clamp(phys:GetMass() * 0.35, 0, 100)
    end

    -- 5. Classification multiplier
    local class_mult = 1.0
    if ent:IsPlayer() then
        class_mult = 1.35
    elseif ent.IsDrGNextbot or (ent.GetMaxHealth and ent:GetMaxHealth() >= 250) then
        class_mult = 1.25
    elseif ent:IsNPC() then
        class_mult = 1.05
    end

    local base_val = (vol_factor + diag_factor + hp_factor + mass_factor) * class_mult

    local cv_scale = GetConVar("vnpcs_prey_value_scale")
    local global_mult = cv_scale and cv_scale:GetFloat() or 1.0

    local total = math.Clamp(base_val * global_mult, 15, 2500)
    local details = string.format("Vol=%.1f, Diag=%.1f, HP=%.1f, Mass=%.1f, Mult=%.2f", vol_factor, diag_factor, hp_factor, mass_factor, class_mult)
    return total, details
end

concommand.Add("vnpcs_prey_value_test", function(ply)
    print("===============================================================")
    print("         V-NPCs ADVANCED PREY VALUE SYSTEM ANALYSIS            ")
    print("===============================================================")
    print(" - Advanced Valuation Enabled: " .. tostring(GetConVar("vnpcs_advanced_prey_value"):GetBool()))
    print(" - Global Value Multiplier: " .. tostring(GetConVar("vnpcs_prey_value_scale"):GetFloat()))
    local count = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and (ent:IsNPC() or ent:IsPlayer() or ent.IsDrGNextbot or ent.VNPC_FemaleModelVore) then
            count = count + 1
            local val, details = VNPC_CalculatePreyValue(ent)
            print(string.format(" - Entity #%d [%s]: Total Value = %.1f (%s)", ent:EntIndex(), ent.PrintName or ent:GetClass(), val, details))
        end
    end
    if count == 0 then
        print(" - Active Characters/NPCs: NONE currently spawned")
    end
    print("===============================================================")
end)
