if SERVER then
    AddCSLuaFile()

    XT3AutospawnEntities = {}

    function XT3AddAutospawnEntities(list)
        for k, v in ipairs(list) do
            if not table.HasValue(XT3AutospawnEntities, v) then
                table.insert(XT3AutospawnEntities, v)
            end
        end
    end

    function XT3RemoveAutospawnEntities(list)
        for k, v in ipairs(list) do
            if table.HasValue(XT3AutospawnEntities, v) then
                table.remove(XT3AutospawnEntities, k)
            end
        end
    end

    local BaseXT3AutospawnList = {
        {EntityClass = "XT3_Tornadoes_EF0", ProbabilityPercentage = 100};
        {EntityClass = "XT3_Tornadoes_EF1", ProbabilityPercentage = 85};
        {EntityClass = "XT3_Tornadoes_EF2", ProbabilityPercentage = 70};
        {EntityClass = "XT3_Tornadoes_EF3", ProbabilityPercentage = 45};
        {EntityClass = "XT3_Tornadoes_EF4", ProbabilityPercentage = 25};
        {EntityClass = "XT3_Tornadoes_EF5", ProbabilityPercentage = 10};
    }

    local BaseWindspeed = {
        {Windspeed = {45, 85}, ProbabilityPercentage = 100};
        {EntityClass = {86, 110}, ProbabilityPercentage = 85};
        {EntityClass = {111, 135}, ProbabilityPercentage = 70};
        {EntityClass = {136, 165}, ProbabilityPercentage = 45};
        {EntityClass = {165, 200}, ProbabilityPercentage = 25};
        {EntityClass = {200, 235}, ProbabilityPercentage = 10};
        {EntityClass = {236, 250}, ProbabilityPercentage = 5};
        {EntityClass = {251, 300}, ProbabilityPercentage = .5};
        {EntityClass = {301, 350}, ProbabilityPercentage = .1};
        {EntityClass = {351, 400}, ProbabilityPercentage = .01};
        {EntityClass = {401, 500}, ProbabilityPercentage = .001};
    }

    local function SelectAutospawnTornado(TableItems)
        local TotalWeight = 0

        for Index, TableData in pairs(TableItems) do
            TotalWeight = TotalWeight + TableData.ProbabilityPercentage
        end

        local Chance = math.random() * TotalWeight
        local AbsoluteCounter = 0

        for Index, TableData in pairs(TableItems) do
            AbsoluteCounter = AbsoluteCounter + TableData.ProbabilityPercentage
            if Chance <= AbsoluteCounter then
                return TableData.EntityClass
            end
        end

        return TableItems[#TableItems].EntityClass
    end

    XT3AddAutospawnEntities(BaseXT3AutospawnList)
    cvars.AddChangeCallback("xtwisters3_autospawnuserandomtornado", function(ConvarName, ValueOld, ValueNew)
        local XT3RandomList = {{EntityClass = "xt3_tornadoes_randomtornado", ProbabilityPercentage = 100};}
        if ValueNew == 1 then
            XT3RemoveAutospawnEntities(BaseXT3AutospawnList)
            XT3AddAutospawnEntities(XT3RandomList)
        else
            XT3RemoveAutospawnEntities(XT3RandomList)
            XT3AddAutospawnEntities(BaseXT3AutospawnList)
        end
    end)

    cvars.AddChangeCallback("xtwisters3_autospawnincludemainapi", function(ConvarName, ValueOld, ValueNew)
        if ValueNew == 1 then
            XT3AddAutospawnEntities(BaseXT3AutospawnList)
        else
            XT3RemoveAutospawnEntities(BaseXT3AutospawnList)
        end
    end)

    cvars.AddChangeCallback("xtwisters3_deletemaptornadoes", function(ConvarName, ValueOld, ValueNew)
        if GetConVar("xtwisters3_deletemaptornadoes"):GetBool() then
            for Index, Tornado in pairs(ents.FindByClass("func_tracktrain", "func_tanktrain")) do
                Tornado:Remove()
            end
        end
    end)

    local function GetAutospawnTable()
        local ChosenAutospawnTable = {}

        if GetConVar("xtwisters3_autospawnincludemodapi"):GetBool() then
            ChosenAutospawnTable = XT3AutospawnEntities
        else
            if GetConVar("xtwisters3_autospawnuserandomtornado"):GetBool() then
                local XT3RandomList = {{EntityClass = "xt3_tornadoes_randomtornado", ProbabilityPercentage = 100};}
                ChosenAutospawnTable = XT3RandomList 
            else
                ChosenAutospawnTable = BaseXT3AutospawnList     
            end
        end

        return ChosenAutospawnTable
    end
    
    local LastThink = CurTime()
    local function AutospawnLoop()

        if CurTime() - LastThink > 10 then
            if GetConVar("xtwisters3_deletemaptornadoes"):GetBool() then
                for Index, Tornado in pairs(ents.FindByClass("func_tracktrain", "func_tanktrain")) do
                    Tornado:Remove()
                end
            end

            LastThink = CurTime()

            if GetConVar("xtwisters3_enableautospawn"):GetBool() then
                local OnGoingTornadoes = #ents.FindByClass("xt3_tornadoes*")
                local CanSpawnTornado = true;
                if OnGoingTornadoes >= GetConVar("xtwisters3_autospawnmaximumtornadocount"):GetFloat() then
                    CanSpawnTornado = false; -- print("yeah don't spawn it")
                end

                if CanSpawnTornado and (GetConVar("xtwisters3_autospawntornadoprobability"):GetFloat() == 1 or math.random(1, GetConVar("xtwisters3_autospawntornadoprobability"):GetFloat()) == 1) then
                    -- print("Tornado Forming")

                    local ChosenTornado = SelectAutospawnTornado(GetAutospawnTable())
                    local DontAllowSpawn, ChosenPosition = XT3GetPositionInRadius(VectorZAxis, 30000, 500)
                    if not DontAllowSpawn then
                        local TornadoToSpawn = ents.Create(ChosenTornado)
                        if GetConVar("xtwisters3_autospawnuserandomtornado"):GetBool() then
                            local WindspeedRange = SelectAutospawnTornado(BaseWindspeed) or {65, 85}
                            TornadoToSpawn.VortexWindspeed = Lerp(math.random()^2, WindspeedRange[1], WindspeedRange[2])
                        end

                        TornadoToSpawn:SetPos(ChosenPosition)
                        TornadoToSpawn:Spawn()
                    end
                else
                    -- print("Tried to tornado, failed.")
                end
            end
        end
    end

    hook.Add("Think", "XT3AutospawnStartLoop", AutospawnLoop)
end
