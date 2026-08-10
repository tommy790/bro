-- V-NPCs Client-Side 1st-Person Inside-Belly Camera & Escape Rhythm Mini-Game HUD (cl_vnpcs_inside_cam.lua)
-- Renders fleshy organic vignette, heartbeat rhythm ring, and escape struggle progress bar

local cl_cam_enabled = CreateConVar("vnpcs_cl_inside_cam_enabled", "1", {FCVAR_ARCHIVE}, "Enable client 1st-person inside-belly camera overlay")
local cl_minigame_enabled = CreateConVar("vnpcs_cl_minigame_enabled", "1", {FCVAR_ARCHIVE}, "Enable Escape Rhythm Mini-Game HUD ring")
local cl_heartbeat_volume = CreateConVar("vnpcs_cl_heartbeat_volume", "80", {FCVAR_ARCHIVE}, "Volume of heartbeat acoustics in inside-belly view")

VNPC_CL_InsideCamActive = true
VNPC_CL_EscapeMeter = 0
VNPC_CL_LastHitFeedback = ""
VNPC_CL_FeedbackColor = Color(255, 255, 255)
VNPC_CL_FeedbackTime = 0
VNPC_CL_NextPunchTime = 0
VNPC_CL_NextHeartbeatSound = 0

net.Receive("VNPC_EscapeProgress", function()
    VNPC_CL_EscapeMeter = net.ReadFloat() or 0
end)

function VNPC_CalculateHeartbeatTiming()
    local now = CurTime()
    local interval = 1.35
    local cycle = (now % interval) / interval
    if cycle <= 0.18 then
        return 2, cycle -- Perfect Heartbeat Hit!
    elseif cycle <= 0.36 then
        return 1, cycle -- Good Hit
    else
        return 0, cycle -- Miss
    end
end

-- Hook into reload key to toggle inside-cam mode and attack keys to punch
hook.Add("PlayerBindPress", "VNPC_InsideCam_Binds", function(ply, bind, pressed)
    if not pressed or not IsValid(ply) then return end
    if not (ply.Vored or ply.VNPC_VoredBelly) then return end

    if string.find(bind, "reload") then
        VNPC_CL_InsideCamActive = not VNPC_CL_InsideCamActive
        surface.PlaySound("buttons/lightswitch2.wav")
        ply:ChatPrint("[V-NPCs] Inside-Belly Camera: " .. (VNPC_CL_InsideCamActive and "ENABLED (1st-Person)" or "DISABLED (3rd-Person)"))
        return true
    end

    if (string.find(bind, "attack") or string.find(bind, "attack2")) and cl_minigame_enabled:GetBool() and VNPC_CL_InsideCamActive then
        local now = CurTime()
        if now < (VNPC_CL_NextPunchTime or 0) then return true end
        VNPC_CL_NextPunchTime = now + 0.45

        local score, cycle = VNPC_CalculateHeartbeatTiming()
        if score == 2 then
            VNPC_CL_LastHitFeedback = "PERFECT!"
            VNPC_CL_FeedbackColor = Color(80, 255, 120)
            surface.PlaySound("physics/body/body_medium_impact_hard1.wav")
        elseif score == 1 then
            VNPC_CL_LastHitFeedback = "GOOD"
            VNPC_CL_FeedbackColor = Color(255, 220, 80)
            surface.PlaySound("physics/body/body_medium_impact_soft1.wav")
        else
            VNPC_CL_LastHitFeedback = "MISS..."
            VNPC_CL_FeedbackColor = Color(255, 90, 90)
            surface.PlaySound("buttons/button10.wav")
        end
        VNPC_CL_FeedbackTime = now + 1.25

        net.Start("VNPC_StrugglePunch")
        net.WriteUInt(score, 3)
        net.SendToServer()
        return true
    end
end)

function VNPC_RenderInsideBellyHUD(ply, npc, belly)
    if not cl_cam_enabled:GetBool() then return end
    if not IsValid(ply) or not ply:Alive() then return end

    local now = CurTime()
    local sw, sh = ScrW(), ScrH()
    local pulse = (math.sin(now * 4.6) + 1.0) * 0.5
    local score, cycle = VNPC_CalculateHeartbeatTiming()

    -- 1. Fleshy organic border vignette
    surface.SetDrawColor(150, 25, 45, math.floor(130 + pulse * 60))
    local borderSize = math.floor(25 + pulse * 15)
    surface.DrawRect(0, 0, sw, borderSize)               -- Top
    surface.DrawRect(0, sh - borderSize, sw, borderSize) -- Bottom
    surface.DrawRect(0, 0, borderSize, sh)               -- Left
    surface.DrawRect(sw - borderSize, 0, borderSize, sh) -- Right

    -- Heartbeat acoustic thump foley
    if now >= (VNPC_CL_NextHeartbeatSound or 0) then
        VNPC_CL_NextHeartbeatSound = now + 1.35
        surface.PlaySound("vore_stomach/digestion_loop1.wav")
    end

    if not cl_minigame_enabled:GetBool() then return end

    -- 2. Escape Progress Bar (Bottom Center)
    local barW, barH = 340, 24
    local barX, barY = (sw - barW) * 0.5, sh - 65

    surface.SetDrawColor(35, 10, 15, 220)
    surface.DrawRect(barX, barY, barW, barH)

    local fillW = math.floor((barW - 4) * math.Clamp(VNPC_CL_EscapeMeter / 100, 0, 1))
    surface.SetDrawColor(80, 240, 120, 230)
    surface.DrawRect(barX + 2, barY + 2, fillW, barH - 4)

    draw.SimpleText("ESCAPE PROGRESS: " .. math.floor(VNPC_CL_EscapeMeter) .. "%", "Trebuchet24", sw * 0.5, barY + barH * 0.5, Color(255, 255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- 3. Heartbeat Rhythm Circle (Above Progress Bar)
    local ringX, ringY = sw * 0.5, barY - 70
    local targetRadius = 32

    -- Outer contracting circle
    local outerRadius = math.floor(targetRadius + (1.0 - cycle) * 55)
    surface.SetDrawColor(255, 120, 140, 200)
    for r = outerRadius - 1, outerRadius + 1 do
        for i = 0, 360, 12 do
            local rad = math.rad(i)
            local x1 = ringX + math.cos(rad) * r
            local y1 = ringY + math.sin(rad) * r
            surface.DrawRect(x1, y1, 2, 2)
        end
    end

    -- Center target ring
    surface.SetDrawColor(255, 255, 255, 220)
    for r = targetRadius - 1, targetRadius + 1 do
        for i = 0, 360, 12 do
            local rad = math.rad(i)
            local x1 = ringX + math.cos(rad) * r
            local y1 = ringY + math.sin(rad) * r
            surface.DrawRect(x1, y1, 2, 2)
        end
    end

    if score == 2 then
        draw.SimpleText("[ PUNCH NOW! ]", "Trebuchet24", ringX, ringY, Color(80, 255, 120, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    else
        draw.SimpleText("♥", "Trebuchet24", ringX, ringY, Color(220, 50, 70, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Hit feedback text (PERFECT / GOOD / MISS)
    if now <= VNPC_CL_FeedbackTime then
        draw.SimpleText(VNPC_CL_LastHitFeedback, "Trebuchet24", ringX, ringY - 50, VNPC_CL_FeedbackColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- 4. Instructions
    draw.SimpleText("[R] Toggle View   |   [LMB/RMB] Punch on Heartbeat to Escape!", "Default", sw * 0.5, sh - 25, Color(230, 230, 230, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end
