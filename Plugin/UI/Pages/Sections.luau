--[[
	Factory for schema-driven section pages (Atmosphere, Lighting, Water).
	Each page is a list of PropertyEditors generated from registry schemas.
]]
local Theme = require(script.Parent.Parent.Theme)
local PropertyEditor = require(script.Parent.Parent.PropertyEditor)

local Sections = {}

--[[
	specs: { { Title, Path = { ... }, Fields = fields, Live = fn } }
]]
function Sections.Page(name: string, description: string, specs)
	return function(context)
		local ui, controller = context.UI, context.Controller
		local frame = ui:Stack(Theme.Spacing.Medium)
		local page = { Name = name, Frame = frame, Editors = {} }
		ui:Label(description, { Dim = true, LayoutOrder = 0 }).Parent = frame
		for index, spec in ipairs(specs(context)) do
			local editor = PropertyEditor.new(ui, controller, spec.Path, spec.Fields, {
				Title = spec.Title,
				Live = spec.Live,
				LayoutOrder = index,
				Collapsed = spec.Collapsed,
				Exclude = spec.Exclude,
			})
			editor.Frame.Parent = frame
			table.insert(page.Editors, editor)
		end
		function page:Refresh()
			for _, editor in ipairs(page.Editors) do
				editor:Refresh()
			end
		end
		return page
	end
end

return Sections
