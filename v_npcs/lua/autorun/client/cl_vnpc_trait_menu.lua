-- V-NPCs Status & Trait Editor Menu (cl_vnpc_trait_menu.lua)
-- Client-side Derma UI to view live NPC status (personality, hunger, level,
-- belly stats, traits) and assign/remove traits from the modular trait system.
-- Works from the spawn menu (V-NPCs -> Status & Traits) and from the
-- "Trait Editor" toolgun, which opens a standalone window.

local STAT_LABELS = {
    metabolism = "Metabolism",
    acid_resistance = "Acid Resistance",
    capacity = "Belly Capacity",
    weight_resistance = "Weight Resistance",
    struggle_energy = "Struggle Energy",
    perception = "Perception",
    night_vision = "Night Vision",
    stealth = "Stealth",
    aggression = "Aggression"
}

local function isPredEnt(ent)
    if not IsValid(ent) then return false end
    return ent.Predator or ent.VNPC_FemaleModelVore or ent.IsDrGNextbot or ent.EatEntity ~= nil
end

local function npcIsEligible(ent)
    if not IsValid(ent) then return false end
    if ent:IsPlayer() then return false end
    if not (ent:IsNPC() or ent:IsNextBot() or ent.IsDrGNextbot) then return false end
    return true
end

local function npcTraitList(ent)
    if not IsValid(ent) then return {} end
    local str = ent.GetNWString and ent:GetNWString("VNPC_Traits", "") or ""
    if str == "" then return {} end
    local out = {}
    for id in string.gmatch(str, "[^,]+") do
        out[id] = true
    end
    return out
end

local function collectCandidates()
    local list = {}
    local seen = {}
    for _, ent in ipairs(ents.GetAll()) do
        if not npcIsEligible(ent) then continue end
        if seen[ent] then continue end
        seen[ent] = true
        table.insert(list, ent)
    end
    table.sort(list, function(a, b)
        local av, bv = isPredEnt(a), isPredEnt(b)
        if av ~= bv then return av end
        return (a.PrintName or a:GetClass()) < (b.PrintName or b:GetClass())
    end)
    return list
end

-- Item management that works on both spawnmenu control panels (which have
-- AddItem/ClearControls) and plain DScrollPanels/DPanels.
local function clearItems(container)
    if not IsValid(container) then return end
    if container.ClearControls then
        pcall(container.ClearControls, container)
    end
    for _, item in ipairs(container.VNPC_Items or {}) do
        if IsValid(item) then
            item:Remove()
        end
    end
    container.VNPC_Items = {}
end

local function addItem(container, item)
    if not IsValid(container) or not IsValid(item) then return end
    container.VNPC_Items = container.VNPC_Items or {}
    table.insert(container.VNPC_Items, item)
    if container.AddItem then
        container:AddItem(item)
    else
        item:SetParent(container)
        item:Dock(TOP)
        item:DockMargin(0, 2, 0, 2)
    end
end

local function makeLabel(text, color, tall)
    local label = vgui.Create("DLabel")
    label:SetText(text or "")
    label:SetTall(tall or 20)
    if color then label:SetTextColor(color) end
    return label
end

local function makeButton(text, onClick, w)
    local btn = vgui.Create("DButton")
    btn:SetText(text)
    btn:SetTall(24)
    btn:SetWide(w or 120)
    btn.DoClick = onClick
    return btn
end

local function buildTraitRows(container, ent)
    for _, item in ipairs(container.VNPC_TraitRows or {}) do
        if IsValid(item) then item:Remove() end
    end
    container.VNPC_TraitRows = {}
    if not IsValid(ent) then return end

    local pred = isPredEnt(ent)
    local owned = npcTraitList(ent)

    local sorted = {}
    for id, data in pairs(VNPC_TRAITS or {}) do
        table.insert(sorted, id)
    end
    table.sort(sorted, function(a, b)
        return (VNPC_TRAITS[a].name or a) < (VNPC_TRAITS[b].name or b)
    end)

    local function rebuild()
        if IsValid(container) and IsValid(ent) then
            buildTraitRows(container, ent)
            updateInfoLabels(container, ent)
        end
    end

    for _, id in ipairs(sorted) do
        local data = VNPC_TRAITS[id]
        if data.kind == "predator" and not pred then continue end
        if data.kind == "prey" and pred then continue end

        local row = vgui.Create("DPanel")
        row:SetTall(36)
        row:DockMargin(0, 2, 0, 2)
        row.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, Color(40, 40, 48, 220))
        end

        local cb = vgui.Create("DCheckBox", row)
        cb:SetPos(8, 10)
        cb:SetChecked(owned[id] == true)
        cb:SetTooltip(data.description or "")
        cb.OnChange = function(self, checked)
            if not IsValid(ent) then return end
            if checked then
                RunConsoleCommand("vnpcs_trait_add", tostring(ent:EntIndex()), id)
            else
                RunConsoleCommand("vnpcs_trait_remove", tostring(ent:EntIndex()), id)
            end
            timer.Simple(0.35, rebuild)
        end

        local name = vgui.Create("DLabel", row)
        name:SetPos(32, 4)
        name:SetSize(170, 16)
        name:SetText(data.name or id)
        name:SetFont("DermaDefaultBold")

        local desc = vgui.Create("DLabel", row)
        desc:SetPos(32, 19)
        desc:SetSize(360, 14)
        desc:SetText(data.description or "")
        desc:SetTextColor(Color(180, 180, 190))

        table.insert(container.VNPC_TraitRows, row)
        addItem(container, row)
    end
end

local function updateInfoLabels(container, ent)
    if not IsValid(container) or not IsValid(container.VNPC_InfoLabel) then return end
    if not IsValid(ent) then
        container.VNPC_InfoLabel:SetText("Pick an NPC from the list (or aim with the Trait Editor tool).")
        return
    end

    local pred = isPredEnt(ent)
    local pers = "?"
    if pred and VNPC_GetPredatorPersonality then
        pers = select(1, VNPC_GetPredatorPersonality(ent)) or "?"
    elseif VNPC_GetPreyPersonality then
        pers = select(1, VNPC_GetPreyPersonality(ent)) or "?"
    end

    local parts = {
        string.format("#%d  %s", ent:EntIndex(), ent.PrintName or ent:GetClass()),
        string.format("%s  |  Personality: %s", pred and "PREDATOR" or "PREY", tostring(pers))
    }
    if pred then
        local level = ent.GetNWInt and ent:GetNWInt("VNPC_Level", 1) or 1
        local hunger = ent.GetNWFloat and ent:GetNWFloat("VNPC_Hunger", -1) or -1
        local bellySize = ent.GetNWFloat and ent:GetNWFloat("BellySize", 0) or 0
        table.insert(parts, string.format("Level %d  |  Hunger %.0f%%  |  Belly size %.2f", level, math.max(0, hunger), bellySize))
    end

    -- Recompute stat summary from the replicated trait string
    local mults = {}
    local str = ent.GetNWString and ent:GetNWString("VNPC_Traits", "") or ""
    for id in string.gmatch(str, "[^,]+") do
        local data = VNPC_TRAITS and VNPC_TRAITS[id]
        if data and data.stats then
            for stat, v in pairs(data.stats) do
                mults[stat] = (mults[stat] or 1.0) * v
            end
        end
    end
    local summary = {}
    for _, stat in ipairs({ "metabolism", "acid_resistance", "capacity", "weight_resistance", "struggle_energy", "perception", "stealth", "aggression" }) do
        local v = mults[stat]
        if v and math.abs(v - 1.0) > 0.001 then
            table.insert(summary, string.format("%s x%.2f", STAT_LABELS[stat] or stat, v))
        end
    end
    if #summary > 0 then
        table.insert(parts, "Stats: " .. table.concat(summary, "  |  "))
    end

    container.VNPC_InfoLabel:SetText(table.concat(parts, "\n"))
end

-- Builds the full trait editor inside any container panel (spawnmenu page or
-- DScrollPanel). Falls back to plain docking when AddItem is unavailable.
function VNPC_BuildTraitEditor(container, ent)
    if not IsValid(container) then return end
    clearItems(container)
    container.VNPC_TraitRows = {}

    local info = vgui.Create("DLabel")
    info:SetTall(66)
    info:SetTextColor(Color(230, 230, 240))
    container.VNPC_InfoLabel = info
    addItem(container, info)

    local selector = vgui.Create("DComboBox")
    selector:SetTall(26)
    selector:SetValue("Pick an NPC...")
    local candidates = collectCandidates()
    for _, cand in ipairs(candidates) do
        selector:AddChoice(
            string.format("#%d %s [%s]", cand:EntIndex(), cand.PrintName or cand:GetClass(), isPredEnt(cand) and "PRED" or "PREY"),
            cand:EntIndex()
        )
    end
    selector.OnSelect = function(self, index, value, data)
        local sel = Entity(data or 0)
        if IsValid(sel) then
            container.VNPC_SelectedEnt = sel
            updateInfoLabels(container, sel)
            buildTraitRows(container, sel)
        end
    end
    addItem(container, selector)

    local function refresh()
        local sel = container.VNPC_SelectedEnt
        if IsValid(sel) then
            updateInfoLabels(container, sel)
            buildTraitRows(container, sel)
        end
    end

    local buttonRow = vgui.Create("DPanel")
    buttonRow:SetTall(30)
    buttonRow:DockMargin(0, 4, 0, 4)
    buttonRow.Paint = function() end

    local randomize = makeButton("Randomize Traits", function()
        local sel = container.VNPC_SelectedEnt
        if IsValid(sel) then
            RunConsoleCommand("vnpcs_trait_randomize", tostring(sel:EntIndex()))
            timer.Simple(0.35, refresh)
        end
    end)
    randomize:SetParent(buttonRow)
    randomize:SetPos(0, 2)

    local clear = makeButton("Clear All", function()
        local sel = container.VNPC_SelectedEnt
        if IsValid(sel) then
            RunConsoleCommand("vnpcs_trait_clear", tostring(sel:EntIndex()))
            timer.Simple(0.35, refresh)
        end
    end)
    clear:SetParent(buttonRow)
    clear:SetPos(150, 2)

    local refreshBtn = makeButton("Refresh", refresh)
    refreshBtn:SetParent(buttonRow)
    refreshBtn:SetPos(300, 2)

    addItem(container, buttonRow)

    local sep = makeLabel("Assign traits (conflicts resolve automatically):", Color(255, 200, 120), 20)
    addItem(container, sep)

    -- v0.7 personality matrix sliders
    local matrixSep = makeLabel("Personality Matrix (mix behavioral profiles):", Color(120, 220, 255), 24)
    addItem(container, matrixSep)

    local axisLabels = {
        stealth = "Stealth (stalking, hiding, quiet)",
        greed = "Greed (digestion speed, appetite)",
        shy = "Shy (hunts unseen, camouflages)",
        aggression = "Aggression (rushing, pinning, chasing)",
        gentle = "Gentle (slow digestion, calm)",
        playful = "Playful (misc. behaviors)"
    }
    local function refreshMatrix(container, ent)
        if not IsValid(container) or not IsValid(ent) then return end
        local mix = VNPC_GetMatrixFromNW and VNPC_GetMatrixFromNW(ent) or {}
        for _, slider in ipairs(container.VNPC_MatrixSliders or {}) do
            if IsValid(slider) then
                slider:SetValue(mix[slider.VNPC_Axis] or 0)
            end
        end
    end
    container.VNPC_MatrixSliders = {}
    for _, axis in ipairs(VNPC_MATRIX_AXES or {}) do
        local row = vgui.Create("DPanel")
        row:SetTall(46)
        row:DockMargin(0, 2, 0, 2)
        row.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, Color(28, 38, 48, 220))
        end

        local label = vgui.Create("DLabel", row)
        label:SetPos(8, 2)
        label:SetSize(220, 14)
        label:SetText(axisLabels[axis] or axis)
        label:SetTextColor(Color(150, 200, 230))

        local slider = vgui.Create("DNumSlider", row)
        slider:SetPos(8, 16)
        slider:SetSize(380, 26)
        slider:SetMin(0)
        slider:SetMax(1)
        slider:SetDecimals(2)
        slider:SetValue(0)
        slider.VNPC_Axis = axis
        slider.Label:SetText("")
        slider.OnValueChanged = function(self, val)
            local sel = container.VNPC_SelectedEnt
            if IsValid(sel) then
                -- debounce: fire 0.4s after the last change
                if sel.VNPC_MatrixDebounce then
                    timer.Remove(sel.VNPC_MatrixDebounce)
                end
                sel.VNPC_MatrixDebounce = "vnpcs_matrix_" .. sel:EntIndex()
                timer.Create(sel.VNPC_MatrixDebounce, 0.4, 1, function()
                    if IsValid(sel) then
                        RunConsoleCommand("vnpcs_matrix_set", tostring(sel:EntIndex()), axis, string.format("%.2f", val))
                    end
                end)
            end
        end

        table.insert(container.VNPC_MatrixSliders, slider)
        addItem(container, row)
    end

    local matrixReset = makeButton("Reset Matrix to Personality", function()
        local sel = container.VNPC_SelectedEnt
        if IsValid(sel) then
            RunConsoleCommand("vnpcs_matrix_clear", tostring(sel:EntIndex()))
            timer.Simple(0.4, function()
                if IsValid(container) and IsValid(sel) then
                    refreshMatrix(container, sel)
                end
            end)
        end
    end)
    addItem(container, matrixReset)

    if IsValid(ent) then
        container.VNPC_SelectedEnt = ent
        updateInfoLabels(container, ent)
        buildTraitRows(container, ent)
        refreshMatrix(container, ent)
    else
        updateInfoLabels(container, nil)
    end
end

-- Spawn menu entry (same re-add-on-populate pattern as tool_menu.lua)
hook.Add("PopulateToolMenu", "VNPC_TraitMenu_Populate", function()
    spawnmenu.AddToolMenuOption("V-NPCs", "Status & Traits", "vnpcs_trait_editor", "Status & Traits", "", "", function(panel)
        VNPC_BuildTraitEditor(panel, nil)
    end)
end)

-- Standalone editor window (used by the Trait Editor toolgun)
function VNPC_OpenTraitEditorWindow(ent)
    local frame = vgui.Create("DFrame")
    frame:SetTitle("V-NPCs Status & Trait Editor")
    frame:SetSize(440, 640)
    frame:Center()
    frame:MakePopup()

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    scroll:DockPadding(10, 10, 10, 10)

    VNPC_BuildTraitEditor(scroll, ent)
end

concommand.Add("vnpcs_trait_menu_open", function(ply, _, args)
    local ent = nil
    local idx = tonumber(args and args[1])
    if idx then
        local cand = Entity(idx)
        if IsValid(cand) then ent = cand end
    else
        local tr = ply:GetEyeTrace()
        if tr and IsValid(tr.Entity) then ent = tr.Entity end
    end
    VNPC_OpenTraitEditorWindow(ent)
end)
