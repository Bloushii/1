--[[
	DrawGame - لعبة رسم: كل جولة كل لاعب يرسم لاعب ثاني، وبعدين الرسومات تنعرض واللاعبين يعطون إعجابات

	  • ساحة رسم بجو غروب وأشجار ساكورا وأقلام عملاقة
	  • جولات: استراحة ← رسم (3 دقايق) ← معرض وتصويت ❤ ← النتائج
	  • الرسمة اللي انرسمت لك تطلع فوق راسك
	  • إعجابات وكوينز محفوظة، ولوحتين: أكثر إعجابات وأكثر وقت لعب
	  • تمثال لأكثر لاعب عنده إعجابات

	طريقة الاستخدام:
	  هذا السكربت ← ServerScriptService (Script)
	  DrawClient ← StarterPlayer ← StarterPlayerScripts (LocalScript)
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Terrain = workspace.Terrain

-- ===== إعدادات تقدر تغيرها =====
local INTERMISSION = 15     -- الاستراحة بين الجولات (ثواني)
local DRAW_TIME = 180       -- وقت الرسم
local SHOWCASE_TIME = 45    -- وقت المعرض والتصويت
local RESULTS_TIME = 8      -- وقت إعلان أحلى رسمة

local SUBMIT_COINS = 10     -- كوينز لكل رسمة يسلمها
local LIKE_COINS = 5        -- كوينز لكل إعجاب ياخذه
local BEST_COINS = 50       -- كوينز لأحلى رسمة بالجولة

local MAX_POINTS = 1500     -- أكثر عدد نقاط بالرسمة (لازم يطابق DrawClient)
local MAX_STROKES = 400
local EASEL_COUNT = 10
local PLAZA_TOP = 1.1       -- ارتفاع أرضية الساحة

local GOLD = Color3.fromRGB(255, 210, 60)
local GREEN = Color3.fromRGB(120, 255, 140)
local PINK = Color3.fromRGB(255, 140, 190)
local RED = Color3.fromRGB(255, 110, 110)

-- ===== تنظيف القالب =====
for _, child in ipairs(workspace:GetChildren()) do
	if child.Name == "Baseplate" or child:IsA("SpawnLocation") then
		child:Destroy()
	end
end

local map = Instance.new("Folder")
map.Name = "ArtPark"
map.Parent = workspace

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

local function billboard(adornee, width, height, offsetY)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(width, 0, height, 0)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = 100
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	gui.Adornee = adornee
	gui.Parent = adornee
	return label
end

-- رسالة تطلع للاعب فوق الشاشة
local function notify(player, text, color)
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return end
	local screen = playerGui:FindFirstChild("Notify")
	if not screen then
		screen = Instance.new("ScreenGui")
		screen.Name = "Notify"
		screen.ResetOnSpawn = false
		screen.DisplayOrder = 20
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.fromScale(0.5, 0.14)
		label.Size = UDim2.fromScale(0.5, 0.06)
		label.BackgroundColor3 = Color3.fromRGB(45, 28, 60)
		label.BackgroundTransparency = 0.15
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

local function notifyAll(text, color)
	for _, player in ipairs(Players:GetPlayers()) do
		notify(player, text, color)
	end
end

-- ===== الجو: غروب وساكورا =====
Lighting.ClockTime = 17.7
Lighting.Brightness = 2.2
Lighting.OutdoorAmbient = Color3.fromRGB(150, 110, 130)
local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = 0.32
atmosphere.Color = Color3.fromRGB(255, 180, 150)
atmosphere.Decay = Color3.fromRGB(180, 110, 140)
atmosphere.Glare = 0.3
atmosphere.Haze = 1.5
atmosphere.Parent = Lighting
local colorCorrection = Instance.new("ColorCorrectionEffect")
colorCorrection.Saturation = 0.15
colorCorrection.TintColor = Color3.fromRGB(255, 240, 235)
colorCorrection.Parent = Lighting

Terrain:FillBlock(CFrame.new(0, -8, 0), Vector3.new(500, 16, 500), Enum.Material.Grass)

-- ===== الساحة =====
local function disc(radius, topY, color, material)
	return part({
		Name = "Plaza", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, radius * 2, radius * 2),
		CFrame = CFrame.new(0, topY - 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color, Material = material or Enum.Material.SmoothPlastic,
	})
end
disc(48, 0.9, Color3.fromRGB(240, 120, 110), Enum.Material.Brick)
disc(45, 1.0, Color3.fromRGB(250, 232, 210), Enum.Material.Concrete)
disc(12, PLAZA_TOP, Color3.fromRGB(190, 160, 240))

local spawn = part({ Name = "Spawn", Size = Vector3.new(10, 1, 10), CFrame = CFrame.new(0, PLAZA_TOP - 0.5, 0), Transparency = 1, CanCollide = false }, "SpawnLocation")
spawn.Duration = 0

-- ===== أقلام عملاقة =====
local pencilColors = {
	Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 225, 70), Color3.fromRGB(100, 210, 120),
	Color3.fromRGB(80, 170, 255), Color3.fromRGB(160, 110, 255), Color3.fromRGB(255, 120, 200), Color3.fromRGB(70, 200, 200),
}
for index, color in ipairs(pencilColors) do
	local angle = math.rad(index * 45 + 10)
	local base = CFrame.new(math.cos(angle) * 56, 0, math.sin(angle) * 56) * CFrame.Angles(0, angle, math.rad(7))
	local function segment(y, length, diameter, segColor, material)
		part({ Name = "Pencil", Shape = Enum.PartType.Cylinder, Size = Vector3.new(length, diameter, diameter), CFrame = base * CFrame.new(0, y + length / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = segColor, Material = material or Enum.Material.SmoothPlastic })
	end
	segment(0, 1.5, 3.2, Color3.fromRGB(255, 170, 190))
	segment(1.5, 14, 3, color)
	segment(15.5, 1.6, 2.2, Color3.fromRGB(230, 190, 140), Enum.Material.Wood)
	segment(17.1, 0.9, 0.9, color)
end

-- ===== أشجار ساكورا =====
local rng = Random.new(77)
local blossom = { Color3.fromRGB(255, 170, 200), Color3.fromRGB(255, 195, 220), Color3.fromRGB(250, 150, 190) }
for _ = 1, 26 do
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = rng:NextNumber(64, 130)
	local pos = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	local height = rng:NextNumber(9, 14)
	part({ Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, 2, 2), CFrame = CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(110, 70, 60), Material = Enum.Material.Wood })
	for n = 1, 3 do
		local size = rng:NextNumber(7, 10)
		local offset = Vector3.new(rng:NextNumber(-2.5, 2.5), height + rng:NextNumber(0, 2), rng:NextNumber(-2.5, 2.5))
		part({ Name = "Blossom", Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), CFrame = CFrame.new(pos + offset), Color = blossom[n], Material = Enum.Material.Grass })
	end
end

-- ===== الحوامل (المعرض) =====
local easels = {}
local function makeEasel(angle)
	local pos = Vector3.new(math.cos(angle) * 30, PLAZA_TOP, math.sin(angle) * 30)
	local base = CFrame.lookAt(pos, Vector3.new(0, PLAZA_TOP, 0))
	local wood = Color3.fromRGB(150, 95, 60)
	for _, x in ipairs({ -2.4, 2.4 }) do
		part({ Name = "Leg", Size = Vector3.new(0.4, 9, 0.4), CFrame = base * CFrame.new(x, 4.5, 0.2), Color = wood, Material = Enum.Material.Wood })
	end
	part({ Name = "Leg", Size = Vector3.new(0.4, 9, 0.4), CFrame = base * CFrame.new(0, 4.3, 1.9) * CFrame.Angles(math.rad(-14), 0, 0), Color = wood, Material = Enum.Material.Wood })
	part({ Name = "Ledge", Size = Vector3.new(6.6, 0.3, 0.9), CFrame = base * CFrame.new(0, 2.85, -0.2), Color = wood, Material = Enum.Material.Wood })

	local board = part({ Name = "Canvas", Size = Vector3.new(6, 6, 0.3), CFrame = base * CFrame.new(0, 6, 0) * CFrame.Angles(math.rad(8), 0, 0), Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.SmoothPlastic })
	local data = Instance.new("StringValue")
	data.Name = "Data"
	data.Parent = board
	CollectionService:AddTag(board, "DrawingDisplay")

	local label = billboard(board, 8, 1.6, 4.4)
	label.Text = "🖼️ لوحة فاضية"
	local like = Instance.new("ProximityPrompt")
	like.ActionText = "❤ إعجاب"
	like.ObjectText = "لوحة"
	like.HoldDuration = 0
	like.MaxActivationDistance = 10
	like.RequiresLineOfSight = false
	like.Parent = board

	local easel = { board = board, data = data, label = label, like = like, entry = nil }
	table.insert(easels, easel)
	return easel
end

for index = 1, EASEL_COUNT do
	makeEasel(math.rad(18 + (index - 1) * 360 / EASEL_COUNT))
end

-- ===== لوحات الترتيب والتمثال =====
local function leaderboardBoard(position, title, color)
	local base = CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
	for _, x in ipairs({ -5, 5 }) do
		part({ Name = "Post", Size = Vector3.new(0.6, 12, 0.6), CFrame = base * CFrame.new(x, 6, 0.4), Color = Color3.fromRGB(150, 95, 60), Material = Enum.Material.Wood })
	end
	local board = part({ Name = "Leaderboard", Size = Vector3.new(11, 9, 0.5), CFrame = base * CFrame.new(0, 7.5, 0), Color = color, Material = Enum.Material.SmoothPlastic })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = board
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.fromScale(1, 0.18)
	titleLabel.BackgroundTransparency = 1
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.Text = title
	titleLabel.Parent = gui
	local list = Instance.new("TextLabel")
	list.Position = UDim2.fromScale(0.05, 0.2)
	list.Size = UDim2.fromScale(0.9, 0.76)
	list.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	list.BackgroundTransparency = 0.15
	list.TextScaled = true
	list.Font = Enum.Font.GothamBold
	list.TextColor3 = Color3.fromRGB(60, 40, 70)
	list.Text = "..."
	list.Parent = gui
	Instance.new("UICorner").Parent = list
	return list
end

local likesList = leaderboardBoard(Vector3.new(-16, PLAZA_TOP, 40), "❤ أكثر إعجابات", Color3.fromRGB(240, 90, 140))
local minutesList = leaderboardBoard(Vector3.new(16, PLAZA_TOP, 40), "⏱️ أكثر وقت لعب", Color3.fromRGB(110, 90, 220))

local pedestal = part({ Name = "Pedestal", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 7, 7), CFrame = CFrame.new(0, PLAZA_TOP + 1.5, 44) * CFrame.Angles(0, 0, math.rad(90)), Color = GOLD, Material = Enum.Material.SmoothPlastic })
local statueLabel = billboard(pedestal, 10, 1.5, 10)
statueLabel.Text = "👑 مكان الأفضل"
statueLabel.TextColor3 = GOLD

-- ===== الريموتات وحالة اللعبة =====
local remotes = Instance.new("Folder")
remotes.Name = "DrawRemotes"
remotes.Parent = ReplicatedStorage
local submitRemote = Instance.new("RemoteEvent")
submitRemote.Name = "SubmitDrawing"
submitRemote.Parent = remotes

-- الكلاينت يقرا من هالـ Attributes: Phase, EndsAt, Status, Submitted, Total, Round
local state = Instance.new("Folder")
state.Name = "DrawState"
state.Parent = ReplicatedStorage

-- ===== الحفظ =====
local function getStore(name, ordered)
	local ok, store = pcall(function()
		if ordered then
			return DataStoreService:GetOrderedDataStore(name)
		end
		return DataStoreService:GetDataStore(name)
	end)
	return ok and store or nil
end
local store = getStore("DrawData_v1")
local likesStore = getStore("TopLikes_v1", true)
local minutesStore = getStore("TopMinutes_v1", true)
if not store then
	warn("DataStore not available (publish the game and enable API access). Progress won't be saved.")
end

local sessions = {}

local function saveData(player)
	local session = sessions[player]
	local leaderstats = player:FindFirstChild("leaderstats")
	if not (store and session and session.loaded and leaderstats) then return end
	local key = "u_" .. player.UserId
	local ok, err = pcall(function()
		store:SetAsync(key, { likes = leaderstats.Likes.Value, coins = leaderstats.Coins.Value, minutes = session.minutes })
	end)
	if not ok then
		warn("Failed to save " .. player.Name .. ": " .. tostring(err))
	end
	pcall(function()
		if likesStore then likesStore:SetAsync(key, leaderstats.Likes.Value) end
		if minutesStore then minutesStore:SetAsync(key, session.minutes) end
	end)
end

-- ===== الرسومات =====
local function validHex(value)
	return type(value) == "string" and value:match("^%x%x%x%x%x%x$") and value or nil
end

-- نتأكد إن الرسمة اللي جات من اللاعب سليمة وحجمها معقول
local function sanitize(data)
	if type(data) ~= "table" then return nil end
	local out = { bg = validHex(data.bg) or "ffffff", strokes = {} }
	if type(data.strokes) ~= "table" then return out end
	local total = 0
	for _, stroke in ipairs(data.strokes) do
		if #out.strokes >= MAX_STROKES or total >= MAX_POINTS then break end
		if type(stroke) == "table" and type(stroke.p) == "table" then
			local points = {}
			for i = 1, math.min(#stroke.p, (MAX_POINTS - total) * 2) do
				local value = tonumber(stroke.p[i])
				if not value or value ~= value then break end
				points[i] = math.clamp(math.floor(value * 1000 + 0.5) / 1000, 0, 1)
			end
			if #points % 2 == 1 then
				table.remove(points)
			end
			if #points >= 2 then
				total += #points / 2
				table.insert(out.strokes, {
					c = validHex(stroke.c) or "000000",
					e = stroke.e == true or nil,
					s = math.clamp(tonumber(stroke.s) or 0.02, 0.004, 0.12),
					p = points,
				})
			end
		end
	end
	return out
end

-- ===== الرسمة فوق الراس =====
local headDrawings = {} -- [player] = { json, caption }

local function attachHeadSign(player, character)
	local head = character:WaitForChild("Head", 10)
	if not head then return end
	local sign = Instance.new("Part")
	sign.Name = "HeadSign"
	sign.Size = Vector3.new(3.2, 3.2, 0.15)
	sign.Transparency = 1
	sign.CanCollide = false
	sign.CanTouch = false
	sign.CanQuery = false
	sign.Massless = true
	sign.CFrame = head.CFrame * CFrame.new(0, 3.2, 0)
	sign:SetAttribute("TwoSided", true)
	local data = Instance.new("StringValue")
	data.Name = "Data"
	data.Parent = sign
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = sign
	weld.Parent = sign
	sign.Parent = character
	local current = headDrawings[player]
	if current then
		data.Value = current.json
		sign:SetAttribute("Caption", current.caption)
	end
	CollectionService:AddTag(sign, "DrawingDisplay")
end

local function setHeadDrawing(player, json, caption)
	headDrawings[player] = { json = json, caption = caption }
	local sign = player.Character and player.Character:FindFirstChild("HeadSign")
	if sign then
		sign.Data.Value = json
		sign:SetAttribute("Caption", caption)
	end
end

-- ===== اللاعبين =====
local function onPlayerAdded(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local likes = Instance.new("IntValue")
	likes.Name = "Likes"
	likes.Parent = leaderstats
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = leaderstats
	leaderstats.Parent = player

	local session = { loaded = false, minutes = 0, lastSubmit = 0 }
	sessions[player] = session

	player.CharacterAdded:Connect(function(character)
		attachHeadSign(player, character)
	end)
	if player.Character then
		task.spawn(attachHeadSign, player, player.Character)
	end

	if store then
		local ok, data = pcall(function()
			return store:GetAsync("u_" .. player.UserId)
		end)
		if not player.Parent then return end
		session.loaded = ok
		if ok and data then
			likes.Value += data.likes or 0
			coins.Value += data.coins or 0
			session.minutes = data.minutes or 0
		elseif not ok then
			warn("Failed to load " .. player.Name .. ": " .. tostring(data))
		end
	end
	task.delay(3, notify, player, "🎨 أهلاً! كل جولة بترسم لاعب، والكل يصوّت لأحلى رسمة", PINK)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	sessions[player] = nil
	headDrawings[player] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveData(player)
	end
end)

-- وقت اللعب + حفظ تلقائي
task.spawn(function()
	local minuteCount = 0
	while true do
		task.wait(60)
		minuteCount += 1
		for player, session in pairs(sessions) do
			session.minutes += 1
			if minuteCount % 2 == 0 then
				task.spawn(saveData, player)
			end
		end
	end
end)

-- ===== الجولات =====
local targets = {}      -- [artist] = target
local submissions = {}  -- [artist] = drawing
local phaseEndsAt = 0

local function setPhase(phase, duration, status)
	phaseEndsAt = workspace:GetServerTimeNow() + duration
	state:SetAttribute("Phase", phase)
	state:SetAttribute("Status", status)
	state:SetAttribute("EndsAt", phaseEndsAt)
end

local function waitPhase()
	while workspace:GetServerTimeNow() < phaseEndsAt do
		task.wait(0.25)
	end
end

local function countSubmissions()
	local submitted, total = 0, 0
	for artist in pairs(targets) do
		if artist.Parent then
			total += 1
			if submissions[artist] then
				submitted += 1
			end
		end
	end
	state:SetAttribute("Submitted", submitted)
	state:SetAttribute("Total", total)
	return submitted, total
end

submitRemote.OnServerEvent:Connect(function(player, data)
	local phase = state:GetAttribute("Phase")
	local session = sessions[player]
	if (phase ~= "Drawing" and phase ~= "Collecting") or not targets[player] or not session then return end
	if os.clock() - session.lastSubmit < 1.5 then return end
	session.lastSubmit = os.clock()
	local clean = sanitize(data)
	if not clean or #clean.strokes == 0 then return end
	submissions[player] = clean
	local submitted, total = countSubmissions()
	-- إذا الكل سلّم نختصر الوقت
	if phase == "Drawing" and submitted >= total then
		local shorter = workspace:GetServerTimeNow() + 5
		if shorter < phaseEndsAt then
			phaseEndsAt = shorter
			state:SetAttribute("EndsAt", phaseEndsAt)
			state:SetAttribute("Status", "الكل سلّم! المعرض بيبدأ ✨")
		end
	end
end)

local function updateEaselLabel(easel)
	local entry = easel.entry
	if entry then
		easel.label.Text = "🎨 " .. entry.artistName .. "\n❤ " .. entry.likes
	else
		easel.label.Text = "🖼️ لوحة فاضية"
	end
end

for _, easel in ipairs(easels) do
	easel.like.Triggered:Connect(function(player)
		local entry = easel.entry
		if not entry then
			notify(player, "اللوحة فاضية، انطر المعرض الجاي 🖼️", PINK)
			return
		end
		if entry.artistId == player.UserId then
			notify(player, "ما تقدر تعجب برسمتك 😅", RED)
			return
		end
		if entry.likedBy[player.UserId] then
			notify(player, "عطيتها إعجاب قبل ❤", PINK)
			return
		end
		entry.likedBy[player.UserId] = true
		entry.likes += 1
		updateEaselLabel(easel)
		notify(player, "❤ عطيت " .. entry.artistName .. " إعجاب", PINK)
		local artist = Players:GetPlayerByUserId(entry.artistId)
		if artist and artist:FindFirstChild("leaderstats") then
			artist.leaderstats.Likes.Value += 1
			artist.leaderstats.Coins.Value += LIKE_COINS
			notify(artist, "❤ " .. player.DisplayName .. " عجبته رسمتك! +" .. LIKE_COINS .. " كوينز", PINK)
		end
	end)
end

local function clearEasels()
	for _, easel in ipairs(easels) do
		easel.entry = nil
		easel.data.Value = ""
		easel.board:SetAttribute("Caption", nil)
		easel.like.ObjectText = "لوحة"
		local sparkles = easel.board:FindFirstChildOfClass("Sparkles")
		if sparkles then
			sparkles:Destroy()
		end
		updateEaselLabel(easel)
	end
end

local function shuffle(list)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function runRound()
	local list = shuffle(Players:GetPlayers())
	if #list == 0 then return end

	-- كل لاعب يرسم اللي بعده (بدائرة)، وإذا بروحه يرسم نفسه
	targets, submissions = {}, {}
	for index, artist in ipairs(list) do
		local target = list[index % #list + 1]
		targets[artist] = target
		artist:SetAttribute("DrawTargetName", target.DisplayName)
		artist:SetAttribute("DrawTargetId", target.UserId)
	end
	state:SetAttribute("Round", (state:GetAttribute("Round") or 0) + 1)
	countSubmissions()

	setPhase("Drawing", DRAW_TIME, "ارسم اللي طلع لك! ✏️")
	waitPhase()
	setPhase("Collecting", 3, "نجمع الرسومات... 📥")
	waitPhase()
	for artist in pairs(targets) do
		if artist.Parent then
			artist:SetAttribute("DrawTargetName", nil)
			artist:SetAttribute("DrawTargetId", nil)
		end
	end

	-- المعرض
	clearEasels()
	local entries = {}
	for artist, drawing in pairs(submissions) do
		local target = targets[artist]
		local json = HttpService:JSONEncode(drawing)
		local entry = {
			json = json, likes = 0, likedBy = {},
			artistId = artist.UserId, artistName = artist.DisplayName,
			targetName = target.DisplayName, selfie = artist == target,
		}
		table.insert(entries, entry)
		if artist.Parent then
			artist.leaderstats.Coins.Value += SUBMIT_COINS
			notify(artist, "🎨 رسمتك بالمعرض! +" .. SUBMIT_COINS .. " كوينز", GREEN)
		end
		-- الرسمة تطلع فوق راس اللي انرسم
		if target.Parent then
			setHeadDrawing(target, json, entry.selfie and "🪞 رسم نفسه" or "✏️ " .. artist.DisplayName)
		end
	end
	shuffle(entries)
	for index, entry in ipairs(entries) do
		local easel = easels[index]
		if not easel then break end
		easel.entry = entry
		easel.data.Value = entry.json
		easel.board:SetAttribute("Caption", entry.selfie and ("🪞 " .. entry.targetName) or ("صورة " .. entry.targetName))
		easel.like.ObjectText = entry.artistName
		updateEaselLabel(easel)
	end

	if #entries == 0 then
		setPhase("Results", RESULTS_TIME, "محد رسم هالجولة 😢 الجولة الجاية!")
		waitPhase()
		return
	end

	setPhase("Showcase", SHOWCASE_TIME, "تمشّى بين اللوحات واضغط ❤ على اللي تعجبك")
	notifyAll("🖼️ المعرض بدأ! صوّت لأحلى رسمة ❤", PINK)
	waitPhase()

	-- أحلى رسمة
	local best, bestEasel = nil, nil
	for _, easel in ipairs(easels) do
		local entry = easel.entry
		if entry and entry.likes > 0 and (not best or entry.likes > best.likes) then
			best, bestEasel = entry, easel
		end
	end
	if best then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = GOLD
		sparkles.Parent = bestEasel.board
		local winner = Players:GetPlayerByUserId(best.artistId)
		if winner then
			winner.leaderstats.Coins.Value += BEST_COINS
			notify(winner, "🏆 رسمتك أحلى رسمة بالجولة! +" .. BEST_COINS .. " كوينز", GOLD)
		end
		setPhase("Results", RESULTS_TIME, "🏆 أحلى رسمة: " .. best.artistName .. " (❤ " .. best.likes .. ")")
	else
		setPhase("Results", RESULTS_TIME, "محد عطى إعجابات هالجولة 😅")
	end
	waitPhase()
end

task.spawn(function()
	while true do
		while #Players:GetPlayers() == 0 do
			setPhase("Waiting", 1, "بانتظار لاعبين...")
			task.wait(1)
		end
		setPhase("Intermission", INTERMISSION, "استراحة ☕ الجولة الجاية بتبدأ قريب")
		waitPhase()
		runRound()
	end
end)

-- ===== لوحات الترتيب + التمثال =====
local nameCache = {}
local function nameOf(userId)
	if not nameCache[userId] then
		local ok, name = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		nameCache[userId] = ok and name or "?"
	end
	return nameCache[userId]
end

local function topEntries(orderedStore, fallback)
	local entries = {}
	local ok = orderedStore and pcall(function()
		local page = orderedStore:GetSortedAsync(false, 8):GetCurrentPage()
		for _, item in ipairs(page) do
			local userId = tonumber((item.key:gsub("u_", "")))
			if userId then
				table.insert(entries, { userId = userId, name = nameOf(userId), value = item.value })
			end
		end
	end)
	if not ok then
		-- بدون DataStore: نرتب اللي بالسيرفر بس
		entries = {}
		for _, player in ipairs(Players:GetPlayers()) do
			local value = fallback(player)
			if value then
				table.insert(entries, { userId = player.UserId, name = player.DisplayName, value = value })
			end
		end
		table.sort(entries, function(a, b)
			return a.value > b.value
		end)
	end
	return entries
end

local function formatList(entries, suffix)
	local lines = {}
	for rank = 1, math.min(#entries, 8) do
		local medal = rank == 1 and "🥇" or rank == 2 and "🥈" or rank == 3 and "🥉" or (rank .. ".")
		table.insert(lines, medal .. " " .. entries[rank].name .. "  " .. entries[rank].value .. suffix)
	end
	if #lines == 0 then
		return "محد للحين، كن أول واحد!"
	end
	return table.concat(lines, "\n")
end

local statue, statueUserId = nil, nil
local function updateStatue(entry)
	if not entry or entry.userId == statueUserId then return end
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromUserId(entry.userId)
	end)
	if not ok or not model then return end
	if statue then
		statue:Destroy()
	end
	statue, statueUserId = model, entry.userId
	model.Name = "Statue"
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = true
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	model.Parent = map
	pcall(function()
		model:ScaleTo(1.5)
	end)
	local _, size = model:GetBoundingBox()
	-- يواجه نص الساحة
	model:PivotTo(CFrame.lookAt(Vector3.new(0, PLAZA_TOP + 3 + size.Y / 2, 44), Vector3.new(0, PLAZA_TOP + 3 + size.Y / 2, 0)))
	statueLabel.Text = "👑 " .. entry.name .. " - ❤ " .. entry.value
end

task.spawn(function()
	while true do
		local topLikes = topEntries(likesStore, function(player)
			local leaderstats = player:FindFirstChild("leaderstats")
			return leaderstats and leaderstats.Likes.Value
		end)
		likesList.Text = formatList(topLikes, " ❤")
		minutesList.Text = formatList(topEntries(minutesStore, function(player)
			local session = sessions[player]
			return session and session.minutes
		end), " د")
		if topLikes[1] and topLikes[1].value > 0 then
			updateStatue(topLikes[1])
		end
		task.wait(60)
	end
end)

print("🎨 Draw game ready")
