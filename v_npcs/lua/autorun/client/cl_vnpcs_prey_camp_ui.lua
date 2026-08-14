-- V-NPCs Client-Side Prey Camp Recruitment UI (cl_vnpcs_prey_camp_ui.lua)
-- Surfaces an interactive Derma popup dialog asking if the player wants to join a Prey Camp

if not CLIENT then return end

net.Receive("VNPC_PreyCampJoinPrompt", function()
    local campID = net.ReadUInt(32)
    local townStageName = net.ReadString() or "OUTPOST"
    local memberCount = net.ReadUInt(16) or 1

    if IsValid(VNPC_PreyCampJoinFrame) then
        VNPC_PreyCampJoinFrame:Remove()
    end

    local frame = vgui.Create("DFrame")
    frame:SetSize(360, 170)
    frame:Center()
    frame:SetTitle("Prey Camp Recruitment")
    frame:SetVisible(true)
    frame:SetDraggable(true)
    frame:ShowCloseButton(true)
    frame:MakePopup()
    VNPC_PreyCampJoinFrame = frame

    local lbl = vgui.Create("DLabel", frame)
    lbl:SetFont("DermaDefaultBold")
    lbl:SetText("Would you like to join Prey Camp #" .. tostring(campID) .. "?")
    lbl:SetTextColor(Color(255, 255, 255))
    lbl:SetSize(340, 24)
    lbl:SetPos(15, 38)
    lbl:SetContentAlignment(5)

    local desc = vgui.Create("DLabel", frame)
    desc:SetFont("DermaDefault")
    desc:SetText(string.format("Town Stage: %s | Active Citizens: %d", townStageName, memberCount))
    desc:SetTextColor(Color(200, 220, 255))
    desc:SetSize(340, 20)
    desc:SetPos(15, 68)
    desc:SetContentAlignment(5)

    local btnYes = vgui.Create("DButton", frame)
    btnYes:SetText("Yes (Join Camp)")
    btnYes:SetSize(140, 36)
    btnYes:SetPos(25, 110)
    btnYes.DoClick = function()
        surface.PlaySound("buttons/button14.wav")
        net.Start("VNPC_PreyCampJoinResponse")
            net.WriteUInt(campID, 32)
            net.WriteBool(true)
        net.SendToServer()
        frame:Close()
    end

    local btnNo = vgui.Create("DButton", frame)
    btnNo:SetText("No (Decline)")
    btnNo:SetSize(140, 36)
    btnNo:SetPos(195, 110)
    btnNo.DoClick = function()
        surface.PlaySound("buttons/button15.wav")
        net.Start("VNPC_PreyCampJoinResponse")
            net.WriteUInt(campID, 32)
            net.WriteBool(false)
        net.SendToServer()
        frame:Close()
    end
end)
