VNPCs = VNPCs or {}
VNPCs.Icon = "vnpcs/vnpcsicon16.png"

properties.Add("vnpcs_eatme", {
	MenuLabel = "Eat me!",
	Order = 999,
	MenuIcon = VNPCs.Icon,
	Filter = function(self, ent, ply)
		if not ent.IsDrGNextbot and not ent.VNPC_FemaleModelVore then return false end
		if not ent.Predator then return false end
		return true
	end,
	Action = function(self, ent)
        self:MsgStart()
		net.WriteEntity( ent )
		self:MsgEnd()
	end,
	Receive = function(self, len, ply)
		local ent = net.ReadEntity()
        if ent.EatEntity then
            ent:EatEntity(ply)
            return
        end
        --print(ent, SERVER) blehhhh
        ent:ClearPatrols()
        ent:SetEntityRelationship(ply, D_HT, 99999)
        ent:SetEnemy(ply)
        ent:SpotEntity(ply)
	end
})

properties.Add("vnpcs_regurgitate", {
	MenuLabel = "Regurgitate Prey",
	Order = 1000,
	MenuIcon = VNPCs.Icon,
	Filter = function(self, ent, ply)
		local belly = ent.VNPC_Belly or ent.Belly
		if IsValid(belly) and belly.Prey and #belly.Prey > 0 then return true end
		return false
	end,
	Action = function(self, ent)
        self:MsgStart()
		net.WriteEntity(ent)
		self:MsgEnd()
	end,
	Receive = function(self, len, ply)
		local ent = net.ReadEntity()
		if IsValid(ent) and ent.ReleaseAllPrey then
			ent:ReleaseAllPrey()
		elseif IsValid(ent) and ent.Belly and ent.Belly.Regurgitate then
			for _, p_tbl in ipairs(ent.Belly.Prey or {}) do
				if p_tbl and IsValid(p_tbl.Entity) then
					pcall(ent.Belly.Regurgitate, ent.Belly, p_tbl.Entity)
				end
			end
		end
	end
})

hook.Add("EntityEmitSound", "MuffleVoredSounds", function( sound_info )
    --local server_or_client = SERVER and "SERVER" or "CLIENT"
	local ent = sound_info.Entity
    if not ent or not IsValid(ent) then return end
    
    local parent = ent:GetParent()
    --print(server_or_client, ent, parent)
    if ent.Vored or parent.Vored then
        --print(server_or_client, ent, parent)
        --sound_info.Volume = sound_info.Volume * 2 --lowers volume
        sound_info.SoundLevel = 60 --distance falloff
        sound_info.DSP = 15 --muffle, uses underwater dsp
        
        return true
    end
end )

--[[
hook.Add( "SetupPlayerVisibility", "AddRTCamera", function( ply, viewEntity )
   -- print(SERVER and "SERVER" or "CLIENT")
    --print(ply, viewEntity)
	-- Adds any view entity
	--
	-- We test if the PVS is already loaded, as in the past adding a loaded pvs could have crash the server which was fixed.
	-- (See https://github.com/Facepunch/garrysmod-issues/issues/3744)
	--if viewEntity:IsValid() and !viewEntity:TestPVS( ply ) then
		--AddOriginToPVS( viewEntity:GetPos() )
	--end
end )
]]

if CLIENT then
    if not DrGBase then 
        chat.AddText(Color(255,66,66), "YOU NEED DrGBASE IN ORDER FOR V-NPCS TO WORK\n", Color(255,145,42),"https://steamcommunity.com/sharedfiles/filedetails/?id=1560118657")
        return 
    end
    DrGBase.SetIcon("Vore", VNPCs.Icon)
end