AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"

ENT.VortexWindspeed = 1
ENT.VortexCoreSize = 10
ENT.VortexSwirlRatio = 1
ENT.VortexWindfieldFallOff = 1

ENT.IsTornadic = true
ENT.CustomFunctionality = false
ENT.MovementSpeedMultiplier = 1

ENT.MovementHeightGoal = 0
ENT.MovementSpeed = 0
ENT.MovementDirection = Vector(0, 0, 0)
ENT.PhysicsDelay = CurTime()

local function UpdateNWValues(ENT)
    if SERVER then
        ENT:SetNWInt("XT3VortexWindspeed", ENT.VortexWindspeed)
        ENT:SetNWInt("XT3VortexSize", ENT.VortexCoreSize)
        ENT:SetNWInt("XT3VortexSwirlRatio", ENT.VortexSwirlRatio)
        ENT:SetNWInt("XT3VortexWindfieldFallOff", ENT.VortexWindfieldFallOff)
        ENT:SetNWVector("XT3VortexMovementDirection", ENT.MovementDirection * ENT.MovementSpeed)
    elseif CLIENT then
        local VortexWindspeed = ENT:GetNWInt("XT3VortexWindspeed", 1)
        local VortexCoreSize = ENT:GetNWInt("XT3VortexSize", 1)
        local VortexSwirlRatio = ENT:GetNWInt("XT3VortexSwirlRatio", 1)
        local VortexWindfieldFallOff = ENT:GetNWInt("XT3VortexWindfieldFallOff", 1)
        local VortexMovementDirection = ENT:GetNWVector("XT3VortexMovementDirection", Vector(0, 0, 0))
        return VortexWindspeed, VortexCoreSize, VortexSwirlRatio, VortexWindfieldFallOff, VortexMovementDirection
    end
end

function ENT:CalculateMovement()
    self.MovementSpeed = GetConVar("xtwisters3_vortexspeed"):GetFloat() * self.MovementSpeedMultiplier

    if self.SmartPathing then

        if not self.SmartInfluenceTime then
            self.SmartInfluenceTime = CurTime()
            local Filter, SpawnPos, Radius = self, self:GetPos(), (self.VortexCoreSize * 5 + 20000)

            local SmartSpawnPosition = SpawnPos + (Vector(SuperRandom(-1, 1), SuperRandom(-1, 1), 0) * Radius) + Vector(0, 0, 100)
            local DontAllowSpawn = false

            if not util.IsInWorld(SmartSpawnPosition) then
                local NewPositionFound = false
                local MaxCount = 0

                repeat
                    MaxCount = MaxCount + 1
                    SmartSpawnPosition = SpawnPos + (Vector(SuperRandom(-1, 1), SuperRandom(-1, 1), 0) * Radius) + Vector(0, 0, 100)

                    if util.IsInWorld(SmartSpawnPosition) then
                        NewPositionFound = true
                    end

                    if MaxCount >= 500 then
                        MaxCount = 0
                        DontAllowSpawn = true
                    end
                until NewPositionFound or DontAllowSpawn
            end

            if not DontAllowSpawn then
                local FindSky = util.TraceLine({
                    start = SmartSpawnPosition,
                    endpos = SmartSpawnPosition + Vector(0, 0, 100000),
                    mask = MASK_NPCWORLDSTATIC,
                    filter = Filter
                })

                local ConnectToGround = util.TraceLine({
                    start = FindSky.HitPos - Vector(0, 0, 10),
                    endpos = FindSky.HitPos - Vector(0, 0, 100000),
                    mask = MASK_WATER + MASK_SOLID,
                    filter = Filter
                })

                self.MovementHeightGoal = ConnectToGround.HitPos[3]

                self:SetPos(ConnectToGround.HitPos + (VectorZAxis * self.MovementHeightGoal))
            end

            self.SmartTarget = SpawnPos
        end

        local NoTargetTime = 1
        if GetConVar("xtwisters3_tornadoesstrengthen"):GetBool() then
            NoTargetTime = math.max(self.VortexStrengthenParameters.SizeFadeEnd * 0.825, self.VortexStrengthenParameters.WindspeedFadeEnd * 0.825)
        end

        local SmartDirInfluence = Lerp(math.max((CurTime() - self.SmartInfluenceTime) - NoTargetTime, 0) / 150 * (perlinNoise1D(CurTime() / 10) + 0.5), 0, 0.001)

        local VortexPosition = self:GetPos()
        local GoalVortexPosition = (VortexPosition * Vector(1, 1, 0)) + (VectorZAxis * self.MovementHeightGoal)

        local Speed = (self.MovementSpeed * 23.472 * FrameTime())

        local NoiseSize = 300
        local DeviateTime = CurTime() / Lerp(perlinNoise3D(VortexPosition[1] / NoiseSize, CurTime(), VortexPosition[2] / NoiseSize) + 0.5, 3, 30)
        local DeviationOffset = Vector(math.cos(DeviateTime), math.sin(DeviateTime), 0) * Lerp(perlinNoise3D(VortexPosition[1] / NoiseSize, CurTime() + 10000, VortexPosition[2] / NoiseSize) + 0.35, 0.075, 0.0005)

        local SmartNormallized = (self.SmartTarget - VortexPosition) * Vector(1, 1, 0)
        local SmartDirection = SmartNormallized
        local SmartDistance = SmartNormallized:Length()

        self.MovementDirection = ((Lerp(SmartDirInfluence, self.MovementDirection + DeviationOffset, SmartDirection)) * Vector(1, 1, 0)):GetNormalized()

        local RoofCheck = util.TraceLine({
            start = GoalVortexPosition + Vector(0, 0, 1000),
            endpos = GoalVortexPosition + Vector(0, 0, 100000),
            mask = MASK_NPCWORLDSTATIC, -- MASK_WATER + MASK_SOLID_BRUSHONLY,
            filter = self
        })

        if RoofCheck then
            local HeightCheck = util.TraceLine({
                start = RoofCheck.HitPos,
                endpos = RoofCheck.HitPos - Vector(0, 0, 100000),
                mask = MASK_WATER + MASK_SOLID_BRUSHONLY,
                filter = self
            })

            local WallCheck = util.TraceLine({
                start = GoalVortexPosition + Vector(0, 0, 1000),
                endpos = GoalVortexPosition + Vector(0, 0, 1000) + (self.MovementDirection * math.max(Speed, self.VortexCoreSize * 0.65)),
                mask = MASK_WATER + MASK_SOLID_BRUSHONLY,
                filter = self
            })

            if WallCheck.Hit then
                self.MovementDirection = (self.MovementDirection - (2 * self.MovementDirection:Dot(WallCheck.HitNormal) * WallCheck.HitNormal) + ((Vector(0, 0, 0) - VortexPosition):GetNormalized() * SuperRandom(1, 0))):GetNormalized()
            end

            if HeightCheck.Hit then
                self.MovementHeightGoal = HeightCheck.HitPos.Z + 10
                HeightCheck.HitPos = (HeightCheck.HitPos * Vector(1, 1, 0)) + (VectorZAxis * VortexPosition.Z)
                VortexPosition = (HeightCheck.HitPos + self.MovementDirection * Speed)
            else
                self.MovementHeightGoal = VortexPosition.Z
                VortexPosition = VortexPosition + (self.MovementDirection * Speed)
            end

            local HeightCorrectedPosition = (VortexPosition * Vector(1, 1, 0)) + (VectorZAxis * Lerp(FrameTime() * 2, VortexPosition.Z, self.MovementHeightGoal))
            self:SetPos(HeightCorrectedPosition)

            if not self:IsInWorld() then
                -- self.MovementDirection = (Vector(SuperRandom(-1000, 1000), SuperRandom(-1000, 1000), 0) - VortexPosition):GetNormalized()
                -- XT3PrintError("The tornado is in the world! You may have to turn down the tornado's speed or find a better map.", 5)
            end
        end

        if SmartDistance < self.VortexCoreSize * 2 and (CurTime() - NoTargetTime) > NoTargetTime then
            self.SmartPathing = false
        end

    else
        local VortexPosition = self:GetPos()
        local GoalVortexPosition = (VortexPosition * Vector(1, 1, 0)) + (VectorZAxis * self.MovementHeightGoal)

        local Speed = (self.MovementSpeed * 23.472 * FrameTime())

        local NoiseSize = 300
        local DeviateTime = CurTime() / Lerp(perlinNoise3D(VortexPosition[1] / NoiseSize, CurTime(), VortexPosition[2] / NoiseSize) + 0.5, 3, 30)
        local DeviationOffset = Vector(math.cos(DeviateTime), math.sin(DeviateTime), 0) * Lerp(perlinNoise3D(VortexPosition[1] / NoiseSize, CurTime() + 10000, VortexPosition[2] / NoiseSize) + 0.35, 0.075, 0.0005)

        self.MovementDirection = ((self.MovementDirection + DeviationOffset) * Vector(1, 1, 0)):GetNormalized()

        local RoofCheck = util.TraceLine({
            start = GoalVortexPosition + Vector(0, 0, 1000),
            endpos = GoalVortexPosition + Vector(0, 0, 100000),
            mask = MASK_NPCWORLDSTATIC, -- MASK_WATER + MASK_SOLID_BRUSHONLY,
            filter = self
        })

        if RoofCheck then
            local HeightCheck = util.TraceLine({
                start = RoofCheck.HitPos,
                endpos = RoofCheck.HitPos - Vector(0, 0, 100000),
                mask = MASK_WATER + MASK_SOLID_BRUSHONLY,
                filter = self
            })

            local WallCheck = util.TraceLine({
                start = GoalVortexPosition + Vector(0, 0, 1000),
                endpos = GoalVortexPosition + Vector(0, 0, 1000) + (self.MovementDirection * math.max(Speed, self.VortexCoreSize * 0.65)),
                mask = MASK_WATER + MASK_SOLID_BRUSHONLY,
                filter = self
            })

            if WallCheck.Hit then
                self.MovementDirection = (self.MovementDirection - (2 * self.MovementDirection:Dot(WallCheck.HitNormal) * WallCheck.HitNormal) + ((Vector(0, 0, 0) - VortexPosition):GetNormalized() * SuperRandom(1, 0))):GetNormalized()
            end

            if HeightCheck.Hit then
                self.MovementHeightGoal = HeightCheck.HitPos.Z + 10
                HeightCheck.HitPos = (HeightCheck.HitPos * Vector(1, 1, 0)) + (VectorZAxis * VortexPosition.Z)

                VortexPosition = (HeightCheck.HitPos + self.MovementDirection * Speed)
            else
                self.MovementHeightGoal = VortexPosition.Z
                VortexPosition = VortexPosition + (self.MovementDirection * Speed)
            end

            local HeightCorrectedPosition = (VortexPosition * Vector(1, 1, 0)) + (VectorZAxis * Lerp(FrameTime() * 2, VortexPosition.Z, self.MovementHeightGoal))
            self:SetPos(HeightCorrectedPosition)

            if not self:IsInWorld() then
                -- self.MovementDirection = (Vector(SuperRandom(-1000, 1000), SuperRandom(-1000, 1000), 0) - VortexPosition):GetNormalized()
                -- XT3PrintError("The tornado is in the world! You may have to turn down the tornado's speed or find a better map.", 5)
            end
        end
    end
end

function ENT:Think()
    if self.CustomFunctionality then
        self:CustomFunction()
    end

    local ClientWindspeed, ClientCoreSize, ClientSwirlRatio, ClientWindfieldFallOff, ClientMovementDirection = UpdateNWValues(self)
    if SERVER then
        self:CalculateMovement()

        local PhysicsDelayTime
        local SeekWindspeed

        local TimeElapsed = (CurTime() - self.CreationTime)
        --print(math.Round(TimeElapsed*100)/100)

        if GetConVar("xtwisters3_tornadoesstrengthen"):GetBool() and not self.FinishedStrengthening and self.CanStrengthen then
            local WindspeedFadeStart = self.VortexStrengthenParameters.WindspeedFadeStart or 0
            local WindspeedFadeEnd = self.VortexStrengthenParameters.WindspeedFadeEnd or 0

            local SizeFadeStart = self.VortexStrengthenParameters.SizeFadeStart or 0
            local SizeFadeEnd = self.VortexStrengthenParameters.SizeFadeEnd or 0

            local SizeStart = self.VortexStrengthenParameters.VortexStartSize

            local WindspeedTheta = InverseLerp(TimeElapsed, WindspeedFadeStart, WindspeedFadeEnd) ^ 0.4
            local SizeTheta = InverseLerp(TimeElapsed, SizeFadeStart, SizeFadeEnd)

            local DeathFade = 1 - InverseLerp(TimeElapsed, self.VortexLifetime/1.125, self.VortexLifetime)
            self.VortexWindspeed = self.GoalWindspeed * WindspeedTheta * DeathFade
            self.VortexCoreSize = Lerp(SizeTheta, SizeStart, self.GoalCoreSize)
            -- print(self.VortexWindspeed)

            if WindspeedTheta >= 1 and SizeTheta >= 1 then
                self.FinishedStrengthening = true
            end
        end

        if GetConVar("xtwisters3_antilag"):GetBool() then
            local AntilagType = GetConVar("xtwisters3_antilagtype"):GetInt() or 1

            if not AntilagType then
                SeekWindspeed = 1
            else
                if AntilagType == 2 then
                    SeekWindspeed = math.min(65, math.max(math.Round(self.VortexWindspeed * 0.55), 1))
                elseif AntilagType <= 1 then
                    SeekWindspeed = math.min(30, math.max(math.Round(self.VortexWindspeed * 0.35), 1))
                end
            end
        else
            -- PhysicsDelayTime = 0.1
            SeekWindspeed = 1
        end

        PhysicsDelayTime = GetConVar("xtwisters3_updatetime"):GetFloat()

        local AntilagBoost = PhysicsDelayTime / 0.1
        local Entities = ents.FindInSphere(self:GetPos() + Vector(0, 0, 1), ReturnWindfieldRadius(self, SeekWindspeed))

        local function ValidityCheck(Entity)
            if Entity:IsValid() and Entity ~= self and Entity:GetClass() ~= "gmod_ghost" and Entity:GetClass() ~= "sent_anim" and not Entity:IsWorld() and not Entity:IsWeapon() and not Entity:IsNPC() and not Entity:IsPlayer() and not Entity:IsVehicle() and not Entity:IsRagdoll() and not Entity.XT3DoNotApplyPhysics and not XT3CheckIfEntityConnectedToVehicle(Entity) then
                return true
            end
        end

        local VortexPosition = self:GetPos()
        local Direction = self.MovementDirection
        local Speed = self.MovementSpeed

        if CurTime() - self.PhysicsDelay >= PhysicsDelayTime then
            self.PhysicsDelay = CurTime()

            for Index = 1, #Entities do
                local Entity = Entities[Index]

                if ValidityCheck(Entity) then
                    local PhysObject = Entity:GetPhysicsObject()

                    local Trace, WindTunnelMultiplier, LiftMultiplier = false, 1, 1
                    if GetConVar("xtwisters3_windblockedbyobjects"):GetBool() then
                        Trace, WindTunnelMultiplier, LiftMultiplier = TraceCheckWalls(Entity, self)
                    end

                    if PhysObject:IsValid() and not Trace then
                        local WindVelocity, Windspeed, WindfieldMultiplier = GetTornadoWindspeed(self, Entity:GetPos())

                        if GetConVar("xtwisters3_windblockedbyobjects"):GetBool() then
                            WindVelocity = Vector(WindVelocity[1] * WindTunnelMultiplier, WindVelocity[2] * WindTunnelMultiplier, WindVelocity[3] * LiftMultiplier)
                        end

                        if not GetConVar("xtwisters3_windfieldforwardmomentum"):GetBool() then
                            WindVelocity = WindVelocity + (Direction * self.MovementSpeed * 23.472 * FrameTime() * math.pi * WindfieldMultiplier)
                        end

                        local ForceMultiplier = 1
                        local CanDamage = true

                        local WindspeedExponent = math.min((Windspeed ^ 2) / 10000, 1)
                        ForceMultiplier = ForceMultiplier * WindspeedExponent * AntilagBoost

                        if PhysObject:IsMotionEnabled() then
                            local MaxWeight = math.max(1 - (PhysObject:GetMass() * GetConVar("xtwisters3_debrisweightmultiplier"):GetFloat()) / (Windspeed ^ 2 * 3), 0)
                            PhysObject:SetDamping(1.25 * WindspeedExponent, 0)
                            PhysObject:SetDragCoefficient(1 * WindspeedExponent)
                            PhysObject:ApplyForceCenter(WindVelocity * 50 * math.max((math.min(PhysObject:GetMass(), 5000) * (1 / GetConVar("xtwisters3_debrisweightmultiplier"):GetFloat())) / 12, 1) * MaxWeight * ForceMultiplier)
                            PhysObject:AddAngleVelocity(WindVelocity * 0.5 * MaxWeight * ForceMultiplier)
                        elseif GetConVar("xtwisters3_unweldprops"):GetBool() then
                            local WindResistance = 50 * (PhysObject:GetMass() / 10000)
                            local BreakChance = Lerp(InverseLerp(Windspeed, 50, 170 + WindResistance) ^ 0.045, 2700 + (6000 * (1 - WindspeedExponent ^ 0.25)), 1)
                            BreakChance = BreakChance * Lerp(InverseLerp(Windspeed, 20, 60), 1000, 1)

                            if not PhysObject:IsMotionEnabled() and math.random(1, BreakChance) == 1 then
                                PhysObject:Wake()
                                PhysObject:EnableMotion(true)
                            end
                        end

                        if GetConVar("xtwisters3_unweldprops"):GetBool() then
                            if (constraint.HasConstraints(Entity)) then
                                local Destructible = PhysObject:IsMotionEnabled()

                                if GetConVar("xtwisters3_unweldmovingprops"):GetBool() then
                                    Destructible = false
                                end

                                local WindResistance = 50 * (PhysObject:GetMass() / 10000)
                                local BreakChance = Lerp(InverseLerp(Windspeed, 40, 170 + WindResistance) ^ 0.045, 2700 + (6000 * (1 - WindspeedExponent ^ 0.25)), 1) / AntilagBoost
                                BreakChance = BreakChance * Lerp(InverseLerp(Windspeed, 20, 60), 1000, 1)
                                if (math.random(1, BreakChance)) == 1 and not Destructible then
                                    Entity:EmitSound("PropDamage/break" .. math.random(1, 16) .. ".wav", SuperRandom(50, 130))
                                    constraint.RemoveAll(Entity)

                                    if not PhysObject:IsMotionEnabled() then
                                        PhysObject:Wake()
                                        PhysObject:EnableMotion(true)
                                    end
                                end
                            end
                        end

                        if GetConVar("xtwisters3_damageprops"):GetBool() and CanDamage then
                            local Damage = math.max(20 * ((Windspeed - 60) / 350), 0) * AntilagBoost
                            XT3CauseDamage(self, self, Entity, Damage * GetConVar("xtwisters3_damagemultiplier"):GetFloat(), DMG_SLASH)
                        end

                    end
                end
            end
        end

        local ClientEntities = XT3RetrievePlayerEntities(true, true)

        for Index = 1, #ClientEntities do
            local Entity = ClientEntities[Index]
            local PhysObject = Entity:GetPhysicsObject()
            if PhysObject:IsValid() then
                if (Entity:IsPlayer() or Entity:IsNPC()) then
                    local Trace, WindTunnelMultiplier, LiftMultiplier = TraceCheckWalls(Entity, self)
                    if PhysObject:IsValid() and Entity:GetMoveType() ~= MOVETYPE_NOCLIP and not (Entity:IsPlayer() and Entity:InVehicle()) and not Trace then
                        local WindVelocity, Windspeed, WindfieldMultiplier = GetTornadoWindspeed(self, Entity:GetPos())

                        WindVelocity = Vector(WindVelocity[1] * WindTunnelMultiplier, WindVelocity[2] * WindTunnelMultiplier, WindVelocity[3] * LiftMultiplier)
                        Windspeed = Windspeed * WindTunnelMultiplier

                        local ForceMultiplier = 1

                        if GetConVar("xtwisters3_damagenpcs"):GetBool() and Entity:IsNPC() then
                            local Damage = 5 * math.max((Windspeed - 60) / 350, 0)
                            XT3CauseDamage(self, self, Entity, Damage * GetConVar("xtwisters3_damagemultiplier"):GetFloat(), DMG_SLASH)
                        elseif GetConVar("xtwisters3_damageplayers"):GetBool() and Entity:IsPlayer() then
                            local Damage = 1 * math.max((Windspeed - 60) / 350, 0)
                            XT3CauseDamage(self, self, Entity, Damage * GetConVar("xtwisters3_damagemultiplier"):GetFloat(), DMG_SLASH)
                        end

                        if Entity:OnGround() then
                            if Entity:IsNPC() then
                                ForceMultiplier = 2
                            else
                                WindVelocity = Vector(WindVelocity[1], WindVelocity[2], WindVelocity[3] * 8)
                                ForceMultiplier = 2

                                if Entity:Crouching() then
                                    ForceMultiplier = 0.7
                                end
                            end
                        else
                            if Entity:IsNPC() then
                                ForceMultiplier = 0.5
                            else
                                WindVelocity = Vector(WindVelocity[1], WindVelocity[2], WindVelocity[3] * 2)
                                ForceMultiplier = 0.2
                            end
                        end

                        ForceMultiplier = ForceMultiplier * InverseLerp(Windspeed, 30, 150) ^ 2

                        if Entity.AddVelocity then
                            Entity:AddVelocity(WindVelocity * ForceMultiplier)
                        else
                            Entity:SetVelocity(WindVelocity * ForceMultiplier)
                        end
                    end
                elseif (Entity:IsVehicle() or Entity.XT3SensesIsVehicle) then
                    local Trace, WindTunnelMultiplier, LiftMultiplier = TraceCheckWalls(Entity, self)
                    if PhysObject:IsMotionEnabled() and not Trace then
                        local WindVelocity, Windspeed, WindfieldMultiplier = GetTornadoWindspeed(self, Entity:GetPos())
                        local ForceMultiplier = 0.65
                        WindVelocity = Vector(WindVelocity[1] * WindTunnelMultiplier, WindVelocity[2] * WindTunnelMultiplier, WindVelocity[3] * LiftMultiplier)

                        if not GetConVar("xtwisters3_windfieldforwardmomentum"):GetBool() then
                            WindVelocity = WindVelocity + (Direction * self.MovementSpeed * 23.472 * FrameTime())
                        end

                        local MaxWeight = math.max(1 - PhysObject:GetMass() / (Windspeed ^ 2 * 3) , 0)

                        local WindspeedExponent = math.min((Windspeed ^ 2) / 25000, 1) ^ 2
                        local WindspeedExponent2 = math.min((Windspeed ^ 2) / 25000, 1) ^ 0.5
                        ForceMultiplier = MaxWeight * ForceMultiplier * WindspeedExponent

                        local RollDirection = WindVelocity * Vector(1, 1, 0)

                        PhysObject:AddVelocity(WindVelocity * ForceMultiplier)
                        PhysObject:AddAngleVelocity(RollDirection * ForceMultiplier * WindspeedExponent *.5)

                        if math.random(0, 130) == 1 and Windspeed >= 60 and GetConVar("xtwisters3_debrisbanging"):GetBool() then
                            Entity:EmitSound("physics/metal/metal_barrel_impact_hard" .. math.random(1, 3) .. ".wav", 75, 100, 0.35)
                        end

                        local VehicleIsGrounded = false

                        local GroundedCheck = util.TraceLine({
                            start = Entity:GetPos(),
                            endpos = Entity:GetPos() - (Entity:GetUp() * 30),
                            filter = XT3GetEntityAndChildern(Entity)
                        })

                        if GroundedCheck.Hit then
                            VehicleIsGrounded = true
                        end

                        if GetConVar("xtwisters3_vehicleimpactskill"):GetBool() then
                            if Entity.LastVelocityXT3 then
                                local NewVelocity = PhysObject:GetVelocity():Length()
                                local VelocityDifference = math.max(Entity.LastVelocityXT3 - math.min(NewVelocity, Entity.LastVelocityXT3), 0)

                                if Windspeed > 60 and not GroundedCheck.Hit then
                                    Entity.ThrownByTornadoXT3 = true
                                end

                                if VelocityDifference > 50 and Entity.ThrownByTornadoXT3 and not Entity:IsPlayerHolding() then
                                    local Players = player.GetAll()
                                    for Index = 1, #Players do
                                        local ply = Players[Index]
                                        if ply:InVehicle() and ply:GetVehicle() == Entity then
                                            local DamageTypes = 0
                                            
                                            DamageTypes = bit.bor(DamageTypes, 128) 
                                            DamageTypes = bit.bor(DamageTypes, 16)

                                            XT3CauseDamage(self, self, Entity, VelocityDifference * 0.08, DamageTypes)

                                            if VelocityDifference * 0.08 > 90 and GetConVar("xtwisters3_ejectwhenrolling"):GetBool() then
                                                ply:ExitVehicle()
                                            end
                                        end
                                    end

                                    if CurTime() - Entity.LastCrashSoundXT3 > 0.075 then
                                        Entity.LastCrashSoundXT3 = CurTime()

                                        if VelocityDifference > 600 then
                                            Entity:EmitSound("vehicles/v8/vehicle_impact_heavy" .. math.random(1, 4) .. ".wav", 75, 100, 1)
                                            Entity:EmitSound("vehicles/v8/vehicle_rollover" .. math.random(1, 2) .. ".wav", 75, 100, 1)
                                        elseif VelocityDifference > 250 then
                                            Entity:EmitSound("vehicles/v8/vehicle_impact_heavy" .. math.random(1, 4) .. ".wav", 75, 100, 1)
                                        else
                                            Entity:EmitSound("physics/metal/metal_barrel_impact_hard" .. math.random(1, 3) .. ".wav", 75, 100, 0.35)
                                        end
                                    end

                                    if GroundedCheck then
                                        timer.Simple(4, function()
                                            if Entity and Entity:IsValid() and Windspeed < 60 then
                                                Entity.ThrownByTornadoXT3 = false
                                            end
                                        end)
                                    end
                                end

                                Entity.LastVelocityXT3 = NewVelocity
                            else
                                Entity.ThrownByTornadoXT3 = false
                                Entity.LastVelocityXT3 = PhysObject:GetVelocity():Length()
                                Entity.LastCrashSoundXT3 = 0
                            end
                        end

                        if GetConVar("xtwisters3_ejectwhenrolling"):GetBool() then
                            local vehicleVelocity = PhysObject:GetAngleVelocity():Length()
                            if vehicleVelocity > 1000 then
                                local Players = player.GetAll()
                                for Index = 1, #Players do
                                    local ply = Players[Index]
                                    if ply:InVehicle() and ply:GetVehicle() == Entity then
                                        ply:ExitVehicle()
                                        XT3CauseDamage(self, self, ply, SuperRandom(10, 40), DMG_CLUB)
                                    end
                                end
                            end
                        end
                    end
                elseif Entity:IsRagdoll() then
                    local Trace, WindTunnelMultiplier, LiftMultiplier = TraceCheckWalls(Entity, self)
                    if PhysObject:IsMotionEnabled() and not Trace then
                        local WindVelocity, Windspeed, WindfieldMultiplier = GetTornadoWindspeed(self, Entity:GetPos())

                        WindVelocity = Vector(WindVelocity[1] * WindTunnelMultiplier, WindVelocity[2] * WindTunnelMultiplier, WindVelocity[3] * LiftMultiplier)
                        Windspeed = Windspeed * WindTunnelMultiplier

                        if not GetConVar("xtwisters3_windfieldforwardmomentum"):GetBool() then
                            WindVelocity = WindVelocity + (Direction * self.MovementSpeed * 23.472 * FrameTime() * WindfieldMultiplier)
                        end

                        local ForceMultiplier = 1

                        if Entity:IsRagdoll() then
                            CanDamage = false
                            ForceMultiplier = 3
                            if Entity:OnGround() then
                                ForceMultiplier = 1.75
                            end
                        end

                        local WindspeedExponent = math.min((Windspeed ^ 2) / 10000, 1)
                        ForceMultiplier = ForceMultiplier * WindspeedExponent * 0.5

                        if PhysObject:IsMotionEnabled() then
                            local MaxWeight = math.max(1 - (PhysObject:GetMass() * GetConVar("xtwisters3_debrisweightmultiplier"):GetFloat()) / (Windspeed ^ 2 * 3), 0)

                            WindVelocity = WindVelocity * FrameTime() * 23.472 / 2
                            PhysObject:ApplyForceCenter(WindVelocity * 50 * math.max((math.min(PhysObject:GetMass(), 5000) * (1 / GetConVar("xtwisters3_debrisweightmultiplier"):GetFloat())) / 12, 1) * MaxWeight * ForceMultiplier)
                            PhysObject:AddAngleVelocity(WindVelocity * 0.5 * MaxWeight * ForceMultiplier)
                        end
                    end
                end
            end
        end

        for Index, Player in ipairs(player.GetAll()) do

            if Player:IsValid() then
                PrecacheParticleSystem("XT3WindfieldVisuals_200MPH_V1")
                PrecacheParticleSystem("XT3WindfieldVisuals_170MPH_V1")
                PrecacheParticleSystem("XT3WindfieldVisuals_140MPH_V1")
                PrecacheParticleSystem("XT3WindfieldVisuals_110MPH_V1")
                PrecacheParticleSystem("XT3WindfieldVisuals_80MPH_V1")
                PrecacheParticleSystem("XT3WindfieldVisuals_50MPH_V1")
            end

        end

    elseif CLIENT then
        if not (gui.IsGameUIVisible() and game.SinglePlayer()) then
            local Players = player.GetAll()
            for Index = 1, #Players do
                local Entity = Players[Index]
                if Entity == LocalPlayer() then
                    local WindfieldData = {
                        VortexCenter = self:GetPos(),
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

                    local WindVelocity, Windspeed, WindfieldMultiplier = GetTornadoWindspeed(self, Entity:GetPos(), WindfieldData)
                    local Trace, WindTunnelMultiplier, LiftMultiplier = TraceCheckWalls(Entity, self, 5000)

                    local PlayerPosition = Entity:GetPos()

                    if GetConVar("xtwisters3_windfieldeffects"):GetBool() then
                        local TornadoCenterPositionX = self:GetPos()[1]
                        local TornadoCenterPositionZ = self:GetPos()[2]

                        local PlayerPositionX = PlayerPosition[1]
                        local PlayerPositionZ = PlayerPosition[2]

                        local WindAngle = math.deg(math.atan2(TornadoCenterPositionZ - PlayerPositionZ, TornadoCenterPositionX - PlayerPositionX))
                        local ParticlePosition = PlayerPosition - (VectorZAxis * 0)
                        local ParticleAngle = Angle(0, WindAngle, 0)
                       
                        if Windspeed >= 200 then
                            if math.random()^2 >= Lerp(InverseLerp(Windspeed, 200, 230)^0.4, 1, 0) then
                                ParticleEffect("XT3WindfieldVisuals_200MPH_V1", ParticlePosition, ParticleAngle, Entity)
                            else
                                ParticleEffect("XT3WindfieldVisuals_170MPH_V1", ParticlePosition, ParticleAngle, Entity)
                            end
                        elseif Windspeed >= 170 then
                            if math.random()^2 >= Lerp(InverseLerp(Windspeed, 170, 200)^0.4, 1, 0) then
                                ParticleEffect("XT3WindfieldVisuals_170MPH_V1", ParticlePosition, ParticleAngle, Entity)
                            else
                                ParticleEffect("XT3WindfieldVisuals_140MPH_V1", ParticlePosition, ParticleAngle, Entity)
                            end
                        elseif Windspeed >= 140 then
                            if math.random()^2 >= Lerp(InverseLerp(Windspeed, 140, 170)^0.4, 1, 0) then
                                ParticleEffect("XT3WindfieldVisuals_140MPH_V1", ParticlePosition, ParticleAngle, Entity)
                            else
                                ParticleEffect("XT3WindfieldVisuals_110MPH_V1", ParticlePosition, ParticleAngle, Entity)
                            end
                        elseif Windspeed >= 110 then
                            if math.random()^2 >= Lerp(InverseLerp(Windspeed, 110, 140)^0.4, 1, 0) then
                                ParticleEffect("XT3WindfieldVisuals_110MPH_V1", ParticlePosition, ParticleAngle, Entity)
                            else
                                ParticleEffect("XT3WindfieldVisuals_80MPH_V1", ParticlePosition, ParticleAngle, Entity)
                            end
                        elseif Windspeed >= 80 then
                            if math.random()^2 >= Lerp(InverseLerp(Windspeed, 80, 110)^0.4, 1, 0) then
                                ParticleEffect("XT3WindfieldVisuals_80MPH_V1", ParticlePosition, ParticleAngle, Entity)
                            else
                                ParticleEffect("XT3WindfieldVisuals_50MPH_V1", ParticlePosition, ParticleAngle, Entity)
                            end
                        elseif Windspeed >= 30 and math.random()^2 > Lerp(InverseLerp(Windspeed, 30, 80)^0.4, 1, 0) then
                            ParticleEffect("XT3WindfieldVisuals_50MPH_V1", ParticlePosition, ParticleAngle, Entity)
                        end
                    end

                    if CurTime() - self.CreationTime >= 0.1 then
                        self.RenderUpdateDelay = self.RenderUpdateDelay or CurTime()
                        if CurTime() - self.RenderUpdateDelay >= GetConVar("xtwisters3_visuallizewindfieldupdatetime"):GetFloat() and self.CompletedWindfieldRendering ~= false then
                            self.CompletedWindfieldRendering = XT3RenderWindfield(self, GetConVar("xtwisters3_visuallizewindfieldgridcount"):GetInt(), LocalPlayer(), GetConVar("xtwisters3_visuallizewindfield"):GetBool())

                            self.RenderUpdateDelay = CurTime()
                        end
                    end

                    if GetConVar("xtwisters3_screenshake"):GetBool() then
                        local ShakeAmount = (math.max(Windspeed - 40, 0) / 80) ^ 2 * 2

                        util.ScreenShake(Entity:GetShootPos(), ShakeAmount, 40, SuperRandom(0.01, 0.1), 10000)
                    end

                    if self.TornadoSound and self.StartUp then
                        local PlayerDistanceFromTornado = ((self:GetPos() - PlayerPosition) * Vector(1, 1, 0)):Length()

                        local FadeDiameter = ReturnWindfieldRadius(self, 60, WindfieldData) * 2 + (ClientWindspeed * 50 + ClientCoreSize)
                        local FadeDistance = 1 - math.min((PlayerDistanceFromTornado / FadeDiameter), 1) ^ 0.35

                        local HeavyWindFade = InverseLerp(Windspeed, 25, 140)
                        local ModerateWindFade = InverseLerp(Windspeed, 15, 130)
                        local DestructiveWindFade = InverseLerp(Windspeed, 35, 155)
                        local ViolentWindFade = InverseLerp(Windspeed, 75, 235)

                        self.TornadoSound:ChangeVolume(FadeDistance)

                        if WindTunnelMultiplier < 0.5 and GetConVar("xtwisters3_audiomuffling"):GetBool() then
                            local DSP = 104
                            if WindTunnelMultiplier <= 0 then
                                DSP = 15
                            end

                            self.HeavyWind:SetDSP(DSP)
                            self.ModerateWind:SetDSP(DSP)
                            self.DestructiveWind:SetDSP(DSP)
                            self.ViolentWinds:SetDSP(DSP)
                            self.TornadoSound:SetDSP(DSP)
                        else
                            local DSP = 0

                            self.HeavyWind:SetDSP(DSP)
                            self.ModerateWind:SetDSP(DSP)
                            self.DestructiveWind:SetDSP(DSP)
                            self.ViolentWinds:SetDSP(DSP)
                            self.TornadoSound:SetDSP(DSP)
                        end

                        if not self.TornadoSound:IsPlaying() then
                            self.TornadoSound:SetSoundLevel(0)
                            self.TornadoSound:PlayEx(0, 100)
                        end

                        if GetConVar("xtwisters3_windsounds"):GetBool() then

                            self.HeavyWind:ChangeVolume(HeavyWindFade/2, 0)
                            self.ModerateWind:ChangeVolume(ModerateWindFade/2, 0)
                            self.DestructiveWind:ChangeVolume(DestructiveWindFade/2, 0)
                            self.ViolentWinds:ChangeVolume(ViolentWindFade, 0)

                            self.HeavyWind:ChangePitch(Lerp(HeavyWindFade, 70, 110), 0)
                            self.ModerateWind:ChangePitch(Lerp(ModerateWindFade, 65, 150), 0)
                            self.DestructiveWind:ChangePitch(Lerp(DestructiveWindFade, 100, 255), 0)
                            self.ViolentWinds:ChangePitch(Lerp(ViolentWindFade, 70, 135), 0)

                            if not self.HeavyWind:IsPlaying() then
                                self.HeavyWind:SetSoundLevel(0)
                                self.HeavyWind:PlayEx(0, 0)
                            end

                            if not self.ModerateWind:IsPlaying() then
                                self.ModerateWind:SetSoundLevel(0)
                                self.ModerateWind:PlayEx(0, 0)
                            end

                            if not self.DestructiveWind:IsPlaying() then
                                self.DestructiveWind:SetSoundLevel(0)
                                self.DestructiveWind:PlayEx(0, 0)
                            end

                            if not self.ViolentWinds:IsPlaying() then
                                self.ViolentWinds:SetSoundLevel(0)
                                self.ViolentWinds:PlayEx(0, 0)
                            end
                        else
                            self.HeavyWind:ChangeVolume(0, 0)
                            self.ModerateWind:ChangeVolume(0, 0)
                            self.DestructiveWind:ChangeVolume(0, 0)
                            self.ViolentWinds:ChangeVolume(0, 0)
                        end
                    end

                    Windspeed = Windspeed * WindTunnelMultiplier

                    if math.random(0, 550) == 1 and Windspeed >= 25 and GetConVar("xtwisters3_windgusts"):GetBool() then
                        local GustSoundFade = InverseLerp(Windspeed, 75, 200)
                        Entity:EmitSound("ambient/ambience/rainscapes/rain/stereo_gust_0" .. math.random(2, 6) .. ".wav", 75, 100, 0.9 * GustSoundFade)
                    end

                    if math.random(0, 130) == 1 and Windspeed >= 60 and GetConVar("xtwisters3_debrisbanging"):GetBool() then
                        local DebrisSoundFade = InverseLerp(Windspeed, 75, 200)
                        Entity:EmitSound("ambient/ambience/rainscapes/rain/debris_0" .. math.random(2, 8) .. ".wav", 75, 100, 0.35 * DebrisSoundFade)
                    end
                end
            end
        end
    end

    self:NextThink(CurTime())
    return true
end

function ENT:OnStart()
    self.CreationTime = CurTime()

    if SERVER then
        timer.Simple(GetConVar("xtwisters3_vortexlifetime"):GetFloat(), function()
            if self and self:IsValid() then
                self:Remove()
            end
        end)

        self.VortexLifetime = GetConVar("xtwisters3_vortexlifetime"):GetFloat()
        self.MovementDirection = Vector(SuperRandom(-1, 1), 0, SuperRandom(-1, 1))
        self.MovementHeightGoal = self:GetPos().Z

        UpdateNWValues(self)
        timer.Simple(0.1, function()
            if self and self:IsValid() then
                if GetConVar("xtwisters3_tornadoesstrengthen"):GetBool() then
                    self.CanStrengthen = true
                    self.GoalCoreSize = self.VortexCoreSize
                    self.GoalWindspeed = self.VortexWindspeed
                end
                self.StartUp = true

                ParticleEffectAttach(self.ParticleSystemName, PATTACH_POINT_FOLLOW, self, 0)
            end
        end)

        if GetConVar("xtwisters3_smarttornadoes"):GetBool() then
            self.SmartPathing = true
            self.SmartTarget = Vector(0, 0, 0)
        end
    elseif CLIENT then
        self.HeavyWind = CreateSound(self, "ambient/ambience/rainscapes/rain/whistle_debris_loop.wav")
        self.ModerateWind = CreateSound(self, "ambient/ambience/rainscapes/rain/heavy_wind01.wav")
        self.DestructiveWind = CreateSound(self, "ambient/ambience/rainscapes/rain/debris_loop.wav")
        self.ViolentWinds = CreateSound(self, "WindSounds/ViolentWinds.wav")

        RunConsoleCommand("r_farz", "90000")

        timer.Simple(0.1, function()
            if self and self:IsValid() then
                self.StartUp = true
            end
        end)
    end
end

function ENT:OnRemoval()
    self:StopParticles()

    XT3RemoveSound(self.HeavyWind)
    XT3RemoveSound(self.ModerateWind)
    XT3RemoveSound(self.DestructiveWind)
    XT3RemoveSound(self.ViolentWind)

    if SERVER then
        local Entities = ents.FindInSphere(self:GetPos() + Vector(0, 0, 1), ReturnWindfieldRadius(self, 1))

        for Index = 1, #Entities do
            local Entity = Entities[Index]

            if Entity:IsValid() and Entity ~= self and Entity:GetClass() ~= "gmod_ghost" and Entity:GetClass() ~= "sent_anim" and not Entity:IsWorld() and not Entity:IsWeapon() and not Entity:IsVehicle() and not Entity:IsNPC() and not Entity:IsPlayer() then
                local PhysObject = Entity:GetPhysicsObject()
                if PhysObject:IsValid() then
                    if PhysObject:IsMotionEnabled() then
                        PhysObject:SetDamping(0, 0)
                        PhysObject:SetDragCoefficient(0)
                    end
                end
            end
        end
    elseif CLIENT then
        self.CompletedWindfieldRendering = XT3RenderWindfield(self, 1, LocalPlayer(), false)
    end
end

function ENT:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end
