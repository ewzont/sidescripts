--[[
	Vertex UI
	A compact, one-file Roblox UI library.

	- BuilderSans typography (heavy, readable)
	- Steel-blue accent, near-black surfaces, hairline strokes
	- Lucide icons (loaded at runtime, with graceful text fallbacks)
	- Heartbeat lerp smoothing (no tween spam)

	Quick start:
		local Vertex = loadstring(game:HttpGet("YOUR_RAW_URL"))()
		local Window = Vertex:CreateWindow({ Title = "Vertex", Subtitle = "Dashboard" })
		local Main = Window:AddTab({ Name = "Main", Icon = "layout-dashboard" })
		local General = Main:AddSection({ Name = "General" })

		General:AddToggle({
			Name = "Enabled",
			Default = false,
			Callback = function(value) print(value) end,
		})
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local Vertex = {
	Version = "0.4.0",
	Flags = {},
	Windows = {},
	Connections = {},
}

--=====================================================================
-- Design tokens
--=====================================================================

Vertex.Theme = {
	Background = Color3.fromRGB(5, 5, 5),
	Surface = Color3.fromRGB(23, 23, 23),
	SurfaceRaised = Color3.fromRGB(31, 31, 31),
	SurfaceHover = Color3.fromRGB(43, 43, 43),
	Text = Color3.fromRGB(244, 244, 244),
	TextMuted = Color3.fromRGB(170, 170, 170),
	TextDim = Color3.fromRGB(110, 110, 110),
	Accent = Color3.fromRGB(115, 147, 179), -- #7393B3
	AccentHover = Color3.fromRGB(140, 168, 196),
	AccentText = Color3.fromRGB(183, 201, 219),
	Danger = Color3.fromRGB(239, 68, 68),
	Knob = Color3.fromRGB(245, 245, 245),
}

-- Hairline strokes: white at low opacity. Kept slightly thick + visible so
-- Roblox doesn't render 1px strokes unevenly.
local STROKE_COLOR = Color3.fromRGB(255, 255, 255)
local STROKE_SOFT = 0.84
local STROKE_STRONG = 0.72
local STROKE_THICKNESS = 1.6

-- One radius scale for the whole library.
local RADIUS = {
	Window = 14,
	Card = 10,
	Control = 8,
	Inner = 6,
	Pill = 999,
}

local TEXT = {
	Title = 18,
	Section = 14,
	Value = 15,
	Label = 15,
	Body = 14,
	Small = 13,
	Micro = 11,
}

local SPACING = {
	Window = 16,
	Section = 14,
	Gap = 10,
	ControlH = 46,
	TopBar = 50,
	SideW = 178,
}

--=====================================================================
-- Low-level helpers
--=====================================================================

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(Vertex.Connections, connection)
	return connection
end

local function create(className, properties, parent)
	local instance = Instance.new(className)
	for property, value in pairs(properties or {}) do
		instance[property] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function addCorner(instance, radius)
	return create("UICorner", {
		CornerRadius = UDim.new(0, radius or RADIUS.Inner),
	}, instance)
end

local function addStroke(instance, transparency, color, thickness)
	return create("UIStroke", {
		Color = color or STROKE_COLOR,
		Transparency = transparency or STROKE_SOFT,
		Thickness = thickness or STROKE_THICKNESS,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, instance)
end

-- Squares off an interior edge of a rounded panel so its corner radius only
-- shows where we want it (used to round only the window-facing corners).
local function cornerFill(parent, anchor, position, size, zIndex)
	return create("Frame", {
		Name = "CornerFill",
		BackgroundColor3 = Vertex.Theme.Surface,
		BorderSizePixel = 0,
		AnchorPoint = anchor,
		Position = position,
		Size = size,
		ZIndex = zIndex or 3,
	}, parent)
end

local function addPadding(instance, top, right, bottom, left)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, top or 0),
		PaddingRight = UDim.new(0, right or 0),
		PaddingBottom = UDim.new(0, bottom or 0),
		PaddingLeft = UDim.new(0, left or 0),
	}, instance)
end

local function safeCall(callback, ...)
	if type(callback) ~= "function" then
		return
	end
	local success, message = pcall(callback, ...)
	if not success then
		warn("[Vertex UI] Callback failed: " .. tostring(message))
	end
end

--=====================================================================
-- Motion: frame-rate independent lerp smoothing on Heartbeat
--=====================================================================

local Motion = {} -- Motion[instance] = { [property] = { target, speed } }

local function lerpValue(a, b, t)
	local kind = typeof(a)
	if kind == "number" then
		return a + (b - a) * t
	elseif kind == "Color3" then
		return a:Lerp(b, t)
	elseif kind == "UDim2" then
		return a:Lerp(b, t)
	elseif kind == "Vector2" then
		return a:Lerp(b, t)
	elseif kind == "UDim" then
		return UDim.new(a.Scale + (b.Scale - a.Scale) * t, a.Offset + (b.Offset - a.Offset) * t)
	end
	return b
end

local function nearEnough(a, b)
	local kind = typeof(a)
	if kind == "number" then
		return math.abs(a - b) < 0.01
	elseif kind == "Color3" then
		return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.008
	elseif kind == "UDim2" then
		return math.abs(a.X.Scale - b.X.Scale) < 0.001
			and math.abs(a.Y.Scale - b.Y.Scale) < 0.001
			and math.abs(a.X.Offset - b.X.Offset) < 0.5
			and math.abs(a.Y.Offset - b.Y.Offset) < 0.5
	elseif kind == "Vector2" then
		return (a - b).Magnitude < 0.5
	elseif kind == "UDim" then
		return math.abs(a.Scale - b.Scale) < 0.001 and math.abs(a.Offset - b.Offset) < 0.5
	end
	return true
end

-- Smoothly drive instance[property] toward target using exponential smoothing.
local function motion(instance, property, target, speed)
	local props = Motion[instance]
	if not props then
		props = {}
		Motion[instance] = props
	end
	props[property] = { target = target, speed = speed or 16 }
end

-- Set a value instantly and clear any in-flight smoothing for it.
local function setNow(instance, property, value)
	instance[property] = value
	local props = Motion[instance]
	if props then
		props[property] = nil
	end
end

-- Snapshot every fade-able transparency under `root` (plus root itself) so a
-- whole subtree can be faded out and later restored to its exact look.
local function snapshotAlpha(root)
	local list = { { root, "BackgroundTransparency", root.BackgroundTransparency } }
	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("GuiObject") then
			list[#list + 1] = { inst, "BackgroundTransparency", inst.BackgroundTransparency }
		end
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			list[#list + 1] = { inst, "TextTransparency", inst.TextTransparency }
		end
		if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			list[#list + 1] = { inst, "ImageTransparency", inst.ImageTransparency }
		end
		if inst:IsA("UIStroke") then
			list[#list + 1] = { inst, "Transparency", inst.Transparency }
		end
	end
	return list
end

-- Drive a snapshot toward shown (its captured values) or hidden (fully clear).
local function fadeAlpha(list, shown, speed)
	for _, entry in ipairs(list) do
		motion(entry[1], entry[2], shown and entry[3] or 1, speed)
	end
end

local function setAlpha(list, shown)
	for _, entry in ipairs(list) do
		setNow(entry[1], entry[2], shown and entry[3] or 1)
	end
end

connect(RunService.Heartbeat, function(dt)
	for instance, props in pairs(Motion) do
		if typeof(instance) ~= "Instance" or not instance.Parent then
			Motion[instance] = nil
		else
			for property, entry in pairs(props) do
				local ok, current = pcall(function()
					return instance[property]
				end)
				if not ok then
					props[property] = nil
				else
					local t = 1 - math.exp(-dt * entry.speed)
					local nextValue = lerpValue(current, entry.target, t)
					if nearEnough(nextValue, entry.target) then
						nextValue = entry.target
						props[property] = nil
					end
					instance[property] = nextValue
				end
			end
			if next(props) == nil then
				Motion[instance] = nil
			end
		end
	end
end)

--=====================================================================
-- Fonts: BuilderSans
--=====================================================================

local FONT_FAMILY = "rbxasset://fonts/families/BuilderSans.json"

local function weightedFont(weightEnum)
	local success, font = pcall(Font.new, FONT_FAMILY, weightEnum, Enum.FontStyle.Normal)
	if success and font then
		return font
	end
	return Font.fromEnum(Enum.Font.BuilderSans)
end

Vertex.Fonts = {
	Regular = weightedFont(Enum.FontWeight.Regular),
	Medium = weightedFont(Enum.FontWeight.Medium),
	SemiBold = weightedFont(Enum.FontWeight.SemiBold),
	Bold = weightedFont(Enum.FontWeight.Bold),
}
Vertex.Font = Vertex.Fonts.SemiBold

local function textProps(size, color, font)
	return {
		BackgroundTransparency = 1,
		FontFace = font or Vertex.Fonts.SemiBold,
		TextColor3 = color or Vertex.Theme.Text,
		TextSize = size or TEXT.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}
end

local function merge(base, extra)
	local result = {}
	for key, value in pairs(base) do
		result[key] = value
	end
	for key, value in pairs(extra or {}) do
		result[key] = value
	end
	return result
end

--=====================================================================
-- Lucide icons (runtime, with fallback)
--=====================================================================

local IconPack
do
	local ok, pack = pcall(function()
		return loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/Footagesus/Icons/main/Main-v2.lua"))()
	end)
	if ok and type(pack) == "table" then
		pcall(function()
			pack.SetIconsType("lucide")
		end)
		IconPack = pack
	end
end

local function getIcon(name)
	if not name or not IconPack then
		return nil
	end
	local ok, image = pcall(IconPack.GetIcon, name)
	if ok and type(image) == "string" and image ~= "" then
		return image
	end
	return nil
end

-- Creates a Lucide ImageLabel when available, else a text-glyph fallback.
local function makeGlyph(parent, iconName, fallback, size, color)
	local image = getIcon(iconName)
	if image then
		return create("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Image = image,
			ImageColor3 = color or Vertex.Theme.Text,
			Size = UDim2.fromOffset(size or 16, size or 16),
			ZIndex = 4,
		}, parent)
	end
	return create(
		"TextLabel",
		merge(textProps(size or 16, color or Vertex.Theme.Text, Vertex.Fonts.Bold), {
			Name = "Icon",
			Text = fallback or "?",
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(size or 16, size or 16),
			ZIndex = 4,
		}),
		parent
	)
end

-- Recolor a glyph regardless of whether it is an image or a text fallback.
local function paintGlyph(glyph, color, speed)
	if glyph:IsA("ImageLabel") then
		motion(glyph, "ImageColor3", color, speed or 18)
	else
		motion(glyph, "TextColor3", color, speed or 18)
	end
end

--=====================================================================
-- Behaviour helpers
--=====================================================================

local function getGuiParent()
	if type(gethui) == "function" then
		local success, result = pcall(gethui)
		if success and result then
			return result
		end
	end
	local player = Players.LocalPlayer
	return (player and player:FindFirstChildOfClass("PlayerGui")) or CoreGui
end

local function hoverFill(button, normalColor, hoverColor, visual)
	visual = visual or button
	button.AutoButtonColor = false
	connect(button.MouseEnter, function()
		motion(visual, "BackgroundColor3", hoverColor, 20)
	end)
	connect(button.MouseLeave, function()
		motion(visual, "BackgroundColor3", normalColor, 20)
	end)
end

-- Robust dragging: drag from anywhere on the given handle.
local function makeDraggable(handle, target)
	local dragging = false
	local dragInput
	local dragStart
	local startPosition

	connect(handle.InputBegan, function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			dragStart = input.Position
			startPosition = target.Position
			dragInput = input

			local changed
			changed = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					changed:Disconnect()
				end
			end)
		end
	end)

	connect(UserInputService.InputChanged, function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragInput = input
		end
	end)

	connect(UserInputService.InputChanged, function(input)
		if dragging and input == dragInput and dragStart then
			local delta = input.Position - dragStart
			target.Position = UDim2.new(
				startPosition.X.Scale,
				startPosition.X.Offset + delta.X,
				startPosition.Y.Scale,
				startPosition.Y.Offset + delta.Y
			)
		end
	end)
end

-- A single, consistent control-row shell used by every component.
local function makeControl(section, height)
	local row = create("Frame", {
		Name = "Control",
		BackgroundColor3 = Vertex.Theme.SurfaceRaised,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, height or SPACING.ControlH),
		ClipsDescendants = true,
		ZIndex = 3,
	}, section.Container)
	addCorner(row, RADIUS.Control)
	-- No stroke on control rows: the raised background already separates them,
	-- and stacking a stroke inside the section card looks like boxes-in-boxes.
	return row
end

-- Centered label for single-line controls (toggle, button, keybind, label).
local function inlineLabel(row, name, description)
	local label = create(
		"TextLabel",
		merge(textProps(TEXT.Label, Vertex.Theme.Text, Vertex.Fonts.SemiBold), {
			Name = "Label",
			Text = name or "Control",
			Position = UDim2.fromOffset(14, description and 8 or 0),
			Size = UDim2.new(1, -74, description and 0 or 1, description and 18 or 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 3,
		}),
		row
	)
	if description then
		create(
			"TextLabel",
			merge(textProps(TEXT.Small, Vertex.Theme.TextMuted, Vertex.Fonts.Medium), {
				Name = "Description",
				Text = description,
				Position = UDim2.fromOffset(14, 28),
				Size = UDim2.new(1, -74, 0, 16),
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 3,
			}),
			row
		)
	end
	return label
end

-- Top-aligned label for stacked controls (slider, input, dropdown).
local function stackLabel(row, name)
	return create(
		"TextLabel",
		merge(textProps(TEXT.Label, Vertex.Theme.Text, Vertex.Fonts.SemiBold), {
			Name = "Label",
			Text = name or "Control",
			Position = UDim2.fromOffset(14, 10),
			Size = UDim2.new(1, -28, 0, 18),
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 3,
		}),
		row
	)
end

--=====================================================================
-- Public: theming
--=====================================================================

function Vertex:SetTheme(overrides)
	for key, value in pairs(overrides or {}) do
		if self.Theme[key] ~= nil and typeof(value) == "Color3" then
			self.Theme[key] = value
		end
	end
end

--=====================================================================
-- Public: windows
--=====================================================================

function Vertex:CreateWindow(options)
	options = options or {}

	local screenGui = create("ScreenGui", {
		Name = "VertexUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = options.DisplayOrder or 50,
	}, getGuiParent())

	if syn and type(syn.protect_gui) == "function" then
		pcall(syn.protect_gui, screenGui)
	end

	local main = create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = options.Size or UDim2.fromOffset(640, 460),
		BackgroundColor3 = Vertex.Theme.Background,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		ZIndex = 2,
	}, screenGui)
	addCorner(main, RADIUS.Window)

	local uiScale = create("UIScale", { Scale = 1 }, main)

	----------------------------------------------------------------
	-- Top bar (title + minimise, full-width drag handle)
	----------------------------------------------------------------
	local topBar = create("Frame", {
		Name = "TopBar",
		BackgroundColor3 = Vertex.Theme.Surface,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, SPACING.TopBar),
		Active = true,
		ZIndex = 4,
	}, main)
	-- Round the top corners to match the window; square off the bottom edge.
	addCorner(topBar, RADIUS.Window)
	cornerFill(topBar, Vector2.new(0, 1), UDim2.new(0, 0, 1, 0), UDim2.new(1, 0, 0, RADIUS.Window), 4)

	create("Frame", {
		Name = "TopDivider",
		BackgroundColor3 = STROKE_COLOR,
		BackgroundTransparency = STROKE_SOFT,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		ZIndex = 5,
	}, topBar)

	local brand = create("Frame", {
		Name = "BrandMark",
		BackgroundColor3 = Vertex.Theme.Accent,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(16, 13),
		Size = UDim2.fromOffset(4, SPACING.TopBar - 26),
		ZIndex = 5,
	}, topBar)
	addCorner(brand, RADIUS.Pill)

	create(
		"TextLabel",
		merge(textProps(TEXT.Title, Vertex.Theme.Text, Vertex.Fonts.Bold), {
			Name = "Title",
			Text = options.Title or "Vertex",
			Position = UDim2.fromOffset(30, options.Subtitle and 8 or 0),
			Size = UDim2.new(0, 320, options.Subtitle and 0 or 1, options.Subtitle and 22 or 0),
			ZIndex = 5,
		}),
		topBar
	)

	if options.Subtitle then
		create(
			"TextLabel",
			merge(textProps(TEXT.Small, Vertex.Theme.TextMuted, Vertex.Fonts.Medium), {
				Name = "Subtitle",
				Text = options.Subtitle,
				Position = UDim2.fromOffset(30, 28),
				Size = UDim2.new(0, 320, 0, 16),
				ZIndex = 5,
			}),
			topBar
		)
	end

	local minimiseButton = create("TextButton", {
		Name = "Minimise",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = Vertex.Theme.SurfaceRaised,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 5,
	}, topBar)
	addCorner(minimiseButton, RADIUS.Inner)
	local minimiseIcon = makeGlyph(minimiseButton, "x", "✕", 18, Vertex.Theme.TextMuted)
	minimiseIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	minimiseIcon.Position = UDim2.fromScale(0.5, 0.5)

	----------------------------------------------------------------
	-- Sidebar + content (parented straight to main so their window-facing
	-- corners aren't squared by a clipping parent)
	----------------------------------------------------------------
	local sidebar = create("Frame", {
		Name = "Sidebar",
		BackgroundColor3 = Vertex.Theme.Surface,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, SPACING.TopBar),
		Size = UDim2.new(0, SPACING.SideW, 1, -SPACING.TopBar),
		ZIndex = 3,
	}, main)
	-- Round only the bottom-left (window) corner; square the interior edges.
	addCorner(sidebar, RADIUS.Window)
	cornerFill(sidebar, Vector2.new(0, 0), UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, RADIUS.Window), 3)
	cornerFill(sidebar, Vector2.new(1, 0), UDim2.new(1, 0, 0, 0), UDim2.new(0, RADIUS.Window, 1, 0), 3)

	create("Frame", {
		Name = "Divider",
		BackgroundColor3 = STROKE_COLOR,
		BackgroundTransparency = STROKE_SOFT,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -1, 0, 0),
		Size = UDim2.new(0, 1, 1, 0),
		ZIndex = 4,
	}, sidebar)

	local tabList = create("ScrollingFrame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 12),
		Size = UDim2.new(1, -20, 1, -20),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 4,
	}, sidebar)
	create("UIListLayout", {
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tabList)

	local content = create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(SPACING.SideW, SPACING.TopBar),
		Size = UDim2.new(1, -SPACING.SideW, 1, -SPACING.TopBar),
		ClipsDescendants = true,
		ZIndex = 3,
	}, main)

	local window = {
		ScreenGui = screenGui,
		Instance = main,
		TopBar = topBar,
		Sidebar = sidebar,
		TabList = tabList,
		Content = content,
		Tabs = {},
		OpenDropdowns = {},
		CurrentTab = nil,
		Visible = true,
		Minimised = false,
		ExpandedHeight = (options.Size or UDim2.fromOffset(640, 460)).Y.Offset,
		ToggleKey = options.ToggleKey or Enum.KeyCode.RightShift,
	}

	makeDraggable(topBar, main)

	function window:SetVisible(value)
		value = value == true
		if value == self.Visible then
			return
		end
		self.Visible = value

		if value then
			-- Open: drop in from slightly above, scale up and fade every element
			-- back to its captured look.
			screenGui.Enabled = true
			local alpha = self._alpha or snapshotAlpha(main)
			self._alpha = alpha
			local rest = main.Position

			setNow(uiScale, "Scale", 0.9)
			setNow(main, "Position", rest - UDim2.fromOffset(0, 22))
			setAlpha(alpha, false)

			motion(uiScale, "Scale", 1, 13)
			motion(main, "Position", rest, 15)
			fadeAlpha(alpha, true, 14)
		else
			-- Close: snapshot the current look (so re-opening restores it),
			-- then slide down, shrink and fade out before disabling.
			local alpha = snapshotAlpha(main)
			self._alpha = alpha
			local rest = main.Position

			motion(uiScale, "Scale", 0.9, 19)
			motion(main, "Position", rest + UDim2.fromOffset(0, 22), 19)
			fadeAlpha(alpha, false, 20)

			task.delay(0.3, function()
				if not self.Visible then
					screenGui.Enabled = false
					setNow(uiScale, "Scale", 1)
					setNow(main, "Position", rest)
					setAlpha(alpha, true)
				end
			end)
		end
	end

	function window:Toggle()
		self:SetVisible(not self.Visible)
	end

	function window:SetMinimised(state)
		self.Minimised = state == true
		if self.Minimised then
			-- Hide the body immediately (main no longer clips) then collapse.
			sidebar.Visible = false
			content.Visible = false
			motion(main, "Size", UDim2.new(main.Size.X.Scale, main.Size.X.Offset, 0, SPACING.TopBar), 16)
			motion(minimiseIcon, "Rotation", 45, 18)
		else
			motion(main, "Size", UDim2.new(main.Size.X.Scale, main.Size.X.Offset, 0, self.ExpandedHeight), 16)
			motion(minimiseIcon, "Rotation", 0, 18)
			-- Reveal the body once the window has grown back to full height.
			task.delay(0.28, function()
				if not self.Minimised then
					sidebar.Visible = true
					content.Visible = true
				end
			end)
		end
	end

	function window:Minimise()
		self:SetMinimised(not self.Minimised)
	end

	function window:Destroy()
		for index, item in ipairs(Vertex.Windows) do
			if item == self then
				table.remove(Vertex.Windows, index)
				break
			end
		end
		screenGui:Destroy()
	end

	connect(minimiseButton.MouseButton1Click, function()
		window:Minimise()
	end)
	connect(minimiseButton.MouseEnter, function()
		motion(minimiseButton, "BackgroundTransparency", 0, 20)
		paintGlyph(minimiseIcon, Vertex.Theme.Text)
	end)
	connect(minimiseButton.MouseLeave, function()
		motion(minimiseButton, "BackgroundTransparency", 1, 20)
		paintGlyph(minimiseIcon, Vertex.Theme.TextMuted)
	end)

	connect(UserInputService.InputBegan, function(input, processed)
		if not processed and input.KeyCode == window.ToggleKey then
			window:Toggle()
		end
	end)

	-- Entrance animation: reuse the open transition (drop-in + scale + fade).
	window.Visible = false
	window:SetVisible(true)

	function window:AddTab(tabOptions)
		tabOptions = tabOptions or {}
		local tabName = tabOptions.Name or "Tab"

		local tabButton = create("TextButton", {
			Name = tabName,
			Text = "",
			BackgroundColor3 = Vertex.Theme.SurfaceRaised,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 38),
			AutoButtonColor = false,
			ZIndex = 3,
		}, tabList)
		addCorner(tabButton, RADIUS.Control)

		local indicator = create("Frame", {
			Name = "Indicator",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.fromOffset(3, 16),
			BackgroundColor3 = Vertex.Theme.Accent,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, tabButton)
		addCorner(indicator, RADIUS.Pill)

		local textOffset = 20
		local tabIcon
		if tabOptions.Icon and getIcon(tabOptions.Icon) then
			tabIcon = makeGlyph(tabButton, tabOptions.Icon, nil, 17, Vertex.Theme.TextMuted)
			tabIcon.AnchorPoint = Vector2.new(0, 0.5)
			tabIcon.Position = UDim2.new(0, 20, 0.5, 0)
			textOffset = 46
		end

		local tabLabel = create(
			"TextLabel",
			merge(textProps(TEXT.Label, Vertex.Theme.TextMuted, Vertex.Fonts.SemiBold), {
				Text = tabName,
				Position = UDim2.fromOffset(textOffset, 0),
				Size = UDim2.new(1, -textOffset - 10, 1, 0),
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 4,
			}),
			tabButton
		)

		local page = create("ScrollingFrame", {
			Name = tabName,
			Visible = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(SPACING.Window, SPACING.Window),
			Size = UDim2.new(1, -SPACING.Window * 2, 1, -SPACING.Window * 2),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 0,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ZIndex = 3,
		}, content)
		-- Inset content from the ScrollingFrame clip so section corners/strokes
		-- render fully (no chopped-off left edge, no squared top corners).
		addPadding(page, 4, 10, 10, 8)
		create("UIListLayout", {
			Padding = UDim.new(0, SPACING.Gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, page)

		local tab = {
			Name = tabName,
			Button = tabButton,
			Label = tabLabel,
			Icon = tabIcon,
			Indicator = indicator,
			Page = page,
			Sections = {},
			Window = window,
		}

		function tab:Select()
			if window.CurrentTab == self then
				return
			end
			for _, other in ipairs(window.Tabs) do
				local selected = other == self
				if selected then
					-- Slide the page up a touch and fade it in.
					other.Page.Visible = true
					other.Page.Position = UDim2.fromOffset(SPACING.Window, SPACING.Window + 14)
					setNow(other.Page, "CanvasPosition", Vector2.new())
					motion(other.Page, "Position", UDim2.fromOffset(SPACING.Window, SPACING.Window), 16)
				else
					other.Page.Visible = false
				end
				motion(other.Button, "BackgroundTransparency", selected and 0 or 1, 18)
				motion(other.Label, "TextColor3", selected and Vertex.Theme.Text or Vertex.Theme.TextMuted, 18)
				motion(other.Indicator, "BackgroundTransparency", selected and 0 or 1, 18)
				other.Label.FontFace = selected and Vertex.Fonts.Bold or Vertex.Fonts.SemiBold
				if other.Icon then
					paintGlyph(other.Icon, selected and Vertex.Theme.Text or Vertex.Theme.TextMuted)
				end
			end
			window.CurrentTab = self
		end

		connect(tabButton.MouseButton1Click, function()
			tab:Select()
		end)
		connect(tabButton.MouseEnter, function()
			if window.CurrentTab ~= tab then
				motion(tabButton, "BackgroundTransparency", 0.45, 20)
			end
		end)
		connect(tabButton.MouseLeave, function()
			if window.CurrentTab ~= tab then
				motion(tabButton, "BackgroundTransparency", 1, 20)
			end
		end)

		function tab:AddSection(sectionOptions)
			sectionOptions = sectionOptions or {}
			local sectionFrame = create("Frame", {
				Name = sectionOptions.Name or "Section",
				BackgroundColor3 = Vertex.Theme.Surface,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				ZIndex = 3,
			}, page)
			addCorner(sectionFrame, RADIUS.Card)
			addPadding(sectionFrame, SPACING.Section, SPACING.Section, SPACING.Section, SPACING.Section)
			create("UIListLayout", {
				Padding = UDim.new(0, 12),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}, sectionFrame)

			create(
				"TextLabel",
				merge(textProps(TEXT.Section, Vertex.Theme.TextMuted, Vertex.Fonts.Bold), {
					Name = "SectionTitle",
					Text = sectionOptions.Name or "Section",
					Size = UDim2.new(1, 0, 0, 18),
					LayoutOrder = 0,
					ZIndex = 3,
				}),
				sectionFrame
			)

			local sectionContainer = create("Frame", {
				Name = "Container",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 1,
				ZIndex = 3,
			}, sectionFrame)
			create("UIListLayout", {
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}, sectionContainer)

			local section = {
				Name = sectionOptions.Name or "Section",
				Instance = sectionFrame,
				Container = sectionContainer,
				Tab = tab,
			}

			function section:AddLabel(labelOptions)
				if type(labelOptions) == "string" then
					labelOptions = { Text = labelOptions }
				end
				labelOptions = labelOptions or {}
				local row = makeControl(self, labelOptions.Description and 56 or 42)
				local label =
					inlineLabel(row, labelOptions.Text or labelOptions.Name or "Label", labelOptions.Description)
				local control = { Instance = row, Label = label }
				function control:Set(text)
					label.Text = tostring(text)
				end
				return control
			end

			function section:AddButton(buttonOptions)
				buttonOptions = buttonOptions or {}
				local row = makeControl(self, buttonOptions.Description and 56 or SPACING.ControlH)
				local button = create("TextButton", {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.fromScale(1, 1),
					Text = "",
					AutoButtonColor = false,
					ZIndex = 3,
				}, row)
				inlineLabel(button, buttonOptions.Name or "Button", buttonOptions.Description)
				local arrow = makeGlyph(button, "chevron-right", "›", 18, Vertex.Theme.TextDim)
				arrow.AnchorPoint = Vector2.new(1, 0.5)
				arrow.Position = UDim2.new(1, -12, 0.5, 0)
				hoverFill(button, Vertex.Theme.SurfaceRaised, Vertex.Theme.SurfaceHover, row)
				connect(button.MouseButton1Click, function()
					paintGlyph(arrow, Vertex.Theme.Accent, 26)
					task.delay(0.18, function()
						if arrow.Parent then
							paintGlyph(arrow, Vertex.Theme.TextDim)
						end
					end)
					safeCall(buttonOptions.Callback)
				end)
				return {
					Instance = row,
					Press = function()
						safeCall(buttonOptions.Callback)
					end,
				}
			end

			function section:AddToggle(toggleOptions)
				toggleOptions = toggleOptions or {}
				local flag = toggleOptions.Flag or toggleOptions.Name or HttpService:GenerateGUID(false)
				local value = toggleOptions.Default == true
				Vertex.Flags[flag] = value

				local row = makeControl(self, toggleOptions.Description and 56 or SPACING.ControlH)
				inlineLabel(row, toggleOptions.Name or "Toggle", toggleOptions.Description)
				local track = create("TextButton", {
					Name = "Toggle",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -14, 0.5, 0),
					Size = UDim2.fromOffset(42, 23),
					BackgroundColor3 = value and Vertex.Theme.Accent or Vertex.Theme.SurfaceHover,
					BorderSizePixel = 0,
					Text = "",
					AutoButtonColor = false,
					ZIndex = 3,
				}, row)
				addCorner(track, RADIUS.Pill)
				local knob = create("Frame", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = value and UDim2.new(0, 22, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
					Size = UDim2.fromOffset(17, 17),
					BackgroundColor3 = Vertex.Theme.Knob,
					BorderSizePixel = 0,
					ZIndex = 4,
				}, track)
				addCorner(knob, RADIUS.Pill)

				local control = { Instance = row, Flag = flag, Value = value }
				function control:Set(newValue, silent)
					self.Value = newValue == true
					Vertex.Flags[flag] = self.Value
					motion(
						track,
						"BackgroundColor3",
						self.Value and Vertex.Theme.Accent or Vertex.Theme.SurfaceHover,
						20
					)
					motion(knob, "Position", self.Value and UDim2.new(0, 22, 0.5, 0) or UDim2.new(0, 3, 0.5, 0), 24)
					if not silent then
						safeCall(toggleOptions.Callback, self.Value)
					end
				end
				connect(track.MouseButton1Click, function()
					control:Set(not control.Value)
				end)
				return control
			end

			function section:AddSlider(sliderOptions)
				sliderOptions = sliderOptions or {}
				local minimum = tonumber(sliderOptions.Min) or 0
				local maximum = tonumber(sliderOptions.Max) or 100
				local step = tonumber(sliderOptions.Step) or 1
				local flag = sliderOptions.Flag or sliderOptions.Name or HttpService:GenerateGUID(false)
				local value = math.clamp(tonumber(sliderOptions.Default) or minimum, minimum, maximum)
				Vertex.Flags[flag] = value

				local row = makeControl(self, 68)
				stackLabel(row, sliderOptions.Name or "Slider")
				local valueLabel = create(
					"TextLabel",
					merge(textProps(TEXT.Body, Vertex.Theme.AccentText, Vertex.Fonts.Bold), {
						Text = tostring(value) .. (sliderOptions.Suffix or ""),
						TextXAlignment = Enum.TextXAlignment.Right,
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -14, 0, 12),
						Size = UDim2.fromOffset(100, 18),
						ZIndex = 3,
					}),
					row
				)
				local track = create("TextButton", {
					Position = UDim2.new(0, 14, 0, 46),
					Size = UDim2.new(1, -28, 0, 7),
					BackgroundColor3 = Vertex.Theme.SurfaceHover,
					BorderSizePixel = 0,
					Text = "",
					AutoButtonColor = false,
					ZIndex = 3,
				}, row)
				addCorner(track, RADIUS.Pill)
				local fill = create("Frame", {
					Size = UDim2.fromScale((value - minimum) / math.max(maximum - minimum, 1), 1),
					BackgroundColor3 = Vertex.Theme.Accent,
					BorderSizePixel = 0,
					ZIndex = 4,
				}, track)
				addCorner(fill, RADIUS.Pill)

				local control = { Instance = row, Flag = flag, Value = value }
				function control:Set(newValue, silent)
					newValue = math.clamp(tonumber(newValue) or minimum, minimum, maximum)
					newValue = math.floor((newValue / step) + 0.5) * step
					self.Value = newValue
					Vertex.Flags[flag] = newValue
					valueLabel.Text = tostring(newValue) .. (sliderOptions.Suffix or "")
					motion(fill, "Size", UDim2.fromScale((newValue - minimum) / math.max(maximum - minimum, 1), 1), 26)
					if not silent then
						safeCall(sliderOptions.Callback, newValue)
					end
				end

				local sliding = false
				local function update(input)
					local percent = math.clamp(
						(input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1),
						0,
						1
					)
					control:Set(minimum + ((maximum - minimum) * percent))
				end
				connect(track.InputBegan, function(input)
					if
						input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
					then
						sliding = true
						update(input)
					end
				end)
				connect(UserInputService.InputChanged, function(input)
					if
						sliding
						and (
							input.UserInputType == Enum.UserInputType.MouseMovement
							or input.UserInputType == Enum.UserInputType.Touch
						)
					then
						update(input)
					end
				end)
				connect(UserInputService.InputEnded, function(input)
					if
						input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
					then
						sliding = false
					end
				end)
				return control
			end

			function section:AddInput(inputOptions)
				inputOptions = inputOptions or {}
				local flag = inputOptions.Flag or inputOptions.Name or HttpService:GenerateGUID(false)
				local value = tostring(inputOptions.Default or "")
				Vertex.Flags[flag] = value

				local row = makeControl(self, 78)
				stackLabel(row, inputOptions.Name or "Input")
				local field = create(
					"TextBox",
					merge(textProps(TEXT.Body, Vertex.Theme.Text, Vertex.Fonts.Medium), {
						Position = UDim2.new(0, 14, 0, 38),
						Size = UDim2.new(1, -28, 0, 30),
						BackgroundColor3 = Vertex.Theme.Background,
						BorderSizePixel = 0,
						Text = value,
						PlaceholderText = inputOptions.Placeholder or "Enter a value...",
						PlaceholderColor3 = Vertex.Theme.TextDim,
						ClearTextOnFocus = false,
						-- No ClipsDescendants: it would clip the field's own UIStroke
						-- border. The control row clips any extreme overflow.
						ClipsDescendants = false,
						ZIndex = 3,
					}),
					row
				)
				addCorner(field, RADIUS.Inner)
				local fieldStroke = addStroke(field, STROKE_SOFT)
				addPadding(field, 0, 12, 0, 12)

				local control = { Instance = row, Input = field, Flag = flag, Value = value }
				function control:Set(newValue, silent)
					self.Value = tostring(newValue or "")
					field.Text = self.Value
					Vertex.Flags[flag] = self.Value
					if not silent then
						safeCall(inputOptions.Callback, self.Value)
					end
				end
				connect(field.Focused, function()
					motion(fieldStroke, "Transparency", 0.25, 22)
					motion(fieldStroke, "Color", Vertex.Theme.Accent, 22)
				end)
				connect(field.FocusLost, function(enterPressed)
					motion(fieldStroke, "Transparency", STROKE_SOFT, 22)
					motion(fieldStroke, "Color", STROKE_COLOR, 22)
					if inputOptions.Numeric and not tonumber(field.Text) then
						field.Text = self.Value
						return
					end
					control:Set(field.Text)
					if enterPressed then
						safeCall(inputOptions.OnEnter, field.Text)
					end
				end)
				return control
			end

			function section:AddDropdown(dropdownOptions)
				dropdownOptions = dropdownOptions or {}
				local items = dropdownOptions.Items or {}
				local flag = dropdownOptions.Flag or dropdownOptions.Name or HttpService:GenerateGUID(false)
				local selected = dropdownOptions.Default
				Vertex.Flags[flag] = selected

				local baseHeight = 78
				local optionHeight = 32
				local row = makeControl(self, baseHeight)
				stackLabel(row, dropdownOptions.Name or "Dropdown")

				local selector = create(
					"TextButton",
					merge(textProps(TEXT.Body, Vertex.Theme.Text, Vertex.Fonts.Medium), {
						Position = UDim2.new(0, 14, 0, 38),
						Size = UDim2.new(1, -28, 0, 30),
						BackgroundColor3 = Vertex.Theme.Background,
						BorderSizePixel = 0,
						Text = selected and tostring(selected) or (dropdownOptions.Placeholder or "Select..."),
						TextColor3 = selected and Vertex.Theme.Text or Vertex.Theme.TextDim,
						AutoButtonColor = false,
						-- No ClipsDescendants so the UIStroke border renders.
						ClipsDescendants = false,
						ZIndex = 3,
					}),
					row
				)
				addCorner(selector, RADIUS.Inner)
				addStroke(selector, STROKE_SOFT)
				addPadding(selector, 0, 34, 0, 12)

				local chevron = makeGlyph(selector, "chevron-down", "⌄", 16, Vertex.Theme.TextMuted)
				chevron.AnchorPoint = Vector2.new(1, 0.5)
				chevron.Position = UDim2.new(1, -8, 0.5, 0)

				local optionsHolder = create("Frame", {
					Name = "Options",
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(14, baseHeight),
					Size = UDim2.new(1, -28, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					ZIndex = 3,
				}, row)
				create("UIListLayout", {
					Padding = UDim.new(0, 4),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}, optionsHolder)

				local control = {
					Instance = row,
					Flag = flag,
					Value = selected,
					Open = false,
					Items = items,
				}

				function control:Set(newValue, silent)
					self.Value = newValue
					Vertex.Flags[flag] = newValue
					selector.Text = newValue ~= nil and tostring(newValue)
						or (dropdownOptions.Placeholder or "Select...")
					selector.TextColor3 = newValue ~= nil and Vertex.Theme.Text or Vertex.Theme.TextDim
					if not silent then
						safeCall(dropdownOptions.Callback, newValue)
					end
				end

				function control:SetOpen(open)
					self.Open = open == true
					if self.Open then
						for _, other in ipairs(window.OpenDropdowns) do
							if other ~= self and other.Open then
								other:SetOpen(false)
							end
						end
					end
					local count = #self.Items
					local expanded = count * optionHeight + math.max(count - 1, 0) * 4 + 10
					local height = self.Open and (baseHeight + expanded) or baseHeight
					motion(chevron, "Rotation", self.Open and 180 or 0, 20)
					motion(row, "Size", UDim2.new(1, 0, 0, height), 18)
				end

				function control:Refresh(newItems)
					self.Items = newItems or {}
					for _, child in ipairs(optionsHolder:GetChildren()) do
						if child:IsA("GuiButton") then
							child:Destroy()
						end
					end
					for _, item in ipairs(self.Items) do
						local isSelected = tostring(item) == tostring(self.Value)
						local option = create(
							"TextButton",
							merge(
								textProps(
									TEXT.Body,
									isSelected and Vertex.Theme.Text or Vertex.Theme.TextMuted,
									Vertex.Fonts.SemiBold
								),
								{
									BackgroundColor3 = isSelected and Vertex.Theme.SurfaceHover
										or Vertex.Theme.Background,
									BorderSizePixel = 0,
									Size = UDim2.new(1, 0, 0, optionHeight),
									Text = tostring(item),
									AutoButtonColor = false,
									ZIndex = 3,
								}
							),
							optionsHolder
						)
						addCorner(option, RADIUS.Inner)
						addPadding(option, 0, 10, 0, 10)
						hoverFill(
							option,
							isSelected and Vertex.Theme.SurfaceHover or Vertex.Theme.Background,
							Vertex.Theme.SurfaceHover
						)
						connect(option.MouseButton1Click, function()
							control:Set(item)
							control:SetOpen(false)
							control:Refresh(self.Items)
						end)
					end
					if self.Open then
						self:SetOpen(true)
					end
				end

				connect(selector.MouseButton1Click, function()
					control:SetOpen(not control.Open)
				end)
				table.insert(window.OpenDropdowns, control)
				control:Refresh(items)
				return control
			end

			function section:AddKeybind(keybindOptions)
				keybindOptions = keybindOptions or {}
				local flag = keybindOptions.Flag or keybindOptions.Name or HttpService:GenerateGUID(false)
				local value = keybindOptions.Default or Enum.KeyCode.Unknown
				Vertex.Flags[flag] = value

				local row = makeControl(self, keybindOptions.Description and 56 or SPACING.ControlH)
				inlineLabel(row, keybindOptions.Name or "Keybind", keybindOptions.Description)
				local bindButton = create(
					"TextButton",
					merge(textProps(TEXT.Small, Vertex.Theme.TextMuted, Vertex.Fonts.Bold), {
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -14, 0.5, 0),
						Size = UDim2.fromOffset(90, 28),
						BackgroundColor3 = Vertex.Theme.Background,
						BorderSizePixel = 0,
						Text = value.Name,
						TextXAlignment = Enum.TextXAlignment.Center,
						AutoButtonColor = false,
						ZIndex = 3,
					}),
					row
				)
				addCorner(bindButton, RADIUS.Inner)
				addStroke(bindButton, STROKE_SOFT)

				local listening = false
				local control = { Instance = row, Flag = flag, Value = value }
				function control:Set(newValue, silent)
					if typeof(newValue) ~= "EnumItem" then
						return
					end
					self.Value = newValue
					Vertex.Flags[flag] = newValue
					bindButton.Text = newValue.Name
					if not silent then
						safeCall(keybindOptions.Callback, newValue)
					end
				end
				connect(bindButton.MouseButton1Click, function()
					listening = true
					bindButton.Text = "..."
					bindButton.TextColor3 = Vertex.Theme.AccentText
					motion(bindButton, "BackgroundColor3", Vertex.Theme.SurfaceHover, 20)
				end)
				connect(UserInputService.InputBegan, function(input)
					if listening and input.KeyCode ~= Enum.KeyCode.Unknown then
						listening = false
						bindButton.TextColor3 = Vertex.Theme.TextMuted
						control:Set(input.KeyCode)
						motion(bindButton, "BackgroundColor3", Vertex.Theme.Background, 20)
					elseif not listening and input.KeyCode == control.Value then
						safeCall(keybindOptions.Pressed)
					end
				end)
				return control
			end

			table.insert(tab.Sections, section)
			return section
		end

		table.insert(window.Tabs, tab)
		if not window.CurrentTab then
			tab:Select()
		end
		return tab
	end

	table.insert(self.Windows, window)
	return window
end

--=====================================================================
-- Public: notifications
--=====================================================================

function Vertex:Notify(options)
	if type(options) == "string" then
		options = { Title = options }
	end
	options = options or {}

	local parent = self.Windows[#self.Windows]
	if not parent or not parent.ScreenGui then
		warn("[Vertex UI] Create a window before sending notifications.")
		return
	end

	local holder = parent.ScreenGui:FindFirstChild("Notifications")
	if not holder then
		holder = create("Frame", {
			Name = "Notifications",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -18, 0, 18),
			Size = UDim2.fromOffset(320, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex = 60,
		}, parent.ScreenGui)
		create("UIListLayout", {
			Padding = UDim.new(0, 8),
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, holder)
	end

	local notification = create("Frame", {
		BackgroundColor3 = self.Theme.Surface,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(310, options.Description and 74 or 54),
		Position = UDim2.fromOffset(56, 0),
		ZIndex = 61,
	}, holder)
	addCorner(notification, RADIUS.Card)

	local accentBar = create("Frame", {
		BackgroundColor3 = options.Color or self.Theme.Accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(0, 3, 1, -24),
		ZIndex = 62,
	}, notification)
	addCorner(accentBar, RADIUS.Pill)

	local title = create(
		"TextLabel",
		merge(textProps(TEXT.Label, self.Theme.Text, self.Fonts.Bold), {
			Text = options.Title or "Notification",
			TextTransparency = 1,
			Position = UDim2.fromOffset(24, options.Description and 11 or 0),
			Size = UDim2.new(1, -36, options.Description and 0 or 1, options.Description and 20 or 0),
			ZIndex = 62,
		}),
		notification
	)

	local body
	if options.Description then
		body = create(
			"TextLabel",
			merge(textProps(TEXT.Small, self.Theme.TextMuted, self.Fonts.Medium), {
				Text = options.Description,
				TextTransparency = 1,
				Position = UDim2.fromOffset(24, 32),
				Size = UDim2.new(1, -36, 0, 32),
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 62,
			}),
			notification
		)
	end

	-- Slide in from the right while fading up.
	motion(notification, "BackgroundTransparency", 0, 15)
	motion(notification, "Position", UDim2.fromOffset(0, 0), 17)
	motion(accentBar, "BackgroundTransparency", 0, 15)
	motion(title, "TextTransparency", 0, 15)
	if body then
		motion(body, "TextTransparency", 0, 15)
	end

	task.delay(options.Duration or 3, function()
		if not notification.Parent then
			return
		end
		-- Slide back out to the right while fading away.
		motion(accentBar, "BackgroundTransparency", 1, 24)
		motion(title, "TextTransparency", 1, 24)
		if body then
			motion(body, "TextTransparency", 1, 24)
		end
		motion(notification, "BackgroundTransparency", 1, 24)
		motion(notification, "Position", UDim2.fromOffset(56, 0), 22)
		task.wait(0.35)
		if notification.Parent then
			notification:Destroy()
		end
	end)

	return notification
end

--=====================================================================
-- Public: teardown
--=====================================================================

function Vertex:Destroy()
	for _, window in ipairs(self.Windows) do
		if window.ScreenGui then
			window.ScreenGui:Destroy()
		end
	end
	for _, connection in ipairs(self.Connections) do
		connection:Disconnect()
	end
	table.clear(Motion)
	table.clear(self.Windows)
	table.clear(self.Connections)
	table.clear(self.Flags)
end

return Vertex
