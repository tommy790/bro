if SERVER then
    AddCSLuaFile()
end

local convars = {
    {name = "xtwisters3_vortexspeed", default = "20", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_vortexlifetime", default = "400", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_tornadoesstrengthen", default = "true", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_antilag", default = "true", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_antilagtype", default = "1", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_updatetime", default = "0.1", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_lightningintornadoes", default = "true", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_windblockedbyobjects", default = "false", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_windfieldforwardmomentum", default = "false", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_ejectwhenrolling", default = "false", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_vehicleimpactskill", default = "false", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_damagemultiplier", default = "1", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_damageprops", default = "false", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_damagenpcs", default = "false", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_damageplayers", default = "false", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_smarttornadoes", default = "false", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_unweldprops", default = "true", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_unweldmovingprops", default = "false", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_debrisweightmultiplier", default = "1", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_adminspawnonly", default = "true", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_checkvehicleconstraints", default = "false", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_instablewindfield", default = "true", flags = FCVAR_GAMEDLL},
    
    {name = "xtwisters3_enableautospawn", default = "false", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_deletemaptornadoes", default = "false", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_autospawnincludemodapi", default = "true", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_autospawnincludemainapi", default = "true", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_autospawnuserandomtornado", default = "false", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_autospawnmaximumtornadocount", default = "1", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_autospawntornadoprobability", default = "25", flags = FCVAR_GAMEDLL},

    {name = "xtwisters3_glidecompatibility", default = "true", flags = FCVAR_GAMEDLL},

    {name = "xtwisters3_visuallizewindfield", default = "false", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_visuallizewindfieldupdatetime", default = "1", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_visuallizewindfieldgridcount", default = "50", flags = FCVAR_GAMEDLL},
    {name = "xtwisters3_visuallizewindfieldgridheight", default = "1", flags = FCVAR_GAMEDLL},

    {name = "xtwisters3_lightningflashes", default = "true", flags = FCVAR_LUA_CLIENT},
    {name = "xtwisters3_windfieldeffects", default = "false", flags = FCVAR_LUA_CLIENT},
    {name = "xtwisters3_screenshake", default = "true", flags = FCVAR_LUA_CLIENT},
    {name = "xtwisters3_windsounds", default = "true", flags = FCVAR_LUA_CLIENT},
    {name = "xtwisters3_windgusts", default = "true", flags = FCVAR_LUA_CLIENT},
    {name = "xtwisters3_debrisbanging", default = "true", flags = FCVAR_LUA_CLIENT},
    {name = "xtwisters3_audiomuffling", default = "true", flags = FCVAR_LUA_CLIENT},
    {name = "xtwisters3_printhints", default = "false", flags = FCVAR_LUA_CLIENT},
    {name = "xtwisters3_hideskyboxfix", default = "false", flags = FCVAR_LUA_CLIENT},
}

cvars.AddChangeCallback("xtwisters3_hideskyboxfix", function(ConvarName, ValueOld, ValueNew)
    if GetConVar("xtwisters3_hideskyboxfix"):GetBool() then
        RunConsoleCommand("r_3dsky", "0")
    else
        RunConsoleCommand("r_3dsky", "1")
    end
end)

for _, convar in ipairs(convars) do
    if not ConVarExists(convar.name) then
        CreateConVar(convar.name, convar.default, bit.bor(FCVAR_ARCHIVE, (convar.flags) or 0), "XTwisters 3 Convars")
    end
end

function XT3GetConvars()
    return convars
end