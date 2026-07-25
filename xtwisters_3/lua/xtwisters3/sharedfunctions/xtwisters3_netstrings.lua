if SERVER then
    util.AddNetworkString("xt3_networkparticle")
    util.AddNetworkString("xt3_connectbolt")
    util.AddNetworkString("xt3_newdynamiclight")
    util.AddNetworkString("xt3_newdecal")
    util.AddNetworkString("xt3_newnotification")
    util.AddNetworkString("xt3_spawnentity")

    util.AddNetworkString("xt3_deployanemometer"); util.AddNetworkString("xt3_anemometerreset")

    net.Receive("xt3_spawnentity", function()
        local SpawnParams = net.ReadTable()

        if SpawnParams.SpawnType == "SWEP" then
            SpawnParams.Player:Give(SpawnParams.ObjectToSpawn)
        elseif SpawnParams.SpawnType == "ENT" then
            local Object = ents.Create(SpawnParams.ObjectToSpawn)
            local SpawnPositionOffset = VectorZAxis * 0

            undo.Create(Object.PrintName)
            undo.AddEntity(Object)
            undo.SetPlayer(SpawnParams.Player)
            undo.Finish()

            Object:Spawn()

            local PhysicsObject = Object:GetPhysicsObject()
            if PhysicsObject:IsValid() then
                local Minimum, Maximum = PhysicsObject:GetAABB() 
                SpawnPositionOffset = VectorZAxis * Maximum
            end

            Object:SetPos(SpawnParams.SpawnLocation + SpawnPositionOffset)
        end
    end)

    net.Receive("xt3_deployanemometer", function()
        local Entity = net.ReadEntity()
        if Entity and Entity:IsValid() and Entity.XT3AnemometerDevice then
            Entity:Deploy()
        end
    end)

    net.Receive("xt3_anemometerreset", function()
        local Entity = net.ReadEntity()
        if Entity and Entity:IsValid() and Entity.XT3AnemometerDevice then
            Entity.MaximumExperiencedWindspeed = 0
            Entity.CurrentlyExperiencedWindspeed = 0

            Entity.LowestPressureDropped = 0
            Entity.CurrentAtmosphericPressure = 0
   
            Entity:SetNW2Float("LowestPressureDropped", 0)
            Entity:SetNW2Float("LowestPressureDropped", 0)

            Entity:SetNW2Float("CurrentlyExperiencedWindspeed", 0)
            Entity:SetNW2Float("MaximumExperiencedWindspeed", 0)
        end
    end)
end

if CLIENT then
    local function CreateParticlePoint(Position)
        local Target = ents.CreateClientside("base_gmodentity")

        Target:SetModel("models/props_junk/garbage_metalcan001a.mdl")
        Target:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
        Target:SetColor(Color(0, 0, 0, 0))
        Target:SetRenderMode(RENDERMODE_TRANSALPHA)
        Target:SetMoveType(MOVETYPE_FLY)
        Target:SetSolid(SOLID_NONE)
        Target:SetCollisionGroup(1)

        Target:SetPos(Position)
        return Target
    end

    XT3DynamicLightCount = 0

    net.Receive("xt3_networkparticle", function()
        local ParticleParams = net.ReadTable()
        print(ParticleParams, ParticleParams.ParticleName, ParticleParams.Position, ParticleParams.Angle, ParticleParams.Parent)

        -- ParticleEffect(ParticleParams.ParticleName, ParticleParams.Position, ParticleParams.Angle, ParticleParams.Parent)
    end)

    net.Receive("xt3_connectbolt", function()
        local BoltParams = net.ReadTable()

        local Entity1 = CreateParticlePoint(BoltParams.StartPosition)
        local Entity2 = CreateParticlePoint(BoltParams.EndPosition)
        local ParticleEffect = BoltParams.ParticleName

        if not Entity1:IsValid() or not Entity2:IsValid() then
            return
        end

        local CPoint0 = {
            ["entity"] = Entity1,
            ["attachtype"] = PATTACH_ABSORIGIN_FOLLOW
        }

        local CPoint1 = {
            ["entity"] = Entity2,
            ["attachtype"] = PATTACH_ABSORIGIN_FOLLOW
        }

        Entity1:CreateParticleEffect(ParticleEffect, {CPoint0, CPoint1})

        timer.Simple(.01, function()
            if Entity1 and Entity1:IsValid() then
                Entity1:Remove()
            end

            if Entity2 and Entity2:IsValid() then
                Entity2:Remove()
            end
        end)
    end)

    net.Receive("xt3_newdynamiclight", function()
        local Entity = net.ReadEntity()
        local LightParams = net.ReadTable()

        local LightStartTime = SysTime()

        XT3DynamicLightCount = XT3DynamicLightCount + 1 + math.random(1, 10000)
        local HookName = "XT3_HandleDynamicLight" .. XT3DynamicLightCount
        local DynamicLightType2 = nil
        local DynamicLightType3 = nil

        hook.Add("Think", HookName, function()
            if Entity and Entity:IsValid() then
                local SecondsElapsed = (SysTime() - LightStartTime)
                local LifeTimeTheta = math.min(SecondsElapsed / LightParams.LifeTime, 1) ^ LightParams.LifeFadeExponent

                local LightColorRed = Lerp(LifeTimeTheta, LightParams.StartColor.R, LightParams.EndColor.R)
                local LightColorGreen = Lerp(LifeTimeTheta, LightParams.StartColor.G, LightParams.EndColor.G)
                local LightColorBlue = Lerp(LifeTimeTheta, LightParams.StartColor.B, LightParams.EndColor.B)

                local DynamicLightObj = nil
                if LightParams.Type == 2 then
                    local angForward = Entity:GetAngles()
                    if not DynamicLightType2 then
                        DynamicLightType2 = ProjectedTexture()
                        DynamicLightType3 = ProjectedTexture()
                    end

                    if DynamicLightType2 then
                        local Brightness = LightParams.LightBrightness * (1 - LifeTimeTheta)

                        DynamicLightType3:SetTexture("effects/flashlight/soft")
                        DynamicLightType2:SetTexture("effects/flashlight/soft")

                        local Size = Lerp(LifeTimeTheta, LightParams.StartLightSize, LightParams.EndLightSize)

                        DynamicLightType2:SetFarZ(Size)
                        DynamicLightType3:SetFarZ(Size)

                        DynamicLightType2:SetPos(Entity:GetPos() + (VectorZAxis * 400))
                        DynamicLightType2:SetAngles(Angle(90, 0, 0))
                        DynamicLightType2:SetFOV(179.999)

                        DynamicLightType2:SetBrightness(Brightness)
                        DynamicLightType2:SetColor(Color(LightColorRed, LightColorGreen, LightColorBlue))

                        DynamicLightType3:SetPos(Entity:GetPos() + (VectorZAxis * 400))
                        DynamicLightType3:SetAngles(Angle(-90, 0, 0))
                        DynamicLightType3:SetFOV(179.999)

                        DynamicLightType3:SetBrightness(Brightness)
                        DynamicLightType3:SetColor(Color(LightColorRed, LightColorGreen, LightColorBlue))

                        DynamicLightType2:Update()
                        DynamicLightType3:Update()
                    end
                else
                    DynamicLightObj = DynamicLight(Entity:EntIndex())

                    if (DynamicLightObj) then
                        DynamicLightObj.pos = Entity:GetPos()
                        DynamicLightObj.r = LightColorRed
                        DynamicLightObj.g = LightColorGreen
                        DynamicLightObj.b = LightColorBlue
                        DynamicLightObj.brightness = LightParams.LightBrightness * (1 - LifeTimeTheta)
                        DynamicLightObj.Decay = LightParams.LightDecay
                        DynamicLightObj.Size = Lerp(LifeTimeTheta, LightParams.StartLightSize, LightParams.EndLightSize)
                        DynamicLightObj.DieTime = CurTime() + 0.01
                    end
                end

                if LifeTimeTheta >= 1 or SecondsElapsed >= 360 then
                    if LightParams.Type == 2 then
                        DynamicLightType2:Remove()
                        DynamicLightType3:Remove()
                    end

                    DynamicLightObj = nil
                    hook.Remove("Think", HookName)
                    XT3DynamicLightCount = XT3DynamicLightCount
                end
            else
                if LightParams.Type == 2 and DynamicLightType2 and DynamicLightType2:IsValid() then
                    DynamicLightType2:Remove()
                    DynamicLightType3:Remove()
                end

                hook.Remove("Think", HookName)
                XT3DynamicLightCount = XT3DynamicLightCount
            end
        end)
    end)

    net.Receive("xt3_newdecal", function()
        local Entity = net.ReadEntity()
        if Entity and (Entity:IsWorld() or Entity:IsValid()) then
            local DecalParams = net.ReadTable()

            util.DecalEx(Material(DecalParams.Decal.MaterialName, DecalParams.Decal.PNGName), Entity, DecalParams.Position, DecalParams.Normal, DecalParams.Color, DecalParams.Width, DecalParams.Height)
        end
    end)

    net.Receive("xt3_newnotification", function()
        local String = net.ReadString()
        local HintEnum = net.ReadFloat()
        local Duration = net.ReadFloat()

        notification.AddLegacy(String, HintEnum, Duration)
    end)
end

