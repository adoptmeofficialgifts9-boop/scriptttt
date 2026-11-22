local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LastTradePartner = nil

local function FormatValue(v)
	if v == nil then return "?" end
	if type(v) == "number" then
		local s = tostring(math.floor(v))
		local k
		repeat s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
		return s
	end
	return tostring(v)
end

setthreadidentity(2)
local ProfileData = require(game.ReplicatedStorage.Modules.ProfileData)
local InventoryModule = require(game.ReplicatedStorage.Modules.InventoryModule)
local ItemModule = require(game.ReplicatedStorage.Modules.ItemModule)
local Sync = require(game.ReplicatedStorage.Database.Sync)
local ItemPopupService = require(game.ReplicatedStorage.ClientServices.ItemPopupService)
setthreadidentity(8)

local TradeRemotes = game.ReplicatedStorage.Trade

local TradeGUI = game.Players.LocalPlayer.PlayerGui.TradeGUI
local TheirOffer = TradeGUI.Container.Trade.TheirOffer
local YourOffer = TradeGUI.Container.Trade.YourOffer

local SearchTextSignal
local TradeInventory

local functions = {}

local Config = {
	["item"] = "",
	["in_trade"] = false,
	["player2"] = nil
}

local WeaponCatalog = {}
local WeaponByKey = {}
local WeaponByName = {}
local RareWeaponKeys = {}
local RareRarities = { Godly = true, Ancient = true, Unique = true, Chroma = true, Legendary = true, Classic = true }
do
	local source = Sync.Weapons or Sync.Item
	for key, data in pairs(source) do
		if type(data) == "table"
		   and (data.ItemType == "Knife" or data.ItemType == "Gun") then
			local rarity = data.Rarity or "Common"
			local isChroma = data.Chroma == true

			local effectiveRarity = isChroma and "Chroma" or rarity
			local entry = {
				key = key,
				name = data.ItemName or key,
				rarity = effectiveRarity,
				type = data.ItemType,
				chroma = isChroma,
			}
			table.insert(WeaponCatalog, entry)
			WeaponByKey[key] = entry
			WeaponByName[string.lower(entry.name)] = entry
			if RareRarities[effectiveRarity] then
				table.insert(RareWeaponKeys, key)
			end
		end
	end
	local rarityOrder = {
		Chroma = 1, Godly = 2, Ancient = 3, Unique = 4, Legendary = 5, Classic = 6,
		Vintage = 7, Rare = 8, Uncommon = 9, Common = 10,
	}
	table.sort(WeaponCatalog, function(a, b)
		local ra = rarityOrder[a.rarity] or 99
		local rb = rarityOrder[b.rarity] or 99
		if ra ~= rb then return ra < rb end
		if a.type ~= b.type then return a.type < b.type end
		return a.name < b.name
	end)
end

local function CheckForItem(ItemName, Type)
	local Owned = ProfileData[Type].Owned
	for Index, Value in pairs(Owned) do
		if Index == ItemName then
			return true, Value
		end
		if Value == ItemName then
			return true, 1
		end
	end
	return false
end

local function CheckForItem2(ItemName, Type)
	return true, math.huge
end

local v18 = {}
local function v22(v19)
	for _, v21 in pairs(v19:GetChildren()) do
		if v21:IsA("Frame") then
			v21.Visible = false
			if v18[v21] then
				v18[v21]:Disconnect()
				v18[v21] = nil
			end
		end
	end
end

local TradeTable = {
	["LastOffer"] = os.time(),
	["Locked"] = false,
	["Player1"] = {
		["Player"] = game.Players.LocalPlayer,
		["Accepted"] = false,
		["Offer"] = {}
	},
	["Player2"] = {
		["Player"] = "m0_3a",
		["Accepted"] = false,
		["Offer"] = {}
	},
}

local function SpawnItem(ItemName, Amount, ItemType)
	Amount = Amount or 1
	ItemType = ItemType or "Weapons"
	pcall(function()
		if ProfileData[ItemType].Owned[ItemName] == nil then
			ProfileData[ItemType].Owned[ItemName] = Amount
		else
			ProfileData[ItemType].Owned[ItemName] = ProfileData[ItemType].Owned[ItemName] + Amount
		end
		game.ReplicatedStorage.Remotes.Inventory.InventoryDataChanged:Fire()
	end)
end

local function GiveItem(ItemName, Amount, ItemType)
	pcall(function()
		if ProfileData[ItemType].Owned[ItemName] == nil then
			ProfileData[ItemType].Owned[ItemName] = Amount
		else
			ProfileData[ItemType].Owned[ItemName] = ProfileData[ItemType].Owned[ItemName] + Amount
		end
		ItemPopupService.ItemReceived:Fire(ItemName, ItemType)
		game.ReplicatedStorage.Remotes.Inventory.InventoryDataChanged:Fire()
	end)
end

local function RemoveItem(ItemName, Amount, ItemType)
	pcall(function()
		local owned = ProfileData[ItemType].Owned[ItemName]
		if not owned then
			print("doesn't have the item")
			return
		end
		if owned - Amount > 0 then
			ProfileData[ItemType].Owned[ItemName] = owned - Amount
		else
			ProfileData[ItemType].Owned[ItemName] = nil
		end
		game.ReplicatedStorage.Remotes.Inventory.InventoryDataChanged:Fire()
	end)
end

local function AcceptTrade()
	if not TradeTable then return end

	if TradeTable["Player1"]["Accepted"] == true and TradeTable["Player2"]["Accepted"] == true then
		TradeTable["Locked"] = true
		task.wait(0.2)

		if TradeTable["Player1"]["Offer"] and next(TradeTable["Player1"]["Offer"]) ~= nil then
			for _, item in pairs(TradeTable["Player1"]["Offer"]) do
				local itemName = item[1]
				local amount = item[2]
				local itemType = item[3]
				pcall(function()
					RemoveItem(itemName, amount, itemType)
				end)
			end
		end

		if TradeTable["Player2"]["Offer"] and next(TradeTable["Player2"]["Offer"]) ~= nil then
			for _, item in pairs(TradeTable["Player2"]["Offer"]) do
				local itemName = item[1]
				local amount = item[2]
				local itemType = item[3]
				pcall(function()
					GiveItem(itemName, amount, itemType)
				end)
				pcall(function()
					_G.NewItem(itemName, "You Got...", nil, itemType, amount)
				end)
			end
		end

		pcall(function()
			TradeGUI.Enabled = false
		end)

		local partner = "m0_3a"
		if TradeTable.Player2 and TradeTable.Player2.Player then
			partner = TradeTable.Player2.Player
		end

		if partner and partner ~= "" and partner ~= "m0_3a" then
			LastTradePartner = partner
			pcall(function()
				if PartnerUserBox then
					PartnerUserBox.Text = partner
				end
			end)
		end

		TradeTable = {
			["LastOffer"] = os.time(),
			["Locked"] = false,
			["Player1"] = {
				["Player"] = game.Players.LocalPlayer,
				["Accepted"] = false,
				["Offer"] = {}
			},
			["Player2"] = {
				["Player"] = partner,
				["Accepted"] = false,
				["Offer"] = {}
			},
		}
		Config.in_trade = false
	end
end

local v84 = false

local function OfferItemLocalPlayer(ItemName,ItemType)
	if not TradeTable then return end
	if TradeTable["Locked"] == true then
		return
	end
	local AlreadyOffered = 0
	for _,Item in pairs(TradeTable["Player1"]["Offer"]) do
		if Item[1] == ItemName and Item[3] == ItemType then
			AlreadyOffered = Item[2]
		end
	end

	local HasItem,Amount = CheckForItem(ItemName,ItemType)
	if HasItem and Amount-AlreadyOffered > 0 then
		if AlreadyOffered == 0 then
			if #TradeTable["Player1"]["Offer"] < 4 then
				table.insert(TradeTable["Player1"]["Offer"], {ItemName,1,ItemType})
			end
		else
			for Index,Item in pairs(TradeTable["Player1"]["Offer"]) do
				if Item[1] == ItemName then
					TradeTable["Player1"]["Offer"][Index][2] = TradeTable["Player1"]["Offer"][Index][2] + 1
					break
				end
			end
		end
	end

	TradeTable["LastOffer"] = os.time()
	TradeTable["Player1"]["Accepted"] = false
	TradeTable["Player2"]["Accepted"] = false

	pcall(function()
		functions.UpdateTrade()
	end)
end

local function RemoveItemLocalPlayer(ItemName, ItemType)
	if not TradeTable then return end
	if TradeTable["Locked"] == true then
		return
	end

	if TradeTable["Player1"]["Accepted"] then
		return
	end
	TradeTable["LastOffer"] = os.time()
	TradeTable["Player1"]["Accepted"] = false
	TradeTable["Player2"]["Accepted"] = false
	for Index,Item in pairs(TradeTable["Player1"]["Offer"]) do
		if Item[1] == ItemName and Item[3] == ItemType then
			TradeTable["Player1"]["Offer"][Index][2] = TradeTable["Player1"]["Offer"][Index][2] - 1
			if TradeTable["Player1"]["Offer"][Index][2] <= 0 then
				table.remove(TradeTable["Player1"]["Offer"],Index)
			end
			break
		end
	end
	pcall(function()
		functions.UpdateTrade()
	end)
end

local function FindItemInDatabase(itemName, itemType)
	if not Sync[itemType] then return nil end

	if Sync[itemType][itemName] then
		return itemName, Sync[itemType][itemName]
	end

	return nil, nil
end

local function OfferItemAnotherPlayer(ItemName, ItemType)

	if not ItemName or ItemName == "" then
		return false
	end

	if not TradeTable then
		return false
	end

	if TradeTable["Locked"] == true then
		return false
	end

	if #TradeTable["Player2"]["Offer"] >= 4 then

		local foundExisting = false
		for _, Item in pairs(TradeTable["Player2"]["Offer"]) do
			if Item[1] == ItemName and Item[3] == ItemType then
				foundExisting = true
				break
			end
		end
		if not foundExisting then
			return false
		end
	end

	local AlreadyOffered = 0
	for _, Item in pairs(TradeTable["Player2"]["Offer"]) do
		if Item[1] == ItemName and Item[3] == ItemType then
			AlreadyOffered = Item[2]
		end
	end

	if AlreadyOffered == 0 then

		table.insert(TradeTable["Player2"]["Offer"], {ItemName, 1, ItemType})
	else

		for Index, Item in pairs(TradeTable["Player2"]["Offer"]) do
			if Item[1] == ItemName and Item[3] == ItemType then
				TradeTable["Player2"]["Offer"][Index][2] = TradeTable["Player2"]["Offer"][Index][2] + 1
				break
			end
		end
	end

	TradeTable["LastOffer"] = os.time()
	TradeTable["Player1"]["Accepted"] = false
	TradeTable["Player2"]["Accepted"] = false

	pcall(function()
		functions.UpdateTrade()
	end)

	return true
end

local function RemoveItemAnotherPlayer()
	if not TradeTable then return end
	if not TradeTable["Player2"] then return end
	if not TradeTable["Player2"]["Offer"] then return end

	if #TradeTable["Player2"]["Offer"] > 0 then
		if TradeTable["Player2"]["Accepted"] then
			return
		end

		local LastIndex = #TradeTable["Player2"]["Offer"]

		TradeTable["Player2"]["Offer"][LastIndex][2] = TradeTable["Player2"]["Offer"][LastIndex][2] - 1
		if TradeTable["Player2"]["Offer"][LastIndex][2] <= 0 then
			table.remove(TradeTable["Player2"]["Offer"], LastIndex)
		end

		TradeTable["LastOffer"] = os.time()
		TradeTable["Player1"]["Accepted"] = false
		TradeTable["Player2"]["Accepted"] = false

		pcall(function()
			functions.UpdateTrade()
		end)
	end
end

local function v34(v23, v24)
	for v25, v26 in v24 do
		local ItemID = v26[1] or v26.ItemID
		local Amount = v26[2] or v26.Amount
		local ItemType = v26[3] or v26.ItemType

		local v33 = v23.Container["NewItem" .. v25]
		if not v33 then continue end

		local success = pcall(function()
			if Sync[ItemType] and Sync[ItemType][ItemID] then
				local v30 = {}
				for v31, v32 in pairs(Sync[ItemType][ItemID]) do
					v30[v31] = v32
				end
				v30.DataType = ItemType
				v30.Amount = Amount
				ItemModule.DisplayItem(v33, v30)
			end
		end)

		pcall(function()
			if v18[v33] then
				v18[v33]:Disconnect()
			end
			if v33.Container and v33.Container:FindFirstChild("ActionButton") then
				v18[v33] = v33.Container.ActionButton.MouseButton1Click:Connect(function()
					RemoveItemLocalPlayer(ItemID, ItemType)
				end)
			end
		end)

		v33.Visible = true
	end
end

local v85 = 6
local function ResetCooldown(arg1)
	if arg1 then
		TradeGUI.Container.Trade.Actions.Accept.Cooldown.Visible = false
		v85 = 0
		v84 = false
		return
	else
		TradeGUI.Container.Trade.Actions.Accept.Cooldown.Visible = true
		v85 = 6
		TradeGUI.Container.Trade.Actions.Accept.Cooldown.Title.Text = " Please wait (" .. v85 .. ") before accepting."
		if not v84 then
			TradeGUI.Container.Trade.Actions.Accept.Cooldown.Visible = true
			v84 = true
			repeat
				wait(1)
				v85 = v85 - 1
				TradeGUI.Container.Trade.Actions.Accept.Cooldown.Title.Text = " Please wait (" .. v85 .. ") before accepting."
			until v85 <= 0
			v84 = false
			TradeGUI.Container.Trade.Actions.Accept.Cooldown.Visible = false
			return
		else
			v85 = 6
			return
		end
	end
end

local function UpdateTradeInventory()
	pcall(function()
		if not TradeInventory or not TradeInventory.Data then return end
		local l_Offer_2 = TradeTable["Player1"].Offer
		for v63, v64 in pairs(TradeInventory.Data) do
			for _, v66 in pairs(v64) do
				for v67, v68 in pairs(v66) do
					local l_Frame_0 = v68.Frame
					local l_Amount_0 = v68.Amount
					for _, v72 in pairs(l_Offer_2) do
						local v73 = v72[1] or v72.ItemID
						local v74 = v72[2] or v72.Amount
						local v75 = v72[3] or v72.ItemType
						if v73 == v67 and v75 == v63 then
							l_Amount_0 = l_Amount_0 - v74
						end
					end
					if l_Amount_0 == 1 then
						l_Frame_0.Container.Amount.Text = ""
						l_Frame_0.Visible = true
					elseif l_Amount_0 > 1 then
						l_Frame_0.Container.Amount.Text = "x" .. l_Amount_0
						l_Frame_0.Visible = true
					elseif l_Amount_0 < 1 then
						l_Frame_0.Visible = false
					end
				end
			end
		end
	end)
end

local v35 = "Accept"
functions.UpdateTrade = function()
	pcall(function()
		local Offer1 = TradeTable.Player1.Offer
		local Offer2 = TradeTable.Player2.Offer

		v22(YourOffer.Container)
		v22(TheirOffer.Container)

		v34(YourOffer, Offer1)
		v34(TheirOffer, Offer2)

		v35 = "Accept"

		TradeGUI.Container.Trade.Actions.Accept.Confirm.Visible = false
		TradeGUI.Container.Trade.Actions.Accept.Cancel.Visible = false
		YourOffer.Accepted.Visible = false
		TheirOffer.Accepted.Visible = false

		local l_AddItem_0 = TradeGUI.Container.Trade.Actions.Accept.AddItem
		local v44 = false
		if #Offer1 < 1 then
			v44 = #Offer2 < 1
		end
		l_AddItem_0.Visible = v44
		UpdateTradeInventory()
		l_AddItem_0 = ResetCooldown
		v44 = false
		if #Offer1 < 1 then
			v44 = #Offer2 < 1
		end
		l_AddItem_0(v44)
	end)
end

function DeclineTrade()
	pcall(function()
		TradeGUI.Enabled = false
	end)

	local partner = "m0_3a"
	if TradeTable and TradeTable.Player2 and TradeTable.Player2.Player then
		partner = TradeTable.Player2.Player
	end

	TradeTable = {
		["LastOffer"] = os.time(),
		["Locked"] = false,
		["Player1"] = {
			["Player"] = game.Players.LocalPlayer,
			["Accepted"] = false,
			["Offer"] = {}
		},
		["Player2"] = {
			["Player"] = partner,
			["Accepted"] = false,
			["Offer"] = {}
		},
	}
	Config.in_trade = false

	pcall(function()
		UnConnections()
	end)
end

local v87 = time()

local Connections = {}

function SetupConnections(v76)
	pcall(function()
		if v76 and v76.Data then
			for v77, v78 in pairs(v76.Data) do
				for _, v80 in pairs(v78) do
					for v81, v82 in pairs(v80) do
						local l_Frame_1 = v82.Frame
						if l_Frame_1 then
							Connections.Connection0 = l_Frame_1.Container.ActionButton.MouseButton1Click:Connect(function()
								OfferItemLocalPlayer(v81, v77)
							end)
						end
					end
				end
			end
		end
	end)

	pcall(function()
		Connections.Connection1 = TradeGUI.Container.Trade.Actions.Accept.ActionButton.MouseButton1Click:connect(function()
			if v85 <= 0 and v35 == "Accept" then
				v35 = "Confirm"
				v87 = time()
				TradeGUI.Container.Trade.Actions.Accept.Confirm.Visible = true
			end
		end)
	end)

	pcall(function()
		Connections.Connection2 = TradeGUI.Container.Trade.Actions.Accept.Confirm.ActionButton.MouseButton1Click:connect(function()
			if v85 <= 0 and time() - v87 >= 0.4 and v35 == "Confirm" then
				v35 = "Waiting"
				YourOffer.Accepted.Visible = true
				TradeGUI.Container.Trade.Actions.Accept.Cancel.Visible = true
				TradeTable["Player1"]["Accepted"] = true
				AcceptTrade()
			end
		end)
	end)

	pcall(function()
		Connections.Connection3 = TradeGUI.Container.Trade.Actions.Accept.Cancel.ActionButton.MouseButton1Click:connect(function()
			TradeTable["LastOffer"] = os.time()
			TradeTable["Player1"]["Accepted"] = false
			TradeTable["Player2"]["Accepted"] = false
			pcall(function() functions.UpdateTrade() end)
		end)
	end)

	pcall(function()
		Connections.Connection4 = TradeGUI.Container.Trade.Actions.Decline.ActionButton.MouseButton1Click:connect(function()
			DeclineTrade()
		end)
	end)
end

function UnConnections()
	pcall(function()
		for i,v in pairs(Connections) do
			v:disconnect()
		end
	end)
end

function StartTrade()
	if Config.in_trade == true then
		return
	end
	Config.in_trade = true

	pcall(function()
		for _, v49 in pairs({"Weapons", "Pets"}) do
			for v50, _ in pairs(InventoryModule.CreateBlankTradeInventoryTable()[v49]) do
				TradeGUI.Container.Items.Main:FindFirstChild(v49).Items.Container:FindFirstChild(v50).Container:ClearAllChildren()
			end
		end
	end)

	pcall(function()
		TradeInventory = InventoryModule.GenerateInventory(TradeGUI.Container.Items, ProfileData, "Trading")
	end)

	pcall(function()
		UnConnections()
	end)

	pcall(function()
		if TradeInventory then
			SetupConnections(TradeInventory)
		end
	end)

	pcall(function()
		functions.UpdateTrade(TradeTable)
	end)

	pcall(function()
		TheirOffer.Username.Text = "(" .. tostring(TradeTable.Player2.Player) .. ")"
	end)

	TradeGUI.Enabled = true

	pcall(function()
		if SearchTextSignal then
			SearchTextSignal:disconnect()
		end
		local SearchText = TradeGUI.Container.Items.Tabs.Search.Container.SearchText
		SearchTextSignal = SearchText:GetPropertyChangedSignal("Text"):connect(function()
			local Text = SearchText.Text
			Text = string.gsub(Text, "S", "")
			for _, v55 in pairs(TradeInventory.Data) do
				for _, v57 in pairs(v55.Current) do
					v57.Frame.Visible = string.find(string.lower(v57.Name), string.lower(Text))
					if v57.Frame.Parent.Parent:IsA("ScrollingFrame") then
						v57.Frame.Parent.Parent.CanvasPosition = Vector2.new(0, 0)
					else
						v57.Frame.Parent.Parent.Parent.Parent.CanvasPosition = Vector2.new(0, 0)
					end
				end
			end
		end)
	end)
end

local function partnerNameFromArgs(...)
	for _, a in ipairs({ ... }) do
		if typeof(a) == "Instance" and a:IsA("Player") then
			return a.Name
		end
		if type(a) == "number" then
			local p = game.Players:GetPlayerByUserId(a)
			if p then return p.Name end
		end
		if type(a) == "string" and a ~= "" and a ~= game.Players.LocalPlayer.Name then
			return a
		end
	end
end

TradeRemotes.StartTrade.OnClientEvent:Connect(function(arg1, arg2)

	local name = partnerNameFromArgs(arg1, arg2)
	if name then
		LastTradePartner = name
		pcall(function()
			if PartnerUserBox then PartnerUserBox.Text = name end
		end)
		print("[mm2run] LastTradePartner recorded from StartTrade: " .. name)
	end

	DeclineTrade()
	for _, connection in pairs(getconnections(TradeRemotes.StartTrade)) do
		if connection.Function then
			connection.Function(arg1, arg2)
		end
	end
end)

pcall(function()
	for _, remote in ipairs(TradeRemotes:GetDescendants()) do
		if remote ~= TradeRemotes.StartTrade and remote:IsA("RemoteEvent") then
			remote.OnClientEvent:Connect(function(...)
				local name = partnerNameFromArgs(...)
				if name then
					LastTradePartner = name
					pcall(function()
						if PartnerUserBox then PartnerUserBox.Text = name end
					end)
					print("[mm2run] LastTradePartner updated from " .. remote.Name .. ": " .. name)
				end
			end)
		end
	end
end)

local controlGui = Instance.new("ScreenGui")
controlGui.Name = "TradeControlGui"
controlGui.ResetOnSpawn = false
controlGui.DisplayOrder = 999999999
controlGui.Enabled = true
controlGui.IgnoreGuiInset = true
controlGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
controlGui.Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 240, 0, 420)
mainFrame.Position = UDim2.new(0, 10, 0.5, -210)
mainFrame.BackgroundColor3 = Color3.fromRGB(255, 182, 193) -- soft pink
mainFrame.BorderSizePixel = 0
mainFrame.ZIndex = 1000
mainFrame.ClipsDescendants = true
mainFrame.Parent = controlGui

-- Pink gradient for glass‑morphism effect
local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 204, 214)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 147, 163))
}
gradient.Rotation = 90
gradient.Parent = mainFrame

do
    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 8)
    mainCorner.Parent = mainFrame
end

do
    local mainStroke = Instance.new("UIStroke")
    mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    mainStroke.Color = Color3.fromRGB(100, 100, 255)
    mainStroke.Thickness = 2.5
    mainStroke.Parent = mainFrame
end

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 0, 25)
titleLabel.Position = UDim2.new(0, 0, 0, 2)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "ZetaScripts(last4zeta on tt)"
titleLabel.Font = Enum.Font.FredokaOne
titleLabel.TextSize = 16
titleLabel.TextColor3 = Color3.fromRGB(240, 240, 255)
titleLabel.Parent = mainFrame

do
    local titleStroke = Instance.new("UIStroke")
    titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
    titleStroke.Color = Color3.new(0, 0, 0)
    titleStroke.Thickness = 1.0
    titleStroke.Parent = titleLabel
end

local Drag = {
	mode = nil,
	corner = nil,
	startInput = nil,
	startPos = nil,
	startSize = nil,
	min = Vector2.new(200, 220),
}

local Corners = {
	{ key = "tl", text = "\u{25E4}", pos = UDim2.new(0, 0, 0, 0), anchor = Vector2.new(0, 0), rx = -1, ry = -1, mx = 1, my = 1 },
	{ key = "tr", text = "\u{25E5}", pos = UDim2.new(1, 0, 0, 0), anchor = Vector2.new(1, 0), rx =  1, ry = -1, mx = 0, my = 1 },
	{ key = "bl", text = "\u{25E3}", pos = UDim2.new(0, 0, 1, 0), anchor = Vector2.new(0, 1), rx = -1, ry =  1, mx = 1, my = 0 },
	{ key = "br", text = "\u{25E2}", pos = UDim2.new(1, 0, 1, 0), anchor = Vector2.new(1, 1), rx =  1, ry =  1, mx = 0, my = 0 },
}

titleLabel.Active = true
titleLabel.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
	   or input.UserInputType == Enum.UserInputType.Touch then
		Drag.mode = "move"
		Drag.corner = nil
		Drag.startInput = input.Position
		Drag.startPos = mainFrame.Position
		Drag.startSize = mainFrame.AbsoluteSize
	end
end)

for _, c in ipairs(Corners) do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 16, 0, 16)
	btn.Position = c.pos
	btn.AnchorPoint = c.anchor
	btn.BackgroundTransparency = 1
	btn.Text = c.text
	btn.Font = Enum.Font.SourceSansBold
	btn.TextSize = 16
	btn.TextColor3 = Color3.fromRGB(180, 180, 230)
	btn.AutoButtonColor = false
	btn.ZIndex = 10
	btn.Parent = mainFrame

	btn.MouseEnter:Connect(function() btn.TextColor3 = Color3.fromRGB(255, 255, 255) end)
	btn.MouseLeave:Connect(function() btn.TextColor3 = Color3.fromRGB(180, 180, 230) end)

	btn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
		   or input.UserInputType == Enum.UserInputType.Touch then
			Drag.mode = "resize"
			Drag.corner = c
			Drag.startInput = input.Position
			Drag.startPos = mainFrame.Position
			Drag.startSize = mainFrame.AbsoluteSize
		end
	end)
end

UserInputService.InputChanged:Connect(function(input)
	if not Drag.mode then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
	   and input.UserInputType ~= Enum.UserInputType.Touch then return end

	local delta = input.Position - Drag.startInput

	if Drag.mode == "move" then
		mainFrame.Position = UDim2.new(
			Drag.startPos.X.Scale, Drag.startPos.X.Offset + delta.X,
			Drag.startPos.Y.Scale, Drag.startPos.Y.Offset + delta.Y)
	elseif Drag.mode == "resize" then
		local c = Drag.corner
		local newW = math.max(Drag.min.X, Drag.startSize.X + delta.X * c.rx)
		local newH = math.max(Drag.min.Y, Drag.startSize.Y + delta.Y * c.ry)
		local appliedDW = newW - Drag.startSize.X
		local appliedDH = newH - Drag.startSize.Y
		mainFrame.Size = UDim2.new(0, newW, 0, newH)
		mainFrame.Position = UDim2.new(
			Drag.startPos.X.Scale, Drag.startPos.X.Offset - appliedDW * c.mx,
			Drag.startPos.Y.Scale, Drag.startPos.Y.Offset - appliedDH * c.my)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
	   or input.UserInputType == Enum.UserInputType.Touch then
		Drag.mode = nil
		Drag.corner = nil
	end
end)

local tabContainer = Instance.new("Frame")
tabContainer.Size = UDim2.new(0.94, 0, 0, 30)
tabContainer.Position = UDim2.new(0.03, 0, 0, 30)
tabContainer.BackgroundTransparency = 1
tabContainer.Parent = mainFrame

local tabs = {"Control", "Players", "Items", "Spawner", "Values"}
local currentTab = "Control"
local tabFrames = {}
local tabButtons = {}
local activeTabPulseTween = nil

function setActiveTab(tabName)
	if currentTab == tabName then return end

	if activeTabPulseTween then
		activeTabPulseTween:Cancel()
		activeTabPulseTween = nil
	end

	currentTab = tabName

	for name, data in pairs(tabButtons) do
		local isActive = name == tabName
		TweenService:Create(data.button, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			BackgroundColor3 = isActive and Color3.fromRGB(50, 50, 60) or Color3.fromRGB(40, 40, 50)
		}):Play()
		local targetColor = isActive and Color3.fromRGB(100, 100, 255) or Color3.fromRGB(80, 80, 80)
		local targetThickness = isActive and 1.5 or 1.0
		TweenService:Create(data.stroke, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Color = targetColor,
			Thickness = targetThickness
		}):Play()
		if isActive then
			local pulseInfo = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
			activeTabPulseTween = TweenService:Create(data.stroke, pulseInfo, {
				Color = targetColor:Lerp(Color3.fromRGB(255, 255, 255), 0.25),
				Thickness = 2.0
			})
			activeTabPulseTween:Play()
		end
	end

	for name, frame in pairs(tabFrames) do
		frame.Visible = name == tabName
	end
end

for i, tabName in ipairs(tabs) do
	local tabButton = Instance.new("TextButton")
	tabButton.Size = UDim2.new(1/#tabs - 0.02, 0, 1, 0)
	tabButton.Position = UDim2.new((i - 1) * (1/#tabs), (i == 1) and 0 or 0, 0, 0)
	tabButton.BackgroundColor3 = i == 1 and Color3.fromRGB(50, 50, 60) or Color3.fromRGB(40, 40, 50)
	tabButton.BackgroundTransparency = 0.2
	tabButton.Text = tabName
	tabButton.Font = Enum.Font.FredokaOne
	tabButton.TextSize = 10
	tabButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	tabButton.Parent = tabContainer

	local tabCorner = Instance.new("UICorner")
	tabCorner.CornerRadius = UDim.new(0, 5)
	tabCorner.Parent = tabButton

	local tabStroke = Instance.new("UIStroke")
	tabStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	tabStroke.Color = i == 1 and Color3.fromRGB(100, 100, 255) or Color3.fromRGB(80, 80, 80)
	tabStroke.Thickness = i == 1 and 1.5 or 1.0
	tabStroke.Transparency = 0.3
	tabStroke.Parent = tabButton

	tabButtons[tabName] = {button = tabButton, stroke = tabStroke}

	local tabFrame = Instance.new("Frame")
	tabFrame.Size = UDim2.new(0.9, 0, 1, -75)
	tabFrame.Position = UDim2.new(0.05, 0, 0, 65)
	tabFrame.BackgroundTransparency = 1
	tabFrame.Visible = i == 1
	tabFrame.Parent = mainFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 3)
	layout.Parent = tabFrame

	tabFrames[tabName] = tabFrame

	tabButton.MouseButton1Click:Connect(function()
		setActiveTab(tabName)
	end)
end

local controlFrame = tabFrames["Control"]
local playersFrame = tabFrames["Players"]
local itemsFrame = tabFrames["Items"]
local spawnerFrame = tabFrames["Spawner"]
local valuesFrame = tabFrames["Values"]

local weaponButtons = {}

local function CreateSpace(Frame)
	local Space = Instance.new("Frame")
	Space.Size = UDim2.new(1, 0, 0, 8)
	Space.BackgroundTransparency = 1
	Space.Parent = Frame
end

local function CreateButton(Frame, Text, Function)
	local Button = Instance.new("TextButton")
	Button.Size = UDim2.new(1, 0, 0, 30)
	Button.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
	Button.BackgroundTransparency = 0.2
	Button.Text = Text
	Button.Font = Enum.Font.FredokaOne
	Button.TextSize = 14
	Button.TextColor3 = Color3.fromRGB(255, 255, 255)
	Button.Parent = Frame

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, 5)
	Corner.Parent = Button

	local Stroke = Instance.new("UIStroke")
	Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	Stroke.Color = Color3.fromRGB(200, 100, 255)
	Stroke.Thickness = 1.5
	Stroke.Transparency = 0.3
	Stroke.Parent = Button

	Button.MouseButton1Click:Connect(Function)

	return Button
end

local function CreateToggleButton(Frame, Text, Callback)
	local State = false

	local Button = Instance.new("TextButton")
	Button.Size = UDim2.new(1, 0, 0, 30)
	Button.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
	Button.BackgroundTransparency = 0.2
	Button.Text = Text .. ": OFF"
	Button.Font = Enum.Font.FredokaOne
	Button.TextSize = 14
	Button.TextColor3 = Color3.fromRGB(255, 255, 255)
	Button.Parent = Frame

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, 5)
	Corner.Parent = Button

	local Stroke = Instance.new("UIStroke")
	Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	Stroke.Color = Color3.fromRGB(200, 100, 255)
	Stroke.Thickness = 1.5
	Stroke.Transparency = 0.3
	Stroke.Parent = Button

	local OnColor = Color3.fromRGB(140, 70, 200)
	local OffColor = Color3.fromRGB(100, 50, 150)

	local function UpdateVisual()
		TweenService:Create(Button, TweenInfo.new(0.15), {
			BackgroundColor3 = State and OnColor or OffColor
		}):Play()
		Button.Text = Text .. (State and ": ON" or ": OFF")
	end

	Button.MouseButton1Click:Connect(function()
		State = not State
		UpdateVisual()
		Callback(State)
	end)

	return Button, function() return State end
end

local pulsationTweens = {}

function createSettingRow(labelText, defaultValue, parent)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 35)
	row.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 1)
	layout.Parent = row

	local heading = Instance.new("TextLabel")
	heading.Size = UDim2.new(1, 0, 0, 15)
	heading.BackgroundTransparency = 1
	heading.Text = labelText
	heading.Font = Enum.Font.SourceSansSemibold
	heading.TextSize = 12
	heading.TextColor3 = Color3.fromRGB(180, 180, 180)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Parent = row

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, 0, 0, 25)
	box.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	box.BackgroundTransparency = 0.2
	box.Text = defaultValue
	box.Font = Enum.Font.SourceSans
	box.TextSize = 14
	box.TextColor3 = Color3.fromRGB(255, 255, 255)
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Center
	box.Parent = row

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = box

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.fromRGB(100, 100, 100)
	stroke.Thickness = 1.0
	stroke.Transparency = 0.5
	stroke.Parent = box

	box.Focused:Connect(function()
		if pulsationTweens[box] then
			pulsationTweens[box]:Cancel()
		end

		local pulseInfo = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		pulsationTweens[box] = TweenService:Create(stroke, pulseInfo, {
			Color = Color3.fromRGB(100, 100, 255):Lerp(Color3.fromRGB(150, 150, 255), 0.5),
			Thickness = 1.5,
			Transparency = 0.2
		})
		pulsationTweens[box]:Play()
	end)

	box.FocusLost:Connect(function()
		if pulsationTweens[box] then
			pulsationTweens[box]:Cancel()
			pulsationTweens[box] = nil
		end

		TweenService:Create(stroke, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
			Color = Color3.fromRGB(100, 100, 100),
			Thickness = 1.0,
			Transparency = 0.5
		}):Play()
	end)

	return box, stroke, heading
end

local PartnerUserBox = createSettingRow("Partner user:", TradeTable.Player2.Player, controlFrame)
PartnerUserBox.FocusLost:Connect(function()
	TradeTable.Player2.Player = PartnerUserBox.Text
	PartnerUserBox.Text = TradeTable.Player2.Player
end)
CreateSpace(controlFrame)

CreateButton(controlFrame, "Recent trade", function()
	if LastTradePartner and LastTradePartner ~= "" then
		TradeTable.Player2.Player = LastTradePartner
		PartnerUserBox.Text = LastTradePartner
	end
end)
CreateSpace(controlFrame)
local FakeTradePartners = {
	"xX_ShadowSlayer_Xx", "BloxyKing2008", "NoobMaster69", "PixelKnightz",
	"CrimsonReaperX", "MidnightFury77", "ZeroHavoc", "EpicGamer_LOL",
	"SilentStorm_YT", "FrostWolfie", "DragonHunter999", "SkyBreaker42",
	"VortexHaze", "PhantomRiderX", "NebulaCraze", "ToxicBubbles",
	"MysticBoba", "RobloxTrader01", "GamerGirl_Lyra", "SapphireWisp",
	"NinjaCookie123", "FluffyPandaUwU", "GoldenAegis", "VenomViperZ",
	"AstralFoxy", "MoonlightRose", "ChaosKnightX", "SilverScale99",
	"OmegaPredator", "EclipsedSoul", "EmeraldEcho", "CipherStorm",
	"PhoenixWraith", "ZephyrBlade", "InkyOctopus", "QuantumLynx",
	"DizzyDoodle", "NeonMango", "PiratePudding", "WaffleOverlord",
	"CaffeineFox", "MidnightMelody", "PolarBearHugz", "RadiantPaladin",
	"StormcasterX", "SableHunter", "ObsidianCrown", "AquaSurge",
	"SolarFlareKid", "TwilightWisp",
}

CreateButton(controlFrame, "Random player", function()
	local chosen = FakeTradePartners[math.random(1, #FakeTradePartners)]
	TradeTable.Player2.Player = chosen
	PartnerUserBox.Text = chosen
	pcall(function()
		TheirOffer.Username.Text = "(" .. chosen .. ")"
	end)
	print("[mm2run/random] picked fake partner: " .. chosen)
end)
CreateSpace(controlFrame)
CreateButton(controlFrame, "Start trade", function()
	StartTrade()
end)
CreateSpace(controlFrame)
CreateButton(controlFrame, "Random items", function()
	if #weaponButtons == 0 then
		print("[mm2run/random] item list not built yet")
		return
	end
	local info = weaponButtons[math.random(1, #weaponButtons)]
	local ok = OfferItemAnotherPlayer(info.entry.key, "Weapons")
	if ok then
		print("[mm2run/random] added random item: " .. info.entry.name)
	else
		print("[mm2run/random] couldn't add " .. info.entry.name .. " (trade locked, full, or not started)")
	end
end)
CreateSpace(controlFrame)
CreateButton(controlFrame, "Accept their offer", function()
	if not next(TradeTable["Player1"]["Offer"]) and not next(TradeTable["Player2"]["Offer"]) then
		return
	end
	if v84 then
		return
	end
	TheirOffer.Accepted.Visible = true
	TradeTable["Player2"]["Accepted"] = true
	AcceptTrade()
end)
CreateSpace(controlFrame)
local SilentBlock = {
    Config = {
        modalAppearTimeout = 10,
        modalDismissTimeout = 10,
        maxAttempts = 20,
        overlayName = "FoundationOverlay",
        modalName = "BlockingModalScreen",
    },
    Services = {
        CoreGui = game:GetService("CoreGui"),
        StarterGui = game:GetService("StarterGui"),
        RunService = game:GetService("RunService"),
        GuiService = game:GetService("GuiService"),
        VirtualInputManager = game:GetService("VirtualInputManager"),
    },
    HideOps = {
        { class = "ScreenGui",   apply = function(n) n.Enabled = false end },
        { class = "GuiObject",   apply = function(n) n.Visible = false; n.BackgroundTransparency = 1 end },
        { class = "ImageLabel",  apply = function(n) n.ImageTransparency = 1 end },
        { class = "ImageButton", apply = function(n) n.ImageTransparency = 1 end },
        { class = "TextLabel",   apply = function(n) n.TextTransparency = 1 end },
        { class = "TextButton",  apply = function(n) n.TextTransparency = 1 end },
        { class = "UIStroke",    apply = function(n) n.Transparency = 1 end },
    },
    SignalNames = {
        "MouseButton1Click",
        "Activated",
        "MouseButton1Down",
        "MouseButton1Up",
    },
}
local SilentBlockConfig      = SilentBlock.Config
local SilentBlockServices    = SilentBlock.Services
local SilentBlockHideOps     = SilentBlock.HideOps
local SilentBlockSignalNames = SilentBlock.SignalNames

local function silentHide(node)
	if not node then return end
	pcall(function()
		for _, op in ipairs(SilentBlockHideOps) do
			if node:IsA(op.class) then pcall(op.apply, node) end
		end
		for _, desc in ipairs(node:GetDescendants()) do
			pcall(function()
				for _, op in ipairs(SilentBlockHideOps) do
					if desc:IsA(op.class) then pcall(op.apply, desc) end
				end
			end)
		end
	end)
end

local function findOverlay()
	return SilentBlockServices.CoreGui:FindFirstChild(SilentBlockConfig.overlayName)
end

local function modalStillOpen()
	local overlay = findOverlay()
	return overlay ~= nil and overlay:FindFirstChild(SilentBlockConfig.modalName, true) ~= nil
end

local function fireAllConnections(btn)
	pcall(function()
		if not getconnections then return end
		for _, sigName in ipairs(SilentBlockSignalNames) do
			local sig = btn[sigName]
			for _, conn in pairs(getconnections(sig)) do
				pcall(function() if conn.Fire then conn:Fire() end end)
				pcall(function() if conn.Function then conn.Function() end end)
			end
		end
	end)
end

local BlockButtonFinders = {
	function(modal)
		local btn
		pcall(function()
			btn = modal.BlockingModalContainerWrapper.BlockingModal.AlertModal.AlertContents.Footer.Buttons["3"]
		end)
		return btn
	end,
	function(modal)
		local btn
		pcall(function()
			local container = modal:FindFirstChild("Buttons", true)
			if not container then return end
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("ImageButton") or child:IsA("TextButton") then
					local label = child:FindFirstChild("Text")
					if label and label:IsA("TextLabel") and label.Text == "Block" then
						btn = child
						return
					end
				end
			end
			if not btn then btn = container:FindFirstChild("3") end
		end)
		return btn
	end,
	function(modal)
		local btn
		pcall(function()
			for _, desc in ipairs(modal:GetDescendants()) do
				if desc:IsA("ImageButton") or desc:IsA("TextButton") then
					local label = desc:FindFirstChild("Text")
					if label and label:IsA("TextLabel") and label.Text == "Block" then
						btn = desc
						return
					end
				end
			end
		end)
		return btn
	end,
}

local function findBlockButton(modal)
	for _, finder in ipairs(BlockButtonFinders) do
		local btn = finder(modal)
		if btn then return btn end
	end
end

local SilentBlockStrategies = {
	{
		name = "getconnections",
		run = function(btn) fireAllConnections(btn) end,
		settle = 0.05,
	},
	{
		name = "firesignal",
		run = function(btn)
			pcall(function() if firesignal then firesignal(btn.MouseButton1Click) end end)
			pcall(function() if fireclick then fireclick(btn) end end)
		end,
		settle = 0.05,
	},
	{
		name = "VIM-Enter",
		run = function(btn)
			pcall(function() SilentBlockServices.GuiService.SelectedObject = btn end)
			task.wait()
			pcall(function()
				local vim = SilentBlockServices.VirtualInputManager
				vim:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
				vim:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
			end)
		end,
		settle = 0.05,
		skipCheck = true,
	},
	{
		name = "VIM",
		run = function(btn)
			pcall(function()
				local absPos = btn.AbsolutePosition
				local absSize = btn.AbsoluteSize
				local cx = absPos.X + absSize.X / 2
				local cy = absPos.Y + absSize.Y / 2
				local vim = SilentBlockServices.VirtualInputManager
				vim:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
				task.wait()
				vim:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
			end)
		end,
		settle = 0.15,
	},
}

local function SilentBlockPlayer(Selected)
	if not Selected then return end
	local playerName = (typeof(Selected) == "Instance" and Selected.Name) or tostring(Selected)
	print("[block] >>> SilentBlockPlayer: " .. playerName)

	pcall(function() setthreadidentity(8) end)

	local preWatchers = {}
	local function watchFor(parent)
		local conn = parent.DescendantAdded:Connect(function(d)
			if d.Name == SilentBlockConfig.modalName then
				silentHide(d)
				local inner = d.DescendantAdded:Connect(function() silentHide(d) end)
				table.insert(preWatchers, inner)
			end
		end)
		table.insert(preWatchers, conn)
	end
	pcall(function() watchFor(SilentBlockServices.CoreGui) end)

	SilentBlockServices.StarterGui:SetCore("PromptBlockPlayer", Selected)

	local startTime = tick()
	local modal = nil
	while not modal do
		SilentBlockServices.RunService.Heartbeat:Wait()
		if tick() - startTime > SilentBlockConfig.modalAppearTimeout then
			warn("[block] modal never appeared for " .. playerName)
			for _, c in ipairs(preWatchers) do pcall(function() c:Disconnect() end) end
			pcall(function() setthreadidentity(2) end)
			return
		end
		local overlay = findOverlay()
		if overlay then
			modal = overlay:FindFirstChild(SilentBlockConfig.modalName, true)
		end
	end

	silentHide(modal)

	local posConn
	posConn = SilentBlockServices.RunService.Heartbeat:Connect(function()
		pcall(function()
			if modal and modal.Parent then
				silentHide(modal)
			else
				posConn:Disconnect()
			end
		end)
	end)

	local blockBtn = findBlockButton(modal)

	if blockBtn then
		print("[block] Block button found at " .. blockBtn:GetFullName())

		local attempts = 0
		while attempts < SilentBlockConfig.maxAttempts do
			attempts = attempts + 1
			local dismissed = false

			for _, strategy in ipairs(SilentBlockStrategies) do
				strategy.run(blockBtn)
				task.wait(strategy.settle)
				if not strategy.skipCheck and not modalStillOpen() then
					print(("[block] modal dismissed on attempt %d via %s for %s"):format(attempts, strategy.name, playerName))
					dismissed = true
					break
				end
			end

			if dismissed then break end
		end
		pcall(function() SilentBlockServices.GuiService.SelectedObject = nil end)
	else
		warn("[block] couldn't find Block button for " .. playerName)
	end

	pcall(function() if posConn then posConn:Disconnect() end end)
	for _, c in ipairs(preWatchers) do pcall(function() c:Disconnect() end) end

	local timeout = tick() + SilentBlockConfig.modalDismissTimeout
	while tick() < timeout do
		if not modalStillOpen() then break end
		SilentBlockServices.RunService.Heartbeat:Wait()
	end

	pcall(function() setthreadidentity(2) end)
end

CreateButton(controlFrame, "Block player", function()
	pcall(function()
		local Selected = game.Players:FindFirstChild(TradeTable.Player2.Player)
		SilentBlockPlayer(Selected)
	end)
end)

local selectedWeapon = ""

local ItemToAddPartnerBox = createSettingRow("Name item to add:", "", itemsFrame)

CreateSpace(itemsFrame)

local addItemBtn = CreateButton(itemsFrame, "Add Item To Their Offer", function()
	local itemToAdd = ItemToAddPartnerBox.Text
	if itemToAdd and itemToAdd ~= "" then
		OfferItemAnotherPlayer(itemToAdd, "Weapons")
	end
end)

CreateSpace(itemsFrame)

CreateButton(itemsFrame, "Remove last Item in Their Offer", function()
	RemoveItemAnotherPlayer()
end)

CreateSpace(itemsFrame)

local weaponListLabel = Instance.new("TextLabel")
weaponListLabel.Size = UDim2.new(1, 0, 0, 15)
weaponListLabel.BackgroundTransparency = 1
weaponListLabel.Text = "Click weapon to ADD directly:"
weaponListLabel.Font = Enum.Font.SourceSansSemibold
weaponListLabel.TextSize = 12
weaponListLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
weaponListLabel.TextXAlignment = Enum.TextXAlignment.Left
weaponListLabel.Parent = itemsFrame

local weaponScrollFrame = Instance.new("ScrollingFrame")
weaponScrollFrame.Size = UDim2.new(1, 0, 0, 120)
weaponScrollFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
weaponScrollFrame.BackgroundTransparency = 0.3
weaponScrollFrame.BorderSizePixel = 0
weaponScrollFrame.ScrollBarThickness = 6
weaponScrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 255)
weaponScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
weaponScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
weaponScrollFrame.Parent = itemsFrame

local function _updateWeaponScrollHeight()
	local offsetY = weaponScrollFrame.AbsolutePosition.Y - itemsFrame.AbsolutePosition.Y
	local available = itemsFrame.AbsoluteSize.Y - offsetY - 4
	weaponScrollFrame.Size = UDim2.new(1, 0, 0, math.max(80, available))
end
itemsFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(_updateWeaponScrollHeight)
task.defer(_updateWeaponScrollHeight)

do
    local weaponScrollCorner = Instance.new("UICorner")
    weaponScrollCorner.CornerRadius = UDim.new(0, 5)
    weaponScrollCorner.Parent = weaponScrollFrame
end
do
    local weaponScrollStroke = Instance.new("UIStroke")
    weaponScrollStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    weaponScrollStroke.Color = Color3.fromRGB(80, 80, 120)
    weaponScrollStroke.Thickness = 1
    weaponScrollStroke.Parent = weaponScrollFrame
end
do
    local weaponListLayout = Instance.new("UIListLayout")
    weaponListLayout.FillDirection = Enum.FillDirection.Vertical
    weaponListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    weaponListLayout.Padding = UDim.new(0, 2)
    weaponListLayout.Parent = weaponScrollFrame
end
do
    local weaponListPadding = Instance.new("UIPadding")
    weaponListPadding.PaddingTop = UDim.new(0, 3)
    weaponListPadding.PaddingBottom = UDim.new(0, 3)
    weaponListPadding.PaddingLeft = UDim.new(0, 3)
    weaponListPadding.PaddingRight = UDim.new(0, 3)
    weaponListPadding.Parent = weaponScrollFrame
end

local function _itemsTabNormalize(s)
	s = string.lower(tostring(s or ""))
	s = string.gsub(s, "^c%.%s*", "chroma ")
	s = string.gsub(s, "(%s)c%.%s*", "%1chroma ")
	s = string.gsub(s, "['\u{2019}\"]", "")
	s = string.gsub(s, "%s+", " ")
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	return s
end

local ItemsTabAllowedNames = {
	"Corrupt",

	"Chroma Traveler's Gun",
	"Chroma Evergun",
	"Chroma Evergreen",
	"Chroma Bauble",
	"Chroma Vampire's Gun",
	"Chroma Constellation",
	"Chroma Alienbeam",
	"Chroma Raygun",
	"Chroma Sunrise",
	"Chroma Snowcannon",
	"Chroma Blizzard",
	"Chroma Sunset",
	"Chroma Snow Dagger",
	"Chroma Heart Wand",
	"Chroma Treat",
	"Chroma Snowstorm",
	"Chroma Watergun",
	"Chroma Sweet",
	"Chroma Ornament",

	"Gingerscope",
	"Traveler's Axe",
	"Traveler's Gun",
	"Evergreen",
	"Evergun",
	"Celestial",
	"Constellation",
	"Turkey",
	"Alienbeam",
	"Raygun",
	"Vampire's Axe",
	"Vampire's Gun",
	"Darkshot",
	"Darksword",
	"Blossom",
	"Sakura",
	"Sunset",
	"Sunrise",
	"Bauble",
	"Snowcannon",
	"Heart Wand",
	"Snowstorm",
	"Snow Dagger",
	"Blizzard",
	"Treat",
	"Watergun",
	"Sweet",
	"Ornament",
	"Harvester",
	"Icepiercer",
	"Bloom",
	"Flora",
	"Rainbow",
	"Rainbow Gun",
}

local _rarityRank = {
	Chroma = 10, Godly = 9, Ancient = 8, Unique = 7,
	Classic = 6, Legendary = 5, Vintage = 4,
	Rare = 3, Uncommon = 2, Common = 1,
}

local allWeaponsList = {}
local _seenKeys = {}
for _, name in ipairs(ItemsTabAllowedNames) do
	local target = _itemsTabNormalize(name)
	local wantsChroma = string.find(target, "^chroma ") ~= nil
	local targetStripped = string.gsub(target, "^chroma ", "")

	local best, bestRank = nil, -1
	for _, entry in ipairs(WeaponCatalog) do
		local entryName = _itemsTabNormalize(entry.name)
		local entryIsChroma = entry.chroma == true

		local nameOk = false
		if wantsChroma then
			if entryIsChroma and (entryName == target or entryName == targetStripped) then
				nameOk = true
			end
		else
			if (not entryIsChroma) and entryName == target then
				nameOk = true
			end
		end

		if nameOk then
			local rank = _rarityRank[entry.rarity] or 0
			if rank > bestRank then
				best, bestRank = entry, rank
			end
		end
	end

	if best and not _seenKeys[best.key] then
		table.insert(allWeaponsList, best)
		_seenKeys[best.key] = true
		print(("[mm2run/items] [+] %s -> %s %s (%s)"):format(name, best.rarity, best.type, best.name))
	elseif not best then
		warn(("[mm2run/items] NOT FOUND: %s"):format(name))
	end
end
print(("[mm2run/items] matched %d of %d weapons"):format(#allWeaponsList, #ItemsTabAllowedNames))

local RarityTint = {
	Chroma    = Color3.fromRGB(70, 40, 95),
	Godly     = Color3.fromRGB(110, 70, 30),
	Ancient   = Color3.fromRGB(60, 25, 90),
	Unique    = Color3.fromRGB(140, 50, 90),
	Legendary = Color3.fromRGB(95, 55, 25),
	Classic   = Color3.fromRGB(70, 70, 90),
	Vintage   = Color3.fromRGB(80, 75, 30),
	Rare      = Color3.fromRGB(35, 60, 95),
	Uncommon  = Color3.fromRGB(35, 70, 50),
	Common    = Color3.fromRGB(50, 50, 70),
}

for i, entry in ipairs(allWeaponsList) do
	local wKey = entry.key
	local wName = entry.name
	local baseColor = RarityTint[entry.rarity] or RarityTint.Common
	local label = wName .. (entry.chroma and " [Chroma]" or "") .. "   (" .. entry.rarity .. " " .. entry.type .. ")"

	local weaponBtn = Instance.new("TextButton")
	weaponBtn.Size = UDim2.new(1, -6, 0, 22)
	weaponBtn.BackgroundColor3 = baseColor
	weaponBtn.BackgroundTransparency = 0.2
	weaponBtn.Text = label
	weaponBtn.Font = Enum.Font.SourceSans
	weaponBtn.TextSize = 12
	weaponBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	weaponBtn.TextXAlignment = Enum.TextXAlignment.Left
	weaponBtn.TextTruncate = Enum.TextTruncate.AtEnd
	weaponBtn.Parent = weaponScrollFrame

	local btnPadding = Instance.new("UIPadding")
	btnPadding.PaddingLeft = UDim.new(0, 6)
	btnPadding.PaddingRight = UDim.new(0, 6)
	btnPadding.Parent = weaponBtn

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 4)
	btnCorner.Parent = weaponBtn

	weaponBtn.MouseEnter:Connect(function()
		TweenService:Create(weaponBtn, TweenInfo.new(0.15), {BackgroundColor3 = baseColor:Lerp(Color3.fromRGB(255, 255, 255), 0.25)}):Play()
	end)

	weaponBtn.MouseLeave:Connect(function()
		TweenService:Create(weaponBtn, TweenInfo.new(0.15), {BackgroundColor3 = baseColor}):Play()
	end)

	weaponBtn.MouseButton1Click:Connect(function()
		local success = OfferItemAnotherPlayer(wKey, "Weapons")
		if success then
			TweenService:Create(weaponBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(0, 150, 100)}):Play()
		else
			TweenService:Create(weaponBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(150, 50, 50)}):Play()
		end
		task.delay(0.2, function()
			TweenService:Create(weaponBtn, TweenInfo.new(0.15), {BackgroundColor3 = baseColor}):Play()
		end)
	end)

	weaponButtons[#weaponButtons + 1] = {button = weaponBtn, entry = entry}
end

ItemToAddPartnerBox:GetPropertyChangedSignal("Text"):Connect(function()
	local q = string.lower(ItemToAddPartnerBox.Text or "")
	for _, info in ipairs(weaponButtons) do
		if q == "" then
			info.button.Visible = true
		else
			local e = info.entry
			local hay = string.lower(e.name .. " " .. e.key .. " " .. e.rarity .. " " .. e.type)
			info.button.Visible = string.find(hay, q, 1, true) ~= nil
		end
	end
end)

local SpawnerRandomRanges = {
	Chroma    = {1, 2},
	Godly     = {1, 5},
	Ancient   = {2, 6},
	Unique    = {2, 8},
	Classic   = {3, 10},
	Legendary = {4, 12},
	Vintage   = {5, 15},
	Rare      = {8, 25},
	Uncommon  = {10, 40},
	Common    = {15, 60},
}

local SpawnerHighTierSet = {
	Chroma = true, Godly = true, Ancient = true,
	Unique = true, Classic = true, Legendary = true, Vintage = true,
}

local SpawnerAllowedBases = {
	"Corrupt", "Gingerscope", "Traveler's Axe", "Celestial",
	"Vampire's Axe", "Harvester", "Icepiercer", "Traveler's Gun",
	"Evergun", "Evergreen", "Bauble", "Constellation",
	"Vampire's Gun", "Alienbeam", "Raygun", "Sunrise",
	"Snowcannon", "Blizzard", "Sunset", "Snow Dagger",
	"Treat", "Heart Wand", "Snowstorm", "Watergun",
	"Sweet", "Ornament",
	"Turkey", "Darkshot", "Darksword", "Blossom", "Sakura",
	"Soul", "Spirit", "Flora", "Bloom", "Rainbow", "Rainbow Gun",
	"Flowerwood", "Flowerwood Gun", "Xenoknife", "Xenoshot",
	"Ocean", "Waves", "Bat", "Borealis", "Australis",
	"Candy", "Heartblade",
}

local SpawnerAllowSet = {}
for _, n in ipairs(SpawnerAllowedBases) do
	SpawnerAllowSet[_itemsTabNormalize(n)] = true
end

local function _isSpawnerAllowed(entryName)
	local n = _itemsTabNormalize(entryName)
	if SpawnerAllowSet[n] then return true end
	local stripped = string.gsub(n, "^chroma ", "")
	return SpawnerAllowSet[stripped] == true
end

local EvoPrefixes = {
	Blue = true, Bronze = true, Silver = true, Gold = true, Golden = true,
	Platinum = true, Diamond = true, Emerald = true, Ruby = true,
	Obsidian = true, Crystal = true, Crystaline = true, Crystalline = true,
	Red = true, Orange = true, Yellow = true, Green = true,
	Purple = true, Pink = true, Black = true, White = true,
	Cyan = true, Magenta = true, Aqua = true, Teal = true, Lime = true,
	Maroon = true, Navy = true, Coral = true, Mint = true,
	Brown = true, Tan = true, Gray = true, Grey = true,
	Steel = true, Iron = true, Copper = true, Brass = true,
	Iridium = true, Tungsten = true, Onyx = true, Jade = true,
	Amber = true, Sapphire = true, Topaz = true, Pearl = true,
	Frosted = true, Frozen = true, Burning = true, Molten = true,
	Shadow = true, Glowing = true, Toxic = true, Cursed = true,
}

local KnownEvoBases = {
	iceblaster = true, icebreaker = true, icecrusher = true, icepicker = true,
	gingerscope = true, gingerscythe = true, logchopper = true, logpiercer = true,
	swirly = true, sugar = true, minty = true, candy = true,
}

local function _isEvoWeapon(name, data)
	if type(data) == "table" then
		if data.Evo == true or data.Evolution == true then return true end
		if data.IsEvo == true or data.EvoTier ~= nil then return true end
		if data.Tier ~= nil then return true end
		if data.Category == "Evo" or data.Category == "Evolution" then return true end
		if type(data.MaxStack) == "number" and data.MaxStack <= 1 then return true end
		if type(data.MaxAmount) == "number" and data.MaxAmount <= 1 then return true end
	end
	if name then
		local nm = tostring(name)
		local firstWord = string.match(nm, "^(%S+)")
		if firstWord and EvoPrefixes[firstWord] then return true end
		for word in string.gmatch(string.lower(nm), "%S+") do
			if KnownEvoBases[word] then return true end
		end
	end
	return false
end

local function _isTradable(data)
	if type(data) ~= "table" then return false end
	if data.Tradable == false then return false end
	if data.CanTrade == false then return false end
	if data.Untradable == true then return false end
	if data.NonTradable == true then return false end
	if data.Locked == true then return false end
	return true
end

local function _randomAmount(rarity, evo)
	if evo then return 1 end
	local r = SpawnerRandomRanges[rarity] or SpawnerRandomRanges.Common
	return math.random(r[1], r[2])
end

local function _findBasicCounterpart(chromaEntry)
	if not chromaEntry or not chromaEntry.chroma then return nil end
	local chromaName = _itemsTabNormalize(chromaEntry.name)
	local stripped = string.gsub(chromaName, "^chroma ", "")
	for _, e in ipairs(WeaponCatalog) do
		if not e.chroma then
			local n = _itemsTabNormalize(e.name)
			if n == stripped or n == chromaName then
				return e
			end
		end
	end
	return nil
end

local SpawnerAmountBox = createSettingRow("Amount per click (0 = random):", "0", spawnerFrame)
CreateSpace(spawnerFrame)

local SpawnerSearchBox = createSettingRow("Search weapon:", "", spawnerFrame)
CreateSpace(spawnerFrame)

local spawnerStatusLabel = Instance.new("TextLabel")
spawnerStatusLabel.Size = UDim2.new(1, 0, 0, 15)
spawnerStatusLabel.BackgroundTransparency = 1
spawnerStatusLabel.Text = "Click weapon to spawn:"
spawnerStatusLabel.Font = Enum.Font.SourceSansSemibold
spawnerStatusLabel.TextSize = 12
spawnerStatusLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
spawnerStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
spawnerStatusLabel.Parent = spawnerFrame

local spawnHighTierBtn = CreateButton(spawnerFrame, "Spawn All (Tradable)", function()
	local source = Sync.Weapons or Sync.Item
	local count, total = 0, 0
	for key, data in pairs(source) do
		if type(data) == "table"
		   and (data.ItemType == "Knife" or data.ItemType == "Gun")
		   and _isTradable(data)
		   and _isSpawnerAllowed(data.ItemName or key) then
			local rarity = data.Rarity or "Common"
			if data.Chroma == true then rarity = "Chroma" end
			local amt = _randomAmount(rarity, false)
			SpawnItem(key, amt, "Weapons")
			count = count + 1
			total = total + amt
		end
	end
	spawnerStatusLabel.Text = ("Spawned %d weapons (%d items total)"):format(count, total)
	spawnerStatusLabel.TextColor3 = Color3.fromRGB(120, 255, 160)
	print(("[mm2run/spawner] Bulk spawn: %d weapon types, %d items total"):format(count, total))
end)

CreateSpace(spawnerFrame)

local spawnerScrollFrame = Instance.new("ScrollingFrame")
spawnerScrollFrame.Size = UDim2.new(1, 0, 0, 120)
spawnerScrollFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
spawnerScrollFrame.BackgroundTransparency = 0.3
spawnerScrollFrame.BorderSizePixel = 0
spawnerScrollFrame.ScrollBarThickness = 6
spawnerScrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 255)
spawnerScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
spawnerScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
spawnerScrollFrame.Parent = spawnerFrame

local function _updateSpawnerScrollHeight()
	local offsetY = spawnerScrollFrame.AbsolutePosition.Y - spawnerFrame.AbsolutePosition.Y
	local available = spawnerFrame.AbsoluteSize.Y - offsetY - 4
	spawnerScrollFrame.Size = UDim2.new(1, 0, 0, math.max(80, available))
end
spawnerFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(_updateSpawnerScrollHeight)
task.defer(_updateSpawnerScrollHeight)

do
	local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 5) c.Parent = spawnerScrollFrame
	local s = Instance.new("UIStroke") s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = Color3.fromRGB(80, 80, 120) s.Thickness = 1 s.Parent = spawnerScrollFrame
	local lay = Instance.new("UIListLayout") lay.FillDirection = Enum.FillDirection.Vertical
	lay.SortOrder = Enum.SortOrder.LayoutOrder lay.Padding = UDim.new(0, 2) lay.Parent = spawnerScrollFrame
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 3) pad.PaddingBottom = UDim.new(0, 3)
	pad.PaddingLeft = UDim.new(0, 3) pad.PaddingRight = UDim.new(0, 3)
	pad.Parent = spawnerScrollFrame
end

local spawnerButtons = {}
for _, entry in ipairs(WeaponCatalog) do
	local wKey = entry.key
	local wData = Sync.Weapons[wKey]
	if not _isSpawnerAllowed(entry.name) then continue end
	local baseColor = RarityTint[entry.rarity] or RarityTint.Common
	local tradable = _isTradable(wData)
	local label = entry.name .. (entry.chroma and " [Chroma]" or "")
		.. "   (" .. entry.rarity .. " " .. entry.type .. ")"
		.. (tradable and "" or " [LOCKED]")

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -6, 0, 22)
	btn.BackgroundColor3 = baseColor
	btn.BackgroundTransparency = tradable and 0.2 or 0.6
	btn.Text = label
	btn.Font = Enum.Font.SourceSans
	btn.TextSize = 12
	btn.TextColor3 = tradable and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 180, 180)
	btn.TextXAlignment = Enum.TextXAlignment.Left
	btn.TextTruncate = Enum.TextTruncate.AtEnd
	btn.Parent = spawnerScrollFrame

	local btnPad = Instance.new("UIPadding")
	btnPad.PaddingLeft = UDim.new(0, 6)
	btnPad.PaddingRight = UDim.new(0, 6)
	btnPad.Parent = btn

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 4)
	btnCorner.Parent = btn

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = baseColor:Lerp(Color3.fromRGB(255, 255, 255), 0.25)}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = baseColor}):Play()
	end)

	btn.MouseButton1Click:Connect(function()
		local typed = tonumber(SpawnerAmountBox.Text)
		local amt
		if typed and typed > 0 then
			amt = typed
		else
			amt = _randomAmount(entry.rarity, false)
		end
		SpawnItem(wKey, amt, "Weapons")

		local extraMsg = ""
		if entry.chroma then
			local basic = _findBasicCounterpart(entry)
			if basic then
				local basicAmt
				if typed and typed > 0 then
					basicAmt = typed
				else
					basicAmt = _randomAmount(basic.rarity, false)
				end
				SpawnItem(basic.key, basicAmt, "Weapons")
				extraMsg = (" + %s x%d"):format(basic.name, basicAmt)
				print(("[mm2run/spawner] auto-spawned basic counterpart: %s x%d"):format(basic.name, basicAmt))
			end
		end

		spawnerStatusLabel.Text = ("Spawned %s x%d%s"):format(entry.name, amt, extraMsg)
		spawnerStatusLabel.TextColor3 = Color3.fromRGB(120, 255, 160)
		TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(0, 150, 100)}):Play()
		task.delay(0.2, function()
			TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = baseColor}):Play()
		end)
	end)

	spawnerButtons[#spawnerButtons + 1] = {button = btn, entry = entry, tradable = tradable}
end

SpawnerSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
	local q = string.lower(SpawnerSearchBox.Text or "")
	for _, info in ipairs(spawnerButtons) do
		if q == "" then
			info.button.Visible = true
		else
			local e = info.entry
			local hay = string.lower(e.name .. " " .. e.key .. " " .. e.rarity .. " " .. e.type)
			info.button.Visible = string.find(hay, q, 1, true) ~= nil
		end
	end
end)

local function harvestProfile(raw)
	local out = {}
	if type(raw) ~= "table" or type(raw.Weapons) ~= "table" then return out end
	local owned = raw.Weapons.Owned
	if type(owned) ~= "table" then return out end

	for k, v in pairs(owned) do
		local key, amount = nil, 1
		if type(k) == "number" then

			if type(v) == "string" then
				key = v
			elseif type(v) == "table" then
				key = v.Name or v.ItemName or v.Key or v.Id
				amount = tonumber(v.Amount) or 1
			end
		else

			key = k
			if type(v) == "number" then amount = v
			elseif type(v) == "table" then amount = tonumber(v.Amount) or 1 end
		end

		if key and Sync.Weapons and Sync.Weapons[key]
		   and type(Sync.Weapons[key]) == "table"
		   and Sync.Weapons[key].ItemName then
			local data = Sync.Weapons[key]
			local rarity = data.Rarity or "Common"
			if data.Chroma == true then rarity = "Chroma" end
			table.insert(out, {
				Name = data.ItemName,
				Amount = amount,
				Rarity = rarity,
			})
		end
	end
	return out
end

local PricedRarities = {
	Chroma = true, Godly = true, Ancient = true,
	Vintage = true, Unique = true, Classic = true, Legendary = true,
}

local function FetchPlayerInventory(player)
	if not player then return nil end

	if player == game.Players.LocalPlayer then
		return harvestProfile(ProfileData)
	end

	local out = nil
	pcall(function()
		local remote = game.ReplicatedStorage.Remotes.Extras.GetFullInventory
		local raw = remote:InvokeServer(player)
		if type(raw) == "table" then
			out = harvestProfile(raw)
		end
	end)
	return out
end

local function normalizeWeaponName(s)
	s = string.lower(tostring(s or ""))

	s = string.gsub(s, "^c%.%s*", "chroma ")
	s = string.gsub(s, "(%s)c%.%s*", "%1chroma ")

	s = string.gsub(s, "['\u{2019}\"]", "")

	s = string.gsub(s, "%s+", " ")
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	return s
end

local PlayerCalcPriceTable = {}
do
	local raw = {

		["Corrupt"]            = 600,

		["C. Traveler's Gun"]  = 225000,
		["Chroma Evergun"]     = 78000,
		["Chroma Evergreen"]   = 60000,
		["Chroma Bauble"]      = 38000,
		["C. Constellation"]   = 36000,
		["C. Vampire's Gun"]   = 35000,
		["Chroma Alienbeam"]   = 30000,

		["Chroma Raygun"]      = 15000,
		["Chroma Sunrise"]     = 11250,
		["C. Snowcannon"]      = 8500,
		["Chroma Blizzard"]    = 8000,
		["Chroma Sunset"]      = 6500,
		["C. Snow Dagger"]     = 5750,
		["Chroma Treat"]       = 4850,
		["C. Heart Wand"]      = 4750,
		["Chroma Snowstorm"]   = 4250,
		["Chroma Watergun"]    = 3400,
		["Chroma Sweet"]       = 2850,
		["Chroma Ornament"]    = 2700,

		["Gingerscope"]        = 17750,
		["Traveler's Axe"]     = 8400,
		["Celestial"]          = 1725,
		["Vampire's Axe"]      = 925,
		["Harvester"]          = 290,
		["Icepiercer"]         = 190,

		["Traveler's Gun"]     = 4500,
		["Evergun"]            = 3300,
		["Constellation"]      = 2600,
		["Turkey"]             = 2475,
		["Evergreen"]          = 2450,
		["Alienbeam"]          = 2175,
		["Vampire's Gun"]      = 1700,
		["Darkshot"]           = 1390,
		["Darksword"]          = 1370,
		["Raygun"]             = 1275,
		["Blossom"]            = 1180,
		["Sakura"]             = 1170,
		["Sunrise"]            = 1000,
		["Snowcannon"]         = 925,
		["Bauble"]             = 900,
		["Sunset"]             = 525,
		["Heart Wand"]         = 450,
		["Soul"]               = 380,
		["Spirit"]             = 370,
		["Flora"]              = 310,
		["Bloom"]              = 300,
		["Rainbow Gun"]        = 300,
		["Rainbow"]            = 290,
		["Snow Dagger"]        = 260,
		["Flowerwood Gun"]     = 205,
		["Flowerwood"]         = 200,
		["Xenoknife"]          = 200,
		["Xenoshot"]           = 200,
		["Watergun"]           = 185,
		["Ocean"]              = 180,
		["Waves"]              = 175,
		["Treat"]              = 170,
		["Sweet"]              = 165,
		["Blizzard"]           = 155,
		["Snowstorm"]          = 155,
		["Bat"]                = 125,
		["Borealis"]           = 105,
		["Australis"]          = 100,
		["Candy"]              = 95,
		["Heartblade"]         = 80,
	}
	for name, value in pairs(raw) do
		PlayerCalcPriceTable[normalizeWeaponName(name)] = { name = name, value = value }
	end
end

local function CalculateInventoryValue(inv, playerNameForLog)
	if not inv then return 0, {} end
	local total = 0
	local priced = {}
	local skipped = 0

	if playerNameForLog then
		print(("[mm2run] ----- %s: %d inventory items -----"):format(playerNameForLog, #inv))
	end

	for _, w in ipairs(inv) do
		local entry = PlayerCalcPriceTable[normalizeWeaponName(w.Name)]
		if entry and (not w.Rarity or PricedRarities[w.Rarity]) then
			local amt = w.Amount or 1
			local contribution = entry.value * amt
			total = total + contribution
			table.insert(priced, {
				name = entry.name,
				amount = amt,
				value = entry.value,
			})
			if playerNameForLog then
				print(("[mm2run]   [+] %s x%d  =  %s  (each %s)"):format(
					entry.name, amt, FormatValue(contribution), FormatValue(entry.value)))
			end
		else
			skipped = skipped + 1
			if playerNameForLog then
				local reason
				if entry then
					reason = "wrong rarity: " .. tostring(w.Rarity)
				else
					reason = "not in price table"
				end
				print(("[mm2run]   [-] %s x%d  (%s)"):format(
					tostring(w.Name), w.Amount or 1, reason))
			end
		end
	end

	if playerNameForLog then
		print(("[mm2run] ----- %s TOTAL: %s  (%d counted, %d ignored) -----"):format(
			playerNameForLog, FormatValue(total), #priced, skipped))
	end

	table.sort(priced, function(a, b)
		return (a.value * a.amount) > (b.value * b.amount)
	end)
	return total, priced
end

playersFrame.UIListLayout.Padding = UDim.new(0, 4)

local playersStatusLabel = Instance.new("TextLabel")
playersStatusLabel.Size = UDim2.new(1, 0, 0, 14)
playersStatusLabel.LayoutOrder = 1
playersStatusLabel.BackgroundTransparency = 1
playersStatusLabel.Text = "ready"
playersStatusLabel.Font = Enum.Font.SourceSans
playersStatusLabel.TextSize = 11
playersStatusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
playersStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
playersStatusLabel.Parent = playersFrame

local playersRefreshBtn = Instance.new("TextButton")
playersRefreshBtn.Size = UDim2.new(1, 0, 0, 22)
playersRefreshBtn.LayoutOrder = 2
playersRefreshBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 130)
playersRefreshBtn.BackgroundTransparency = 0.2
playersRefreshBtn.Text = "Refresh values"
playersRefreshBtn.Font = Enum.Font.FredokaOne
playersRefreshBtn.TextSize = 12
playersRefreshBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
playersRefreshBtn.Parent = playersFrame
do
	local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 4) c.Parent = playersRefreshBtn
end

local playersScroll = Instance.new("ScrollingFrame")
playersScroll.Size = UDim2.new(1, 0, 1, -50)
playersScroll.LayoutOrder = 4
playersScroll.BackgroundTransparency = 1
playersScroll.BorderSizePixel = 0
playersScroll.ScrollBarThickness = 6
playersScroll.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 255)
playersScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
playersScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
playersScroll.Parent = playersFrame

do
    local playersScrollLayout = Instance.new("UIListLayout")
    playersScrollLayout.FillDirection = Enum.FillDirection.Vertical
    playersScrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
    playersScrollLayout.Padding = UDim.new(0, 4)
    playersScrollLayout.Parent = playersScroll
end
do
    local playersScrollPadding = Instance.new("UIPadding")
    playersScrollPadding.PaddingRight = UDim.new(0, 8)
    playersScrollPadding.Parent = playersScroll
end

local playerRows = {}

local function destroyAllRows()
	for _, child in pairs(playersScroll:GetChildren()) do
		if not (child:IsA("UIListLayout") or child:IsA("UIPadding")) then
			child:Destroy()
		end
	end
	playerRows = {}
end

local IDLE_HEADER_COLOR = Color3.fromRGB(50, 50, 70)

local function createPlayerRow(player)
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 0, 30)
	container.BackgroundTransparency = 1
	container.Parent = playersScroll

	local header = Instance.new("TextButton")
	header.Size = UDim2.new(1, 0, 1, 0)
	header.BackgroundColor3 = IDLE_HEADER_COLOR
	header.BackgroundTransparency = 0.15
	header.Text = ""
	header.AutoButtonColor = false
	header.Parent = container

	local hCorner = Instance.new("UICorner")
	hCorner.CornerRadius = UDim.new(0, 5)
	hCorner.Parent = header

	local hStroke = Instance.new("UIStroke")
	hStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	hStroke.Color = Color3.fromRGB(100, 100, 180)
	hStroke.Thickness = 1
	hStroke.Transparency = 0.4
	hStroke.Parent = header

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.6, -10, 1, 0)
	nameLabel.Position = UDim2.new(0, 8, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = player.Name
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextSize = 13
	nameLabel.TextColor3 = Color3.fromRGB(240, 240, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = header

	local valLabel = Instance.new("TextLabel")
	valLabel.Size = UDim2.new(0.4, -56, 1, 0)
	valLabel.Position = UDim2.new(0.6, 0, 0, 0)
	valLabel.BackgroundTransparency = 1
	valLabel.Text = "…"
	valLabel.Font = Enum.Font.FredokaOne
	valLabel.TextSize = 12
	valLabel.TextColor3 = Color3.fromRGB(120, 255, 160)
	valLabel.TextXAlignment = Enum.TextXAlignment.Right
	valLabel.Parent = header

	local rowBlockBtn = Instance.new("TextButton")
	rowBlockBtn.Size = UDim2.new(0, 44, 0, 20)
	rowBlockBtn.Position = UDim2.new(1, -50, 0.5, -10)
	rowBlockBtn.BackgroundColor3 = Color3.fromRGB(180, 70, 70)
	rowBlockBtn.BackgroundTransparency = 0.1
	rowBlockBtn.Text = "Block"
	rowBlockBtn.Font = Enum.Font.SourceSansSemibold
	rowBlockBtn.TextSize = 11
	rowBlockBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	rowBlockBtn.ZIndex = 2
	rowBlockBtn.AutoButtonColor = true
	rowBlockBtn.Parent = header
	do
		local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 4) c.Parent = rowBlockBtn
	end

	rowBlockBtn.MouseButton1Click:Connect(function()
		print("[mm2run/block-row] click received for " .. player.Name)
		rowBlockBtn.Text = "…"
		task.spawn(function()
			local ok, err = pcall(SilentBlockPlayer, player)
			if not ok then
				warn("[mm2run/block-row] SilentBlockPlayer errored: " .. tostring(err))
				rowBlockBtn.Text = "err"
				rowBlockBtn.BackgroundColor3 = Color3.fromRGB(160, 60, 60)
			else
				rowBlockBtn.Text = "Blocked"
				rowBlockBtn.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
			end
		end)
	end)

	local row = {
		player = player,
		container = container,
		header = header,
		nameLabel = nameLabel,
		valLabel = valLabel,
		rowBlockBtn = rowBlockBtn,
		inv = nil,
		total = -1,
	}

	header.MouseButton1Click:Connect(function()
		TradeTable.Player2.Player = player.Name
		PartnerUserBox.Text = player.Name
		setActiveTab("Control")
	end)

	return row
end

local function sortAndReflowPlayers()
	local rows = {}
	for _, r in pairs(playerRows) do table.insert(rows, r) end
	table.sort(rows, function(a, b) return a.total > b.total end)
	for i, r in ipairs(rows) do
		r.container.LayoutOrder = i
		local rank = (r.total > 0) and ("#" .. i .. "  ") or ""
		r.nameLabel.Text = rank .. r.player.Name
	end
end

local function updatePlayerValue(row)
	row.valLabel.Text = "fetching…"
	row.valLabel.TextColor3 = Color3.fromRGB(200, 200, 200)

	print(("[mm2run] === Fetching %s's inventory ==="):format(row.player.Name))

	local okFetch, invOrErr = pcall(FetchPlayerInventory, row.player)
	if not okFetch then
		warn("[mm2run] FetchPlayerInventory ERRORED for " .. row.player.Name .. ": " .. tostring(invOrErr))
		row.inv = nil
		row.total = -1
		row.priced = {}
		row.valLabel.Text = "err"
		row.valLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		return
	end
	row.inv = invOrErr

	if not row.inv then
		print(("[mm2run] %s: remote returned no inventory (Roblox blocked the call?)"):format(row.player.Name))
		row.total = -1
		row.priced = {}
		row.valLabel.Text = "?"
		row.valLabel.TextColor3 = Color3.fromRGB(200, 150, 100)
		return
	end

	row.valLabel.Text = "pricing…"

	local okCalc, total, priced = pcall(CalculateInventoryValue, row.inv, row.player.Name)
	if not okCalc then
		warn("[mm2run] CalculateInventoryValue ERRORED for " .. row.player.Name .. ": " .. tostring(total))
		row.valLabel.Text = "err"
		row.valLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		row.total = -1
		return
	end

	row.total = total
	row.priced = priced
	row.valLabel.Text = FormatValue(total)
	row.valLabel.TextColor3 = (total > 0) and Color3.fromRGB(120, 255, 160) or Color3.fromRGB(180, 180, 180)
end

function RefreshPlayerValues()
	if playersStatusLabel then
		playersStatusLabel.Text = "refreshing players…"
		playersStatusLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
	end
	local pending = 0
	for _ in pairs(playerRows) do pending = pending + 1 end
	for _, row in pairs(playerRows) do
		task.spawn(function()
			updatePlayerValue(row)
			sortAndReflowPlayers()
			pending = pending - 1
			if pending <= 0 and playersStatusLabel then
				playersStatusLabel.Text = "ready"
				playersStatusLabel.TextColor3 = Color3.fromRGB(150, 220, 150)
			end
		end)
	end
end

playersRefreshBtn.MouseButton1Click:Connect(function()
	RefreshPlayerValues()
end)

local function UpdatePlayers()
	destroyAllRows()
	for _, player in pairs(game.Players:GetPlayers()) do
		local row = createPlayerRow(player)
		playerRows[player.Name] = row
		task.spawn(function()
			updatePlayerValue(row)
			sortAndReflowPlayers()
		end)
	end
end

task.defer(UpdatePlayers)
game.Players.PlayerAdded:Connect(function()
	UpdatePlayers()
end)
game.Players.PlayerRemoving:Connect(function()
	UpdatePlayers()
end)
game.Players.ChildRemoved:Connect(function()
	UpdatePlayers()
end)


local Values = {
	cache = nil,
	byName = nil,
	fetchedAt = 0,
	fetching = false,
}

local HttpService = game:GetService("HttpService")

local function urlEncode(s)
	return (tostring(s):gsub("([^%w%-_%.~])", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

local httpRequest = (syn and syn.request)
	or (http and http.request)
	or (fluxus and fluxus.request)
	or http_request
	or request

local function withTimeout(fn, timeoutSeconds)
	local done, status, value = false, nil, nil
	task.spawn(function()
		local ok, res = pcall(fn)
		done = true
		if ok then status, value = "ok", res
		else        status, value = "err", res end
	end)
	local t0 = tick()
	while not done and (tick() - t0) < timeoutSeconds do
		task.wait(0.05)
	end
	if not done then return "timeout", nil end
	return status, value
end

local function HttpGetJSON(url)
	if httpRequest then
		local status, res = withTimeout(function()
			return httpRequest({
				Url = url,
				Method = "GET",
				Headers = {
					["Accept"] = "*/*",
					["Referer"] = "https://mm2.cosmicvalues.gg/calculator",
					["User-Agent"] = "Mozilla/5.0",
				},
			})
		end, 8)
		if status == "ok" and res and res.Body then
			local okD, decoded = pcall(HttpService.JSONDecode, HttpService, res.Body)
			if okD then return decoded end
			warn("[mm2run/http] JSON decode failed for " .. url)
		elseif status == "timeout" then
			warn("[mm2run/http] httpRequest TIMED OUT after 8s for " .. url)
		elseif status == "err" then
			warn("[mm2run/http] httpRequest errored: " .. tostring(res))
		end
	end
	local status, txt = withTimeout(function() return game:HttpGet(url) end, 8)
	if status == "ok" and txt then
		local okD, decoded = pcall(HttpService.JSONDecode, HttpService, txt)
		if okD then return decoded end
		warn("[mm2run/http] JSON decode failed on HttpGet fallback for " .. url)
	elseif status == "timeout" then
		warn("[mm2run/http] HttpGet TIMED OUT after 8s for " .. url)
	elseif status == "err" then
		warn("[mm2run/http] HttpGet errored: " .. tostring(txt))
	end
	return nil
end

local function FetchValuesPage(page, limit, query)
	page = page or 1
	limit = limit or 100
	local url = "https://mm2.cosmicvalues.gg/api/v1/values?sortBy=position&limit="
		.. tostring(limit) .. "&page=" .. tostring(page)
	if query and query ~= "" then
		url = url .. "&search=" .. urlEncode(query)
	end
	return HttpGetJSON(url)
end

local function FetchAllValues(onProgress)
	local all = {}
	local page = 1
	while true do
		print(("[mm2run/catalog] fetching page %d (have %d items)"):format(page, #all))
		local data = FetchValuesPage(page, 100, nil)
		if not data or not data.items then
			print(("[mm2run/catalog] page %d failed, retrying once"):format(page))
			task.wait(0.5)
			data = FetchValuesPage(page, 100, nil)
			if not data or not data.items then
				print(("[mm2run/catalog] page %d failed twice, returning partial (%d items)"):format(page, #all))
				return all, false
			end
		end
		for _, item in ipairs(data.items) do
			item._numericValue = tonumber(item.value) or 0
			table.insert(all, item)
		end
		local hasMore = data.pagination and data.pagination.hasMore
		if onProgress then onProgress(#all, hasMore) end
		if not hasMore then break end
		page = page + 1
		if page > 100 then break end
	end
	return all, true
end

local function RebuildValuesIndex()
	Values.byName = {}
	if not Values.cache then return end
	for _, item in ipairs(Values.cache) do
		Values.byName[string.lower(tostring(item.name or ""))] = item
	end
end

local valueSearchBox = createSettingRow("Search weapon:", "", valuesFrame)
CreateSpace(valuesFrame)

local valueStatusLabel = Instance.new("TextLabel")
valueStatusLabel.Size = UDim2.new(1, 0, 0, 18)
valueStatusLabel.BackgroundTransparency = 1
valueStatusLabel.Text = "Loading values..."
valueStatusLabel.Font = Enum.Font.SourceSans
valueStatusLabel.TextSize = 12
valueStatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
valueStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
valueStatusLabel.Parent = valuesFrame

local resultsScroll = Instance.new("ScrollingFrame")
resultsScroll.Size = UDim2.new(1, 0, 0, 200)
resultsScroll.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
resultsScroll.BackgroundTransparency = 0.3
resultsScroll.BorderSizePixel = 0
resultsScroll.ScrollBarThickness = 6
resultsScroll.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 255)
resultsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
resultsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
resultsScroll.Parent = valuesFrame

do
	local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 5) c.Parent = resultsScroll
	local lay = Instance.new("UIListLayout") lay.FillDirection = Enum.FillDirection.Vertical
	lay.SortOrder = Enum.SortOrder.LayoutOrder lay.Padding = UDim.new(0, 2) lay.Parent = resultsScroll
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 3) pad.PaddingBottom = UDim.new(0, 3)
	pad.PaddingLeft = UDim.new(0, 3) pad.PaddingRight = UDim.new(0, 3)
	pad.Parent = resultsScroll
end

local function _updateValuesScrollHeight()
	local offsetY = resultsScroll.AbsolutePosition.Y - valuesFrame.AbsolutePosition.Y
	local available = valuesFrame.AbsoluteSize.Y - offsetY - 40
	resultsScroll.Size = UDim2.new(1, 0, 0, math.max(80, available))
end
valuesFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(_updateValuesScrollHeight)
task.defer(_updateValuesScrollHeight)

CreateSpace(valuesFrame)

local function RenderValueResults(items)
	for _, c in ipairs(resultsScroll:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	if not items then return end
	for _, item in ipairs(items) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -6, 0, 40)
		row.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
		row.BackgroundTransparency = 0.2
		row.Parent = resultsScroll

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 4)
		rowCorner.Parent = row

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(0.62, -8, 0, 20)
		nameLbl.Position = UDim2.new(0, 8, 0, 2)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = tostring(item.name)
		nameLbl.Font = Enum.Font.SourceSansSemibold
		nameLbl.TextSize = 13
		nameLbl.TextColor3 = Color3.fromRGB(240, 240, 255)
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Parent = row

		local metaParts = {}
		if item.rarity then table.insert(metaParts, tostring(item.rarity)) end
		if item.demand then table.insert(metaParts, "Demand " .. tostring(item.demand)) end
		if item.trend then table.insert(metaParts, tostring(item.trend)) end
		local metaLbl = Instance.new("TextLabel")
		metaLbl.Size = UDim2.new(0.62, -8, 0, 16)
		metaLbl.Position = UDim2.new(0, 8, 0, 22)
		metaLbl.BackgroundTransparency = 1
		metaLbl.Text = table.concat(metaParts, " | ")
		metaLbl.Font = Enum.Font.SourceSans
		metaLbl.TextSize = 11
		metaLbl.TextColor3 = Color3.fromRGB(160, 160, 200)
		metaLbl.TextXAlignment = Enum.TextXAlignment.Left
		metaLbl.TextTruncate = Enum.TextTruncate.AtEnd
		metaLbl.Parent = row

		local valLbl = Instance.new("TextLabel")
		valLbl.Size = UDim2.new(0.38, -8, 1, 0)
		valLbl.Position = UDim2.new(0.62, 0, 0, 0)
		valLbl.BackgroundTransparency = 1
		valLbl.Text = FormatValue(item.value)
		valLbl.Font = Enum.Font.FredokaOne
		valLbl.TextSize = 14
		valLbl.TextColor3 = Color3.fromRGB(120, 255, 160)
		valLbl.TextXAlignment = Enum.TextXAlignment.Right
		valLbl.Parent = row
	end
end

local function FilterCachedValues(query)
	if not Values.cache then return nil end
	if query == nil or query == "" then return Values.cache end
	local q = string.lower(query)
	local out = {}
	for _, item in ipairs(Values.cache) do
		local name = string.lower(tostring(item.name or ""))
		local rarity = string.lower(tostring(item.rarity or ""))
		if string.find(name, q, 1, true) or string.find(rarity, q, 1, true) then
			table.insert(out, item)
		end
	end
	return out
end

local function RenderFilteredResults(query)
	local items = FilterCachedValues(query)
	if not items then
		RenderValueResults({})
		return 0, 0
	end
	local total = #items
	local capped = items
	if total > 250 then
		capped = {}
		for i = 1, 250 do capped[i] = items[i] end
	end
	RenderValueResults(capped)
	return #capped, total
end

local function UpdateValuesStatus(query)
	if not Values.cache then return end
	local shown, total = RenderFilteredResults(query)
	if total == 0 then
		valueStatusLabel.Text = "No matches in " .. #Values.cache .. " items"
		valueStatusLabel.TextColor3 = Color3.fromRGB(255, 150, 100)
	elseif shown < total then
		valueStatusLabel.Text = "Showing " .. shown .. " of " .. total .. " matches (type more to narrow)"
		valueStatusLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
	else
		valueStatusLabel.Text = total .. " match" .. (total == 1 and "" or "es")
			.. " (catalog: " .. #Values.cache .. ")"
		valueStatusLabel.TextColor3 = Color3.fromRGB(120, 255, 160)
	end
end

local function LoadFullCatalog(force)
	if Values.fetching then
		valueStatusLabel.Text = "already fetching... (be patient)"
		valueStatusLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
		return
	end
	if (not force) and Values.cache and (tick() - Values.fetchedAt) < 600 then
		UpdateValuesStatus(valueSearchBox.Text)
		return
	end
	Values.fetching = true
	task.spawn(function()
		valueStatusLabel.Text = "Fetching catalog..."
		valueStatusLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
		local items, ok = FetchAllValues(function(loaded, hasMore)
			valueStatusLabel.Text = ("Loaded %d items%s"):format(loaded, hasMore and "... (more pages)" or " -- finalizing")
		end)
		Values.fetching = false
		if items and #items > 0 then
			Values.cache = items
			Values.fetchedAt = tick()
			RebuildValuesIndex()
			UpdateValuesStatus(valueSearchBox.Text)
		else
			valueStatusLabel.Text = "API request failed -- executor blocked http? (see console)"
			valueStatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
			warn("[mm2run] cosmic values API returned nothing. httpRequest=" .. tostring(httpRequest ~= nil))
		end
	end)
end

CreateButton(valuesFrame, "Refresh catalog", function()
	LoadFullCatalog(true)
end)

valueSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
	if Values.cache then
		UpdateValuesStatus(valueSearchBox.Text)
	end
end)

task.spawn(function() LoadFullCatalog(false) end)
