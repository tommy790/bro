
local function displayFullResImage(material)
    local frame = vgui.Create("DFrame")
    frame:SetTitle('Click X to close')

    local width, height = material:Width(), material:Height()

    frame:SetSize(width + 8, height + 26)
    frame:Center()
    frame:MakePopup()

    local logo = vgui.Create("DImage", frame)
    logo:SetSize(width, height)
    logo:SetPos(4, 22)
    logo:SetMaterial(material)
end


local function addImage(panel, img, make_full_res_button)
    local logo = vgui.Create("DImage")
    logo:SetSize(300,300)
    logo:SetImage(img)
    logo:SetKeepAspect(true)
    panel:AddItem(logo)

    local material = logo:GetMaterial()
    local width, height = material:Width(), material:Height()
    logo:SetSize(270, 270 * (height/width))

    if make_full_res_button then
        local display_full_res = panel:Button("Display Full Image")
        display_full_res.DoClick = function()
            displayFullResImage(material)
        end
    end
end

local function do_popup(text, title)
	local mainFrame = vgui.Create("DFrame")
	mainFrame:SetSize(325, 100)
	mainFrame:Center()
	mainFrame:SetTitle(title)	-- Title of window
	mainFrame:MakePopup()

	local _text = vgui.Create("DLabel", mainFrame)
	_text:SetText(text)
    _text:DockPadding(15,15,15,15)
    _text:Dock(1)
end

local function populate()
    spawnmenu.AddToolMenuOption("V-NPCs", "Personalization", "vnpcs_settings", "Settings", "", "", function(panel)
        panel:ClearControls()

        panel:CheckBox("Burps Enabled", "vnpcs_burps")
        panel:CheckBox("Patrolling while full", "vnpcs_patrol_full")
        panel:CheckBox("Weight Gain", "vnpcs_gain")
        panel:CheckBox("Insta-vore", "vnpcs_instavore")
        panel:CheckBox("Camera Sway", "vnpcs_camerasway")
        panel:CheckBox("Belly Clipping Fix", "vnpcs_bellyclipping")

        panel:NumSlider("Belly-fat Loss", "vnpcs_belly_fat_lose", 0, 8, 1)
        panel:ControlHelp("This makes V-NPCs will lose their belly fat after awhile. Tied to absorption power.")
        panel:NumSlider("Weight Gain Loss", "vnpcs_weight_loss", 0, 8, 1)
        panel:ControlHelp("This makes V-NPCs will lose weight they gained after awhile. Tied to absorption power and weight gain multiplier.")


        panel:Help("\nMultipliers\n")
        panel:ControlHelp("(Multiplies the NPC's settings)")

        --MECHANICS
        panel:NumSlider("Digestion Power multiplier", "vnpcs_digestion_multi", 0, 20, 1)
        panel:NumSlider("Absorption Power multiplier", "vnpcs_absorption_multi", 0, 20, 1)
        panel:NumSlider("Slow from Weight multiplier", "vnpcs_speeddiff", 0, 4, 1)
        panel:NumSlider("Digestion Heal multiplier", "vnpcs_absorptionheal_multi", 0, 4, 1)

        panel:ControlHelp("")
        --VISUAL
        panel:NumSlider("Struggle Animation multiplier", "vnpcs_struggle_multi", 0, 8, 1)
        panel:NumSlider("Weight Gain multiplier", "vnpcs_gain_multi", 0, 8, 1)
        panel:NumSlider("Belly-fat gain multiplier", "vnpcs_fat_multi", 0, 2, 1)
        panel:NumSlider("Belly-fat max multiplier", "vnpcs_fatcap_multi", 0, 4, 1)


        panel:Help("\nForcers\n")
        panel:ControlHelp("Sets the variable to the multiplier, so all V-NPCs have the same values/settings")

        panel:CheckBox("Force Digestion Power", "vnpcs_global_digestion")
        panel:ControlHelp("Default is 2")
        panel:CheckBox("Force Absorption Power", "vnpcs_global_absorption")
        panel:ControlHelp("Default is 1.5")
        panel:CheckBox("Force Struggle Animation", "vnpcs_global_struggle")
        panel:ControlHelp("Default is 1.2")
        panel:CheckBox("Force Belly-fat Max", "vnpcs_global_fatcap")
        panel:ControlHelp("Default is 0.5")

        panel:ControlHelp("")

        panel:CheckBox("Force Burps", "vnpcs_global_burps")
        panel:CheckBox("Force Weight Gain", "vnpcs_global_gain")

        --panel:CheckBox("Do Custom Animations", "drg_animate")
        panel:ControlHelp("")
        panel:ControlHelp("")
    end)

    spawnmenu.AddToolMenuOption("V-NPCs", "Personalization", "vnpcs_personality", "Personality", "", "", function(panel)
        panel:ClearControls()

        panel:Help("this is system will be replaced later by a more advanced one later")
        panel:Help("")

        panel:Help("\nForcers\n")
        panel:ControlHelp("Sets the variable to the multiplier, so all V-NPCs have the same values/settings")

        panel:CheckBox("Hungry for Players", "vnpcspersonality_players")
        panel:CheckBox("Hungry for NPCs", "vnpcspersonality_npcs")
    end)

    spawnmenu.AddToolMenuOption("V-NPCs", "Info", "vnpcs_credits", "Credits", "", "", function(panel)
        panel:ClearControls()

        panel:Help("V-NPCs")
        addImage(panel, "vnpcs/vnpcslogo.png")
        do
            local help = panel:ControlHelp("www.aryion.com/forum/vnpcs") --idk why im lying, BUT no one wants to see an ugly url
            help:SetMouseInputEnabled(true) --WHY
            help:SetKeyboardInputEnabled(true) --WHY
            help.DoClick = function()
                gui.OpenURL("https://aryion.com/forum/viewtopic.php?f=79&t=69727")
            end
        end
        panel:Help("Inspired by MechoFoxlur's Alyx Vore mod\n")

        panel:Help("Credits\n")
        panel:Help("Creator - wormonlooker")
        do
            local help = panel:ControlHelp("aryion.com/g4/user/wormonlooker")
            help:SetMouseInputEnabled(true) --WHY
            help:SetKeyboardInputEnabled(true) --WHY
            help.DoClick = function()
                gui.OpenURL("https://aryion.com/g4/user/wormonlooker")
            end
        end
        do
            local help = panel:ControlHelp("x.com/wormord")
            help:SetMouseInputEnabled(true) --WHY
            help:SetKeyboardInputEnabled(true) --WHY
            help.DoClick = function()
                gui.OpenURL("https://x.com/wormord")
            end
        end

        panel:Help("Sounds - Hora")
        do
            local help = panel:ControlHelp("x.com/HoraGator")
            help:SetMouseInputEnabled(true) --WHY
            help:SetKeyboardInputEnabled(true) --WHY
            help.DoClick = function()
                gui.OpenURL("https://x.com/HoraGator")
            end
        end
        do
            local help = panel:ControlHelp("furaffinity.net/user/helios542")
            help:SetMouseInputEnabled(true) --WHY
            help:SetKeyboardInputEnabled(true) --WHY
            help.DoClick = function()
                gui.OpenURL("https://www.furaffinity.net/user/helios542")
            end
        end
        do
            local help = panel:ControlHelp("bsky.app/profile/gator-bellies.bsky.social")
            help:SetMouseInputEnabled(true) --WHY
            help:SetKeyboardInputEnabled(true) --WHY
            help.DoClick = function()
                gui.OpenURL("https://bsky.app/profile/gator-bellies.bsky.social")
            end
        end

        panel:Help("Contributor - Muri")
        do
            local help = panel:ControlHelp("aryion.com/g4/user/svuzz")
            help:SetMouseInputEnabled(true) --WHY
            help:SetKeyboardInputEnabled(true) --WHY
            help.DoClick = function()
                gui.OpenURL("https://aryion.com/g4/user/svuzz")
            end
        end

        panel:Help("")

        panel:Help("Belly Model - FERRUM")
        do
            local help = panel:ControlHelp("x.com/FERRUM_Yum")
            help:SetMouseInputEnabled(true) --WHY
            help:SetKeyboardInputEnabled(true) --WHY
            help.DoClick = function()
                gui.OpenURL("https://x.com/FERRUM_Yum")
            end
        end

        panel:Help("Alt Belly Model - Fernkarry")
        do
            local help = panel:ControlHelp("x.com/Fernkarry")
            help:SetMouseInputEnabled(true) --WHY
            help:SetKeyboardInputEnabled(true) --WHY
            help.DoClick = function()
                gui.OpenURL("https://x.com/Fernkarry")
            end
        end

         panel:Help("DrGBase - Dragoteryx")  
            do
            local help = panel:ControlHelp("github.com/Dragoteryx")
            help:SetMouseInputEnabled(true) --WHY
            help:SetKeyboardInputEnabled(true) --WHY
            help.DoClick = function()
                gui.OpenURL("https://github.com/Dragoteryx")
            end
        end
        
        panel:Help("Mr. Tucket - 'Classic Alyx' model")
        panel:Help("AlphaWolf77 - 'Female Vortigant' model")
        panel:Help("Workshop Creators - everything else")

        panel:Help("\nAll assets belong to their respective owners")  
    end)

    spawnmenu.AddToolMenuOption("V-NPCs", "Info", "vnpcs_tutorial", "Add more NPCs", "", "", function(panel)
        panel:ClearControls()

        panel:Help("Find NPCs and mods for V-NPCs at...")
        local aryion = panel:Button("Aryion")
        aryion.DoClick = function(arguments)
            gui.OpenURL( "https://aryion.com/forum/viewtopic.php?f=79&t=69727" )
        end

        panel:Help("")
        do
            local button = panel:Button("Video Tutorial")
            button.DoClick = function(arguments)
                gui.OpenURL( "https://www.youtube.com/watch?v=xsBm0jBE22E" )
            end
        end
        panel:Help("Go to Gmod's files in Steam by right clicking on 'Garry's Mod' in your libary and clicking on 'Browse Local Files'")
        addImage(panel, "vnpcs/how2/managefiles.png", true)
        panel:Help("Nagivate to 'garrysmod' and then to 'addons'. Create a new folder in 'garrysmod/addons'")
        panel:ControlHelp("This folder can be called anything\n")
        panel:Help("Create a 'models', 'sound', 'lua', and 'materials' folder. In 'lua' create an 'entities' folder, and in 'materials' create an 'entities' folder. Your folders should look like this.")
        addImage(panel, "vnpcs/how2/filesetup.png", true)
        panel:Help("Insert the files from the mods that you download in their respective folders.")
        panel:ControlHelp("NPC/Belly lua files are placed in 'lua/entities'\n")
        panel:ControlHelp("NPC icons are placed in 'materials/entities' and need to have the same name as the lua file that the npc belongs to.")
        addImage(panel, "vnpcs/how2/iconsfiles.png", true)
        panel:Help("Restart the game for all changes to be enacted. Future changes to anything in the folder will be reloaded with a new game/server.\n")
    end)

    spawnmenu.AddToolMenuOption("V-NPCs", "Info", "vnpcs_tos", "Info", "", "", function(panel)
        panel:ClearControls()

        panel:Help("This mod is only for 18+ audiences only.")
        panel:Help("\n")
        panel:Help("The Mod is unfinished and remains in active development. Features will be incomplete, broken, changed, or removed at any time. All code included in V-NPCs is open source. This Mod is a non-profit project, if you paid to obtain V-NPCs, you were scammed. The only official download locations for V-NPCs are the Steam Workshop and Aryion. The developers do not claim ownership of models and sounds used within V-NPCs. Certain assets belong to their respective owners.")
        panel:Help("")
        do
            local aryion = panel:Button("Aryion Thread")
            aryion.DoClick = function(arguments)
                gui.OpenURL( "https://aryion.com/forum/viewtopic.php?f=79&t=69727" )
            end
        end
        do
            local aryion = panel:Button("Steam Workshop")
            aryion.DoClick = function(arguments)
                steamworks.ViewFile("3607783188")
                --gui.OpenURL( "https://steamcommunity.com/sharedfiles/filedetails/?id=3607783188" )
            end
        end
        panel:Help("If you have created or ported a model that's in V-NPCs and don't want it in. Contact me at @wormmario on Discord to get it removed.")
    end)

    spawnmenu.AddToolMenuOption("V-NPCs", "Info", "vnpcs_tutorial2", "How to make NPCs", "", "", function(panel)
        panel:ClearControls()

        panel:ControlHelp("\nstill a work in progress + vnpcs is still in development so documentation will change regularly")
        panel:Help("")

        local clipboard = panel:Button("NPC Lua Template")
        clipboard.DoClick = function()
            local help = file.Read("entities/npc_vore_template.lua", "LUA" )
            SetClipboardText(help)
            surface.PlaySound( "ambient/water/drip1.wav" )
            surface.PlaySound( "buttons/button15.wav" )

            do_popup(" Copied code to clipboard.\n Create a .txt file in your mod folder in /lua/entities.\n Ctrl + V into that .txt file using Notepad or any text editor.\n Transform that .txt file into a .lua file by changing the extension.", "Copied!")
        end
        panel:ControlHelp("\nBase code that all V-NPCs use, create a lua file using this")

        do
            local button = panel:Button("Basic Tutorial")
            button.DoClick = function(arguments)
                gui.OpenURL( "https://docs.google.com/document/d/1uDq2A_L7iOwEJWP06Sljz23KpGNhAzNz15VNIrWAtzU/edit?tab=t.0" )
            end
            panel:ControlHelp("\nUnkn0wn's tutorial on how to make an NPC.")
        end

        do
            local button = panel:Button("Facial Expressions Tutorial")
            button.DoClick = function(arguments)
                gui.OpenURL( "https://docs.google.com/document/d/1uDq2A_L7iOwEJWP06Sljz23KpGNhAzNz15VNIrWAtzU/edit?tab=t.hrzzrf5l9tu3" )
            end
            panel:ControlHelp("\nUnkn0wn's tutorial for facial expressions, also read about it in the lua template.")
        end

        do
            local button = panel:Button("Weight Gain Tutorial")
            button.DoClick = function(arguments)
                gui.OpenURL( "https://docs.google.com/document/d/1uDq2A_L7iOwEJWP06Sljz23KpGNhAzNz15VNIrWAtzU/edit?tab=t.5ep7u8otbhxk" )
            end
            panel:ControlHelp("\nUnkn0wn's tutorial for weight gain, also read about it in the lua template.")
        end

        do
            local button = panel:Button("Video Tutorial (OUTDATED)")
            button.DoClick = function(arguments)
                gui.OpenURL( "https://youtube.com/watch?v=-A0-dUy3vvM&t" )
            end
            panel:ControlHelp("\nOffical video on how to make an NPC.")

        end
    end)
end

hook.Add("PopulateToolMenu", "VNpcsToolMenu", populate)