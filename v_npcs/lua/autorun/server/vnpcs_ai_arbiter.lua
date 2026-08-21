-- V-NPCs AI Arbiter
-- Many Think loops were re-issuing SetSchedule / SetEnemy every 0.3–0.6s.
-- HL2 NPCs restart their path each time, so they walk a few steps and stop.
-- This module debounces movement commands and gives one owner of intent.

if not SERVER then return end

CreateConVar("vnpcs_ai_arbiter_enabled", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Debounce NPC schedules so AI systems stop thrashing walk/stop")
CreateConVar("vnpcs_ai_schedule_min_hold", "1.25", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Minimum seconds an AI schedule is held before another system can replace it (unless higher priority)")
CreateConVar("vnpcs_ai_chase_repath", "2.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Minimum seconds between chase repaths toward the same enemy")
CreateConVar("vnpcs_ai_debug_arbiter", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Print AI arbiter schedule rejections/overrides")

-- Higher number wins. Combat/swallow must beat camp idle / welfare / scent.
VNPC_AI_PRIORITY = {
    critical   = 100, -- freeze, death, regurgitation, ingestion lock
    combat     = 80,  -- chase enemy, rush, ambush
    swallow    = 75,  -- closing to eat
    flee       = 70,  -- run from predator
    hunt       = 60,  -- investigate / stalk
    camp       = 40,  -- camp roles, build, forage return
    welfare    = 30,  -- drink, social, clean
    idle       = 10,  -- stand around
    background = 1,   -- scent curiosity, etc.
}

local function arbiterOn()
    local cv = GetConVar("vnpcs_ai_arbiter_enabled")
    return not cv or cv:GetBool()
end

local function holdTime()
    local cv = GetConVar("vnpcs_ai_schedule_min_hold")
    return cv and cv:GetFloat() or 1.25
end

local function chaseRepath()
    local cv = GetConVar("vnpcs_ai_chase_repath")
    return cv and cv:GetFloat() or 2.0
end

local function dbg(msg)
    local cv = GetConVar("vnpcs_ai_debug_arbiter")
    if cv and cv:GetBool() then
        print("[VNPC-AI] " .. tostring(msg))
    end
end

local function normalizePriority(p)
    if isnumber(p) then return p end
    if isstring(p) and VNPC_AI_PRIORITY[p] then return VNPC_AI_PRIORITY[p] end
    return VNPC_AI_PRIORITY.idle
end

function VNPC_AI_IsLocked(ent)
    if not IsValid(ent) then return true end
    if ent.Vored or ent.VNPC_Vored then return true end
    if ent.Swallowing or ent.VNPC_IsBeingSwallowed then return true end
    if ent.VNPC_IsHumanOralSwallow or (ent.GetNWBool and ent:GetNWBool("VNPC_IsHumanOralSwallow")) then return true end
    if ent.VNPC_IsMountingHeavyPrey or (ent.GetNWBool and ent:GetNWBool("VNPC_IsMountingHeavyPrey")) then return true end
    if ent.VNPC_IsMatingBonePose or (ent.GetNWBool and ent:GetNWBool("VNPC_IsMatingBonePose")) then return true end
    if (ent.VNPC_InChildbirthPose or 0) > CurTime() then return true end
    if ent.VNPC_IsSleeping and not ent.VNPC_IsSleepCrawled then return true end
    if ent.VNPC_Surrendered then return true end
    return false
end

function VNPC_AI_CanTakeControl(ent, priority, force)
    if not IsValid(ent) then return false end
    if force then return true end
    if not arbiterOn() then return true end
    if VNPC_AI_IsLocked(ent) then return false end

    local p = normalizePriority(priority)
    local now = CurTime()
    local curP = ent.VNPC_AIPriority or 0
    local untilT = ent.VNPC_AIHoldUntil or 0

    if p > curP then return true end
    if p == curP and now >= untilT then return true end
    if p < curP and now >= untilT then
        return true
    end
    return false
end

function VNPC_AI_Claim(ent, priority, owner, hold)
    if not IsValid(ent) then return false end
    local p = normalizePriority(priority)
    hold = tonumber(hold) or holdTime()
    ent.VNPC_AIPriority = p
    ent.VNPC_AIOwner = owner or "unknown"
    ent.VNPC_AIHoldUntil = CurTime() + math.max(0.2, hold)
    ent.VNPC_AILastClaim = CurTime()
    return true
end

function VNPC_AI_Release(ent, owner)
    if not IsValid(ent) then return end
    if owner and ent.VNPC_AIOwner and ent.VNPC_AIOwner ~= owner then return end
    ent.VNPC_AIPriority = 0
    ent.VNPC_AIOwner = nil
    ent.VNPC_AIHoldUntil = 0
end

function VNPC_AI_SetSchedule(ent, schedule, priority, owner, opts)
    if not IsValid(ent) or schedule == nil then return false end
    if not ent.SetSchedule then return false end
    opts = opts or {}
    local force = opts.force == true
    local p = normalizePriority(priority or "idle")

    if VNPC_AI_IsLocked(ent) and not force then
        dbg(string.format("#%s locked, reject %s", ent:EntIndex(), tostring(owner)))
        return false
    end
    if not VNPC_AI_CanTakeControl(ent, p, force) then
        dbg(string.format("#%s hold by %s (p=%s), reject %s (p=%s)",
            ent:EntIndex(), tostring(ent.VNPC_AIOwner), tostring(ent.VNPC_AIPriority),
            tostring(owner), tostring(p)))
        return false
    end

    local now = CurTime()
    local sameSched = (ent.VNPC_AILastSchedule == schedule)
    local sameEnemy = true
    if opts.enemy ~= nil then
        sameEnemy = (ent.VNPC_AILastEnemy == opts.enemy)
    end
    local samePos = true
    if opts.pos and ent.VNPC_AILastPos then
        samePos = ent.VNPC_AILastPos:DistToSqr(opts.pos) < (48 * 48)
    end

    local minGap = opts.minGap
    if not minGap then
        if schedule == SCHED_CHASE_ENEMY or schedule == SCHED_FORCED_GO_RUN or schedule == SCHED_FORCED_GO then
            minGap = chaseRepath()
        else
            minGap = holdTime()
        end
    end

    if sameSched and sameEnemy and samePos and not force then
        if (ent.VNPC_AILastScheduleTime or 0) + minGap > now then
            VNPC_AI_Claim(ent, p, owner, opts.hold or minGap)
            return true
        end
    end

    if opts.enemy ~= nil and ent.SetEnemy then
        pcall(ent.SetEnemy, ent, opts.enemy)
    end
    if opts.pos and ent.SetLastPosition then
        pcall(ent.SetLastPosition, ent, opts.pos)
    end
    if opts.target and ent.SetTarget then
        pcall(ent.SetTarget, ent, opts.target)
    end

    local ok = pcall(ent.SetSchedule, ent, schedule)
    if not ok then return false end

    ent.VNPC_AILastSchedule = schedule
    ent.VNPC_AILastScheduleTime = now
    ent.VNPC_AILastEnemy = opts.enemy
    ent.VNPC_AILastPos = opts.pos and Vector(opts.pos) or ent.VNPC_AILastPos
    VNPC_AI_Claim(ent, p, owner, opts.hold or minGap)
    return true
end

function VNPC_AI_Chase(ent, enemy, priority, owner, opts)
    if not IsValid(ent) or not IsValid(enemy) then return false end
    opts = opts or {}
    opts.enemy = enemy
    return VNPC_AI_SetSchedule(ent, opts.schedule or SCHED_CHASE_ENEMY, priority or "combat", owner or "chase", opts)
end

function VNPC_AI_MoveTo(ent, pos, run, priority, owner, opts)
    if not IsValid(ent) or not pos then return false end
    opts = opts or {}
    opts.pos = pos
    local sched = run and SCHED_FORCED_GO_RUN or SCHED_FORCED_GO
    return VNPC_AI_SetSchedule(ent, sched, priority or "camp", owner or "move", opts)
end

function VNPC_AI_Idle(ent, priority, owner, opts)
    if not IsValid(ent) then return false end
    opts = opts or {}
    return VNPC_AI_SetSchedule(ent, SCHED_IDLE_STAND, priority or "idle", owner or "idle", opts)
end

function VNPC_AI_StopHard(ent, priority, owner)
    if not IsValid(ent) then return false end
    if not VNPC_AI_CanTakeControl(ent, priority or "critical", false) and (priority ~= "critical") then
        return false
    end
    if ent.ClearSchedule then pcall(ent.ClearSchedule, ent) end
    if ent.SetSchedule then pcall(ent.SetSchedule, ent, SCHED_IDLE_STAND) end
    if ent.StopMoving then pcall(ent.StopMoving, ent) end
    -- Do NOT zero velocity every tick — that causes the stutter. Once is enough.
    local now = CurTime()
    if (ent.VNPC_AILastHardStop or 0) + 1.5 < now then
        if ent.SetVelocity then pcall(ent.SetVelocity, ent, Vector(0, 0, 0)) end
        ent.VNPC_AILastHardStop = now
    end
    VNPC_AI_Claim(ent, priority or "critical", owner or "hardstop", 2.0)
    ent.VNPC_AILastSchedule = SCHED_IDLE_STAND
    ent.VNPC_AILastScheduleTime = now
    return true
end

concommand.Add("vnpcs_ai_arbiter_status", function(ply)
    print("===============================================================")
    print("              V-NPCs AI ARBITER STATUS                         ")
    print("===============================================================")
    print(" - Enabled: " .. tostring(arbiterOn()))
    print(" - Min hold: " .. tostring(holdTime()) .. "s | Chase repath: " .. tostring(chaseRepath()) .. "s")
    local n = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent.VNPC_AIOwner then
            n = n + 1
            local left = math.max(0, (ent.VNPC_AIHoldUntil or 0) - CurTime())
            print(string.format(" -> #%d [%s] owner=%s prio=%s hold=%.2fs sched=%s",
                ent:EntIndex(), ent.PrintName or ent:GetClass(),
                tostring(ent.VNPC_AIOwner), tostring(ent.VNPC_AIPriority),
                left, tostring(ent.VNPC_AILastSchedule)))
        end
    end
    if n == 0 then print(" - No entities currently claimed.") end
    print("===============================================================")
    if IsValid(ply) then ply:ChatPrint("[V-NPCs] AI arbiter status printed (" .. n .. " claimed).") end
end)

print("[V-NPCs] AI Arbiter loaded (schedule debounce / priority).")
