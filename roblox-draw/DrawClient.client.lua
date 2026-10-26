--[[
	DrawClient - واجهة الرسم + عرض الرسومات على الحوامل وفوق الروس

	طريقة الاستخدام: حطه في StarterPlayer ← StarterPlayerScripts كـ LocalScript
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("DrawRemotes")
local submitRemote = remotes:WaitForChild("SubmitDrawing")
local state = ReplicatedStorage:WaitForChild("DrawState")

-- ===== إعدادات =====
local MAX_POINTS = 1500       -- لازم يطابق السيرفر
local MIN_STEP = 0.008        -- أقل مسافة بين نقطتين بالخط
local RENDER_DISTANCE = 90    -- اللوحات الأبعد من كذا ما تنرسم (عشان الأداء)
local BRUSH_SIZES = { 0.008, 0.018, 0.035, 0.06 }

local PALETTE = {
	"000000", "ffffff", "7f7f7f", "c3c3c3", "ff3b30", "ff9500",
	"ffcc00", "34c759", "00c7be", "007aff", "5856d6", "af52de",
	"ff2d92", "ffd6e0", "a2845e", "5c3a21", "b3e5fc", "c8e6c9",
	-- ألوان بشرة
	"ffe0bd", "f1c27d", "e0ac69", "c68642", "8d5524", "3b2219",
}

-- ألوان الواجهة: بنفسجي غامق + خوخي
local PANEL = Color3.fromRGB(45, 28, 60)
local PANEL_LIGHT = Color3.fromRGB(70, 48, 92)
local ACCENT = Color3.fromRGB(255, 170, 130)
local WHITE = Color3.new(1, 1, 1)

-- ===== أدوات =====
local function make(className, props)
	local obj = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then
			obj[key] = value
		end
	end
	obj.Parent = props.Parent
	return obj
end

local function corner(obj, radius)
	make("UICorner", { CornerRadius = UDim.new(radius or 0.15, 0), Parent = obj })
end

local function label(props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextScaled = true
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or WHITE
	return make("TextLabel", props)
end

local function button(parent, text, color, order, width)
	local b = make("TextButton", {
		Size = UDim2.fromScale(width or 1, 1), BackgroundColor3 = color, Text = text,
		TextScaled = true, Font = Enum.Font.GothamBold, TextColor3 = WHITE,
		LayoutOrder = order or 0, AutoButtonColor = true, Parent = parent,
	})
	corner(b, 0.2)
	make("UIPadding", { PaddingTop = UDim.new(0.12, 0), PaddingBottom = UDim.new(0.12, 0), Parent = b })
	return b
end

-- ===== رسم الخطوط (Frames) =====
local function drawDot(parent, x, y, size, color)
	local dot = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(size, size),
		BackgroundColor3 = color, BorderSizePixel = 0, Parent = parent,
	})
	make("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = dot })
end

local function drawSegment(parent, x1, y1, x2, y2, size, color)
	local dx, dy = x2 - x1, y2 - y1
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2),
		Size = UDim2.fromScale(math.sqrt(dx * dx + dy * dy), size), Rotation = math.deg(math.atan2(dy, dx)),
		BackgroundColor3 = color, BorderSizePixel = 0, Parent = parent,
	})
end

local function renderStroke(parent, stroke, bg)
	local container = make("Frame", { Name = "Stroke", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
	local color = stroke.e and bg or Color3.fromHex(stroke.c or "000000")
	local p = stroke.p
	drawDot(container, p[1], p[2], stroke.s, color)
	for i = 3, #p - 1, 2 do
		drawSegment(container, p[i - 2], p[i - 1], p[i], p[i + 1], stroke.s, color)
		drawDot(container, p[i], p[i + 1], stroke.s, color)
	end
	return container
end

-- ===== عرض الرسومات على الحوامل وفوق الروس =====
local displays = {}

local function removeDisplay(part)
	local entry = displays[part]
	if not entry then return end
	for _, face in ipairs(entry.faces) do
		face.gui:Destroy()
	end
	displays[part] = nil
end

local function setupDisplay(part)
	if displays[part] then return end
	local data = part:WaitForChild("Data", 10)
	if not data or not part.Parent then return end
	local entry = { part = part, data = data, faces = {}, rendered = nil }
	local sides = { Enum.NormalId.Front }
	if part:GetAttribute("TwoSided") then
		table.insert(sides, Enum.NormalId.Back)
	end
	for _, side in ipairs(sides) do
		local gui = make("SurfaceGui", {
			Name = "DrawingDisplay", Adornee = part, Face = side, Enabled = false, ResetOnSpawn = false,
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 50, LightInfluence = 0,
			Parent = playerGui,
		})
		local canvas = make("Frame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundColor3 = WHITE, Parent = gui })
		local ink = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = canvas })
		local caption = label({
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(1, 0.13),
			BackgroundTransparency = 0.25, BackgroundColor3 = PANEL, ZIndex = 2, Text = "", Parent = canvas,
		})
		table.insert(entry.faces, { gui = gui, canvas = canvas, ink = ink, caption = caption })
	end
	displays[part] = entry
end

for _, part in ipairs(CollectionService:GetTagged("DrawingDisplay")) do
	task.spawn(setupDisplay, part)
end
CollectionService:GetInstanceAddedSignal("DrawingDisplay"):Connect(function(part)
	task.spawn(setupDisplay, part)
end)
CollectionService:GetInstanceRemovedSignal("DrawingDisplay"):Connect(removeDisplay)

-- نرسم بس اللوحات القريبة، والبعيدة نمسحها
task.spawn(function()
	while true do
		local camera = workspace.CurrentCamera
		for part, entry in pairs(displays) do
			if not part.Parent then
				removeDisplay(part)
			else
				local value = entry.data.Value
				local near = camera and (part.Position - camera.CFrame.Position).Magnitude < RENDER_DISTANCE
				local want = (near and value ~= "") and value or nil
				if want ~= entry.rendered then
					entry.rendered = want
					local decoded = nil
					if want then
						local ok, result = pcall(HttpService.JSONDecode, HttpService, want)
						decoded = ok and type(result) == "table" and result or nil
					end
					for _, face in ipairs(entry.faces) do
						face.ink:ClearAllChildren()
						face.gui.Enabled = decoded ~= nil
						if decoded then
							pcall(function()
								local bg = Color3.fromHex(decoded.bg or "ffffff")
								face.canvas.BackgroundColor3 = bg
								for _, stroke in ipairs(decoded.strokes or {}) do
									if type(stroke.p) == "table" and #stroke.p >= 2 then
										renderStroke(face.ink, stroke, bg)
									end
								end
							end)
						end
					end
				end
				local caption = part:GetAttribute("Caption") or ""
				for _, face in ipairs(entry.faces) do
					face.caption.Text = caption
					face.caption.Visible = caption ~= ""
				end
			end
		end
		task.wait(0.5)
	end
end)

-- ===== الشريط اللي فوق (الوقت والحالة) =====
local hud = make("ScreenGui", { Name = "DrawHUD", ResetOnSpawn = false, DisplayOrder = 10, Parent = playerGui })
local topBar = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.01), Size = UDim2.fromScale(0.36, 0.11),
	BackgroundColor3 = PANEL, BackgroundTransparency = 0.1, Parent = hud,
})
corner(topBar, 0.25)
make("UIStroke", { Thickness = 3, Color = ACCENT, Parent = topBar })
local timerLabel = label({ Size = UDim2.fromScale(1, 0.58), Text = "0:00", TextColor3 = ACCENT, Font = Enum.Font.GothamBlack, Parent = topBar })
local statusLabel = label({ Position = UDim2.fromScale(0.04, 0.58), Size = UDim2.fromScale(0.92, 0.38), Text = "", Parent = topBar })

local openButton = make("TextButton", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.97), Size = UDim2.fromScale(0.28, 0.09),
	BackgroundColor3 = Color3.fromRGB(240, 110, 150), Text = "✏️ ارجع للرسم", TextScaled = true,
	Font = Enum.Font.GothamBold, TextColor3 = WHITE, Visible = false, Parent = hud,
})
corner(openButton, 0.3)

local toast = label({
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.86), Size = UDim2.fromScale(0.5, 0.06),
	BackgroundTransparency = 0.15, BackgroundColor3 = PANEL, Visible = false, Text = "", Parent = hud,
})
corner(toast, 0.3)
local toastToken = 0
local function flash(text)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.Visible = true
	task.delay(3, function()
		if toastToken == token then
			toast.Visible = false
		end
	end)
end

-- ===== واجهة الرسم =====
local drawGui = make("ScreenGui", { Name = "DrawUI", ResetOnSpawn = false, Enabled = false, DisplayOrder = 5, Parent = playerGui })
-- خلفية تغطي الشاشة عشان الكاميرا ما تتحرك وأنت ترسم
local shade = make("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(20, 10, 30), BackgroundTransparency = 0.35,
	Active = true, Parent = drawGui,
})

local panel = make("Frame", {
	AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.02, 0.56), Size = UDim2.fromScale(0.36, 0.84),
	BackgroundColor3 = PANEL, Parent = shade,
})
corner(panel, 0.05)
make("UIPadding", {
	PaddingTop = UDim.new(0.025, 0), PaddingBottom = UDim.new(0.025, 0),
	PaddingLeft = UDim.new(0.04, 0), PaddingRight = UDim.new(0.04, 0), Parent = panel,
})
make("UIListLayout", { Padding = UDim.new(0.02, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = panel })

-- الهيدر: صورة اللي ترسمه + اسمه
local header = make("Frame", { Size = UDim2.fromScale(1, 0.2), BackgroundTransparency = 1, LayoutOrder = 1, Parent = panel })
local thumb = make("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = PANEL_LIGHT, Image = "", Parent = header })
make("UIAspectRatioConstraint", { AspectRatio = 1, Parent = thumb })
corner(thumb, 0.2)
local title = label({ Position = UDim2.fromScale(0.3, 0), Size = UDim2.fromScale(0.7, 0.6), Text = "ارسم!", TextColor3 = ACCENT, Font = Enum.Font.GothamBlack, Parent = header })
local hint = label({ Position = UDim2.fromScale(0.3, 0.6), Size = UDim2.fromScale(0.7, 0.4), Text = "شوف الصورة وارسمه 👀", Parent = header })

-- الألوان
local paletteFrame = make("Frame", { Size = UDim2.fromScale(1, 0.36), BackgroundTransparency = 1, LayoutOrder = 2, Parent = panel })
make("UIGridLayout", { CellSize = UDim2.fromScale(0.15, 0.22), CellPadding = UDim2.fromScale(0.016, 0.03), SortOrder = Enum.SortOrder.LayoutOrder, Parent = paletteFrame })

local sizeRow = make("Frame", { Size = UDim2.fromScale(1, 0.1), BackgroundTransparency = 1, LayoutOrder = 3, Parent = panel })
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0.025, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sizeRow })

local toolRow = make("Frame", { Size = UDim2.fromScale(1, 0.12), BackgroundTransparency = 1, LayoutOrder = 4, Parent = panel })
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0.025, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = toolRow })

local submitButton = button(panel, "✅ إرسال الرسمة", Color3.fromRGB(80, 200, 120), 5)
submitButton.Size = UDim2.fromScale(1, 0.12)

local closeButton = make("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.99, 0.02), Size = UDim2.fromScale(0.07, 0.1),
	BackgroundColor3 = Color3.fromRGB(230, 80, 90), Text = "✖", TextScaled = true, Font = Enum.Font.GothamBlack,
	TextColor3 = WHITE, Parent = shade,
})
make("UIAspectRatioConstraint", { AspectRatio = 1, Parent = closeButton })
corner(closeButton, 0.3)

-- اللوحة
local canvas = make("Frame", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.97, 0.56), Size = UDim2.fromScale(0.58, 0.84),
	BackgroundColor3 = WHITE, BorderSizePixel = 0, Active = true, ClipsDescendants = true, Parent = shade,
})
make("UIAspectRatioConstraint", {
	AspectRatio = 1, AspectType = Enum.AspectType.FitWithinMaxSize, DominantAxis = Enum.DominantAxis.Height, Parent = canvas,
})
make("UIStroke", { Thickness = 4, Color = ACCENT, Parent = canvas })
local ink = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = canvas })

-- ===== حالة الرسم =====
local colorHex = "000000"
local bgHex = "ffffff"
local brushSize = BRUSH_SIZES[2]
local tool = "pen"
local strokes = {}       -- { data, container }
local totalPoints = 0
local current = nil      -- الخط اللي ينرسم الحين
local lastSubmit = 0

local swatches = {}
local preview
local function selectColor(hex)
	colorHex = hex
	for swatchHex, stroke in pairs(swatches) do
		stroke.Thickness = swatchHex == hex and 3 or 0
	end
	preview.BackgroundColor3 = Color3.fromHex(hex)
end

for index, hex in ipairs(PALETTE) do
	local swatch = make("TextButton", { Text = "", BackgroundColor3 = Color3.fromHex(hex), LayoutOrder = index, AutoButtonColor = true, Parent = paletteFrame })
	corner(swatch, 0.3)
	swatches[hex] = make("UIStroke", { Thickness = 0, Color = ACCENT, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = swatch })
	swatch.Activated:Connect(function()
		selectColor(hex)
		if tool == "eraser" then
			tool = "pen"
		end
	end)
end

preview = make("Frame", { Size = UDim2.fromScale(0.18, 1), BackgroundColor3 = Color3.new(0, 0, 0), LayoutOrder = 0, Parent = sizeRow })
corner(preview, 0.3)
make("UIStroke", { Thickness = 2, Color = WHITE, Parent = preview })

local sizeButtons = {}
local function selectSize(size)
	brushSize = size
	for buttonSize, b in pairs(sizeButtons) do
		b.BackgroundColor3 = buttonSize == size and ACCENT or PANEL_LIGHT
	end
end
for index, size in ipairs(BRUSH_SIZES) do
	local b = button(sizeRow, "", PANEL_LIGHT, index, 0.18)
	local dotSize = 0.25 + index * 0.15
	local dot = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(dotSize, dotSize),
		BackgroundColor3 = WHITE, Parent = b,
	})
	make("UIAspectRatioConstraint", { AspectRatio = 1, Parent = dot })
	corner(dot, 0.5)
	sizeButtons[size] = b
	b.Activated:Connect(function()
		selectSize(size)
	end)
end

local penButton = button(toolRow, "✏️", ACCENT, 1, 0.18)
local eraserButton = button(toolRow, "🧽", PANEL_LIGHT, 2, 0.18)
local fillButton = button(toolRow, "🪣", PANEL_LIGHT, 3, 0.18)
local undoButton = button(toolRow, "↩️", PANEL_LIGHT, 4, 0.18)
local clearButton = button(toolRow, "🗑️", Color3.fromRGB(200, 70, 90), 5, 0.18)

local function selectTool(name)
	tool = name
	penButton.BackgroundColor3 = name == "pen" and ACCENT or PANEL_LIGHT
	eraserButton.BackgroundColor3 = name == "eraser" and ACCENT or PANEL_LIGHT
end

-- الممحاة ترسم بلون الخلفية، فإذا تغيرت الخلفية تتغير معاها
local function setBackground(hex)
	bgHex = hex
	local color = Color3.fromHex(hex)
	canvas.BackgroundColor3 = color
	for _, stroke in ipairs(strokes) do
		if stroke.data.e then
			for _, frame in ipairs(stroke.container:GetChildren()) do
				frame.BackgroundColor3 = color
			end
		end
	end
end

local function finishStroke()
	if not current then return end
	table.insert(strokes, { data = current.data, container = current.container })
	current = nil
end

local function resetCanvas()
	current = nil
	ink:ClearAllChildren()
	strokes = {}
	totalPoints = 0
	setBackground("ffffff")
	selectTool("pen")
	selectColor("000000")
	selectSize(BRUSH_SIZES[2])
end
resetCanvas()

penButton.Activated:Connect(function()
	selectTool("pen")
end)
eraserButton.Activated:Connect(function()
	selectTool("eraser")
end)
fillButton.Activated:Connect(function()
	setBackground(colorHex)
end)
undoButton.Activated:Connect(function()
	finishStroke()
	local last = table.remove(strokes)
	if last then
		totalPoints -= #last.data.p / 2
		last.container:Destroy()
	end
end)
clearButton.Activated:Connect(function()
	current = nil
	ink:ClearAllChildren()
	strokes = {}
	totalPoints = 0
end)

-- ===== الرسم باللمس والماوس =====
local function toCanvas(position)
	local size = canvas.AbsoluteSize
	local rel = Vector2.new(position.X, position.Y) - canvas.AbsolutePosition
	local function round(v)
		return math.floor(math.clamp(v, 0, 1) * 1000 + 0.5) / 1000
	end
	return round(rel.X / size.X), round(rel.Y / size.Y)
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

canvas.InputBegan:Connect(function(input)
	if not drawGui.Enabled or current or not isPress(input) then return end
	if totalPoints >= MAX_POINTS then
		flash("الرسمة امتلت! تراجع ↩️ أو امسح شوي")
		return
	end
	local x, y = toCanvas(input.Position)
	local stroke = { s = brushSize, p = { x, y } }
	local color
	if tool == "eraser" then
		stroke.e = true
		color = Color3.fromHex(bgHex)
	else
		stroke.c = colorHex
		color = Color3.fromHex(colorHex)
	end
	local container = make("Frame", { Name = "Stroke", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = ink })
	drawDot(container, x, y, stroke.s, color)
	totalPoints += 1
	current = { data = stroke, container = container, color = color, x = x, y = y, kind = input.UserInputType }
end)

UserInputService.InputChanged:Connect(function(input)
	if not current or totalPoints >= MAX_POINTS then return end
	local moving = (current.kind == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)
		or (current.kind == Enum.UserInputType.Touch and input.UserInputType == Enum.UserInputType.Touch)
	if not moving then return end
	local x, y = toCanvas(input.Position)
	if math.abs(x - current.x) + math.abs(y - current.y) < MIN_STEP then return end
	drawSegment(current.container, current.x, current.y, x, y, current.data.s, current.color)
	drawDot(current.container, x, y, current.data.s, current.color)
	table.insert(current.data.p, x)
	table.insert(current.data.p, y)
	current.x, current.y = x, y
	totalPoints += 1
end)

UserInputService.InputEnded:Connect(function(input)
	if current and input.UserInputType == current.kind then
		finishStroke()
	end
end)

-- ===== الإرسال =====
local function submit(auto)
	finishStroke()
	if #strokes == 0 then
		if not auto then
			flash("ارسم شي أول! ✏️")
		end
		return
	end
	if not auto and os.clock() - lastSubmit < 2 then return end
	lastSubmit = os.clock()
	local list = {}
	for _, stroke in ipairs(strokes) do
		table.insert(list, stroke.data)
	end
	submitRemote:FireServer({ bg = bgHex, strokes = list })
	if not auto then
		flash("✅ انرسلت! تقدر تعدل وترسل مرة ثانية لين يخلص الوقت")
	end
end
submitButton.Activated:Connect(function()
	submit(false)
end)

-- ===== فتح وسكر الواجهة حسب الجولة =====
local function hasTarget()
	return player:GetAttribute("DrawTargetId") ~= nil
end

local function updateOpenButton()
	openButton.Visible = state:GetAttribute("Phase") == "Drawing" and hasTarget() and not drawGui.Enabled
end

local function loadTarget()
	local targetId = player:GetAttribute("DrawTargetId")
	local targetName = player:GetAttribute("DrawTargetName") or "?"
	if not targetId then return end
	if targetId == player.UserId then
		title.Text = "ارسم نفسك! 🪞"
	else
		title.Text = "ارسم " .. targetName .. "!"
	end
	thumb.Image = ""
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(targetId, Enum.ThumbnailType.AvatarThumbnail, Enum.ThumbnailSize.Size420x420)
		end)
		if ok and player:GetAttribute("DrawTargetId") == targetId then
			thumb.Image = image
		end
	end)
end

local drawingRound = nil
local function refresh()
	local phase = state:GetAttribute("Phase")
	local round = state:GetAttribute("Round")
	if phase == "Drawing" and hasTarget() then
		if drawingRound ~= round then
			-- جولة جديدة: نمسح اللوحة ونفتح الواجهة
			drawingRound = round
			resetCanvas()
			loadTarget()
			drawGui.Enabled = true
		end
	elseif drawGui.Enabled or current then
		drawGui.Enabled = false
		current = nil
	end
	updateOpenButton()
end

local lastPhase = state:GetAttribute("Phase")
state:GetAttributeChangedSignal("Phase"):Connect(function()
	local phase = state:GetAttribute("Phase")
	-- لما يخلص الوقت نرسل آخر نسخة تلقائياً
	if lastPhase == "Drawing" and phase == "Collecting" and hasTarget() then
		submit(true)
	end
	lastPhase = phase
	refresh()
end)
state:GetAttributeChangedSignal("Round"):Connect(refresh)
player:GetAttributeChangedSignal("DrawTargetId"):Connect(refresh)
refresh()

openButton.Activated:Connect(function()
	drawGui.Enabled = true
	updateOpenButton()
end)
closeButton.Activated:Connect(function()
	finishStroke()
	drawGui.Enabled = false
	updateOpenButton()
end)

-- ===== العداد =====
local PHASE_NAMES = {
	Waiting = "⏳",
	Intermission = "☕ استراحة",
	Drawing = "✏️ وقت الرسم",
	Collecting = "📥",
	Showcase = "🖼️ المعرض",
	Results = "🏆 النتائج",
}

task.spawn(function()
	while true do
		local phase = state:GetAttribute("Phase")
		local remaining = math.max(0, math.ceil((state:GetAttribute("EndsAt") or 0) - workspace:GetServerTimeNow()))
		timerLabel.Text = (PHASE_NAMES[phase] or "") .. "  " .. string.format("%d:%02d", remaining // 60, remaining % 60)
		timerLabel.TextColor3 = (phase == "Drawing" and remaining <= 30) and Color3.fromRGB(255, 90, 90) or ACCENT
		local status = state:GetAttribute("Status") or ""
		if phase == "Drawing" then
			status = status .. "  (" .. (state:GetAttribute("Submitted") or 0) .. "/" .. (state:GetAttribute("Total") or 0) .. " سلّموا)"
			if not hasTarget() then
				status = "دخلت بنص الجولة، انطر الجولة الجاية 🙂"
			end
		end
		statusLabel.Text = status
		task.wait(0.2)
	end
end)
