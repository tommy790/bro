--[[

    MODULAR STATUS & TRAIT SYSTEM - client status menu

    Right click a V-NPC predator and choose "Vore Status..." to pull this up.
    Every slider here maps 1:1 to a trait defined in npc_modules/traits.lua.

]]

if not CLIENT then return end

local TRAIT_INFO = {
    {
        key = "MetabolismSpeed",
        nw = "Trait_Metabolism",
        label = "Metabolism Speed",
        min = 0.1, max = 6,
        help = "How quickly this predator digests & absorbs prey.",
    },
    {
        key = "AcidResistance",
        nw = "Trait_AcidRes",
        label = "Acid Resistance",
        min = 0.1, max = 6,
        help = "How resistant this NPC is to being digested if it ends up as prey itself.",
    },
    {
        key = "MaxCapacity",
        nw = "Trait_MaxCap",
        label = "Max Capacity Limit",
        min = 0, max = 24,
        help = "Max amount of living prey this predator can hold at once. 0 = unlimited.",
    },
    {
        key = "StaminaPenalty",
        nw = "Trait_Stamina",
        label = "Stamina Penalty",
        min = 0, max = 4,
        help = "How much heavier prey slows this predator's movement speed down.",
    },
}

function OpenVoreStatusMenu(ent)
    if not IsValid(ent) then return end

    local frame = vgui.Create("DFrame")
    frame:SetTitle("Status & Traits - "..(ent.PrintName or ent:GetClass()))
    frame:SetSize(380, 420)
    frame:Center()
    frame:MakePopup()

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    scroll:DockMargin(5, 5, 5, 5)

    for _, info in ipairs(TRAIT_INFO) do
        local label = vgui.Create("DLabel", scroll)
        label:SetText(info.label)
        label:SetFont("DermaDefaultBold")
        label:SizeToContents()
        label:Dock(TOP)
        label:DockMargin(2, 10, 2, 0)

        local help = vgui.Create("DLabel", scroll)
        help:SetText(info.help)
        help:SetWrap(true)
        help:SetAutoStretchVertical(true)
        help:SetTextColor(Color(150, 150, 150))
        help:Dock(TOP)
        help:DockMargin(2, 0, 2, 2)

        local slider = vgui.Create("DNumSlider", scroll)
        slider:Dock(TOP)
        slider:DockMargin(0, 0, 0, 2)
        slider:SetText("")
        slider:SetMin(info.min)
        slider:SetMax(info.max)
        slider:SetDecimals(2)
        slider:SetValue(ent:GetNWFloat(info.nw, 1))

        slider.OnValueChanged = function(_, value)
            net.Start("VNPC_SetTrait")
                net.WriteEntity(ent)
                net.WriteString(info.key)
                net.WriteFloat(value)
            net.SendToServer()
        end
    end

    local resetBtn = vgui.Create("DButton", frame)
    resetBtn:SetText("Reset all to defaults")
    resetBtn:Dock(BOTTOM)
    resetBtn:DockMargin(5, 0, 5, 5)
    resetBtn.DoClick = function()
        for _, info in ipairs(TRAIT_INFO) do
            net.Start("VNPC_SetTrait")
                net.WriteEntity(ent)
                net.WriteString(info.key)
                net.WriteFloat(info.key == "MaxCapacity" and 0 or 1)
            net.SendToServer()
        end
        frame:Close()
    end

    local close = vgui.Create("DButton", frame)
    close:SetText("Close")
    close:Dock(BOTTOM)
    close:DockMargin(5, 0, 5, 0)
    close.DoClick = function() frame:Close() end
end
