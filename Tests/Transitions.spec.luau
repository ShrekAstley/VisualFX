return function(t)
	local expect = t.expect

	local function run(engine, seconds, step)
		local dt = step or 0.05
		local elapsed = 0
		while elapsed < seconds - 1e-9 do
			engine:Step(dt)
			elapsed += dt
		end
	end

	t.describe("Transitions", function()
		t.it("interpolates numbers and colors over the duration", function()
			local engine = t.newEngine()
			local lighting = t.Services.Lighting
			engine:SetLighting({ Brightness = 1, OutdoorAmbient = Color3.fromRGB(0, 0, 0) })
			local result = engine:TransitionTo({
				Duration = 2,
				Easing = "Linear",
				Configuration = { Lighting = { Brightness = 3, OutdoorAmbient = Color3.fromRGB(200, 100, 0) } },
			})
			expect(result.Success).toBe(true)
			expect(engine:IsTransitioning()).toBe(true)
			run(engine, 1)
			expect(lighting.Brightness).toBeCloseTo(2, 0.05)
			expect(lighting.OutdoorAmbient.R).toBeCloseTo(100 / 255, 0.02)
			run(engine, 1.1)
			expect(engine:IsTransitioning()).toBe(false)
			expect(lighting.Brightness).toBeCloseTo(3)
			expect(lighting.OutdoorAmbient).toBe(Color3.fromRGB(200, 100, 0))
		end)

		t.it("applies easing", function()
			local engine = t.newEngine()
			engine:SetLighting({ Brightness = 0 })
			engine:TransitionTo({ Duration = 2, Easing = "Quad", EasingDirection = "In", Configuration = { Lighting = { Brightness = 4 } } })
			run(engine, 1)
			expect(t.Services.Lighting.Brightness).toBeCloseTo(1, 0.1) -- 4 * 0.5^2
		end)

		t.it("takes the short way around midnight for ClockTime", function()
			local engine = t.newEngine()
			engine:SetLighting({ ClockTime = 23 })
			engine:TransitionTo({ Duration = 2, Easing = "Linear", Configuration = { Lighting = { ClockTime = 1 } } })
			run(engine, 1)
			local clock = t.Services.Lighting.ClockTime
			expect(clock < 0.1 or clock > 23.9).toBe(true)
			run(engine, 1.1)
			expect(t.Services.Lighting.ClockTime).toBeCloseTo(1, 1 / 600)
		end)

		t.it("fades new particle systems in from zero and removed ones out", function()
			local engine = t.newEngine()
			engine:TransitionTo({ Duration = 2, Easing = "Linear", Configuration = { Particles = { Snow = { Template = "Snow", Rate = 200 } } } })
			local emitter = engine.InstanceManager:Find("particles.Snow")
			expect(emitter).never.toBeNil()
			expect(emitter.Rate).toBeLessThan(1)
			run(engine, 1)
			expect(emitter.Rate).toBeCloseTo(100, 5)
			run(engine, 1.1)
			expect(emitter.Rate).toBeCloseTo(200)
			engine:TransitionTo({ Duration = 1, Easing = "Linear", Configuration = { Particles = { Snow = "$remove" } } })
			run(engine, 0.5)
			expect(emitter.Parent ~= nil).toBe(true)
			expect(emitter.Rate).toBeCloseTo(100, 5)
			run(engine, 0.6)
			expect(engine.InstanceManager:Find("particles.Snow")).toBeNil()
		end)

		t.it("interpolates NumberRange, NumberSequence and ColorSequence", function()
			local engine = t.newEngine()
			engine:CreateParticleSystem("P", {
				Template = "Custom",
				Speed = NumberRange.new(0, 10),
				Size = NumberSequence.new(1),
				Color = ColorSequence.new(Color3.fromRGB(0, 0, 0)),
			})
			engine:TransitionTo({
				Duration = 2,
				Easing = "Linear",
				Configuration = {
					Particles = {
						P = {
							Speed = NumberRange.new(10, 20),
							Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(0.5, 5), NumberSequenceKeypoint.new(1, 3) }),
							Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
						},
					},
				},
			})
			run(engine, 1)
			local emitter = engine.InstanceManager:Find("particles.P")
			expect(emitter.Speed.Min).toBeCloseTo(5, 0.2)
			expect(emitter.Speed.Max).toBeCloseTo(15, 0.2)
			expect(#emitter.Size.Keypoints).toBe(3)
			expect(emitter.Size.Keypoints[2].Value).toBeCloseTo(3, 0.1)
			expect(emitter.Color.Keypoints[1].Value.R).toBeCloseTo(0.5, 0.02)
			run(engine, 1.1)
			expect(emitter.Size.Keypoints[2].Value).toBeCloseTo(5)
		end)

		t.it("ends in exactly the same state as an instant apply", function()
			local transitioned = t.newEngine()
			transitioned:ApplyPreset("Night")
			transitioned:TransitionTo({ Duration = 3, Preset = "Storm" })
			run(transitioned, 3.2, 0.1)
			local viaTransition = transitioned:ExportConfiguration({ Format = "json" })
			local diff = transitioned:DiffScene(transitioned:GetPreset("Storm"))
			expect(#diff.Added).toBe(0)
			expect(#diff.Modified).toBe(0)
			expect(#diff.Removed).toBe(0)
			local instant = t.newEngine()
			instant:ApplyPreset("Storm")
			expect(instant:ExportConfiguration({ Format = "json" })).toBe(viaTransition)
		end)

		t.it("switches booleans on at the start and off at the end", function()
			local engine = t.newEngine()
			engine:SetPostProcessing({ Bloom = { Enabled = false, Intensity = 1 } })
			local bloom = engine.InstanceManager:Find("postprocessing.bloom")
			engine:TransitionTo({ Duration = 1, Configuration = { PostProcessing = { Bloom = { Enabled = true } } } })
			expect(bloom.Enabled).toBe(true)
			run(engine, 1.1)
			engine:TransitionTo({ Duration = 1, Configuration = { PostProcessing = { Bloom = { Enabled = false } } } })
			run(engine, 0.5)
			expect(bloom.Enabled).toBe(true)
			run(engine, 0.6)
			expect(bloom.Enabled).toBe(false)
		end)

		t.it("can be cancelled or completed early", function()
			local engine = t.newEngine()
			engine:SetLighting({ Brightness = 0 })
			engine:TransitionTo({ Duration = 4, Easing = "Linear", Configuration = { Lighting = { Brightness = 4 } } })
			run(engine, 1)
			engine:CancelTransition()
			local frozen = t.Services.Lighting.Brightness
			run(engine, 2)
			expect(t.Services.Lighting.Brightness).toBe(frozen)
			engine:TransitionTo({ Duration = 4, Configuration = { Lighting = { Brightness = 2 } } })
			engine:CancelTransition(true)
			expect(t.Services.Lighting.Brightness).toBeCloseTo(2)
		end)

		t.it("does not write unchanged properties", function()
			local engine = t.newEngine()
			engine:SetLighting({ Brightness = 2, ClockTime = 12 })
			local writes = 0
			local lighting = t.Services.Lighting
			local connection = lighting.Changed:Connect(function(property)
				if property == "ClockTime" then
					writes += 1
				end
			end)
			engine:TransitionTo({ Duration = 1, Configuration = { Lighting = { Brightness = 3 } } })
			run(engine, 1.2)
			connection:Disconnect()
			expect(writes).toBe(0)
		end)

		t.it("fires start and completion events", function()
			local engine = t.newEngine()
			local started, completed = 0, 0
			engine.Events.TransitionStarted:Connect(function()
				started += 1
			end)
			engine.Events.TransitionCompleted:Connect(function(info)
				if not info.Cancelled then
					completed += 1
				end
			end)
			engine:TransitionTo({ Duration = 0.5, Configuration = { Lighting = { Brightness = 1 } } })
			run(engine, 0.6)
			expect(started).toBe(1)
			expect(completed).toBe(1)
		end)

		t.it("rejects invalid transition requests", function()
			local engine = t.newEngine()
			expect(engine:TransitionTo({ Duration = -1, Configuration = {} }).Success).toBe(false)
			expect(engine:TransitionTo({ Duration = 1 }).Success).toBe(false)
			expect(engine:TransitionTo({ Duration = 1, Configuration = { Lighting = { Brightness = "x" } } }).Success).toBe(false)
			expect(engine:IsTransitioning()).toBe(false)
		end)
	end)
end
