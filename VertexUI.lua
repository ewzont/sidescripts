--[[
	Vertex UI
	A compact, one-file Roblox UI library.

	Quick start:
		local Vertex = loadstring(game:HttpGet("YOUR_RAW_URL"))()
		local Window = Vertex:CreateWindow({ Title = "Vertex", Subtitle = "Dashboard" })
		local Main = Window:AddTab({ Name = "Main" })
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
	Version = "0.1.0",
	Flags = {},
	Windows = {},
	Connections = {},
}

Vertex.Theme = {
	Background = Color3.fromRGB(2, 6, 23),
	Surface = Color3.fromRGB(15, 23, 42),
	SurfaceRaised = Color3.fromRGB(24, 34, 54),
	SurfaceHover = Color3.fromRGB(31, 43, 66),
	Border = Color3.fromRGB(51, 65, 85),
	BorderSoft = Color3.fromRGB(38, 50, 70),
	Text = Color3.fromRGB(248, 250, 252),
	TextMuted = Color3.fromRGB(148, 163, 184),
	TextDim = Color3.fromRGB(100, 116, 139),
	Accent = Color3.fromRGB(34, 197, 94),
	AccentHover = Color3.fromRGB(48, 211, 111),
	AccentDark = Color3.fromRGB(20, 83, 45),
	Danger = Color3.fromRGB(239, 68, 68),
}

local animation = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local fastAnimation = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

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
	local result = TweenService:Create(instance, info or animation, properties)
	result:Play()
	return result
end

local function addCorner(instance, radius)
	return create("UICorner", {
		CornerRadius = UDim.new(0, radius or 8),
	}, instance)
end

local function addStroke(instance, color, transparency, thickness)
	return create("UIStroke", {
		Color = color or Vertex.Theme.Border,
		Transparency = transparency or 0,
		Thickness = thickness or 1,
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

local function loadInter()
	local fallback = Font.fromEnum(Enum.Font.BuilderSans)
	if
		type(isfile) ~= "function"
		or type(writefile) ~= "function"
		or type(makefolder) ~= "function"
		or type(isfolder) ~= "function"
		or type(getcustomasset) ~= "function"
	then
		return fallback
	end

	local success, font = pcall(function()
		local directory = "VertexUI"
		local ttfPath = directory .. "/Inter-SemiBold.ttf"
		local fontPath = directory .. "/Inter.font"

		if not isfolder(directory) then
			makefolder(directory)
		end
		if not isfile(ttfPath) then
			writefile(
				ttfPath,
				game:HttpGet("https://github.com/google/fonts/raw/main/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf")
			)
		end

		local fontData = {
			name = "Inter",
			faces = {
				{
					name = "Regular",
					weight = 600,
					style = "normal",
					assetId = getcustomasset(ttfPath),
				},
			},
		}
		writefile(fontPath, HttpService:JSONEncode(fontData))
		return Font.new(getcustomasset(fontPath))
	end)

	return success and font or fallback
end

Vertex.Font = loadInter()

local function textProperties(size, color)
	return {
		BackgroundTransparency = 1,
		FontFace = Vertex.Font,
		TextColor3 = color or Vertex.Theme.Text,
		TextSize = size or 13,
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

local function makeInteractive(button, normalColor, hoverColor, visual)
	visual = visual or button
	button.AutoButtonColor = false
	connect(button.MouseEnter, function()
		tween(visual, { BackgroundColor3 = hoverColor }, fastAnimation)
	end)
	connect(button.MouseLeave, function()
		tween(visual, { BackgroundColor3 = normalColor }, fastAnimation)
	end)
	connect(button.MouseButton1Down, function()
		tween(visual, { BackgroundTransparency = 0.18 }, fastAnimation)
	end)
	connect(button.MouseButton1Up, function()
		tween(visual, { BackgroundTransparency = 0 }, fastAnimation)
	end)
end

local function makeDraggable(handle, target)
	local dragging = false
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
		end
	end)

	connect(UserInputService.InputChanged, function(input)
		if not dragging then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		local delta = input.Position - dragStart
		target.Position = UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y
		)
	end)

	connect(UserInputService.InputEnded, function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)
end

local function makeControl(section, height)
	local row = create("Frame", {
		Name = "Control",
		BackgroundColor3 = Vertex.Theme.SurfaceRaised,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, height or 44),
		ClipsDescendants = true,
	}, section.Container)
	addCorner(row, 7)
	addStroke(row, Vertex.Theme.BorderSoft, 0.35)
	return row
end

local function controlLabel(row, name, description)
	local label = create(
		"TextLabel",
		merge(textProperties(13), {
			Name = "Label",
			Text = name or "Control",
			Position = UDim2.fromOffset(12, description and 6 or 0),
			Size = UDim2.new(1, -24, description and 0 or 1, description and 20 or 0),
		}),
		row
	)

	if description then
		create(
			"TextLabel",
			merge(textProperties(11, Vertex.Theme.TextMuted), {
				Name = "Description",
				Text = description,
				Position = UDim2.fromOffset(12, 25),
				Size = UDim2.new(1, -24, 0, 16),
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
			row
		)
	end
	return label
end

function Vertex:SetTheme(overrides)
	for key, value in pairs(overrides or {}) do
		if self.Theme[key] ~= nil and typeof(value) == "Color3" then
			self.Theme[key] = value
		end
	end
end

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
		Size = options.Size or UDim2.fromOffset(760, 500),
		BackgroundColor3 = Vertex.Theme.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, screenGui)
	addCorner(main, 12)
	addStroke(main, Vertex.Theme.Border, 0.1)

	local shadow = create("ImageLabel", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 54, 1, 54),
		BackgroundTransparency = 1,
		Image = "rbxassetid://6014261993",
		ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 0.38,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(49, 49, 450, 450),
		ZIndex = 0,
	}, main)
	shadow.Parent = screenGui
	main.ZIndex = 2

	local sidebar = create("Frame", {
		Name = "Sidebar",
		BackgroundColor3 = Vertex.Theme.Surface,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 190, 1, 0),
		ZIndex = 3,
	}, main)

	create("Frame", {
		Name = "Divider",
		BackgroundColor3 = Vertex.Theme.BorderSoft,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -1, 0, 0),
		Size = UDim2.new(0, 1, 1, 0),
	}, sidebar)

	local header = create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 78),
		Active = true,
	}, sidebar)

	create("Frame", {
		Name = "BrandMark",
		BackgroundColor3 = Vertex.Theme.Accent,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(16, 21),
		Size = UDim2.fromOffset(4, 35),
	}, header)

	create(
		"TextLabel",
		merge(textProperties(16), {
			Name = "Title",
			Text = options.Title or "Vertex",
			Position = UDim2.fromOffset(30, 16),
			Size = UDim2.new(1, -42, 0, 25),
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		header
	)

	create(
		"TextLabel",
		merge(textProperties(11, Vertex.Theme.TextMuted), {
			Name = "Subtitle",
			Text = options.Subtitle or "Interface library",
			Position = UDim2.fromOffset(30, 39),
			Size = UDim2.new(1, -42, 0, 18),
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		header
	)

	local tabList = create("ScrollingFrame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 78),
		Size = UDim2.new(1, -20, 1, -128),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 0,
	}, sidebar)
	create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tabList)

	create(
		"TextLabel",
		merge(textProperties(10, Vertex.Theme.TextDim), {
			Name = "Footer",
			Text = "VERTEX  •  " .. Vertex.Version,
			Position = UDim2.new(0, 16, 1, -38),
			Size = UDim2.new(1, -32, 0, 20),
		}),
		sidebar
	)

	local content = create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(190, 0),
		Size = UDim2.new(1, -190, 1, 0),
	}, main)

	local window = {
		ScreenGui = screenGui,
		Instance = main,
		Sidebar = sidebar,
		TabList = tabList,
		Content = content,
		Tabs = {},
		CurrentTab = nil,
		Visible = true,
		ToggleKey = options.ToggleKey or Enum.KeyCode.RightShift,
	}

	makeDraggable(header, main)

	function window:SetVisible(value)
		self.Visible = value == true
		screenGui.Enabled = self.Visible
	end

	function window:Toggle()
		self:SetVisible(not self.Visible)
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

	connect(UserInputService.InputBegan, function(input, processed)
		if not processed and input.KeyCode == window.ToggleKey then
			window:Toggle()
		end
	end)

	function window:AddTab(tabOptions)
		tabOptions = tabOptions or {}
		local tabName = tabOptions.Name or "Tab"

		local tabButton = create(
			"TextButton",
			merge(textProperties(13, Vertex.Theme.TextMuted), {
				Name = tabName,
				Text = "",
				BackgroundColor3 = Vertex.Theme.Surface,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 38),
				AutoButtonColor = false,
			}),
			tabList
		)
		addCorner(tabButton, 7)

		local indicator = create("Frame", {
			Name = "Indicator",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 7, 0.5, 0),
			Size = UDim2.fromOffset(3, 18),
			BackgroundColor3 = Vertex.Theme.Accent,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, tabButton)
		addCorner(indicator, 2)

		local tabLabel = create(
			"TextLabel",
			merge(textProperties(13, Vertex.Theme.TextMuted), {
				Text = tabName,
				Position = UDim2.fromOffset(18, 0),
				Size = UDim2.new(1, -28, 1, 0),
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
			tabButton
		)

		local page = create("ScrollingFrame", {
			Name = tabName,
			Visible = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(18, 18),
			Size = UDim2.new(1, -36, 1, -36),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Vertex.Theme.Border,
			ScrollBarImageTransparency = 0.25,
		}, content)
		addPadding(page, 0, 6, 8, 0)
		create("UIListLayout", {
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, page)

		local tab = {
			Name = tabName,
			Button = tabButton,
			Label = tabLabel,
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
				tween(other.Button, {
					BackgroundColor3 = selected and Vertex.Theme.SurfaceRaised or Vertex.Theme.Surface,
				})
				tween(other.Label, {
					TextColor3 = selected and Vertex.Theme.Text or Vertex.Theme.TextMuted,
				})
				tween(other.Indicator, {
					BackgroundTransparency = selected and 0 or 1,
				})
			end
			window.CurrentTab = self
		end

		connect(tabButton.MouseButton1Click, function()
			tab:Select()
		end)
		connect(tabButton.MouseEnter, function()
			if window.CurrentTab ~= tab then
				tween(tabButton, { BackgroundColor3 = Vertex.Theme.SurfaceHover }, fastAnimation)
			end
		end)
		connect(tabButton.MouseLeave, function()
			if window.CurrentTab ~= tab then
				tween(tabButton, { BackgroundColor3 = Vertex.Theme.Surface }, fastAnimation)
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
			}, page)
			addCorner(sectionFrame, 9)
			addStroke(sectionFrame, Vertex.Theme.BorderSoft, 0.2)
			addPadding(sectionFrame, 12, 12, 12, 12)

			create(
				"TextLabel",
				merge(textProperties(12, Vertex.Theme.TextMuted), {
					Name = "SectionTitle",
					Text = string.upper(sectionOptions.Name or "SECTION"),
					Size = UDim2.new(1, 0, 0, 20),
					LayoutOrder = 0,
				}),
				sectionFrame
			)

			local sectionContainer = create("Frame", {
				Name = "Container",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 1,
			}, sectionFrame)
			create("UIListLayout", {
				Padding = UDim.new(0, 7),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}, sectionContainer)
			create("UIListLayout", {
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}, sectionFrame)

			local section = {
				Name = sectionOptions.Name or "Section",
				Instance = sectionFrame,
				Container = sectionContainer,
				Tab = tab,
			}

			function section:AddLabel(options)
				if type(options) == "string" then
					options = { Text = options }
				end
				options = options or {}
				local row = makeControl(self, options.Description and 54 or 40)
				local label = controlLabel(row, options.Text or options.Name or "Label", options.Description)
				local control = { Instance = row, Label = label }
				function control:Set(text)
					label.Text = tostring(text)
				end
				return control
			end

			function section:AddButton(options)
				options = options or {}
				local row = makeControl(self, options.Description and 54 or 44)
				local button = create("TextButton", {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.fromScale(1, 1),
					Text = "",
					AutoButtonColor = false,
				}, row)
				controlLabel(button, options.Name or "Button", options.Description)
				local action = create(
					"TextLabel",
					merge(textProperties(16, Vertex.Theme.TextMuted), {
						Text = "›",
						TextXAlignment = Enum.TextXAlignment.Center,
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -11, 0.5, 0),
						Size = UDim2.fromOffset(24, 24),
					}),
					button
				)
				makeInteractive(button, Vertex.Theme.SurfaceRaised, Vertex.Theme.SurfaceHover, row)
				connect(button.MouseButton1Click, function()
					tween(action, { TextColor3 = Vertex.Theme.Accent }, fastAnimation)
					task.delay(0.15, function()
						if action.Parent then
							tween(action, { TextColor3 = Vertex.Theme.TextMuted }, fastAnimation)
						end
					end)
					safeCall(options.Callback)
				end)
				return {
					Instance = row,
					Press = function()
						safeCall(options.Callback)
					end,
				}
			end

			function section:AddToggle(options)
				options = options or {}
				local flag = options.Flag or options.Name or HttpService:GenerateGUID(false)
				local value = options.Default == true
				Vertex.Flags[flag] = value

				local row = makeControl(self, options.Description and 54 or 44)
				controlLabel(row, options.Name or "Toggle", options.Description)
				local track = create("TextButton", {
					Name = "Toggle",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -12, 0.5, 0),
					Size = UDim2.fromOffset(38, 22),
					BackgroundColor3 = value and Vertex.Theme.Accent or Vertex.Theme.Border,
					BorderSizePixel = 0,
					Text = "",
					AutoButtonColor = false,
				}, row)
				addCorner(track, 11)
				local knob = create("Frame", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = value and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
					Size = UDim2.fromOffset(16, 16),
					BackgroundColor3 = Color3.fromRGB(255, 255, 255),
					BorderSizePixel = 0,
				}, track)
				addCorner(knob, 8)

				local control = { Instance = row, Flag = flag, Value = value }
				function control:Set(newValue, silent)
					self.Value = newValue == true
					Vertex.Flags[flag] = self.Value
					tween(track, {
						BackgroundColor3 = self.Value and Vertex.Theme.Accent or Vertex.Theme.Border,
					})
					tween(knob, {
						Position = self.Value and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
					})
					if not silent then
						safeCall(options.Callback, self.Value)
					end
				end
				connect(track.MouseButton1Click, function()
					control:Set(not control.Value)
				end)
				return control
			end

			function section:AddSlider(options)
				options = options or {}
				local minimum = tonumber(options.Min) or 0
				local maximum = tonumber(options.Max) or 100
				local step = tonumber(options.Step) or 1
				local flag = options.Flag or options.Name or HttpService:GenerateGUID(false)
				local value = math.clamp(tonumber(options.Default) or minimum, minimum, maximum)
				Vertex.Flags[flag] = value

				local row = makeControl(self, 64)
				controlLabel(row, options.Name or "Slider")
				local valueLabel = create(
					"TextLabel",
					merge(textProperties(12, Vertex.Theme.TextMuted), {
						Text = tostring(value) .. (options.Suffix or ""),
						TextXAlignment = Enum.TextXAlignment.Right,
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -12, 0, 0),
						Size = UDim2.fromOffset(90, 38),
					}),
					row
				)
				local track = create("TextButton", {
					Position = UDim2.new(0, 12, 1, -18),
					Size = UDim2.new(1, -24, 0, 5),
					BackgroundColor3 = Vertex.Theme.Border,
					BorderSizePixel = 0,
					Text = "",
					AutoButtonColor = false,
				}, row)
				addCorner(track, 3)
				local fill = create("Frame", {
					Size = UDim2.fromScale((value - minimum) / math.max(maximum - minimum, 1), 1),
					BackgroundColor3 = Vertex.Theme.Accent,
					BorderSizePixel = 0,
				}, track)
				addCorner(fill, 3)

				local control = { Instance = row, Flag = flag, Value = value }
				function control:Set(newValue, silent)
					newValue = math.clamp(tonumber(newValue) or minimum, minimum, maximum)
					newValue = math.floor((newValue / step) + 0.5) * step
					self.Value = newValue
					Vertex.Flags[flag] = newValue
					valueLabel.Text = tostring(newValue) .. (options.Suffix or "")
					tween(fill, {
						Size = UDim2.fromScale((newValue - minimum) / math.max(maximum - minimum, 1), 1),
					}, fastAnimation)
					if not silent then
						safeCall(options.Callback, newValue)
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

			function section:AddInput(options)
				options = options or {}
				local flag = options.Flag or options.Name or HttpService:GenerateGUID(false)
				local value = tostring(options.Default or "")
				Vertex.Flags[flag] = value

				local row = makeControl(self, 64)
				controlLabel(row, options.Name or "Input")
				local input = create(
					"TextBox",
					merge(textProperties(12), {
						Position = UDim2.new(0, 12, 1, -28),
						Size = UDim2.new(1, -24, 0, 22),
						BackgroundColor3 = Vertex.Theme.Background,
						BorderSizePixel = 0,
						Text = value,
						PlaceholderText = options.Placeholder or "Enter a value...",
						PlaceholderColor3 = Vertex.Theme.TextDim,
						ClearTextOnFocus = false,
						TextTruncate = Enum.TextTruncate.AtEnd,
					}),
					row
				)
				addCorner(input, 5)
				addStroke(input, Vertex.Theme.BorderSoft, 0.25)
				addPadding(input, 0, 8, 0, 8)

				local control = { Instance = row, Input = input, Flag = flag, Value = value }
				function control:Set(newValue, silent)
					self.Value = tostring(newValue or "")
					input.Text = self.Value
					Vertex.Flags[flag] = self.Value
					if not silent then
						safeCall(options.Callback, self.Value)
					end
				end
				connect(input.Focused, function()
					tween(input, { BackgroundColor3 = Vertex.Theme.SurfaceHover }, fastAnimation)
				end)
				connect(input.FocusLost, function(enterPressed)
					tween(input, { BackgroundColor3 = Vertex.Theme.Background }, fastAnimation)
					control:Set(input.Text)
					if enterPressed then
						safeCall(options.OnEnter, input.Text)
					end
				end)
				return control
			end

			function section:AddDropdown(options)
				options = options or {}
				local items = options.Items or {}
				local flag = options.Flag or options.Name or HttpService:GenerateGUID(false)
				local selected = options.Default
				Vertex.Flags[flag] = selected

				local row = makeControl(self, 64)
				row.ClipsDescendants = true
				controlLabel(row, options.Name or "Dropdown")
				local selector = create(
					"TextButton",
					merge(textProperties(12), {
						Position = UDim2.new(0, 12, 0, 34),
						Size = UDim2.new(1, -24, 0, 23),
						BackgroundColor3 = Vertex.Theme.Background,
						BorderSizePixel = 0,
						Text = selected and tostring(selected) or (options.Placeholder or "Select..."),
						TextColor3 = selected and Vertex.Theme.Text or Vertex.Theme.TextDim,
						AutoButtonColor = false,
					}),
					row
				)
				addCorner(selector, 5)
				addStroke(selector, Vertex.Theme.BorderSoft, 0.25)
				addPadding(selector, 0, 24, 0, 8)

				create(
					"TextLabel",
					merge(textProperties(13, Vertex.Theme.TextMuted), {
						Text = "⌄",
						TextXAlignment = Enum.TextXAlignment.Center,
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, 0, 0, 0),
						Size = UDim2.fromOffset(24, 23),
					}),
					selector
				)

				local optionsHolder = create("Frame", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(12, 63),
					Size = UDim2.new(1, -24, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
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
					selector.Text = newValue ~= nil and tostring(newValue) or (options.Placeholder or "Select...")
					selector.TextColor3 = newValue ~= nil and Vertex.Theme.Text or Vertex.Theme.TextDim
					if not silent then
						safeCall(options.Callback, newValue)
					end
				end

				function control:SetOpen(open)
					self.Open = open == true
					local height = self.Open and (#self.Items * 31 + math.max(#self.Items - 1, 0) * 4 + 70) or 64
					tween(row, { Size = UDim2.new(1, 0, 0, height) })
				end

				function control:Refresh(newItems)
					self.Items = newItems or {}
					for _, child in ipairs(optionsHolder:GetChildren()) do
						if child:IsA("GuiButton") then
							child:Destroy()
						end
					end
					for _, item in ipairs(self.Items) do
						local option = create(
							"TextButton",
							merge(textProperties(12), {
								BackgroundColor3 = Vertex.Theme.Background,
								BorderSizePixel = 0,
								Size = UDim2.new(1, 0, 0, 31),
								Text = tostring(item),
								AutoButtonColor = false,
							}),
							optionsHolder
						)
						addCorner(option, 5)
						addPadding(option, 0, 8, 0, 8)
						makeInteractive(option, Vertex.Theme.Background, Vertex.Theme.SurfaceHover)
						connect(option.MouseButton1Click, function()
							control:Set(item)
							control:SetOpen(false)
						end)
					end
					if self.Open then
						self:SetOpen(true)
					end
				end

				connect(selector.MouseButton1Click, function()
					control:SetOpen(not control.Open)
				end)
				control:Refresh(items)
				return control
			end

			function section:AddKeybind(options)
				options = options or {}
				local flag = options.Flag or options.Name or HttpService:GenerateGUID(false)
				local value = options.Default or Enum.KeyCode.Unknown
				Vertex.Flags[flag] = value

				local row = makeControl(self, options.Description and 54 or 44)
				controlLabel(row, options.Name or "Keybind", options.Description)
				local bindButton = create(
					"TextButton",
					merge(textProperties(11), {
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -12, 0.5, 0),
						Size = UDim2.fromOffset(88, 26),
						BackgroundColor3 = Vertex.Theme.Background,
						BorderSizePixel = 0,
						Text = value.Name,
						TextXAlignment = Enum.TextXAlignment.Center,
						AutoButtonColor = false,
					}),
					row
				)
				addCorner(bindButton, 5)
				addStroke(bindButton, Vertex.Theme.BorderSoft, 0.25)

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
						safeCall(options.Callback, newValue)
					end
				end
				connect(bindButton.MouseButton1Click, function()
					listening = true
					bindButton.Text = "..."
					tween(bindButton, { BackgroundColor3 = Vertex.Theme.SurfaceHover })
				end)
				connect(UserInputService.InputBegan, function(input)
					if listening and input.KeyCode ~= Enum.KeyCode.Unknown then
						listening = false
						control:Set(input.KeyCode)
						tween(bindButton, { BackgroundColor3 = Vertex.Theme.Background })
					elseif not listening and input.KeyCode == control.Value then
						safeCall(options.Pressed)
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
			ZIndex = 50,
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
		Size = UDim2.fromOffset(300, options.Description and 72 or 54),
		Position = UDim2.fromOffset(24, 0),
		ZIndex = 51,
	}, holder)
	addCorner(notification, 8)
	addStroke(notification, self.Theme.Border, 0.15)

	create("Frame", {
		BackgroundColor3 = options.Color or self.Theme.Accent,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(0, 3, 1, -20),
		ZIndex = 52,
	}, notification)

	create(
		"TextLabel",
		merge(textProperties(13), {
			Text = options.Title or "Notification",
			Position = UDim2.fromOffset(15, options.Description and 9 or 0),
			Size = UDim2.new(1, -28, options.Description and 0 or 1, options.Description and 22 or 0),
			ZIndex = 52,
		}),
		notification
	)

	if options.Description then
		create(
			"TextLabel",
			merge(textProperties(11, self.Theme.TextMuted), {
				Text = options.Description,
				Position = UDim2.fromOffset(15, 31),
				Size = UDim2.new(1, -28, 0, 30),
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 52,
			}),
			notification
		)
	end

	tween(notification, {
		BackgroundTransparency = 0,
		Position = UDim2.fromOffset(0, 0),
	})

	task.delay(options.Duration or 3, function()
		if not notification.Parent then
			return
		end
		local closing = tween(notification, {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(24, 0),
		})
		closing.Completed:Wait()
		notification:Destroy()
	end)

	return notification
end

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
