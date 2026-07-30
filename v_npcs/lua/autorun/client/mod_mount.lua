local function DownloadAndMount(id)
    steamworks.DownloadUGC(id, function(path, file)
        game.MountGMA(path)
    end)
end

local function noModBitch()
    local mod = net.ReadString()
    local npcName = net.ReadString()
    local frame = vgui.Create("DFrame")
    frame:SetTitle('"'..npcName..'" Failure')
    frame:SetSize(250, 200)
    frame:Center()
    frame:MakePopup()

    local label = vgui.Create("DLabel", frame)
    label:SetText("Model failed to load, check console for more info.\n                If you don't have the model?")
    label:SetSize(380, 60)
    label:SetPos(10, 10)

    local id = string.match(mod, "id=(%d+)")

    steamworks.FileInfo( id, function( result ) 

        if not result or result.banned then
            local page = vgui.Create("DButton", frame)
            page:SetText("Open Download Page")
            page:SetSize(170, 30)
            page:SetPos(40, 60)

            page.DoClick = function()
                gui.OpenURL(mod)
                frame:Close()
            end
            
            return
        end
        -------
        local page = vgui.Create("DButton", frame)
        page:SetText("Open Workshop Page")
        page:SetSize(170, 30)
        page:SetPos(40, 60)

        page.DoClick = function()
            steamworks.ViewFile(id)
            frame:Close()
        end
        local label = vgui.Create("DLabel", frame)
        label:SetText("Subscribe to the addon to have it permanently.\n                     Requires server restart.")
        label:SetSize(230, 30)
        label:SetPos(15, 90)

        local download = vgui.Create("DButton", frame)
        download:SetText("Download and Mount")
        download:SetSize(170, 30)
        download:SetPos(40, 129)
        download.DoClick = function()
            DownloadAndMount(id)
            frame:Close()
        end

        local label = vgui.Create("DLabel", frame)
        label:SetText("  Temporarily downloads the addon.")
        label:SetSize(240, 30)
        label:SetPos(39, 160)
    end)   
end

net.Receive("VoreNoModNotif", noModBitch)