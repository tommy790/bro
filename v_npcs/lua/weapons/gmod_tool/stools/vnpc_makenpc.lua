
-- Define these!
TOOL.Tab = "V-NPCs"
TOOL.Category = "Tools" -- Name of the category
TOOL.Name = "#tool.vnpc_makenpc.name" -- Name to display. # means it will be translated ( see below )

TOOL.LeftClickAutomatic = false 
TOOL.RightClickAutomatic = false 
TOOL.Information = {
	{ name = "left"},
}

TOOL.ClientConVar["name"] = "NAME HERE"
TOOL.ClientConVar["model"] = "MODEL PATH"
TOOL.ClientConVar[ "color_r" ] = "255"
TOOL.ClientConVar[ "color_g" ] = "255"
TOOL.ClientConVar[ "color_b" ] = "255"

TOOL.ClientConVar[ "belly_x" ] = "0"
TOOL.ClientConVar[ "belly_y" ] = "0"
TOOL.ClientConVar[ "belly_z" ] = "0"

TOOL.ClientConVar["scale"] = "1"
TOOL.ClientConVar["health"] = "1"
TOOL.ClientConVar[ "mcolor_r" ] = "255"
TOOL.ClientConVar[ "mcolor_g" ] = "255"
TOOL.ClientConVar[ "mcolor_b" ] = "255"


function TOOL:GetInfo()
	return {
		SpawnHealth = self:GetClientNumber( "health", 100),
		Models = {self:GetClientInfo("model")},
		PrintName = self:GetClientInfo("name"),
		BellyColor = Color(self:GetClientNumber( "color_r", 255 ), self:GetClientNumber( "color_g", 255 ), self:GetClientNumber( "color_b", 255)),
		Belly_Offset = Vector(self:GetClientNumber( "belly_x", 0 ), self:GetClientNumber( "belly_y", 0 ), self:GetClientNumber( "belly_z", 0)),

		ModelScale = self:GetClientNumber( "scale", 1),
		ModelColor = Color(self:GetClientNumber( "mcolor_r", 255 ), self:GetClientNumber( "mcolor_g", 255 ), self:GetClientNumber( "mcolor_b", 255)),
	}
end

function TOOL:LeftClick(tr)
	if ( IsValid( tr.Entity ) && tr.Entity:IsPlayer() ) then return false end

	local info = self:GetInfo()

	local ent = ents.Create("npc_vore_template")
	for i,v in pairs(info) do
		ent[i] = v
	end

	ent:SetPos( tr.HitPos )
	ent:Spawn()
	ent:Activate()

	undo.Create( info.PrintName )
	undo.SetPlayer( self:GetOwner() )
	undo.AddEntity(ent)
	undo.Finish()

	return true 
end

function TOOL:Reload(tr)
	self:updateClient()
	return true
end

function TOOL:getClient()
	return self:GetWeapon():GetNWInt("update")
end

function TOOL:updateClient()
	self:GetWeapon():SetNWInt("update", self:getClient() + 1)
end

local function stringifyValue(v)
    if isstring(v) then
        return string.format("%q", v)

    elseif isnumber(v) or isbool(v) then
        return tostring(v)
	 elseif IsColor(v) then
        return string.format("Color(%d, %d, %d)", v.r, v.g, v.b)
    elseif isvector(v) then
        return string.format("Vector(%g, %g, %g)", v.x, v.y, v.z)
    elseif istable(v) then
        -- detect array form
        local isArray = true
        local idx = 1
        for k,_ in pairs(v) do
            if k ~= idx then
                isArray = false
                break
            end
            idx = idx + 1
        end

        if isArray then
            local parts = {}
            for _, item in ipairs(v) do
                table.insert(parts, stringifyValue(item))
            end
            return "{ " .. table.concat(parts, ", ") .. " }"
        else
            -- not needed unless your info table contains nested tables
            return "\"<nested table>\""
        end
	end
   

    return "\"<unsupported>\""
end

local function turnTableIntoCode(tbl)
	local lines = {
		'--This is an auto-generated npc!--',
		'if not DrGBase then return end',
		'ENT.Base = "npc_vore_template"',
		'ENT.Category = "Vore"',
	}

    for k, v in pairs(tbl) do
        table.insert(lines, "ENT."..k .. " = " .. stringifyValue(v))
    end

	table.Add(lines, {
		"AddCSLuaFile()",
		"DrGBase.AddNextbot(ENT)"
	})

    return table.concat(lines, "\n")
end

local function do_popup(text, title)
	local mainFrame = vgui.Create("DFrame")
	mainFrame:SetSize(300, 70)
	mainFrame:Center()
	mainFrame:SetTitle(title)	-- Title of window
	mainFrame:MakePopup()

	local _text = vgui.Create("DLabel", mainFrame)
	_text:SetText(text)
	_text:SetSize(290,30)
	_text:SetPos(10, 30)
end

local function save_to_file(code, info)
	local filename = "generated_npc_"..string.lower(info.PrintName)..".lua"
	local path = "entities/"..filename
	local test = file.Exists(path, "LUA")
	print(path)

	if test then
		print("ERROR ALREADY EXISTS BRO")
		do_popup("File with same name already exists")
		return 
	end
	print("ok trying to write?")
	local result = file.Write("helloworld.txt", code)
	print(result)
end

function TOOL.BuildCPanel( CPanel )
	CPanel:ClearControls()

    CPanel:Help("THIS IS VERY UNFINISHED AND EXPERIMENTAL!!!")
    CPanel:Help("")

	local clipboard = CPanel:Button("Copy code to clipboard")
	clipboard.DoClick = function()
		local tool = LocalPlayer():GetTool("vnpc_makenpc")
		if not tool then return end

		local info = tool:GetInfo()
		local code = turnTableIntoCode(info)
		SetClipboardText(code)
		do_popup("Copied to clipboard.", "Copied!")
	end
	--[[
	local save = CPanel:Button("Save to file")
	save.DoClick = function()
		local tool = LocalPlayer():GetTool("vnpc_makenpc")
		if not tool then return end

		local info = tool:GetInfo()
		local code = turnTableIntoCode(info)

		save_to_file(code, info)
		do_popup("Not finished", "lol")
	end
	]]
	CPanel:TextEntry( "Name", "vnpc_makenpc_name" )
	CPanel:TextEntry( "Model", "vnpc_makenpc_model" )

	CPanel:NumSlider("Belly Pos X", "vnpc_makenpc_belly_x", -10, 10, 1)
	CPanel:NumSlider("Belly Pos Y", "vnpc_makenpc_belly_y", -10, 10, 1)
	CPanel:NumSlider("Belly Pos Z", "vnpc_makenpc_belly_z", -10, 10, 1)
	CPanel:ColorPicker( "Belly Color", "vnpc_makenpc_color_r", "vnpc_makenpc_color_g", "vnpc_makenpc_color_b" )

	CPanel:NumSlider("Spawn health", "vnpc_makenpc_health", 1, 9999, 0)
	CPanel:NumSlider("Model Scale", "vnpc_makenpc_scale", 0.1, 10, 2)
	CPanel:ColorPicker( "Model Color", "vnpc_makenpc_mcolor_r", "vnpc_makenpc_mcolor_g", "vnpc_makenpc_mcolor_b" )



end

if ( CLIENT ) then -- We can only use language.Add on client
	language.Add("tool.vnpc_makenpc.name", "Make NPC" ) -- Add translation
	language.Add("tool.vnpc_makenpc.desc", "Set npc options in menu, click to spawn it." ) -- Add translation
	language.Add("tool.vnpc_makenpc.left", "Spawn NPC" ) -- Add translation

	function TOOL:Initialize()
		net.Receive("refresh_cpanel_makenpc", function()
			local name = "vnpc_makenpc"
			local panel = controlpanel.Get(name)
			if not panel then
				print("Couldn't find " .. name .. " panel!")
				return
			end
			self.BuildCPanel(panel)
		end)
	end

	function TOOL:Think()
		self.current = self.current or self:getClient()

		if self.current ~= self:getClient() then
			self.current = self:getClient()

			local name = "vnpc_makenpc"
			local panel = controlpanel.Get(name)
			
			if not panel then
				print("Couldn't find " .. name .. " panel!")
				return
			end
		
			self.BuildCPanel(panel)
		end
	end
end