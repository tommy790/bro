util.AddNetworkString("UGotVored")
util.AddNetworkString("StopVoreClient")
util.AddNetworkString("VoreNoModNotif")
util.AddNetworkString("refresh_cpanel_makenpc")

hook.Add("PlayerSpawn", "vore_player_spawned", function(ply, trans)
    ply:SetParent(nil)
    ply.Vored = false
        
    net.Start("StopVoreClient")
    net.Send(ply)
end)

hook.Add("PlayerSwitchWeapon", "vore_prevent_weapon", function( ply, oldWeapon, newWeapon )
    if ply.Vored then
       return true 
    end
end)