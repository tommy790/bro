VNPCs = VNPCs or {}
VNPCs.Icon = "vnpcs/vnpcsicon16.png"

properties.Add("vnpcs_eatme", {
	MenuLabel = "Eat me!",
	Order = 999,
	MenuIcon = VNPCs.Icon,
	Filter = function(self, ent, ply)
		if not IsValid(ent) then return false end
		if not IsValid(ply) then return false end
		if not ent.IsDrGNextbot then return false end
		if not ent.Predator then return false end
		if not gamemode.Call("CanProperty", ply, "vnpcs_eatme", ent) then return false end
		return true
	end,
	Action = function(self, ent)
        self:MsgStart()
		net.WriteEntity( ent )
		self:MsgEnd()
	end,
	Receive = function(self, len, ply)
		local ent = net.ReadEntity()

		--[[
			Filter only runs clientside when the menu is built, so the message
			has to be re-validated here. Without this a crafted net message
			could aggro -- or error on -- any entity index a client felt like
			sending. Order matches the stock Facepunch property implementations.
		]]
		if not IsValid(ent) then return end
		if not properties.CanBeTargeted(ent, ply) then return end
		if not self:Filter(ent, ply) then return end

        ent:ClearPatrols()
        ent:SetEntityRelationship(ply, D_HT, 99999)
        ent:SetEnemy(ply)
        ent:SpotEntity(ply)
	end
})

hook.Add("EntityEmitSound", "MuffleVoredSounds", function( sound_info )
	local ent = sound_info.Entity
    if not IsValid(ent) then return end

    --[[
        GetParent() returns a NULL entity when unparented, and reading a field
        off NULL raises "Tried to use a NULL entity!". This hook runs for every
        sound emitted by anything in the game, so that had to be guarded.
    ]]
    local parent = ent:GetParent()
    local vored = ent.Vored or (IsValid(parent) and parent.Vored)
    if not vored then return end

    sound_info.SoundLevel = 60 --distance falloff
    sound_info.DSP = 15 --muffle, uses underwater dsp

    return true
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