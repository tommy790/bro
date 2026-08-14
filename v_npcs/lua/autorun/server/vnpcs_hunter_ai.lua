-- V-NPCs Hunter AI: Ambush, Noise & Flashlight Tracking, Pack Cornering, Hazards (vnpcs_hunter_ai.lua)
-- Upgrades predator nextbots (DrGBase) and female-model NPCs with tactical behavior:
--   * Noise tracking: footsteps (players + NPCs) create world noise events; predators
--     with free bellies investigate loud noises and track noisy prey by sound.
--   * Flashlight tracking: a player's flashlight beam sweeping over a predator
--     exposes them - the predator pinpoints and tracks that player.
--   * Ambush & stalking: predators flank, keep out of the target's view cone,
--     hide behind cover, then burst out when the target's back is turned.
--   * Pack cornering: pack members take flank slots around a target (leader frontal,
--     wings at +/-120 degrees) and close the net.
--   * Map hazards: predators kick explosive barrels at targets, and herd targets
--     toward water so they have to flee into it.
--   * Navmesh-aware placement: all tactical positions snap to the navmesh when one
--     is loaded, with trace-validated fallbacks when it is not.

CreateConVar("vnpcs_hunter_ai_enabled", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable tactical hunter AI (ambush, noise/flashlight tracking, cornering, hazards)")
CreateConVar("vnpcs_noise_tracking", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Predators investigate footsteps and other noises")
CreateConVar("vnpcs_noise_base_range", "550", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Hearing range at full noise loudness")
CreateConVar("vnpcs_flashlight_tracking", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Predators detect and track players whose flashlight beam hits them")
CreateConVar("vnpcs_flashlight_range", "1400", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Max range a flashlight beam can expose a predator")
CreateConVar("vnpcs_ambush_ai", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Predators stalk and ambush targets from cover")
CreateConVar("vnpcs_pack_cornering", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Pack members flank targets from multiple sides to corner them")
CreateConVar("vnpcs_hazard_use", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Predators kick explosive barrels at targets and herd prey into water")
CreateConVar("vnpcs_hunter_debug", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Draw hunter AI state, ambush points and flank slots")

-- ---------------------------------------------------------------------------
-- World noise model
-- ---------------------------------------------------------------------------

VNPC_NoiseEvents = VNPC_NoiseEvents or {}

-- loudness: 0..1 (crouch-walk ~0.3, walk ~0.6, run ~1.0, explosions 1.0+)
function VNPC_RegisterNoise(pos, loudness, source, radiusOverride)
    if not isvector(pos) then return end
    local enabled = GetConVar("vnpcs_noise_tracking")
    if enabled and not enabled:GetBool() then return end
    if #VNPC_NoiseEvents >= 64 then
        table.remove(VNPC_NoiseEvents, 1)
    end
    table.insert(VNPC_NoiseEvents, {
        pos = pos,
        loudness = math.max(0.05, loudness or 0.5),
        source = source,
        time = CurTime(),
        radius = radiusOverride or 0
    })
end

local function pruneNoise(now)
    for i = #VNPC_NoiseEvents, 1, -1 do
        local ev = VNPC_NoiseEvents[i]
        if (now - ev.time) > 9 or not isvector(ev.pos) then
            table.remove(VNPC_NoiseEvents, i)
        end
    end
end

-- Loudest recent noise within the predator's hearing range. Returns ev, dist.
function VNPC_HearNoise(pred, now)
    local enabled = GetConVar("vnpcs_noise_tracking")
    if enabled and not enabled:GetBool() then return nil end
    local baseRange = GetConVar("vnpcs_noise_base_range")
    local range = baseRange and baseRange:GetFloat() or 550

    -- Traits: perception scales hearing; hunger makes hungry hunters more alert
    if VNPC_GetTraitStat then
        range = range * VNPC_GetTraitStat(pred, "perception")
    end
    if VNPC_GetHungerMultiplier then
        range = range * VNPC_GetHungerMultiplier(pred)
    end

    local pos = pred:GetPos()
    local best, bestScore = nil, 0
    for _, ev in ipairs(VNPC_NoiseEvents) do
        if ev.source == pred then continue end
        local dist = pos:Distance(ev.pos)
        local evRange = (ev.radius > 0) and ev.radius or (range * ev.loudness)
        if dist <= evRange then
            -- fresher + louder + closer wins
            local age = math.max(0.2, now - ev.time)
            local score = ev.loudness / (dist + 60) / age
            if score > bestScore then
                bestScore = score
                best = ev
            end
        end
    end
    return best
end

hook.Add("PlayerFootstep", "VNPC_Noise_Footsteps", function(ply, pos, foot, sound, volume, rf)
    if not IsValid(ply) then return end
    if ply.VNPC_IsBeingSwallowed or ply.Vored then return end
    local loud = 0.35
    if ply:Crouching() then
        loud = 0.3
    elseif ply:KeyDown(IN_SPEED) then
        loud = 1.0
    else
        loud = 0.6
    end
    -- stealth trait quiets the footsteps
    if VNPC_GetTraitStat then
        loud = loud / math.max(VNPC_GetTraitStat(ply, "stealth"), 0.1)
    end
    VNPC_RegisterNoise(pos, loud, ply)
end)

hook.Add("EntityEmitSound", "VNPC_Noise_NPCFootsteps", function(data)
    if not istable(data) then return end
    local ent = data.Entity
    if not IsValid(ent) or ent:IsPlayer() then return end
    local name = string.lower(data.SoundName or "")
    if not (name:find("footstep") or name:find("run") or name:find("walk")) then return end
    if ent.Vored or ent.VNPC_Vored then return end
    local loud = math.Clamp((data.SoundLevel or 70) / 90, 0.3, 1.0)
    if VNPC_GetTraitStat then
        loud = loud / math.max(VNPC_GetTraitStat(ent, "stealth"), 0.1)
    end
    local pos = ent:GetPos()
    if data.Pos and isvector(data.Pos) then pos = data.Pos end
    VNPC_RegisterNoise(pos, loud, ent)
end)

-- ---------------------------------------------------------------------------
-- Flashlight exposure
-- ---------------------------------------------------------------------------

-- Returns the player whose flashlight beam currently hits this predator, or nil.
function VNPC_GetFlashlightExposer(pred)
    local enabled = GetConVar("vnpcs_flashlight_tracking")
    if enabled and not enabled:GetBool() then return nil end
    local rangeCv = GetConVar("vnpcs_flashlight_range")
    local maxRange = rangeCv and rangeCv:GetFloat() or 1400

    local eyePos = pred:EyePos()
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or ply == pred then continue end
        if ply:Health() <= 0 then continue end
        if not ply:FlashlightIsOn() then continue end
        local dist = ply:EyePos():Distance(eyePos)
        if dist > maxRange then continue end

        local aim = ply:GetAimVector()
        local toPred = (eyePos - ply:EyePos()):GetNormalized()
        -- beam cone ~ 28 degrees
        if aim:Dot(toPred) < math.cos(math.rad(28)) then continue end

        local tr = util.TraceLine({
            start = ply:EyePos(),
            endpos = eyePos,
            filter = { ply, pred },
            mask = MASK_VISIBLE
        })
        if tr.Hit then continue end -- beam blocked by a wall
        return ply
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Movement + navmesh helpers
-- ---------------------------------------------------------------------------

function VNPC_NavmeshLoaded()
    return navmesh and navmesh.IsLoaded and navmesh.IsLoaded() or false
end

-- Snap a point onto the nearest nav area (fallback: raw position).
function VNPC_SnapToNav(pos, radius)
    if not isvector(pos) then return pos end
    if not VNPC_NavmeshLoaded() then return pos end
    local ok, area = pcall(navmesh.GetNearestNavArea, pos, false, true, true, true)
    if ok and area and area.GetCenter then
        local ok2, center = pcall(area.GetCenter, area)
        if ok2 and isvector(center) then
            return center
        end
    end
    return pos
end

-- Move an entity toward a position (works for DrGBase nextbots and stock NPCs).
function VNPC_MoveEntTo(ent, pos, run, speedScale)
    if not IsValid(ent) or not isvector(pos) then return false end
    speedScale = speedScale or 1.0
    if ent.MoveToPos then
        local ok = pcall(ent.MoveToPos, ent, pos, {
            speed = (run and (ent.RunSpeed or 320) or (ent.WalkSpeed or 120)) * speedScale,
            use_navmesh = VNPC_NavmeshLoaded(),
            repath = 0.5
        })
        return ok ~= false
    end
    if ent.SetLastPosition then
        pcall(ent.SetLastPosition, ent, pos)
        if ent.SetSchedule then
            pcall(ent.SetSchedule, ent, run and SCHED_FORCED_GO_RUN or SCHED_FORCED_GO)
        end
        return true
    end
    return false
end

local function hasLOS(from, to, filterEnts)
    local tr = util.TraceLine({
        start = from,
        endpos = to,
        filter = filterEnts,
        mask = MASK_SOLID
    })
    return not tr.Hit
end

local function groundPos(pos)
    local tr = util.TraceLine({
        start = pos + Vector(0, 0, 60),
        endpos = pos - Vector(0, 0, 140),
        mask = MASK_SOLID
    })
    if tr.Hit then return tr.HitPos end
    return nil
end

-- ---------------------------------------------------------------------------
-- Ambush / stalk positioning
-- ---------------------------------------------------------------------------

-- Find a hidden approach point around a target: within [minD, maxD], on the
-- ground, with a clear line to the target but outside the target's view cone
-- (and behind cover when possible).
function VNPC_FindAmbushPoint(pred, target, minD, maxD)
    local predPos = pred:GetPos()
    local tPos = target:GetPos()
    local aim = Vector(0, 0, 0)
    if target.GetAimVector then aim = target:GetAimVector() end

    local best, bestScore = nil, -1e9
    local tries = 14
    local baseAng = math.random() * math.pi * 2
    for i = 0, tries - 1 do
        local ang = baseAng + (i / tries) * math.pi * 2
        local dist = minD + ((i % 5) / 4) * (maxD - minD)
        local cand = tPos + Vector(math.cos(ang) * dist, math.sin(ang) * dist, 0)
        local ground = groundPos(cand)
        if not ground then continue end
        ground.z = ground.z + 2

        -- must be reachable-ish: no wall between predator's side and candidate
        if not hasLOS(predPos, ground, { pred, target }) and predPos:Distance(ground) > 400 then continue end
        -- must have a clear sight line to the target (so the ambush works)
        if not hasLOS(ground + Vector(0, 0, 40), tPos + Vector(0, 0, 40), { pred, target }) then continue end

        local toCand = (ground - tPos):GetNormalized()
        local score = 0
        -- prefer spots behind the target (outside view cone)
        local behind = aim:Dot(toCand)
        if behind > 0.35 then
            score = score + 60
        else
            score = score - 30
        end
        -- prefer cover: blocked from target's eye height
        local coverTr = util.TraceLine({
            start = tPos + Vector(0, 0, 55),
            endpos = ground + Vector(0, 0, 55),
            mask = MASK_SOLID,
            filter = { pred, target }
        })
        if coverTr.Hit and coverTr.HitPos:Distance(tPos) < dist * 0.8 then
            score = score + 40
        end
        -- prefer higher ground
        score = score + math.Clamp((ground.z - tPos.z) * 0.4, -20, 40)
        -- prefer closer to predator's current position
        score = score - predPos:Distance(ground) * 0.03

        if score > bestScore then
            bestScore = score
            best = ground
        end
    end
    if best then
        best = VNPC_SnapToNav(best, 200)
    end
    return best
end

-- Flank position around target at a given angle offset from the leader direction.
function VNPC_GetFlankSlot(target, anchorPos, angleOffset, radius)
    if not IsValid(target) or not isvector(anchorPos) then return nil end
    local tPos = target:GetPos()
    local dir = (tPos - anchorPos)
    dir.z = 0
    if dir:LengthSqr() < 1 then dir = Vector(1, 0, 0) else dir:Normalize() end
    local ang = math.rad(angleOffset)
    local cosA, sinA = math.cos(ang), math.sin(ang)
    local slot = tPos + Vector(
        dir.x * cosA - dir.y * sinA,
        dir.x * sinA + dir.y * cosA,
        0
    ) * radius
    local ground = groundPos(slot)
    if ground then
        slot = ground + Vector(0, 0, 2)
        slot = VNPC_SnapToNav(slot, 150)
    end
    return slot
end

-- ---------------------------------------------------------------------------
-- Hazard helpers
-- ---------------------------------------------------------------------------

function VNPC_FindExplosiveBarrel(pos, radius)
    for _, ent in ipairs(ents.FindInSphere(pos, radius)) do
        if not IsValid(ent) or ent:GetClass() ~= "prop_physics" then continue end
        local mdl = string.lower(ent:GetModel() or "")
        if mdl:find("explosive") or mdl:find("barrel") or mdl:find("fuel") or mdl:find("canister") or mdl:find("propane") then
            return ent
        end
    end
    return nil
end

function VNPC_FindWaterDirection(pred, radius)
    local pos = pred:GetPos()
    for r = 200, radius, 200 do
        for s = 1, 12 do
            local ang = math.rad((s - 1) * 30)
            local testPos = pos + Vector(math.cos(ang) * r, math.sin(ang) * r, 10)
            if bit.band(util.PointContents(testPos), CONTENTS_WATER) ~= 0 then
                return (testPos - pos):GetNormalized(), testPos
            end
        end
    end
    return nil, nil
end

-- ---------------------------------------------------------------------------
-- Per-predator tactical brain
-- ---------------------------------------------------------------------------

local HUNT_STATES = { "idle", "investigate", "stalk", "ambush", "rush", "engage", "flank", "barrel", "herd" }

function VNPC_GetHuntState(pred)
    return pred.VNPC_HuntState or "idle"
end

local function setHuntState(pred, state, dur)
    pred.VNPC_HuntState = state
    pred.VNPC_HuntStateUntil = CurTime() + (dur or 3)
end

local function predIsHunter(pred)
    if not IsValid(pred) then return false end
    if pred.Vored or pred.VNPC_Vored then return false end
    if pred.VNPC_IsSleeping then return false end
    if pred.VNPC_IsDrinkingWater or pred.VNPC_IsMating or pred.VNPC_InChildbirthPose then return false end
    -- Secret assassins only hunt during their night-raid phase (mission AI owns them otherwise).
    if pred.VNPC_IsSecretAssassin and pred.VNPC_AssassinPhase ~= "night" then return false end
    -- Full belly (capacity trait): hunters with no room digest instead of hunting
    if VNPC_GetBellyCapacity then
        local belly = pred.VNPC_Belly or pred.Belly
        if IsValid(belly) and istable(belly.Prey) then
            local used = belly:GetCollectivePreyValue() or 0
            if used >= VNPC_GetBellyCapacity(belly, pred) then return false end
        end
    end
    return pred.Predator or pred.VNPC_FemaleModelVore or pred.IsDrGNextbot
end

local function getEnemy(pred)
    if pred.GetEnemy then
        local ok, en = pcall(pred.GetEnemy, pred)
        if ok and IsValid(en) then return en end
    end
    return nil
end

-- Pack cornering: assign flank roles to pack members around the pack target.
local function updatePackCornering(pred, now)
    local enabled = GetConVar("vnpcs_pack_cornering")
    if enabled and not enabled:GetBool() then return end
    local target = pred.VNPC_PackTarget or pred.VNPC_FlankTarget
    if not IsValid(target) then return end
    if not (pred.VNPC_PackLeader or pred.VNPC_PackRole) then return end

    -- Gather the pack around this leader
    local pack = {}
    local leader = IsValid(pred.VNPC_PackLeader) and pred.VNPC_PackLeader or pred
    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) or ent == target then continue end
        if not (ent.Predator or ent.VNPC_FemaleModelVore or ent.IsDrGNextbot) then continue end
        if ent.VNPC_PackLeader ~= leader and ent ~= leader then continue end
        if ent:GetPos():DistToSqr(target:GetPos()) > (900 * 900) then continue end
        table.insert(pack, ent)
    end
    if #pack < 2 then return end

    local leaderPos = leader:GetPos()
    local now2 = now
    for i, member in ipairs(pack) do
        if member == leader then
            -- leader keeps the frontal pressure
            if not member.VNPC_FlankSlot or member.VNPC_FlankSlotExpired and member.VNPC_FlankSlotExpired < now2 then
                member.VNPC_FlankSlot = nil
            end
            continue
        end
        local angleOffset = (i % 2 == 0) and 120 or -120
        if not member.VNPC_FlankSlot or (member.VNPC_FlankSlotExpired or 0) < now2 then
            member.VNPC_FlankSlot = VNPC_GetFlankSlot(target, leaderPos, angleOffset, 300)
            member.VNPC_FlankSlotExpired = now2 + 6
        end
        local slot = member.VNPC_FlankSlot
        if not slot then continue end

        local d = member:GetPos():Distance(slot)
        local distToTarget = member:GetPos():Distance(target:GetPos())
        if d > 90 and distToTarget > 200 then
            setHuntState(member, "flank", 2)
            VNPC_MoveEntTo(member, slot, true, 1.05)
        else
            -- slot reached: close the net
            setHuntState(member, "rush", 2.5)
            if member.SetEnemy then pcall(member.SetEnemy, member, target) end
            VNPC_MoveEntTo(member, target:GetPos(), true, 1.3)
        end
    end
end

-- Barrel kicking: move behind the barrel, then shove it at the target.
local function tryBarrelTactic(pred, target, now)
    local enabled = GetConVar("vnpcs_hazard_use")
    if enabled and not enabled:GetBool() then return false end
    if (pred.VNPC_NextBarrelTry or 0) > now then return false end
    pred.VNPC_NextBarrelTry = now + 7

    local barrel = VNPC_FindExplosiveBarrel(target:GetPos(), 320)
    if not IsValid(barrel) then return false end
    if pred:GetPos():Distance(barrel:GetPos()) > 700 then return false end
    -- only when we have the health to survive the blast
    if pred:Health() < pred:GetMaxHealth() * 0.55 then return false end

    local phys = barrel:GetPhysicsObject()
    if not IsValid(phys) then return false end

    pred.VNPC_BarrelTarget = barrel
    setHuntState(pred, "barrel", 4)
    return true
end

local function runBarrelTactic(pred, now)
    local barrel = pred.VNPC_BarrelTarget
    if not IsValid(barrel) then
        setHuntState(pred, "engage", 2)
        return
    end
    local target = getEnemy(pred)
    if not IsValid(target) then
        setHuntState(pred, "engage", 2)
        return
    end

    local bPos = barrel:GetPos()
    local behind = bPos + (bPos - target:GetPos()):GetNormalized() * 45
    local behindGround = groundPos(behind)
    if behindGround then behind = behindGround + Vector(0, 0, 2) end

    if pred:GetPos():Distance(behind) > 130 then
        VNPC_MoveEntTo(pred, behind, true)
        return
    end

    -- shove the barrel toward the target
    local dir = (target:GetPos() - bPos)
    dir.z = 0
    if dir:LengthSqr() < 1 then dir = Vector(1, 0, 0) else dir:Normalize() end
    if not pred.VNPC_BarrelPushing then
        pred.VNPC_BarrelPushing = { ["until"] = now + 0.8, dir = dir }
        if pred.EmitSound then pred:EmitSound("npc/antlion_guard/angry1.wav", 80, 100) end
    end
    if pred.VNPC_BarrelPushing["until"] > now then
        local mass = physMass(barrel)
        phys:ApplyForceCenter(pred.VNPC_BarrelPushing.dir * mass * 420)
        phys:ApplyAngularImpulse(Vector(0, 0, math.random(-900, 900)))
        VNPC_MoveEntTo(pred, bPos - pred.VNPC_BarrelPushing.dir * 60, false)
    else
        pred.VNPC_BarrelPushing = nil
        pred.VNPC_BarrelTarget = nil
        -- retreat from the blast
        local away = (pred:GetPos() - target:GetPos()):GetNormalized()
        local retreat = groundPos(pred:GetPos() + away * 400)
        if retreat then
            setHuntState(pred, "herd", 2.5)
            VNPC_MoveEntTo(pred, retreat, true, 1.2)
        else
            setHuntState(pred, "engage", 2)
        end
    end
end

local function physMass(ent)
    if not IsValid(ent) then return 40 end
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) and phys.GetMass then
        local m = phys:GetMass()
        if m and m > 1 then return m end
    end
    return 40
end

-- Water herding: get behind the target relative to the water and push.
local function tryHerdTactic(pred, target, now)
    local enabled = GetConVar("vnpcs_hazard_use")
    if enabled and not enabled:GetBool() then return false end
    if (pred.VNPC_NextHerdTry or 0) > now then return false end
    pred.VNPC_NextHerdTry = now + 9

    local waterDir = VNPC_FindWaterDirection(pred, 1100)
    if not waterDir then return false end

    -- target must be between the predator and the water for the herd to work
    local toTarget = (target:GetPos() - pred:GetPos()):GetNormalized()
    if toTarget:Dot(waterDir) < 0.35 then return false end

    setHuntState(pred, "herd", 3)
    return true
end

local function runHerdTactic(pred, target)
    -- charge straight at the target; they back up into the water
    setHuntState(pred, "rush", 2)
    if pred.SetEnemy then pcall(pred.SetEnemy, pred, target) end
    VNPC_MoveEntTo(pred, target:GetPos(), true, 1.25)
end

-- ---------------------------------------------------------------------------
-- Main think
-- ---------------------------------------------------------------------------

hook.Add("Think", "VNPC_HunterAI_TacticalLoop", function()
    local master = GetConVar("vnpcs_hunter_ai_enabled")
    if master and not master:GetBool() then return end
    local smartEnabled = GetConVar("vnpcs_smart_ai_enabled")
    if smartEnabled and not smartEnabled:GetBool() then return end

    local now = CurTime()
    pruneNoise(now)

    for _, pred in ipairs(ents.GetAll()) do
        if not predIsHunter(pred) then continue end
        if (pred.VNPC_NextHunterThink or 0) > now then continue end
        pred.VNPC_NextHunterThink = now + 0.3

        local enemy = getEnemy(pred)
        local state = pred.VNPC_HuntState or "idle"

        -- 1. FLASHLIGHT EXPOSURE: track whoever's beam is on us
        if GetConVar("vnpcs_flashlight_tracking"):GetBool() then
            local exposer = VNPC_GetFlashlightExposer(pred)
            if IsValid(exposer) then
                pred.VNPC_FlashlightExposed = exposer
                pred.VNPC_FlashlightExposedUntil = now + 4
                if not IsValid(enemy) and (pred.SetEnemy) and (pred.VNPC_Hunger or 50) > 20 then
                    pcall(pred.SetEnemy, pred, exposer)
                    enemy = exposer
                    setHuntState(pred, "rush", 3)
                end
            end
        end

        -- 2. NOISE: investigate loud sounds when idle/hungry
        if not IsValid(enemy) and GetConVar("vnpcs_noise_tracking"):GetBool() then
            local noise = VNPC_HearNoise(pred, now)
            if noise and (pred.VNPC_Hunger or 50) > 15 and (state == "idle" or state == "investigate") then
                setHuntState(pred, "investigate", 5)
                VNPC_MoveEntTo(pred, noise.pos, false, 1.1)
                -- if the noise source is visible once we're close, engage
                if pred:GetPos():Distance(noise.pos) < 200 and IsValid(noise.source) then
                    if pred.SetEnemy then pcall(pred.SetEnemy, pred, noise.source) end
                    enemy = noise.source
                    setHuntState(pred, "rush", 3)
                end
            end
        end

        -- 3. PACK CORNERING (roles assigned by pack hunting)
        if GetConVar("vnpcs_pack_cornering"):GetBool() and (pred.VNPC_PackTarget or pred.VNPC_FlankSlot) then
            updatePackCornering(pred, now)
        end

        -- 4. HAZARDS
        if IsValid(enemy) then
            if state == "barrel" then
                runBarrelTactic(pred, now)
                continue
            end
            if state ~= "herd" and GetConVar("vnpcs_hazard_use"):GetBool() then
                if tryBarrelTactic(pred, enemy, now) then
                    continue
                end
                if tryHerdTactic(pred, enemy, now) then
                    runHerdTactic(pred, enemy)
                    continue
                end
            elseif state == "herd" then
                runHerdTactic(pred, enemy)
                continue
            end

            -- 5. AMBUSH / STALK
            if GetConVar("vnpcs_ambush_ai"):GetBool() then
                local dist = pred:GetPos():Distance(enemy:GetPos())
                local backTurned = false
                local aim = enemy.GetAimVector and enemy:GetAimVector() or Vector(0, 0, 0)
                if aim:LengthSqr() > 0.01 then
                    local toPred = (pred:GetPos() - enemy:GetPos()):GetNormalized()
                    backTurned = aim:Dot(toPred) < -0.35
                end

                if dist > 900 then
                    -- far: normal approach, but walk a curved line when unseen
                    if (pred.VNPC_HuntState or "idle") ~= "rush" then
                        setHuntState(pred, "engage", 2)
                    end
                elseif dist > 380 and backTurned then
                    -- mid range with back turned: stalk to a flanking ambush point
                    if (pred.VNPC_HuntState or "idle") ~= "stalk" or (pred.VNPC_StalkPointExpired or 0) < now then
                        local ambush = VNPC_FindAmbushPoint(pred, enemy, 300, 620)
                        if ambush then
                            pred.VNPC_StalkPoint = ambush
                            pred.VNPC_StalkPointExpired = now + 5
                            setHuntState(pred, "stalk", 5)
                        end
                    end
                    if pred.VNPC_StalkPoint then
                        VNPC_MoveEntTo(pred, pred.VNPC_StalkPoint, true, 0.95)
                    end
                elseif dist <= 380 and backTurned then
                    -- close + unaware: burst out of the ambush
                    if (pred.VNPC_HuntState or "idle") ~= "rush" then
                        setHuntState(pred, "rush", 3)
                        if pred.SetEnemy then pcall(pred.SetEnemy, pred, enemy) end
                    end
                    VNPC_MoveEntTo(pred, enemy:GetPos(), true, 1.35)
                else
                    -- spotted: drop the stealth act and commit
                    setHuntState(pred, "rush", 2)
                    VNPC_MoveEntTo(pred, enemy:GetPos(), true, 1.1)
                end
            end
        else
            -- no enemy: settle back to idle after the state expires
            if (pred.VNPC_HuntStateUntil or 0) < now then
                setHuntState(pred, "idle", 2)
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Debug overlay + status
-- ---------------------------------------------------------------------------

if CLIENT then
    hook.Add("PostDrawTranslucentRenderables", "VNPC_HunterAI_Debug", function()
        local dbg = GetConVar("vnpcs_hunter_debug")
        if not dbg or not dbg:GetBool() then return end
        for _, pred in ipairs(ents.GetAll()) do
            if not IsValid(pred) then continue end
            local state = pred.VNPC_HuntState
            if not state then continue end
            local col = Color(255, 255, 255)
            if state == "stalk" then col = Color(255, 200, 60)
            elseif state == "ambush" then col = Color(255, 120, 60)
            elseif state == "rush" then col = Color(255, 60, 60)
            elseif state == "flank" then col = Color(90, 200, 255)
            elseif state == "barrel" then col = Color(255, 140, 40)
            elseif state == "herd" then col = Color(80, 160, 255)
            elseif state == "investigate" then col = Color(200, 255, 120) end
            local pos = pred:GetPos() + Vector(0, 0, 88)
            render.DrawText(pos, string.upper(state), col, 2, 2)
            if pred.VNPC_StalkPoint then
                render.DrawLine(pred:GetPos() + Vector(0, 0, 40), pred.VNPC_StalkPoint + Vector(0, 0, 4), Color(255, 200, 60, 180), true)
                render.DrawWireframeSphere(pred.VNPC_StalkPoint, 10, 6, 6, Color(255, 200, 60, 200), true)
            end
            if pred.VNPC_FlankSlot then
                render.DrawWireframeSphere(pred.VNPC_FlankSlot, 12, 6, 6, Color(90, 200, 255, 200), true)
            end
        end
    end)
end

concommand.Add("vnpcs_hunter_ai_status", function(ply)
    print("===============================================================")
    print("            V-NPCs HUNTER AI (SMART NEXTBOT) STATUS            ")
    print("===============================================================")
    print(" - Hunter AI: " .. tostring(GetConVar("vnpcs_hunter_ai_enabled"):GetBool()))
    print(" - Noise Tracking: " .. tostring(GetConVar("vnpcs_noise_tracking"):GetBool()) .. " (base range " .. tostring(GetConVar("vnpcs_noise_base_range"):GetFloat()) .. ")")
    print(" - Flashlight Tracking: " .. tostring(GetConVar("vnpcs_flashlight_tracking"):GetBool()) .. " (range " .. tostring(GetConVar("vnpcs_flashlight_range"):GetFloat()) .. ")")
    print(" - Ambush AI: " .. tostring(GetConVar("vnpcs_ambush_ai"):GetBool()))
    print(" - Pack Cornering: " .. tostring(GetConVar("vnpcs_pack_cornering"):GetBool()))
    print(" - Hazard Use: " .. tostring(GetConVar("vnpcs_hazard_use"):GetBool()))
    print(" - Navmesh Loaded: " .. tostring(VNPC_NavmeshLoaded()))
    print(" - Active Noise Events: " .. #VNPC_NoiseEvents)
    print("-----------------------------------------")
    local count = 0
    for _, pred in ipairs(ents.GetAll()) do
        if IsValid(pred) and predIsHunter(pred) then
            count = count + 1
            local enemy = getEnemy(pred)
            local exposed = IsValid(pred.VNPC_FlashlightExposed) and tostring(pred.VNPC_FlashlightExposed) or "-"
            print(string.format(" -> #%d [%s] state=%s enemy=%s flashlight=%s",
                pred:EntIndex(), pred.PrintName or pred:GetClass(),
                string.upper(pred.VNPC_HuntState or "idle"),
                IsValid(enemy) and tostring(enemy) or "none", exposed))
        end
    end
    if count == 0 then print(" - No hunter predators currently spawned.") end
    print("===============================================================")
    if IsValid(ply) then
        ply:ChatPrint("[V-NPCs] Hunter AI status printed to console. Hunters: " .. count)
    end
end)

concommand.Add("vnpcs_test_noise", function(ply)
    if not IsValid(ply) then return end
    VNPC_RegisterNoise(ply:GetPos() + ply:GetForward() * 120, 1.0, ply)
    local tr = util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 400 })
    local pos = tr.HitPos or (ply:GetPos() + ply:GetForward() * 150)
    VNPC_RegisterNoise(pos, 1.0, ply)
    ply:ChatPrint("[V-NPCs] Emitted a loud noise event. Nearby predators will investigate!")
end)

concommand.Add("vnpcs_test_ambush", function(ply)
    if not IsValid(ply) then return end
    local target = ply:GetEyeTrace().Entity
    if not IsValid(target) or not (target.Predator or target.VNPC_FemaleModelVore or target.IsDrGNextbot) then
        ply:ChatPrint("[V-NPCs] Aim at a predator to force an ambush-stalk state!")
        return
    end
    target.VNPC_PackTarget = ply
    target.VNPC_FlankTarget = ply
    setHuntState(target, "stalk", 8)
    ply:ChatPrint("[V-NPCs] Forced " .. tostring(target) .. " into STALK state against you. Enable vnpcs_hunter_debug 1 to watch.")
end)
