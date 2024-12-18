-- Lifecycle management for train stops.
-- Train stop state is only created/destroyed in this module.

---Create a stored train-stop state.
---@param stop_entity LuaEntity A *valid* reference to a train stop.
---@return Cybersyn.TrainStop #The new stop state.
function stop_api.create_stop_state(stop_entity)
	local map_data = (storage --[[@as MapData]])
	local id = stop_entity.unit_number
	if not id then
		-- Should be impossible.
		error("Train-stop entity has no unit number.")
	end
	if map_data.train_stops[id] then
		error("Train-stop state already exists.")
	end
	map_data.train_stops[id] = {
		id = id,
		entity = stop_entity,
		combinator_set = {},
		layout = {
			accepted_layouts = {},
			rail_set = {},
		},
	} --[[@as Cybersyn.TrainStop]]

	return map_data.train_stops[id]
end

---Destroy a stored train-stop state.
---@param stop_id UnitNumber
---@return boolean `true` if the state was removed, `false` if it was not found.
function stop_api.destroy_stop_state(stop_id)
	local map_data = (storage --[[@as MapData]])
	if map_data.train_stops[stop_id] then
		map_data.train_stops[stop_id] = nil
		return true
	end
	return false
end

---Full teardown of a train-stop, disassociating combinators and firing events.
---@param stop_id UnitNumber
function stop_api.destroy_stop(stop_id)
	local stop = stop_api.get_stop_state(stop_id, true)
	if not stop then return end

	stop.is_being_destroyed = true

	-- Clear railset from global map
	local map_data = (storage --[[@as MapData]])
	for rail_id in pairs(stop.layout.rail_set) do
		map_data.rail_to_stop[rail_id] = nil
	end

	-- Reassociate all associated combinators
	if next(stop.combinator_set) then
		local associated_combs = map_table(stop.combinator_set, function(_, comb_id)
			return combinator_api.get_combinator_state(comb_id)
		end)
		stop_api.reassociate_combinators(associated_combs)
	end

	-- Remove the stop itself.
	raise_train_stop_destroyed(stop)
	stop_api.destroy_stop_state(stop_id)
end

local reassociate_recursive
local create_recursive

---@param combinators Cybersyn.Combinator[] A list of *valid* combinator states.
---@param depth number The current depth of the recursion.
function reassociate_recursive(combinators, depth)
	if depth > 100 then
		-- This would mean there is a continuous chain of
		-- 50 train stops linked to each other by ambiguous combinators.
		error("reassociate_recursive: Recursion limit reached.")
	end

	-- Stops whose combinator sets are being changed.
	---@type UnitNumberSet
	local affected_stop_set = {}
	-- Stop entities that need to be promoted to new Cybersyn stops.
	-- NOTE: can contain duplicates, recursive creation function should check.
	---@type LuaEntity[]
	local new_stop_entities = {}

	for _, combinator in ipairs(combinators) do
		-- Find the preferred stop for association
		local target_stop_entity, target_rail_entity = combinator_api.find_associable_entity(combinator.entity)
		---@type Cybersyn.TrainStop?
		local target_stop = nil
		if target_stop_entity then
			local stop = stop_api.get_stop_state(target_stop_entity.unit_number, true)
			if stop then
				-- Comb already associated with correct stop
				if combinator.stop_id == stop.id then goto continue end
				-- Comb needs to be reassociated to target stop.
				target_stop = stop
			else
				-- Comb is causing the creation of a new stop, which needs to be
				-- handled by recursion.
				table.insert(new_stop_entities, target_stop_entity)
			end
		elseif target_rail_entity then
			local stop = stop_api.find_stop_from_rail(target_rail_entity)
			if stop then
				if combinator.stop_id == stop.id then goto continue end
				target_stop = stop
			end
		end

		-- Disassociate if necessary
		if (not target_stop) or target_stop.is_being_destroyed or (combinator.stop_id and combinator.stop_id ~= target_stop.id) then
			local old_stop = stop_api.get_stop_state(combinator.stop_id, true)
			combinator.stop_id = nil
			if old_stop then
				old_stop.combinator_set[combinator.id] = nil
				raise_combinator_disassociated(combinator, old_stop)
				affected_stop_set[old_stop.id] = true
			end
		end

		-- Associate if possible
		if target_stop and (not target_stop.is_being_destroyed) then
			target_stop.combinator_set[combinator.id] = true
			combinator.stop_id = target_stop.id
			affected_stop_set[target_stop.id] = true
			raise_combinator_associated(combinator, target_stop)
		end
		::continue::
	end

	-- Fire batch set-change events; destroy empty stops.
	for stop_id in pairs(affected_stop_set) do
		local stop = stop_api.get_stop_state(stop_id)
		if stop then
			raise_train_stop_combinator_set_changed(stop)
			if not next(stop.combinator_set) then
				-- Should be no recursion here as the comb set is empty.
				stop_api.destroy_stop(stop.id)
			end
		end
	end

	-- Create new stops as needed, recursively reassociating combinators near
	-- the created stops.
	if #new_stop_entities > 0 then
		create_recursive(new_stop_entities, depth + 1)
	end
end

---@param stop_entities LuaEntity[] A list of *valid* train stop entities that are not already Cybersyn stops. They will be promoted to Cybersyn stops.
---@param depth number The current depth of the recursion.
function create_recursive(stop_entities, depth)
	if depth > 100 then
		-- This would mean there is a continuous chain of
		-- 50 train stops linked to each other by ambiguous combinators.
		error("create_recursive: Recursion limit reached.")
	end

	for _, stop_entity in ipairs(stop_entities) do
		local stop_id = stop_entity.unit_number --[[@as uint]]
		local stop = stop_api.get_stop_state(stop_id, true)
		if stop then
			-- Elide duplicate stop creation.
			goto continue
		end
		stop = stop_api.create_stop_state(stop_entity)
		stop.is_being_created = true
		raise_train_stop_created(stop)
		-- Recursively reassociate combinators near the new stop.
		local combs = stop_api.find_associable_combinators(stop_entity)
		if #combs > 0 then
			local comb_states = map(combs, function(comb)
				return combinator_api.get_combinator_state(comb.unit_number)
			end)
			reassociate_recursive(comb_states, depth + 1)
		end
		stop.is_being_created = nil
		raise_train_stop_post_created(stop)
		::continue::
	end
end

---Re-evaluate the preferred associations of all the given combinators and
---reassociate them en masse as necessary.
---@param combinators Cybersyn.Combinator[] A list of *valid* combinator states.
function stop_api.reassociate_combinators(combinators)
	return reassociate_recursive(combinators, 1)
end

on_train_stop_post_created(function(stop)
	-- Perform initial scan of stop layout
	stop_api.compute_layout(stop)
end)
