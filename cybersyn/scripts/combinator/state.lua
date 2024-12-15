-- Registration and manipulation of combinator state.

---@alias Cybersyn.Combinator.StateReader fun(definition: Cybersyn.Combinator.StateDefinition, state: Cybersyn.Combinator): any Reads a state from a combinator.
---@alias Cybersyn.Combinator.StateWriter fun(definition: Cybersyn.Combinator.StateDefinition, state: Cybersyn.Combinator, value: any): boolean Writes a state to a combinator. Returns `true` if the write was successful.

---@class Cybersyn.Combinator.StateDefinition
---@field public name string The unique name of the state
---@field public reader Cybersyn.Combinator.StateReader? The function used to read this state from a combinator.
---@field public writer Cybersyn.Combinator.StateWriter? The function used to write this state to a combinator.

if not combinator_api.states then
	combinator_api.states = {} --[[@as {[string]: Cybersyn.Combinator.StateDefinition}]]
end

---@param combinator Cybersyn.Combinator
---@param state Cybersyn.Combinator.StateDefinition
---@return any
function combinator_api.read_state(combinator, state)
	local reader = state.reader
	if reader then return reader(state, combinator) else return nil end
end

---@param combinator Cybersyn.Combinator
---@param state Cybersyn.Combinator.StateDefinition
---@param value any
---@return boolean
function combinator_api.write_state(combinator, state, value)
	local writer = state.writer
	if writer then return writer(state, combinator, value) else return false end
end

---@param definition Cybersyn.Combinator.StateDefinition
function combinator_api.register_state(definition)
	local name = definition.name
	if combinator_api.states[name] then
		return false
	end
	combinator_api.states[name] = definition
	return true
end

combinator_api.register_state({
	name = "output_signals",
	writer = function(definition, state, value)
		local output_combinator = state.output
		if output_combinator and output_combinator.valid then
			local beh = output_combinator.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
			beh.get_section(1).filters = value or {}
			raise_combinator_state_written(state, definition.name, value)
			return true
		else
			return false
		end
	end,
})

local WORKING = defines.entity_status.working
local LOW_POWER = defines.entity_status.low_power

combinator_api.register_state({
	name = "input_signals",
	reader = function(definition, state)
		local input_combinator = state.entity
		if input_combinator and input_combinator.valid then
			if input_combinator.status == WORKING or input_combinator.status == LOW_POWER then
				return input_combinator.get_signals(defines.wire_connector_id.circuit_red,
					defines.wire_connector_id.circuit_green)
			end
		end
		return nil
	end,
})

-- LORD: use combinator states for the display of bad combinator statuses, as opposed to the "red S"
