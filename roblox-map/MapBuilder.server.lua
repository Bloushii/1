--[[
	MapBuilder - يبني خريطة كاملة تلقائياً:
	  • أرض عشب + بحيرة ماء حقيقية (Terrain)
	  • منطقة سبون مع لوحة ترحيب
	  • قرية صغيرة (بيوت + شوارع + أشجار)
	  • أوبي (Obby) فوق اللافا: 4 مراحل + نقاط حفظ + خط النهاية
	  • لوحة نقاط (Stage) لكل لاعب

	طريقة الاستخدام: حط هذا السكربت داخل ServerScriptService كـ Script (مو LocalScript)
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Terrain = workspace.Terrain

-- ===== إعدادات تقدر تغيرها =====
local STAGES = 4            -- عدد مراحل الأوبي
local PLATS_PER_STAGE = 6   -- عدد المنصات بكل مرحلة
local SEED = 2026           -- غيّر الرقم عشان يطلع لك أوبي مختلف

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
sign(spawn, "Welcome! Obby is that way →", Color3.fromRGB(255, 255, 120))

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
	local inTown = math.abs(x) < 75 and z > -110 and z < 10
	local inObby = math.abs(x) < 35 and z > 30
	local inLake = math.abs(x + 110) < 45 and math.abs(z + 100) < 45
	local nearSpawn = math.abs(x) < 15 and math.abs(z) < 15
	if not (inTown or inObby or inLake or nearSpawn) then
		tree(Vector3.new(x, 0, z))
		planted += 1
	end
end

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
sign(startPad, "OBBY START", Color3.fromRGB(120, 255, 120))
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
	sign(cp, "Checkpoint " .. stage, Color3.fromRGB(120, 255, 120))

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
			part({ Name = "Platform", Size = size, CFrame = nextPlatform(size, gap, rise), Color = color, Material = Enum.Material.SmoothPlastic })
		end
	end
end

local finishSize = Vector3.new(16, 1, 16)
local finish = part({ Name = "Finish", Size = finishSize, CFrame = nextPlatform(finishSize, 5, 0), Color = Color3.fromRGB(255, 200, 0), Material = Enum.Material.Neon })
finish:SetAttribute("Stage", STAGES + 1)
checkpoints[STAGES + 1] = finish
sign(finish, "🏆 FINISH 🏆", Color3.fromRGB(255, 220, 60))

-- أرضية اللافا تحت الأوبي كله
local lavaLength = edge - lavaStart + 10
table.insert(killParts, part({ Name = "Lava", Size = Vector3.new(50, 1, lavaLength), CFrame = CFrame.new(0, 0.5, lavaStart + lavaLength / 2), Color = Color3.fromRGB(255, 80, 0), Material = Enum.Material.Neon }))

-- ===== منطق اللعبة =====
for _, kill in ipairs(killParts) do
	kill.Touched:Connect(function(hit)
		local _, humanoid = getPlayer(hit)
		if humanoid then
			humanoid.Health = 0
		end
	end)
end

local function onPlayerAdded(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local stageValue = Instance.new("IntValue")
	stageValue.Name = "Stage"
	stageValue.Parent = leaderstats
	leaderstats.Parent = player

	-- لما يموت يرجع لآخر نقطة حفظ وصلها
	player.CharacterAdded:Connect(function(character)
		local cp = checkpoints[stageValue.Value]
		if stageValue.Value > 0 and cp then
			character:WaitForChild("HumanoidRootPart")
			task.wait(0.1)
			character:PivotTo(cp.CFrame * CFrame.new(0, 4, 0))
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

for stage = 1, STAGES + 1 do
	checkpoints[stage].Touched:Connect(function(hit)
		local player, humanoid = getPlayer(hit)
		if not player then return end
		local stageValue = player.leaderstats.Stage
		-- لازم يمشي بالترتيب، ما يقدر يقفز مراحل
		if stageValue.Value == stage - 1 then
			stageValue.Value = stage
			if stage == STAGES + 1 then
				local sparkles = Instance.new("Sparkles")
				sparkles.Parent = humanoid.Parent:FindFirstChild("HumanoidRootPart")
			end
		end
	end)
end

print("✅ Map generated: " .. STAGES .. " stages, finish at Z = " .. math.floor(edge))
