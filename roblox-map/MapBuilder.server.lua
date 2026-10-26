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

	المزرعة والندرة:
	  • كل لاعب ياخذ أرض فيها 9 مربعات، يزرع ويحصد، والزرع يكبر حتى لو طلع من اللعبة
	  • كل نبتة لها ندرة مخفية (Common لين Mythic) تنكشف لما تكبر، والنادرة تلمع وتنباع بأضعاف
	  • متجر بذور مشترك بالسيرفر: المخزون محدود ويتجدد كل 5 دقايق، والبذور النادرة تطلع أحياناً بس
	  • نقاط Rarity، ولوحة "أندر المزارعين" تجمع كل السيرفرات
	  • الحصاد الأسطوري ينعلن بكل السيرفرات

	الطقس (حدث كل 6 دقايق، ينعلن قبله بـ 30 ثانية):
	  • عاصفة رعد ⚡: البرق يضرب الزرع ويخليه Electric (البيع ×5)
	  • القمر الدموي 🌕: اللي ينزرع وقتها ياخذ فرصتين بالندرة
	  • المطر الذهبي ✨: الزرع يكبر بسرعة الضعف، واللي يخلص وقتها يصير Golden (البيع ×3)

	طريقة الاستخدام: حط هذا السكربت داخل ServerScriptService كـ Script (مو LocalScript)
	عشان الحفظ يشتغل في Studio: Experience Settings ← Security ← Enable Studio Access to API Services
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local DataStoreService = game:GetService("DataStoreService")
local Debris = game:GetService("Debris")
local MessagingService = game:GetService("MessagingService")
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

-- البذور: grow = وقت النمو بالثواني، sell = سعر البيع (Common)، points = يضرب نقاط الندرة
-- maxStock = أكثر عدد يطلع بالمتجر، chance = احتمال تطلع بكل تجديد (بدون maxStock = دايم موجودة)
local SEEDS = {
	{ id = "Carrot", price = 10, grow = 60, sell = 18, points = 1, size = 1.5, color = Color3.fromRGB(255, 140, 40) },
	{ id = "Strawberry", price = 30, grow = 300, sell = 60, points = 2, size = 1.8, color = Color3.fromRGB(230, 40, 60), maxStock = 5, chance = 0.9 },
	{ id = "Pumpkin", price = 100, grow = 1200, sell = 230, points = 4, size = 3, color = Color3.fromRGB(255, 120, 20), maxStock = 3, chance = 0.6 },
	{ id = "Watermelon", price = 250, grow = 3600, sell = 620, points = 8, size = 3.4, color = Color3.fromRGB(60, 170, 60), maxStock = 2, chance = 0.4 },
	{ id = "Moonflower", price = 800, grow = 10800, sell = 2200, points = 20, size = 2.6, color = Color3.fromRGB(150, 180, 255), maxStock = 1, chance = 0.2, neon = true, announce = true },
	{ id = "DragonFruit", name = "Dragon Fruit", price = 2500, grow = 28800, sell = 8000, points = 50, size = 3, color = Color3.fromRGB(255, 50, 170), maxStock = 1, chance = 0.07, neon = true, announce = true },
}

-- الندرة: chance بالمية، mult = يضرب سعر البيع، points = نقاط Rarity (× points حق البذرة)
local RARITIES = {
	{ name = "Common", chance = 60, mult = 1, points = 0, color = Color3.fromRGB(220, 220, 220) },
	{ name = "Uncommon", chance = 25, mult = 1.5, points = 1, color = Color3.fromRGB(90, 220, 120) },
	{ name = "Rare", chance = 10, mult = 3, points = 5, color = Color3.fromRGB(80, 170, 255) },
	{ name = "Epic", chance = 4, mult = 6, points = 25, color = Color3.fromRGB(190, 110, 255) },
	{ name = "Legendary", chance = 0.9, mult = 15, points = 100, color = Color3.fromRGB(255, 200, 40) },
	{ name = "Mythic", chance = 0.1, mult = 50, points = 500, color = Color3.fromRGB(255, 60, 120) },
}

-- الطفرات من الطقس: mult = يضرب سعر البيع (فوق الندرة)، ونقاط Rarity تتضاعف
local MUTATIONS = {
	Electric = { mult = 5, icon = "⚡", color = Color3.fromRGB(90, 230, 255) },
	Golden = { mult = 3, icon = "✨", color = Color3.fromRGB(255, 210, 60) },
}

local WEATHER_EVERY = 360        -- كل كم ثانية يجي حدث طقس (6 دقايق)
local WEATHER_LENGTH = 150       -- مدة الحدث بالثواني
local LIGHTNING_EVERY = 6        -- ضربة برق كل كم ثانية وقت العاصفة
local LIGHTNING_CROP_CHANCE = 0.4 -- احتمال البرق يضرب زرع (والباقي يضرب الأرض)

local RESTOCK_EVERY = 300   -- تجديد متجر البذور بالثواني (5 دقايق)
local STARTER_SEEDS = 3     -- جزر مجاني للاعب الجديد

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
sign(spawn, "Obby, farm & rare crops! Farm is east →", Color3.fromRGB(255, 255, 120))

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
	local inFarm = x > 75 and x < 215 and z > -95 and z < 20
	if not (inTown or inObby or inLake or inFarm) then
		tree(Vector3.new(x, 0, z))
		planted += 1
	end
end

-- ===== الكوينز =====
-- الجمع يصير بالمسافة (مو Touched) عشان الكوينز اللي تلف ما تفوت اللاعب
local COIN_PICKUP_RANGE = 4.5
local coins = {}
local function makeCoin(pos, value, respawnTime)
	local coin = part({ Name = "Coin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 3, 3), CFrame = CFrame.new(pos), Color = GOLD, Material = Enum.Material.Neon, CanCollide = false, CanTouch = false })
	table.insert(coins, { part = coin, value = value, respawn = respawnTime, active = true })
	return coin
end

local function collectCoin(entry, player)
	entry.active = false
	entry.part.Transparency = 1
	player.leaderstats.Coins.Value += entry.value
	if entry.respawn then
		task.delay(entry.respawn, function()
			entry.active = true
			entry.part.Transparency = 0
		end)
	else
		entry.part:Destroy()
	end
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
local rarityStoreOk, rarityStore = pcall(function()
	return DataStoreService:GetOrderedDataStore("RarityPoints_v1")
end)
if not rarityStoreOk then
	rarityStore = nil
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
		seeds = session.seeds,
		farm = session.farm,
		selectedSeed = session.selectedSeed,
		rarity = leaderstats.Rarity.Value,
		bestTier = session.bestTier,
	}
	local ok, err = pcall(function()
		store:SetAsync("u_" .. player.UserId, payload)
	end)
	if not ok then
		warn("Failed to save data for " .. player.Name .. ": " .. tostring(err))
	end
	if rarityStore then
		pcall(function()
			rarityStore:SetAsync("u_" .. player.UserId, leaderstats.Rarity.Value)
		end)
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

-- ===== المزرعة =====
local farmRng = Random.new()
local currentWeather = nil -- اسم الحدث الشغال حالياً (أو nil)
local seedById = {}
for _, seed in ipairs(SEEDS) do
	seed.name = seed.name or seed.id
	seedById[seed.id] = seed
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

local function rollOnce()
	local roll = farmRng:NextNumber(0, 100)
	local total = 0
	for index, rarity in ipairs(RARITIES) do
		total += rarity.chance
		if roll <= total then
			return index
		end
	end
	return 1
end

-- luck = كم مرة نرمي وناخذ الأحسن
local function rollRarity(luck)
	local best = 1
	for _ = 1, luck or 1 do
		best = math.max(best, rollOnce())
	end
	return best
end

-- لوحة كبيرة بحجم بالـ studs (تكبر وتصغر مع المسافة)
local function board(adornee, width, height, offsetY)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(width, 0, height, 0)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = 120
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	label.BackgroundTransparency = 0.3
	label.TextScaled = true
	label.RichText = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = gui
	gui.Adornee = adornee
	gui.Parent = adornee
	return label
end

local function prompt(parent, action)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.HoldDuration = 0
	p.MaxActivationDistance = 9
	p.RequiresLineOfSight = false
	p.Enabled = false
	p.Parent = parent
	return p
end

local function nextSeed(session, current)
	local start = 0
	for index, seed in ipairs(SEEDS) do
		if seed.id == current then
			start = index
		end
	end
	for offset = 1, #SEEDS do
		local seed = SEEDS[(start + offset - 1) % #SEEDS + 1]
		if (session.seeds[seed.id] or 0) > 0 then
			return seed.id
		end
	end
	return nil
end

local function seedText(session)
	local id = session.selectedSeed
	local count = id and session.seeds[id] or 0
	if count <= 0 then
		return "No seeds - visit the seed shop"
	end
	return seedById[id].name .. " seed x" .. count
end

local function growthStage(data)
	local seed = seedById[data.seed]
	local elapsed = os.time() - data.at
	if elapsed >= seed.grow then
		return 3, 0
	end
	return (elapsed < seed.grow / 2) and 1 or 2, seed.grow - elapsed
end

-- الشارع والأراضي
part({ Name = "FarmRoad", Size = Vector3.new(140, 0.4, 10), CFrame = CFrame.new(140, 0.2, -50), Color = roadColor, Material = Enum.Material.Cobblestone })

local plots = {}
for row, z in ipairs({ -28, -72 }) do
	for _, x in ipairs({ 100, 130, 160, 190 }) do
		local center = Vector3.new(x, 0, z)
		local plot = { tiles = {}, prompts = {}, visuals = {}, labels = {}, stages = {} }
		plot.base = part({ Name = "FarmPlot", Size = Vector3.new(26, 0.6, 26), CFrame = CFrame.new(center + Vector3.new(0, 0.3, 0)), Color = Color3.fromRGB(110, 160, 70), Material = Enum.Material.Grass })
		plot.ownerLabel = board(plot.base, 12, 2, 12)
		plot.ownerLabel.Text = "Free plot"
		for dx = -7, 7, 7 do
			for dz = -7, 7, 7 do
				local tile = part({ Name = "Soil", Size = Vector3.new(6, 0.4, 6), CFrame = CFrame.new(center + Vector3.new(dx, 0.8, dz)), Color = Color3.fromRGB(95, 65, 40), Material = Enum.Material.Ground })
				table.insert(plot.tiles, tile)
				table.insert(plot.prompts, prompt(tile, "Plant"))
			end
		end
		-- كيس البذور على جهة الشارع
		local side = row == 1 and -1 or 1
		plot.bag = part({ Name = "SeedBag", Size = Vector3.new(2, 3, 2), CFrame = CFrame.new(center + Vector3.new(0, 2, side * 11.5)), Color = Color3.fromRGB(200, 170, 110), Material = Enum.Material.Fabric })
		plot.bagPrompt = prompt(plot.bag, "Switch seed")
		table.insert(plots, plot)
	end
end

local function cropTitle(data)
	local tier = data.tier or 1
	local rarity = RARITIES[tier] or RARITIES[1]
	local mutation = MUTATIONS[data.mutation]
	return (mutation and mutation.icon .. " " .. data.mutation .. " " or "") .. (tier > 1 and rarity.name .. " " or "") .. seedById[data.seed].name
end

local function growingText(data, remaining)
	local mutation = MUTATIONS[data.mutation]
	return (mutation and mutation.icon .. " " or "") .. seedById[data.seed].name .. " " .. formatTime(remaining)
end

local function clearVisual(plot, t)
	if plot.visuals[t] then
		plot.visuals[t]:Destroy()
	end
	plot.visuals[t] = nil
	plot.labels[t] = nil
	plot.stages[t] = nil
end

local function renderTile(plot, t)
	clearVisual(plot, t)
	local session = plot.owner and sessions[plot.owner]
	local tilePrompt = plot.prompts[t]
	if not session then
		tilePrompt.Enabled = false
		return
	end
	local key = "t" .. t
	local data = session.farm[key]
	if data and not seedById[data.seed] then
		session.farm[key] = nil
		data = nil
	end
	if not data then
		tilePrompt.ActionText = "Plant"
		tilePrompt.ObjectText = seedText(session)
		tilePrompt.Enabled = true
		return
	end

	local seed = seedById[data.seed]
	local tier = data.tier or 1
	local rarity = RARITIES[tier] or RARITIES[1]
	local stage, remaining = growthStage(data)
	local base = plot.tiles[t].CFrame * CFrame.new(0, 0.2, 0)
	local model = Instance.new("Model")
	model.Name = "Crop"
	model.Parent = map
	plot.visuals[t] = model
	plot.stages[t] = stage

	local stemHeight = stage == 1 and 1 or stage == 2 and 2.5 or 3.5
	local stem = part({ Name = "Stem", Size = Vector3.new(0.5, stemHeight, 0.5), CFrame = base * CFrame.new(0, stemHeight / 2, 0), Color = Color3.fromRGB(60, 150, 50), Material = Enum.Material.Grass, CanCollide = false, Parent = model })
	local leafSize = stage == 1 and 1.2 or 2.2
	part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(leafSize, leafSize, leafSize), CFrame = base * CFrame.new(0, stemHeight, 0), Color = Color3.fromRGB(70, 180, 60), Material = Enum.Material.Grass, CanCollide = false, Parent = model })

	if stage < 3 then
		-- الندرة مخفية لين تكبر
		tilePrompt.Enabled = false
		local label = board(stem, 5, 1.2, stemHeight / 2 + 2)
		label.Text = growingText(data, remaining)
		plot.labels[t] = label
		return
	end

	local mutation = MUTATIONS[data.mutation]
	local fruitColor = data.mutation == "Golden" and GOLD or seed.color
	local fruit = part({ Name = "Fruit", Shape = Enum.PartType.Ball, Size = Vector3.new(seed.size, seed.size, seed.size), CFrame = base * CFrame.new(0, stemHeight + seed.size / 2 + 0.3, 0), Color = fruitColor, Material = (seed.neon or mutation) and Enum.Material.Neon or Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
	local glowColor = mutation and mutation.color or rarity.color
	if tier >= 3 or mutation then
		local light = Instance.new("PointLight")
		light.Color = glowColor
		light.Range = 6 + tier * 2
		light.Brightness = 2
		light.Parent = fruit
	end
	if tier >= 5 or mutation then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = glowColor
		sparkles.Parent = fruit
	end
	local cropName = cropTitle(data)
	local label = board(stem, 7, 1.4, stemHeight / 2 + seed.size + 1.5)
	label.Text = cropName
	label.TextColor3 = rarity.color
	tilePrompt.ActionText = "Harvest"
	tilePrompt.ObjectText = cropName
	tilePrompt.Enabled = true
end

local function refreshPrompts(plot)
	local session = plot.owner and sessions[plot.owner]
	if not session then return end
	local text = seedText(session)
	plot.bagPrompt.ObjectText = text
	for t, tilePrompt in ipairs(plot.prompts) do
		if not session.farm["t" .. t] then
			tilePrompt.ObjectText = text
		end
	end
end

local function assignPlot(player)
	local session = sessions[player]
	for _, plot in ipairs(plots) do
		if not plot.owner then
			plot.owner = player
			session.plot = plot
			plot.ownerLabel.Text = player.DisplayName .. "'s Farm"
			plot.bagPrompt.Enabled = true
			for t = 1, #plot.tiles do
				renderTile(plot, t)
			end
			refreshPrompts(plot)
			return
		end
	end
	notify(player, "All farm plots are taken in this server", RED)
end

local function releasePlot(player)
	local session = sessions[player]
	local plot = session and session.plot
	if not plot then return end
	plot.owner = nil
	session.plot = nil
	for t = 1, #plot.tiles do
		clearVisual(plot, t)
		plot.prompts[t].Enabled = false
	end
	plot.bagPrompt.Enabled = false
	plot.ownerLabel.Text = "Free plot"
end

local function harvest(player, session, plot, t, data)
	local seed = seedById[data.seed]
	local tier = data.tier or 1
	local rarity = RARITIES[tier] or RARITIES[1]
	local mutation = MUTATIONS[data.mutation]
	local earned = math.floor(seed.sell * rarity.mult * (mutation and mutation.mult or 1))
	local points = rarity.points * seed.points * (mutation and 2 or 1)
	local cropName = cropTitle(data)
	session.farm["t" .. t] = nil
	player.leaderstats.Coins.Value += earned
	player.leaderstats.Rarity.Value += points
	session.bestTier = math.max(session.bestTier or 1, tier)
	renderTile(plot, t)

	notify(player, "Harvested " .. cropName .. "! +" .. earned .. " coins" .. (points > 0 and (", +" .. points .. " rarity") or ""), mutation and mutation.color or rarity.color)
	if tier >= 4 or (mutation and tier >= 3) then
		local text = "🌟 " .. player.DisplayName .. " harvested a " .. string.upper(cropName) .. "!"
		notifyAll(text, rarity.color, player)
		if tier >= 5 then
			-- إعلان بكل السيرفرات
			task.spawn(pcall, function()
				MessagingService:PublishAsync("RareHarvest", { text = text .. " (other server)", tier = tier, job = game.JobId })
			end)
		end
		saveData(player)
	end
end

pcall(function()
	MessagingService:SubscribeAsync("RareHarvest", function(message)
		local data = message.Data
		if type(data) ~= "table" or data.job == game.JobId then return end
		local rarity = RARITIES[data.tier]
		notifyAll(tostring(data.text), rarity and rarity.color or GOLD)
	end)
end)

for _, plot in ipairs(plots) do
	for t, tilePrompt in ipairs(plot.prompts) do
		tilePrompt.Triggered:Connect(function(player)
			local session = sessions[player]
			if plot.owner ~= player or not session then
				notify(player, "This isn't your farm!", RED)
				return
			end
			local key = "t" .. t
			local data = session.farm[key]
			if not data then
				local id = session.selectedSeed
				if not id or (session.seeds[id] or 0) <= 0 then
					notify(player, "No seeds! Buy some at the seed shop", RED)
					return
				end
				session.seeds[id] -= 1
				if session.seeds[id] <= 0 then
					session.seeds[id] = nil
					session.selectedSeed = nextSeed(session, id)
				end
				local luck = currentWeather == "BloodMoon" and 2 or 1
				session.farm[key] = { seed = id, at = os.time(), tier = rollRarity(luck) }
				if luck > 1 then
					notify(player, "🌕 Blood Moon luck! This crop rolled rarity twice", RED)
				end
				renderTile(plot, t)
				refreshPrompts(plot)
			elseif growthStage(data) == 3 then
				harvest(player, session, plot, t, data)
			end
		end)
	end

	plot.bagPrompt.Triggered:Connect(function(player)
		local session = sessions[player]
		if plot.owner ~= player or not session then
			notify(player, "This isn't your farm!", RED)
			return
		end
		local id = nextSeed(session, session.selectedSeed)
		if not id then
			notify(player, "No seeds! Buy some at the seed shop", RED)
			return
		end
		session.selectedSeed = id
		refreshPrompts(plot)
		notify(player, "Selected: " .. seedText(session), GREEN)
	end)
end

-- متجر البذور (المخزون مشترك بين كل اللي بالسيرفر)
local stock = {}
local nextRestock = 0
local crates = {}
local shopPost = part({ Name = "SeedShopSign", Size = Vector3.new(1, 6, 1), CFrame = CFrame.new(115, 3, 7), Color = Color3.fromRGB(105, 70, 40), Material = Enum.Material.Wood })
local shopLabel = board(shopPost, 14, 11, 9)
for index, seed in ipairs(SEEDS) do
	local crate = part({ Name = "SeedCrate", Size = Vector3.new(4, 2, 4), CFrame = CFrame.new(100 + (index - 1) * 6, 1, 2), Color = seed.color, Material = seed.neon and Enum.Material.Neon or Enum.Material.Wood })
	crates[seed.id] = prompt(crate, "Buy")
end

local function updateShop()
	local lines = { "🌱 SEED SHOP 🌱" }
	for _, seed in ipairs(SEEDS) do
		local count = stock[seed.id] or 0
		local stockText = count == math.huge and "∞" or (count > 0 and count .. " left" or "SOLD OUT")
		table.insert(lines, string.format('<font color="#%s">%s</font>  %dc  (%s)', seed.color:ToHex(), seed.name, seed.price, stockText))
		crates[seed.id].ObjectText = seed.name .. " - " .. seed.price .. "c (" .. stockText .. ")"
		crates[seed.id].Enabled = count > 0
	end
	table.insert(lines, "Restock in " .. formatTime(nextRestock - os.time()))
	shopLabel.Text = table.concat(lines, "\n")
end

local function restock()
	nextRestock = os.time() + RESTOCK_EVERY
	local rareNews = {}
	for _, seed in ipairs(SEEDS) do
		if not seed.maxStock then
			stock[seed.id] = math.huge
		elseif farmRng:NextNumber() < seed.chance then
			stock[seed.id] = farmRng:NextInteger(1, seed.maxStock)
			if seed.announce then
				table.insert(rareNews, seed.name)
			end
		else
			stock[seed.id] = 0
		end
	end
	if #rareNews > 0 then
		notifyAll("🔥 RARE SEEDS IN STOCK: " .. table.concat(rareNews, ", ") .. "! Go fast!", GOLD)
	end
	updateShop()
end
restock()

for _, seed in ipairs(SEEDS) do
	crates[seed.id].Triggered:Connect(function(player)
		local session = sessions[player]
		if not session then return end
		local coinsValue = player.leaderstats.Coins
		if (stock[seed.id] or 0) <= 0 then
			notify(player, seed.name .. " is sold out! Wait for the restock", RED)
			return
		end
		if coinsValue.Value < seed.price then
			notify(player, "Need " .. (seed.price - coinsValue.Value) .. " more coins for " .. seed.name, RED)
			return
		end
		coinsValue.Value -= seed.price
		stock[seed.id] -= 1
		session.seeds[seed.id] = (session.seeds[seed.id] or 0) + 1
		if not session.selectedSeed or (session.seeds[session.selectedSeed] or 0) <= 0 then
			session.selectedSeed = seed.id
		end
		if session.plot then
			refreshPrompts(session.plot)
		end
		notify(player, "Bought " .. seed.name .. " seed! (" .. session.seeds[seed.id] .. " in bag)", GREEN)
		if seed.announce then
			notifyAll(player.DisplayName .. " grabbed a " .. seed.name .. " seed!", GOLD, player)
		end
		updateShop()
	end)
end

-- لوحة أندر المزارعين (كل السيرفرات)
local boardPost = part({ Name = "RarityBoard", Size = Vector3.new(1, 6, 1), CFrame = CFrame.new(165, 3, 7), Color = Color3.fromRGB(105, 70, 40), Material = Enum.Material.Wood })
local rankLabel = board(boardPost, 12, 12, 9)
local nameCache = {}
local function nameOf(userId)
	if not userId then return "?" end
	if not nameCache[userId] then
		local ok, name = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		nameCache[userId] = ok and name or "?"
	end
	return nameCache[userId]
end

local function refreshRanking()
	local entries = {}
	local ok = rarityStore and pcall(function()
		local page = rarityStore:GetSortedAsync(false, 10):GetCurrentPage()
		for _, entry in ipairs(page) do
			table.insert(entries, { name = nameOf(tonumber((entry.key:gsub("u_", "")))), value = entry.value })
		end
	end)
	if not ok then
		-- بدون DataStore: نرتب اللي بالسيرفر بس
		entries = {}
		for _, player in ipairs(Players:GetPlayers()) do
			local leaderstats = player:FindFirstChild("leaderstats")
			if leaderstats then
				table.insert(entries, { name = player.DisplayName, value = leaderstats.Rarity.Value })
			end
		end
		table.sort(entries, function(a, b)
			return a.value > b.value
		end)
	end
	local lines = { "🏆 RAREST FARMERS 🏆" }
	for rank = 1, math.min(#entries, 10) do
		table.insert(lines, rank .. ". " .. entries[rank].name .. " - " .. entries[rank].value)
	end
	if #entries == 0 then
		table.insert(lines, "No one yet. Be the first!")
	end
	rankLabel.Text = table.concat(lines, "\n")
end

task.spawn(function()
	while true do
		refreshRanking()
		task.wait(60)
	end
end)

-- ===== الطقس =====
local WEATHERS = {
	Thunderstorm = {
		title = "⚡ THUNDERSTORM", hint = "Lightning makes crops ELECTRIC (x5)!",
		clock = 17.5, brightness = 0.6, density = 0.55,
		atmosphere = Color3.fromRGB(120, 130, 150), ambient = Color3.fromRGB(60, 70, 90),
		rain = Color3.fromRGB(170, 200, 255),
	},
	BloodMoon = {
		title = "🌕 BLOOD MOON", hint = "Crops planted now roll rarity twice!",
		clock = 0, brightness = 1, density = 0.4,
		atmosphere = Color3.fromRGB(200, 40, 40), ambient = Color3.fromRGB(130, 30, 30),
	},
	GoldenRain = {
		title = "✨ GOLDEN RAIN", hint = "Crops grow 2x faster and finish GOLDEN (x3)!",
		clock = 14, brightness = 2.5, density = 0.35,
		atmosphere = Color3.fromRGB(255, 220, 120), ambient = Color3.fromRGB(140, 120, 60),
		rain = GOLD,
	},
}
local WEATHER_ORDER = { "Thunderstorm", "BloodMoon", "GoldenRain" }

local defaultLighting = {
	clock = Lighting.ClockTime, brightness = Lighting.Brightness,
	ambient = Lighting.Ambient, outdoor = Lighting.OutdoorAmbient,
	density = atmosphere.Density, atmosphere = atmosphere.Color,
}

local rainCloud = part({ Name = "RainCloud", Size = Vector3.new(380, 1, 260), CFrame = CFrame.new(30, 90, -40), Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false })
local rain = Instance.new("ParticleEmitter")
rain.EmissionDirection = Enum.NormalId.Bottom
rain.Rate = 800
rain.Speed = NumberRange.new(70, 90)
rain.Lifetime = NumberRange.new(1.2, 1.4)
rain.Size = NumberSequence.new(0.25)
rain.LightEmission = 0.5
rain.Enabled = false
rain.Parent = rainCloud

local weatherBrightness = defaultLighting.brightness
local function applyWeather(id)
	local weather = WEATHERS[id]
	if weather then
		Lighting.ClockTime = weather.clock
		Lighting.Ambient = weather.ambient
		Lighting.OutdoorAmbient = weather.ambient
		atmosphere.Density = weather.density
		atmosphere.Color = weather.atmosphere
		weatherBrightness = weather.brightness
		rain.Enabled = weather.rain ~= nil
		if weather.rain then
			rain.Color = ColorSequence.new(weather.rain)
		end
	else
		Lighting.ClockTime = defaultLighting.clock
		Lighting.Ambient = defaultLighting.ambient
		Lighting.OutdoorAmbient = defaultLighting.outdoor
		atmosphere.Density = defaultLighting.density
		atmosphere.Color = defaultLighting.atmosphere
		weatherBrightness = defaultLighting.brightness
		rain.Enabled = false
	end
	Lighting.Brightness = weatherBrightness
end

-- شريط فوق الشاشة يبين الطقس والوقت الباقي
local weatherBarText = nil
local function updateWeatherBar(player)
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return end
	local screen = playerGui:FindFirstChild("WeatherBar")
	if not screen then
		screen = Instance.new("ScreenGui")
		screen.Name = "WeatherBar"
		screen.ResetOnSpawn = false
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, 10)
		label.Size = UDim2.new(0.5, 0, 0, 34)
		label.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
		label.BackgroundTransparency = 0.25
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		Instance.new("UICorner").Parent = label
		label.Parent = screen
		screen.Parent = playerGui
	end
	screen.Label.Visible = weatherBarText ~= nil
	screen.Label.Text = weatherBarText or ""
end

local function lightningStrike(position)
	local bolt = part({ Name = "Lightning", Size = Vector3.new(0.8, 80, 0.8), CFrame = CFrame.new(position + Vector3.new(0, 40, 0)), Color = Color3.fromRGB(200, 240, 255), Material = Enum.Material.Neon, CanCollide = false, CanTouch = false, CanQuery = false })
	Debris:AddItem(bolt, 0.25)
	Lighting.Brightness = 6
	task.delay(0.12, function()
		Lighting.Brightness = weatherBrightness
	end)
end

local function strikeFarm()
	-- نجمع كل الزرع اللي ما فيه طفرة
	local candidates = {}
	for _, plot in ipairs(plots) do
		local session = plot.owner and sessions[plot.owner]
		if session then
			for t = 1, #plot.tiles do
				local data = session.farm["t" .. t]
				if data and seedById[data.seed] and not data.mutation then
					table.insert(candidates, { plot = plot, t = t, data = data })
				end
			end
		end
	end
	if #candidates > 0 and farmRng:NextNumber() < LIGHTNING_CROP_CHANCE then
		local hit = candidates[farmRng:NextInteger(1, #candidates)]
		hit.data.mutation = "Electric"
		lightningStrike(hit.plot.tiles[hit.t].Position)
		renderTile(hit.plot, hit.t)
		notify(hit.plot.owner, "⚡ Lightning hit your " .. seedById[hit.data.seed].name .. "! It's ELECTRIC now (x5)", MUTATIONS.Electric.color)
	else
		lightningStrike(Vector3.new(farmRng:NextNumber(85, 205), 0, farmRng:NextNumber(-90, 10)))
	end
end

task.spawn(function()
	while true do
		task.wait(WEATHER_EVERY - 30)
		local id = WEATHER_ORDER[farmRng:NextInteger(1, #WEATHER_ORDER)]
		local weather = WEATHERS[id]
		local startsAt = os.time() + 30
		notifyAll("⚠️ " .. weather.title .. " in 30 seconds! " .. weather.hint, GOLD)
		while os.time() < startsAt do
			weatherBarText = weather.title .. " coming in " .. formatTime(startsAt - os.time())
			task.wait(1)
		end

		currentWeather = id
		applyWeather(id)
		notifyAll(weather.title .. " has started! " .. weather.hint, GOLD)
		local endsAt = os.time() + WEATHER_LENGTH
		local nextStrike = os.time() + LIGHTNING_EVERY
		while os.time() < endsAt do
			weatherBarText = weather.title .. " " .. formatTime(endsAt - os.time()) .. " - " .. weather.hint
			if id == "Thunderstorm" and os.time() >= nextStrike then
				nextStrike = os.time() + LIGHTNING_EVERY
				strikeFarm()
			end
			task.wait(1)
		end

		currentWeather = nil
		weatherBarText = nil
		applyWeather(nil)
		notifyAll("The " .. weather.title .. " is over. Next weather soon!", GREEN)
	end
end)

-- الزرع يكبر كل ثانية + عداد المتجر + شريط الطقس
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			updateWeatherBar(player)
		end
		for _, plot in ipairs(plots) do
			local session = plot.owner and sessions[plot.owner]
			if session then
				for t = 1, #plot.tiles do
					local data = session.farm["t" .. t]
					if data and seedById[data.seed] then
						local stage, remaining = growthStage(data)
						if currentWeather == "GoldenRain" and stage < 3 then
							-- ثانية زيادة نمو = سرعة الضعف
							data.at -= 1
							stage, remaining = growthStage(data)
						end
						local previous = plot.stages[t]
						if stage ~= previous then
							if stage == 3 and previous and previous < 3 and currentWeather == "GoldenRain" and not data.mutation then
								data.mutation = "Golden"
								notify(plot.owner, "✨ Your " .. seedById[data.seed].name .. " finished in the Golden Rain: GOLDEN (x3)!", GOLD)
							end
							renderTile(plot, t)
						elseif plot.labels[t] then
							plot.labels[t].Text = growingText(data, remaining)
						end
					end
				end
			end
		end
		if os.time() >= nextRestock then
			restock()
		else
			updateShop()
		end
	end
end)

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
	local rarityValue = stat("Rarity")
	leaderstats.Parent = player

	local session = {
		owned = {}, foundSecret = false, lastDay = 0, streak = 0, loaded = false,
		seeds = { Carrot = STARTER_SEEDS }, farm = {}, selectedSeed = "Carrot", bestTier = 1,
	}
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
		-- += عشان ما تضيع الكوينز اللي جمعها وهو ينطر التحميل
		coinsValue.Value += data.coins or 0
		winsValue.Value += data.wins or 0
		stageValue.Value = math.clamp(data.stage or 0, 0, STAGES)
		session.owned = data.owned or {}
		session.foundSecret = data.foundSecret or false
		session.lastDay = data.lastDay or 0
		session.streak = data.streak or 0
		session.seeds = data.seeds or session.seeds
		session.farm = data.farm or {}
		session.selectedSeed = data.selectedSeed
		session.bestTier = data.bestTier or 1
		rarityValue.Value = data.rarity or 0
	end
	if not session.selectedSeed or (session.seeds[session.selectedSeed] or 0) <= 0 then
		session.selectedSeed = nextSeed(session, nil)
	end
	if player.Character then
		task.spawn(placeCharacter, player.Character)
	end
	assignPlot(player)

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
	releasePlot(player)
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

-- لف الكوينز + جمعها لما اللاعب يقرب منها
task.spawn(function()
	local angle = 0
	while true do
		angle += 0.15
		local collectors = {}
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 and player:FindFirstChild("leaderstats") then
				table.insert(collectors, { player = player, position = root.Position })
			end
		end
		for index = #coins, 1, -1 do
			local entry = coins[index]
			local coin = entry.part
			if not coin.Parent then
				table.remove(coins, index)
			elseif entry.active then
				coin.CFrame = CFrame.new(coin.Position) * CFrame.Angles(0, angle, 0)
				for _, collector in ipairs(collectors) do
					if (collector.position - coin.Position).Magnitude < COIN_PICKUP_RANGE then
						collectCoin(entry, collector.player)
						break
					end
				end
			end
		end
		task.wait(0.05)
	end
end)

print("✅ Map generated: " .. STAGES .. " stages, finish at Z = " .. math.floor(edge))
