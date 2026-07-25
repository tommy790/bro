if SERVER then
    AddCSLuaFile()
end

function XT3AddCollapsibleSection(parent, title, expanded, buildFn)

    local category = vgui.Create("DCollapsibleCategory", parent)

    category:SetLabel(title)
    category:SetExpanded(expanded)

    parent:AddItem(category)

    local form = vgui.Create("DForm", category)

    form:SetName("")
    form:SetSpacing(6)
    form:SetPadding(6)
    form:SetPaintBackground(false)

    if form.SetPaintBorderEnabled then form:SetPaintBorderEnabled(false) end

    form.Paint = function() end

    if form.Header then
        form.Header:SetVisible(false)
        form.Header:SetTall(0)
    end

    category:SetContents(form)

    local before, seen = form:GetChildren() or {}, {}

    for _, ch in ipairs(before) do 
		seen[ch] = true 
	end

    buildFn(form)

    local created = {}

    for _, ch in ipairs(form:GetChildren() or {}) do
        if not seen[ch] then table.insert(created, ch) end
    end

    return form, category, created

end

hook.Add("AddToolMenuCategories", "XTwisters3loadMenu", function()
    spawnmenu.AddToolTab("XTwisters3", "XTwisters3", "materials/SpawnMenuIcons/XT3Icon.png", 50)
    spawnmenu.AddToolCategory("XTwisters3", "XTwisters3", "#XTwisters3 Settings")
end)

hook.Add("PopulateToolMenu", "XTwisters3MenuLoad", function()

    spawnmenu.AddToolMenuOption("XTwisters3", "XTwisters3", "XTwisters3CustomMenu1", "#XTwisters3 General Options", "", "", function(panel)

        panel:CheckBox("Admins can only spawn XT3 entities", "xtwisters3_adminspawnonly"):SetTooltip("Multiplayer only, when enabled allows only those with admin to spawn entities.")

        XT3AddCollapsibleSection(panel, "[ Tornado Configuration ]", true, function(option)
            option:Help("(DEFAULT: 400.0)")

            option:NumSlider("Spawned Tornado Lifetime.", "xtwisters3_vortexlifetime", 5, 1000, 0):SetTooltip("Tornadoes delete after this time elapses.")

            option:Help("(DEFAULT: 20.0)")

            option:NumSlider("Spawned Tornado Speed in MPH.", "xtwisters3_vortexspeed", 0, 100, 1):SetTooltip("General vortex forward speed, some vortices might move slower.")

            option:CheckBox("Tornadoes aim towards spawn location.", "xtwisters3_smarttornadoes"):SetTooltip("Spiritual Successor to GDisasters Smart Tornadoes, targets the location of where the tornado spawned and spawns the tornado elsewhere.")

            option:CheckBox("Tornadoes strengthen on spawn.", "xtwisters3_tornadoesstrengthen"):SetTooltip("When enabled, tornadoes will gradually strengthen and widen (per particle basis).")

            option:CheckBox("Lighting spawns around tornadoes.", "xtwisters3_lightningintornadoes"):SetTooltip("Lightning will spawn around the tornado and cause fire and damage upon impacts, creating another threat to avoid.")
        end)

        XT3AddCollapsibleSection(panel, "[ Autospawn Configuration ]", true, function(option)
            option:CheckBox("Enable Autospawn", "xtwisters3_enableautospawn"):SetTooltip("When enabled, tornadoes will randomly spawn. Good for chasing and whatnots.")

            option:Help("(DEFAULT: 25.0)")
            option:Help("Every autospawn tick is 10 seconds, so below is the chance per 10 seconds.")

            option:NumSlider("Autospawn Tornado Probability", "xtwisters3_autospawntornadoprobability", 1, 300, 0):SetTooltip("1 in X chance for a tornado to spawn every autospawn tick.")
            option:NumSlider("Maximum ongoing tornadoes", "xtwisters3_autospawnmaximumtornadocount", 1, 10, 0):SetTooltip("Maximum ongoing tornado count.")
            
            option:Help(" ")
            option:CheckBox("Autospawn gives tornadoes random windspeeds", "xtwisters3_autospawnuserandomtornado"):SetTooltip("The autospawn will randomly choose a windspeed and particle to make the experience more unpredictable.")
            option:CheckBox("Autospawn includes mod API added tornadoes", "xtwisters3_autospawnincludemodapi"):SetTooltip("Includes all the XT3 mod api tornadoes in the autospawn")
            option:CheckBox("Autospawn includes main XT3 tornadoes", "xtwisters3_autospawnincludemainapi"):SetTooltip("only works when disabled if the above is enabled")
            option:Help(" ")

            option:CheckBox("Delete map tornadoes", "xtwisters3_deletemaptornadoes"):SetTooltip("To restore the map tornadoes you have to tick this off and clean the map, might also delete map trains.")

            option:Help(" Still work in progress, I plan on adding more options later down the line. ")
        end)
    end)

    spawnmenu.AddToolMenuOption("XTwisters3", "XTwisters3", "XTwisters3CustomMenu2", "#XTwisters3 Simulation Options", "", "", function(panel)

        XT3AddCollapsibleSection(panel, "[ Antilag Settings ]", true, function(option)
            option:Help(" Antilag worsens the quality of simulation for a (theortically) higher framerate.")

            option:CheckBox("Antilag", "xtwisters3_antilag")
            option:NumSlider("Antilag Type", "xtwisters3_antilagtype", 1, 2, 0):SetTooltip("Higher antilag modes decrease the scanning radius of vortices.")
            option:NumSlider("Tornado Update Time", "xtwisters3_updatetime", 0.1, 1, 3):SetTooltip("Higher update times will result in worse visuals but significantly better performance.")
        end)

        XT3AddCollapsibleSection(panel, "[ Tornado Debris/Damage Settings ]", true, function(option)
            option:CheckBox("Wind unwelds props", "xtwisters3_unweldprops"):SetTooltip("Higher update times will result in worse visuals but significantly better performance.")
            option:CheckBox("Wind unwelds props regardless of it's flying/dynamic", "xtwisters3_unweldmovingprops"):SetTooltip("Usually tornadoes only damage objects if they're frozen, this will damage them regardless of that.")

            option:Help(" ")
            option:NumSlider("Wind damage multiplier", "xtwisters3_damagemultiplier", 0, 1000, 0):SetTooltip("When damage props is enabled, this can be used to make the damage stronger or weaker.")
            option:CheckBox("Wind damages Props", "xtwisters3_damageprops"):SetTooltip("Wind damages props based on the windspeed, higher winds will do higher damage.")
            option:CheckBox("Wind damages NPCs", "xtwisters3_damagenpcs"):SetTooltip("Wind damage will include NPCs. Good for ragdoll moments.")
            option:CheckBox("Wind damages Players", "xtwisters3_damageplayers"):SetTooltip("Wind damage will include Players. Good for if you want tornadoes to be a threat beyond fall damage.")

            option:NumSlider("Debris weight Multiplier", "xtwisters3_debrisweightmultiplier", 0.1, 5, 3):SetTooltip("Higher values make debris heavier, lower makes debris lighter.")
        end)
        
        XT3AddCollapsibleSection(panel, "[ Gameplay Settings ]", true, function(option)
            option:CheckBox("Vehicle Rolling ejects Players", "xtwisters3_ejectwhenrolling"):SetTooltip("If the tornado rolls the vehicle at a extreme ")
            option:CheckBox("Vehicle Impacts kill Players", "xtwisters3_vehicleimpactskill"):SetTooltip("If the tornado throws player at a high enough velocity into the ground, damage will be dealt.")
        end)

        XT3AddCollapsibleSection(panel, "[ Experimental Settings ]", true, function(option)
            option:Help("These options can cause preformance issues or general inconsistency.")

            option:CheckBox("Instable windfield", "xtwisters3_instablewindfield"):SetTooltip("Adds a noise algorithm to the windfield to simulate windfield gusts.")
            option:CheckBox("Wind Blocked by Objects", "xtwisters3_windblockedbyobjects"):SetTooltip("Can be performance heavy, preforms traces to see if the wind can make impact.")
            option:CheckBox("Windfields Account for Forward Momentum", "xtwisters3_windfieldforwardmomentum"):SetTooltip("Adds an extra calculation to simulate the windfield being effected by translation")

            option:Help("This is EXTREMELY EXPENSIVE on heavily detailed dupes/constrained entities")
            option:CheckBox("Windfields check for entities attached to vehicles", "xtwisters3_checkvehicleconstraints"):SetTooltip("Seriously if you spawn like any building dupes you might kill your game.")
        
            XT3AddCollapsibleSection(option, "[ Debug Visuallizers ]", false, function(option2)
                option2:Help("These options will and can definitely just kill your PC and performance, they're not meant to run well.")
               
                option2:CheckBox("Windfield visuallization", "xtwisters3_visuallizewindfield"):SetTooltip("Makes a grid of pixels that show in EF adjacent how strong the vortex is.")
               
                option2:NumSlider("Windfield update time", "xtwisters3_visuallizewindfieldupdatetime", .1, 2, 1):SetTooltip("Lower updates time increases debug fidelity but decreases performance")
                option2:NumSlider("Windfield grid resolution", "xtwisters3_visuallizewindfieldgridcount", 15, 50, 0):SetTooltip("The windfield grid resolution in pixels")
                option2:NumSlider("Windfield grid height", "xtwisters3_visuallizewindfieldgridheight", 1, 5000, 0):SetTooltip("The upwards axis relative to the tornado's local position")
            end)

            XT3AddCollapsibleSection(option, "[ Addon Compatibility ]", false, function(option2)
                option2:Help("These options at the possible cost of performance will allow other addons to work in tandem with XT3.")

                option2:CheckBox("Glide Compatibility", "xtwisters3_glidecompatibility"):SetTooltip("Adds an extra expensive calculation just so you can have glide function, glide sucks.")
            end)
        end)

    end)

    spawnmenu.AddToolMenuOption("XTwisters3", "XTwisters3", "XTwisters3CustomMenu3", "#XTwisters3 Client Options", "", "", function(panel)
        panel:CheckBox("Print hints", "xtwisters3_printhints", 0, 1, 0):SetTooltip("Shows information about the tornado(s) you spawn.")
        panel:CheckBox("Particles in 3D skybox fix", "xtwisters3_hideskyboxfix", 0, 1, 0):SetTooltip("There's really only one way to solve this issue, it's to hide the skybox.")
        
        XT3AddCollapsibleSection(panel, "[ Tornado/Weather FX Settings ]", true, function(option)
            option:CheckBox("Screenshake", "xtwisters3_screenshake", 0, 1, 0):SetTooltip("Higher winds mean higher screenshake.")
            option:CheckBox("Windfield Effects", "xtwisters3_windfieldeffects", 0, 1, 0):SetTooltip("Spawns some (basic) particles depending on windspeed around your player.")

            option:CheckBox("Audio when in high winds.", "xtwisters3_windsounds", 0, 1, 0):SetTooltip("Based on the windspeeds you experience audio plays that progressively gets more intense as the windspeeds increase.")
            option:CheckBox("Windgust audio when in high winds.", "xtwisters3_windgusts", 0, 1, 0):SetTooltip("Adds some sound variation just to spice it up a little. Mimics wind coming in gusts around you.")
            option:CheckBox("Debris banging audio when in high winds.", "xtwisters3_debrisbanging", 0, 1, 0):SetTooltip("Adds some sound variation just to spice it up a little. Mimics debris being thrown around you.")
        end)

        XT3AddCollapsibleSection(panel, "[ Experimental Settings ]", true, function(option)
            option:Help("These options can cause preformance issues or general inconsistency.")

            option:CheckBox("Audio muffling when in buildings", "xtwisters3_audiomuffling", 0, 1, 0):SetTooltip("Somewhat janky, needs more refinement, small small chances of (unconfirmable) crashes possibly?")
            option:CheckBox("Lightning emits flashes", "xtwisters3_lightningflashes"):SetTooltip("Can definitely be laggy, uses a more expensive light creation script to have long range flashes.")
        end)
    end)

end)
