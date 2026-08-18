-- V-NPCs gulp sound helpers.
-- Centralizes gulps/g1..g10 so every swallow path (EatEntity, direct AddPrey,
-- ingestion stages, player vore) plays audible gulps on a consistent channel.

VNPC_GULP_SOUND_PATHS = {
    "gulps/g1.wav",
    "gulps/g2.wav",
    "gulps/g3.wav",
    "gulps/g4.wav",
    "gulps/g5.wav",
    "gulps/g6.wav",
    "gulps/g7.wav",
    "gulps/g8.wav",
    "gulps/g9.wav",
    "gulps/g10.wav",
}

CreateConVar("vnpcs_gulp_sounds_enabled", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Play gulps/g*.wav when predators swallow prey")
CreateConVar("vnpcs_gulp_volume", "100", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Default EmitSound level for gulp clips (0-150)")

local function pickGulpPath()
    return VNPC_GULP_SOUND_PATHS[math.random(1, #VNPC_GULP_SOUND_PATHS)]
end

--- Play a random gulp on ent. Debounced so EatEntity + OnPreySwallowed + stages
--- don't stack into silence/cutoff. Uses CHAN_VOICE so body foley doesn't kill it.
function VNPC_PlayGulpSound(ent, volume, pitch, force)
    if not IsValid(ent) then return false end
    local enabled = GetConVar("vnpcs_gulp_sounds_enabled")
    if enabled and not enabled:GetBool() then return false end
    if not ent.EmitSound then return false end

    local now = CurTime()
    if not force and (ent.VNPC_NextGulpSound or 0) > now then
        return false
    end

    local volCv = GetConVar("vnpcs_gulp_volume")
    local vol = tonumber(volume) or (volCv and volCv:GetFloat()) or 100
    vol = math.Clamp(vol, 40, 150)
    local pit = tonumber(pitch) or math.random(95, 105)
    pit = math.Clamp(pit, 70, 140)

    local path = pickGulpPath()
    -- Prefer predator's own VoreSounds.swallow list when present.
    local list = ent.VoreSounds and ent.VoreSounds["swallow"]
    if istable(list) and #list > 0 then
        path = list[math.random(1, #list)] or path
    end

    ent.VNPC_NextGulpSound = now + 0.28
    ent:EmitSound(path, vol, pit, 1.0, CHAN_VOICE)
    return true
end

function VNPC_PrecacheGulpSounds()
    for _, path in ipairs(VNPC_GULP_SOUND_PATHS) do
        if util.PrecacheSound then
            util.PrecacheSound(path)
        end
    end
end

if SERVER then
    hook.Add("Initialize", "VNPC_PrecacheGulpSounds", function()
        VNPC_PrecacheGulpSounds()
    end)

    -- Every successful AddPrey fires this, including assassins / smart AI / camps
    -- that never go through EatEntity. Debounce keeps EatEntity double-calls clean.
    hook.Add("VNPC_OnPreySwallowed", "VNPC_PlayGulpOnSwallow", function(pred, prey, belly)
        local emitter = IsValid(pred) and pred or (IsValid(belly) and belly or nil)
        if not IsValid(emitter) then return end
        VNPC_PlayGulpSound(emitter, 100, math.random(95, 105))
    end)
end

if CLIENT then
    hook.Add("InitPostEntity", "VNPC_PrecacheGulpSounds_Client", function()
        VNPC_PrecacheGulpSounds()
    end)
end

concommand.Add("vnpcs_test_gulp", function(ply)
    local target = IsValid(ply) and ply or nil
    if IsValid(ply) then
        local tr = ply:GetEyeTrace()
        if IsValid(tr.Entity) then target = tr.Entity end
    end
    if not IsValid(target) then
        print("[V-NPCs] vnpcs_test_gulp: no target")
        return
    end
    local ok = VNPC_PlayGulpSound(target, 100, 100, true)
    local msg = ok
        and ("[V-NPCs] Played gulp on " .. tostring(target))
        or ("[V-NPCs] Gulp failed / disabled on " .. tostring(target))
    if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
end)
