if SERVER then
    AddCSLuaFile()
elseif CLIENT then
    XT3addedParticles = {}

    function XT3AddParticlesToCache(list)
        for k, v in ipairs(list) do
            if not table.HasValue(XT3addedParticles, v) then
                game.AddParticles(v)
                table.insert(XT3addedParticles, v)
            end
        end
    end

    local Particles = 

    {
        "particles/RainbowDoesStuff/RDSXT3Tornadoes.pcf", "particles/RainbowDoesStuff/RainbowWindTest.pcf",
        "particles/TheRollingTempest/trt_Tornadoes.pcf", "particles/PoisonGamerYT/PGYT-XT3-particles.pcf",
        "particles/AstralPlains/astralparticles_XT3.pcf", "particles/AstralPlains/astraltornadoes_XT3.pcf", "particles/AstralPlains/astralgeoparticles_XT3.pcf", "particles/AstralPlains/astralwhirlwinds.pcf",
        "particles/Caiden/caidenscontribution.pcf", "particles/Caiden/csc.pcf",
         "particles/Asher/asherstornadoes.pcf"
    }

    XT3AddParticlesToCache(Particles)

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
end
