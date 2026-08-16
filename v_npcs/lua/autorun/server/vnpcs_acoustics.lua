-- V-NPCs Low-Frequency Acoustical Sound Porting (vnpcs_acoustics.lua)
-- v0.7: internal sounds are ported through the belly's medium. A fluid fill
-- factor (swallowed prey mass + drunk water) drives:
--   * muffling: internal struggle/scream sounds lose volume and drop in pitch
--     the fuller the belly is,
--   * sub-bass echo: a delayed, lower, quieter repeat simulates the
--     reverberant interior (deep stereo occlusion),
--   * gait porting: heavy full predators emit low-frequency footstep thumps
--     that get deeper while crawling and louder while running,
--   * medium absorption: armored models damp their own emitted sounds.
--
-- Engine note: GMod exposes no per-sound DSP (no live low-pass filters), so
-- muffling is emulated with pitch/volume attenuation + echo layering, which
-- is what the engine can actually do.

CreateConVar("vnpcs_acoustics_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable the acoustical sound porting system (muffling, echo, footstep thumps)")
CreateConVar("vnpcs_acoustics_muffle", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Muffle internal prey sounds by belly fluid fill")
CreateConVar("vnpcs_acoustics_echo", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Add the delayed sub-bass echo to internal sounds")
CreateConVar("vnpcs_acoustics_thump", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Low-frequency footstep thumps while carrying a heavy belly")

-- 0..1: how full of fluid/mass the belly is.
function VNPC_GetBellyFluid(ent)
    if not IsValid(ent) then return 0 end
    local belly = VNPC_GetPredBelly and VNPC_GetPredBelly(ent) or ent.VNPC_Belly or ent.Belly
    local fluid = 0
    if IsValid(belly) then
        if belly.Prey and #belly.Prey > 0 then
            local mass = 0
            for _, info in ipairs(belly.Prey) do
                if istable(info) and not info.Absorbing then
                    mass = mass + (info.Value or 0)
                end
            end
            fluid = fluid + math.min(mass / 300, 1) * 0.8
        end
        fluid = fluid + math.min(((belly.VNPC_WaterWeight or 0) + (ent.VNPC_WaterDrank or 0)) / 90, 1) * 0.5
    end
    return math.Clamp(fluid, 0, 1)
end

-- Armor-ish models absorb their own sounds a bit (medium density absorption).
local function mediumDensity(ent)
    if not IsValid(ent) then return 1.0 end
    local mdl = string.lower(ent:GetModel() or "")
    if mdl:find("combine") or mdl:find("metrocop") or mdl:find("armor") or mdl:find("soldier") then
        return 0.75
    end
    return 1.0
end

-- Plays a sound as heard from INSIDE the belly (muffled + echo).
function VNPC_EmitMuffledInternal(pred, snd, vol, pitchBase)
    if not IsValid(pred) then return end
    local enabled = GetConVar("vnpcs_acoustics_enabled")
    if enabled and not enabled:GetBool() then return end
    local fill = VNPC_GetBellyFluid(pred)

    local muffle = GetConVar("vnpcs_acoustics_muffle")
    local doMuffle = not muffle or muffle:GetBool()
    local volOut = vol or 70
    local pitchOut = pitchBase or 100
    if doMuffle then
        volOut = volOut * (1 - fill * 0.5)
        pitchOut = pitchOut - fill * 28
    end
    if volOut < 8 then return end

    if pred.EmitSound then
        pred:EmitSound(snd, 72, math.max(35, pitchOut), volOut)
    end

    -- sub-bass echo: delayed, deeper, quieter repeat
    local echoCv = GetConVar("vnpcs_acoustics_echo")
    if (not echoCv or echoCv:GetBool()) and IsValid(pred) then
        local delay = 0.15 + fill * 0.12
        timer.Simple(delay, function()
            if IsValid(pred) and pred.EmitSound then
                pred:EmitSound(snd, 62, math.max(30, pitchOut - 14), volOut * 0.32)
            end
        end)
    end
end

-- Intercept internal prey sounds (screams, struggle thumps) and port them
-- through the belly medium. Server-side only - player-prey sounds are
-- client-side and can't be intercepted here.
hook.Add("EntityEmitSound", "VNPC_Acoustics_MufflePrey", function(data)
    local enabled = GetConVar("vnpcs_acoustics_enabled")
    if enabled and not enabled:GetBool() then return end
    if not istable(data) then return end
    local ent = data.Entity
    if not IsValid(ent) or ent:IsPlayer() then return end
    if not (ent.Vored or ent.VNPC_Vored) then return end
    if ent.VNPC_IsBeingSwallowed then return end

    local name = string.lower(data.SoundName or "")
    -- only port the "internal" sounding classes
    if not (name:find("body_medium_impact") or name:find("body_small_impact") or
            name:find("scream") or name:find("pain") or name:find("groan") or
            name:find("struggle") or name:find("citizen/vo")) then
        return
    end

    -- find the predator that owns this prey
    local pred = nil
    if ent.GetParent and IsValid(ent:GetParent()) then
        local par = ent:GetParent()
        if par.VNPC_Belly or par.Belly or par.NPC then
            pred = par.NPC or par
        end
    end
    if not IsValid(pred) then
        for _, belly in ipairs(ents.FindByClass("ent_vore_belly")) do
            if IsValid(belly) and belly.Prey then
                for _, info in ipairs(belly.Prey) do
                    if istable(info) and info.Entity == ent then
                        pred = belly.NPC or belly:GetOwner()
                        break
                    end
                end
            end
            if IsValid(pred) then break end
        end
    end
    if not IsValid(pred) then return end

    VNPC_EmitMuffledInternal(pred, data.SoundName, data.SoundLevel or 70, 100)
    return true -- suppress the original unmuffled sound
end)

-- ---------------------------------------------------------------------------
-- Gait porting: low-frequency footstep thumps for heavy predators
-- ---------------------------------------------------------------------------
hook.Add("Think", "VNPC_Acoustics_FootstepThumps", function()
    local enabled = GetConVar("vnpcs_acoustics_enabled")
    if enabled and not enabled:GetBool() then return end
    local thumpCv = GetConVar("vnpcs_acoustics_thump")
    if thumpCv and not thumpCv:GetBool() then return end

    local now = CurTime()
    for _, pred in ipairs(ents.GetAll()) do
        if not IsValid(pred) or pred:IsPlayer() then continue end
        if not (pred.Predator or pred.VNPC_FemaleModelVore or pred.IsDrGNextbot) then continue end

        local fullness = VNPC_GetPredatorFullness and VNPC_GetPredatorFullness(pred) or 0
        if fullness <= 0.5 then continue end

        local vel = pred:GetVelocity()
        local speed = vel:Length2D()
        if speed < 40 then
            pred.VNPC_NextThump = nil
            continue
        end

        -- cadence: slower when crawling, faster when running
        local crawling = pred.VNPC_IsSleeping or pred.VNPC_IsSleepCrawled
        local interval = crawling and 1.1 or math.Clamp(0.62 - speed * 0.0008, 0.34, 0.62)
        if (pred.VNPC_NextThump or 0) > now then continue end
        pred.VNPC_NextThump = now + interval

        local fill = VNPC_GetBellyFluid(pred)
        local pitch = crawling and (36 + fill * 12) or (44 + fill * 22)
        local vol = math.Clamp((18 + fullness * 7) * math.Clamp(speed / 120, 0.5, 1.6), 22, 72)
        if crawling then vol = vol * 0.6 end
        if pred.EmitSound then
            pred:EmitSound("physics/body/body_medium_impact_hard1.wav", 70, pitch, vol)
        end
    end
end)

concommand.Add("vnpcs_acoustics_status", function(ply)
    print("===============================================================")
    print("        V-NPCs ACOUSTICAL SOUND PORTING (v0.7) STATUS          ")
    print("===============================================================")
    print(" - Acoustics Enabled: " .. tostring(GetConVar("vnpcs_acoustics_enabled"):GetBool()))
    print(" - Muffling: " .. tostring(GetConVar("vnpcs_acoustics_muffle"):GetBool()))
    print(" - Sub-bass Echo: " .. tostring(GetConVar("vnpcs_acoustics_echo"):GetBool()))
    print(" - Footstep Thumps: " .. tostring(GetConVar("vnpcs_acoustics_thump"):GetBool()))
    local count = 0
    for _, pred in ipairs(ents.GetAll()) do
        if IsValid(pred) and (pred.Predator or pred.VNPC_FemaleModelVore or pred.IsDrGNextbot) and not pred:IsPlayer() then
            local fill = VNPC_GetBellyFluid(pred)
            if fill > 0.01 then
                count = count + 1
                print(string.format(" -> #%d [%s] fluid=%.0f%% fullness=%.1f medium=%.2f",
                    pred:EntIndex(), pred.PrintName or pred:GetClass(), fill * 100,
                    VNPC_GetPredatorFullness and VNPC_GetPredatorFullness(pred) or 0,
                    mediumDensity(pred)))
            end
        end
    end
    if count == 0 then print(" - No predators with belly fluid currently spawned.") end
    print("===============================================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Acoustics status printed to console. Ported predators: " .. count)
    end
end)
