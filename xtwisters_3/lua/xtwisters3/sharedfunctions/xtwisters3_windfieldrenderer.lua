AddCSLuaFile()

local function UpdateNWValues(ENT)
    if CLIENT then
        local VortexWindspeed = ENT:GetNWInt("XT3VortexWindspeed", 1)
        local VortexCoreSize = ENT:GetNWInt("XT3VortexSize", 1)
        local VortexSwirlRatio = ENT:GetNWInt("XT3VortexSwirlRatio", 1)
        local VortexWindfieldFallOff = ENT:GetNWInt("XT3VortexWindfieldFallOff", 1)
        local VortexMovementDirection = ENT:GetNWVector("XT3VortexMovementDirection", Vector(0, 0, 0))
        return VortexWindspeed, VortexCoreSize, VortexSwirlRatio, VortexWindfieldFallOff, VortexMovementDirection
    end
end

if CLIENT then

    local gridPosOffset = 10 -- Height of the grid positions (offset on the Z axis)
    local RenderWindfield = true

    local function Lerp(a, b, t)
        if type(a) == "number" and type(b) == "number" then
            return a + (b - a) * t

        elseif istable(a) and istable(b) and a.r and b.r then
            return Color(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
        end
    end

    local function InverseLerp(v, a, b)
        local value = (v - a) / (b - a)
        value = math.Clamp(value, 0, 1)
        return value
    end

    local velocityColors = {{
        windspeed = 0,
        color = Color(231, 235, 243)
    }, {
        windspeed = 30,
        color = Color(148, 170, 222)
    }, {
        windspeed = 60,
        color = Color(34, 90, 222)
    }, {
        windspeed = 75,
        color = Color(65, 220, 255)
    }, {
        windspeed = 85,
        color = Color(1, 230, 85)
    }, {
        windspeed = 120,
        color = Color(255, 238, 0)
    }, {
        windspeed = 135,
        color = Color(255, 136, 0)
    }, {
        windspeed = 145,
        color = Color(255, 106, 0)
    }, {
        windspeed = 175,
        color = Color(200, 0, 3)
    }, {
        windspeed = 190,
        color = Color(202, 0, 114)
    }, {
        windspeed = 210,
        color = Color(109, 38, 153)
    }, {
        windspeed = 235,
        color = Color(78, 42, 156)
    }, {
        windspeed = 250,
        color = Color(39, 4, 156)
    }, {
        windspeed = 280,
        color = Color(35, 35, 47)
    }, {
        windspeed = 300,
        color = Color(0, 0, 0)
    }, {
        windspeed = 767,
        color = Color(255, 255, 255)
    }}

    local function ReturnListOfGridPositions(resolution, tornadoPosition, gridSize)
        local squareSize = gridSize / resolution
        local halfGridSize = gridSize / 2
        local squareOffset = squareSize / 2
        local listOfPositions = {}
        for i = 0, resolution - 1 do
            local xBase = tornadoPosition.x - halfGridSize + (i * squareSize) + squareOffset
            for j = 0, resolution - 1 do
                local y = tornadoPosition.y - halfGridSize + (j * squareSize) + squareOffset
                local key = string.format("%f_%f", xBase, y)
                listOfPositions[key] = Vector(xBase, y, tornadoPosition.z + gridPosOffset)
            end
        end
        return listOfPositions, squareSize, true
    end

    local function getVelocityWindspeeds(windspeed)
        local windspeeds = {}
        local lowerValue, upperValue = false, false

        if math.abs(windspeed) > math.abs(velocityColors[#velocityColors].windspeed) then
            repeat
                windspeed = -windspeed + (math.abs(velocityColors[#velocityColors].windspeed) * math.Clamp(windspeed, -1, 1))
            until math.abs(windspeed) <= math.abs(velocityColors[#velocityColors].windspeed)
        end

        for i, v in ipairs(velocityColors) do
            table.insert(windspeeds, {
                colorWindspeed = v.windspeed,
                index = i
            })
        end

        for i = 1, #windspeeds do
            windspeeds[i].nearestValue = math.abs(windspeed - windspeeds[i].colorWindspeed)
        end

        table.sort(windspeeds, function(a, b)
            return a.nearestValue < b.nearestValue
        end)

        local limits = {}

        for i = 1, #windspeeds do
            if windspeeds[i].colorWindspeed <= windspeed and not lowerValue then
                lowerValue = true
                table.insert(limits, windspeeds[i])
            elseif windspeeds[i].colorWindspeed > windspeed and not upperValue then
                upperValue = true
                table.insert(limits, windspeeds[i])
            end
        end

        table.sort(limits, function(a, b)
            return a.colorWindspeed < b.colorWindspeed
        end)

        return limits
    end

    local function GetColorForWindspeed(windspeed)
        local colorWindspeeds = getVelocityWindspeeds(windspeed)
        local color

        if #colorWindspeeds > 1 then
            local value = InverseLerp(windspeed, velocityColors[colorWindspeeds[1].index].windspeed, velocityColors[colorWindspeeds[2].index].windspeed)
            color = Lerp(velocityColors[colorWindspeeds[1].index].color, velocityColors[colorWindspeeds[2].index].color, value)
        else
            color = velocityColors[colorWindspeeds[1].index].color
        end

        return color
    end

    local windspeed

    local modelName = "models/hunter/plates/plate4x4.mdl"

    function XT3RenderWindfield(tornado, gridSize, plyRequested, RenderWindfield)

        if plyRequested.LastRenderResolution and gridSize ~= plyRequested.LastRenderResolution or RenderWindfield == false then
            if tornado.gridProps then
                for _, prop in pairs(tornado.gridProps) do
                    if IsValid(prop) then
                        prop:Remove()
                    end
                end
            end
        end

        if RenderWindfield == false then
            return
        end

        plyRequested.LastRenderResolution = gridSize

        local Completed = false -- Spazzes without this so pls keep

        if tornado.gridProps then
            for _, prop in pairs(tornado.gridProps) do
                if IsValid(prop) then
                    prop:Remove()
                end
            end
            Completed = true
        end

        if not Completed and tornado.gridProps then
            return
        end

        local ClientWindspeed, ClientCoreSize, ClientSwirlRatio, ClientWindfieldFallOff, ClientMovementDirection = UpdateNWValues(tornado)
        local WindfieldData = {
            VortexCenter = tornado:GetPos(),
            VortexWindspeed = ClientWindspeed,
            VortexCoreSize = ClientCoreSize,
            VortexSwirlRatio = ClientSwirlRatio,
            VortexWindfieldFallOff = ClientWindfieldFallOff,
            VortexForceMultipliers = {
                Radial = 1,
                Axial = 1,
                Tangential = 1
            },
            VortexMovementVector = (ClientMovementDirection)
        }

        local tempGridSize = math.max(ReturnWindfieldRadius(tornado, 60, WindfieldData) * 2, WindfieldData.VortexCoreSize * 4) -- * math.pi

        local gridPositionTable, squareSize, waitForPositions = ReturnListOfGridPositions(gridSize, tornado:GetPos() + VectorZAxis*GetConVar("xtwisters3_visuallizewindfieldgridheight"):GetFloat(), tempGridSize)

        if waitForPositions then
            tornado.gridProps = tornado.gridProps or {}

            local activeKeys = {}

            for key, gridPos in pairs(gridPositionTable) do

                local WindVelocity, Windspeed, WindfieldMultiplier, PressureData = GetTornadoWindspeed(self, gridPos, WindfieldData)
            
                local color = GetColorForWindspeed(Windspeed)

                if color and Windspeed >= 0 then
                    activeKeys[key] = true
                    if not tornado.gridProps[key] then
                        local prop = ClientsideModel(modelName)
                        if prop and prop:IsValid() then
                            local scale = squareSize / 188
                            local minBound, maxBound = Vector(-scale, -scale, -scale), Vector(scale, scale, scale)
                            prop:SetRenderBounds(minBound, maxBound)
                            prop:SetModelScale(scale, 0)
                            prop:SetPos(gridPos)
                            prop:SetColor(color)
                            prop:SetMaterial("models/debug/debugwhite")
                            prop:SetCollisionGroup(COLLISION_GROUP_NONE)
                            prop:DrawShadow(false)
                            prop:SetNoDraw(false)
                            prop:SetParent(tornado)

                            tornado.gridProps[key] = prop
                        end
                    end
                end
            end

            for key, prop in pairs(tornado.gridProps) do
                if not activeKeys[key] and prop:IsValid() then
                    prop:SetNoDraw(true)
                    prop:Remove()
                    tornado.gridProps[key] = nil
                end
            end
        else
            return false
        end
    end

    return true
end
