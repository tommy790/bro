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

ENT.LoadedSounds = {}
ENT.DigestSounds = {}
ENT.AbsorbSounds = {}

ENT.CurrentDigestSound = nil --index?
ENT.CurrentAbsorbSound = nil --index?

local function GetRandomFromTable(tbl) --:string?
	if not tbl then return end
	if #tbl == 0 then return end --has to be an array not a dict

	return tbl[math.random(1, #tbl)]
end

function ENT:StartDigestionSound()
    if self.CurrentDigestSound then return end
    
    local index = math.random(1, #self.DigestSounds)
    local patch = self.DigestSounds[index]
    self.CurrentDigestSound = index

    patch:Play()
    patch:ChangePitch(math.random(90,110))
end

function ENT:StopDigestionSound()
    if not self.CurrentDigestSound then return end
    local patch = self.DigestSounds[self.CurrentDigestSound]
    self.CurrentDigestSound = nil

    patch:FadeOut(1.5) --last incase it doesnt exist or some shit
end

function ENT:StartAbsorbSound()
    if self.CurrentAbsorbSound then return end
    
    local index = math.random(1, #self.AbsorbSounds)
    local patch = self.AbsorbSounds[index]
    self.CurrentAbsorbSound = index

    patch:Play()
    patch:ChangePitch(math.random(90,110))
end

function ENT:StopAbsorbSound()
    if not self.CurrentAbsorbSound then return end
    local patch = self.AbsorbSounds[self.CurrentAbsorbSound]
    self.CurrentAbsorbSound = nil

    patch:FadeOut(1.5) --last incase it doesnt exist or some shit
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
    self.DigestSounds = {}
    self.AbsorbSounds = {}

    for _,v in ipairs(self.Sounds.Digestion) do
        if self.LoadedSounds[v] then continue end
        self.LoadedSounds[v] = true

        local newPatch = CreateSound(self, v)
        table.insert(self.DigestSounds, newPatch)
    end

    for _,v in ipairs(self.Sounds.Absorb) do
        if self.LoadedSounds[v] then continue end
        self.LoadedSounds[v] = true 

        local newPatch = CreateSound(self, v)
        table.insert(self.AbsorbSounds, newPatch)
    end
end

function ENT:UpdateSounds(new_sounds)
    self.Sounds = new_sounds
    self:CreateSounds()
end

function ENT:StopAllSounds()
    for _,v in pairs(self.Sounds) do
        for _,j in ipairs(v) do
            self:StopSound(j)
        end
    end
end
