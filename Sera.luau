--!strict
--!native
-- Low-level schematized serialization library

-- Imports when running via lune
local _, Roblox = pcall(require, "@lune/roblox")
local Vector3, CFrame, Color3 = Vector3, CFrame, Color3
if Roblox then
	Vector3 = Roblox.Vector3
	CFrame = Roblox.CFrame
	Color3 = Roblox.Color3
end

--- A function that serializes a value `T` into `buffer` at `offset` bytes.
--- Returns a new offset pointing to the offset after the serialized value.
export type Ser<T> = (buf: buffer, offset: number, value: T) -> number

--- A function that deserializes a value of type `T` from `buffer` at `offset` bytes.
export type Des<T> = (buf: buffer, offset: number) -> (T, number)

--- A resultant table from deserializing a buffer according to a schema.
export type SchemaDeserializeResult = { [string]: any }

--- A table to be serialized
export type SchemaSerializeInput = { [string]: any }

--- A serializable and deserializable encoding for type `T`.
export type SeraType<T> = {
	name: string,
	ser: Ser<T>,
	des: Des<T>,
}

--- Used to create schemas composed of multiple serialization types.
export type SeraTypeMap = {
	[string]: SeraType<any>,
}

--- A table that maps a number to another number.
type NumberMap = { [number]: number }

--- A single field that encodes and decodes from type `T`.
--- Used in `Schema` to represent multiple fields.
type Field<T> = {
	index: number,
	key: string,
	name: string,
	ser: Ser<T>,
	des: Des<T>,
}

--- An array of various fields
type Fields = { Field<any> }

--- A lookup table from keys to fields
type FieldLookup = { [string]: Field<any> }

--- A schema used to serialize and deserialize data that contains many fields.
export type Schema = {
	fields: Fields,
	fieldLookup: FieldLookup,
}

--- Size for the large buffer that Serialize writes to
-- NOTE: "Serialize" and "DeltaSerialize" will fail if resulting buffer size is larger than this value
local BIG_BUFFER_SIZE = 1000000

--- Sizes for strings and buffers
local SIZE_8 = 2 ^ 8 - 1
local SIZE_16 = 2 ^ 16 - 1
local SIZE_32 = 2 ^ 32 - 1

--- The maximum number of fields a schema can have
local MAX_FIELDS = 2 ^ 8 - 1

--- Big reusable buffer
local BB = buffer.create(BIG_BUFFER_SIZE)

--- Range to wrap radians around
local RAD2 = math.pi * 2

--- Range for Angle8
local ANGLE8RANGE = math.rad(359)

--- Encode an angle (0-360) into integer form (0-255)
local function RadEncode(angle: number): number
	return math.round((angle % RAD2) * 255 / ANGLE8RANGE)
end

--- A lookup table that decodes encoded radians.
--- degDecodeLookup[encoded] = decoded
local radDecodeLookup: NumberMap = {}
do
	-- Populate degDecodeLookup
	for i = 0, 255 do
		radDecodeLookup[i] = i * ANGLE8RANGE / 255
	end
	for i = 0, 315, 45 do
		local r = math.rad(i)
		local index = RadEncode(r)
		radDecodeLookup[index] = r
	end
end

--- SeraType presets for commonly used value types
local SERA_TYPES = table.freeze {
	--- A boolean representation
	Boolean = table.freeze {
		name = "Boolean",
		ser = function(buf: buffer, offset: number, value: boolean): number
			buffer.writeu8(buf, offset, if value then 1 else 0)
			return offset + 1
		end,
		des = function(buf: buffer, offset: number): (boolean, number)
			return buffer.readu8(buf, offset) == 1, offset + 1
		end,
	} :: SeraType<boolean>,

	--- An unsigned 8-bit integer
	Uint8 = table.freeze {
		name = "Uint8",
		ser = function(buf: buffer, offset: number, value: number): number
			buffer.writeu8(buf, offset, value)
			return offset + 1
		end,
		des = function(buf: buffer, offset: number): (number, number)
			return buffer.readu8(buf, offset), offset + 1
		end,
	} :: SeraType<number>,

	--- An unsigned 16-bit integer
	Uint16 = table.freeze {
		name = "Uint16",
		ser = function(buf: buffer, offset: number, value: number): number
			buffer.writeu16(buf, offset, value)
			return offset + 2
		end,
		des = function(buf: buffer, offset: number): (number, number)
			return buffer.readu16(buf, offset), offset + 2
		end,
	} :: SeraType<number>,

	--- An unsigned 32-bit integer
	Uint32 = table.freeze {
		name = "Uint32",
		ser = function(buf: buffer, offset: number, value: number): number
			buffer.writeu32(buf, offset, value)
			return offset + 4
		end,
		des = function(buf: buffer, offset: number): (number, number)
			return buffer.readu32(buf, offset), offset + 4
		end,
	} :: SeraType<number>,

	--- A signed 8-bit integer
	Int8 = table.freeze {
		name = "Int8",
		ser = function(buf: buffer, offset: number, value: number): number
			buffer.writei8(buf, offset, value)
			return offset + 1
		end,
		des = function(buf: buffer, offset: number): (number, number)
			return buffer.readi8(buf, offset), offset + 1
		end,
	} :: SeraType<number>,

	--- A signed 16-bit integer
	Int16 = table.freeze {
		name = "Int16",
		ser = function(buf: buffer, offset: number, value: number): number
			buffer.writei16(buf, offset, value)
			return offset + 2
		end,
		des = function(buf: buffer, offset: number): (number, number)
			return buffer.readi16(buf, offset), offset + 2
		end,
	} :: SeraType<number>,

	--- A signed 32-bit integer
	Int32 = table.freeze {
		name = "Int32",
		ser = function(buf: buffer, offset: number, value: number): number
			buffer.writei32(buf, offset, value)
			return offset + 4
		end,
		des = function(buf: buffer, offset: number): (number, number)
			return buffer.readi32(buf, offset), offset + 4
		end,
	} :: SeraType<number>,

	--- A 32-bit float
	Float32 = table.freeze {
		name = "Float32",
		ser = function(buf: buffer, offset: number, value: number): number
			buffer.writef32(buf, offset, value)
			return offset + 4
		end,
		des = function(buf: buffer, offset: number): (number, number)
			return buffer.readf32(buf, offset), offset + 4
		end,
	} :: SeraType<number>,

	--- A 64-bit float
	Float64 = table.freeze {
		name = "Float64",
		ser = function(buf: buffer, offset: number, value: number): number
			buffer.writef64(buf, offset, value)
			return offset + 8
		end,
		des = function(buf: buffer, offset: number): (number, number)
			return buffer.readf64(buf, offset), offset + 8
		end,
	} :: SeraType<number>,

	--- A 48-byte full precision representation of a CFrame.
	CFrame = table.freeze {
		name = "CFrame",
		ser = function(buf: buffer, offset: number, value: CFrame): number
			local v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11 = value:GetComponents()
			buffer.writef32(buf, offset, v0)
			buffer.writef32(buf, offset + 4, v1)
			buffer.writef32(buf, offset + 8, v2)
			buffer.writef32(buf, offset + 12, v3)
			buffer.writef32(buf, offset + 16, v4)
			buffer.writef32(buf, offset + 20, v5)
			buffer.writef32(buf, offset + 24, v6)
			buffer.writef32(buf, offset + 28, v7)
			buffer.writef32(buf, offset + 32, v8)
			buffer.writef32(buf, offset + 36, v9)
			buffer.writef32(buf, offset + 40, v10)
			buffer.writef32(buf, offset + 44, v11)
			return offset + 48
		end,
		des = function(buf: buffer, offset: number): (CFrame, number)
			return CFrame.new(
				buffer.readf32(buf, offset),
				buffer.readf32(buf, offset + 4),
				buffer.readf32(buf, offset + 8),
				buffer.readf32(buf, offset + 12),
				buffer.readf32(buf, offset + 16),
				buffer.readf32(buf, offset + 20),
				buffer.readf32(buf, offset + 24),
				buffer.readf32(buf, offset + 28),
				buffer.readf32(buf, offset + 32),
				buffer.readf32(buf, offset + 36),
				buffer.readf32(buf, offset + 40),
				buffer.readf32(buf, offset + 44)
			),
				offset + 48
		end,
	} :: SeraType<CFrame>,

	--- A 28-byte lossy representation of a CFrame.
	--- Less than 0.0005 degree precision error for rotation.
	CFrameLossy = table.freeze {
		name = "CFrameLossy",
		ser = function(buf: buffer, offset: number, value: CFrame): number
			local axis, angle = value:ToAxisAngle()
			buffer.writef32(buf, offset, value.X)
			buffer.writef32(buf, offset + 4, value.Y)
			buffer.writef32(buf, offset + 8, value.Z)
			buffer.writef32(buf, offset + 12, axis.X)
			buffer.writef32(buf, offset + 16, axis.Y)
			buffer.writef32(buf, offset + 20, axis.Z)
			buffer.writef32(buf, offset + 24, angle)
			return offset + 28
		end,
		des = function(buf: buffer, offset: number): (CFrame, number)
			return CFrame.fromAxisAngle(
				Vector3.new(
					buffer.readf32(buf, offset + 12),
					buffer.readf32(buf, offset + 16),
					buffer.readf32(buf, offset + 20)
				),
				buffer.readf32(buf, offset + 24)
			) + Vector3.new(
				buffer.readf32(buf, offset),
				buffer.readf32(buf, offset + 4),
				buffer.readf32(buf, offset + 8)
			),
				offset + 28
		end,
	} :: SeraType<CFrame>,

	--- A full-precision Vector3 representation
	Vector3 = table.freeze {
		name = "Vector3",
		ser = function(buf: buffer, offset: number, value: Vector3): number
			buffer.writef32(buf, offset, value.X)
			buffer.writef32(buf, offset + 4, value.Y)
			buffer.writef32(buf, offset + 8, value.Z)
			return offset + 12
		end,
		des = function(buf: buffer, offset: number): (Vector3, number)
			return Vector3.new(
				buffer.readf32(buf, offset),
				buffer.readf32(buf, offset + 4),
				buffer.readf32(buf, offset + 8)
			),
				offset + 12
		end,
	} :: SeraType<Vector3>,

	--- A full-precision Color3 representation
	Color3 = table.freeze {
		name = "Color3",
		ser = function(buf: buffer, offset: number, value: Color3): number
			buffer.writeu8(buf, offset, value.R * 255)
			buffer.writeu8(buf, offset + 1, value.G * 255)
			buffer.writeu8(buf, offset + 2, value.B * 255)
			return offset + 3
		end,
		des = function(buf: buffer, offset: number): (Color3, number)
			return Color3.fromRGB(
				buffer.readu8(buf, offset),
				buffer.readu8(buf, offset + 1),
				buffer.readu8(buf, offset + 2)
			),
				offset + 3
		end,
	} :: SeraType<Color3>,

	--- A vectorized Color3 representation.
	--- Input and output are Vector3's with [0, 1] color values.
	ColorV3 = table.freeze {
		name = "ColorV3",
		ser = function(buf: buffer, offset: number, value: Vector3): number
			buffer.writeu8(buf, offset, value.X * 255)
			buffer.writeu8(buf, offset + 1, value.Y * 255)
			buffer.writeu8(buf, offset + 2, value.Z * 255)
			return offset + 3
		end,
		des = function(buf: buffer, offset: number): (Vector3, number)
			return Vector3.new(
				buffer.readu8(buf, offset) / 255,
				buffer.readu8(buf, offset + 1) / 255,
				buffer.readu8(buf, offset + 2) / 255
			),
				offset + 3
		end,
	} :: SeraType<Vector3>,

	--- A string with max 255 size.
	String8 = table.freeze {
		name = "String8",
		ser = function(buf: buffer, offset: number, value: string): number
			local length = value:len()
			assert(length <= SIZE_8, "String too long")
			buffer.writeu8(buf, offset, length)
			buffer.writestring(buf, offset + 1, value)
			return offset + 1 + length
		end,
		des = function(buf: buffer, offset: number): (string, number)
			local length = buffer.readu8(buf, offset)
			return buffer.readstring(buf, offset + 1, length), offset + 1 + length
		end,
	} :: SeraType<string>,

	--- A string with max 65,535 size.
	String16 = table.freeze {
		name = "String16",
		ser = function(buf: buffer, offset: number, value: string): number
			local length = value:len()
			assert(length <= SIZE_16, "String too long")
			buffer.writeu16(buf, offset, length)
			buffer.writestring(buf, offset + 2, value)
			return offset + 2 + length
		end,
		des = function(buf: buffer, offset: number): (string, number)
			local length = buffer.readu16(buf, offset)
			return buffer.readstring(buf, offset + 2, length), offset + 2 + length
		end,
	} :: SeraType<string>,

	--- A string with max 4,294,967,295 size.
	String32 = table.freeze {
		name = "String32",
		ser = function(buf: buffer, offset: number, value: string): number
			local length = value:len()
			assert(length <= SIZE_32, "String too long")
			buffer.writeu32(buf, offset, length)
			buffer.writestring(buf, offset + 4, value)
			return offset + 4 + length
		end,
		des = function(buf: buffer, offset: number): (string, number)
			local length = buffer.readu32(buf, offset)
			return buffer.readstring(buf, offset + 4, length), offset + 4 + length
		end,
	} :: SeraType<string>,

	--- An 8-bit buffer.
	Buffer8 = table.freeze {
		name = "Buffer8",
		ser = function(buf: buffer, offset: number, value: buffer): number
			local length = buffer.len(value)
			assert(length <= SIZE_8, "Buffer too long")
			buffer.writeu8(buf, offset, length)
			buffer.copy(buf, offset + 1, value)
			return offset + 1 + length
		end,
		des = function(buf: buffer, offset: number): (buffer, number)
			local length = buffer.readu8(buf, offset)
			local value = buffer.create(length)
			buffer.copy(value, 0, buf, offset + 1, length)
			return value, offset + 1 + length
		end,
	} :: SeraType<buffer>,

	--- A 16-bit buffer.
	Buffer16 = table.freeze {
		name = "Buffer16",
		ser = function(buf: buffer, offset: number, value: buffer): number
			local length = buffer.len(value)
			assert(length <= SIZE_16, "Buffer too long")
			buffer.writeu16(buf, offset, length)
			buffer.copy(buf, offset + 2, value)
			return offset + 2 + length
		end,
		des = function(buf: buffer, offset: number): (buffer, number)
			local length = buffer.readu16(buf, offset)
			local value = buffer.create(length)
			buffer.copy(value, 0, buf, offset + 2, length)
			return value, offset + 2 + length
		end,
	} :: SeraType<buffer>,

	--- A 32-bit buffer.
	Buffer32 = table.freeze {
		name = "Buffer32",
		ser = function(buf: buffer, offset: number, value: buffer): number
			local length = buffer.len(value)
			assert(length <= SIZE_32, "Buffer too long")
			buffer.writeu32(buf, offset, length)
			buffer.copy(buf, offset + 4, value)
			return offset + 4 + length
		end,
		des = function(buf: buffer, offset: number): (buffer, number)
			local length = buffer.readu32(buf, offset)
			local value = buffer.create(length)
			buffer.copy(value, 0, buf, offset + 4, length)
			return value, offset + 4 + length
		end,
	} :: SeraType<buffer>,

	--- An unsigned radian representation in one byte while preserving cardinal direction accuracy.
	--- (Every 45 degrees)
	Angle8 = table.freeze {
		name = "Angle8",
		ser = function(buf: buffer, offset: number, value: number): number
			buffer.writeu8(buf, offset, RadEncode(value))
			return offset + 1
		end,
		des = function(buf: buffer, offset: number): (number, number)
			return radDecodeLookup[buffer.readu8(buf, offset)], offset + 1
		end,
	} :: SeraType<number>,
}

--- Serialize values from table `input` onto buffer `buf` at offset `offset` based on serialization scheme `schema`.
---
--- Will fail if fields from `schema` are missing from table `input`.
---
--- Serialization may throw an error! Wrap in `pcall`.
---
--- ```luau
--- return offset
--- ```
function SerializeUnsafe(schema: Schema, input: SchemaSerializeInput, buf: buffer, offset: number): number
	for _, field in schema.fields do
		local inputValue = input[field.key]
		offset = field.ser(buf, offset, inputValue)
	end
	return offset
end

--- Delta-serialize values from table `input` onto buffer `buf` at offset `offset` based on serialization scheme `schema`.
---
--- Will fail if extra fields are present in `input` that aren't in `schema`.
---
--- Serialization may throw an error! Wrap in `pcall`.
---
--- ```luau
--- return offset
--- ```
function DeltaSerializeUnsafe(schema: Schema, input: SchemaSerializeInput, buf: buffer, offset: number): number
	-- Skip one byte of offset
	local startOffset = offset
	offset += 1

	-- For each provided field, write the index of the field and then the field's value
	local fieldCount = 0
	local fieldLookup = schema.fieldLookup
	for key in input do
		fieldCount += 1
		local field = fieldLookup[key]
		local fieldIndex = field.index
		buffer.writeu8(buf, offset, fieldIndex)
		local fieldKey = field.key
		local inputValue = input[fieldKey]
		offset = field.ser(buf, offset + 1, inputValue)
	end

	-- Write the number of fields into the start offset
	buffer.writeu8(buf, startOffset, fieldCount)
	return offset
end

--- Validates a serialization of table `input` onto buffer `buf` based on serialization scheme `schema`.
---
--- ```luau
--- return err
--- ```
function GetSerializationError(schema: Schema, input: SchemaSerializeInput, buf: buffer, offset: number): string
	local serSuccess: boolean
	for _, field in schema.fields do
		-- Catch missing fields in input
		local value = input[field.key]
		if value == nil then
			return `Missing field "{field.key}"`
		end

		-- Catch serialization errors
		serSuccess, offset = pcall(field.ser, buf, offset, value)
		if not serSuccess then
			return `Couldn't serialize field '{field.key}' (Expected: '{field.name}'; Got: '{typeof(value)}'; Message: '{offset}')`
		end
	end
	return `Unknown error`
end

--- Validates a delta serialization of table `input` onto buffer `buf` based on serialization scheme `schema`.
---
--- ```luau
--- return err
--- ```
function GetDeltaSerializationError(schema: Schema, input: SchemaSerializeInput, buf: buffer, offset: number): string
	local serSuccess: boolean
	for inputKey, inputValue in input do
		-- Catch extraneous fields
		local field = schema.fieldLookup[inputKey]
		if field == nil then
			return `Key "{inputKey}" not specified in schema`
		end
		buffer.writeu8(buf, offset, field.index)

		-- Catch serialization errors
		serSuccess, offset = pcall(field.ser, buf, offset + 1, inputValue)
		if not serSuccess then
			return `Couldn't serialize field '{field.key}' (Expected: {field.name}; Got: '{typeof(inputValue)}'; Message: {offset})`
		end
	end
	return `Unknown error`
end

local Sera = {
	Types = SERA_TYPES,
}

--- Returns a new buffer `buf` serialized from table `input` based on serialization scheme `schema`.
---
--- Will error if `input` is missing any fields from `schema`.
---
--- If serialization fails, `buf` is nil and `err` is a string containing the error message.
---
--- ```luau
--- return buf, err
--- ```
function Sera.Serialize(schema: Schema, input: SchemaSerializeInput): (buffer?, string?)
	-- Try serializing onto big-buffer `BB`
	local success, offset = pcall(SerializeUnsafe, schema, input, BB, 0)
	if not success then
		return nil, GetSerializationError(schema, input, BB, 0)
	end

	-- Return a new exact-sized buffer copied from BB
	local buf = buffer.create(offset)
	buffer.copy(buf, 0, BB, 0, offset)
	return buf, nil
end

--- Returns a new buffer `buf` delta-serialized from table `input` based on serialization scheme `schema`.
---
--- `input` can have fields missing from `schema` but may not have extraneous fields.
---
--- If serialization fails, `buf` is nil and `err` is a string containing the error message.
---
--- ```luau
--- return buf, err
--- ```
function Sera.DeltaSerialize(schema: Schema, input: SchemaSerializeInput): (buffer?, string?)
	-- Try delta-serializing onto big-buffer `BB`
	local success, offset = pcall(DeltaSerializeUnsafe, schema, input, BB, 0)
	if not success then
		return nil, GetDeltaSerializationError(schema, input, BB, 0)
	end

	-- Return a new exact-sized buffer copied from BB
	local buf = buffer.create(offset)
	buffer.copy(buf, 0, BB, 0, offset)
	return buf, nil
end

--- Push values from table `input` onto buffer `buf` at byte `offset` based on serialization scheme `schema`.
---
--- Will fail if fields from `schema` are missing from table `input`.
---
--- Returns new buffer offset after serialization or error message if fail.
---
--- ```luau
--- return offset, err
--- ```
function Sera.Push(schema: Schema, input: SchemaSerializeInput, buf: buffer, offset: number): (number?, string?)
	local success, newOffset = pcall(SerializeUnsafe, schema, input, buf, offset)
	if not success then
		return nil, GetSerializationError(schema, input, buf, offset)
	end
	return newOffset, nil
end

--- Pushes serialized deltas to an existing buffer.
--- Returns new buffer offset or error message if fail.
function Sera.DeltaPush(schema: Schema, input: SchemaSerializeInput, buf: buffer, offset: number): (number?, string?)
	local success, newOffset = pcall(DeltaSerializeUnsafe, schema, input, buf, offset)
	if not success then
		return nil, GetDeltaSerializationError(schema, input, buf, offset)
	end
	return newOffset, nil
end

--- Returns dictionary of deserialized schema.
function Sera.Deserialize(schema: Schema, buf: buffer, offset: number): (SchemaDeserializeResult, number)
	-- Read all fields one-by-one into result
	local result: SchemaDeserializeResult = {}
	for _, field in schema.fields do
		local fieldKey = field.key
		result[fieldKey], offset = field.des(buf, offset)
	end
	return result, offset
end

--- Returns dictionary of deserialized deltas.
function Sera.DeltaDeserialize(schema: Schema, buf: buffer, offset: number): (SchemaDeserializeResult, number)
	-- The field count is at the first position
	local fieldCount = buffer.readu8(buf, offset)

	-- All other values are red at the offset after the fieldCount
	offset += 1

	-- Get field values, insert them into result
	local fieldLookup = schema.fields
	local result: SchemaDeserializeResult = {}
	for _ = 1, fieldCount do
		local field = fieldLookup[buffer.readu8(buf, offset)]
		local fieldKey = field.key
		result[fieldKey], offset = field.des(buf, offset + 1)
	end
	return result, offset
end

--- Create a deserialization schema with a type map `schemaKey`.
--- Has a maximum of 255 fields.
function Sera.Schema(schemaKey: SeraTypeMap): Schema
	-- Convert schema key into fields
	local fields: Fields = {}
	for key, seraType in schemaKey do
		assert(typeof(key) == "string", `Expected string for field name, got '{typeof(key)}'`)
		assert(
			typeof(seraType) == "table"
				and typeof(seraType.ser) == "function"
				and typeof(seraType.des) == "function"
				and typeof(seraType.name) == "string",
			`Expected SeraType for field '{key}'`
		)
		table.insert(fields, {
			index = 0,
			key = key,
			name = seraType.name,
			ser = seraType.ser,
			des = seraType.des,
		})
	end

	-- Enforce field limits
	assert(#fields ~= 0, "Schema must have fields")
	assert(#fields <= MAX_FIELDS, `Schema exceeded {MAX_FIELDS} fields, got {#fields} fields`)

	-- Sort fields by name to ensure consistency in encoding/decoding
	-- Set .index to sorted ordering
	table.sort(fields, function(a, b)
		return a.key < b.key
	end)
	local fieldLookup: FieldLookup = {}
	for index, field in fields do
		field.index = index
		fieldLookup[field.key] = field
	end

	-- Return a frozen schema
	return table.freeze {
		fields = fields,
		fieldLookup = fieldLookup,
	}
end

return Sera
