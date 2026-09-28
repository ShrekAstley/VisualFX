--[[
	VisualFX Studio UI components. Plain Roblox GUI objects (Frame, TextBox,
	UIListLayout, ...) with a small controller object per control:

	  local control = ui:Slider(0.5, 0, 1, function(value) ... end)
	  control.Instance.Parent = row
	  control:Set(0.25)          -- update without firing the callback

	Inline expansion (dropdown lists, color pickers) is used instead of
	floating overlays so controls work inside scrolling dock widgets.
]]

local Theme = require(script.Parent.Theme)

local Components = {}
Components.__index = Components

function Components.new(palette)
	local self = setmetatable({}, Components)
	self.Palette = palette or Theme.Palette()
	self.Connections = {}
	return self
end

function Components:Track(connection)
	table.insert(self.Connections, connection)
	return connection
end

function Components:Destroy()
	for _, connection in ipairs(self.Connections) do
		connection:Disconnect()
	end
	table.clear(self.Connections)
end

-- Creates an instance, applies properties and parents children.
function Components:Create(className: string, properties: { [string]: any }?, children: { Instance }?)
	local instance = Instance.new(className)
	for key, value in pairs(properties or {}) do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	if properties and properties.Parent then
		instance.Parent = properties.Parent
	end
	return instance
end

function Components:Corner(radius: number?)
	return self:Create("UICorner", { CornerRadius = UDim.new(0, radius or 4) })
end

function Components:Stroke(color: Color3?, thickness: number?)
	return self:Create("UIStroke", {
		Color = color or self.Palette.InputBorder,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Components:Padding(all: number, horizontal: number?)
	return self:Create("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, horizontal or all),
		PaddingRight = UDim.new(0, horizontal or all),
	})
end

function Components:VerticalList(padding: number?)
	return self:Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, padding or Theme.Spacing.Small),
	})
end

function Components:HorizontalList(padding: number?)
	return self:Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, padding or Theme.Spacing.Small),
	})
end

-- A transparent, auto-height vertical container.
function Components:Stack(padding: number?, layoutOrder: number?)
	return self:Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = layoutOrder or 0,
	}, { self:VerticalList(padding) })
end

function Components:Label(text: string, options: { [string]: any }?)
	local opts = options or {}
	return self:Create("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = opts.Color or (if opts.Dim then self.Palette.SubText else self.Palette.Text),
		Font = opts.Font or (if opts.Heading then Theme.Fonts.Heading else Theme.Fonts.Body),
		TextSize = opts.TextSize or (if opts.Heading then Theme.TextSize.Heading else Theme.TextSize.Body),
		TextXAlignment = opts.Align or Enum.TextXAlignment.Left,
		TextWrapped = opts.Wrap ~= false,
		RichText = opts.RichText == true,
		Size = opts.Size or UDim2.new(1, 0, 0, 0),
		AutomaticSize = if opts.Size then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
		LayoutOrder = opts.LayoutOrder or 0,
	})
end

local BUTTON_STYLES = {
	Primary = { Background = "Accent", Text = "AccentText" },
	Secondary = { Background = "Button", Text = "ButtonText" },
	Danger = { Background = "Error", Text = "AccentText" },
	Ghost = { Background = nil, Text = "Accent" },
}

function Components:Button(text: string, onClick: (() -> ())?, options: { [string]: any }?)
	local opts = options or {}
	local style = BUTTON_STYLES[opts.Style or "Secondary"]
	local background = style.Background and self.Palette[style.Background] or self.Palette.Button
	local button = self:Create("TextButton", {
		Text = text,
		Font = Theme.Fonts.Strong,
		TextSize = Theme.TextSize.Body,
		TextColor3 = self.Palette[style.Text],
		BackgroundColor3 = background,
		BackgroundTransparency = if style.Background then 0 else 1,
		AutoButtonColor = true,
		Size = opts.Size or UDim2.new(0, 0, 0, Theme.RowHeight),
		AutomaticSize = if opts.Size then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
		LayoutOrder = opts.LayoutOrder or 0,
	}, { self:Corner(4), self:Padding(0, 10) })
	if opts.Tooltip then
		button:SetAttribute("Tooltip", opts.Tooltip)
	end
	if onClick then
		self:Track(button.MouseButton1Click:Connect(onClick))
	end
	return button
end

-- A row of buttons.
function Components:ButtonBar(buttons: { Instance }, layoutOrder: number?)
	local bar = self:Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.RowHeight),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = layoutOrder or 0,
	}, { self:HorizontalList(Theme.Spacing.Small) })
	for index, button in ipairs(buttons) do
		button.LayoutOrder = index
		button.Parent = bar
	end
	return bar
end

--[[
	Single-line text input. onCommit(text) fires on Enter or focus loss.
]]
function Components:TextInput(text: string, onCommit: ((string) -> ())?, options: { [string]: any }?)
	local opts = options or {}
	local box = self:Create("TextBox", {
		Text = text or "",
		PlaceholderText = opts.Placeholder or "",
		PlaceholderColor3 = self.Palette.SubText,
		Font = opts.Font or Theme.Fonts.Body,
		TextSize = Theme.TextSize.Body,
		TextColor3 = self.Palette.Text,
		BackgroundColor3 = self.Palette.Input,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = opts.Size or UDim2.new(1, 0, 0, Theme.RowHeight - 2),
		LayoutOrder = opts.LayoutOrder or 0,
	}, { self:Corner(3), self:Padding(0, 6) })
	local stroke = self:Stroke()
	stroke.Parent = box
	local control = { Instance = box, Stroke = stroke }
	function control:Set(value: string)
		if not box:IsFocused() then
			box.Text = value
		end
	end
	function control:Get(): string
		return box.Text
	end
	function control.SetInvalid(_, invalid: boolean)
		stroke.Color = if invalid then self.Palette.Error else self.Palette.InputBorder
	end
	if onCommit then
		self:Track(box.FocusLost:Connect(function()
			onCommit(box.Text)
		end))
	end
	return control
end

-- Multi-line text/code area.
function Components:CodeBox(text: string, options: { [string]: any }?)
	local opts = options or {}
	local scroll = self:Create("ScrollingFrame", {
		BackgroundColor3 = self.Palette.Input,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, opts.Height or 220),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.XY,
		ScrollBarThickness = 8,
		ScrollingDirection = Enum.ScrollingDirection.XY,
		LayoutOrder = opts.LayoutOrder or 0,
	}, { self:Corner(3) })
	local box = self:Create("TextBox", {
		Text = text or "",
		Font = Theme.Fonts.Code,
		TextSize = Theme.TextSize.Small,
		TextColor3 = self.Palette.Text,
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		MultiLine = true,
		TextEditable = opts.Editable ~= false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Parent = scroll,
	}, { self:Padding(6) })
	local control = { Instance = scroll, TextBox = box }
	function control:Set(value: string)
		box.Text = value
	end
	function control:Get(): string
		return box.Text
	end
	-- Focus and select everything so the user can press Ctrl+C.
	function control:SelectAll()
		pcall(function()
			box:CaptureFocus()
			box.SelectionStart = 1
			box.CursorPosition = #box.Text + 1
		end)
	end
	return control
end

local function formatNumber(value: number, integer: boolean?): string
	if integer then
		return tostring(math.floor(value + 0.5))
	end
	local text = string.format("%.3f", value)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end
Components.formatNumber = formatNumber

-- Numeric input. Invalid text is flagged and not committed.
function Components:NumberInput(value: number, onCommit: ((number) -> ())?, options: { [string]: any }?)
	local opts = options or {}
	local control
	control = self:TextInput(formatNumber(value or 0, opts.Integer), function(text)
		local number = tonumber(text)
		if number == nil or number ~= number then
			control:SetInvalid(true)
			return
		end
		if opts.Min then
			number = math.max(opts.Min, number)
		end
		if opts.Max then
			number = math.min(opts.Max, number)
		end
		if opts.Integer then
			number = math.floor(number + 0.5)
		end
		control:SetInvalid(false)
		control.Instance.Text = formatNumber(number, opts.Integer)
		if onCommit then
			onCommit(number)
		end
	end, { Size = opts.Size or UDim2.new(0, 64, 0, Theme.RowHeight - 2), LayoutOrder = opts.LayoutOrder, Font = Theme.Fonts.Code })
	control.Instance.TextXAlignment = Enum.TextXAlignment.Right
	local baseSet = control.Set
	function control:Set(number: number)
		baseSet(control, formatNumber(number, opts.Integer))
	end
	return control
end

--[[
	Slider with an attached numeric field. Click or drag on the track.
	onChange(value, final) - final is true when a drag ends or a value is typed.
]]
function Components:Slider(value: number, min: number, max: number, onChange: (number, boolean) -> (), options: { [string]: any }?)
	local opts = options or {}
	local current = value or min
	local container = self:Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.RowHeight - 2),
		LayoutOrder = opts.LayoutOrder or 0,
	})
	local track = self:Create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = self.Palette.Input,
		Size = UDim2.new(1, -72, 0, 6),
		Position = UDim2.new(0, 0, 0.5, -3),
		Parent = container,
	}, { self:Corner(3) })
	local fill = self:Create("Frame", {
		BackgroundColor3 = self.Palette.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		Parent = track,
	}, { self:Corner(3) })
	local knob = self:Create("Frame", {
		BackgroundColor3 = self.Palette.Text,
		Size = UDim2.new(0, 10, 0, 14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Parent = track,
	}, { self:Corner(3) })

	local control = { Instance = container }
	local number

	local function render()
		local alpha = if max > min then math.clamp((current - min) / (max - min), 0, 1) else 0
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
	end

	local function quantize(raw: number): number
		local result = math.clamp(raw, min, max)
		if opts.Integer then
			result = math.floor(result + 0.5)
		elseif opts.Step then
			result = math.floor(result / opts.Step + 0.5) * opts.Step
		else
			result = math.floor(result * 1000 + 0.5) / 1000
		end
		return result
	end

	number = self:NumberInput(current, function(typed)
		current = quantize(typed)
		render()
		onChange(current, true)
	end, { Min = min, Max = max, Integer = opts.Integer, Size = UDim2.new(0, 64, 1, 0) })
	number.Instance.Position = UDim2.new(1, -64, 0, 0)
	number.Instance.Parent = container

	local dragging = false
	local function setFromX(x: number, final: boolean)
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local alpha = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		local newValue = quantize(min + (max - min) * alpha)
		if newValue ~= current or final then
			current = newValue
			render()
			number:Set(current)
			onChange(current, final)
		end
	end

	self:Track(track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			setFromX(input.Position.X, false)
		end
	end))
	self:Track(track.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			setFromX(input.Position.X, false)
		end
	end))
	self:Track(track.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
			dragging = false
			setFromX(input.Position.X, true)
		end
	end))
	self:Track(track.MouseLeave:Connect(function()
		if dragging then
			dragging = false
			onChange(current, true)
		end
	end))

	function control:Set(newValue: number)
		if dragging then
			return
		end
		current = newValue
		render()
		number:Set(newValue)
	end
	function control:Get(): number
		return current
	end
	render()
	return control
end

function Components:Toggle(value: boolean, onChange: (boolean) -> (), options: { [string]: any }?)
	local opts = options or {}
	local state = value == true
	local button = self:Create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(0, 36, 0, 18),
		BackgroundColor3 = self.Palette.Input,
		LayoutOrder = opts.LayoutOrder or 0,
	}, { self:Corner(9) })
	local dot = self:Create("Frame", {
		Size = UDim2.new(0, 14, 0, 14),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = self.Palette.SubText,
		Parent = button,
	}, { self:Corner(7) })
	local control = { Instance = button }
	local function render()
		button.BackgroundColor3 = if state then self.Palette.Accent else self.Palette.Input
		dot.BackgroundColor3 = if state then self.Palette.AccentText else self.Palette.SubText
		dot.Position = if state then UDim2.new(1, -16, 0.5, 0) else UDim2.new(0, 2, 0.5, 0)
	end
	self:Track(button.MouseButton1Click:Connect(function()
		state = not state
		render()
		onChange(state)
	end))
	function control:Set(newValue: boolean)
		state = newValue == true
		render()
	end
	function control:Get(): boolean
		return state
	end
	render()
	return control
end

--[[
	Dropdown that expands inline. options: list of strings.
]]
function Components:Dropdown(choices: { string }, value: string?, onChange: (string) -> (), options: { [string]: any }?)
	local opts = options or {}
	local selected = value
	local container = self:Create("Frame", {
		BackgroundTransparency = 1,
		Size = opts.Size or UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = opts.LayoutOrder or 0,
	}, { self:VerticalList(1) })
	local header = self:Create("TextButton", {
		Text = "",
		AutoButtonColor = true,
		BackgroundColor3 = self.Palette.Input,
		Size = UDim2.new(1, 0, 0, Theme.RowHeight - 2),
		LayoutOrder = 0,
		Parent = container,
	}, { self:Corner(3), self:Padding(0, 6) })
	self:Stroke().Parent = header
	local caption = self:Label(selected or opts.Placeholder or "Select…", {
		Size = UDim2.new(1, -14, 1, 0),
		Wrap = false,
	})
	caption.Parent = header
	local arrow = self:Label("▾", { Size = UDim2.new(0, 14, 1, 0), Align = Enum.TextXAlignment.Right, Dim = true })
	arrow.Position = UDim2.new(1, -14, 0, 0)
	arrow.Parent = header
	local list = self:Create("Frame", {
		BackgroundColor3 = self.Palette.PanelAlt,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		LayoutOrder = 1,
		Parent = container,
	}, { self:VerticalList(0), self:Corner(3) })
	local control = { Instance = container, Choices = choices }

	local function rebuild()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		for index, choice in ipairs(control.Choices) do
			local item = self:Create("TextButton", {
				Text = "  " .. choice,
				Font = if choice == selected then Theme.Fonts.Strong else Theme.Fonts.Body,
				TextSize = Theme.TextSize.Body,
				TextColor3 = self.Palette.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundColor3 = if choice == selected then self.Palette.Selected else self.Palette.PanelAlt,
				AutoButtonColor = true,
				Size = UDim2.new(1, 0, 0, 22),
				LayoutOrder = index,
				Parent = list,
			})
			self:Track(item.MouseButton1Click:Connect(function()
				selected = choice
				caption.Text = choice
				list.Visible = false
				onChange(choice)
			end))
		end
	end

	self:Track(header.MouseButton1Click:Connect(function()
		if not list.Visible then
			rebuild()
		end
		list.Visible = not list.Visible
	end))

	function control:Set(newValue: string?)
		selected = newValue
		caption.Text = newValue or opts.Placeholder or "Select…"
	end
	function control:Get(): string?
		return selected
	end
	function control:SetChoices(newChoices: { string })
		control.Choices = newChoices
		if list.Visible then
			rebuild()
		end
	end
	return control
end

--[[
	Color picker: a swatch that expands inline to R/G/B sliders and a hex field.
]]
function Components:ColorPicker(color: Color3, onChange: (Color3, boolean) -> (), options: { [string]: any }?)
	local opts = options or {}
	local current = color or Color3.new(1, 1, 1)
	local container = self:Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = opts.LayoutOrder or 0,
	}, { self:VerticalList(2) })
	local header = self:Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.RowHeight - 2),
		LayoutOrder = 0,
		Parent = container,
	}, { self:HorizontalList(6) })
	local swatch = self:Create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = current,
		Size = UDim2.new(0, 40, 0, 18),
		LayoutOrder = 0,
		Parent = header,
	}, { self:Corner(3) })
	self:Stroke().Parent = swatch
	local control = { Instance = container }
	local hex
	hex = self:TextInput(current:ToHex(), function(text)
		local ok, parsed = pcall(Color3.fromHex, text)
		if ok and parsed then
			hex:SetInvalid(false)
			control:Set(parsed)
			onChange(parsed, true)
		else
			hex:SetInvalid(true)
		end
	end, { Size = UDim2.new(0, 80, 0, Theme.RowHeight - 2), LayoutOrder = 1, Font = Theme.Fonts.Code })
	hex.Instance.Parent = header

	local panel = self:Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		LayoutOrder = 1,
		Parent = container,
	}, { self:VerticalList(2) })

	local channels = {}
	local function channelValues()
		return math.floor(current.R * 255 + 0.5), math.floor(current.G * 255 + 0.5), math.floor(current.B * 255 + 0.5)
	end
	for index, channel in ipairs({ "R", "G", "B" }) do
		local row = self:Create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, Theme.RowHeight - 2),
			LayoutOrder = index,
			Parent = panel,
		})
		local label = self:Label(channel, { Size = UDim2.new(0, 14, 1, 0), Dim = true })
		label.Parent = row
		local values = { channelValues() }
		local slider = self:Slider(values[index], 0, 255, function(newValue, final)
			local r, g, b = channelValues()
			if channel == "R" then
				r = newValue
			elseif channel == "G" then
				g = newValue
			else
				b = newValue
			end
			current = Color3.fromRGB(r, g, b)
			swatch.BackgroundColor3 = current
			hex:Set(current:ToHex())
			onChange(current, final)
		end, { Integer = true })
		slider.Instance.Size = UDim2.new(1, -18, 1, 0)
		slider.Instance.Position = UDim2.new(0, 18, 0, 0)
		slider.Instance.Parent = row
		channels[channel] = slider
	end

	self:Track(swatch.MouseButton1Click:Connect(function()
		panel.Visible = not panel.Visible
	end))

	function control:Set(newColor: Color3)
		current = newColor
		swatch.BackgroundColor3 = newColor
		hex:Set(newColor:ToHex())
		local r, g, b = channelValues()
		channels.R:Set(r)
		channels.G:Set(g)
		channels.B:Set(b)
	end
	function control:Get(): Color3
		return current
	end
	return control
end

--[[
	Collapsible section: { Frame, Content, SetCollapsed(bool), Title }.
]]
function Components:Section(title: string, options: { [string]: any }?)
	local opts = options or {}
	local frame = self:Create("Frame", {
		BackgroundColor3 = self.Palette.Panel,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = opts.LayoutOrder or 0,
	}, { self:VerticalList(0), self:Corner(4) })
	local header = self:Create("TextButton", {
		Text = "",
		AutoButtonColor = true,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 0,
		Parent = frame,
	}, { self:Padding(0, 8) })
	local chevron = self:Label("▾", { Size = UDim2.new(0, 14, 1, 0), Dim = true, Wrap = false })
	chevron.Parent = header
	local titleLabel = self:Label(title, { Size = UDim2.new(1, -18, 1, 0), Font = Theme.Fonts.Strong, Wrap = false })
	titleLabel.Position = UDim2.new(0, 18, 0, 0)
	titleLabel.Parent = header
	local content = self:Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = frame,
	}, { self:VerticalList(Theme.Spacing.Small), self:Padding(Theme.Spacing.Medium) })
	local section = { Frame = frame, Content = content, Title = title, Collapsed = false }
	function section:SetCollapsed(collapsed: boolean)
		section.Collapsed = collapsed
		content.Visible = not collapsed
		chevron.Text = if collapsed then "▸" else "▾"
	end
	self:Track(header.MouseButton1Click:Connect(function()
		section:SetCollapsed(not section.Collapsed)
	end))
	section:SetCollapsed(opts.Collapsed == true)
	return section
end

--[[
	Labelled row. `control` is placed on the right. The row carries the label
	text in an attribute so the search box can filter rows.
]]
function Components:Row(label: string, control: Instance?, options: { [string]: any }?)
	local opts = options or {}
	local row = self:Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.RowHeight),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = opts.LayoutOrder or 0,
	})
	row:SetAttribute("SearchText", string.lower(label .. " " .. (opts.SearchExtra or "")))
	local labelWidth = opts.LabelWidth or 0.38
	local text = self:Label(label, {
		Size = UDim2.new(labelWidth, -4, 0, Theme.RowHeight),
		Dim = opts.Unset == true,
		Wrap = false,
	})
	text.TextTruncate = Enum.TextTruncate.AtEnd
	text.Parent = row
	local holder = self:Create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(labelWidth, 0, 0, 1),
		Size = UDim2.new(1 - labelWidth, 0, 0, Theme.RowHeight - 2),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = row,
	})
	if control then
		control.Parent = holder
	end
	return row, holder, text
end

local SEVERITY_COLORS = { Error = "Error", Warning = "Warning", Info = "Info", Success = "Success" }

function Components:Badge(text: string, severity: string?, layoutOrder: number?)
	local color = self.Palette[SEVERITY_COLORS[severity or "Info"] or "Info"]
	return self:Create("TextLabel", {
		Text = " " .. text .. " ",
		Font = Theme.Fonts.Strong,
		TextSize = Theme.TextSize.Small,
		TextColor3 = self.Palette.AccentText,
		BackgroundColor3 = color,
		Size = UDim2.new(0, 0, 0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = layoutOrder or 0,
	}, { self:Corner(9) })
end

-- A message line with a colored severity marker.
function Components:Message(text: string, severity: string?, layoutOrder: number?)
	local marks = { Error = "✕", Warning = "⚠", Info = "ℹ", Success = "✓" }
	local color = self.Palette[SEVERITY_COLORS[severity or "Info"] or "Info"]
	return self:Label((marks[severity or "Info"] or "•") .. "  " .. text, { Color = color, LayoutOrder = layoutOrder, TextSize = Theme.TextSize.Small })
end

function Components:ScrollFrame()
	return self:Create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, { self:VerticalList(Theme.Spacing.Medium), self:Padding(Theme.Spacing.Medium) })
end

return Components
