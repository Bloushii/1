--[[
	MapBuilder - يبني خريطة كاملة تلقائياً:
	  • أرض عشب + بحيرة ماء حقيقية (Terrain)
	  • منطقة سبون مع لوحة ترحيب
	  • قرية صغيرة (بيوت + شوارع + أشجار)
	  • أوبي (Obby) فوق اللافا: 4 مراحل + نقاط حفظ + خط النهاية

	أشياء تخلي اللاعبين يبقون:
	  • حفظ دائم (DataStore): المرحلة والكوينز والفوز والمشتريات ترجع لما يدخل مرة ثانية
	  • كوينز تلف بالشوارع وفوق منصات الأوبي
	  • متجر: سرعة، قفزة عالية، ذيل ألوان (تمشي فوق المنصة وتشتري)
	  • مكافأة يومية تكبر كل يوم يرجع فيه (لين 7 أيام)
	  • مكافأة كل 5 دقايق لعب
	  • حدث "مطر الكوينز" كل 8 دقايق عند السبون
	  • كنز سري تحت البحيرة (مرة وحدة لكل لاعب)
	  • الفوز بالأوبي: كوينز + Wins، وإعلان للسيرفر كله، وترجع تعيده

	طريقة الاستخدام: حط هذا السكربت داخل ServerScriptService كـ Script (مو LocalScript)
	عشان الحفظ يشتغل في Studio: Experience Settings ← Security ← Enable Studio Access to API Services
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local DataStoreService = game:GetService("DataStoreService")
local Debris = game:GetService("Debris")
local Terrain = workspace.Terrain

-- ===== إعدادات تقدر تغيرها =====
local STAGES = 4            -- عدد مراحل الأوبي
local PLATS_PER_STAGE = 6   -- عدد المنصات بكل مرحلة
local SEED = 2026           -- غيّر الرقم عشان يطلع لك أوبي مختلف

local CHECKPOINT_REWARD = 10      -- كوينز لكل نقطة حفظ جديدة
local FINISH_REWARD = 100         -- كوينز لما يخلص الأوبي
local SECRET_REWARD = 250         -- كوينز الكنز السري
local DAILY_REWARD = 25           -- × عدد أيام الستريك (لين 7)
local PLAYTIME_REWARD = 25        -- كوينز كل فترة لعب
local PLAYTIME_EVERY = 300        -- بالثواني (5 دقايق)
local COIN_RAIN_EVERY = 480       -- بالثواني (8 دقايق)

local SHOP = {
	{ id = "Speed", name = "Speed Boost", price = 50, x = 25, color = Color3.fromRGB(80, 170, 255) },
	{ id = "Jump", name = "Super Jump", price = 120, x = 40, color = Color3.fromRGB(90, 220, 120) },
	{ id = "Trail", name = "Rainbow Trail", price = 200, x = 55, color = Color3.fromRGB(190, 110, 255) },
}

local GOLD = Color3.fromRGB(255, 210, 60)
local GREEN = Color3.fromRGB(120, 255, 120)
local RED = Color3.fromRGB(255, 110, 110)

-- ===== تنظيف القالب الافتراضي =====
for _, child in ipairs(workspace:GetChildren()) do
	if child.Name == "Baseplate" or child:IsA("SpawnLocation") then
		child:Destroy()
	end
end

local map = Instance.new("Folder")
map.Name = "GeneratedMap"
map.Parent = workspace

-- ===== أدوات مساعدة =====
local function part(props, className)
	local p = Instance.new(className or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		if key ~= "Parent" then
			p[key] = value
		end
	end
	p.Parent = props.Parent or map
	return p
end

local function sign(adornee, text, color)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 50)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.MaxDistance = 150
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Adornee = adornee
	gui.Parent = adornee
end

local function getPlayer(hit)
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	return Players:GetPlayerFromCharacter(character), humanoid
end

-- رسالة تطلع فوق الشاشة للاعب
local function notify(player, text, color)
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return end
	local screen = playerGui:FindFirstChild("Notify")
	if not screen then
		screen = Instance.new("ScreenGui")
		screen.Name = "Notify"
		screen.ResetOnSpawn = false
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, 60)
		label.Size = UDim2.new(0.6, 0, 0, 44)
		label.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
		label.BackgroundTransparency = 0.25
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Visible = false
		Instance.new("UICorner").Parent = label
		label.Parent = screen
		screen.Parent = playerGui
	end
	local label = screen.Label
	label.Text = text
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.Visible = true
	local token = (label:GetAttribute("Token") or 0) + 1
	label:SetAttribute("Token", token)
	task.delay(4, function()
		if label.Parent and label:GetAttribute("Token") == token then
			label.Visible = false
		end
	end)
end

local function notifyAll(text, color, except)
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= except then
			notify(player, text, color)
		end
	end
end

-- ===== الإضاءة والجو =====
Lighting.ClockTime = 14
Lighting.Brightness = 2
local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = 0.3
atmosphere.Parent = Lighting

-- ===== الأرض والبحيرة =====
Terrain:FillBlock(CFrame.new(0, -8, 0), Vector3.new(600, 16, 600), Enum.Material.Grass)
Terrain:FillBlock(CFrame.new(-110, -4, -100), Vector3.new(76, 8, 76), Enum.Material.Sand)
Terrain:FillBlock(CFrame.new(-110, -4, -100), Vector3.new(60, 8, 60), Enum.Material.Water)

-- ===== السبون =====
local spawn = part({
	Name = "MainSpawn",
	Size = Vector3.new(12, 1, 12),
	CFrame = CFrame.new(0, 0.5, 0),
	Color = Color3.fromRGB(60, 160, 255),
	Material = Enum.Material.SmoothPlastic,
}, "SpawnLocation")
spawn.Duration = 0
sign(spawn, "Collect coins, shop, beat the obby!", Color3.fromRGB(255, 255, 120))

-- ===== الشوارع =====
local roadColor = Color3.fromRGB(110, 110, 115)
part({ Name = "Road", Size = Vector3.new(10, 0.4, 140), CFrame = CFrame.new(0, 0.2, -20), Color = roadColor, Material = Enum.Material.Cobblestone })
part({ Name = "Road", Size = Vector3.new(140, 0.4, 10), CFrame = CFrame.new(0, 0.2, -40), Color = roadColor, Material = Enum.Material.Cobblestone })

-- ===== البيوت =====
local function house(pos, color, faceAngle)
	local w, h, d, roofH = 16, 10, 14, 5
	local model = Instance.new("Model")
	model.Name = "House"
	model.Parent = map
	local base = CFrame.new(pos) * CFrame.Angles(0, math.rad(faceAngle), 0)

	part({ Name = "Body", Size = Vector3.new(w, h, d), CFrame = base * CFrame.new(0, h / 2, 0), Color = color, Material = Enum.Material.Brick, Parent = model })
	-- السقف: قطعتين مائلة تلتقي بالنص
	local roofColor = Color3.fromRGB(150, 50, 40)
	local half = w / 2 + 1
	part({ Size = Vector3.new(d + 2, roofH, half), CFrame = base * CFrame.new(-half / 2, h + roofH / 2, 0) * CFrame.Angles(0, math.rad(90), 0), Color = roofColor, Material = Enum.Material.Wood, Parent = model }, "WedgePart")
	part({ Size = Vector3.new(d + 2, roofH, half), CFrame = base * CFrame.new(half / 2, h + roofH / 2, 0) * CFrame.Angles(0, math.rad(-90), 0), Color = roofColor, Material = Enum.Material.Wood, Parent = model }, "WedgePart")
	-- الباب والشبابيك (بالواجهة)
	part({ Name = "Door", Size = Vector3.new(4, 7, 0.3), CFrame = base * CFrame.new(0, 3.5, -d / 2 - 0.15), Color = Color3.fromRGB(90, 55, 30), Material = Enum.Material.Wood, Parent = model })
	for _, x in ipairs({ -5, 5 }) do
		part({ Name = "Window", Size = Vector3.new(3, 3, 0.3), CFrame = base * CFrame.new(x, 6, -d / 2 - 0.15), Color = Color3.fromRGB(170, 220, 255), Material = Enum.Material.Glass, Transparency = 0.3, Parent = model })
	end
end

local houseColors = {
	Color3.fromRGB(240, 220, 180), Color3.fromRGB(200, 230, 200),
	Color3.fromRGB(230, 200, 220), Color3.fromRGB(210, 210, 240),
}
local i = 0
for _, z in ipairs({ -80, -15 }) do
	for _, x in ipairs({ -45, -20, 20, 45 }) do
		i += 1
		-- البيوت تواجه الشارع
		house(Vector3.new(x, 0, z), houseColors[(i - 1) % #houseColors + 1], z < -40 and 180 or 0)
	end
end

-- ===== الأشجار =====
local rng = Random.new(SEED)
local function tree(pos)
	local height = rng:NextNumber(8, 14)
	part({ Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, 2, 2), CFrame = CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(105, 70, 40), Material = Enum.Material.Wood })
	local size = rng:NextNumber(7, 11)
	part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), CFrame = CFrame.new(pos + Vector3.new(0, height + size / 3, 0)), Color = Color3.fromRGB(40, rng:NextInteger(120, 170), 50), Material = Enum.Material.Grass })
end

local planted = 0
while planted < 70 do
	local x, z = rng:NextNumber(-280, 280), rng:NextNumber(-280, 280)
	local inTown = math.abs(x) < 75 and z > -110 and z < 30
	local inObby = math.abs(x) < 35 and z > 30
	local inLake = math.abs(x + 110) < 45 and math.abs(z + 100) < 50
	if not (inTown or inObby or inLake) then
		tree(Vector3.new(x, 0, z))
		planted += 1
	end
end

-- ===== الكوينز =====
local coins = {}
local function makeCoin(pos, value, respawnTime)
	local coin = part({ Name = "Coin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 3, 3), CFrame = CFrame.new(pos), Color = GOLD, Material = Enum.Material.Neon, CanCollide = false })
	table.insert(coins, coin)
	coin.Touched:Connect(function(hit)
		if coin.Transparency > 0 then return end
		local player = getPlayer(hit)
		if not player or not player:FindFirstChild("leaderstats") then return end
		coin.Transparency = 1
		player.leaderstats.Coins.Value += value
		if respawnTime then
			task.delay(respawnTime, function()
				coin.Transparency = 0
			end)
		else
			coin:Destroy()
		end
	end)
	return coin
end

-- كوينز على الشوارع
for z = -85, 25, 10 do
	if math.abs(z) > 8 then
		makeCoin(Vector3.new(0, 3, z), 1, 15)
	end
end
for x = -65, 65, 10 do
	if x ~= -5 and x ~= 5 then
		makeCoin(Vector3.new(x, 3, -40), 1, 15)
	end
end

-- ===== المتجر =====
local shopPads = {}
for _, item in ipairs(SHOP) do
	local pad = part({ Name = "Shop_" .. item.id, Size = Vector3.new(10, 1, 8), CFrame = CFrame.new(item.x, 0.6, 14), Color = item.color, Material = Enum.Material.Neon })
	sign(pad, item.name .. " - " .. item.price .. " coins", item.color)
	shopPads[item] = pad
end

-- ===== الكنز السري تحت البحيرة =====
local chest = part({ Name = "SecretChest", Size = Vector3.new(4, 3, 3), CFrame = CFrame.new(-110, -6.5, -100), Color = Color3.fromRGB(110, 70, 35), Material = Enum.Material.Wood })
part({ Name = "ChestLid", Size = Vector3.new(4.2, 0.6, 3.2), CFrame = CFrame.new(-110, -4.7, -100), Color = GOLD, Material = Enum.Material.Neon })
local glow = Instance.new("PointLight")
glow.Color = GOLD
glow.Range = 14
glow.Brightness = 3
glow.Parent = chest
local hint = part({ Name = "HintPost", Size = Vector3.new(1, 4, 1), CFrame = CFrame.new(-110, 2, -58), Color = Color3.fromRGB(105, 70, 40), Material = Enum.Material.Wood })
sign(hint, "Psst... treasure hides under the lake", Color3.fromRGB(150, 220, 255))

-- ===== الأوبي =====
local checkpoints = { [0] = spawn }
local palette = {
	Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 180, 60), Color3.fromRGB(255, 240, 80),
	Color3.fromRGB(90, 220, 120), Color3.fromRGB(80, 170, 255), Color3.fromRGB(190, 110, 255),
}

local killParts = {}
local y = 2
local edge = 40 -- الحافة البعيدة لآخر منصة

local startPad = part({ Name = "ObbyStart", Size = Vector3.new(14, 1, 10), CFrame = CFrame.new(0, 1.5, 35), Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.SmoothPlastic })
sign(startPad, "OBBY START", GREEN)
local lavaStart = edge

local function nextPlatform(size, gap, rise)
	y = math.clamp(y + rise, 2, 22)
	local center = edge + gap + size.Z / 2
	edge = center + size.Z / 2
	return CFrame.new(rng:NextNumber(-6, 6), y, center)
end

for stage = 1, STAGES do
	local cpSize = Vector3.new(12, 1, 12)
	local cp = part({ Name = "Checkpoint" .. stage, Size = cpSize, CFrame = nextPlatform(cpSize, 5, 1), Color = Color3.fromRGB(40, 200, 80), Material = Enum.Material.Neon })
	cp:SetAttribute("Stage", stage)
	checkpoints[stage] = cp
	sign(cp, "Checkpoint " .. stage, GREEN)

	for n = 1, PLATS_PER_STAGE do
		local gap = math.min(3 + stage, 7)
		local rise = rng:NextInteger(-1, 2)
		local color = palette[rng:NextInteger(1, #palette)]
		if stage >= 2 and n % 3 == 0 then
			-- منصة عليها خط ليزر لازم تنط فوقه
			local size = Vector3.new(8, 1, 12)
			local cf = nextPlatform(size, gap, rise)
			part({ Name = "Platform", Size = size, CFrame = cf, Color = color, Material = Enum.Material.SmoothPlastic })
			table.insert(killParts, part({ Name = "KillBar", Size = Vector3.new(8, 0.6, 1), CFrame = cf * CFrame.new(0, 0.8, 0), Color = Color3.fromRGB(255, 0, 0), Material = Enum.Material.Neon }))
		elseif stage >= 3 and n % 2 == 0 then
			local size = Vector3.new(4, 1, 4) -- منصة صغيرة
			part({ Name = "Platform", Size = size, CFrame = nextPlatform(size, gap - 1, rise), Color = color, Material = Enum.Material.SmoothPlastic })
		else
			local s = rng:NextInteger(6, 8)
			local size = Vector3.new(s, 1, s)
			local cf = nextPlatform(size, gap, rise)
			part({ Name = "Platform", Size = size, CFrame = cf, Color = color, Material = Enum.Material.SmoothPlastic })
			makeCoin((cf * CFrame.new(0, 3, 0)).Position, 3, 20)
		end
	end
end

local finishSize = Vector3.new(16, 1, 16)
local finish = part({ Name = "Finish", Size = finishSize, CFrame = nextPlatform(finishSize, 5, 0), Color = Color3.fromRGB(255, 200, 0), Material = Enum.Material.Neon })
checkpoints[STAGES + 1] = finish
sign(finish, "🏆 FINISH 🏆", GOLD)

-- أرضية اللافا تحت الأوبي كله
local lavaLength = edge - lavaStart + 10
table.insert(killParts, part({ Name = "Lava", Size = Vector3.new(50, 1, lavaLength), CFrame = CFrame.new(0, 0.5, lavaStart + lavaLength / 2), Color = Color3.fromRGB(255, 80, 0), Material = Enum.Material.Neon }))

-- ===== الحفظ (DataStore) =====
local storeOk, store = pcall(function()
	return DataStoreService:GetDataStore("PlayerData_v1")
end)
if not storeOk then
	warn("DataStore not available (publish the game and enable API access). Progress won't be saved.")
	store = nil
end

local sessions = {}

local function loadData(player)
	if not store then return nil, false end
	local ok, data = pcall(function()
		return store:GetAsync("u_" .. player.UserId)
	end)
	if not ok then
		warn("Failed to load data for " .. player.Name .. ": " .. tostring(data))
		return nil, false
	end
	return data, true
end

local function saveData(player)
	local session = sessions[player]
	local leaderstats = player:FindFirstChild("leaderstats")
	-- إذا التحميل فشل ما نحفظ، عشان ما نمسح بيانات اللاعب القديمة
	if not (store and session and session.loaded and leaderstats) then return end
	local payload = {
		coins = leaderstats.Coins.Value,
		wins = leaderstats.Wins.Value,
		stage = math.min(leaderstats.Stage.Value, STAGES),
		owned = session.owned,
		foundSecret = session.foundSecret,
		lastDay = session.lastDay,
		streak = session.streak,
	}
	local ok, err = pcall(function()
		store:SetAsync("u_" .. player.UserId, payload)
	end)
	if not ok then
		warn("Failed to save data for " .. player.Name .. ": " .. tostring(err))
	end
end

-- ===== مزايا المتجر =====
local function applyPerks(player, character)
	local session = sessions[player]
	if not session then return end
	local owned = session.owned
	local humanoid = character:WaitForChild("Humanoid")
	if owned.Speed then
		humanoid.WalkSpeed = 24
	end
	if owned.Jump then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 62
	end
	if owned.Trail then
		local root = character:WaitForChild("HumanoidRootPart")
		if root:FindFirstChild("RainbowTrail") then return end
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 1, 0)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -1, 0)
		a1.Parent = root
		local trail = Instance.new("Trail")
		trail.Name = "RainbowTrail"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.7
		trail.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 60)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(60, 255, 120)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(60, 160, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 80, 255)),
		})
		trail.Parent = root
	end
end

for item, pad in pairs(shopPads) do
	local cooldown = {}
	pad.Touched:Connect(function(hit)
		local player = getPlayer(hit)
		local session = player and sessions[player]
		if not session or cooldown[player] then return end
		cooldown[player] = true
		task.delay(2, function()
			cooldown[player] = nil
		end)

		local coinsValue = player.leaderstats.Coins
		if session.owned[item.id] then
			notify(player, "You already own " .. item.name, GREEN)
		elseif coinsValue.Value < item.price then
			notify(player, "Need " .. (item.price - coinsValue.Value) .. " more coins for " .. item.name, RED)
		else
			coinsValue.Value -= item.price
			session.owned[item.id] = true
			if player.Character then
				task.spawn(applyPerks, player, player.Character)
			end
			notify(player, "Bought " .. item.name .. "!", GREEN)
			saveData(player)
		end
	end)
end

-- ===== منطق اللعبة =====
for _, kill in ipairs(killParts) do
	kill.Touched:Connect(function(hit)
		local _, humanoid = getPlayer(hit)
		if humanoid then
			humanoid.Health = 0
		end
	end)
end

chest.Touched:Connect(function(hit)
	local player = getPlayer(hit)
	local session = player and sessions[player]
	if not session or session.foundSecret then return end
	session.foundSecret = true
	player.leaderstats.Coins.Value += SECRET_REWARD
	notify(player, "You found the secret treasure! +" .. SECRET_REWARD .. " coins", GOLD)
	notifyAll(player.DisplayName .. " found the secret treasure! Can you?", GOLD, player)
	saveData(player)
end)

local function onPlayerAdded(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local function stat(name)
		local value = Instance.new("IntValue")
		value.Name = name
		value.Parent = leaderstats
		return value
	end
	local stageValue = stat("Stage")
	local coinsValue = stat("Coins")
	local winsValue = stat("Wins")
	leaderstats.Parent = player

	local session = { owned = {}, foundSecret = false, lastDay = 0, streak = 0, loaded = false }
	sessions[player] = session

	-- لما يموت يرجع لآخر نقطة حفظ وصلها
	local function placeCharacter(character)
		task.spawn(applyPerks, player, character)
		local cp = checkpoints[stageValue.Value]
		if stageValue.Value > 0 and cp then
			character:WaitForChild("HumanoidRootPart")
			task.wait(0.1)
			character:PivotTo(cp.CFrame * CFrame.new(0, 4, 0))
		end
	end
	player.CharacterAdded:Connect(placeCharacter)

	local data, loaded = loadData(player)
	if not player.Parent then return end
	session.loaded = loaded
	if data then
		coinsValue.Value = data.coins or 0
		winsValue.Value = data.wins or 0
		stageValue.Value = math.clamp(data.stage or 0, 0, STAGES)
		session.owned = data.owned or {}
		session.foundSecret = data.foundSecret or false
		session.lastDay = data.lastDay or 0
		session.streak = data.streak or 0
	end
	if player.Character then
		task.spawn(placeCharacter, player.Character)
	end

	-- مكافأة يومية: كل يوم ورا بعض تكبر
	local today = math.floor(os.time() / 86400)
	if session.lastDay ~= today then
		session.streak = (session.lastDay == today - 1) and math.min(session.streak + 1, 7) or 1
		session.lastDay = today
		local reward = DAILY_REWARD * session.streak
		coinsValue.Value += reward
		task.delay(3, notify, player, "Daily reward! Day " .. session.streak .. " streak: +" .. reward .. " coins", GOLD)
	elseif stageValue.Value > 0 then
		task.delay(3, notify, player, "Welcome back! You're on stage " .. stageValue.Value, GREEN)
	end

	-- مكافأة كل فترة لعب
	task.spawn(function()
		while true do
			task.wait(PLAYTIME_EVERY)
			if not player.Parent then break end
			coinsValue.Value += PLAYTIME_REWARD
			notify(player, "+" .. PLAYTIME_REWARD .. " coins for playing! Stay for more", GOLD)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	sessions[player] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveData(player)
	end
end)

-- حفظ تلقائي كل دقيقتين
task.spawn(function()
	while true do
		task.wait(120)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(saveData, player)
		end
	end
end)

local function onFinish(player, humanoid)
	local leaderstats = player.leaderstats
	leaderstats.Wins.Value += 1
	leaderstats.Coins.Value += FINISH_REWARD
	local root = humanoid.Parent and humanoid.Parent:FindFirstChild("HumanoidRootPart")
	if root then
		local sparkles = Instance.new("Sparkles")
		sparkles.Parent = root
		Debris:AddItem(sparkles, 6)
	end
	notify(player, "You beat the obby! +" .. FINISH_REWARD .. " coins 🏆", GOLD)
	notifyAll(player.DisplayName .. " beat the obby! 🏆 (Wins: " .. leaderstats.Wins.Value .. ")", GOLD, player)

	-- يرجع للبداية عشان يعيدها ويجمع أكثر
	task.delay(4, function()
		if not player.Parent then return end
		leaderstats.Stage.Value = 0
		if player.Character then
			player.Character:PivotTo(spawn.CFrame * CFrame.new(0, 4, 0))
		end
		notify(player, "Run it again for more coins and wins!", GREEN)
		saveData(player)
	end)
end

for stage = 1, STAGES + 1 do
	checkpoints[stage].Touched:Connect(function(hit)
		local player, humanoid = getPlayer(hit)
		if not player or not sessions[player] then return end
		local stageValue = player.leaderstats.Stage
		-- لازم يمشي بالترتيب، ما يقدر يقفز مراحل
		if stageValue.Value ~= stage - 1 then return end
		stageValue.Value = stage
		if stage == STAGES + 1 then
			onFinish(player, humanoid)
		else
			player.leaderstats.Coins.Value += CHECKPOINT_REWARD
			notify(player, "Checkpoint " .. stage .. "! +" .. CHECKPOINT_REWARD .. " coins", GREEN)
		end
	end)
end

-- ===== حدث مطر الكوينز =====
local eventRng = Random.new()
task.spawn(function()
	while true do
		task.wait(COIN_RAIN_EVERY - 30)
		notifyAll("💰 COIN RAIN in 30 seconds at spawn!", GOLD)
		task.wait(30)
		notifyAll("💰 COIN RAIN! Grab them fast!", GOLD)
		for _ = 1, 40 do
			local coin = makeCoin(Vector3.new(eventRng:NextNumber(-70, 70), 3, eventRng:NextNumber(-4, 26)), 2, nil)
			Debris:AddItem(coin, 45)
			task.wait(0.1)
		end
	end
end)

-- لف الكوينز
task.spawn(function()
	local angle = 0
	while true do
		angle += 0.15
		for index = #coins, 1, -1 do
			local coin = coins[index]
			if coin.Parent then
				coin.CFrame = CFrame.new(coin.Position) * CFrame.Angles(0, angle, 0)
			else
				table.remove(coins, index)
			end
		end
		task.wait(0.05)
	end
end)

print("✅ Map generated: " .. STAGES .. " stages, finish at Z = " .. math.floor(edge))
