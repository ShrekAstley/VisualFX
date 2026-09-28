--[[
	Creates the VisualFX Studio toolbar and its toggle button.
]]

local Toolbar = {}

function Toolbar.create(plugin: Plugin)
	local toolbar = plugin:CreateToolbar("VisualFX Studio")
	-- No bundled icon asset: Studio shows the "VisualFX" text label instead.
	-- Upload an icon and pass its rbxassetid:// here to customize it.
	local button = toolbar:CreateButton("VisualFXToggle", "Open the VisualFX environment editor", "", "VisualFX")
	button.ClickableWhenViewportHidden = true
	return {
		Toolbar = toolbar,
		Button = button,
	}
end

return Toolbar
