--[[
	VisualFX Studio application shell:

	  ┌──────────────────────────────────────────┐
	  │ VisualFX            [ search settings… ] │
	  ├──────────┬───────────────────────────────┤
	  │ Overview │                               │
	  │ Scene    │   page content (scrolling)    │
	  │ …        │                               │
	  ├──────────┴───────────────────────────────┤
	  │ ✓ status / warnings   Preview [Apply][Revert] │
	  └──────────────────────────────────────────┘

	Pages are created lazily and refreshed (debounced) when the controller
	reports a change.
]]

local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Pages = script.Parent.Pages

local App = {}
App.__index = App

App.PageOrder = {
	{ Name = "Overview", Module = "Overview" },
	{ Name = "Scene", Module = "Scene" },
	{ Name = "Atmosphere", Module = "Atmosphere" },
	{ Name = "Lighting", Module = "Lighting" },
	{ Name = "Water", Module = "Water" },
	{ Name = "Particles", Module = "Particles" },
	{ Name = "Weather", Module = "Weather" },
	{ Name = "Presets", Module = "Presets" },
	{ Name = "Transitions", Module = "Transitions" },
	{ Name = "AI Director", Module = "Director" },
	{ Name = "Inspector", Module = "Inspector" },
	{ Name = "Code", Module = "Code" },
	{ Name = "Settings", Module = "Settings" },
}

function App.new(widget: Instance, controller, library: Instance)
	local self = setmetatable({}, App)
	self.Widget = widget
	self.Controller = controller
	self.Library = library
	self.Pages = {}
	self.Current = nil
	self.Search = ""
	self._dirty = false
	self._connections = {}
	self:Build()
	table.insert(self._connections, controller.Changed:Connect(function()
		self._dirty = true
	end))
	local themeConnection = Theme.OnChanged(function()
		self:Rebuild()
	end)
	if themeConnection then
		table.insert(self._connections, themeConnection)
	end
	local elapsed = 0
	table.insert(self._connections, game:GetService("RunService").Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.2 then
			return
		end
		elapsed = 0
		self:Tick()
	end))
	return self
end

function App:Build()
	local ui = Components.new(Theme.Palette())
	self.UI = ui
	local palette = ui.Palette

	local root = ui:Create("Frame", {
		Name = "VisualFXRoot",
		BackgroundColor3 = palette.Background,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
	})
	self.Root = root

	-- Top bar
	local topBar = ui:Create("Frame", {
		BackgroundColor3 = palette.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 36),
		Parent = root,
	}, { ui:Padding(6, 8) })
	local title = ui:Label("VisualFX Studio", { Heading = true, Size = UDim2.new(0, 140, 1, 0), Wrap = false })
	title.Parent = topBar
	local search = ui:TextInput("", function(text)
		self.Search = string.lower(text)
		self:ApplySearch()
	end, { Placeholder = "Search settings…" })
	search.Instance.AnchorPoint = Vector2.new(1, 0)
	search.Instance.Position = UDim2.new(1, 0, 0, 0)
	search.Instance.Size = UDim2.new(1, -150, 1, 0)
	search.Instance.Parent = topBar
	table.insert(self._connections, search.Instance:GetPropertyChangedSignal("Text"):Connect(function()
		self.Search = string.lower(search.Instance.Text)
		self:ApplySearch()
	end))

	-- Sidebar
	local sidebar = ui:Create("ScrollingFrame", {
		BackgroundColor3 = palette.Panel,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 36),
		Size = UDim2.new(0, 116, 1, -36 - 34),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Parent = root,
	}, { ui:VerticalList(1), ui:Padding(4) })
	self.NavButtons = {}
	for index, entry in ipairs(App.PageOrder) do
		local button = ui:Create("TextButton", {
			Text = "  " .. entry.Name,
			Font = Theme.Fonts.Body,
			TextSize = Theme.TextSize.Body,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = palette.Text,
			BackgroundColor3 = palette.Panel,
			AutoButtonColor = true,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = index,
			Parent = sidebar,
		}, { ui:Corner(3) })
		ui:Track(button.MouseButton1Click:Connect(function()
			self:Navigate(entry.Name)
		end))
		self.NavButtons[entry.Name] = button
	end

	-- Content
	local content = ui:Create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 116, 0, 36),
		Size = UDim2.new(1, -116, 1, -36 - 34),
		ClipsDescendants = true,
		Parent = root,
	})
	self.Content = content

	-- Status bar
	local status = ui:Create("Frame", {
		BackgroundColor3 = palette.Panel,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -34),
		Size = UDim2.new(1, 0, 0, 34),
		Parent = root,
	}, { ui:Padding(4, 8) })
	self.StatusLabel = ui:Label("Ready", { Size = UDim2.new(1, -190, 1, 0), Wrap = false, TextSize = Theme.TextSize.Small })
	self.StatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	self.StatusLabel.Parent = status
	local actions = ui:Create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 186, 1, 0),
		Parent = status,
	}, { ui:HorizontalList(4) })
	actions:FindFirstChildOfClass("UIListLayout").HorizontalAlignment = Enum.HorizontalAlignment.Right
	self.PreviewButton = ui:Button("Preview", function()
		self.Controller:PreviewPending()
	end, { LayoutOrder = 1 })
	self.ApplyButton = ui:Button("Apply", function()
		self.Controller:Apply()
	end, { Style = "Primary", LayoutOrder = 2 })
	self.RevertButton = ui:Button("Revert", function()
		self.Controller:Revert()
	end, { Style = "Danger", LayoutOrder = 3 })
	self.PreviewButton.Parent = actions
	self.ApplyButton.Parent = actions
	self.RevertButton.Parent = actions

	root.Parent = self.Widget
	self:Navigate(self.Controller.Settings.LastPage or "Overview")
	self:UpdateStatus()
end

function App:Rebuild()
	local current = self.Current
	for _, page in pairs(self.Pages) do
		if page.Frame then
			page.Frame:Destroy()
		end
	end
	self.Pages = {}
	if self.Root then
		self.Root:Destroy()
	end
	self.UI:Destroy()
	self.Current = nil
	self.Controller.Settings.LastPage = current or "Overview"
	self:Build()
end

function App:_CreatePage(name: string)
	local entry
	for _, candidate in ipairs(App.PageOrder) do
		if candidate.Name == name then
			entry = candidate
		end
	end
	if not entry then
		return nil
	end
	local factory = require(Pages[entry.Module])
	local context = {
		UI = self.UI,
		Controller = self.Controller,
		Engine = self.Controller.Engine,
		Library = self.Library,
		Navigate = function(target)
			self:Navigate(target)
		end,
	}
	local ok, page = pcall(factory, context)
	if not ok then
		warn("[VisualFX Studio] failed to build page " .. name .. ": " .. tostring(page))
		page = { Name = name, Frame = self.UI:Label("This page failed to load:\n" .. tostring(page), { Color = self.UI.Palette.Error }) }
	end
	local scroll = self.UI:ScrollFrame()
	scroll.Visible = false
	scroll.Parent = self.Content
	page.Frame.Parent = scroll
	page.Scroll = scroll
	self.Pages[name] = page
	return page
end

function App:Navigate(name: string)
	local page = self.Pages[name] or self:_CreatePage(name)
	if not page then
		return
	end
	for pageName, other in pairs(self.Pages) do
		other.Scroll.Visible = pageName == name
	end
	for buttonName, button in pairs(self.NavButtons) do
		button.BackgroundColor3 = if buttonName == name then self.UI.Palette.Selected else self.UI.Palette.Panel
	end
	self.Current = name
	if self.Controller.Settings.LastPage ~= name then
		self.Controller:SetSetting("LastPage", name)
	end
	self:RefreshCurrent()
	self:ApplySearch()
end

function App:RefreshCurrent()
	local page = self.Pages[self.Current]
	if page and page.Refresh then
		local ok, problem = pcall(page.Refresh, page)
		if not ok then
			warn("[VisualFX Studio] " .. tostring(self.Current) .. " refresh failed: " .. tostring(problem))
		end
	end
end

-- Hides rows whose label/description does not match the search text.
function App:ApplySearch()
	local page = self.Pages[self.Current]
	if not page then
		return
	end
	local query = self.Search
	for _, descendant in ipairs(page.Frame:GetDescendants()) do
		local text = descendant:GetAttribute("SearchText")
		if text then
			descendant.Visible = query == "" or string.find(text, query, 1, true) ~= nil
		end
	end
end

function App:UpdateStatus()
	local controller = self.Controller
	local result = controller.LastResult
	local text, color = "Ready", self.UI.Palette.SubText
	if result then
		local errors = result.Errors and #result.Errors or 0
		local warnings = result.Warnings and #result.Warnings or 0
		if errors > 0 then
			text = "✕ " .. tostring(result.Errors[1])
			color = self.UI.Palette.Error
		elseif warnings > 0 then
			text = string.format("⚠ %d warning%s — %s", warnings, if warnings == 1 then "" else "s", tostring(result.Warnings[1]))
			color = self.UI.Palette.Warning
		else
			text = "✓ " .. tostring(result.Action or "Done")
			color = self.UI.Palette.Success
		end
	end
	if controller.Pending then
		text = "Unpreviewed edits — press Preview"
		color = self.UI.Palette.Warning
	elseif controller:IsPreviewing() then
		text = "Previewing • " .. text
	end
	self.StatusLabel.Text = text
	self.StatusLabel.TextColor3 = color
	local previewing = controller:IsPreviewing()
	self.PreviewButton.Visible = controller.Pending ~= nil
	self.ApplyButton.Visible = previewing or controller.Pending ~= nil
	self.RevertButton.Visible = previewing or controller.Pending ~= nil
end

function App:Tick()
	local page = self.Pages[self.Current]
	if page and page.Tick then
		pcall(page.Tick)
	end
	if self._dirty then
		self._dirty = false
		self:UpdateStatus()
		self:RefreshCurrent()
		self:ApplySearch()
	end
end

function App:Destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self.UI:Destroy()
	if self.Root then
		self.Root:Destroy()
	end
end

return App
