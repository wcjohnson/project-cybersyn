--By Mami
local area = require("__flib__.bounding-box")
local abs = math.abs
local floor = math.floor
local ceil = math.ceil
local min = math.min
local max = math.max
local bit_extract = bit32.extract

---@param layout_pattern (0|1|2|3)[]
---@param layout (0|1|2)[]
function is_refuel_layout_accepted(layout_pattern, layout)
	local valid = true
	for i, v in ipairs(layout) do
		local p = layout_pattern[i] or 0
		if (v == 1 and (p == 1 or p == 3)) or (v == 2 and (p == 2 or p == 3)) then
			valid = false
			break
		end
	end
	if valid or not layout[0] then return valid end
	for i, v in irpairs(layout) do
		local p = layout_pattern[i] or 0
		if (v == 1 and (p == 1 or p == 3)) or (v == 2 and (p == 2 or p == 3)) then
			valid = false
			break
		end
	end
	return valid
end
---@param layout_pattern (0|1|2|3)[]
---@param layout (0|1|2)[]
function is_layout_accepted(layout_pattern, layout)
	local valid = true
	for i, v in ipairs(layout) do
		local p = layout_pattern[i] or 0
		if (v == 1 and not (p == 1 or p == 3)) or (v == 2 and not (p == 2 or p == 3)) then
			valid = false
			break
		end
	end
	if valid or not layout[0] then return valid end
	for i, v in irpairs(layout) do
		local p = layout_pattern[i] or 0
		if (v == 1 and not (p == 1 or p == 3)) or (v == 2 and not (p == 2 or p == 3)) then
			valid = false
			break
		end
	end
	return valid
end

---@param map_data MapData
---@param train_id uint
---@param train Train
function remove_train(map_data, train_id, train)
	if train.manifest then
		on_failed_delivery(map_data, train_id, train)
	end
	remove_available_train(map_data, train_id, train)

	local layout_id = train.layout_id
	local count = storage.layout_train_count[layout_id]
	if count <= 1 then
		storage.layout_train_count[layout_id] = nil
		storage.layouts[layout_id] = nil
		for _, stop in pairs(storage.stations) do
			stop.accepted_layouts[layout_id] = nil
		end
		for _, stop in pairs(storage.refuelers) do
			stop.accepted_layouts[layout_id] = nil
		end
	else
		storage.layout_train_count[layout_id] = count - 1
	end

	map_data.trains[train_id] = nil
	interface_raise_train_removed(train_id, train)
end

---@param map_data MapData
---@param train Train
function set_train_layout(map_data, train)
	local carriages = train.entity.carriages
	local layout = {}
	local i = 1
	local item_slot_capacity = 0
	local fluid_capacity = 0
	for _, carriage in pairs(carriages) do
		if carriage.type == "cargo-wagon" then
			layout[#layout + 1] = 1
			local inv = carriage.get_inventory(defines.inventory.cargo_wagon)
			item_slot_capacity = item_slot_capacity + #inv
		elseif carriage.type == "fluid-wagon" then
			layout[#layout + 1] = 2
			fluid_capacity = fluid_capacity + carriage.prototype.fluid_capacity
		else
			layout[#layout + 1] = 0
		end
		i = i + 1
	end
	local back_movers = train.entity.locomotives["back_movers"]
	if #back_movers > 0 then
		--mark the layout as reversible
		layout[0] = true
	end

	local layout_id = 0
	for id, cur_layout in pairs(map_data.layouts) do
		if table_compare(layout, cur_layout) then
			layout = cur_layout
			layout_id = id
			break
		end
	end
	if layout_id == 0 then
		--define new layout
		layout_id = map_data.layout_top_id
		map_data.layout_top_id = map_data.layout_top_id + 1

		map_data.layouts[layout_id] = layout
		map_data.layout_train_count[layout_id] = 1
		for _, stop in pairs(map_data.stations) do
			if stop.layout_pattern then
				stop.accepted_layouts[layout_id] = is_layout_accepted(stop.layout_pattern, layout) or nil
			end
		end
		for _, stop in pairs(map_data.refuelers) do
			if stop.layout_pattern then
				stop.accepted_layouts[layout_id] = is_refuel_layout_accepted(stop.layout_pattern, layout) or nil
			end
		end
	else
		map_data.layout_train_count[layout_id] = map_data.layout_train_count[layout_id] + 1
	end
	train.layout_id = layout_id
	train.item_slot_capacity = item_slot_capacity
	train.fluid_capacity = fluid_capacity
end

---@param stop LuaEntity
---@param train LuaTrain
local function get_train_direction(stop, train)
	local back_end = train.get_rail_end(defines.rail_direction.back)

	if back_end and back_end.rail then
		local back_pos = back_end.rail.position
		local stop_pos = stop.position
		if abs(back_pos.x - stop_pos.x) < 3 and abs(back_pos.y - stop_pos.y) < 3 then
			return true
		end
	end

	return false
end

---@param map_data MapData
---@param station Station
---@param train Train
function set_p_wagon_combs(map_data, station, train)
	if not station.wagon_combs or not next(station.wagon_combs) then return end
	local carriages = train.entity.carriages
	local manifest = train.manifest --[[@as Manifest]]
	if not manifest[1] then return end
	local sign = mod_settings.invert_sign and 1 or -1

	local is_reversed = get_train_direction(station.entity_stop, train.entity)

	local locked_slots = station.locked_slots
	local percent_slots_to_use_per_wagon = 1.0
	if train.item_slot_capacity > 0 then
		local total_item_slots
		if locked_slots > 0 then
			local total_cargo_wagons = #train.entity.cargo_wagons
			total_item_slots = max(train.item_slot_capacity - total_cargo_wagons * locked_slots, 1)
		else
			total_item_slots = train.item_slot_capacity
		end

		local to_be_used_item_slots = 0
		for i, item in ipairs(train.manifest) do
			if not item.type or item.type == "item" then
				to_be_used_item_slots = to_be_used_item_slots + ceil(item.count / get_stack_size(map_data, item.name))
			end
		end
		percent_slots_to_use_per_wagon = min(to_be_used_item_slots / total_item_slots, 1.0)
	end

	local item_i = 1
	local item = manifest[item_i]
	local item_count = item.count
	local item_qual = item.quality or "normal"
	local fluid_i = 1
	local fluid = manifest[fluid_i]
	local fluid_count = fluid.count

	local ivpairs = is_reversed and irpairs or ipairs
	for carriage_i, carriage in ivpairs(carriages) do
		--NOTE: we are not checking valid
		---@type LuaEntity?
		local comb = station.wagon_combs[carriage_i]
		if comb and not comb.valid then
			comb = nil
			station.wagon_combs[carriage_i] = nil
			if next(station.wagon_combs) == nil then
				station.wagon_combs = nil
				break
			end
		end
		if carriage.type == "cargo-wagon" then
			local inv = carriage.get_inventory(defines.inventory.cargo_wagon)
			if inv then
				---@type ConstantCombinatorParameters[]
				local signals = {}

				local inv_filter_i = 1
				local item_slots_capacity = max(ceil((#inv - locked_slots) * percent_slots_to_use_per_wagon), 1)
				while item_slots_capacity > 0 and item_i <= #manifest do
					local do_inc
					if not item.type or item.type == "item" then
						local stack_size = get_stack_size(map_data, item.name)
						local i = #signals + 1
						local count_to_fill = min(item_slots_capacity * stack_size, item_count)
						local slots_to_fill = ceil(count_to_fill / stack_size)

						signals[i] = {
							value = { type = item.type, name = item.name, quality = item_qual, comparator = "=" },
							min = sign * count_to_fill,
						}
						item_count = item_count - count_to_fill
						item_slots_capacity = item_slots_capacity - slots_to_fill
						if comb then
							for j = 1, slots_to_fill do
								inv.set_filter(inv_filter_i, { name = item.name, quality = item_qual, comparator = "=" })
								inv_filter_i = inv_filter_i + 1
							end
							train.has_filtered_wagon = true
						end
						do_inc = item_count == 0
					else
						do_inc = true
					end
					if do_inc then
						item_i = item_i + 1
						if item_i <= #manifest then
							item = manifest[item_i]
							item_count = item.count
							item_qual = item.quality or "normal"
						else
							break
						end
					end
				end

				if comb then
					if bit_extract(get_comb_params(comb).second_constant, SETTING_ENABLE_SLOT_BARRING) > 0 then
						inv.set_bar(inv_filter_i --[[@as uint]])
						train.has_filtered_wagon = true
					end
					set_combinator_output(map_data, comb, signals)
				end
			end
		elseif carriage.type == "fluid-wagon" then
			local fluid_capacity = carriage.prototype.fluid_capacity
			local signals = {}

			while fluid_capacity > 0 and fluid_i <= #manifest do
				local do_inc
				if fluid.type == "fluid" then
					local count_to_fill = min(fluid_count, fluid_capacity)

					signals[1] = { index = 1, signal = { type = fluid.type, name = fluid.name }, count = sign * count_to_fill }
					fluid_count = fluid_count - count_to_fill
					fluid_capacity = 0
					do_inc = fluid_count == 0
				else
					do_inc = true
				end
				if do_inc then
					fluid_i = fluid_i + 1
					if fluid_i <= #manifest then
						fluid = manifest[fluid_i]
						fluid_count = fluid.count
					end
				end
			end

			if comb then
				set_combinator_output(map_data, comb, signals)
			end
		end
	end
end

---@param map_data MapData
---@param station Station
---@param train Train
function set_r_wagon_combs(map_data, station, train)
	if not station.wagon_combs then return end
	local carriages = train.entity.carriages

	local is_reversed = get_train_direction(station.entity_stop, train.entity)
	local sign = mod_settings.invert_sign and -1 or 1

	local ivpairs = is_reversed and irpairs or ipairs
	for carriage_i, carriage in ivpairs(carriages) do
		---@type LuaEntity?
		local comb = station.wagon_combs[carriage_i]
		if comb and not comb.valid then
			comb = nil
			station.wagon_combs[carriage_i] = nil
			if next(station.wagon_combs) == nil then
				station.wagon_combs = nil
				break
			end
		end
		if comb and carriage.type == "cargo-wagon" then
			local inv = carriage.get_inventory(defines.inventory.cargo_wagon)
			if inv then
				local signals = {}
				for stack_i = 1, #inv do
					local stack = inv[stack_i]
					if stack.valid_for_read then
						local i = #signals + 1
						signals[i] = {
							value = { type = "item", name = stack.name, quality = stack.quality or "normal", comparator = "=" },
							min = sign * stack.count,
						}
					end
				end
				set_combinator_output(map_data, comb, signals)
			end
		elseif comb and carriage.type == "fluid-wagon" then
			local signals = {}

			local inv = carriage.get_fluid_contents()
			for fluid_name, count in pairs(inv) do
				local i = #signals + 1
				-- FIXME ? pump conditions can have quality (but why? fluids can only be produced at normal quality and pump filters ignore quality)
				signals[i] = {
					value = { type = "fluid", name = fluid_name, quality = "normal", comparator = "=" },
					min = sign * floor(count),
				}
			end
			set_combinator_output(map_data, comb, signals)
		end
	end
end

---@param map_data MapData
---@param refueler Refueler
---@param train Train
function set_refueler_combs(map_data, refueler, train)
	if not refueler.wagon_combs then return end
	local carriages = train.entity.carriages

	local signals = {}

	local is_reversed = get_train_direction(refueler.entity_stop, train.entity)
	local ivpairs = is_reversed and irpairs or ipairs
	for carriage_i, carriage in ivpairs(carriages) do
		---@type LuaEntity?
		local comb = refueler.wagon_combs[carriage_i]
		if comb and not comb.valid then
			comb = nil
			refueler.wagon_combs[carriage_i] = nil
			if next(refueler.wagon_combs) == nil then
				refueler.wagon_combs = nil
				break
			end
		end
		local inv = carriage.get_fuel_inventory()
		if inv then
			local wagon_signals
			if comb then
				wagon_signals = {}
				local array = carriage.prototype.items_to_place_this
				if array then
					local a = array[1]
					local name
					if type(a) == "string" then
						name = a
					else
						name = a.name
					end
					if prototypes.item[name] then
						wagon_signals[1] = { value = { type = "item", name = a.name, quality = "normal", comparator = "=" }, min = 1 }
					end
				end
			end
			for stack_i = 1, #inv do
				local stack = inv[stack_i]
				if stack.valid_for_read then
					if comb then
						local i = #wagon_signals + 1
						wagon_signals[i] = {
							value = {
								type = "item",
								name = stack.name,
								quality = stack.quality or "normal",
								comparator = "=",
							},
							min = stack.count,
						}
					end
					local j = #signals + 1
					signals[j] = {
						value = { type = "item", name = stack.name, quality = stack.quality or "normal", comparator = "=" },
						min = stack.count,
					}
				end
			end
			if comb then
				set_combinator_output(map_data, comb, wagon_signals)
			end
		end
	end

	set_combinator_output(map_data, refueler.entity_comb, signals)
end

---@param map_data MapData
---@param stop Station|Refueler
function unset_wagon_combs(map_data, stop)
	if not stop.wagon_combs then return end

	for i, comb in pairs(stop.wagon_combs) do
		if comb.valid then
			set_combinator_output(map_data, comb, nil)
		else
			stop.wagon_combs[i] = nil
		end
	end
	if next(stop.wagon_combs) == nil then
		stop.wagon_combs = nil
	end
end
