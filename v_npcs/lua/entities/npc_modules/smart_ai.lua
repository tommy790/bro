--[[

    SMART NEXTBOT AI & NAVIGATION MESH

    Adds a light "tactics" layer on top of DrGBase's own nextbot chase/patrol
    logic:

        - Pack Hunting: v-npcs hunting the same target keep track of who's
          "primary" (closest) and periodically peel secondary hunters off to
          flank/surround the target using the navmesh instead of all
          beelining in a single file.

        - Ambush behaviour: when idle, v-npcs occasionally tuck themselves
          into a nearby-but-unseen nav area near their patrol route and wait,
          springing the moment a player gets close and has line of sight.

        - Sound & Flashlight tracking: v-npcs can notice players by the
          noise of their footsteps (louder/faster footsteps carry further)
          or by catching a flashlight beam pointed near them, even without a
          direct hard-coded sight check.

    Everything here is defensive (pcall'd navmesh calls, convar kill
    switches) since navmesh availability and DrGBase internals can vary
    between maps/versions.

]]

local smart_ai_enabled    = CreateConVar("vnpcs_smart_ai", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED})
local smart_ai_hearing    = CreateConVar("vnpcs_smart_ai_hearing", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED})
local smart_ai_packhunt   = CreateConVar("vnpcs_smart_ai_packhunt", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED})
local smart_ai_ambush     = CreateConVar("vnpcs_smart_ai_ambush", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED})
local smart_ai_navmesh    = CreateConVar("vnpcs_smart_ai_navmesh", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED})

--how many consecutive failed think cycles (broken navmesh, a DrGBase update
--changing/removing MoveTowards/AddPatrolPos, etc) before we stop trying and
--permanently fall back to DrGBase's own plain, foolproof direct-chase for
--that specific NPC instead of erroring (or silently no-op'ing) every 0.3s
--forever.
local SMART_AI_MAX_FAILURES = 3


VNPC_NoiseEvents = VNPC_NoiseEvents or {} --[ply] = {pos=Vector, time=number, loud=bool}
VNPC_Packs = VNPC_Packs or {} --[enemy] = {[npc]=true, ...}

local function VNPC_RegisterHunter(npc, enemy)
    VNPC_Packs[enemy] = VNPC_Packs[enemy] or {}
    VNPC_Packs[enemy][npc] = true
end

local function VNPC_UnregisterHunter(npc)
    for _, members in pairs(VNPC_Packs) do
        members[npc] = nil
    end
end

local function VNPC_GetPack(enemy)
    return VNPC_Packs[enemy]
end

local function hasNavmesh()
    if not smart_ai_navmesh:GetBool() then return false end
    if not navmesh or not navmesh.IsLoaded then return false end

    local ok, loaded = pcall(navmesh.IsLoaded)
    return ok and loaded
end

if SERVER then
    --footsteps are the main way v-npcs "hear" players
    hook.Add("PlayerFootstep", "VNPCsSmartAI_Footsteps", function(ply, pos, foot, soundName, volume)
        if not IsValid(ply) or ply.Vored then return end

        local speed = ply:GetVelocity():Length2D()
        VNPC_NoiseEvents[ply] = {
            pos = pos,
            time = CurTime(),
            loud = speed > 200, --sprinting/fast movement carries further
        }
    end)

    --keep the pack registry from leaking memory/growing forever
    timer.Create("VNPCsSmartAI_PackCleanup", 5, 0, function()
        for enemy, members in pairs(VNPC_Packs) do
            if not IsValid(enemy) then
                VNPC_Packs[enemy] = nil
                continue
            end

            for npc, _ in pairs(members) do
                if not IsValid(npc) or npc:GetEnemy() ~= enemy then
                    members[npc] = nil
                end
            end

            if not next(members) then
                VNPC_Packs[enemy] = nil
            end
        end
    end)

    hook.Add("EntityRemoved", "VNPCsSmartAI_Cleanup", function(ent)
        if ent:IsPlayer() then
            VNPC_NoiseEvents[ent] = nil
        end
        VNPC_UnregisterHunter(ent)
    end)
end

function ENT:InitSmartAI()
    self._smartAI = {
        nextThink = 0,
        flankPos = nil,
        flankUntil = 0,
        nextFlank = 0,
        ambushPos = nil,
        ambushUntil = 0,
        nextAmbushPick = 0,
        failures = 0,
        disabled = false,
    }
end

function ENT:SmartAI_ProcessHearing(state, now)
    if not smart_ai_hearing:GetBool() then return end
    if IsValid(self:GetEnemy()) then return end --already knows about someone

    local settings = self.VoreSettings.SmartAI or {}
    local hearingRange = settings.HearingRange or 700
    local flashRange = settings.FlashlightSpotRange or 900

    local myPos = self:GetPos()
    local best, bestDist = nil, math.huge

    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() or ply.Vored then continue end

        local dist = myPos:Distance(ply:GetPos())
        local heard = false

        local noise = VNPC_NoiseEvents[ply]
        if noise and (now - noise.time) < 0.6 then
            local range = noise.loud and hearingRange or (hearingRange * 0.4)
            if dist <= range then heard = true end
        end

        if not heard and ply:FlashlightIsOn() and dist <= flashRange then
            local eyePos = ply:EyePos()
            local toUs = (self:WorldSpaceCenter() - eyePos):GetNormalized()
            local aim = ply:EyeAngles():Forward()

            if aim:Dot(toUs) > 0.9 then
                local tr = util.TraceLine({
                    start = eyePos,
                    endpos = self:WorldSpaceCenter(),
                    filter = {ply, self},
                })

                if not tr.Hit or tr.HitPos:Distance(self:WorldSpaceCenter()) < 60 then
                    heard = true
                end
            end
        end

        if heard and dist < bestDist then
            best, bestDist = ply, dist
        end
    end

    if best then
        self:SpotEntity(best)
        self:SetEntityRelationship(best, D_HT, 3)
    end
end

function ENT:SmartAI_PackTactics(state, enemy, now)
    local settings = self.VoreSettings.SmartAI or {}
    if settings.PackHunting == false then return end
    if not smart_ai_packhunt:GetBool() then return end

    local pack = VNPC_GetPack(enemy)
    if not pack then return end

    local count, myIndex, i = 0, 0, 0
    local closest, closestDist = nil, math.huge

    for member, _ in pairs(pack) do
        if not IsValid(member) then continue end

        count = count + 1
        i = i + 1
        if member == self then myIndex = i end

        local dist = member:GetPos():Distance(enemy:GetPos())
        if dist < closestDist then
            closest, closestDist = member, dist
        end
    end

    if count < 2 then return end --need at least 2 npcs to bother flanking
    if closest == self then return end --the closest npc just chases normally

    --currently mid-flank, keep steering there directly (in case DrGBase's
    --own chase logic would otherwise override the patrol point)
    if state.flankPos and now < state.flankUntil then
        self:MoveTowards(state.flankPos)
        self:FaceTowards(enemy:GetPos())

        if self:GetPos():Distance(state.flankPos) < 48 or closestDist < 90 then
            state.flankUntil = 0 --close enough, rejoin the normal attack
        end
        return
    end

    if now < state.nextFlank then return end
    state.nextFlank = now + math.Rand(2.5, 4.5)

    local flankAngle = (360 / math.max(count, 2)) * myIndex

    local travel = enemy:GetVelocity()
    if travel:Length2D() < 10 then travel = enemy:GetForward() end
    travel = travel:GetNormalized()

    local offset = travel * -150 -- start roughly opposite of travel direction
    offset:Rotate(Angle(0, flankAngle, 0))

    local flankPos = enemy:GetPos() + offset

    if hasNavmesh() then
        local ok, area = pcall(navmesh.GetNearestNavArea, flankPos)
        if ok and area and area.IsValid and area:IsValid() then
            local ok2, closestPoint = pcall(area.GetClosestPointOnArea, area, flankPos)
            if ok2 and closestPoint then
                flankPos = closestPoint
            end
        end
    end

    state.flankPos = flankPos
    state.flankUntil = now + math.Rand(3, 5)

    self:ClearPatrols()
    self:AddPatrolPos(flankPos)
end

function ENT:SmartAI_Ambush(state, now)
    local settings = self.VoreSettings.SmartAI or {}
    if settings.Ambushes == false then return end
    if not smart_ai_ambush:GetBool() then return end
    if not hasNavmesh() then return end

    if state.ambushPos and now < state.ambushUntil then
        for _, ply in ipairs(player.GetAll()) do
            if not IsValid(ply) or not ply:Alive() or ply.Vored then continue end
            if self:GetPos():Distance(ply:GetPos()) > 220 then continue end

            local tr = util.TraceLine({
                start = self:WorldSpaceCenter(),
                endpos = ply:WorldSpaceCenter(),
                filter = {self},
            })

            if not tr.Hit or tr.Entity == ply then
                self:SpotEntity(ply)
                self:SetEntityRelationship(ply, D_HT, 5)
                state.ambushPos = nil
                state.ambushUntil = 0
                return
            end
        end
        return
    end

    if now < state.nextAmbushPick then return end
    state.nextAmbushPick = now + math.Rand(6, 12)
    if math.random() > 0.35 then return end --don't ambush constantly, keep it occasional

    local ok, area = pcall(navmesh.GetNearestNavArea, self:GetPos())
    if not ok or not area or not area.IsValid or not area:IsValid() then return end

    local ok2, adjacent = pcall(area.GetAdjacentAreas, area)
    if not ok2 or not adjacent then return end

    local candidates = {}
    for _, near in pairs(adjacent) do
        table.insert(candidates, near)
    end
    if #candidates == 0 then return end

    local chosen = candidates[math.random(1, #candidates)]
    local ok3, point = pcall(chosen.GetRandomPoint, chosen)
    if not ok3 or not point then return end

    state.ambushPos = point
    state.ambushUntil = now + math.Rand(8, 14)

    self:ClearPatrols()
    self:AddPatrolPos(point)
end

function ENT:SmartAIThink()
    if CLIENT then return end
    if not smart_ai_enabled:GetBool() then return end
    if not self._smartAI then self:InitSmartAI() end

    local state = self._smartAI
    if state.disabled then return end --tripped the circuit breaker, just let DrGBase do its plain direct-chase

    local now = CurTime()
    if now < state.nextThink then return end
    state.nextThink = now + 0.3

    local ok, err = pcall(function()
        self:SmartAI_ProcessHearing(state, now)

        local enemy = self:GetEnemy()
        if IsValid(enemy) then
            VNPC_RegisterHunter(self, enemy)
            self:SmartAI_PackTactics(state, enemy, now)
        else
            VNPC_UnregisterHunter(self)
            self:SmartAI_Ambush(state, now)
        end
    end)

    if ok then
        state.failures = 0
        return
    end

    --something about this map/DrGBase version doesn't like our tactics
    --layer (missing navmesh functions, MoveTowards/AddPatrolPos behaving
    --differently, etc). Back off a few times before giving up for good so a
    --single one-off hiccup doesn't permanently disable the feature.
    state.failures = state.failures + 1
    print("[V-NPCs] SmartAI hiccup on "..tostring(self).." ("..state.failures.."/"..SMART_AI_MAX_FAILURES.."): "..tostring(err))

    if state.failures >= SMART_AI_MAX_FAILURES then
        state.disabled = true
        VNPC_UnregisterHunter(self)

        --clean up anything we might have left mid-maneuver so DrGBase's own
        --plain chase/patrol logic takes back over immediately and cleanly
        local cleanupOk = pcall(function() self:ClearPatrols() end)

        print("[V-NPCs] SmartAI disabled itself for "..tostring(self)..
            " after repeated errors - falling back to standard Nextbot chasing for this NPC."..
            " Set vnpcs_smart_ai 0 to silence this addon-wide, or report the error above if it looks like a real bug.")
    end
end

