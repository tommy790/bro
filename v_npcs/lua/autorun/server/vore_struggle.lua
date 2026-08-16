--[[
    Turns a swallowed player's key presses into struggle progress.

    GM:KeyPress fires once per press rather than continuously while held, so this
    rewards mashing and cannot be cheesed by taping a key down. Input is read
    server-side from the player's own command, so there is no net message for a
    client to forge -- the client never tells the server how hard it struggled.
]]

util.AddNetworkString("VoreEscaped")

local STRUGGLE_KEYS = {
    [IN_FORWARD] = true,
    [IN_BACK] = true,
    [IN_MOVELEFT] = true,
    [IN_MOVERIGHT] = true,
    [IN_JUMP] = true,
    [IN_DUCK] = true,
    [IN_ATTACK] = true,
    [IN_ATTACK2] = true
}

-- a floor on the time between two presses that both count, so bind spam and
-- mousewheel-bound +attack cannot outrun an honest player by orders of magnitude
local MIN_INPUT_INTERVAL = 0.06

hook.Add("KeyPress", "vnpcs_prey_struggle", function(ply, key)
    if not IsValid(ply) then return end
    if not ply.Vored then return end
    if not STRUGGLE_KEYS[key] then return end

    local belly = ply.VorePredatorBelly
    if not IsValid(belly) then return end
    if not belly.AddStruggle then return end

    local now = CurTime()
    if ply.VoreNextStruggle and now < ply.VoreNextStruggle then return end
    ply.VoreNextStruggle = now + MIN_INPUT_INTERVAL

    belly:AddStruggle(ply)
end)

-- clear the grace period so a fresh spawn is immediately edible again
hook.Add("PlayerSpawn", "vnpcs_prey_struggle_reset", function(ply)
    ply.VoreEscapeCooldown = nil
    ply.VoreNextStruggle = nil
    ply.VorePredatorBelly = nil
    ply:SetNW2Float("VoreEscapeProgress", 0)
end)
