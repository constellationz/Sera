--!strict

local Sera = require("./Sera")

local _, Roblox = pcall(require, "@lune/roblox")
local Vector3, CFrame, Color3 = Vector3, CFrame, Color3
if Roblox then
    Vector3 = Roblox.Vector3
	CFrame = Roblox.CFrame
	Color3 = Roblox.Color3
end

-- Defining a schema
local CustomType: Sera.SeraType<{ number }> = table.freeze {
	name = "TwoNumbers",
	ser = function(b: buffer, offset: number, value: { number }): number
		buffer.writef64(b, offset, value[1])
		buffer.writef64(b, offset + 8, value[2])
		return offset + 16
	end,
	des = function(b: buffer, offset: number): ({ number }, number)
		return {
			buffer.readf64(b, offset),
			buffer.readf64(b, offset + 8),
		}, offset + 16
	end,
}

-- Test schema
local TestSchema = Sera.Schema {
	Health = Sera.Types.Int16,
	Position = Sera.Types.Vector3,
	CFrame = Sera.Types.CFrame,
	CFrameLossy = Sera.Types.CFrameLossy,
	Color = Sera.Types.Color3,
	ColorV3 = Sera.Types.ColorV3,
	Name = Sera.Types.String8,
	Angle = Sera.Types.Angle8,
	TwoNumbers = CustomType,
}

-- Trying out serialization of a dictionary with all fields present:
do
	local serialized, errorMessage = Sera.Serialize(TestSchema, {
		Health = 150,
		Position = Vector3.new(1001, 69, 0.1),
		Name = "Mashend2468",
		CFrame = CFrame.new(1, 2, 3),
		Color = Color3.fromRGB(255, 0, 255),
		ColorV3 = Vector3.new(0.5, 0, 1),
		CFrameLossy = CFrame.new(1, 2, 3),
		Angle = math.rad(90),
		TwoNumbers = { 1234.56, 0.001 },
	})
	if not serialized then
		error(errorMessage)
	end

	local deserialized1, offset = Sera.Deserialize(TestSchema, serialized, 0)
	local b = buffer.create(offset + 10)
	Sera.Push(TestSchema, deserialized1, b, 10)
	local deserialized2 = Sera.Deserialize(TestSchema, b, 10)
	print(`All field serialization:`)
	print(`Serialized buffer size: {buffer.len(serialized)} bytes`)
	print(`Deserialized result #1:`, deserialized1)
	print(`Deserialized result #2:`, deserialized2)
end

-- Trying out serialization of a dictionary with only some fields present:
do
	local serialized, errorMessage = Sera.DeltaSerialize(TestSchema, {
		Position = Vector3.new(900, 60, 3),
		TwoNumbers = { -20, -1.5 },
	})
	if not serialized then
		error(errorMessage)
	end

	local deserialized1, offset = Sera.DeltaDeserialize(TestSchema, serialized, 0)
	local b = buffer.create(offset + 10)
	Sera.DeltaPush(TestSchema, deserialized1, b, 10)
	local deserialized2 = Sera.DeltaDeserialize(TestSchema, b, 10)
	print(`Partial field serialization:`)
	print(`Serialized buffer size: {buffer.len(serialized)} bytes`)
	print(`Deserialized result #1:`, deserialized1)
	print(`Deserialized result #2:`, deserialized2)
end
