VectorZAxis = Vector(0, 0, 1)
XT3SpeedOfSound = 4501.32 -- feet per second
XT3BaseAtmosphericPressure = 1013

local function SullivanVortex(RMW, Magnitude, FallOff)
    local NormalizedDistance = (Magnitude / RMW)

    return (NormalizedDistance ^ 2.4 * (0.3 + 0.7 * NormalizedDistance ^ 7.89) ^ -0.435) ^ FallOff
end

local function BurgersRottVortex(RMW, Magnitude, FallOff)
    local NormalizedDistance = (Magnitude / (RMW))

    local TangentialMultiplier = ((1.4 * NormalizedDistance ^ -1 * (1 - math.exp(-1.2564 * NormalizedDistance ^ 2)))) ^ FallOff
    local AxialMultiplier = (4 * 0.125 * 2 / (1 + NormalizedDistance ^ 2) ^ 2) ^ FallOff
    local RadialMultiplier = ((2 * NormalizedDistance) / (1 + NormalizedDistance ^ 2)) ^ FallOff

    return TangentialMultiplier, RadialMultiplier, AxialMultiplier
end

local function PressureDropCalculation(TotalWindspeed, RMW, Magnitude, FallOff)
    local NormalizedDistance = (Magnitude / (RMW))

    local PressureDropStrength = 100 * (TotalWindspeed / 165) ^ 2
    local PressureDropMultiplier = (4 * 0.125 * 2 / (1 + NormalizedDistance ^ 2) ^ 2) ^ (FallOff/2)
    local PressureDropped = (PressureDropStrength * PressureDropMultiplier)

    local TotalPressureDrop = XT3BaseAtmosphericPressure - PressureDropped
    return TotalPressureDrop, PressureDropped, PressureDropMultiplier
end

function SuperRandom(mi, ma)
    return math.random(1000) / 1000 * (ma - mi) + mi
end

function InverseLerp(v, a, b)
    local Value = (v - a) / (b - a)

    return math.Clamp(Value, 0, 1)
end

function GetWindfieldData(Vortex)
    local WindfieldData = {
        VortexCenter = Vortex:GetPos(),
        VortexWindspeed = Vortex.VortexWindspeed,
        VortexCoreSize = Vortex.VortexCoreSize,
        VortexSwirlRatio = Vortex.VortexSwirlRatio,
        VortexWindfieldFallOff = Vortex.VortexWindfieldFallOff,
        VortexForceMultipliers = Vortex.WindfieldMultipliers,
        VortexMovementVector = (Vortex.MovementDirection * Vortex.MovementSpeed)
    }

    return WindfieldData
end

function GetGlobalWindData()
    local Tornadoes = {}
    local Storms = {}

    local GlobalTornadoes = ents.FindByClass("xt3_tornadoes*")
    for Index = 1, #GlobalTornadoes do
        local LocalTornado = GlobalTornadoes[Index]
        if LocalTornado then
            local LocalTornadoWindfieldData = GetWindfieldData(LocalTornado)
            table.insert(Tornadoes, LocalTornadoWindfieldData)
        end
    end

    return {Tornadoes, Storms}
end

function SingleCelledVortex(WindfieldData, VortexCoreSize, BoundaryLayerMultiplier, NormallizedVector, Distance)
    local VortexWindspeed = WindfieldData.VortexWindspeed

    if GetConVar("xtwisters3_windfieldforwardmomentum"):GetBool() then
        VortexWindspeed = VortexWindspeed - WindfieldData.VortexMovementVector:Length()
    end

    local VortexSwirlRatio = Lerp(BoundaryLayerMultiplier, WindfieldData.VortexSwirlRatio * 0.75, WindfieldData.VortexSwirlRatio)

    local AxialWindspeed = VortexWindspeed / (1 + WindfieldData.VortexSwirlRatio)
    local RadialWindspeed = VortexWindspeed / (1 + VortexSwirlRatio)
    local TangentialWindspeed = VortexWindspeed - RadialWindspeed

    --AxialWindspeed = math.max(TangentialWindspeed, AxialWindspeed)

    local TangentialMultiplier, RadialMultiplier, AxialMultiplier = BurgersRottVortex(VortexCoreSize, Distance, WindfieldData.VortexWindfieldFallOff)

    if not WindfieldData.VortexForceMultipliers then
        WindfieldData.VortexForceMultipliers = {Radial = 1, Tangential = 1, Axial = 1}
    end

    local RadialVector = -NormallizedVector:GetNormalized() * (WindfieldData.VortexForceMultipliers.Radial)
    local TangentialVector = (-VectorZAxis):Cross(RadialVector) * (WindfieldData.VortexForceMultipliers.Tangential)
    local AxialVector = VectorZAxis * (WindfieldData.VortexForceMultipliers.Axial)

    local RadialCalculation = RadialVector * RadialWindspeed * RadialMultiplier * (1.1 - BoundaryLayerMultiplier) * (1 - AxialMultiplier)
    local TangentialCalculation = TangentialVector * TangentialWindspeed * TangentialMultiplier
    local AxialCalculation = AxialVector * AxialWindspeed * AxialMultiplier

    return TangentialCalculation, RadialCalculation, AxialCalculation, TangentialMultiplier
end

function TwoCelledVortex(WindfieldData, VortexCoreSize, BoundaryLayerMultiplier, NormallizedVector, Distance, EyeBleed, WindfieldBleed)
    local VortexWindspeed = WindfieldData.VortexWindspeed

    if GetConVar("xtwisters3_windfieldforwardmomentum"):GetBool() then
        VortexWindspeed = VortexWindspeed - GetConVar("xtwisters3_vortexspeed"):GetFloat()
    end

    local VortexSwirlRatio = Lerp(BoundaryLayerMultiplier ^ 5, WindfieldData.VortexSwirlRatio/4, WindfieldData.VortexSwirlRatio)

    local AxialWindspeed = VortexWindspeed / (1 + WindfieldData.VortexSwirlRatio)
    local RadialWindspeed = VortexWindspeed / (1 + VortexSwirlRatio)
    local TangentialWindspeed = VortexWindspeed - RadialWindspeed
    local SecondCellWindspeed = 100 * (VortexWindspeed / 250)

    local WindfieldMultiplier = SullivanVortex(VortexCoreSize, Distance, WindfieldData.VortexWindfieldFallOff)

    local CentrifugeBleed = 1 - math.min(Distance / (VortexCoreSize + 100), 1)
    SecondCellWindspeed = SecondCellWindspeed * EyeBleed

    local RadialVector = -NormallizedVector:GetNormalized() * (WindfieldData.VortexForceMultipliers.Radial or 1)
    local TangentialVector = (-VectorZAxis):Cross(RadialVector) * (WindfieldData.VortexForceMultipliers.Tangential or 1)
    local AxialVector = VectorZAxis * (WindfieldData.VortexForceMultipliers.Axial or 1)

    local AboveVBLTangentialInwards = TangentialWindspeed/100

    local RadialCalculation = (Lerp(CentrifugeBleed ^ 0.5, RadialVector, -RadialVector) * RadialWindspeed * WindfieldMultiplier) * (1 - BoundaryLayerMultiplier)
    RadialCalculation = RadialCalculation + (RadialVector * AboveVBLTangentialInwards)

    local TangentialCalculation = (TangentialVector * (TangentialWindspeed-AboveVBLTangentialInwards)) * WindfieldMultiplier
    local AxialCalculation = (AxialVector * RadialWindspeed * (WindfieldMultiplier ^ Lerp(BoundaryLayerMultiplier, 5, 2)))

    local DowndraftCalculation = ((AxialVector * (EyeBleed ^ 5) + RadialVector):GetNormalized() * SecondCellWindspeed)
    RadialCalculation = RadialCalculation - DowndraftCalculation

    return TangentialCalculation, RadialCalculation, AxialCalculation, WindfieldMultiplier
end

function GetTornadoWindspeed(Vortex, GetWindspeedAtPosition, WindfieldData)
    if not WindfieldData then
        WindfieldData = GetWindfieldData(Vortex)
    end

    local NormallizedVector = (GetWindspeedAtPosition - WindfieldData.VortexCenter) * Vector(1, 1, 0)
    local Distance = NormallizedVector:Length()

    local VortexHeight = WindfieldData.VortexCenter[3]
    local ObjectHeight = GetWindspeedAtPosition[3]

    local VortexCoreSize = WindfieldData.VortexCoreSize
    local BoundaryLayerSize = VortexCoreSize * 0.1 + (WindfieldData.VortexWindspeed / (1 + WindfieldData.VortexSwirlRatio))

    local BoundaryLayerMultiplier = InverseLerp(ObjectHeight, VortexHeight, VortexHeight + BoundaryLayerSize)

    VortexCoreSize = VortexCoreSize * (1 + ((BoundaryLayerMultiplier) * 0.5))

    local CurrentNoiseTime = CurTime()
    local WindspeedNoise, WindfieldNoise = 1, 1
    
    if GetConVar("xtwisters3_instablewindfield"):GetBool() then
        WindspeedNoise, WindfieldNoise = XT3WindfieldNoise(GetWindspeedAtPosition, WindfieldData.VortexCenter, CurrentNoiseTime, WindfieldData)
    end

    VortexCoreSize = VortexCoreSize * WindfieldNoise

    local WindVelocity, ReturnedWindspeed, WindfieldMultiplier
    local SwirlRatio = math.abs(WindfieldData.VortexSwirlRatio)

    local TangentialWindspeed, RadialWindspeed, AxialWindspeed, WindfieldMultiplier
    local WindfieldBleed = math.min(VortexCoreSize / Distance, 1) ^ WindfieldData.VortexWindfieldFallOff
    local EyeMultiplier = 1 - math.min(Distance / VortexCoreSize, 1) ^ WindfieldData.VortexWindfieldFallOff

    local VortexBreakDown = InverseLerp(SwirlRatio, 0.55, 0.75)
    if VortexBreakDown == 0 then
        TangentialWindspeed, RadialWindspeed, AxialWindspeed, WindfieldMultiplier = SingleCelledVortex(WindfieldData, VortexCoreSize, BoundaryLayerMultiplier, NormallizedVector, Distance)
    elseif VortexBreakDown > 0 and VortexBreakDown < 1 then
        local SwirlValue = VortexBreakDown

        local NormallizedObjectHeight = math.abs(ObjectHeight - VortexHeight)
        local NormallizedVortexHeight = math.abs(VortexHeight - ObjectHeight)
        local VortexBreakdownHeight = math.max(NormallizedObjectHeight / (NormallizedVortexHeight+1000), 0)

        local breakdownMultiplier = InverseLerp(VortexBreakdownHeight, math.max((1 - SwirlValue) - 0.05, 0), (1 - SwirlValue) + 0.05)
        breakdownMultiplier = Lerp(math.Clamp((VortexBreakDown - 0.95) / 0.05, 0, 1), breakdownMultiplier, 1)

        local SCTangential, SCRadial, SCAxial, SCMult = SingleCelledVortex(WindfieldData, VortexCoreSize, BoundaryLayerMultiplier, NormallizedVector, Distance)
        local TCTangential, TCRadial, TCAxial, TCMult = TwoCelledVortex(WindfieldData, VortexCoreSize, BoundaryLayerMultiplier, NormallizedVector, Distance, EyeMultiplier, WindfieldBleed)

        TangentialWindspeed = Lerp(breakdownMultiplier, SCTangential, TCTangential)
        RadialWindspeed = Lerp(breakdownMultiplier, SCRadial, TCRadial)
        AxialWindspeed = Lerp(breakdownMultiplier, SCAxial, TCAxial)

        WindfieldMultiplier = Lerp(breakdownMultiplier, SCMult, TCMult)
    else
        TangentialWindspeed, RadialWindspeed, AxialWindspeed, WindfieldMultiplier = TwoCelledVortex(WindfieldData, VortexCoreSize, BoundaryLayerMultiplier, NormallizedVector, Distance, EyeMultiplier, WindfieldBleed)
    end

    if GetConVar("xtwisters3_windfieldforwardmomentum"):GetBool() then
        local ForwardSpeedCalculation = (WindfieldData.VortexMovementVector * WindfieldMultiplier) * Vector(1, 1, 0)

        WindVelocity = (TangentialWindspeed + RadialWindspeed + ForwardSpeedCalculation) + AxialWindspeed
        ReturnedWindspeed = math.min((ForwardSpeedCalculation + (RadialWindspeed + TangentialWindspeed)):Length() + AxialWindspeed:Length(), (WindfieldData.VortexWindspeed + WindfieldData.VortexMovementVector:Length()))
    else
        WindVelocity = (TangentialWindspeed + RadialWindspeed) + AxialWindspeed
        ReturnedWindspeed = math.min(((RadialWindspeed + TangentialWindspeed):Length() + AxialWindspeed:Length()), WindfieldData.VortexWindspeed)
    end

    --[[ -- This is a test for like a rear inflow jet thing, I'm on the fence about it's implementation.
    if false then
        local RFIDirection = WindfieldData.VortexMovementVector:GetNormalized():Cross(VectorZAxis)
        local RFIOffset = (RFIDirection+WindfieldData.VortexMovementVector:GetNormalized()/2):GetNormalized() * VortexCoreSize

        local RFINormallizedVector = (GetWindspeedAtPosition - (WindfieldData.VortexCenter+RFIOffset)) * Vector(1, 1, 0)
        local NuDistance = RFINormallizedVector:Length()

        local AimVector = (RFINormallizedVector + (RFIDirection * (NuDistance/VortexCoreSize)^2 * 75)):GetNormalized()
        local UpDot = math.Clamp(AimVector:Dot(-WindfieldData.VortexMovementVector:GetNormalized()), 0, 1) ^ 5

        local RFIWindspeed = WindfieldData.VortexWindspeed * (UpDot * WindfieldMultiplier^0.85) * .75
        local RFIWindVector = (-RFINormallizedVector + (RFIDirection * (NuDistance/VortexCoreSize)^2 * 75 * .5)):GetNormalized() * RFIWindspeed

        ReturnedWindspeed = math.max(ReturnedWindspeed, RFIWindspeed)

        WindVelocity = WindVelocity + RFIWindVector 
        WindVelocity = WindVelocity * math.Clamp((ReturnedWindspeed / WindVelocity:Length()), 0, 1)
    end
    --]]

    local TotalPressureDrop, PressureDropped, PressureDropMultiplier = PressureDropCalculation(WindfieldData.VortexWindspeed, VortexCoreSize, Distance, WindfieldData.VortexWindfieldFallOff)
    local PressureData = {TotalPressureDrop, PressureDropped, PressureDropMultiplier}

    WindVelocity = WindVelocity * WindspeedNoise
    ReturnedWindspeed = ReturnedWindspeed * WindspeedNoise

    return WindVelocity, ReturnedWindspeed, WindfieldMultiplier, PressureData
end

function GetGlobalWindspeed(GetWindspeedAtPosition, GlobalWindfieldData)
    if not GlobalWindfieldData then
        GlobalWindfieldData = GetGlobalWindData()
    end

    local LowestAtmosphericPressure = XT3BaseAtmosphericPressure
    local LowestPressureDropped = 0
    local LowestPressureDropMultiplier = 0

    local MaximumWindVelocity = Vector()
    local MaximumWindspeed = 0

    local DominantWindfieldMultiplier = 0

    local GlobalWindfieldDataTornadoes = GlobalWindfieldData[1]
    if #GlobalWindfieldDataTornadoes > 0 then
        for Index = 1, #GlobalWindfieldDataTornadoes do
            local LocalWindfieldData = GlobalWindfieldDataTornadoes[Index]
            if LocalWindfieldData then
                local LocalWindVelocity, LocalWindspeed, LocalMultiplier, PressureData = GetTornadoWindspeed(false, GetWindspeedAtPosition, LocalWindfieldData)

                MaximumWindVelocity = MaximumWindVelocity + LocalWindVelocity
                MaximumWindspeed = math.max(MaximumWindspeed, LocalWindspeed)
                DominantWindfieldMultiplier = math.max(LocalMultiplier, DominantWindfieldMultiplier)

                LowestAtmosphericPressure = math.min(LowestAtmosphericPressure, PressureData[1])
                LowestPressureDropped = math.max(LowestPressureDropped, PressureData[2])
                LowestPressureDropMultiplier = math.max(LowestPressureDropMultiplier, PressureData[3])
            end
        end
    end

    MaximumWindVelocity = MaximumWindVelocity * math.Clamp((MaximumWindspeed / MaximumWindVelocity:Length()), 0, 1)
    return MaximumWindVelocity, MaximumWindspeed, LowestAtmosphericPressure, LowestPressureDropped, LowestPressureDropMultiplier
end

function ReturnWindfieldRadius(Tornado, SeekWindspeed, WindfieldData)
    if not WindfieldData then
        WindfieldData = GetWindfieldData(Tornado)
    end

    local WindfieldRadius = 0 -- WindfieldData.VortexCoreSize * WindfieldData.VortexWindfieldFallOff * ((WindfieldData.VortexWindspeed + (WindfieldData.VortexMovementVector:Length())) / SeekWindspeed) ^ (1 / WindfieldData.VortexWindfieldFallOff)

    if GetConVar("xtwisters3_windfieldforwardmomentum"):GetBool() then
        WindfieldRadius = WindfieldData.VortexCoreSize * WindfieldData.VortexWindfieldFallOff * ((WindfieldData.VortexWindspeed + (WindfieldData.VortexMovementVector:Length())) / SeekWindspeed) ^ (1 / WindfieldData.VortexWindfieldFallOff)
    else
        WindfieldRadius = WindfieldData.VortexCoreSize * WindfieldData.VortexWindfieldFallOff * ((WindfieldData.VortexWindspeed) / SeekWindspeed) ^ (1 / WindfieldData.VortexWindfieldFallOff)
    end

    return math.max(WindfieldRadius, 0)
end

function TraceCheckWalls(Entity, TraceSender, CheckDistance)

    local BlockedFromTheFront = false
    local BlockedFromTheBack = false
    local BlockedFromTheLeft = false
    local BlockedFromTheRight = false
    local BlockedFromTheTop = false

    local AreasBlocked = 0
    local WindTunnelCheck = 0
    local WindMultiplier = 1
    local WindMultiplierUpdraft = 1
    local CheckDistance = CheckDistance or 2000

    local EntityPos = Entity:GetPos()

    if Entity:IsPlayer() or Entity:IsNPC() then
        EntityPos = EntityPos + (VectorZAxis * Entity:GetUp() * 60)
    elseif Entity:IsVehicle() then
       EntityPos = EntityPos + (VectorZAxis * Entity:GetUp() * 60)
    end

    local IgnoreList = {Entity, TraceSender, player.GetAll()}
    local WallTraceFront = util.TraceLine({
        start = EntityPos,
        endpos = EntityPos + Vector(0, CheckDistance, 0),
        filter = IgnoreList
    })

    local WallTraceBack = util.TraceLine({
        start = EntityPos,
        endpos = EntityPos + Vector(0, -CheckDistance, 0),
        filter = IgnoreList
    })

    local WallTraceRight = util.TraceLine({
        start = EntityPos,
        endpos = EntityPos + Vector(CheckDistance, 0, 0),
        filter = IgnoreList
    })

    local WallTraceLeft = util.TraceLine({
        start = EntityPos,
        endpos = EntityPos + Vector(-CheckDistance, 0, 0),
        filter = IgnoreList
    })

    local RoofTrace = util.TraceLine({
        start = EntityPos,
        endpos = EntityPos + Vector(0, 0, CheckDistance),
        filter = IgnoreList
    })

    if WallTraceFront.Hit then
        BlockedFromTheFront = true
        AreasBlocked = AreasBlocked + 1
        WindTunnelCheck = WindTunnelCheck + 1
        WindMultiplier = math.Clamp(WindMultiplier - 0.2, 0, 2)
    end

    if WallTraceBack.Hit then
        BlockedFromTheBack = true
        AreasBlocked = AreasBlocked + 1
        WindTunnelCheck = WindTunnelCheck + 1
        WindMultiplier = math.Clamp(WindMultiplier - 0.2, 0, 2)
    end

    if WallTraceLeft.Hit then
        BlockedFromTheLeft = true
        AreasBlocked = AreasBlocked + 1
        WindTunnelCheck = WindTunnelCheck + 1
        WindMultiplier = math.Clamp(WindMultiplier - 0.2, 0, 2)
    end

    if WallTraceRight.Hit then
        BlockedFromTheRight = true
        AreasBlocked = AreasBlocked + 1
        WindTunnelCheck = WindTunnelCheck + 1
        WindMultiplier = math.Clamp(WindMultiplier - 0.2, 0, 2)
    end

    if RoofTrace.Hit then
        BlockedFromTheTop = true
        AreasBlocked = AreasBlocked + 2
        WindMultiplier = math.Clamp(WindMultiplier - 0.35, 0, 2)
        WindMultiplierUpdraft = 0
    end

    if BlockedFromTheTop == true and WindTunnelCheck == 2 then
        WindMultiplier = math.Clamp(1, 0, 2)
        WindMultiplierUpdraft = 0.25
    end

    if BlockedFromTheTop == false and WindTunnelCheck >= 4 then
        WindMultiplierUpdraft = 2
    end

    if AreasBlocked >= 6 then
        return true, WindMultiplier, WindMultiplierUpdraft
    else
        return false, WindMultiplier, WindMultiplierUpdraft
    end
end

function XT3CauseDamage(attacker, inflictor, victim, damage, damagetype)
    local dmg = DamageInfo()

    dmg:SetDamage(damage)
    dmg:SetAttacker(attacker)
    dmg:SetInflictor(inflictor)
    dmg:SetDamageType(damagetype)
    victim:TakeDamageInfo(dmg)
end

function SelectTornadoParticle(Table)
    local ChosenTornado = Table[math.random(1, #Table)]

    local ParticleName = ChosenTornado.ParticleName
    local VortexSize = ChosenTornado.VortexSize
    local SwirlRatio = ChosenTornado.VortexSwirlRatio
    local StrengthenParams = ChosenTornado.StrengthenParams
    local ForceMultipliers = ChosenTornado.VortexForceMultipliers

    if not SwirlRatio then
        SwirlRatio = Lerp(InverseLerp(VortexSize, 100, 4000), 1, 5) - SuperRandom(0, 0.65)
    else
        SwirlRatio = SuperRandom(ChosenTornado.VortexSwirlRatio.Min, ChosenTornado.VortexSwirlRatio.Max)
    end

    if not StrengthenParams then
        StrengthenParams = {
            WindspeedFadeStart = 1,
            WindspeedFadeEnd = 45,
            VortexStartSize = VortexSize,
            SizeFadeStart = 1,
            SizeFadeEnd = 1
        }
    end

    if not ForceMultipliers then
        ForceMultipliers = {
            Radial = 1,
            Tangential = 1,
            Axial = 1
        }
    end

    return ParticleName, VortexSize, SwirlRatio, StrengthenParams, ForceMultipliers
end -- For old API tornadoes.

function XT3SelectTornadoParticle(Table)
    local ChosenTornado = Table[math.random(1, #Table)]

    local ParticleName = ChosenTornado.ParticleName
    local VortexSize = ChosenTornado.VortexSize
    local SwirlRatio = ChosenTornado.VortexSwirlRatio
    local StrengthenParams = ChosenTornado.StrengthenParams
    local ForceMultipliers = ChosenTornado.VortexForceMultipliers

    if not SwirlRatio then
        SwirlRatio = Lerp(InverseLerp(VortexSize, 100, 4000), 1, 5) - SuperRandom(0, 0.65)
    else
        SwirlRatio = SuperRandom(ChosenTornado.VortexSwirlRatio.Min, ChosenTornado.VortexSwirlRatio.Max)
    end

    if not StrengthenParams then
        StrengthenParams = {
            WindspeedFadeStart = 1,
            WindspeedFadeEnd = 45,
            VortexStartSize = VortexSize,
            SizeFadeStart = 1,
            SizeFadeEnd = 1
        }
    end

    if not ForceMultipliers then
        ForceMultipliers = {
            Radial = 1,
            Tangential = 1,
            Axial = 1
        }
    end

    return ParticleName, VortexSize, SwirlRatio, StrengthenParams, ForceMultipliers
end

function XT3ApplyTornadoParameters(WindspeedRange, FallOffRange, Tornado, ParticleTable)
    local Particle, Size, Swirl, StrengthenParams, WindfieldMultipliers = XT3SelectTornadoParticle(ParticleTable)

    Tornado.ParticleSystemName = tostring(Particle)
    Tornado.VortexCoreSize = Size
    Tornado.VortexSwirlRatio = Swirl
    Tornado.VortexStrengthenParameters = StrengthenParams
    Tornado.WindfieldMultipliers = WindfieldMultipliers

    Tornado.VortexWindspeed = SuperRandom(WindspeedRange.Min, WindspeedRange.Max)

    if FallOffRange then
        Tornado.VortexWindfieldFallOff = SuperRandom(FallOffRange.Min, FallOffRange.Max)
    else
        Tornado.VortexWindfieldFallOff = math.max(SuperRandom(0.55, 1), math.min((Size / 1500) ^ 2, 0.85))
    end

    return {Particle = Particle, Size = Size, Swirl = Swirl, StrengthenParams = StrengthenParams, WindfieldMultipliers = WindfieldMultipliers}
end

function XT3RetrievePlayerEntities(IncludeNPCs, IncludeVehicles, IncludeRagdolls)
    local ClientEntities = ents.FindByClass("player")

    if IncludeVehicles then
        local Vehicles = ents.FindByClass("prop_vehicle*")
        for Index = 1, #Vehicles do
            local Vehicle = Vehicles[Index]
            if Vehicle and Vehicle:IsValid() then
                Vehicle.XT3SensesIsVehicle = true
                table.insert(ClientEntities, Vehicle)
            end
        end

        Vehicles = ents.FindByClass("lvs_*")
        for Index = 1, #Vehicles do
            local Vehicle = Vehicles[Index]
            if Vehicle and Vehicle:IsValid() then
                Vehicle.XT3SensesIsVehicle = true
                table.insert(ClientEntities, Vehicle)
            end
        end

        Vehicles = ents.FindByClass("lfs_*")
        for Index = 1, #Vehicles do
            local Vehicle = Vehicles[Index]
            if Vehicle and Vehicle:IsValid() then
                Vehicle.XT3SensesIsVehicle = true
                table.insert(ClientEntities, Vehicle)
            end
        end

        -- I hate glide. This should not have to exist in the way that it does exist.

        if GetConVar("xtwisters3_glidecompatibility"):GetBool() then
            for Index, Vehicle in ents.Iterator() do
                if Vehicle and Vehicle:IsValid() and Vehicle.IsGlideVehicle then
                    Vehicle.XT3SensesIsVehicle = true
                    table.insert(ClientEntities, Vehicle)
                end
            end
        end
    end

    if IncludeNPCs then
        local NPCs = ents.FindByClass("npc*")
        for Index = 1, #NPCs do
            local NPC = NPCs[Index]
            if NPC and NPC:IsValid() then
                table.insert(ClientEntities, NPC)
            end
        end

        NPCs = ents.FindByClass("monster*")
        for Index = 1, #NPCs do
            local NPC = NPCs[Index]
            if NPC and NPC:IsValid() then
                table.insert(ClientEntities, NPC)
            end
        end

        local Ragdolls = ents.FindByClass("prop_ragdoll*")
        for Index = 1, #Ragdolls do
            local Ragdoll = Ragdolls[Index]
            if Ragdoll and Ragdoll:IsValid() then
                table.insert(ClientEntities, Ragdoll)
            end
        end

        local Ragdolls = ents.FindByClass("hl2mp_ragdoll*")
        for Index = 1, #Ragdolls do
            local Ragdoll = Ragdolls[Index]
            if Ragdoll and Ragdoll:IsValid() then
                table.insert(ClientEntities, Ragdoll)
            end
        end
    end

    return ClientEntities
end

function XT3GetEntityAndChildern(Entity)
    local Entities = {}

    table.insert(Entities, Entity)
    local VehicleChildern = constraint.GetAllConstrainedEntities(Entity)
    for Index = 1, #VehicleChildern do
        local Vehicle = VehicleChildern[Index]
        if Vehicle and Vehicle:IsValid() then
            table.insert(Entities, Vehicle)
        end
    end

    return Entities
end

function XT3PrintHint(String, Duration)
    if GetConVar("xtwisters3_printhints"):GetBool() then
        if not Duration then
            Duration = 5
        end

        net.Start("xt3_newnotification")

        net.WriteString(String)
        net.WriteFloat(3)
        net.WriteFloat(Duration)

        net.Broadcast()
    end
end

function XT3PrintError(String, Duration)
    if GetConVar("xtwisters3_printhints"):GetBool() then
        if not Duration then
            Duration = 5
        end

        net.Start("xt3_newnotification")

        net.WriteString(String)
        net.WriteFloat(1)
        net.WriteFloat(Duration)

        net.Broadcast()
    end
end

function XT3RemoveSound(Sound)
    if Sound then
        Sound:Stop()
        Sound = nil
    end
end

function XT3GetPositionInRadius(StartPosition, Radius, MaxIterations)
    local ChosenPosition = StartPosition + (Vector(SuperRandom(-1, 1), SuperRandom(-1, 1), 0) * Radius)
    local DontAllowSpawn = false

    if not util.IsInWorld(ChosenPosition) then
        local NewPositionFound = false
        local MaxCount = 0

        repeat
            MaxCount = MaxCount + 1
            ChosenPosition = StartPosition + (Vector(SuperRandom(-1, 1), SuperRandom(-1, 1), 0) * Radius)

            if util.IsInWorld(ChosenPosition) then
                NewPositionFound = true
            end

            if MaxCount >= MaxIterations then
                MaxCount = 0
                DontAllowSpawn = true
            end
        until NewPositionFound or DontAllowSpawn
    end

    return DontAllowSpawn, ChosenPosition
end

function XT3SpawnLightning(Filter, SpawnPos, Radius, Type)
    if not Type then
        Type = 1

        if math.random()^2 >= 0.75 then
            Type = 2
        end

        if math.random()^2 >= 0.99 then
            Type = 3
        end
    end

    local PlayerEvaporationChance
    local LightningBolt

    if Type == 1 then
        LightningBolt = ents.Create("xt3_weather_lightning_negativebolt")
        PlayerEvaporationChance = 300
    elseif Type == 2 then
        LightningBolt = ents.Create("xt3_weather_lightning_positivebolt")
        PlayerEvaporationChance = 150
    elseif Type == 3 then
        LightningBolt = ents.Create("xt3_weather_lightning_superbolt")
        PlayerEvaporationChance = 25
    end

    if LightningBolt:IsValid() then
        local DontAllowSpawn, LightningStartPosition = true, VectorZAxis
        local THENALONGCAMEZEUS = false

        if math.random(1, PlayerEvaporationChance) == 1 then
            -- I'm sorry little one....
            THENALONGCAMEZEUS = true
            local PlayerTable = XT3RetrievePlayerEntities(true, false, true)
            local PlayerChosenForDeath = PlayerTable[math.random(1, #PlayerTable)]

            local RandomAngle = math.random() * 360
            local ExtraVector = Vector(math.sin(RandomAngle), 0, math.cos(RandomAngle)) * math.random() * 350

            if PlayerChosenForDeath and PlayerChosenForDeath:IsValid() then
                local PlayerPosition = PlayerChosenForDeath:GetPos()
                LightningStartPosition = PlayerPosition * Vector(1, 1, 0) + ((VectorZAxis * LightningStartPosition[3]) + Vector(0, 0, 100)) + ExtraVector
                DontAllowSpawn = false
            end
        else
            DontAllowSpawn, LightningStartPosition = XT3GetPositionInRadius(SpawnPos, Radius, 500)
            LightningStartPosition = LightningStartPosition + Vector(0, 0, 100)
        end

        if not DontAllowSpawn then
            local FindSky = util.TraceLine({
                start = LightningStartPosition,
                endpos = LightningStartPosition + Vector(0, 0, 100000),
                mask = nil,
                collisiongroup = COLLISION_GROUP_WORLD,
                filter = Filter
            })

            local ConnectToGround = util.TraceLine({
                start = FindSky.HitPos,
                endpos = FindSky.HitPos - Vector(0, 0, 100000),
                mask = MASK_WATER + MASK_SOLID,
                filter = Filter
            })

            local LightningSpawnPosition = FindSky.HitPos - (VectorZAxis * 10)

            LightningBolt:SetPos(LightningSpawnPosition)
            LightningBolt:Spawn()

            LightningBolt.PlayerSpawned = false

            if THENALONGCAMEZEUS then
                LightningBolt:Strike(-VectorZAxis, 50000)
            else
                local RandomX = math.random(-100, 100) / 100
                local RandomY = math.random(-100, 100) / 100
                LightningBolt:Strike(Vector(RandomX, RandomY, -1) * 0 - VectorZAxis, 50000)
            end
        else
            LightningBolt:Remove()
        end
    end
end

function XT3CheckIfEntityConnectedToVehicle(Entity)
    if constraint.HasConstraints(Entity) and GetConVar("xtwisters3_checkvehicleconstraints"):GetBool() then
        local PartOfVehicle = false

        for _, ConnectedPart in pairs(constraint.GetAllConstrainedEntities(Entity)) do
            if ConnectedPart and ConnectedPart:IsVehicle() then
                PartOfVehicle = true
            end
        end

        return PartOfVehicle
    end
end

function XT3ParticleEffect(ParticleName, Position, Angle, Parent)
    if SERVER then
        local ParticleParams = {
            ParticleName = ParticleName,
            Position = Position,
            Angle = Angle,
            Parent = Parent
        }

        net.Start("xt3_networkparticle")
        net.WriteTable(ParticleParams)
        net.Broadcast()

        ParticleEffect(ParticleParams.ParticleName, ParticleParams.Position, ParticleParams.Angle, ParticleParams.Parent)
    end
end

function XT3CreateConnectedParticle(ParticleName, StartPosition, EndPosition)
    net.Start("xt3_connectbolt")

    local BoltParams = {
        ParticleName = ParticleName,
        StartPosition = StartPosition,
        EndPosition = EndPosition
    }

    net.WriteTable(BoltParams)
    net.Broadcast()
end

if CLIENT then
    surface.CreateFont("XT3ProbeFont", {
        font = "Trebuchet MS",
        size = 16,
        weight = 10000,
        antialias = true,
        extended = true
    })
    surface.CreateFont("XT3BigProbeFont", {
        font = "Trebuchet MS",
        size = 32,
        weight = 10000,
        antialias = true,
        extended = true
    })

    local PressedMouseDown = false
    local AltDown = false
    local UseDown = false

    hook.Add("HUDPaint", "XT3AnemometerHudHook", function()
        local Player = LocalPlayer()
        if Player then
            local EyeTraceEntity = Player:GetEyeTrace().Entity
            if EyeTraceEntity:IsValid() then
                if EyeTraceEntity.XT3AnemometerDevice then
                    local PlayerPosition = Player:GetPos()
                    local AnemometerPosition = EyeTraceEntity:GetPos()

                    local DistanceFromPlayer = (AnemometerPosition - PlayerPosition):Length()

                    if DistanceFromPlayer < EyeTraceEntity.MaximumInteractDistance then
                        if EyeTraceEntity:GetNW2Bool("XT3ProbeDeployed", false) then
                            draw.SimpleText('Currently Deployed', "Trebuchet24", ScrW() / 2, (ScrH() / 2) + 30, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                            draw.SimpleText('Press " USE " to undeploy', "Trebuchet24", ScrW() / 2, ScrH() - 80, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                        else
                            draw.SimpleText('Press " USE " to deploy as a probe', "Trebuchet24", ScrW() / 2, ScrH() - 80, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                        end

                        draw.SimpleText('Press " WALK + USE " to reset the maximum scanned windspeeds', "Trebuchet24", ScrW() / 2, ScrH() * 0.96, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    end
                end
            end
        end
    end)

    hook.Add("KeyPress", "XT3AnemometerPressCheck", function(Player, Key)
        if Player and Player:IsValid() then
            local CurrentWeapon = Player:GetActiveWeapon()

            local IsHeld = false
            if CurrentWeapon and CurrentWeapon:IsValid() and CurrentWeapon:GetClass() == "weapon_physgun" and PressedMouseDown then
                IsHeld = true
            end

            if Key == IN_ATTACK then
                PressedMouseDown = true
            end

            if Key == IN_USE and not IsHeld then
                UseDown = true

                if not AltDown then
                    local EyeTraceEntity = Player:GetEyeTrace().Entity
                    if EyeTraceEntity:IsValid() then
                        local PlayerPosition = Player:GetPos()
                        local AnemometerPosition = EyeTraceEntity:GetPos()

                        local DistanceFromPlayer = (AnemometerPosition - PlayerPosition):Length()

                        if EyeTraceEntity.XT3AnemometerDevice and DistanceFromPlayer < (EyeTraceEntity.MaximumInteractDistance or 0) then
                            if EyeTraceEntity:GetNW2Bool("XT3ProbeDeployed", false) then
                                surface.PlaySound("buttons/button6.wav")
                            else
                                surface.PlaySound("buttons/button14.wav")
                            end

                            net.Start("xt3_deployanemometer")
                            net.WriteEntity(EyeTraceEntity)
                            net.SendToServer()
                        end
                    end
                end
            elseif Key == IN_WALK then
                AltDown = true
            end

            if AltDown and UseDown then
                local EyeTraceEntity = Player:GetEyeTrace().Entity
                if EyeTraceEntity:IsValid() then
                    local PlayerPosition = Player:GetPos()
                    local AnemometerPosition = EyeTraceEntity:GetPos()

                    local DistanceFromPlayer = (AnemometerPosition - PlayerPosition):Length()

                    if EyeTraceEntity.XT3AnemometerDevice and DistanceFromPlayer < (EyeTraceEntity.MaximumInteractDistance or 0) then
                        surface.PlaySound("buttons/button3.wav")

                        net.Start("xt3_anemometerreset")
                        net.WriteEntity(EyeTraceEntity)
                        net.SendToServer()
                    end
                end
            end
        end
    end)

    hook.Add("KeyRelease", "XT3AnemometerReleaseKeyCheck", function(Player, Key)
        if Key == IN_ATTACK then
            PressedMouseDown = false
        elseif Key == IN_USE then
            UseDown = false
        elseif Key == IN_WALK then
            AltDown = false
        end
    end)

end
