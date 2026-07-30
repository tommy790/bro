
-- Define these!
TOOL.Tab = "V-NPCs"
TOOL.Category = "Debug" -- Name of the category
TOOL.Name = "#tool.vnpc_displayinfo.name" -- Name to display. # means it will be translated ( see below )

TOOL.RequiresTraceHit = true

TOOL.Information = {
	{ name = "left"},
}

function TOOL:LeftClick( tr )
	local ent = tr.Entity
	local owner = self:GetOwner()

	if IsValid(ent) and SERVER then
		self:setSelectedEntity(ent)
		return true 
	end
end

function TOOL:getSelectedEntity()
	return self:GetWeapon():GetNWEntity("Selected")
end

function TOOL:setSelectedEntity(ent)
	self:GetWeapon():SetNWEntity("Selected", ent)
end

local function make_inspection_tools(main_img, parent, maxResolution, material)
	local currentZoom = 1
	local currentX, currentY = 0, 0
	local baseSize = 680

	local function update_img()
		currentZoom = math.min(currentZoom, maxResolution/baseSize)
		main_img:SetSize(baseSize * currentZoom, baseSize * currentZoom)
		local zoomBS = (baseSize - (baseSize * currentZoom))/2
		main_img:SetPos(currentX + zoomBS, currentY + zoomBS)
	end

	local seperation = 98
	local left_margin = 10

	local sizeX = 90

	local zoomin = vgui.Create("DButton", parent)
	zoomin:SetText("Zoom in")
	zoomin:SetSize(sizeX, 50)
	zoomin:SetPos(left_margin, 730)
	zoomin.DoClick = function()
		currentZoom = currentZoom + 0.15
		update_img()
	end

	local zoomout = vgui.Create("DButton", parent)
	zoomout:SetText("Zoom out")
	zoomout:SetSize(sizeX, 50)
	zoomout:SetPos(left_margin + seperation, 730)
	zoomout.DoClick = function()
		currentZoom = currentZoom - 0.15
		update_img()
	end

	local left = vgui.Create("DButton", parent)
	left:SetText("Move Left")
	left:SetSize(sizeX, 50)
	left:SetPos(left_margin + seperation * 2, 730)
	left.DoClick = function()
		currentX = currentX + 40 * currentZoom
		update_img()
	end

	local right = vgui.Create("DButton", parent)
	right:SetText("Move Right")
	right:SetSize(sizeX, 50)
	right:SetPos(left_margin + seperation * 3, 730)
	right.DoClick = function()
		currentX = currentX - 40 * currentZoom
		update_img()
	end

	local up = vgui.Create("DButton", parent)
	up:SetText("Move Up")
	up:SetSize(sizeX, 50)
	up:SetPos(left_margin + seperation * 4, 730)
	up.DoClick = function()
		currentY = currentY + 40 * currentZoom
		update_img()
	end

	local down = vgui.Create("DButton", parent)
	down:SetText("Move Down")
	down:SetSize(sizeX, 50)
	down:SetPos(left_margin + seperation * 5, 730)
	down.DoClick = function()
		currentY = currentY - 40 * currentZoom
		update_img()
	end

	local reset = vgui.Create("DButton", parent)
	reset:SetText("Reset")
	reset:SetSize(sizeX, 50)
	reset:SetPos(left_margin + seperation * 6, 730)
	reset.DoClick = function()
		currentZoom = 1
		currentX, currentY = 0, 0
		update_img()
	end

end

local function inspect_material(material)
	local width, height = material:Width(), material:Height()

	local mainFrame = vgui.Create("DFrame")
	mainFrame:SetSize(900, 800)
	mainFrame:Center()
	mainFrame:SetTitle(material:GetName())	-- Title of window
	mainFrame:MakePopup()

	local imageFrame = vgui.Create("DPanel", mainFrame)
	imageFrame:SetSize(680, 680)
	imageFrame:SetPos(10, 30)

	-- Image panel of Dr. Breen
	local main_img = vgui.Create("DImage", imageFrame)	-- Add image to Frame
	main_img:SetSize(680, 680)	-- Size it to 150x150
	

	-- Set material relative to "garrysmod/materials/"

	local scrollPanel = vgui.Create( "DScrollPanel", mainFrame)
	scrollPanel:SetSize(190, 760)
	scrollPanel:SetPos(700, 30)
	scrollPanel:SetBackgroundColor(Color(166,166,166))

	for i,v in pairs(material:GetKeyValues()) do
		local button = scrollPanel:Add( "DButton" )
		local name = i..' = "'..tostring(v)..'"'
		button:SetText( i )
		button:SetTextColor( Color( 114, 114, 114) )
		button:Dock( TOP )
		button:DockMargin( 0, 0, 0, 3 )
		button.DoClick = function()
			SetClipboardText( name )
		end
	end
	print(material:GetTexture("$lightwarptexture"))
	print(material:GetTexture("bumpmap"))
	
	main_img:SetMaterial(material)
	make_inspection_tools(main_img, mainFrame, math.max(width, height), material)

	
end

function TOOL.BuildCPanel( panel )
	panel:ClearControls()

	panel:Help("#tool.vnpc_displayinfo.desc")
	
	local tool = LocalPlayer():GetTool("vnpc_displayinfo")
	if not tool then return end
	
	local ent = tool:getSelectedEntity()
	if not ent or not IsValid(ent) then 
		panel:Help("")
		panel:Help("No NPC is selected.")
		return 
	end

	--[[flexes]]
	panel:Help("")
	panel:Help("Flexes (Codenames, click to copy)")

	local scrollPanel = vgui.Create( "DScrollPanel")
	scrollPanel:SetHeight(350)
	scrollPanel:SetBackgroundColor(Color(166,166,166))

	for i=0, ent:GetFlexNum() - 1 do
		local button = scrollPanel:Add( "DButton" )
		local name = ent:GetFlexName(i)
		button:SetText( name )
		button:SetTextColor( Color( 114, 114, 114) )
		button:Dock( TOP )
		button:DockMargin( 0, 0, 0, 3 )
		button.DoClick = function()
			SetClipboardText( name )
		end
	end

	panel:AddItem(scrollPanel)
	--

	--[[flexes]]
	panel:Help("")
	panel:Help("Body groups (Codenames)")

	local scrollPanel = vgui.Create( "DScrollPanel")
	scrollPanel:SetHeight(200)
	scrollPanel:SetBackgroundColor(Color(166,166,166))

	local tree = vgui.Create("DTree")
	tree.bones = {}
	for i,v in pairs(ent:GetBodyGroups()) do
		local newNode = tree:AddNode(v.name)
		local subs = v.submodels
		for i,v in ipairs(subs) do
			newNode:AddNode(v, "icon16/bullet_blue.png")
		end
	end

	tree:Dock( TOP )
	tree:DockMargin( 0, 0, 0, 1 )
	tree:SetHeight(200)
	scrollPanel:Add(tree)

	panel:AddItem(scrollPanel)
	--

	panel:Help("")
	panel:Help("Materials")

	local material_loader = vgui.Create("DImage")
	material_loader:SetSize(268, 268)
	material_loader:SetBackgroundColor(Color(166,166,166))

	local inspect = scrollPanel:Add( "DButton" )
	inspect:SetText("Inspect")
	inspect.DoClick = function()
		local material_to_inspect = material_loader:GetMaterial()
		if not material_to_inspect then return end

		inspect_material(material_to_inspect)
	end

	local scrollPanel = vgui.Create( "DScrollPanel")
	scrollPanel:SetHeight(200)
	scrollPanel:SetBackgroundColor(Color(166,166,166))
	scrollPanel:DockMargin(0,0,0,4)
	for i,v in pairs(ent:GetMaterials()) do
		local button = scrollPanel:Add( "DButton" )
		button:SetText(v)
		button:SetTextColor( Color( 114, 114, 114) )
		button:Dock( TOP )
		button:DockMargin( 0, 0, 0, 3 )
		button.DoClick = function()
			material_loader:SetImage(v)
		end
	end
	
	panel:AddItem(inspect)
	panel:AddItem(material_loader)
	panel:AddItem(scrollPanel)
end



if ( CLIENT ) then -- We can only use language.Add on client
	language.Add("tool.vnpc_displayinfo.name", "Display Info" ) -- Add translation
	language.Add("tool.vnpc_displayinfo.desc", "Click on NPC to display their Flexes, Bodygroups, and Materials." ) -- Add translation
	language.Add("tool.vnpc_displayinfo.left", "Select NPC" ) -- Add translation

	function TOOL:Initialize()
		self.lastSelected = NULL
		self.lastModel = ""
	end

	function TOOL:Think()
		local ent = self:getSelectedEntity()
		local model = ""
		
		if IsValid(ent) then
			model = ent:GetModel() or ""
		end
		
		if ent == self.lastSelected and model == self.lastModel then
			return
		end
		
		self.lastSelected = ent
		self.lastModel = model
		
		--rebuild CPanel
		local name = "vnpc_displayinfo"
		local panel = controlpanel.Get(name)
		
		if not panel then
			print("Couldn't find " .. name .. " panel!")
			return
		end
	
		self.BuildCPanel(panel)
	end
end