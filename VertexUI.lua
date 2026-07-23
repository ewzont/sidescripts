--[[
	Vertex UI
	A compact, one-file Roblox UI library.

	- BuilderSans typography (medium base weight)
	- Steel-blue accent, near-black surfaces, hairline strokes
	- Lucide icons (loaded at runtime, with graceful text fallbacks)

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
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local Vertex = {
	Version = "0.3.0",
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
	SurfaceHover = Color3.fromRGB(41, 41, 41),
	Text = Color3.fromRGB(242, 242, 242),
	TextMuted = Color3.fromRGB(163, 163, 163),
	TextDim = Color3.fromRGB(96, 96, 96),
	Accent = Color3.fromRGB(115, 147, 179), -- #7393B3
	AccentHover = Color3.fromRGB(140, 168, 196),
	AccentText = Color3.fromRGB(183, 201, 219),
	Danger = Color3.fromRGB(239, 68, 68),
	Knob = Color3.fromRGB(245, 245, 245),
}

-- Hairline strokes: white at low opacity.
local STROKE_COLOR = Color3.fromRGB(255, 255, 255)
local STROKE_SOFT = 0.9
local STROKE_STRONG = 0.82

-- One radius scale for the whole library.
local RADIUS = {
	Window = 14,
	Card = 10,
	Control = 8,
	Inner = 6,
	Pill = 999,
}

local TEXT = {
	Title = 15,
	Value = 13,
	Label = 13,
	Body = 12,
	Small = 11,
	Micro = 10,
}

local SPACING = {
	Window = 16,
	Section = 14,
	Gap = 10,
	ControlH = 42,
	TopBar = 48,
	SideW = 176,
}

-- Nicer, consistent motion.
local ANIM = TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local QUICK = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SMOOTH = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

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

local function tween(instance, properties, info)
	local result = TweenService:Create(instance, info or ANIM, properties)
	result:Play()
	return result
end

local function addCorner(instance, radius)
	return create("UICorner", {
		CornerRadius = UDim.new(0, radius or RADIUS.Inner),
	}, instance)
end

local function addStroke(instance, transparency, color)
	return create("UIStroke", {
		Color = color or STROKE_COLOR,
		Transparency = transparency or STROKE_SOFT,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, instance)
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
-- Fonts: BuilderSans, medium base weight
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
Vertex.Font = Vertex.Fonts.Medium

local function textProps(size, color, font)
	return {
		BackgroundTransparency = 1,
		FontFace = font or Vertex.Fonts.Medium,
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
		}, parent),
			true
	end
	return create(
		"TextLabel",
		merge(textProps(size or 16, color or Vertex.Theme.Text, Vertex.Fonts.SemiBold), {
			Name = "Icon",
			Text = fallback or "?",
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(size or 16, size or 16),
			ZIndex = 4,
		}),
		parent
	),
		false
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
		tween(visual, { BackgroundColor3 = hoverColor }, QUICK)
	end)
	connect(button.MouseLeave, function()
		tween(visual, { BackgroundColor3 = normalColor }, QUICK)
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
	addStroke(row, STROKE_SOFT)
	return row
end

-- Centered label for single-line controls (toggle, button, keybind, label).
local function inlineLabel(row, name, description)
	local label = create(
		"TextLabel",
		merge(textProps(TEXT.Label, Vertex.Theme.Text, Vertex.Fonts.Medium), {
			Name = "Label",
			Text = name or "Control",
			Position = UDim2.fromOffset(14, description and 7 or 0),
			Size = UDim2.new(1, -70, description and 0 or 1, description and 18 or 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 3,
		}),
		row
	)
	if description then
		create(
			"TextLabel",
			merge(textProps(TEXT.Small, Vertex.Theme.TextMuted, Vertex.Fonts.Regular), {
				Name = "Description",
				Text = description,
				Position = UDim2.fromOffset(14, 25),
				Size = UDim2.new(1, -70, 0, 16),
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
		merge(textProps(TEXT.Label, Vertex.Theme.Text, Vertex.Fonts.Medium), {
			Name = "Label",
			Text = name or "Control",
			Position = UDim2.fromOffset(14, 9),
			Size = UDim2.new(1, -28, 0, 16),
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
		ClipsDescendants = true,
		ZIndex = 2,
	}, screenGui)
	addCorner(main, RADIUS.Window)
	addStroke(main, STROKE_STRONG)

	local uiScale = create("UIScale", { Scale = 1 }, main)

	-- Soft drop shadow.
	create("ImageLabel", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 60, 1, 60),
		BackgroundTransparency = 1,
		Image = "rbxassetid://6014261993",
		ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 0.4,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(49, 49, 450, 450),
		ZIndex = 1,
	}, screenGui)

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

	create("Frame", {
		Name = "TopDivider",
		BackgroundColor3 = STROKE_COLOR,
		BackgroundTransparency = STROKE_SOFT,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		ZIndex = 5,
	}, topBar)

	create("Frame", {
		Name = "BrandMark",
		BackgroundColor3 = Vertex.Theme.Accent,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(4, SPACING.TopBar - 24),
		ZIndex = 5,
	}, topBar)

	create(
		"TextLabel",
		merge(textProps(TEXT.Title, Vertex.Theme.Text, Vertex.Fonts.SemiBold), {
			Name = "Title",
			Text = options.Title or "Vertex",
			Position = UDim2.fromOffset(30, options.Subtitle and 7 or 0),
			Size = UDim2.new(0, 300, options.Subtitle and 0 or 1, options.Subtitle and 20 or 0),
			ZIndex = 5,
		}),
		topBar
	)

	if options.Subtitle then
		create(
			"TextLabel",
			merge(textProps(TEXT.Small, Vertex.Theme.TextMuted, Vertex.Fonts.Regular), {
				Name = "Subtitle",
				Text = options.Subtitle,
				Position = UDim2.fromOffset(30, 26),
				Size = UDim2.new(0, 300, 0, 16),
				ZIndex = 5,
			}),
			topBar
		)
	end

	local minimiseButton = create("TextButton", {
		Name = "Minimise",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = Vertex.Theme.SurfaceRaised,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 5,
	}, topBar)
	addCorner(minimiseButton, RADIUS.Inner)
	local minimiseIcon = makeGlyph(minimiseButton, "x", "✕", 16, Vertex.Theme.TextMuted)
	minimiseIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	minimiseIcon.Position = UDim2.fromScale(0.5, 0.5)

	----------------------------------------------------------------
	-- Body: sidebar + content
	----------------------------------------------------------------
	local body = create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, SPACING.TopBar),
		Size = UDim2.new(1, 0, 1, -SPACING.TopBar),
		ClipsDescendants = true,
		ZIndex = 3,
	}, main)

	local sidebar = create("Frame", {
		Name = "Sidebar",
		BackgroundColor3 = Vertex.Theme.Surface,
		BorderSizePixel = 0,
		Size = UDim2.new(0, SPACING.SideW, 1, 0),
		ZIndex = 3,
	}, body)

	create("Frame", {
		Name = "Divider",
		BackgroundColor3 = STROKE_COLOR,
		BackgroundTransparency = STROKE_SOFT,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -1, 0, 0),
		Size = UDim2.new(0, 1, 1, 0),
		ZIndex = 3,
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
		ZIndex = 3,
	}, sidebar)
	create("UIListLayout", {
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tabList)

	local content = create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(SPACING.SideW, 0),
		Size = UDim2.new(1, -SPACING.SideW, 1, 0),
		ZIndex = 3,
	}, body)

	local window = {
		ScreenGui = screenGui,
		Instance = main,
		TopBar = topBar,
		Body = body,
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
		self.Visible = value == true
		screenGui.Enabled = self.Visible
	end

	function window:Toggle()
		self:SetVisible(not self.Visible)
	end

	function window:SetMinimised(state)
		self.Minimised = state == true
		if self.Minimised then
			tween(main, { Size = UDim2.new(main.Size.X.Scale, main.Size.X.Offset, 0, SPACING.TopBar) }, ANIM)
			tween(minimiseIcon, { Rotation = 45 }, ANIM)
		else
			tween(main, { Size = UDim2.new(main.Size.X.Scale, main.Size.X.Offset, 0, self.ExpandedHeight) }, ANIM)
			tween(minimiseIcon, { Rotation = 0 }, ANIM)
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
		tween(minimiseButton, { BackgroundTransparency = 0 }, QUICK)
		tween(minimiseIcon, { ImageColor3 = Vertex.Theme.Text, TextColor3 = Vertex.Theme.Text }, QUICK)
	end)
	connect(minimiseButton.MouseLeave, function()
		tween(minimiseButton, { BackgroundTransparency = 1 }, QUICK)
		tween(minimiseIcon, { ImageColor3 = Vertex.Theme.TextMuted, TextColor3 = Vertex.Theme.TextMuted }, QUICK)
	end)

	connect(UserInputService.InputBegan, function(input, processed)
		if not processed and input.KeyCode == window.ToggleKey then
			window:Toggle()
		end
	end)

	-- Entrance animation.
	uiScale.Scale = 0.94
	main.BackgroundTransparency = 1
	tween(uiScale, { Scale = 1 }, POP)
	tween(main, { BackgroundTransparency = 0 }, SMOOTH)

	function window:AddTab(tabOptions)
		tabOptions = tabOptions or {}
		local tabName = tabOptions.Name or "Tab"

		local tabButton = create("TextButton", {
			Name = tabName,
			Text = "",
			BackgroundColor3 = Vertex.Theme.SurfaceRaised,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 36),
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
			tabIcon = makeGlyph(tabButton, tabOptions.Icon, nil, 16, Vertex.Theme.TextMuted)
			tabIcon.AnchorPoint = Vector2.new(0, 0.5)
			tabIcon.Position = UDim2.new(0, 20, 0.5, 0)
			textOffset = 44
		end

		local tabLabel = create(
			"TextLabel",
			merge(textProps(TEXT.Label, Vertex.Theme.TextMuted, Vertex.Fonts.Medium), {
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
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = STROKE_COLOR,
			ScrollBarImageTransparency = 0.7,
			ZIndex = 3,
		}, content)
		addPadding(page, 0, 6, 8, 0)
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
				other.Page.Visible = selected
				tween(other.Button, { BackgroundTransparency = selected and 0 or 1 }, QUICK)
				tween(other.Label, {
					TextColor3 = selected and Vertex.Theme.Text or Vertex.Theme.TextMuted,
				}, QUICK)
				tween(other.Indicator, { BackgroundTransparency = selected and 0 or 1 }, QUICK)
				other.Label.FontFace = selected and Vertex.Fonts.SemiBold or Vertex.Fonts.Medium
				if other.Icon then
					tween(other.Icon, {
						ImageColor3 = selected and Vertex.Theme.Text or Vertex.Theme.TextMuted,
						TextColor3 = selected and Vertex.Theme.Text or Vertex.Theme.TextMuted,
					}, QUICK)
				end
			end
			window.CurrentTab = self
		end

		connect(tabButton.MouseButton1Click, function()
			tab:Select()
		end)
		connect(tabButton.MouseEnter, function()
			if window.CurrentTab ~= tab then
				tween(tabButton, { BackgroundTransparency = 0.45 }, QUICK)
			end
		end)
		connect(tabButton.MouseLeave, function()
			if window.CurrentTab ~= tab then
				tween(tabButton, { BackgroundTransparency = 1 }, QUICK)
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
			addStroke(sectionFrame, STROKE_SOFT)
			addPadding(sectionFrame, SPACING.Section, SPACING.Section, SPACING.Section, SPACING.Section)
			create("UIListLayout", {
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}, sectionFrame)

			create(
				"TextLabel",
				merge(textProps(TEXT.Micro, Vertex.Theme.TextDim, Vertex.Fonts.SemiBold), {
					Name = "SectionTitle",
					Text = string.upper(sectionOptions.Name or "SECTION"),
					Size = UDim2.new(1, 0, 0, 14),
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
				local row = makeControl(self, labelOptions.Description and 52 or 40)
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
				local row = makeControl(self, buttonOptions.Description and 52 or SPACING.ControlH)
				local button = create("TextButton", {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.fromScale(1, 1),
					Text = "",
					AutoButtonColor = false,
					ZIndex = 3,
				}, row)
				inlineLabel(button, buttonOptions.Name or "Button", buttonOptions.Description)
				local arrow = makeGlyph(button, "chevron-right", "›", 16, Vertex.Theme.TextDim)
				arrow.AnchorPoint = Vector2.new(1, 0.5)
				arrow.Position = UDim2.new(1, -12, 0.5, 0)
				hoverFill(button, Vertex.Theme.SurfaceRaised, Vertex.Theme.SurfaceHover, row)
				connect(button.MouseButton1Click, function()
					tween(arrow, { ImageColor3 = Vertex.Theme.Accent, TextColor3 = Vertex.Theme.Accent }, QUICK)
					task.delay(0.16, function()
						if arrow.Parent then
							tween(
								arrow,
								{ ImageColor3 = Vertex.Theme.TextDim, TextColor3 = Vertex.Theme.TextDim },
								QUICK
							)
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

				local row = makeControl(self, toggleOptions.Description and 52 or SPACING.ControlH)
				inlineLabel(row, toggleOptions.Name or "Toggle", toggleOptions.Description)
				local track = create("TextButton", {
					Name = "Toggle",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -14, 0.5, 0),
					Size = UDim2.fromOffset(40, 22),
					BackgroundColor3 = value and Vertex.Theme.Accent or Vertex.Theme.SurfaceHover,
					BorderSizePixel = 0,
					Text = "",
					AutoButtonColor = false,
					ZIndex = 3,
				}, row)
				addCorner(track, RADIUS.Pill)
				addStroke(track, STROKE_SOFT)
				local knob = create("Frame", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = value and UDim2.new(0, 21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
					Size = UDim2.fromOffset(16, 16),
					BackgroundColor3 = Vertex.Theme.Knob,
					BorderSizePixel = 0,
					ZIndex = 4,
				}, track)
				addCorner(knob, RADIUS.Pill)

				local control = { Instance = row, Flag = flag, Value = value }
				function control:Set(newValue, silent)
					self.Value = newValue == true
					Vertex.Flags[flag] = self.Value
					tween(track, {
						BackgroundColor3 = self.Value and Vertex.Theme.Accent or Vertex.Theme.SurfaceHover,
					}, QUICK)
					tween(knob, {
						Position = self.Value and UDim2.new(0, 21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
					}, SMOOTH)
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

				local row = makeControl(self, 56)
				stackLabel(row, sliderOptions.Name or "Slider")
				local valueLabel = create(
					"TextLabel",
					merge(textProps(TEXT.Body, Vertex.Theme.AccentText, Vertex.Fonts.SemiBold), {
						Text = tostring(value) .. (sliderOptions.Suffix or ""),
						TextXAlignment = Enum.TextXAlignment.Right,
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -14, 0, 9),
						Size = UDim2.fromOffset(90, 16),
						ZIndex = 3,
					}),
					row
				)
				local track = create("TextButton", {
					Position = UDim2.new(0, 14, 0, 36),
					Size = UDim2.new(1, -28, 0, 6),
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
					tween(fill, {
						Size = UDim2.fromScale((newValue - minimum) / math.max(maximum - minimum, 1), 1),
					}, QUICK)
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

				local row = makeControl(self, 60)
				stackLabel(row, inputOptions.Name or "Input")
				local field = create(
					"TextBox",
					merge(textProps(TEXT.Body, Vertex.Theme.Text, Vertex.Fonts.Regular), {
						Position = UDim2.new(0, 14, 0, 30),
						Size = UDim2.new(1, -28, 0, 24),
						BackgroundColor3 = Vertex.Theme.Background,
						BorderSizePixel = 0,
						Text = value,
						PlaceholderText = inputOptions.Placeholder or "Enter a value...",
						PlaceholderColor3 = Vertex.Theme.TextDim,
						ClearTextOnFocus = false,
						ClipsDescendants = true,
						ZIndex = 3,
					}),
					row
				)
				addCorner(field, RADIUS.Inner)
				local fieldStroke = addStroke(field, STROKE_SOFT)
				addPadding(field, 0, 10, 0, 10)

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
					tween(fieldStroke, { Transparency = 0.3, Color = Vertex.Theme.Accent }, QUICK)
				end)
				connect(field.FocusLost, function(enterPressed)
					tween(fieldStroke, { Transparency = STROKE_SOFT, Color = STROKE_COLOR }, QUICK)
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

				local baseHeight = 58
				local optionHeight = 28
				local row = makeControl(self, baseHeight)
				stackLabel(row, dropdownOptions.Name or "Dropdown")

				local selector = create(
					"TextButton",
					merge(textProps(TEXT.Body, Vertex.Theme.Text, Vertex.Fonts.Regular), {
						Position = UDim2.new(0, 14, 0, 30),
						Size = UDim2.new(1, -28, 0, 24),
						BackgroundColor3 = Vertex.Theme.Background,
						BorderSizePixel = 0,
						Text = selected and tostring(selected) or (dropdownOptions.Placeholder or "Select..."),
						TextColor3 = selected and Vertex.Theme.Text or Vertex.Theme.TextDim,
						AutoButtonColor = false,
						ClipsDescendants = true,
						ZIndex = 3,
					}),
					row
				)
				addCorner(selector, RADIUS.Inner)
				addStroke(selector, STROKE_SOFT)
				addPadding(selector, 0, 30, 0, 10)

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
					tween(chevron, { Rotation = self.Open and 180 or 0 }, QUICK)
					tween(row, { Size = UDim2.new(1, 0, 0, height) }, ANIM)
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
									Vertex.Fonts.Medium
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

				local row = makeControl(self, keybindOptions.Description and 52 or SPACING.ControlH)
				inlineLabel(row, keybindOptions.Name or "Keybind", keybindOptions.Description)
				local bindButton = create(
					"TextButton",
					merge(textProps(TEXT.Small, Vertex.Theme.TextMuted, Vertex.Fonts.SemiBold), {
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -14, 0.5, 0),
						Size = UDim2.fromOffset(84, 26),
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
					tween(bindButton, { BackgroundColor3 = Vertex.Theme.SurfaceHover }, QUICK)
				end)
				connect(UserInputService.InputBegan, function(input)
					if listening and input.KeyCode ~= Enum.KeyCode.Unknown then
						listening = false
						bindButton.TextColor3 = Vertex.Theme.TextMuted
						control:Set(input.KeyCode)
						tween(bindButton, { BackgroundColor3 = Vertex.Theme.Background }, QUICK)
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
			Size = UDim2.fromOffset(310, 0),
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
		Size = UDim2.fromOffset(300, options.Description and 70 or 52),
		Position = UDim2.fromOffset(24, 0),
		ZIndex = 61,
	}, holder)
	addCorner(notification, RADIUS.Card)
	local notifStroke = addStroke(notification, 1)

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
		merge(textProps(TEXT.Label, self.Theme.Text, self.Fonts.SemiBold), {
			Text = options.Title or "Notification",
			TextTransparency = 1,
			Position = UDim2.fromOffset(24, options.Description and 10 or 0),
			Size = UDim2.new(1, -36, options.Description and 0 or 1, options.Description and 20 or 0),
			ZIndex = 62,
		}),
		notification
	)

	local body
	if options.Description then
		body = create(
			"TextLabel",
			merge(textProps(TEXT.Small, self.Theme.TextMuted, self.Fonts.Regular), {
				Text = options.Description,
				TextTransparency = 1,
				Position = UDim2.fromOffset(24, 30),
				Size = UDim2.new(1, -36, 0, 30),
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 62,
			}),
			notification
		)
	end

	tween(notification, { BackgroundTransparency = 0, Position = UDim2.fromOffset(0, 0) }, SMOOTH)
	tween(notifStroke, { Transparency = STROKE_SOFT }, SMOOTH)
	tween(accentBar, { BackgroundTransparency = 0 }, SMOOTH)
	tween(title, { TextTransparency = 0 }, SMOOTH)
	if body then
		tween(body, { TextTransparency = 0 }, SMOOTH)
	end

	task.delay(options.Duration or 3, function()
		if not notification.Parent then
			return
		end
		tween(notifStroke, { Transparency = 1 }, QUICK)
		tween(accentBar, { BackgroundTransparency = 1 }, QUICK)
		tween(title, { TextTransparency = 1 }, QUICK)
		if body then
			tween(body, { TextTransparency = 1 }, QUICK)
		end
		local closing = tween(notification, {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(24, 0),
		}, ANIM)
		closing.Completed:Wait()
		notification:Destroy()
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
	table.clear(self.Windows)
	table.clear(self.Connections)
	table.clear(self.Flags)
end

return Vertex
