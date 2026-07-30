VNPCs = VNPCs or {}
VNPCs.Icon = "vnpcs/vnpcsicon16.png"

properties.Add("vnpcs_eatme", {
	MenuLabel = "Eat me!",
	Order = 999,
	MenuIcon = VNPCs.Icon,
	Filter = function(self, ent, ply)
		if not ent.IsDrGNextbot then return false end
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
        --print(ent, SERVER) blehhhh
        ent:ClearPatrols()
        ent:SetEntityRelationship(ply, D_HT, 99999)
        ent:SetEnemy(ply)
        ent:SpotEntity(ply)
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