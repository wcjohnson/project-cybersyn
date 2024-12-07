-- Core events library. This is a type-safe internal event system for Cybersyn,
-- hopefully enabling more event-driven and less spaghetti code.
local events = {}

---@param settings Cybersyn.Combinator.Settings
---@param setting_name string The name of the setting that was changed.
---@param value any? The new value of the setting.
function events.raise_combinator_setting_changed(settings, setting_name, value)
end

---@param stop Cybersyn.TrainStop
function events.raise_pre_train_stop_broken(stop)
end

local on_train_stop_broken_handlers = {}
---Event raised after a train stop is broken. By this time, all combinators are detached and the Cybersyn state is destroyed, but the stop entity is still valid.
---@param handler fun(stop_entity: LuaEntity)
function events.on_train_stop_broken(handler)
	table.insert(on_train_stop_broken_handlers, handler)
end
---@param stop_entity LuaEntity
function events.raise_train_stop_broken(stop_entity)
	for _, handler in ipairs(on_train_stop_broken_handlers) do handler(stop_entity) end
end

---@param stop_id Cybersyn.UnitNumber
function events.raise_pre_train_stop_built(stop_id)
end

---@param stop_id Cybersyn.UnitNumber
function events.raise_train_stop_built(stop_id)
end

---Event raised when a combinator is detached from a train stop. WARNING: This event is called when train stops are destroyed, so the `stop_id` is not long-term valid.
---@param handler fun(combinator_id: Cybersyn.UnitNumber, stop_id: Cybersyn.UnitNumber)
function events.on_combinator_detached(handler)
end
---@param combinator_id Cybersyn.UnitNumber
---@param stop_id Cybersyn.UnitNumber
function events.raise_combinator_detached(combinator_id, stop_id)
end

---@param combinator_id Cybersyn.UnitNumber
---@param stop_id Cybersyn.UnitNumber
function events.raise_combinator_attached(combinator_id, stop_id)
end

---@param combinator_ghost_entity LuaEntity
function events.raise_combinator_ghost_broken(ghost_id, ghost_entity)
end

---@param combinator_id Cybersyn.UnitNumber
---@param combinator_entity LuaEntity
function events.raise_pre_combinator_broken(combinator_id, combinator_entity)
end

return events
