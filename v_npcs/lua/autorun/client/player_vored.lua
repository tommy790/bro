
local viewHook = "vore_camera"
local scrollHook = "vore_mousewheel"
local hudHook = "vore_hud"

local is_internal_view = false



local function setInternalView(bool, npc, belly)
    if is_internal_view == bool then return end

    is_internal_view = bool

    if not npc or not IsValid(npc) then return end
    if not belly or not IsValid(belly) then return end

    if bool then
        
        npc.OldColor = npc:GetColor()
        belly.OldColor = belly:GetColor()

        npc:SetColor(Color(0,0,0))
        belly:SetColor(Color(0,0,0))

        npc:SetRenderMode(RENDERMODE_GLOW)
        belly:SetRenderMode(RENDERMODE_GLOW)
    else
        npc:SetColor(npc.OldColor)
        belly:SetColor(belly.OldColor)
    end
end

local function displayText(text, x, y, font, color)
    surface.SetFont(font) -- Set the font
    local width, height = surface.GetTextSize( text )
    local x,y = x -width/2, y - height/2

    surface.SetTextColor(color) -- Set text color
    surface.SetTextPos(x, y) -- Set text position, top left corner
    surface.DrawText(text, false) -- Draw the text
end

--[[
    Struggle meter.

    The value is entirely server-authored (SetNW2Float from belly_modules/
    struggle.lua); this only renders whatever the server says it is.
]]
-- resolved lazily: the convar is created by belly_modules/struggle.lua, which
-- may not have been loaded yet when this autorun file runs
local escape_enabled
local function escapeEnabled()
    if not escape_enabled then
        escape_enabled = GetConVar("vnpcs_prey_escape")
    end

    if not escape_enabled then return true end
    return escape_enabled:GetBool()
end

local smoothedEscape = 0

local function drawStruggleMeter(ply)
    if not escapeEnabled() then return end

    local progress = math.Clamp(ply:GetNW2Float("VoreEscapeProgress", 0), 0, 1)

    -- ease towards the networked value so the bar does not step at the
    -- server's update rate
    smoothedEscape = Lerp(1 - math.exp(-12 * FrameTime()), smoothedEscape, progress)
    if smoothedEscape < 0.005 and progress <= 0 then smoothedEscape = 0 end

    local w, h = 260, 14
    local x, y = (ScrW() - w) / 2, ScrH() * 0.8

    surface.SetDrawColor(0, 0, 0, 160)
    surface.DrawRect(x - 2, y - 2, w + 4, h + 4)

    surface.SetDrawColor(28, 20, 24, 220)
    surface.DrawRect(x, y, w, h)

    -- red while hopeless, green as you approach freedom
    local fill = math.Round(w * smoothedEscape)
    surface.SetDrawColor(
        math.Round(Lerp(smoothedEscape, 206, 120)),
        math.Round(Lerp(smoothedEscape, 74, 214)),
        math.Round(Lerp(smoothedEscape, 88, 120)),
        235)
    surface.DrawRect(x, y, fill, h)

    local label = smoothedEscape > 0.02 and "Struggle!" or "Struggle to break free"
    displayText(label, ScrW() / 2, y - 14, "Trebuchet24", Color(0, 0, 0))
    displayText(label, ScrW() / 2, y - 15, "Trebuchet24", Color(235, 225, 225))
end

local function noMoreVore()
    local ply = LocalPlayer()

    hook.Remove('CalcView', viewHook)
    hook.Remove("CreateMove", scrollHook)
    hook.Remove("HUDShouldDraw", hudHook)
    hook.Remove("HUDPaint", hudHook)
    if IsValid(ply) then
        ply:RemoveFlags(FL_NOTARGET)
        ply:DrawViewModel(true)
        ply.VoreCameraPos = nil
    end
    smoothedEscape = 0
    setInternalView(false)
end

local function OnVored()
    local belly = net.ReadEntity()
    local npc = net.ReadEntity()
    local ZmMult = 1
    local bellyAnchorPoint = belly:GetParentAttachment()

    local isWormsBelly = belly:GetClass() == "ent_vore_belly"

    gui.AddCaption( "*Gulp*", 5 )

    local ply = LocalPlayer()

    hook.Add('CalcView', viewHook, function(ply, origin, ang, fov) --SUPER HARD CODED, GET RID OF THIS CODE
        if not IsValid(belly) or not IsValid(npc) then
            noMoreVore()
            return
        end
    
        ply:DrawViewModel(false)

        local entPos = belly:GetPos()
        if belly.InteralCameraPos then --CUSTOM POSITION AND ANGLE SHI
            entPos, ang = belly:InteralCameraPos(entPos, ang)
            ang = ang - ply:GetViewPunchAngles()
        else
            ang = ang - ply:GetViewPunchAngles() - belly:GetAngles() - npc:GetAngles()
            ang = Angle(ang.x, ang.y, 0) --whatever
        end

        ply.VoreCameraPos = entPos

        local tr = util.TraceLine({
            start = entPos,
            endpos = (entPos - (ang:Forward() * 100) * ZmMult),
            filter = {belly, npc, ply}
        })

        local view = {
            origin = tr.HitPos + (tr.HitNormal),
            angles = ang,
            fov = fov,
            drawviewer = false 
        }

        return view
    end)

    hook.Add("HUDShouldDraw", hudHook, function( name ) 
        if name == "CHudDamageIndicator" or name == "CHudDeathNotice" or name == "CHudPoisonDamageIndicator" or name == "CHudCrosshair" or name == "CHudAmmo" or name == "CHudWeaponSelection" or name == "CHudSecondaryAmmo" then 
            return false 
        end
    end)

    hook.Add("HUDPaint", hudHook, function()
        local ply = LocalPlayer()
        if ply:FlashlightIsOn() then
            setInternalView(true, npc, belly)
        else
            setInternalView(false, npc, belly)
        end

        if not IsValid(ply) or not ply:Alive() then
            setInternalView(false, npc, belly)
            local text = "You have been digested..."

            surface.SetFont( "Trebuchet24" ) -- Set the font
            local x,y = (ScrW() / 2), ScrH() * .75 

            displayText(text, x, y + 3, "Trebuchet24", Color(0,0,0))
            displayText(text, x, y, "Trebuchet24", Color(229,145,145))
            return
        end

        if is_internal_view then
            displayText("this is the temporary internal view, i might finish it", ScrW()/2, ScrH()/2, "BudgetLabel", Color(255,255,255))
        end

        drawStruggleMeter(ply)
	end)

    hook.Add("CreateMove", scrollHook, function(cmd)
         if cmd:GetMouseWheel() ~= 0 then
            ZmMult = ZmMult - cmd:GetMouseWheel() * 0.05
            if ZmMult < 0.5 then
                ZmMult = 0.5
            end
            if ZmMult > 4 then
                ZmMult = 4
            end
        end
    end)
end

net.Receive("UGotVored", OnVored)
net.Receive("StopVoreClient", noMoreVore)

net.Receive("VoreEscaped", function()
    gui.AddCaption("*You struggle free!*", 4)
end)