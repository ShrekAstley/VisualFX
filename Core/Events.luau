--[[
	VisualFX.Core.Events

	Lightweight signal implementation (no BindableEvents, so handlers receive
	tables by reference and nothing is serialized), plus the event bus used by
	the runtime.

	  VisualFX.Events.Changed:Connect(function(result) ... end)
	  VisualFX.Events.AudioHook:Connect(function(hook) ... end)
]]

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local handlers = self._signal._handlers
	local index = table.find(handlers, self)
	if index then
		table.remove(handlers, index)
	end
end
Connection.Destroy = Connection.Disconnect

function Signal.new(name: string?)
	return setmetatable({ Name = name or "Signal", _handlers = {} }, Signal)
end

function Signal:Connect(handler: (...any) -> ())
	assert(typeof(handler) == "function", "Signal:Connect expects a function")
	local connection = setmetatable({ Connected = true, _signal = self, _handler = handler }, Connection)
	table.insert(self._handlers, connection)
	return connection
end

function Signal:Once(handler: (...any) -> ())
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

--[[
	Fires handlers in connection order. A failing handler is reported with
	warn() but never interrupts VisualFX or the other handlers.
]]
function Signal:Fire(...: any)
	local snapshot = table.clone(self._handlers)
	for _, connection in ipairs(snapshot) do
		if connection.Connected then
			local ok, problem = pcall(connection._handler, ...)
			if not ok then
				warn(string.format("[VisualFX] %s handler error: %s", self.Name, tostring(problem)))
			end
		end
	end
end

function Signal:DisconnectAll()
	for _, connection in ipairs(table.clone(self._handlers)) do
		connection:Disconnect()
	end
end

function Signal:GetConnectionCount(): number
	return #self._handlers
end

local Events = {}
Events.Signal = Signal

-- Names of every event exposed on VisualFX.Events.
Events.Names = {
	"Changed", -- (result) after any successful mutation
	"EffectCreated", -- ({ ID, Type, Instance })
	"EffectRemoved", -- ({ ID, Type })
	"TransitionStarted", -- ({ Id, Duration })
	"TransitionCompleted", -- ({ Id, Cancelled })
	"WeatherChanged", -- ({ Previous, Current, Intensity })
	"LightningStrike", -- ({ Intensity, Position?, Time })
	"AudioHook", -- ({ Hook, Action = "Start" | "Stop" | "Update" | "Trigger", Volume })
	"QualityChanged", -- ({ Level, Profile })
	"Warning", -- (message)
}

function Events.newBus()
	local bus = {}
	for _, name in ipairs(Events.Names) do
		bus[name] = Signal.new(name)
	end
	return bus
end

function Events.destroyBus(bus)
	for _, name in ipairs(Events.Names) do
		if bus[name] then
			bus[name]:DisconnectAll()
		end
	end
end

return Events
