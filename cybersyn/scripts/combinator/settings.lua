-- By @wcjohnson
--
-- Registration and manipulation of combinator settings.

local bit_extract = bit32.extract
local bit_replace = bit32.replace

---@alias Cybersyn.Combinator.SettingValue any

---@enum Cybersyn.Combinator.SettingValueType The type of value that a given setting can store.
combinator_api.SettingValueType = {
	UNKNOWN = 0,
	BOOLEAN = 1,
	INTEGER = 2,
	STRING = 3,
	-- A Factorio signal, possibly stored natively on the combinator.
	SIGNAL = 4,
	-- A Factorio `Tags` table. `Tags: table<string, string|boolean|number|Tags>`
	TAGS = 5,
}

---@enum Cybersyn.Combinator.SettingStorageType How a given setting is stored on the combinator.
combinator_api.SettingStorageType = {
	UNKNOWN = 0,
	LEGACY_MODE = 1,
	LEGACY_NETWORK = 2,
	LEGACY_BITFIELD = 3,
}

---@alias Cybersyn.Combinator.SettingReader fun(definition: Cybersyn.Combinator.SettingDefinition, settings: Cybersyn.Combinator.Settings): Cybersyn.Combinator.SettingValue? Reads a setting from a combinator. `nil` return value indicates the setting was absent.
---@alias Cybersyn.Combinator.SettingWriter fun(definition: Cybersyn.Combinator.SettingDefinition, settings: Cybersyn.Combinator.Settings, value: Cybersyn.Combinator.SettingValue?): boolean Writes a setting to a combinator. Returns `true` if the write was successful.

---@class Cybersyn.Combinator.SettingDefinition Definition of a setting that can be stored on a Cybersyn combinator.
---@field public name string The unique name of the setting.
---@field public value_type Cybersyn.Combinator.SettingValueType The type of value that this setting can store.
---@field public storage_type Cybersyn.Combinator.SettingStorageType How this setting is stored on the combinator.
---@field public reader Cybersyn.Combinator.SettingReader The function used to read this setting from a combinator.
---@field public writer Cybersyn.Combinator.SettingWriter? The function used to write this setting to a combinator.
---@field public bit_index? uint The index of this setting in a bitfield, if applicable.
---@field public bit_width? uint The width of this setting in a bitfield, if applicable.

if not combinator_api.settings then
	combinator_api.settings = {} --[[@as {[string]: Cybersyn.Combinator.SettingDefinition}]]
end

---@param combinator Cybersyn.Combinator.Settings
---@param setting Cybersyn.Combinator.SettingDefinition
function combinator_api.read_setting(combinator, setting)
	return setting.reader(setting, combinator)
end

---@param combinator Cybersyn.Combinator.Settings
---@param setting Cybersyn.Combinator.SettingDefinition
---@param value Cybersyn.Combinator.SettingValue
function combinator_api.write_setting(combinator, setting, value)
	local writer = setting.writer
	if writer then return writer(setting, combinator, value) else return false end
end

---@param definition Cybersyn.Combinator.SettingDefinition
function combinator_api.register_setting(definition)
	local name = definition.name
	if combinator_api.settings[name] then
		return false
	end
	combinator_api.settings[name] = definition
	return true
end

---@param op string?
local function op_to_mode(op)
	if op == "*" then
		return "unknown"
	elseif op == "/" or op == "^" or op == "<<" then
		return "legacy_station"
	elseif op == "%" then
		return "legacy_station_control"
	elseif op == "+" then
		return "legacy_depot"
	elseif op == "-" then
		return "legacy_wagon"
	elseif op == ">>" then
		return "legacy_refueler"
	else
		return "unknown"
	end
end

---@param mode string
local function mode_to_op(mode)
	if mode == "legacy_station" then
		return "/"
	elseif mode == "legacy_station_control" then
		return "%"
	elseif mode == "legacy_depot" then
		return "+"
	elseif mode == "legacy_wagon" then
		return "-"
	elseif mode == "legacy_refueler" then
		return ">>"
	else
		return "*"
	end
end

---@param name string
---@param bit_index uint
---@param bit_width uint
---@return Cybersyn.Combinator.SettingDefinition
local function legacy_bitfield(name, bit_index, bit_width)
	---@type Cybersyn.Combinator.SettingDefinition
	local def = {
		name = name,
		value_type = combinator_api.SettingValueType.BOOLEAN,
		storage_type = combinator_api.SettingStorageType.LEGACY_BITFIELD,
		bit_index = bit_index,
		bit_width = bit_width,
		reader = function(definition, settings)
			local params = settings.parameters
			if not params then return 0 end
			local bits = params.second_constant or 0
			return bit_extract(bits, bit_index, bit_width)
		end,
		writer = function(definition, settings, new_value)
			local params = settings.parameters
			if not params then return false end
			local bits = params.second_constant or 0
			local old_value = bit_extract(bits, bit_index, bit_width)
			if old_value ~= new_value then
				local new_bits = bit_replace(bits, new_value, bit_index, bit_width)
				params.second_constant = new_bits
				settings.control_behavior.parameters = params
				raise_combinator_setting_changed(settings, definition.name, new_value, old_value)
			end
			return true
		end,
	}
	return def
end

--- Register Cybersyn's combinator settings.
combinator_api.register_setting({
	name = "mode",
	value_type = combinator_api.SettingValueType.STRING,
	storage_type = combinator_api.SettingStorageType.LEGACY_MODE,
	reader = function(definition, settings)
		local params = settings.parameters
		if not params then return "unknown" end
		return op_to_mode(params.operation)
	end,
	writer = function(definition, settings, new_mode)
		---@type Cybersyn.Combinator.SettingValue
		local x
		local params = settings.parameters
		if not params then return false end
		local old_mode = op_to_mode(params.operation)
		if new_mode ~= old_mode then
			params.operation = mode_to_op(new_mode)
			settings.control_behavior.parameters = params
			raise_combinator_setting_changed(settings, definition.name, new_mode, old_mode)
		end
		return true
	end,
})

combinator_api.register_setting({
	name = "network_signal",
	value_type = combinator_api.SettingValueType.SIGNAL,
	storage_type = combinator_api.SettingStorageType.LEGACY_NETWORK,
	reader = function(definition, settings)
		local params = settings.parameters
		if not params then return nil end
		return params.first_signal
	end,
	writer = function(definition, settings, new_signal)
		local params = settings.parameters
		if not params then return false end
		local old_signal = params.first_signal
		if not signal_eq(new_signal, old_signal) then
			params.first_signal = new_signal
			settings.control_behavior.parameters = params
			raise_combinator_setting_changed(settings, definition.name, new_signal, old_signal)
		end
		return true
	end,
})

combinator_api.register_setting(legacy_bitfield("provide_or_request", 0, 2))
combinator_api.register_setting(legacy_bitfield("disable_allow_list", 2, 1))
combinator_api.register_setting(legacy_bitfield("use_stack_thresholds", 3, 1))
combinator_api.register_setting(legacy_bitfield("enable_inactivity_condition", 4, 1))
combinator_api.register_setting(legacy_bitfield("use_any_depot", 5, 1))
combinator_api.register_setting(legacy_bitfield("disable_depot_bypass", 6, 1))
combinator_api.register_setting(legacy_bitfield("enable_slot_barring", 7, 1))
combinator_api.register_setting(legacy_bitfield("enable_circuit_condition", 8, 1))
combinator_api.register_setting(legacy_bitfield("enable_train_count", 9, 1))
combinator_api.register_setting(legacy_bitfield("enable_manual_inventory", 10, 1))
