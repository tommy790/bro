ENT.Sounds = ENT.Sounds or {
    Gurgles = { --Digesting Foley
        "belly/snd_digesting.wav",
		"belly/snd_qdigestend3.wav",
		"belly/snd_qdigest1.wav",
		"belly/snd_qdigest2.wav",
		"belly/snd_qdigest3.wav",
    },
    Struggle = { --Foley based on struggle animation
        "vore_stomach/struggle1.mp3",
        "vore_stomach/struggle2.mp3",
        "vore_stomach/struggle3.mp3",
        "vore_stomach/struggle4.mp3",
    },
    Digestion = { --Digestion Loop Sound
        "vore_stomach/digestion_loop1.wav",
        "vore_stomach/digestion_loop2.wav",
        "vore_stomach/digestion_loop3.wav",
    },
    Absorb = { --Absorption Loop Sound
        "vore_stomach/absorption_loop1.wav",
        "vore_stomach/absorption_loop2.wav",
        "vore_stomach/absorption_loop3.wav",
    },
    Swallowed = { --When prey is eaten
        "vore_stomach/swallowed1.mp3",
        "vore_stomach/swallowed2.mp3",
        "vore_stomach/swallowed3.mp3",
        "vore_stomach/swallowed4.mp3",
    },
    DigestedPrey = { --When prey dies in stomach
        "vore_stomach/prey_digested_death1.mp3",
        "vore_stomach/prey_digested_death2.mp3",
        "vore_stomach/prey_digested_death3.mp3",
    },  
    AbsorbedPrey = { --When prey gets completely absorbed
        "vore_stomach/prey_fully_absorbed1.mp3",
        "vore_stomach/prey_fully_absorbed2.mp3",
        "vore_stomach/prey_fully_absorbed3.mp3",
    }
}

--[[
    Sound patch lists are created per instance by CreateSounds(). They are
    deliberately NOT declared on the ENT class table -- a class-level table is
    shared by every belly in the map, which previously made the second belly
    spawned load zero patches.
]]

ENT.CurrentDigestSound = nil --index?
ENT.CurrentAbsorbSound = nil --index?

local function GetRandomFromTable(tbl) --:string?
	if not tbl then return end
	if #tbl == 0 then return end --has to be an array not a dict

	return tbl[math.random(1, #tbl)]
end

function ENT:StartDigestionSound()
    if self.CurrentDigestSound then return end

    local patches = self.DigestSounds
    if not patches or #patches == 0 then return end

    local index = math.random(1, #patches)
    local patch = patches[index]
    if not patch then return end

    self.CurrentDigestSound = index

    patch:Play()
    patch:ChangePitch(math.random(90, 110))
end

function ENT:StopDigestionSound()
    if not self.CurrentDigestSound then return end

    local patch = self.DigestSounds and self.DigestSounds[self.CurrentDigestSound]
    self.CurrentDigestSound = nil

    if patch then patch:FadeOut(1.5) end
end

function ENT:StartAbsorbSound()
    if self.CurrentAbsorbSound then return end

    local patches = self.AbsorbSounds
    if not patches or #patches == 0 then return end

    local index = math.random(1, #patches)
    local patch = patches[index]
    if not patch then return end

    self.CurrentAbsorbSound = index

    patch:Play()
    patch:ChangePitch(math.random(90, 110))
end

function ENT:StopAbsorbSound()
    if not self.CurrentAbsorbSound then return end

    local patch = self.AbsorbSounds and self.AbsorbSounds[self.CurrentAbsorbSound]
    self.CurrentAbsorbSound = nil

    if patch then patch:FadeOut(1.5) end
end

function ENT:PlayRandomGurgle()
    if not self.GurgleSoundDebounce then
        local snd = GetRandomFromTable(self.Sounds.Gurgles)
        self:EmitSound(snd, 45, math.random(85, 115), 1)

        self.GurgleSoundDebounce = true 
        timer.Simple(1.25, function()
            if self and IsValid(self) then
                self.SwallowSoundDebounce = nil
            end
        end)
    end
end

function ENT:PlayRandomStruggle()
    if self.StruggleSoundDebounce then return end
    self.StruggleSoundDebounce = true 

    local snd = GetRandomFromTable(self.Sounds.Struggle)
    self:EmitSound(snd, 50, math.random(70, 120), 1)

    timer.Simple(0.6, function()
        if self and IsValid(self) then
            self.StruggleSoundDebounce = nil
        end
    end) 
end

function ENT:PlayFinalDigestSound()
    local snd = GetRandomFromTable(self.Sounds.DigestedPrey)
    self:EmitSound(snd, 75, math.random(85, 115), 1)
end

function ENT:PlayFinalAbsorbSound()
    local snd = GetRandomFromTable(self.Sounds.AbsorbedPrey)
    self:EmitSound(snd, 75, math.random(85, 115), 1)
end

function ENT:PlaySwallowedSound()
    if self.SwallowSoundDebounce then return end
    self.SwallowSoundDebounce = true 

    local snd = GetRandomFromTable(self.Sounds.Swallowed)
    self:EmitSound(snd)
    
    timer.Simple(1, function()
        if self and IsValid(self) then
            self.SwallowSoundDebounce = nil
        end
    end)
end

function ENT:CreateSounds()
    self:StopSoundPatches()

    self.DigestSounds = {}
    self.AbsorbSounds = {}

    for _, path in ipairs(self.Sounds.Digestion or {}) do
        table.insert(self.DigestSounds, CreateSound(self, path))
    end

    for _, path in ipairs(self.Sounds.Absorb or {}) do
        table.insert(self.AbsorbSounds, CreateSound(self, path))
    end
end

function ENT:UpdateSounds(new_sounds)
    self.Sounds = new_sounds
    self:CreateSounds()
end

--[[
    CSoundPatch objects have to be stopped explicitly -- StopSound(path) does not
    stop a looping patch, so removing a belly mid-digestion used to leave the
    gurgle loop playing until map change.
]]
function ENT:StopSoundPatches()
    -- iterate the two lists explicitly: {a, b} with a nil would truncate ipairs
    for _, patch in ipairs(self.DigestSounds or {}) do
        if patch then patch:Stop() end
    end

    for _, patch in ipairs(self.AbsorbSounds or {}) do
        if patch then patch:Stop() end
    end

    self.CurrentDigestSound = nil
    self.CurrentAbsorbSound = nil
end

function ENT:StopAllSounds()
    self:StopSoundPatches()

    for _, list in pairs(self.Sounds or {}) do
        if istable(list) then
            for _, path in ipairs(list) do
                self:StopSound(path)
            end
        end
    end
end
