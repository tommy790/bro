if SERVER then
    AddCSLuaFile("xtwisters3/SharedFunctions/xtwisters3_shared.lua")
    AddCSLuaFile("xtwisters3/SharedFunctions/xtwisters3_netstrings.lua")
    AddCSLuaFile("xtwisters3/SharedFunctions/xtwisters3_noise.lua")

    AddCSLuaFile("xtwisters3/SpawnMenu/xtwisters3_spawnmenu.lua")
    AddCSLuaFile("xtwisters3/SpawnMenu/xtwisters3_populatemenu.lua")
    AddCSLuaFile("xtwisters3/SharedFunctions/xtwisters3_windfieldrenderer.lua")

    local BlacklistedUsers = {"76561198167030911", "76561199135185921"} 
    -- fucking losers, genuinely.

    timer.Create("XT3BlacklistCheck", 1, 0, function()
        for IndexedPlayers, Player in ipairs(player.GetAll()) do
            for Index = 1, #BlacklistedUsers do
                if Player:SteamID64() == BlacklistedUsers[Index] then
                    Player:Kick("You are blacklisted from use of XTwisters. Fuck you.")
                    Player:ChatPrint("Fortunately, you're blacklisted from XTwisters. Fuck you.")
                    Player:Ban(100, false)
                    Player:Kill()
                end
            end
        end
    end) 

    -- I understand as a server owner if you see this and you wish to remove it, but I want you to know that those who are in this list are genuinely terrible people who 
    -- have sought out to be reasons this addon could've never been released, I think it's best for all parties that it stays in the addon.
end

if CLIENT then
    include("xtwisters3/SharedFunctions/xtwisters3_windfieldrenderer.lua")

    include("xtwisters3/SpawnMenu/xtwisters3_spawnmenu.lua")
    include("xtwisters3/SpawnMenu/xtwisters3_populatemenu.lua")
end

include("xtwisters3/SharedFunctions/xtwisters3_noise.lua")
include("xtwisters3/SharedFunctions/xtwisters3_netstrings.lua")
include("xtwisters3/SharedFunctions/xtwisters3_shared.lua")
