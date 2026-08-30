local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local openSpinWheel
local statusToast
local partnerInput
local inputStroke

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ── MM2 Trade remotes ────────────────────────────────────────
local TradeRS = ReplicatedStorage:WaitForChild("Trade")
local Remote = {
    SendRequest    = TradeRS:WaitForChild("SendRequest"),
    CancelRequest  = TradeRS:WaitForChild("CancelRequest"),
    AcceptRequest  = TradeRS:WaitForChild("AcceptRequest"),
    DeclineRequest = TradeRS:WaitForChild("DeclineRequest"),
    OfferItem      = TradeRS:WaitForChild("OfferItem"),
    RemoveOffer    = TradeRS:WaitForChild("RemoveOffer"),
    AcceptTrade    = TradeRS:WaitForChild("AcceptTrade"),
    CancelAccept   = TradeRS:WaitForChild("CancelAccept"),
    DeclineTrade   = TradeRS:WaitForChild("DeclineTrade"),
    UpdateTrade    = TradeRS:WaitForChild("UpdateTrade"),
    StartTrade     = TradeRS:WaitForChild("StartTrade"),
    RequestSent    = TradeRS:WaitForChild("RequestSent"),
}

-- ============================================================
--  MODULE REQUIRES
-- ============================================================
local ProfileData = nil
pcall(function()
    local m = ReplicatedStorage:FindFirstChild("Modules")
    if m then local p = m:FindFirstChild("ProfileData"); if p then ProfileData = require(p) end end
end)

local ItemModule = nil
pcall(function()
    local paths = {{"Modules","ItemModule"},{"Modules","Item"},{"ItemModule"},{"Item"}}
    for _, path in ipairs(paths) do
        local m = ReplicatedStorage
        for _, part in ipairs(path) do m = m:FindFirstChild(part); if not m then break end end
        if m then local ok, r = pcall(require, m); if ok and r and r.DisplayItem then ItemModule = r; break end end
    end
end)

local ItemPopupService = {
    AnimationTargetLocation = nil,
    ItemReceived            = Instance.new("BindableEvent"),
    ItemClaimsComplete      = Instance.new("BindableEvent"),
}
function ItemPopupService:AddNewItem(itemData, amount, source)
    self.ItemReceived:Fire(itemData, amount, source)
end
do
    local function tryGet(...)
        local node = ReplicatedStorage
        for _, part in ipairs({...}) do
            node = node:FindFirstChild(part); if not node then return nil end
        end
        local ok, r = pcall(require, node)
        return ok and r or nil
    end
    local real = tryGet("ClientServices","ItemPopupService")
              or tryGet("Modules","ItemPopupService")
    if real and real.AddNewItem then ItemPopupService = real end
end

local TradeModule = nil
pcall(function()
    local m = ReplicatedStorage:FindFirstChild("Modules")
    if m then local t = m:FindFirstChild("TradeModule"); if t then TradeModule = require(t) end end
end)

local InventoryModule = nil
pcall(function()
    local m = ReplicatedStorage:FindFirstChild("Modules")
    if m then local i = m:FindFirstChild("InventoryModule"); if i then InventoryModule = require(i) end end
end)

local DB = nil
pcall(function()
    local db = ReplicatedStorage:FindFirstChild("Database")
    if db then local s = db:FindFirstChild("Sync"); if s then DB = require(s) end end
end)

_G.Cache      = _G.Cache      or {}
_G.SmallCache = _G.SmallCache or {}

if ProfileData then
    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if not remotes then return end
        local inv = remotes:FindFirstChild("Inventory")
        if not inv then return end
        local r = inv:FindFirstChild("ChangeInventoryItem")
        if not r then return end
        local weaponTypes = { Weapons=true, Pets=true, Materials=true }
        r.OnClientEvent:Connect(function(category, itemID, value)
            if weaponTypes[category] then
                ProfileData[category].Owned[itemID] = value
            elseif value ~= nil and value > 0 then
                table.insert(ProfileData[category].Owned, itemID)
            end
            if _G.UpdateEmotes then _G.UpdateEmotes() end
        end)
    end)
end

-- ============================================================
--  FAKE TRADE STATE
-- ============================================================
local fakeTrade = { active=false, partnerName="", yourOffer={}, theirOffer={} }
local stagedTheirItems = {}
local stagedYourItems  = {}

-- ============================================================
--  DATA
-- ============================================================
local godlies = {
    "Seer","Elderwood Scythe","Chroma Corrupt","Icicle","Candy Cane",
    "Dark Matter","Sunray","Hallows Edge","Batwing","Ghostwalker",
    "Laser Vision","Logchopper","Gingerblade","Heartblade","Eternal",
}

local highTierPool = {
    "TravelersGun","Evergun","Constellation","Evergreen","Turkey","Alienbeam",
    "VampiresGun","Darkshot","Darksword","Raygun","Sunrise","Snowcannon",
    "Bauble","Sunset","HeartWand","Soul","Spirit","Flora","Bloom","RainbowGun",
    "Rainbow","SnowDagger","FlowerwoodGun","Flowerwood","Xenoknife","Xenoshot",
    "Watergun","Ocean","Waves","Treat","Sweet","Blizzard",
    "Gingerscope","TravelersAxe","Celestial","VampireAxe","Harvester","Icepiercer",
}

local highValueWeapons = {
    {name = "Gingerscope",     value = 18500, tier = "Ancient"},
    {name = "Traveler's Axe",   value = 8100,  tier = "Ancient"},
    {name = "Celestial",       value = 1725,  tier = "Ancient"},
    {name = "Vampire's Axe",    value = 925,   tier = "Ancient"},
    {name = "Harvester",       value = 300,   tier = "Ancient"},
    {name = "Icepiercer",      value = 200,   tier = "Ancient"},
    {name = "Traveler's Gun",   value = 4300,  tier = "Godly"},
    {name = "Evergun",         value = 3400,  tier = "Godly"},
    {name = "Constellation",   value = 2900,  tier = "Godly"},
    {name = "Evergreen",       value = 2550,  tier = "Godly"},
    {name = "Alienbeam",       value = 2200,  tier = "Godly"},
    {name = "Turkey",          value = 1925,  tier = "Godly"},
    {name = "Vampire's Gun",    value = 1700,  tier = "Godly"},
    {name = "Raygun",          value = 1400,  tier = "Godly"},
    {name = "Darkshot",        value = 1200,  tier = "Godly"},
    {name = "Darksword",       value = 1180,  tier = "Godly"},
    {name = "Blossom",         value = 1100,  tier = "Godly"},
    {name = "Sakura",          value = 1090,  tier = "Godly"},
    {name = "Bauble",          value = 925,   tier = "Godly"},
    {name = "Sunrise",         value = 750,   tier = "Godly"},
    {name = "Snowcannon",      value = 675,   tier = "Godly"},
    {name = "Sunset",          value = 600,   tier = "Godly"},
    {name = "Soul",            value = 330,   tier = "Godly"},
    {name = "Spirit",          value = 320,   tier = "Godly"},
    {name = "Heart Wand",      value = 260,   tier = "Godly"},
    {name = "Treat",           value = 215,   tier = "Godly"},
    {name = "Sweet",           value = 210,   tier = "Godly"},
    {name = "Watergun",        value = 140,   tier = "Godly"},
    {name = "Xenoknife",       value = 160,   tier = "Godly"},
    {name = "Xenoshot",        value = 160,   tier = "Godly"},
    {name = "Snow Dagger",     value = 205,   tier = "Godly"},
}

local usersList = {
    "aliceroblox6166","DIVAHOLIC","iiicristianxx_o","Darcie_epic","banan_bartek1234",
    "s18amg","Chicken_nuggitx23817","RmSbx_x","siqnnaz","Nidaanurr7","Kkiraly",
    "daisydoo_billy","youssefsalah135","aurivxs","princeplay","sofysofy986353",
    "heaseung008800112277","Agusmareborn","Kellyvault","J3llynoah","Rainbowriley321",
    "hweartsouls","h3llsang3lx","Xcallmeholly","Niniko_201999","Hugso09",
    "ruthjavxn","bubblesxwrldd","Hugeinvestor","Barborich2","Underthechemtrailss",
    "Bunzvii","Qwrtylostaccount","Sparklingorangelol","Tr3ndzyy","Jellycmt","Ex4clusiv3",
    "Killersana66","Chasedatfund","Pukgames0","Lathifcal","Tadhghogan009","Firefelineyt",
    "Jasperisdic","Coalberto","Mouasx","CodyPlays","Obvk1rk","Medinololboi",
    "0bvskileyxo","dwsiredsouls","Track_T0R","glowtropics","Cqvrleo","Alisawants",
    "Themeganplays","Avqrsz","EvergreenPlane","Elisacanlisten","Money_Money1000",
    "Al3xsrz","000teenvogue","Stranger_s4mu","Pradasvogue","Adore1ucax","Sincevampire",
    "Iobotomyd","Woofnico","Sillyoldgoose","Obvliams","Juandicrack777","Lionheart_xo",
}

local serverPlayers = {}
local supremeValues = {}
local function refreshServerPlayers()
    serverPlayers = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(serverPlayers, p.Name) end
    end
end
refreshServerPlayers()
Players.PlayerAdded:Connect(function()    task.wait(0.5); refreshServerPlayers() end)
Players.PlayerRemoving:Connect(function() task.wait(0.5); refreshServerPlayers() end)

-- ============================================================
--  ITEM HELPERS
-- ============================================================
local function notifyItemsReceived(items)
    if not ItemPopupService then return end
    for _, item in ipairs(items) do
        pcall(function() ItemPopupService.ItemReceived:Fire(item.ItemID, item.ItemType or "Weapons") end)
    end
end

local function getItemKey(d)
    if not d then return nil end
    return d.DataID or d.ItemID or d.ID or d.Id or d.id
        or d._ID or d.ItemName or d.Name or d.DisplayName
end

local function updateInvFrameCount(invFrame, remaining)
    if not invFrame then return end
    if remaining <= 0 then
        invFrame.Visible = false
    else
        invFrame.Visible = true
        pcall(function()
            invFrame.Container.Amount.Text = remaining > 1 and ("x" .. remaining) or ""
        end)
    end
end

local function resolveDBItem(id)
    if not DB or not DB.Weapons then return id, nil end
    local function isValid(data)
        if type(data) ~= "table" then return false end
        local r = data.Rarity or ""
        if r == "Unique" or r == "Common" or r == "Uncommon" or r == "Rare" then return false end
        return true
    end
    if DB.Weapons[id] and isValid(DB.Weapons[id]) then return id, DB.Weapons[id] end
    local noSpace = id:gsub("%s+", "")
    if DB.Weapons[noSpace] and isValid(DB.Weapons[noSpace]) then return noSpace, DB.Weapons[noSpace] end
    local stripped = id:gsub("[^%w]", "")
    if DB.Weapons[stripped] and isValid(DB.Weapons[stripped]) then return stripped, DB.Weapons[stripped] end
    local strippedLower = stripped:lower()
    local bestID, bestData, bestScore = nil, nil, 0
    local rarityScore = {Ancient=5, Chroma=4, Godly=3, Legendary=2}
    for dbID, dbData in pairs(DB.Weapons) do
        if isValid(dbData) then
            local idMatch   = dbID:gsub("[^%w]", ""):lower() == strippedLower
            local nameMatch = (dbData.ItemName or dbData.Name or ""):gsub("[^%w]", ""):lower() == strippedLower
            if idMatch or nameMatch then
                local score = rarityScore[dbData.Rarity or ""] or 1
                if score > bestScore then
                    bestScore = score; bestID = dbID; bestData = dbData
                end
            end
        end
    end
    if bestID then return bestID, bestData end
    return id, nil
end

local function SpawnItem(ItemName, Amount, ItemType)
    Amount = Amount or 1
    ItemType = ItemType or "Weapons"
    pcall(function()
        if ProfileData and ProfileData[ItemType] and ProfileData[ItemType].Owned then
            if ProfileData[ItemType].Owned[ItemName] == nil then
                ProfileData[ItemType].Owned[ItemName] = Amount
            else
                ProfileData[ItemType].Owned[ItemName] = ProfileData[ItemType].Owned[ItemName] + Amount
            end
            pcall(function()
                ReplicatedStorage.Remotes.Inventory.InventoryDataChanged:Fire(ItemType, ItemName, ProfileData[ItemType].Owned[ItemName])
            end)
            pcall(function()
                ReplicatedStorage.Remotes.Inventory.InventoryDataChanged:Fire()
            end)
            if ItemPopupService then
                if ItemPopupService.AddNewItem then
                    ItemPopupService:AddNewItem(ItemName, ItemType, Amount)
                elseif ItemPopupService.ItemReceived then
                    ItemPopupService.ItemReceived:Fire(ItemName, ItemType, Amount)
                end
            end
        end
    end)
end

-- ============================================================
--  FAKE TRADE ENGINE
-- ============================================================
local SimGUI, Container, Trade, YourOffer, TheirOffer, Actions, ItemsPanel

local MAX_SLOTS      = 4
local YourSlots      = {}
local TheirSlots     = {}
local SimState       = "Idle"
local AcceptState    = "Accept"
local TradeInventory = nil
local InvFrames      = {}
local pipelineEpoch  = 0

local TradeTable = {
    Player1 = { Offer={}, Accepted=false },
    Player2 = { Offer={}, Accepted=false },
    Locked  = false,
}

local function getTradeGui()
    for _, n in ipairs({"TradeGui","TradeGUI","Trade"}) do
        local g = PlayerGui:FindFirstChild(n); if g then return g end
    end
end

local function initSimGUI()
    if SimGUI then pcall(function() SimGUI:Destroy() end); SimGUI = nil end
    local TradeGUI = getTradeGui(); if not TradeGUI then return false end
    SimGUI = TradeGUI:Clone()
    SimGUI.Name = "MockTradeSimulator"; SimGUI.Enabled = false; SimGUI.Parent = PlayerGui
    Container  = SimGUI:FindFirstChild("Container"); if not Container then return false end
    Trade      = Container:FindFirstChild("Trade");  if not Trade then return false end
    YourOffer  = Trade:FindFirstChild("YourOffer")
    TheirOffer = Trade:FindFirstChild("TheirOffer")
    Actions    = Trade:FindFirstChild("Actions")
    ItemsPanel = Container:FindFirstChild("Items")
    return true
end

local function GetSlotFrame(offerFrame, index)
    if not offerFrame then return nil end
    local c = offerFrame:FindFirstChild("Container"); if not c then return nil end
    return c:FindFirstChild("NewItem"..index)
end

local function DisplaySlot(offerFrame, index, itemData)
    local slot = GetSlotFrame(offerFrame, index); if not slot then return end
    if itemData then
        local ok = false
        if ItemModule and ItemModule.DisplayItem then
            if not ok then pcall(function() ItemModule.DisplayItem(slot, itemData);            ok=true end) end
            if not ok then pcall(function() ItemModule.DisplayItem(slot, itemData, nil, true); ok=true end) end
        end
        if not ok then
            local lbl = slot:FindFirstChild("_TMLabel") or Instance.new("TextLabel")
            lbl.Name="_TMLabel"; lbl.Size=UDim2.new(1,0,0.45,0)
            lbl.Position=UDim2.new(0,0,0.55,0); lbl.BackgroundTransparency=1
            lbl.TextColor3=Color3.fromRGB(255,255,255); lbl.TextSize=9
            lbl.Font=Enum.Font.GothamBold; lbl.TextWrapped=true
            lbl.ZIndex=(slot.ZIndex or 1)+2
            lbl.Text=itemData.ItemName or itemData.Name or itemData.DataID or "?"
            lbl.Parent=slot
        end
        slot.Visible = true
    else
        pcall(function() ItemModule.DisplayItem(slot, nil) end)
        local lbl = slot:FindFirstChild("_TMLabel"); if lbl then lbl:Destroy() end
        slot.Visible = false
    end
end

local function CompactSlots(slots)
    local c = {}
    for i = 1, MAX_SLOTS do if slots[i] then table.insert(c, slots[i]) end end
    for i = 1, MAX_SLOTS do slots[i] = c[i] or nil end
end

local function RefreshAllSlots()
    for i = 1, MAX_SLOTS do
        DisplaySlot(YourOffer, i, YourSlots[i])
        DisplaySlot(TheirOffer, i, TheirSlots[i])
    end
end

local function AddToSide(slots, itemData)
    local key = getItemKey(itemData)
    if key then
        for i = 1, MAX_SLOTS do
            if slots[i] and getItemKey(slots[i]) == key then
                slots[i].Amount = (slots[i].Amount or 1) + 1
                return true
            end
        end
    end
    for i = 1, MAX_SLOTS do
        if not slots[i] then
            slots[i] = itemData; slots[i].Amount = 1
            return true
        end
    end
    return false
end

local function RemoveFromSide(slots, index)
    local item = slots[index]; if not item then return end
    local amount = item.Amount or 1
    if amount > 1 then
        slots[index].Amount = amount - 1
    else
        slots[index] = nil; CompactSlots(slots)
    end
end

local function Reclone(parent, childName)
    if not parent then return nil end
    local child = parent:FindFirstChild(childName); if not child then return nil end
    local new = child:Clone(); child:Destroy(); new.Parent=parent; return new
end

local CooldownActive  = false
local CooldownSeconds = 0
local function ResetCooldown(skip)
    if not Actions then return end
    local cooldownFrame = Actions.Accept and Actions.Accept:FindFirstChild("Cooldown")
    if skip then
        CooldownSeconds = 0; CooldownActive = false
        if cooldownFrame then cooldownFrame.Visible = false end
        return
    end
    if CooldownActive then CooldownSeconds = 6; return end
    CooldownActive = true; CooldownSeconds = 6
    if cooldownFrame then
        cooldownFrame.Visible = true
        local titleLbl = cooldownFrame:FindFirstChild("Title")
        task.spawn(function()
            while CooldownSeconds > 0 do
                if titleLbl then titleLbl.Text = " Please wait ("..CooldownSeconds..") before accepting." end
                task.wait(1); CooldownSeconds = CooldownSeconds - 1
            end
            CooldownActive = false
            if cooldownFrame then cooldownFrame.Visible = false end
        end)
    end
end

local function resetTradeUI()
    if not Actions then return end
    pcall(function() Actions.Accept.Visible         = true  end)
    pcall(function() Actions.Accept.Confirm.Visible = false end)
    pcall(function() Actions.Accept.Cancel.Visible  = false end)
    pcall(function() Actions.Decline.Visible        = true  end)
    pcall(function() YourOffer.Accepted.Visible     = false end)
    pcall(function() TheirOffer.Accepted.Visible    = false end)
end

local function OnItemsChanged()
    RefreshAllSlots()
    if SimState == "Accepted" then pipelineEpoch = pipelineEpoch + 1; SimState="Active"; AcceptState="Accept"; resetTradeUI() end
    if AcceptState == "Confirm" then
        AcceptState = "Accept"
        pcall(function() Actions.Accept.Confirm.Visible = false end)
        pcall(function() Actions.Accept.Cancel.Visible  = false end)
    end
    local yc, tc = 0, 0
    for i = 1, MAX_SLOTS do
        if YourSlots[i]  then yc = yc + 1 end
        if TheirSlots[i] then tc = tc + 1 end
    end
    ResetCooldown(yc < 1 and tc < 1)
end

local SetSimState
SetSimState = function(newState)
    SimState = newState
    if newState == "Active" then AcceptState="Accept"; resetTradeUI()
    elseif newState == "Accepted" then
        AcceptState = "Waiting"
        TradeTable.Player1.Accepted = true
        pcall(function() YourOffer.Accepted.Visible    = true end)
        pcall(function() Actions.Accept.Cancel.Visible = true end)
        local myEpoch = pipelineEpoch
        task.delay(1.4, function()
            if pipelineEpoch ~= myEpoch then return end
            TradeTable.Player2.Accepted = true
            pcall(function() TheirOffer.Accepted.Visible = true end)
            task.delay(0.6, function()
                if pipelineEpoch ~= myEpoch then return end
                if not (TradeTable.Player1.Accepted and TradeTable.Player2.Accepted) then return end
                TradeTable.Locked = true
                for _, item in ipairs(TradeTable.Player2.Offer) do
                    SpawnItem(item[1], item[2], item[3])
                end
                if SimGUI then SimGUI.Enabled = false end
                SetSimState("Idle")
            end)
        end)
    elseif newState == "Idle" then
        AcceptState = "Accept"; ResetCooldown(true)
        if Actions then resetTradeUI() end
    end
end

local function DisconnectRealButtons()
    if not Actions then return end
    pcall(function() Reclone(Actions.Accept,         "ActionButton") end)
    pcall(function() Reclone(Actions.Accept.Confirm, "ActionButton") end)
    pcall(function() Reclone(Actions.Accept.Cancel,  "ActionButton") end)
    pcall(function() Reclone(Actions.Decline,        "ActionButton") end)
    for _, offerFrame in ipairs({YourOffer, TheirOffer}) do
        if offerFrame then
            local c = offerFrame:FindFirstChild("Container")
            if c then
                for i = 1, MAX_SLOTS do
                    local slot = c:FindFirstChild("NewItem"..i)
                    if slot and slot:FindFirstChild("Container") then
                        Reclone(slot.Container, "ActionButton")
                    end
                end
            end
        end
    end
end

local function ConnectSlotClicks()
    for i = 1, MAX_SLOTS do
        local yi = i
        local yourSlot = GetSlotFrame(YourOffer, i)
        if yourSlot and yourSlot:FindFirstChild("Container") then
            local btn = yourSlot.Container:FindFirstChild("ActionButton")
            if btn then btn.MouseButton1Click:Connect(function()
                if not YourSlots[yi] then return end
                RemoveFromSide(YourSlots, yi); OnItemsChanged()
            end) end
        end
        local theirSlot = GetSlotFrame(TheirOffer, i)
        if theirSlot and theirSlot:FindFirstChild("Container") then
            local btn = theirSlot.Container:FindFirstChild("ActionButton")
            if btn then btn.MouseButton1Click:Connect(function()
                if not TheirSlots[yi] then return end
                RemoveFromSide(TheirSlots, yi); OnItemsChanged()
            end) end
        end
    end
end

local function ConnectSimulatorActions()
    if not Actions then return end
    local confirmTime = 0
    pcall(function()
        Actions.Accept.ActionButton.MouseButton1Click:Connect(function()
            if SimState ~= "Active" then return end
            if CooldownSeconds > 0 then return end
            if AcceptState ~= "Accept" then return end
            AcceptState = "Confirm"; confirmTime = tick()
            pcall(function() Actions.Accept.Confirm.Visible = true end)
        end)
    end)
    pcall(function()
        Actions.Accept.Confirm.ActionButton.MouseButton1Click:Connect(function()
            if SimState ~= "Active" then return end
            if CooldownSeconds > 0 then return end
            if AcceptState ~= "Confirm" then return end
            if tick() - confirmTime < 0.4 then return end
            AcceptState = "Waiting"
            pcall(function() YourOffer.Accepted.Visible    = true end)
            pcall(function() Actions.Accept.Cancel.Visible = true end)
            SetSimState("Accepted")
        end)
    end)
    pcall(function()
        Actions.Accept.Cancel.ActionButton.MouseButton1Click:Connect(function()
            pipelineEpoch = pipelineEpoch + 1; AcceptState = "Accept"; SimState = "Active"
            pcall(function() YourOffer.Accepted.Visible = false end)
            resetTradeUI(); ResetCooldown(false)
        end)
    end)
    pcall(function()
        Actions.Decline.ActionButton.MouseButton1Click:Connect(function()
            pipelineEpoch = pipelineEpoch + 1; AcceptState = "Accept"
            SetSimState("Idle")
            if SimGUI then SimGUI.Enabled = false end
        end)
    end)
end

local function ConnectItemsPanelButtons()
    if not Actions or not ItemsPanel then return end
    pcall(function()
        local addBtn = Actions:FindFirstChild("AddItems") or Actions:FindFirstChild("AddItem")
            or (Actions.Accept and Actions.Accept:FindFirstChild("AddItem"))
        if addBtn then
            local btn = addBtn:FindFirstChild("ActionButton")
            if btn then btn.MouseButton1Click:Connect(function()
                if SimState ~= "Active" then return end
                ItemsPanel.Visible = true
            end) end
        end
    end)
    pcall(function()
        ItemsPanel.Tabs.Close.ActionButton.MouseButton1Click:Connect(function()
            ItemsPanel.Visible = false
        end)
    end)
end

local function PopulateInventoryPanel()
    if not InventoryModule or not ProfileData or not ItemsPanel then return end
    pcall(function()
        TradeInventory = InventoryModule.GenerateInventory(ItemsPanel, ProfileData, "Trading", nil)
    end)
    if not TradeInventory then return end
    for _, tabs in pairs(TradeInventory.Data) do
        for _, items in pairs(tabs) do
            for _, itemData in pairs(items) do
                local frame = itemData.Frame
                local key = getItemKey(itemData)
                if frame and key then
                    InvFrames[key] = frame
                    itemData._ownedAmount = itemData.Amount or 1
                    if frame:FindFirstChild("Container") then
                        local btn = Reclone(frame.Container, "ActionButton")
                        if btn then
                            local capturedKey  = key
                            local capturedData = itemData
                            btn.Activated:Connect(function()
                                if SimState ~= "Active" then return end
                                local owned = capturedData._ownedAmount or 1
                                local inSlots = 0
                                for i = 1, MAX_SLOTS do
                                    if YourSlots[i] and getItemKey(YourSlots[i]) == capturedKey then
                                        inSlots = inSlots + (YourSlots[i].Amount or 1)
                                    end
                                end
                                if inSlots >= owned then return end
                                local copy = {}
                                for k, v in pairs(capturedData) do copy[k] = v end
                                copy.Amount = 1; copy._ownedAmount = owned
                                if AddToSide(YourSlots, copy) then OnItemsChanged() end
                            end)
                        end
                    end
                end
            end
        end
    end
end

local function cancelFakeTrade()
    pipelineEpoch = pipelineEpoch + 1
    fakeTrade.active=false; fakeTrade.partnerName=""; fakeTrade.yourOffer={}; fakeTrade.theirOffer={}
    stagedTheirItems={}; stagedYourItems={}; TradeInventory=nil; InvFrames={}
    for i = 1, MAX_SLOTS do YourSlots[i]=nil; TheirSlots[i]=nil end
    if SimGUI then SimGUI.Enabled = false end
    SimState="Idle"; AcceptState="Accept"; ResetCooldown(true)
    if Actions then resetTradeUI() end
end

local tradeGuiHooked = false
local function hookTradeGuiClose()
    if tradeGuiHooked then return end; if not SimGUI then return end
    tradeGuiHooked = true
    SimGUI:GetPropertyChangedSignal("Enabled"):Connect(function()
        if not SimGUI.Enabled and fakeTrade.active then cancelFakeTrade() end
    end)
end

local function startFakeTrade(partnerName, theirItems)
    tradeGuiHooked = false; pipelineEpoch = pipelineEpoch + 1
    if not initSimGUI() then warn("[FakeTrade] Could not init SimGUI"); return end
    fakeTrade.active=true; fakeTrade.partnerName=partnerName
    fakeTrade.yourOffer={}; fakeTrade.theirOffer=theirItems or {}
    for i = 1, MAX_SLOTS do YourSlots[i]=nil; TheirSlots[i]=nil end
    TradeTable={Player1={Offer={},Accepted=false},Player2={Offer={},Accepted=false},Locked=false}
    pcall(function() TheirOffer.Username.Text = "("..partnerName..")" end)
    for i, item in ipairs(theirItems or {}) do
        if i > MAX_SLOTS then break end
        local itemData = {
            DataID=item.ItemID, DataType=item.ItemType or "Weapons",
            Amount=item.Amount or 1, Name=item.ItemID, ItemName=item.ItemID,
        }
        TheirSlots[i] = itemData
    end
    if #(theirItems or {}) > 0 then notifyItemsReceived(theirItems) end
    DisconnectRealButtons(); ConnectSlotClicks(); ConnectSimulatorActions(); ConnectItemsPanelButtons()
    ResetCooldown(true); AcceptState="Accept"; resetTradeUI()
    PopulateInventoryPanel(); RefreshAllSlots()
    SimState = "Active"; SimGUI.Enabled = true
    hookTradeGuiClose()
end

local function addGodlyToTheirSide()
    if not SimGUI or not SimGUI.Enabled then return end
    local pick = godlies[math.random(1,#godlies)]
    if AddToSide(TheirSlots, {DataID=pick,DataType="Weapons",Amount=1,Name=pick,ItemName=pick}) then
        OnItemsChanged()
    end
end

local function removeFromTheirSide()
    if not SimGUI or not SimGUI.Enabled then return end
    for i = MAX_SLOTS, 1, -1 do
        if TheirSlots[i] then RemoveFromSide(TheirSlots, i); OnItemsChanged(); break end
    end
end

local RunService = game:GetService("RunService")
local function BlockPlayerSilent(player)
    if not player then return end
    pcall(function() setthreadidentity(8) end)
    game:GetService("StarterGui"):SetCore("PromptBlockPlayer", player)
    local startTime = tick(); local modal = nil
    while not modal do
        RunService.Heartbeat:Wait()
        if tick() - startTime > 10 then pcall(function() setthreadidentity(2) end); return end
        local overlay = game:GetService("CoreGui"):FindFirstChild("FoundationOverlay")
        if overlay then modal = overlay:FindFirstChild("BlockingModalScreen", true) end
    end
    local function hideModal()
        pcall(function()
            modal.BackgroundTransparency = 1
            for _, desc in ipairs(modal:GetDescendants()) do
                pcall(function()
                    if desc:IsA("ImageLabel") or desc:IsA("ImageButton") then desc.ImageTransparency=1; desc.BackgroundTransparency=1 end
                    if desc:IsA("TextLabel") or desc:IsA("TextButton") then desc.TextTransparency=1; desc.BackgroundTransparency=1 end
                    if desc:IsA("Frame") then desc.BackgroundTransparency=1 end
                    if desc:IsA("UIStroke") then desc.Transparency=1 end
                end)
            end
        end)
    end
    hideModal()
    local posConn
    posConn = RunService.Heartbeat:Connect(function()
        pcall(function()
            if modal and modal.Parent then hideModal()
            else posConn:Disconnect() end
        end)
    end)
    local confirmBtn = nil
    pcall(function() confirmBtn = modal.BlockingModalContainerWrapper.BlockingModal.AlertModal.AlertContents.Footer.Buttons["1"] end)
    if not confirmBtn then pcall(function() confirmBtn = modal.BlockingModalContainerWrapper.BlockingModal.AlertModal.AlertContents.Footer.Buttons["3"] end) end
    if confirmBtn then
        local attempts = 0
        while attempts < 20 do
            attempts = attempts + 1
            pcall(function() game:GetService("GuiService").SelectedObject = confirmBtn end)
            task.wait()
            pcall(function()
                if game:GetService("GuiService").SelectedObject == confirmBtn then
                    game:GetService("VirtualInputManager"):SendKeyEvent(true, Enum.KeyCode.Return, false, game)
                    game:GetService("VirtualInputManager"):SendKeyEvent(false, Enum.KeyCode.Return, false, game)
                end
            end)
            task.wait(0.1)
            pcall(function()
                local ap = confirmBtn.AbsolutePosition; local as = confirmBtn.AbsoluteSize
                local vim = game:GetService("VirtualInputManager")
                vim:SendMouseButtonEvent(ap.X+as.X/2, ap.Y+as.Y/2, 0, true, game, 1)
                task.wait()
                vim:SendMouseButtonEvent(ap.X+as.X/2, ap.Y+as.Y/2, 0, false, game, 1)
            end)
            pcall(function() if firesignal then firesignal(confirmBtn.MouseButton1Click) end end)
            task.wait(0.2)
            local overlay = game:GetService("CoreGui")
            if not overlay or not overlay:FindFirstChild("BlockingModalScreen", true) then break end
        end
        pcall(function() game:GetService("GuiService").SelectedObject = nil end)
    end
    pcall(function() if posConn then posConn:Disconnect() end end)
    pcall(function() setthreadidentity(2) end)
end

-- ============================================================
--  GUI Construction (Preppy Theme)
-- ============================================================
local TweenService = game:GetService("TweenService")

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "TradeManagerGui"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
ScreenGui.DisplayOrder   = 999
ScreenGui.Parent         = PlayerGui

-- Main Panel
local MainFrame = Instance.new("Frame")
MainFrame.Name             = "MainFrame"
MainFrame.Size             = UDim2.new(0, 250, 0, 520)
MainFrame.Position         = UDim2.new(0, 10, 0, 10)
MainFrame.BackgroundColor3 = Color3.fromRGB(255, 238, 245)  -- blush pearl
MainFrame.BorderSizePixel  = 0
MainFrame.Active           = true
MainFrame.ClipsDescendants = true
MainFrame.Parent           = ScreenGui
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,14); c.Parent = MainFrame
    local s = Instance.new("UIStroke"); s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color = Color3.fromRGB(255, 105, 180); s.Thickness = 2.5; s.Parent = MainFrame
end

-- Dragging
local dragEnabled = true
do
    local dragging, dragStart, startPos, dragInput = false, nil, nil, nil
    MainFrame.InputBegan:Connect(function(inp)
        if not dragEnabled then return end
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = inp.Position; startPos = MainFrame.Position
            inp.Changed:Connect(function()
                if inp.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    MainFrame.InputChanged:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
            dragInput = inp
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if inp == dragInput and dragging then
            local d = inp.Position - dragStart
            MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1,0,0,48); header.Position = UDim2.new(0,0,0,0)
header.BackgroundColor3 = Color3.fromRGB(255, 182, 210)
header.BorderSizePixel = 0; header.Parent = MainFrame
do local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0,14); hc.Parent = header end
do
    local border = Instance.new("Frame")
    border.Size = UDim2.new(1,0,0,2); border.Position = UDim2.new(0,0,1,-2)
    border.BackgroundColor3 = Color3.fromRGB(255, 105, 180); border.BorderSizePixel = 0; border.Parent = header
end

local bowLabel = Instance.new("TextLabel")
bowLabel.Size = UDim2.new(0,20,1,0); bowLabel.Position = UDim2.new(0,6,0,0)
bowLabel.BackgroundTransparency = 1; bowLabel.Text = "🎀"
bowLabel.Font = Enum.Font.FredokaOne; bowLabel.TextSize = 14
bowLabel.TextColor3 = Color3.fromRGB(255,255,255); bowLabel.Parent = header

local headerTitle = Instance.new("TextLabel")
headerTitle.Size = UDim2.new(0.65,-36,1,0); headerTitle.Position = UDim2.new(0,30,0,0)
headerTitle.BackgroundTransparency = 1; headerTitle.Text = "ZetaScripts 🌸"
headerTitle.Font = Enum.Font.FredokaOne; headerTitle.TextSize = 13
headerTitle.TextColor3 = Color3.fromRGB(140, 30, 80)
headerTitle.TextXAlignment = Enum.TextXAlignment.Left; headerTitle.Parent = header

local statusFrame = Instance.new("Frame")
statusFrame.Size = UDim2.new(0,60,1,0); statusFrame.Position = UDim2.new(1,-100,0,0)
statusFrame.BackgroundTransparency = 1; statusFrame.Parent = header

local statusDot = Instance.new("Frame")
statusDot.Size = UDim2.new(0,7,0,7); statusDot.Position = UDim2.new(0,0,0.5,-3.5)
statusDot.BackgroundColor3 = Color3.fromRGB(80, 220, 120); statusDot.BorderSizePixel = 0; statusDot.Parent = statusFrame
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = statusDot end

task.spawn(function()
    while statusDot and statusDot.Parent do
        statusDot.BackgroundTransparency = 0; task.wait(0.5)
        statusDot.BackgroundTransparency = 0.6; task.wait(2)
    end
end)

local statusText = Instance.new("TextLabel")
statusText.Size = UDim2.new(0,40,1,0); statusText.Position = UDim2.new(0,12,0,0)
statusText.BackgroundTransparency = 1; statusText.Text = "v7"
statusText.Font = Enum.Font.FredokaOne; statusText.TextSize = 10
statusText.TextColor3 = Color3.fromRGB(180, 80, 120)
statusText.TextXAlignment = Enum.TextXAlignment.Right; statusText.Parent = statusFrame

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0,26,0,26); CloseBtn.Position = UDim2.new(1,-34,0.5,-13)
CloseBtn.BackgroundColor3 = Color3.fromRGB(255, 140, 175); CloseBtn.BorderSizePixel = 0
CloseBtn.Text = "✕"; CloseBtn.TextSize = 12; CloseBtn.TextColor3 = Color3.fromRGB(255,255,255)
CloseBtn.Font = Enum.Font.FredokaOne; CloseBtn.AutoButtonColor = false; CloseBtn.ZIndex = 10; CloseBtn.Parent = header
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = CloseBtn end
local closeBtnStroke = Instance.new("UIStroke")
closeBtnStroke.Color = Color3.fromRGB(220, 80, 130); closeBtnStroke.Thickness = 1.5; closeBtnStroke.Parent = CloseBtn
CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)
CloseBtn.MouseEnter:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(230, 60, 110)}):Play()
    TweenService:Create(closeBtnStroke, TweenInfo.new(0.12), {Color = Color3.fromRGB(255,200,220)}):Play()
end)
CloseBtn.MouseLeave:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(255, 140, 175)}):Play()
    TweenService:Create(closeBtnStroke, TweenInfo.new(0.12), {Color = Color3.fromRGB(220, 80, 130)}):Play()
end)

-- Tab Bar
local tabsContainer = Instance.new("Frame")
tabsContainer.Size = UDim2.new(1,0,0,36); tabsContainer.Position = UDim2.new(0,0,0,50)
tabsContainer.BackgroundColor3 = Color3.fromRGB(255, 220, 235); tabsContainer.BorderSizePixel = 0; tabsContainer.Parent = MainFrame
do
    local border = Instance.new("Frame")
    border.Size = UDim2.new(1,0,0,2); border.Position = UDim2.new(0,0,1,-2)
    border.BackgroundColor3 = Color3.fromRGB(255, 155, 195); border.BorderSizePixel = 0; border.Parent = tabsContainer
end

local tabNames   = {"Control","Players","Weapons","Spawner","Users","Misc"}
local tabButtons = {}
local panels     = {}

for i, name in ipairs(tabNames) do
    local tabButton = Instance.new("TextButton")
    tabButton.Size = UDim2.new(1/#tabNames, 0, 1, 0)
    tabButton.Position = UDim2.new((i-1)/#tabNames, 0, 0, 0)
    tabButton.BackgroundTransparency = 1; tabButton.Text = string.upper(name)
    tabButton.Font = Enum.Font.FredokaOne; tabButton.TextSize = 9
    tabButton.TextColor3 = i == 1 and Color3.fromRGB(180, 30, 90) or Color3.fromRGB(190, 130, 160)
    tabButton.AutoButtonColor = false; tabButton.Parent = tabsContainer

    local bottomLine = Instance.new("Frame")
    bottomLine.Size = UDim2.new(0.7,0,0,2); bottomLine.Position = UDim2.new(0.15,0,1,-2)
    bottomLine.BackgroundColor3 = Color3.fromRGB(255, 105, 180)
    bottomLine.BorderSizePixel = 0; bottomLine.Visible = (i == 1); bottomLine.Parent = tabButton

    tabButtons[name] = {button = tabButton, line = bottomLine}
end

function switchTab(selected)
    for _, name in ipairs(tabNames) do
        local active = (name == selected)
        if tabButtons[name] and tabButtons[name].button then
            tabButtons[name].button.TextColor3 = active and Color3.fromRGB(180, 30, 90) or Color3.fromRGB(190, 130, 160)
            tabButtons[name].line.Visible = active
        end
        if panels[name] then
            panels[name].Visible = active
        end
    end
end

for _, name in ipairs(tabNames) do
    tabButtons[name].button.MouseButton1Click:Connect(function() switchTab(name) end)
end

-- Content frame
local contentFrame = Instance.new("Frame")
contentFrame.Size = UDim2.new(1,-16,1,-90); contentFrame.Position = UDim2.new(0,8,0,88)
contentFrame.BackgroundTransparency = 1; contentFrame.ClipsDescendants = true; contentFrame.Parent = MainFrame

-- Panel factory
function makePanel(name)
    local f = Instance.new("ScrollingFrame")
    f.Name = name.."Panel"; f.Size = UDim2.new(1,0,1,0)
    f.BackgroundTransparency = 1; f.BorderSizePixel = 0
    f.ScrollBarThickness = 3; f.ScrollBarImageColor3 = Color3.fromRGB(255, 155, 195)
    f.CanvasSize = UDim2.new(0,0,0,0); f.AutomaticCanvasSize = Enum.AutomaticSize.Y
    f.Visible = (name == "Control"); f.Parent = contentFrame
    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.Padding = UDim.new(0,5); layout.Parent = f
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0,4); pad.PaddingBottom = UDim.new(0,8)
    pad.PaddingLeft = UDim.new(0,4); pad.PaddingRight = UDim.new(0,4); pad.Parent = f
    panels[name] = f
    return f
end

-- Colour constants
local C_INPUT_BG   = Color3.fromRGB(255,245,250)
local C_INPUT_BORD = Color3.fromRGB(255,180,210)
local C_INPUT_FOC  = Color3.fromRGB(255,105,180)
local C_LABEL      = Color3.fromRGB(120,40,80)
local C_SECLABEL   = Color3.fromRGB(200,100,150)
local C_DIVIDER    = Color3.fromRGB(255,195,220)
local C_ON1        = Color3.fromRGB(80,200,140)
local C_OFF1       = Color3.fromRGB(220,80,110)
local C_WHITE      = Color3.fromRGB(255,255,255)

function createFieldLabel(text, parent)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,0,0,15); lbl.BackgroundTransparency = 1
    lbl.Text = text; lbl.Font = Enum.Font.FredokaOne; lbl.TextSize = 10
    lbl.TextColor3 = C_SECLABEL; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = parent
    return lbl
end

function createInputBox(placeholder, defaultValue, parent)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1,0,0,26)
    box.BackgroundColor3 = C_INPUT_BG; box.BackgroundTransparency = 0
    box.Text = tostring(defaultValue or ""); box.PlaceholderText = placeholder or ""
    box.Font = Enum.Font.FredokaOne; box.TextSize = 12
    box.TextColor3 = C_LABEL; box.PlaceholderColor3 = Color3.fromRGB(200,150,175)
    box.ClearTextOnFocus = false; box.TextXAlignment = Enum.TextXAlignment.Left; box.Parent = parent
    local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0,9); pad.Parent = box
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,8); corner.Parent = box
    local stroke = Instance.new("UIStroke"); stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = C_INPUT_BORD; stroke.Thickness = 1.5; stroke.Parent = box
    box.Focused:Connect(function() TweenService:Create(stroke, TweenInfo.new(0.12), {Color=C_INPUT_FOC}):Play() end)
    box.FocusLost:Connect(function() TweenService:Create(stroke, TweenInfo.new(0.12), {Color=C_INPUT_BORD}):Play() end)
    return box, stroke
end

function createButton(text, bgColor, textColor, borderColor, parent, onClick)
    local sc = borderColor or bgColor:Lerp(C_WHITE, 0.5)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,-8,0,26); btn.BackgroundColor3 = bgColor; btn.BackgroundTransparency = 0.25
    btn.Text = text; btn.Font = Enum.Font.FredokaOne; btn.TextSize = 11
    btn.TextColor3 = textColor or C_WHITE; btn.AutoButtonColor = false; btn.Parent = parent
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,8); corner.Parent = btn
    local stroke = Instance.new("UIStroke"); stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = sc; stroke.Thickness = 1.5; stroke.Transparency = 0.2; stroke.Parent = btn
    btn.MouseButton1Down:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.07, Enum.EasingStyle.Quad), {BackgroundTransparency=0.1}):Play()
        TweenService:Create(stroke, TweenInfo.new(0.07), {Transparency=0.0}):Play()
    end)
    local function release()
        TweenService:Create(btn, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {BackgroundTransparency=0.25}):Play()
        TweenService:Create(stroke, TweenInfo.new(0.1), {Transparency=0.2}):Play()
    end
    btn.MouseButton1Up:Connect(release); btn.MouseLeave:Connect(release)
    if onClick then btn.MouseButton1Click:Connect(onClick) end
    return btn
end

function createDivider(parent)
    local div = Instance.new("Frame")
    div.Size = UDim2.new(1,0,0,1); div.BackgroundColor3 = C_DIVIDER; div.BorderSizePixel = 0; div.Parent = parent
    return div
end

function createSectionLabel(text, parent)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,0,0,15); lbl.BackgroundTransparency = 1
    lbl.Text = "✦ " .. text; lbl.Font = Enum.Font.FredokaOne; lbl.TextSize = 9
    lbl.TextColor3 = C_SECLABEL; lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextYAlignment = Enum.TextYAlignment.Center; lbl.Parent = parent
    return lbl
end

function makeToast(parent)
    local t = Instance.new("TextLabel")
    t.Text = ""; t.Size = UDim2.new(1,-8,0,22)
    t.BackgroundColor3 = Color3.fromRGB(255,220,235); t.BackgroundTransparency = 0.1
    t.TextColor3 = Color3.fromRGB(150,30,80); t.TextSize = 10; t.Font = Enum.Font.FredokaOne
    t.BorderSizePixel = 0; t.Visible = false; t.Parent = parent
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = t
    local s = Instance.new("UIStroke"); s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color = Color3.fromRGB(255,155,195); s.Thickness = 1.5; s.Parent = t
    return t
end

function showToast(toast, text, duration)
    toast.Text = text; toast.Visible = true
    task.delay(duration or 3, function() toast.Visible = false end)
end

-- ============================================================
--  CONTROL PANEL
-- ============================================================
local controlPanel = makePanel("Control")

createFieldLabel("💌  PARTNER USERNAME", controlPanel)
partnerInput, inputStroke = createInputBox("enter username here...", "", controlPanel)

createDivider(controlPanel)
createSectionLabel("ACTIONS", controlPanel)

local startBtn = createButton("🎀  START FAKE TRADE", Color3.fromRGB(220,80,140), nil, nil, controlPanel)
local addTheirBtn = createButton("🌸  ADD GODLY TO THEIR SIDE", Color3.fromRGB(100,180,130), nil, nil, controlPanel)
local removeTheirBtn = createButton("✂️  REMOVE FROM THEIR SIDE", Color3.fromRGB(200,130,160), nil, nil, controlPanel)

createDivider(controlPanel)
createSectionLabel("TOOLS", controlPanel)

local blockBtn = createButton("🚫  BLOCK PLAYER", Color3.fromRGB(220,60,90), nil, nil, controlPanel)
do local c = blockBtn:FindFirstChildWhichIsA("UICorner"); if c then c.CornerRadius = UDim.new(1,0) end end

local godlyToast = makeToast(controlPanel)
statusToast = makeToast(controlPanel)

startBtn.MouseButton1Click:Connect(function()
    local partner = partnerInput.Text
    if partner == "" then showToast(statusToast, "🎀  Enter a partner username first!", 3); return end
    if fakeTrade.active then cancelFakeTrade(); task.wait(0.1) end
    local theirOffer = {}
    for _, item in ipairs(stagedTheirItems) do table.insert(theirOffer, item) end
    startFakeTrade(partner, theirOffer)
    showToast(statusToast, "🌸  Fake trade opened with " .. partner, 4)
    TweenService:Create(inputStroke, TweenInfo.new(0.15), {Color=Color3.fromRGB(80,220,140)}):Play()
    task.delay(1.5, function()
        TweenService:Create(inputStroke, TweenInfo.new(0.15), {Color=Color3.fromRGB(255,180,210)}):Play()
    end)
end)

addTheirBtn.MouseButton1Click:Connect(function()
    if partnerInput.Text == "" then showToast(statusToast, "🎀  Enter a partner username first!", 3); return end
    if fakeTrade.active then
        addGodlyToTheirSide()
        showToast(statusToast, "🌸  Added godly to their side (live)", 3)
    else
        local itemID = godlies[math.random(1,#godlies)]
        table.insert(stagedTheirItems, {ItemID=itemID, Amount=1, ItemType="Weapons"})
        showToast(statusToast, "✨  Staged '" .. itemID .. "' to their side", 3)
    end
end)

removeTheirBtn.MouseButton1Click:Connect(function()
    if fakeTrade.active then
        removeFromTheirSide()
        showToast(statusToast, "✂️  Removed from their side (live)", 3)
    elseif #stagedTheirItems == 0 then
        showToast(statusToast, "🎀  No staged items to remove.", 3)
    else
        local last = table.remove(stagedTheirItems)
        showToast(statusToast, "✂️  Removed '" .. last.ItemID .. "'", 3)
    end
end)

blockBtn.MouseButton1Click:Connect(function()
    local name = partnerInput.Text
    if name == "" then showToast(statusToast, "🎀  Select a player first!", 3); return end
    local player = Players:FindFirstChild(name)
    if not player then showToast(statusToast, "🚫  Player not found in server.", 3); return end
    showToast(statusToast, "🚫  Blocking " .. name .. "...", 3)
    task.spawn(function()
        BlockPlayerSilent(player)
        showToast(statusToast, "✅  Blocked " .. name, 3)
    end)
end)

-- ============================================================
--  PLAYERS PANEL
-- ============================================================
local playersPanel = makePanel("Players")

function formatValue(n)
    if n >= 1000000 then return string.format("%.1fM", n/1000000)
    elseif n >= 1000 then return string.format("%.1fk", n/1000)
    else return tostring(math.floor(n)) end
end

function rebuildPlayersPanel()
    for _, child in ipairs(playersPanel:GetChildren()) do
        if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then child:Destroy() end
    end
    createSectionLabel("💕  SERVER PLAYERS", playersPanel)
    if #serverPlayers == 0 then
        createFieldLabel("No other players in server ☁️", playersPanel); return
    end
    for i, name in ipairs(serverPlayers) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1,0,0,42); row.BackgroundColor3 = Color3.fromRGB(255,230,240)
        row.BorderSizePixel = 0; row.LayoutOrder = i+1; row.Parent = playersPanel
        do
            local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,10); c.Parent = row
            local s = Instance.new("UIStroke"); s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            s.Color = Color3.fromRGB(255,175,210); s.Thickness = 1.5; s.Parent = row
        end
        local avatar = Instance.new("Frame")
        avatar.Size = UDim2.new(0,28,0,28); avatar.Position = UDim2.new(0,8,0.5,-14)
        avatar.BackgroundColor3 = Color3.fromRGB(255,195,220); avatar.BorderSizePixel = 0; avatar.Parent = row
        do local ac = Instance.new("UICorner"); ac.CornerRadius = UDim.new(1,0); ac.Parent = avatar end
        local letter = Instance.new("TextLabel")
        letter.Text = string.upper(string.sub(name,1,1)); letter.Size = UDim2.new(1,0,1,0)
        letter.BackgroundTransparency = 1; letter.TextColor3 = Color3.fromRGB(180,30,90)
        letter.TextSize = 13; letter.Font = Enum.Font.FredokaOne; letter.Parent = avatar
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Text = name .. " · ..."
        nameLabel.Size = UDim2.new(1,-76,1,0); nameLabel.Position = UDim2.new(0,42,0,0)
        nameLabel.BackgroundTransparency = 1; nameLabel.TextColor3 = Color3.fromRGB(120,40,80)
        nameLabel.TextSize = 11; nameLabel.Font = Enum.Font.FredokaOne
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd; nameLabel.Parent = row
        local tradeBtn = Instance.new("TextButton")
        tradeBtn.Text = "Pick 💖"; tradeBtn.Size = UDim2.new(0,54,0,24); tradeBtn.Position = UDim2.new(1,-60,0.5,-12)
        tradeBtn.BackgroundColor3 = Color3.fromRGB(255,105,170); tradeBtn.TextColor3 = C_WHITE
        tradeBtn.TextSize = 10; tradeBtn.Font = Enum.Font.FredokaOne; tradeBtn.AutoButtonColor = false; tradeBtn.Parent = row
        do
            local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = tradeBtn
            local s = Instance.new("UIStroke"); s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            s.Color = Color3.fromRGB(220,60,130); s.Thickness = 1; s.Parent = tradeBtn
        end
        tradeBtn.MouseButton1Click:Connect(function()
            partnerInput.Text = name; switchTab("Control")
            TweenService:Create(inputStroke, TweenInfo.new(0.15), {Color=Color3.fromRGB(80,220,140)}):Play()
            task.delay(1.2, function()
                TweenService:Create(inputStroke, TweenInfo.new(0.15), {Color=Color3.fromRGB(255,180,210)}):Play()
            end)
        end)
    end
end

rebuildPlayersPanel()
Players.PlayerAdded:Connect(function()    task.wait(0.5); rebuildPlayersPanel() end)
Players.PlayerRemoving:Connect(function() task.wait(0.5); rebuildPlayersPanel() end)

-- ============================================================
--  WEAPONS PANEL
-- ============================================================
local weaponsPanel = makePanel("Weapons")

createFieldLabel("⚔️  WEAPON NAME TO ADD", weaponsPanel)
local weaponNameBox, weaponNameStroke = createInputBox("Enter weapon name...", "", weaponsPanel)

local chromaIDMap = {
    ["Alienbeam"]="UFOKnifeChroma", ["Evergun"]="TreeGun2023Chroma",
    ["Evergreen"]="TreeKnife2023Chroma", ["TravelersGun"]="TravelerGunChroma",
    ["VampiresGun"]="VampireGunChroma", ["Ornament"]="BaubleKnifeChroma",
    ["Seer"]="SeerChroma", ["Fang"]="FangChroma", ["Luger"]="LugerChroma",
}
function resolveChromaID(baseName)
    return chromaIDMap[baseName] or baseName:gsub("%s+","") .. "Chroma"
end

createFieldLabel("WEAPON TYPE", weaponsPanel)
local weaponTypeContainer = Instance.new("Frame")
weaponTypeContainer.Size = UDim2.new(1,-8,0,30); weaponTypeContainer.BackgroundTransparency = 1; weaponTypeContainer.Parent = weaponsPanel

local selectedWeaponType = "Regular"
local typeButtons = {}
local typeData = {
    {label = "REGULAR", color = Color3.fromRGB(255,105,180)},
    {label = "CHROMA",  color = Color3.fromRGB(162,228,180)},
}

for i, tdata in ipairs(typeData) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.48,0,1,0); btn.Position = UDim2.new((i-1)*0.52,0,0,0)
    btn.BackgroundColor3 = Color3.fromRGB(255,235,245); btn.BackgroundTransparency = 0.2
    btn.Text = tdata.label; btn.Font = Enum.Font.FredokaOne; btn.TextSize = 11
    btn.TextColor3 = Color3.fromRGB(160,40,90); btn.AutoButtonColor = false; btn.Parent = weaponTypeContainer
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,8); corner.Parent = btn
    local stroke = Instance.new("UIStroke"); stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = tdata.color; stroke.Thickness = 1.5; stroke.Transparency = 0.3; stroke.Parent = btn
    typeButtons[tdata.label] = {button=btn, stroke=stroke, color=tdata.color}
end

task.spawn(function()
    local cb = typeButtons["CHROMA"]; local hue = 0
    while cb and cb.stroke and cb.stroke.Parent do
        hue = (hue + 0.006) % 1; cb.stroke.Color = Color3.fromHSV(hue,1,1); task.wait(0.03)
    end
end)

for _, tdata in ipairs(typeData) do
    local entry = typeButtons[tdata.label]
    entry.button.MouseButton1Click:Connect(function()
        selectedWeaponType = tdata.label
        for _, other in ipairs(typeData) do
            local e = typeButtons[other.label]
            if other.label == tdata.label then
                e.button.BackgroundColor3 = Color3.fromRGB(255,200,220); e.button.BackgroundTransparency = 0.1
                e.stroke.Thickness = 2.0; e.stroke.Transparency = 0.0
            else
                e.button.BackgroundColor3 = Color3.fromRGB(255,235,245); e.button.BackgroundTransparency = 0.3
                e.stroke.Thickness = 1.5; e.stroke.Transparency = 0.4
            end
        end
    end)
end

do
    local e = typeButtons["REGULAR"]
    e.button.BackgroundColor3 = Color3.fromRGB(255,200,220); e.button.BackgroundTransparency = 0.1
    e.stroke.Thickness = 2.0; e.stroke.Transparency = 0.0
end

createFieldLabel("ADD WEAPON DELAY (S)", weaponsPanel)
local addWeaponDelayBox = createInputBox("", "0.5", weaponsPanel)
local addWeaponDelay = 0.5
addWeaponDelayBox.FocusLost:Connect(function()
    local v = tonumber(addWeaponDelayBox.Text)
    if v and v >= 0 then addWeaponDelay = v else addWeaponDelayBox.Text = tostring(addWeaponDelay) end
end)

createButton("✨  ADD WEAPON TO TRADE", Color3.fromRGB(255,105,180), C_WHITE, Color3.fromRGB(220,60,130), weaponsPanel, function()
    local weaponName = weaponNameBox.Text; if weaponName == "" then return end
    if selectedWeaponType == "CHROMA" and not weaponName:lower():find("chroma") then
        weaponName = resolveChromaID(weaponName)
    end
    table.insert(stagedTheirItems, {ItemID=weaponName, Amount=1, ItemType="Weapons"})
    if fakeTrade.active then
        task.wait(addWeaponDelay)
        local resolvedID, dbEntry = resolveDBItem(weaponName)
        local itemData = {DataID=resolvedID, DataType="Weapons", Amount=1, Name=weaponName, ItemName=weaponName}
        if dbEntry and type(dbEntry) == "table" then
            for k,v in pairs(dbEntry) do if itemData[k] == nil then itemData[k] = v end end
            itemData.Name = dbEntry.ItemName or dbEntry.Name or weaponName; itemData.ItemName = itemData.Name
        end
        if AddToSide(TheirSlots, itemData) then RefreshAllSlots(); ResetCooldown(false) end
    end
    showToast(statusToast, "🌸  Staged: " .. weaponName, 3)
end)

createButton("✂️  REMOVE LATEST WEAPON", Color3.fromRGB(200,100,140), C_WHITE, Color3.fromRGB(170,60,100), weaponsPanel, function()
    if fakeTrade.active then
        removeFromTheirSide(); showToast(statusToast, "✂️  Removed from their side", 3)
    elseif #stagedTheirItems > 0 then
        local last = table.remove(stagedTheirItems)
        showToast(statusToast, "✂️  Removed: " .. (last.ItemID or "?"), 3)
    else
        showToast(statusToast, "🎀  Nothing to remove!", 3)
    end
end)

createButton("🎀  ADD RANDOM HIGH-VALUE GODLY", Color3.fromRGB(162,210,185), Color3.fromRGB(80,30,60), Color3.fromRGB(100,180,140), weaponsPanel, function()
    local pick = highTierPool[math.random(1,#highTierPool)]
    local resolvedID, itemData = resolveDBItem(pick)
    weaponNameBox.Text = resolvedID
    local tradeItem = {DataID=resolvedID, DataType="Weapons", Amount=1, Name=resolvedID, ItemName=resolvedID}
    if itemData then
        for k,v in pairs(itemData) do if tradeItem[k] == nil then tradeItem[k] = v end end
        tradeItem.Name = itemData.ItemName or itemData.Name or resolvedID; tradeItem.ItemName = tradeItem.Name
    end
    table.insert(stagedTheirItems, {ItemID=resolvedID, Amount=1, ItemType="Weapons"})
    if fakeTrade.active then
        task.wait(addWeaponDelay)
        if AddToSide(TheirSlots, tradeItem) then RefreshAllSlots(); ResetCooldown(false) end
    end
    showToast(statusToast, "✨  Staged: " .. (tradeItem.Name or resolvedID), 3)
end)

createSectionLabel("💎  HIGH-VALUE GODLYS & ANCIENTS (100+)", weaponsPanel)

local godlyList = Instance.new("ScrollingFrame")
godlyList.Size = UDim2.new(1, 0, 0, 240); godlyList.BackgroundColor3 = Color3.fromRGB(255,240,248)
godlyList.BorderSizePixel = 0; godlyList.ScrollBarThickness = 3
godlyList.ScrollBarImageColor3 = Color3.fromRGB(255,155,195)
godlyList.AutomaticCanvasSize = Enum.AutomaticSize.Y; godlyList.Parent = weaponsPanel
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,10); c.Parent = godlyList
    local s = Instance.new("UIStroke"); s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color = Color3.fromRGB(255,175,210); s.Thickness = 1.5; s.Parent = godlyList
    local l = Instance.new("UIListLayout"); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Padding = UDim.new(0,4); l.Parent = godlyList
    local p = Instance.new("UIPadding")
    p.PaddingTop = UDim.new(0,5); p.PaddingBottom = UDim.new(0,5)
    p.PaddingLeft = UDim.new(0,5); p.PaddingRight = UDim.new(0,5); p.Parent = godlyList
end

for i, weapon in ipairs(highValueWeapons) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,-8,0,36)
    btn.BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(255,225,240) or Color3.fromRGB(230,248,238)
    btn.Text = ""; btn.Font = Enum.Font.FredokaOne; btn.TextSize = 12
    btn.AutoButtonColor = false; btn.LayoutOrder = i; btn.Parent = godlyList
    do
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = btn
        local tc = weapon.tier == "Ancient" and Color3.fromRGB(255,160,195) or Color3.fromRGB(162,228,190)
        local tch = weapon.tier == "Ancient" and Color3.fromRGB(255,105,165) or Color3.fromRGB(100,200,140)
        local s = Instance.new("UIStroke"); s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Color = tc; s.Thickness = 1.5; s.Parent = btn
        btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3=Color3.fromRGB(255,210,230)}):Play()
            TweenService:Create(s, TweenInfo.new(0.15), {Color=tch}):Play()
        end)
        btn.MouseLeave:Connect(function()
            local base = (i % 2 == 0) and Color3.fromRGB(255,225,240) or Color3.fromRGB(230,248,238)
            TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3=base}):Play()
            TweenService:Create(s, TweenInfo.new(0.15), {Color=tc}):Play()
        end)
    end
    local tierLabel = Instance.new("TextLabel")
    tierLabel.Size = UDim2.new(0,14,1,0); tierLabel.Position = UDim2.new(0,5,0,0)
    tierLabel.BackgroundTransparency = 1
    tierLabel.Text = weapon.tier == "Ancient" and "💎" or "✨"
    tierLabel.Font = Enum.Font.FredokaOne; tierLabel.TextSize = 11
    tierLabel.TextColor3 = weapon.tier == "Ancient" and Color3.fromRGB(255,100,160) or Color3.fromRGB(100,190,140)
    tierLabel.Parent = btn
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1,-90,1,0); nameLabel.Position = UDim2.new(0,22,0,0)
    nameLabel.BackgroundTransparency = 1; nameLabel.Text = weapon.name
    nameLabel.TextColor3 = Color3.fromRGB(140,40,80); nameLabel.TextSize = 11; nameLabel.Font = Enum.Font.FredokaOne
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left; nameLabel.Parent = btn
    local valLabel = Instance.new("TextLabel")
    valLabel.Size = UDim2.new(0,60,1,0); valLabel.Position = UDim2.new(1,-65,0,0)
    valLabel.BackgroundTransparency = 1; valLabel.Text = tostring(weapon.value)
    valLabel.TextColor3 = Color3.fromRGB(180,100,140); valLabel.TextSize = 10; valLabel.Font = Enum.Font.FredokaOne
    valLabel.TextXAlignment = Enum.TextXAlignment.Right; valLabel.Parent = btn
    local capturedName = weapon.name
    btn.MouseButton1Click:Connect(function()
        weaponNameBox.Text = capturedName
    end)
end

-- ============================================================
--  SPAWNER PANEL
-- ============================================================
local spawnerPanel = makePanel("Spawner")
createSectionLabel("🪄  WEAPON SPAWNER", spawnerPanel)

createFieldLabel("AMOUNT PER CLICK (0 = RANDOM)", spawnerPanel)
local spawnerAmountBox, spawnerAmountStroke = createInputBox("0 = random amount", "0", spawnerPanel)

createFieldLabel("🔍  SEARCH WEAPON TO SPAWN", spawnerPanel)
local spawnerSearchBox, spawnerSearchStroke = createInputBox("Search weapon...", "", spawnerPanel)

local spawnerToast = makeToast(spawnerPanel)

createButton("🎁  SPAWN ALL TRADABLE GODLIES",
    Color3.fromRGB(240, 150, 190), Color3.fromRGB(255,255,255), Color3.fromRGB(210, 110, 150),
    spawnerPanel, function()
        local count, total = 0, 0
        for _, w in ipairs(highValueWeapons) do
            local resolvedID = resolveDBItem(w.name)
            local amt = math.random(1, 3)
            SpawnItem(resolvedID, amt, "Weapons")
            count = count + 1
            total = total + amt
        end
        showToast(spawnerToast, "🌸  Spawned " .. count .. " godly types (" .. total .. " total)!", 4)
    end)

createButton("✨  SPAWN ALL ANCIENTS",
    Color3.fromRGB(162, 228, 180), Color3.fromRGB(80, 30, 60), Color3.fromRGB(100, 180, 140),
    spawnerPanel, function()
        local count, total = 0, 0
        for _, w in ipairs(highValueWeapons) do
            if w.tier == "Ancient" then
                local resolvedID = resolveDBItem(w.name)
                local amt = math.random(1, 2)
                SpawnItem(resolvedID, amt, "Weapons")
                count = count + 1
                total = total + amt
            end
        end
        showToast(spawnerToast, "✨  Spawned " .. count .. " Ancient weapons!", 4)
    end)

createSectionLabel("💎  SELECT WEAPON TO SPAWN", spawnerPanel)

local spawnerScroll = Instance.new("ScrollingFrame")
spawnerScroll.Size = UDim2.new(1, 0, 0, 220); spawnerScroll.BackgroundColor3 = Color3.fromRGB(255, 240, 248)
spawnerScroll.BorderSizePixel = 0; spawnerScroll.ScrollBarThickness = 3
spawnerScroll.ScrollBarImageColor3 = Color3.fromRGB(255, 155, 195)
spawnerScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; spawnerScroll.Parent = spawnerPanel
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,10); c.Parent = spawnerScroll
    local s = Instance.new("UIStroke"); s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color = Color3.fromRGB(255, 175, 210); s.Thickness = 1.5; s.Parent = spawnerScroll
    local l = Instance.new("UIListLayout"); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Padding = UDim.new(0,4); l.Parent = spawnerScroll
    local p = Instance.new("UIPadding")
    p.PaddingTop = UDim.new(0,5); p.PaddingBottom = UDim.new(0,5)
    p.PaddingLeft = UDim.new(0,5); p.PaddingRight = UDim.new(0,5); p.Parent = spawnerScroll
end

local spawnerButtonsList = {}

for i, weapon in ipairs(highValueWeapons) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,-8,0,36)
    btn.BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(255, 225, 240) or Color3.fromRGB(230, 248, 238)
    btn.Text = ""; btn.Font = Enum.Font.FredokaOne; btn.TextSize = 12
    btn.AutoButtonColor = false; btn.LayoutOrder = i; btn.Parent = spawnerScroll
    do
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = btn
        local tierColor = weapon.tier == "Ancient" and Color3.fromRGB(255, 160, 195) or Color3.fromRGB(162, 228, 190)
        local s = Instance.new("UIStroke"); s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Color = tierColor; s.Thickness = 1.5; s.Parent = btn
        btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(255, 210, 230)}):Play()
        end)
        btn.MouseLeave:Connect(function()
            local base = (i % 2 == 0) and Color3.fromRGB(255, 225, 240) or Color3.fromRGB(230, 248, 238)
            TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = base}):Play()
        end)
    end

    local tierLabel = Instance.new("TextLabel")
    tierLabel.Size = UDim2.new(0,14,1,0); tierLabel.Position = UDim2.new(0,5,0,0)
    tierLabel.BackgroundTransparency = 1
    tierLabel.Text = weapon.tier == "Ancient" and "💎" or "✨"
    tierLabel.Font = Enum.Font.FredokaOne; tierLabel.TextSize = 11
    tierLabel.TextColor3 = weapon.tier == "Ancient" and Color3.fromRGB(255, 100, 160) or Color3.fromRGB(100, 190, 140)
    tierLabel.Parent = btn

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1,-90,1,0); nameLabel.Position = UDim2.new(0,22,0,0)
    nameLabel.BackgroundTransparency = 1; nameLabel.Text = weapon.name
    nameLabel.TextColor3 = Color3.fromRGB(140, 40, 80)
    nameLabel.TextSize = 11; nameLabel.Font = Enum.Font.FredokaOne
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left; nameLabel.Parent = btn

    local spawnBadge = Instance.new("TextLabel")
    spawnBadge.Size = UDim2.new(0,60,1,0); spawnBadge.Position = UDim2.new(1,-65,0,0)
    spawnBadge.BackgroundTransparency = 1
    spawnBadge.Text = "Spawn 🪄"
    spawnBadge.TextColor3 = Color3.fromRGB(180, 80, 140)
    spawnBadge.TextSize = 10; spawnBadge.Font = Enum.Font.FredokaOne
    spawnBadge.TextXAlignment = Enum.TextXAlignment.Right; spawnBadge.Parent = btn

    local capturedName = weapon.name
    btn.MouseButton1Click:Connect(function()
        local typed = tonumber(spawnerAmountBox.Text)
        local amt = (typed and typed > 0) and typed or math.random(1, 3)
        local resolvedID = resolveDBItem(capturedName)
        SpawnItem(resolvedID, amt, "Weapons")
        showToast(spawnerToast, "✨  Spawned " .. capturedName .. " x" .. amt, 3)
        TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(162, 228, 180)}):Play()
        task.delay(0.2, function()
            local base = (i % 2 == 0) and Color3.fromRGB(255, 225, 240) or Color3.fromRGB(230, 248, 238)
            TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = base}):Play()
        end)
    end)

    table.insert(spawnerButtonsList, { btn = btn, name = weapon.name })
end

spawnerSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    local q = spawnerSearchBox.Text:lower()
    for _, info in ipairs(spawnerButtonsList) do
        if q == "" or info.name:lower():find(q, 1, true) then
            info.btn.Visible = true
        else
            info.btn.Visible = false
        end
    end
end)

-- ============================================================
--  USERS PANEL
-- ============================================================
local usersPanel = makePanel("Users")
createSectionLabel("🌸  USERS — CLICK TO SELECT", usersPanel)

for i, name in ipairs(usersList) do
    local row = Instance.new("TextButton")
    row.Text = ""; row.Size = UDim2.new(1,0,0,42)
    row.BackgroundColor3 = Color3.fromRGB(255, 232, 242); row.BorderSizePixel = 0
    row.AutoButtonColor = false; row.LayoutOrder = i+1; row.Parent = usersPanel
    local rowStroke
    do
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,10); c.Parent = row
        rowStroke = Instance.new("UIStroke"); rowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        rowStroke.Color = Color3.fromRGB(255, 180, 215); rowStroke.Thickness = 1.5; rowStroke.Parent = row
    end

    local avatar = Instance.new("Frame")
    avatar.Size = UDim2.new(0,28,0,28); avatar.Position = UDim2.new(0,8,0.5,-14)
    avatar.BackgroundColor3 = Color3.fromRGB(255, 195, 220); avatar.BorderSizePixel = 0; avatar.Parent = row
    do local ac = Instance.new("UICorner"); ac.CornerRadius = UDim.new(1,0); ac.Parent = avatar end
    local letter = Instance.new("TextLabel")
    letter.Text = string.upper(string.sub(name,1,1)); letter.Size = UDim2.new(1,0,1,0)
    letter.BackgroundTransparency = 1; letter.TextColor3 = Color3.fromRGB(180, 30, 90)
    letter.TextSize = 13; letter.Font = Enum.Font.FredokaOne; letter.Parent = avatar

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Text = name; nameLabel.Size = UDim2.new(1,-90,1,0); nameLabel.Position = UDim2.new(0,42,0,0)
    nameLabel.BackgroundTransparency = 1; nameLabel.TextColor3 = Color3.fromRGB(140, 40, 85)
    nameLabel.TextSize = 11; nameLabel.Font = Enum.Font.FredokaOne
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left; nameLabel.Parent = row

    local arrow = Instance.new("TextLabel")
    arrow.Text = "💗"; arrow.Size = UDim2.new(0,30,1,0); arrow.Position = UDim2.new(1,-35,0,0)
    arrow.BackgroundTransparency = 1; arrow.TextColor3 = Color3.fromRGB(220, 160, 190)
    arrow.TextSize = 13; arrow.Font = Enum.Font.FredokaOne; arrow.Parent = row

    row.MouseButton1Click:Connect(function()
        partnerInput.Text = name; switchTab("Control")
        TweenService:Create(inputStroke, TweenInfo.new(0.15), {Color=Color3.fromRGB(80, 220, 140)}):Play()
        task.delay(1.2, function()
            TweenService:Create(inputStroke, TweenInfo.new(0.15), {Color=Color3.fromRGB(255, 180, 210)}):Play()
        end)
    end)
    row.MouseEnter:Connect(function()
        TweenService:Create(row, TweenInfo.new(0.12), {BackgroundColor3=Color3.fromRGB(255, 210, 230)}):Play()
        TweenService:Create(rowStroke, TweenInfo.new(0.12), {Color=Color3.fromRGB(255, 105, 180)}):Play()
        arrow.TextColor3 = Color3.fromRGB(255, 80, 150)
    end)
    row.MouseLeave:Connect(function()
        TweenService:Create(row, TweenInfo.new(0.12), {BackgroundColor3=Color3.fromRGB(255, 232, 242)}):Play()
        TweenService:Create(rowStroke, TweenInfo.new(0.12), {Color=Color3.fromRGB(255, 180, 215)}):Play()
        arrow.TextColor3 = Color3.fromRGB(220, 160, 190)
    end)
end

-- ============================================================
--  MISC PANEL
-- ============================================================
local miscPanel = makePanel("Misc")

createSectionLabel("💰  TRADE VALUES", miscPanel)
do
    local valRow = Instance.new("Frame")
    valRow.Size = UDim2.new(1,-8,0,30); valRow.BackgroundTransparency = 1; valRow.Parent = miscPanel
    local vl = Instance.new("UIListLayout"); vl.FillDirection = Enum.FillDirection.Horizontal; vl.Padding = UDim.new(0,5); vl.Parent = valRow

    local function makeValBox(txt, bgColor, order)
        local box = Instance.new("TextLabel")
        box.Size = UDim2.new(0.5,-3,1,0); box.BackgroundColor3 = bgColor; box.BackgroundTransparency = 0.2
        box.BorderSizePixel = 0; box.LayoutOrder = order; box.Parent = valRow
        box.Text = txt; box.Font = Enum.Font.FredokaOne; box.TextSize = 12; box.TextColor3 = C_WHITE
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = box
        local s = Instance.new("UIStroke"); s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Color = bgColor:Lerp(C_WHITE,0.6); s.Thickness = 1.5; s.Transparency = 0.2; s.Parent = box
        return box
    end

    local tradeValueYouBox  = makeValBox("💗 You: —",  Color3.fromRGB(220, 80, 140),  1)
    local tradeValueThemBox = makeValBox("🌿 Them: —", Color3.fromRGB(80, 180, 120),  2)

    supremeValues = {}
    local svLoaded = false

    local function fetchSupremeValues()
        local pages = {
            "https://supremevalues.com/mm2/godlies",
            "https://supremevalues.com/mm2/ancients",
            "https://supremevalues.com/mm2/chromas",
        }
        local requestFn = syn and syn.request
            or (http and http.request)
            or (rawget(_G,"request") and type(rawget(_G,"request"))=="function" and rawget(_G,"request"))
            or (rawget(_G,"http_request") and type(rawget(_G,"http_request"))=="function" and rawget(_G,"http_request"))
            or (rawget(_G,"fetchget") and type(rawget(_G,"fetchget"))=="function" and rawget(_G,"fetchget"))
        if not requestFn then svLoaded = true; return end
        for _, url in ipairs(pages) do
            local ok, res = pcall(requestFn, { Url = url, Method = "GET" })
            if ok and res and res.Body and #res.Body > 1000 then
                local body = res.Body; local pos = 1
                while true do
                    local ns, ne, rawName = body:find("data%-name='([^']+)'", pos)
                    if not ns then break end
                    local searchBack = body:sub(math.max(1, ns - 800), ns)
                    local val = nil
                    for v in searchBack:gmatch('data%-value="(%d+)"') do val = tonumber(v) end
                    if val and val > 10 then
                        local name = rawName:gsub("&#039;","'"):gsub("&amp;","&"):gsub("&quot;",'"')
                        local key = name:lower():gsub("[^a-z0-9]","")
                        supremeValues[key] = val
                    end
                    pos = ne + 1
                end
            end
            task.wait(0.3)
        end
        svLoaded = true
    end

    task.spawn(fetchSupremeValues)

    local statusLbl = Instance.new("TextLabel")
    statusLbl.Size = UDim2.new(1,-8,0,14); statusLbl.BackgroundTransparency = 1
    statusLbl.Text = "Loading Supreme Values..."; statusLbl.Font = Enum.Font.FredokaOne
    statusLbl.TextSize = 9; statusLbl.TextColor3 = Color3.fromRGB(190, 120, 160)
    statusLbl.TextXAlignment = Enum.TextXAlignment.Left; statusLbl.Parent = miscPanel

    createButton("🌸  REFRESH VALUES", Color3.fromRGB(200, 100, 155), nil, nil, miscPanel, function()
        svLoaded = false; tradeValueYouBox.Text = "💗 You: —"; tradeValueThemBox.Text = "🌿 Them: —"
        statusLbl.Text = "Refreshing..."
        task.spawn(function() fetchSupremeValues(); statusLbl.Text = "Supreme Values ✔" end)
    end)

    local function getItemValue(slots)
        local total = 0
        for i = 1, MAX_SLOTS do
            local item = slots[i]
            if item then
                local name = (item.ItemName or item.Name or item.DataID or ""):lower():gsub("[^a-z0-9]","")
                total = total + (supremeValues[name] or 0) * (item.Amount or 1)
            end
        end
        return total
    end

    local function fmt(n)
        if n >= 1000000 then return string.format("%.1fM", n/1000000)
        elseif n >= 1000 then return string.format("%.1fK", n/1000) end
        return tostring(n)
    end

    task.spawn(function()
        while true do
            task.wait(1)
            if not svLoaded then statusLbl.Text = "Loading Supreme Values..."
            else local count = 0; for _ in pairs(supremeValues) do count = count + 1 end
                statusLbl.Text = "Supreme Values ✔  (" .. count .. " items)"
            end
            if fakeTrade.active then
                local you  = getItemValue(YourSlots)
                local them = getItemValue(TheirSlots)
                tradeValueYouBox.Text  = "💗 You: "  .. (you  > 0 and fmt(you)  or "—")
                tradeValueThemBox.Text = "🌿 Them: " .. (them > 0 and fmt(them) or "—")
            else
                tradeValueYouBox.Text  = "💗 You: —"
                tradeValueThemBox.Text = "🌿 Them: —"
            end
        end
    end)
end

createDivider(miscPanel)
createSectionLabel("🎀  GUI SETTINGS", miscPanel)

-- Keybinds
local keybinds = {
    { action = "Toggle GUI",           key = Enum.KeyCode.RightShift },
    { action = "Start / Cancel Trade", key = Enum.KeyCode.F          },
    { action = "Add Godly Their Side", key = Enum.KeyCode.G          },
    { action = "Remove Their Latest",  key = Enum.KeyCode.X          },
    { action = "Unbox Godly",          key = Enum.KeyCode.U          },
}

local keybindPanel = makePanel("Keybinds")
keybindPanel.Visible = false

local listeningIndex = nil
local keyRows = {}

local function buildKeybindPanel()
    for _, c in ipairs(keybindPanel:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
    end
    keyRows = {}

    local backBtn = Instance.new("TextButton")
    backBtn.Size = UDim2.new(1,-8,0,28); backBtn.BackgroundColor3 = Color3.fromRGB(255, 180, 215)
    backBtn.BackgroundTransparency = 0.2; backBtn.BorderSizePixel = 0
    backBtn.Text = "🎀  BACK"; backBtn.Font = Enum.Font.FredokaOne; backBtn.TextSize = 11
    backBtn.TextColor3 = Color3.fromRGB(140, 30, 80); backBtn.TextXAlignment = Enum.TextXAlignment.Left
    backBtn.AutoButtonColor = false; backBtn.LayoutOrder = 0; backBtn.Parent = keybindPanel
    local bkc = Instance.new("UICorner"); bkc.CornerRadius = UDim.new(0,8); bkc.Parent = backBtn
    local bkpad = Instance.new("UIPadding"); bkpad.PaddingLeft = UDim.new(0,10); bkpad.Parent = backBtn
    backBtn.MouseButton1Click:Connect(function()
        listeningIndex = nil; keybindPanel.Visible = false; miscPanel.Visible = true
    end)

    local hdr = Instance.new("TextLabel")
    hdr.Size = UDim2.new(1,-8,0,18); hdr.BackgroundTransparency = 1
    hdr.Text = "💌  KEYBINDS — click to rebind"; hdr.Font = Enum.Font.FredokaOne
    hdr.TextSize = 10; hdr.TextColor3 = Color3.fromRGB(190, 100, 150)
    hdr.TextXAlignment = Enum.TextXAlignment.Left; hdr.LayoutOrder = 1; hdr.Parent = keybindPanel

    local divLine = Instance.new("Frame")
    divLine.Size = UDim2.new(1,-8,0,2); divLine.BackgroundColor3 = Color3.fromRGB(255, 190, 220)
    divLine.BorderSizePixel = 0; divLine.LayoutOrder = 2; divLine.Parent = keybindPanel

    for i, bind in ipairs(keybinds) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1,-8,0,30); row.BackgroundColor3 = Color3.fromRGB(255, 228, 242)
        row.BackgroundTransparency = 0.1; row.BorderSizePixel = 0; row.LayoutOrder = i + 2; row.Parent = keybindPanel
        local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0,8); rc.Parent = row
        local rs = Instance.new("UIStroke"); rs.Color = Color3.fromRGB(255,180,215); rs.Thickness = 1; rs.Parent = row

        local actionLbl = Instance.new("TextLabel")
        actionLbl.Size = UDim2.new(0.58,0,1,0); actionLbl.Position = UDim2.new(0,8,0,0)
        actionLbl.BackgroundTransparency = 1; actionLbl.Text = bind.action
        actionLbl.Font = Enum.Font.FredokaOne; actionLbl.TextSize = 11; actionLbl.TextColor3 = Color3.fromRGB(140, 40, 85)
        actionLbl.TextXAlignment = Enum.TextXAlignment.Left; actionLbl.Parent = row

        local ks = Instance.new("UIStroke")
        local keyBtn = Instance.new("TextButton")
        keyBtn.Size = UDim2.new(0.38,0,0,22); keyBtn.Position = UDim2.new(0.60,0,0.5,-11)
        keyBtn.BackgroundColor3 = Color3.fromRGB(255, 150, 200); keyBtn.BackgroundTransparency = 0.25
        keyBtn.BorderSizePixel = 0; keyBtn.Text = bind.key.Name; keyBtn.Font = Enum.Font.FredokaOne
        keyBtn.TextSize = 10; keyBtn.TextColor3 = Color3.fromRGB(255,255,255); keyBtn.AutoButtonColor = false; keyBtn.Parent = row
        local kc = Instance.new("UICorner"); kc.CornerRadius = UDim.new(0,6); kc.Parent = keyBtn
        ks.Color = Color3.fromRGB(220, 80, 140); ks.Thickness = 1.5; ks.Transparency = 0.3; ks.Parent = keyBtn

        keyRows[i] = keyBtn
        local idx = i
        keyBtn.MouseButton1Click:Connect(function()
            if listeningIndex == idx then
                listeningIndex = nil; keyBtn.Text = keybinds[idx].key.Name
                keyBtn.TextColor3 = Color3.fromRGB(255,255,255); keyBtn.BackgroundColor3 = Color3.fromRGB(255, 150, 200)
            else
                listeningIndex = idx
                for j, btn in ipairs(keyRows) do
                    if j == idx then
                        btn.Text = "press a key ✨"; btn.TextColor3 = Color3.fromRGB(255,255,255)
                        btn.BackgroundColor3 = Color3.fromRGB(240, 180, 80)
                    else
                        btn.Text = keybinds[j].key.Name; btn.TextColor3 = Color3.fromRGB(255,255,255)
                        btn.BackgroundColor3 = Color3.fromRGB(255, 150, 200)
                    end
                end
            end
        end)
    end
end

createButton("⌨️  KEYBINDS", Color3.fromRGB(200, 130, 180), nil, nil, miscPanel, function()
    buildKeybindPanel(); miscPanel.Visible = false; keybindPanel.Visible = true
end)

UserInputService.InputBegan:Connect(function(inp, gameProcessed)
    if listeningIndex then
        if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if inp.KeyCode == Enum.KeyCode.Escape then
            local btn = keyRows[listeningIndex]
            if btn then btn.Text = keybinds[listeningIndex].key.Name; btn.BackgroundColor3 = Color3.fromRGB(255, 150, 200) end
            listeningIndex = nil; return
        end
        keybinds[listeningIndex].key = inp.KeyCode
        local btn = keyRows[listeningIndex]
        if btn then btn.Text = inp.KeyCode.Name; btn.BackgroundColor3 = Color3.fromRGB(255, 150, 200) end
        listeningIndex = nil; return
    end
    local k = inp.KeyCode
    if UserInputService:GetFocusedTextBox() then return end
    for _, bind in ipairs(keybinds) do
        if k == bind.key then
            if bind.action == "Toggle GUI" then MainFrame.Visible = not MainFrame.Visible
            elseif bind.action == "Start / Cancel Trade" then
                if fakeTrade.active then cancelFakeTrade()
                else
                    local name = partnerInput and partnerInput.Text or ""
                    if name == "" then return end
                    local theirOffer = {}
                    for _, item in ipairs(stagedTheirItems) do table.insert(theirOffer, item) end
                    startFakeTrade(name, theirOffer)
                    showToast(statusToast, "🌸  Fake trade opened with " .. name, 4)
                end
            elseif bind.action == "Add Godly Their Side" then addGodlyToTheirSide()
            elseif bind.action == "Remove Their Latest" then
                if fakeTrade.active then removeFromTheirSide()
                elseif #stagedTheirItems > 0 then table.remove(stagedTheirItems) end
            elseif bind.action == "Unbox Godly" then task.spawn(openSpinWheel)
            end
        end
    end
end)

-- GUI Size
createSectionLabel("📐  GUI SIZE", miscPanel)
do
    local szRow = Instance.new("Frame")
    szRow.Size = UDim2.new(1,-8,0,26); szRow.BackgroundTransparency = 1; szRow.Parent = miscPanel
    local szLbl = Instance.new("TextLabel")
    szLbl.Size = UDim2.new(0.55,0,1,0); szLbl.BackgroundTransparency = 1; szLbl.Text = "GUI Size: 100%"
    szLbl.Font = Enum.Font.FredokaOne; szLbl.TextSize = 11; szLbl.TextColor3 = Color3.fromRGB(140,50,90)
    szLbl.TextXAlignment = Enum.TextXAlignment.Left; szLbl.Parent = szRow
    local guiScale = 100
    local function makeSzBtn(txt, bgColor, xOff, cb)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0,26,0,22); btn.Position = UDim2.new(1,xOff,0.5,-11)
        btn.BackgroundColor3 = bgColor; btn.BackgroundTransparency = 0.25; btn.BorderSizePixel = 0; btn.Parent = szRow
        btn.Text = txt; btn.Font = Enum.Font.FredokaOne; btn.TextSize = 12; btn.TextColor3 = C_WHITE; btn.AutoButtonColor = false
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = btn
        local s = Instance.new("UIStroke"); s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Color = bgColor:Lerp(C_WHITE,0.5); s.Thickness = 1.5; s.Transparency = 0.2; s.Parent = btn
        btn.MouseButton1Down:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.07), {BackgroundTransparency=0.1}):Play()
            TweenService:Create(s, TweenInfo.new(0.07), {Transparency=0.0}):Play()
        end)
        local function r()
            TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundTransparency=0.25}):Play()
            TweenService:Create(s, TweenInfo.new(0.1), {Transparency=0.2}):Play()
        end
        btn.MouseButton1Up:Connect(r); btn.MouseLeave:Connect(r)
        btn.MouseButton1Click:Connect(cb); return btn, s
    end
    makeSzBtn("−", Color3.fromRGB(200,100,155), -86, function()
        guiScale = math.max(50, guiScale - 10); szLbl.Text = "GUI Size: " .. guiScale .. "%"
        local uisc = MainFrame:FindFirstChildOfClass("UIScale")
        if not uisc then uisc = Instance.new("UIScale"); uisc.Parent = MainFrame end; uisc.Scale = guiScale/100
    end)
    makeSzBtn("+", Color3.fromRGB(100,180,130), -56, function()
        guiScale = math.min(200, guiScale + 10); szLbl.Text = "GUI Size: " .. guiScale .. "%"
        local uisc = MainFrame:FindFirstChildOfClass("UIScale")
        if not uisc then uisc = Instance.new("UIScale"); uisc.Parent = MainFrame end; uisc.Scale = guiScale/100
    end)
    local lockBtn2 = makeSzBtn("🔓", Color3.fromRGB(220,160,190), -26, function() end)
    lockBtn2.MouseButton1Click:Connect(function()
        dragEnabled = not dragEnabled
        lockBtn2.Text = dragEnabled and "🔓" or "🔒"
        TweenService:Create(lockBtn2, TweenInfo.new(0.15), {
            BackgroundColor3 = dragEnabled and Color3.fromRGB(220,160,190) or Color3.fromRGB(240,180,80)
        }):Play()
    end)
end

-- ============================================================
--  REMOTE LISTENERS & SPINNER
-- ============================================================
Remote.StartTrade.OnClientEvent:Connect(function()
    if fakeTrade.active then cancelFakeTrade() end
end)
Remote.DeclineTrade.OnClientEvent:Connect(function() cancelFakeTrade() end)
Remote.UpdateTrade.OnClientEvent:Connect(function(state)
    if state == nil and fakeTrade.active then cancelFakeTrade() end
end)

do
openSpinWheel = function()
    local BoxModuleScript = ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("BoxModule")
    if not BoxModuleScript then showToast(statusToast, "⚠  BoxModule not found", 3); return end
    local Unboxing2Source = BoxModuleScript:FindFirstChild("Unboxing2")
    local NewItemSource   = BoxModuleScript:FindFirstChild("NewItem")
    if not Unboxing2Source or not NewItemSource then showToast(statusToast, "⚠  Unboxing assets missing", 3); return end
    local rng = Random.new()
    local godlyPool   = {"TravelerGun","TreeGun2023","Constellation","TreeKnife2023","Turkey2023","UFOKnife","VampireGun","Darkshot","Darksword","Raygun","SunsetGun","Snowcannon","Bauble","SunsetKnife","HeartWand"}
    local ancientPool = {"Gingerscope","TravelerAxe","Celestial","VampireAxe","Harvester","Icepiercer"}
    local chromaPool  = {"TravelerGunChroma","TreeGun2023Chroma","BaubleChroma","VampireGunChroma","UFOKnifeChroma","RaygunChroma","SunsetGunChroma"}
    local function pickRandom()
        local roll = rng:NextInteger(1, 100)
        local pool = roll <= 10 and #chromaPool > 0 and chromaPool or (roll <= 35 and #ancientPool > 0 and ancientPool or godlyPool)
        return pool[rng:NextInteger(1, #pool)]
    end
    local winID = pickRandom()
    local resolvedWinID, winData = resolveDBItem(winID)
    local unboxGUI = Unboxing2Source:Clone()
    local guiContainer = unboxGUI:FindFirstChild("Container")
    local guiMain = guiContainer and guiContainer:FindFirstChild("Main")
    local innerContainer = guiMain and guiMain:FindFirstChild("Container")
    local background = innerContainer and innerContainer:FindFirstChild("Background")
    local itemContainer = background and background:FindFirstChild("ItemContainer")
    local offsetContainer = itemContainer and itemContainer:FindFirstChild("OffsetContainer")
    local mainContainer = offsetContainer and offsetContainer:FindFirstChild("MainContainer")
    if not mainContainer or not offsetContainer then unboxGUI:Destroy(); showToast(statusToast, "⚠  Unboxing2 mismatch", 3); return end
    local stripCount = rng:NextInteger(20, 25); local winIndex = stripCount
    mainContainer:ClearAllChildren()
    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.new(0, 100, 1, 0); gridLayout.CellPadding = UDim2.new(0, 0, 0, 0)
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder; gridLayout.FillDirection = Enum.FillDirection.Horizontal
    gridLayout.Parent = mainContainer
    local cellWidth = 100
    offsetContainer.Size = UDim2.new(0, cellWidth*(stripCount+5), 1, 0)
    offsetContainer.Position = UDim2.new(0.5, cellWidth/2, 0, 0)
    for i = 1, stripCount+5 do
        local itemData; if i == winIndex then itemData = winData
        else local _, randData = resolveDBItem(pickRandom()); itemData = randData end
        local cell = NewItemSource:Clone(); cell.LayoutOrder = i; cell.Visible = true; cell.Parent = mainContainer
        if itemData and ItemModule and ItemModule.DisplayItem then pcall(function() ItemModule.DisplayItem(cell, itemData) end) end
    end
    unboxGUI.DisplayOrder = 1100; unboxGUI.Parent = PlayerGui
    local spinDuration = 3 + rng:NextNumber()
    local targetX = -(cellWidth*winIndex) + rng:NextInteger(-(cellWidth/2-5), cellWidth/2-5) + cellWidth - cellWidth/2
    TweenService:Create(offsetContainer, TweenInfo.new(spinDuration, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {Position=UDim2.new(0.5, targetX, 0, 0)}):Play()
    task.wait(spinDuration + 1)
    local itemName = winData and (winData.ItemName or winData.Name) or resolvedWinID
    pcall(function() unboxGUI:Destroy() end)
    pcall(function()
        if ItemPopupService and ItemPopupService.ItemReceived then
            ItemPopupService.ItemReceived:Fire(resolvedWinID, "Weapons", 1)
        end
    end)
    local tradeItem = {DataID=resolvedWinID, DataType="Weapons", Amount=1, Name=itemName, ItemName=itemName}
    if winData then for k, v in pairs(winData) do if tradeItem[k] == nil then tradeItem[k] = v end end end
    if fakeTrade.active then
        if AddToSide(YourSlots, tradeItem) then RefreshAllSlots(); ResetCooldown(false) end
    end
    showToast(statusToast, "✨  Unboxed: " .. itemName, 4)
end

createDivider(controlPanel)
createSectionLabel("✨  UNBOXING", controlPanel)
createButton("🎁  UNBOX GODLY", Color3.fromRGB(240,180,80), Color3.fromRGB(120,60,10), Color3.fromRGB(210,140,20), controlPanel, function()
    openSpinWheel()
end)

end -- end spinner scope

print("[TradeManager INTEGRATED v7 -- Preppy Redesign] Loaded.")
