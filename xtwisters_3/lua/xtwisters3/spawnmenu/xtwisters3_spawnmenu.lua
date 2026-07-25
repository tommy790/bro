AddCSLuaFile()

if not CLIENT then
    return
end

function AddToXTwisters3Menu(name, class, category, subcategory, adminonly, swep)
    if category == "Vortexes" then

        list.Set("XTwisters3_Vortexes", class, {
            Name = name,
            Class = class,
            Category = subcategory,
            AdminOnly = adminonly,
            Offset = 0
        })

    elseif category == "Weather" then

        list.Set("XTwisters3_Weather", class, {
            Name = name,
            Class = class,
            Category = subcategory,
            AdminOnly = adminonly,
            Offset = 0
        })

    elseif category == "Disasters" then

        list.Set("XTwisters3_Disasters", class, {
            Name = name,
            Class = class,
            Category = subcategory,
            AdminOnly = adminonly,
            Offset = 0
        })

    elseif category == "Weapons" then

        list.Set("XTwisters3_Weapons", class, {
            Name = name,
            Class = class,
            Category = subcategory,
            AdminOnly = adminonly,
            IsWeapon = swep,
            Offset = 0
        })

    elseif category == "Miscellaneous" then

        list.Set("XTwisters3_Miscellaneous", class, {
            Name = name,
            Class = class,
            Category = subcategory,
            AdminOnly = adminonly,
            Offset = 0
        })

    end
end

spawnmenu.AddCreationTab("XTwisters3", function()
    local ctrl = vgui.Create("SpawnmenuContentPanel")
    ctrl:CallPopulateHook("PopulateXT3Vortexes")
    ctrl:CallPopulateHook("PopulateXT3Weather")
    ctrl:CallPopulateHook("PopulateXT3Disasters")
    ctrl:CallPopulateHook("PopulateXT3Weapons")
    ctrl:CallPopulateHook("PopulateXT3Miscellaneous")
    return ctrl
end, "materials/SpawnMenuIcons/XT3Icon.png", 50)

local function NewMenu(NodeName, NodeIcon, List, pnlContent, tree, node)

    local xtree = tree:AddNode(NodeName, NodeIcon)
    xtree.PropPanel = vgui.Create("ContentContainer", pnlContent)
    xtree.PropPanel:SetVisible(false)
    xtree.PropPanel:SetTriggerSpawnlistChange(false)

    local EntityCategories = {}
    local SpawnableEntitiesList = list.Get(List)
    if (SpawnableEntitiesList) then
        for k, v in pairs(SpawnableEntitiesList) do

            EntityCategories[v.Category] = EntityCategories[v.Category] or {}
            table.insert(EntityCategories[v.Category], v)
        end
    end

    for CategoryName, v in SortedPairs(EntityCategories) do

        local node2 = xtree:AddNode(CategoryName, NodeIcon)

        node2.DoPopulate = function(self)

            if (self.PropPanel) then
                return
            end

            self.PropPanel = vgui.Create("ContentContainer", pnlContent)
            self.PropPanel:SetVisible(false)
            self.PropPanel:SetTriggerSpawnlistChange(false)

            for name, ent in SortedPairsByMemberValue(v, "Name") do
                local TypeToAdd
                local Type = 0

                if ent.IsWeapon then
                    TypeToAdd = "weapon"
                    Type = 3
                else
                    TypeToAdd = "entity"
                end

                local icon = vgui.Create("ContentIcon", self.PropPanel)

                icon:SetContentType(TypeToAdd)
                icon:SetName(ent.PrintName or ent.Name)
                icon:SetSpawnName(ent.Class)
                icon:SetAdminOnly(ent.AdminOnly)

                if file.Exists("materials/entities/" .. ent.Class .. ".png", "GAME") then
                    icon:SetMaterial("entities/" .. ent.Class .. ".png")
                else
                    icon:SetMaterial("entities/xt3placeholder.png")
                end

                icon.DoClick = function()
                    local LocalPlayer = LocalPlayer()
                    local AllowSpawn = true

                    if ent.AdminOnly or GetConVar("xtwisters3_adminspawnonly"):GetBool() then
                        if LocalPlayer:IsAdmin() then
                            AllowSpawn = true
                        else
                            AllowSpawn = false
                        end
                    end

                    if AllowSpawn then
                        if icon:GetContentType() == "entity" then
                            local SpawnParams = {
                                SpawnType = "ENT";
                                ObjectToSpawn = icon:GetSpawnName();
                                Player = LocalPlayer;
                                SpawnLocation = LocalPlayer:GetEyeTrace().HitPos;
                            }

                            net.Start("xt3_spawnentity")
                            net.WriteTable(SpawnParams)
                            net.SendToServer()
                        else
                            local SpawnParams = {
                                SpawnType = "SWEP";
                                ObjectToSpawn = icon:GetSpawnName();
                                Player = LocalPlayer;
                            }

                            net.Start("xt3_spawnentity")
                            net.WriteTable(SpawnParams)
                            net.SendToServer()

                            local Tools = LocalPlayer:GetWeapons()
                            for Index = 1, #Tools do
                                local Tool = Tools[Index]
                                if Tool and Tool:IsValid() and Tool:GetClass() == icon:GetSpawnName() then
                                    input.SelectWeapon( Tool )
                                end
                            end
                        end
                    end

                    surface.PlaySound("ui/buttonclickrelease.wav")
                end

                icon.OpenMenu = function(icon)
                    local ExtraStuff = DermaMenu()
                    ExtraStuff:AddOption("Copy to clipboard", function()
                        SetClipboardText(ent.Class)
                    end):SetImage("icon16/page_copy.png")

                    ExtraStuff:AddOption("Spawn using toolgun", function()
                        RunConsoleCommand("gmod_tool", "creator")

                        RunConsoleCommand("creator_type", tostring(Type))
                        RunConsoleCommand("creator_name", ent.Class)
                    end):SetImage("icon16/brick_add.png")

                    ExtraStuff:Open()
                end

                self.PropPanel:Add(icon)
            end

        end

        node2.DoClick = function(self)
            self:DoPopulate()
            pnlContent:SwitchPanel(self.PropPanel)
        end

    end
end

hook.Add("PopulateXT3Vortexes", "AddXTwisters3Vortexes", function(pnlContent, tree, node)
    NewMenu("Tornadoes & Whirlwinds", "materials/SpawnMenuIcons/XT3VortexesIcon.png", "XTwisters3_Vortexes", pnlContent, tree, node)
end)

hook.Add("PopulateXT3Weather", "AddXTwisters3Weather", function(pnlContent, tree, node)
    NewMenu("Weather & Phenomena", "materials/SpawnMenuIcons/XT3WeatherIcon.png", "XTwisters3_Weather", pnlContent, tree, node)
end)

hook.Add("PopulateXT3Disasters", "AddXTwisters3Disasters", function(pnlContent, tree, node)
    NewMenu("Disasters", "materials/SpawnMenuIcons/XT3DisastersIcon.png", "XTwisters3_Disasters", pnlContent, tree, node)
end)

hook.Add("PopulateXT3Weapons", "AddXTwisters3Weapons", function(pnlContent, tree, node)
    NewMenu("Weapons", "materials/SpawnMenuIcons/XT3WeaponsIcon.png", "XTwisters3_Weapons", pnlContent, tree, node)
end)

hook.Add("PopulateXT3Miscellaneous", "AddXTwisters3Miscellaneous", function(pnlContent, tree, node)
    NewMenu("Miscellaneous", "materials/SpawnMenuIcons/XT3MiscellaneousIcon.png", "XTwisters3_Miscellaneous", pnlContent, tree, node)
end)

