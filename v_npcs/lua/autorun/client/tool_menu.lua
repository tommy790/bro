
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

        panel:Help("\nBelly RT (Render-Target) Texturing\n")
        panel:CheckBox("Enable Belly RT Textures", "vnpcs_belly_rt_enabled")
        panel:NumSlider("RT Texture Resolution", "vnpcs_belly_rt_size", 128, 1024, 0)
        panel:ControlHelp("Default 512. For large battles, set to 256 for 4x faster rendering.")
        panel:NumSlider("Max Captures / Frame (Idle)", "vnpcs_belly_rt_max_captures", 1, 100, 0)
        panel:NumSlider("Max Captures / Frame (Battle)", "vnpcs_belly_rt_battle_captures", 1, 100, 0)
        panel:ControlHelp("Default 99. Unlimited captures per frame so all bellies texture immediately.")
        do
            local btn_battle = panel:Button("Apply Large Battle Preset")
            btn_battle.DoClick = function()
                RunConsoleCommand("vnpcs_belly_rt_battle_preset")
            end
            panel:ControlHelp("Optimizes RT settings for large NPC battles (Size 256, unlimited captures/frame).\n")
            local btn_default = panel:Button("Restore Default RT Settings")
            btn_default.DoClick = function()
                RunConsoleCommand("vnpcs_belly_rt_default_preset")
            end
            local btn_refresh = panel:Button("Refresh All Belly RT Textures")
            btn_refresh.DoClick = function()
                RunConsoleCommand("vnpcs_belly_rt_refresh")
            end
        end

        panel:Help("\nFemale Model NPCs Vore\n")
        panel:CheckBox("Give Female Model NPCs Vore", "vnpcs_female_model_vore")
        panel:CheckBox("Citizen Preds: Own Species Only If Starving", "vnpcs_citizen_same_species_restrict")
        panel:NumSlider("Citizen Own-Species Hunger", "vnpcs_citizen_same_species_hunger", 50, 100, 0)
        panel:ControlHelp("Female citizen predators will not swallow other citizens/humans unless hunger is at least this high. Other species are always valid prey.")
        panel:NumSlider("Detection Range", "vnpcs_female_model_vore_range", 100, 2000, 0)
        panel:NumSlider("Grab Range", "vnpcs_female_model_vore_grab_range", 20, 300, 0)
        panel:NumSlider("Belly Offset X", "vnpcs_female_model_vore_offset_x", -20, 20, 1)
        panel:NumSlider("Belly Offset Y", "vnpcs_female_model_vore_offset_y", -20, 20, 1)
        panel:NumSlider("Belly Offset Z", "vnpcs_female_model_vore_offset_z", -20, 20, 1)
        panel:CheckBox("Eat Corpses / Ragdolls", "vnpcs_female_model_vore_eat_corpses")
        panel:NumSlider("Ragdoll Scan Range", "vnpcs_female_model_vore_ragdoll_range", 50, 500, 0)
        panel:NumSlider("Regurgitate Damage Threshold", "vnpcs_female_model_vore_regurgitate_dmg", 0.1, 1.0, 2)
        panel:CheckBox("Enable 3D Debug Overlay", "vnpcs_female_model_vore_debug_overlay")
        panel:Help("\nClumped Prey Group Vore\n")
        panel:CheckBox("Enable Clumped Group Vore", "vnpcs_clumped_vore_enabled")
        panel:NumSlider("Clump Search Radius", "vnpcs_clumped_vore_radius", 20, 250, 0)
        panel:NumSlider("Max Group Size", "vnpcs_clumped_vore_max_group", 1, 15, 0)
        panel:CheckBox("Enable Bone-Pose Vore Animations", "vnpcs_bone_pose_animations")
        panel:Help("\nGPU Belly Struggle Mesh\n")
        panel:CheckBox("GPU Belly Mesh", "vnpcs_gpu_belly_mesh")
        panel:CheckBox("GPU Struggle Deforms", "vnpcs_gpu_belly_struggle")
        panel:NumSlider("Struggle Lump Amplitude", "vnpcs_gpu_belly_struggle_amp", 0, 3, 2)
        panel:CheckBox("GPU Gulp Neck Bulge", "vnpcs_gpu_belly_gulp")
        panel:NumSlider("Gulp Bulge Amplitude", "vnpcs_gpu_belly_gulp_amp", 0, 3, 2)
        panel:CheckBox("Torso Hull Mesh", "vnpcs_gpu_belly_torso_hull")
        panel:CheckBox("Belly Jiggle", "vnpcs_gpu_belly_jiggle")
        panel:NumSlider("Jiggle Amplitude", "vnpcs_gpu_belly_jiggle_amp", 0, 3, 2)
        panel:CheckBox("Pregnancy vs Prey Shape", "vnpcs_gpu_belly_preg_shape")
        panel:CheckBox("Hide Belly Entity (GPU Only)", "vnpcs_gpu_belly_hide_entity")
        panel:CheckBox("GPU Belly Debug Overlay", "vnpcs_gpu_belly_debug")
        panel:Help("Gulp is one traveling ridge on the neck/chest. The real belly entity stays visible. Torso Hull and Hide Belly Entity stay off unless you want to replace the belly model.")

        --panel:CheckBox("Do Custom Animations", "drg_animate")
        panel:ControlHelp("")
        panel:ControlHelp("")
    end)

    spawnmenu.AddToolMenuOption("V-NPCs", "Personalization", "vnpcs_personality", "Personality", "", "", function(panel)
        panel:ClearControls()
        panel:Help("Predator and Prey Personality System")
        panel:CheckBox("Enable Personalities", "vnpcs_personalities_enabled")
        panel:Help("\nDefault Personalities (use 'random' to randomize each NPC)")
        panel:TextEntry("Default Predator Personality", "vnpcs_default_predator_personality")
        panel:TextEntry("Default Prey Personality", "vnpcs_default_prey_personality")

        panel:Help("\nPredator Personalities:\n- aggressive: Actively hunts targets (1.5x range, 1.2x grab, 1.2x digestion)\n- opportunistic: Prefers weakened/isolated targets\n- glutton: Indiscriminate eater (1.25x range/grab, 1.5x digestion)\n- shy: Only eats when unobserved by witnesses\n- selective: Only targets direct enemies\n- gentle: Slower digestion (0.6x) and playful behavior")
        panel:Help("\nPrey Personalities:\n- fighter: Struggles vigorously (1.8x struggle)\n- passive: Quiet inside belly (0.5x struggle)\n- panicked: Flees predators, struggles rapidly (1.4x struggle)\n- stubborn: Resistant to digestion (0.6x damage)\n- willing / desire: Actively desires to be swallowed, approaches predators, and does not struggle (0x struggle)")

        panel:Help("\nPrey Mate Attraction\n")
        panel:CheckBox("Enable Mate Attraction", "vnpcs_mate_attraction_enabled")
        panel:NumSlider("Mate Seek Threshold", "vnpcs_mate_attraction_threshold", 0, 100, 0)
        panel:NumSlider("Mate Seek Range", "vnpcs_mate_attraction_range", 200, 2500, 0)
        panel:CheckBox("Show Mate Attraction Overlay", "vnpcs_mate_attraction_debug")
        panel:Help("Prey are attracted to female predator types (citizen, alyx, mossman, combine, vortigaunt, rebel, zombie) and seek those preds to mate. Predators do not have preferred hunt prey types.")

        panel:Help("\nLegacy Forcers\n")
        panel:CheckBox("Hungry for Players", "vnpcspersonality_players")
        panel:CheckBox("Hungry for NPCs", "vnpcspersonality_npcs")
    end)

    spawnmenu.AddToolMenuOption("V-NPCs", "Status & Traits", "vnpcs_trait_settings", "Trait Settings", "", "", function(panel)
        panel:ClearControls()
        panel:Help("Modular Status & Trait System")
        panel:CheckBox("Enable Traits", "vnpcs_traits_enabled")
        panel:NumSlider("Random Trait Chance (per spawn)", "vnpcs_traits_random_chance", 0, 1, 2)
        panel:ControlHelp("Traits modify metabolism (digestion speed), acid resistance, belly capacity, weight/stamina penalties, perception and more. Assign them with the Trait Editor tool or this menu.")
        do
            local btn = panel:Button("Open Trait Editor (Aimed NPC)")
            btn.DoClick = function()
                RunConsoleCommand("vnpcs_trait_menu_open")
            end
        end
    end)

    spawnmenu.AddToolMenuOption("V-NPCs", "Status & Traits", "vnpcs_belly_physics", "Belly Physics & Digestion", "", "", function(panel)
        panel:ClearControls()
        panel:Help("Dynamic Weight Painting & Mesh Deform (bounding-box driven)")
        panel:CheckBox("Enable Belly Weight Slowdown", "vnpcs_belly_physics_enabled")
        panel:NumSlider("Weight Slowdown Master", "vnpcs_belly_weight_slow", 0, 3, 2)
        panel:CheckBox("Weight-Painted Belly Shape", "vnpcs_weight_paint_enabled")
        panel:CheckBox("Per-Prey Lumps", "vnpcs_weight_paint_lumps")
        panel:NumSlider("Lump Amplitude", "vnpcs_weight_paint_amp", 0, 3, 2)
        panel:CheckBox("Asymmetric Bones", "vnpcs_weight_paint_asymmetry")
        panel:ControlHelp("Every prey becomes a measured shape blob (torso/pelvis/head width, model scale). Blobs pack shoulder-to-shoulder into rows to size and shape the belly - no live physics simulation, so it's stable and never freezes or crashes.")
        panel:Help("\\nMax Capacity (Modular Traits)\\n")
        panel:CheckBox("Enforce Belly Capacity", "vnpcs_capacity_enabled")
        panel:NumSlider("Base Capacity (value units)", "vnpcs_capacity_base", 200, 5000, 0)
        panel:ControlHelp("Big Stomach / Small Stomach / Glutton traits raise or lower this per predator.")
        do
            local btn = panel:Button("Belly Weight Status")
            btn.DoClick = function()
                RunConsoleCommand("vnpcs_belly_physics_status")
            end
            local btn2 = panel:Button("Weight Paint / Shape Status")
            btn2.DoClick = function()
                RunConsoleCommand("vnpcs_weight_paint_status")
            end
        end
    end)


    spawnmenu.AddToolMenuOption("V-NPCs", "Status & Traits", "vnpcs_hunter_ai", "Hunter AI", "", "", function(panel)
        panel:ClearControls()
        panel:Help("Smart Nextbot AI & Navigation")
        panel:CheckBox("Enable Hunter AI", "vnpcs_hunter_ai_enabled")
        panel:CheckBox("Noise Tracking", "vnpcs_noise_tracking")
        panel:NumSlider("Noise Base Range", "vnpcs_noise_base_range", 100, 1500, 0)
        panel:CheckBox("Flashlight Tracking", "vnpcs_flashlight_tracking")
        panel:NumSlider("Flashlight Range", "vnpcs_flashlight_range", 200, 2500, 0)
        panel:CheckBox("Ambush & Stalk AI", "vnpcs_ambush_ai")
        panel:CheckBox("Pack Cornering", "vnpcs_pack_cornering")
        panel:CheckBox("Hazard Use (Barrels / Water)", "vnpcs_hazard_use")
        panel:CheckBox("Hunter AI Debug Overlay", "vnpcs_hunter_debug")
        panel:ControlHelp("Predators hear footsteps, spot flashlight beams, stalk from cover, flank as a pack and kick explosive barrels at targets.")
        do
            local btn = panel:Button("Hunter AI Status")
            btn.DoClick = function()
                RunConsoleCommand("vnpcs_hunter_ai_status")
            end
        end
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