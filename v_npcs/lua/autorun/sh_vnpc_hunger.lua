-- V-NPCs Universal Hunger System (sh_vnpc_hunger.lua)
-- Gives every predator NPC dynamic hunger that increases swallowing appetite without ever killing or damaging them.

CreateConVar("vnpcs_hunger_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable dynamic hunger system for V-NPC predators (does not damage health)")
CreateConVar("vnpcs_hunger_rate", "1.5", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "How fast hunger increases per second when belly is empty (0 to 100 scale)")
CreateConVar("vnpcs_hunger_max_mult", "3.0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Maximum multiplier applied to sight range and swallowing desire when starving")

function VNPC_GetHunger(ent)
    if not IsValid(ent) then return 0 end
    if not ent.VNPC_Hunger then
        ent.VNPC_Hunger = 50 -- Start moderately hungry
    end
    return ent.VNPC_Hunger
end

function VNPC_SetHunger(ent, val)
    if not IsValid(ent) then return end
    ent.VNPC_Hunger = math.Clamp(val or 50, 0, 100)
    if SERVER and ent.SetNWFloat then
        ent:SetNWFloat("VNPC_Hunger", ent.VNPC_Hunger)
    end
end

function VNPC_FeedHunger(ent, amount)
    if not IsValid(ent) then return end
    local current = VNPC_GetHunger(ent)
    VNPC_SetHunger(ent, current - (amount or 40))
end

function VNPC_GetHungerMultiplier(ent)
    if not IsValid(ent) then return 1.0 end
    local enabled = GetConVar("vnpcs_hunger_enabled")
    if enabled and not enabled:GetBool() then return 1.0 end

    local hunger = VNPC_GetHunger(ent)
    local max_mult = GetConVar("vnpcs_hunger_max_mult")
    local max_val = max_mult and max_mult:GetFloat() or 3.0
    return 1.0 + (hunger / 100.0) * (max_val - 1.0)
end

if SERVER then
    local nextHungerUpdate = 0
    hook.Add("Think", "VNPCS_Hunger_UpdateLoop", function()
        local now = CurTime()
        if now < nextHungerUpdate then return end
        nextHungerUpdate = now + 1.0

        local enabled = GetConVar("vnpcs_hunger_enabled")
        if enabled and not enabled:GetBool() then return end

        local rate = GetConVar("vnpcs_hunger_rate")
        local incRate = rate and rate:GetFloat() or 1.5

        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator or ent.EatEntity) then
                if ent:IsPlayer() then continue end
                local belly = ent.VNPC_Belly or ent.Belly or ent.belly
                local hasPrey = IsValid(belly) and (belly.DigestionPhase ~= 0 or (belly.Prey and #belly.Prey > 0))
                local cur = VNPC_GetHunger(ent)

                if hasPrey then
                    -- Smoothly satisfy hunger while digesting prey
                    VNPC_SetHunger(ent, cur - 3.0)
                else
                    -- Hunger grows over time when empty, increasing swallowing desire
                    VNPC_SetHunger(ent, cur + incRate)
                end

                -- Dynamically boost sight range and hunt willingness based on hunger
                if ent.SightRange and not ent.VNPC_BaseSightRange then
                    ent.VNPC_BaseSightRange = ent.SightRange
                end
                if ent.VNPC_BaseSightRange then
                    ent.SightRange = ent.VNPC_BaseSightRange * VNPC_GetHungerMultiplier(ent)
                end
            end
        end
    end)
end

concommand.Add("vnpcs_hunger_status", function(ply)
    print("===============================================================")
    print("           V-NPCs DYNAMIC HUNGER SYSTEM STATUS                 ")
    print("===============================================================")
    print(" - Hunger System Enabled: " .. tostring(GetConVar("vnpcs_hunger_enabled"):GetBool()))
    print(" - Hunger Growth Rate: " .. tostring(GetConVar("vnpcs_hunger_rate"):GetFloat()) .. " / sec")
    local count = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and (ent.IsDrGNextbot or ent.VNPC_FemaleModelVore or ent.Predator) and not ent:IsPlayer() then
            count = count + 1
            local hunger = VNPC_GetHunger(ent)
            local mult = VNPC_GetHungerMultiplier(ent)
            print(string.format(" - Predator #%d [%s]: Hunger = %.1f%% (Sight/Hunt Multiplier = %.2fx)", ent:EntIndex(), ent.PrintName or ent:GetClass(), hunger, mult))
        end
    end
    if count == 0 then
        print(" - Active Predators: NONE currently spawned")
    end
    print("===============================================================")
end)
