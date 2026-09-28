return function(t)
	local expect = t.expect
	local examples = game:GetService("ReplicatedStorage"):FindFirstChild("VisualFXExamples")

	t.describe("Examples", function()
		t.it("the agent workflow example completes every step", function()
			if not examples then
				return
			end
			local engine = t.newEngine()
			local workflow = require(examples.AgentWorkflow)
			local report = workflow(engine, function(dt)
				engine:Step(dt)
			end)
			for _, entry in ipairs(report.Steps) do
				if not entry.Success then
					error(entry.Step .. ": " .. table.concat(entry.Errors or {}, "; "))
				end
			end
			expect(report.Success).toBe(true)
			expect(#report.Diff).toBeGreaterThan(0)
			expect(report.Json).toContain('"HeavyRain"')
			expect(report.Code).toContain("VisualFX:CreateScene(Configuration)")
			expect(t.Services.Lighting.ClockTime).toBeCloseTo(19.2, 1 / 600)
		end)

		t.it("the Beacon custom effect registers and updates", function()
			if not examples then
				return
			end
			local engine = t.newEngine()
			expect(engine:RegisterEffect(require(examples.Beacon)).Success).toBe(true)
			local created = engine:CreateEffect("HarborBeacon", { Effect = "Beacon", Position = Vector3.new(40, 12, -30), Range = 30 })
			expect(created.Success).toBe(true)
			local part = engine.InstanceManager:Find("effect.HarborBeacon")
			expect(part:FindFirstChildOfClass("PointLight").Range).toBe(30)
			engine:CreateEffect("HarborBeacon", { Effect = "Beacon", Position = Vector3.new(0, 12, 0), Range = 45 })
			expect(part:FindFirstChildOfClass("PointLight").Range).toBe(45)
			expect(part.Position).toBe(Vector3.new(0, 12, 0))
		end)
	end)
end
