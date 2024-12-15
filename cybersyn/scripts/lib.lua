local util = require "__core__.lualib.util"
local abs = math.abs

--By Mami
---@param v string
---@param h string?
function once(v, h)
	return not h and v or nil --[[@as string|nil]]
end
---@param t any[]
---@return any
function rnext_consume(t)
	local len = #t
	if len > 1 then
		local i = math.random(1, len)
		local v = t[i]
		t[i] = t[len]
		t[len] = nil
		return v
	else
		local v = t[1]
		t[1] = nil
		return v
	end
end

function table_compare(t0, t1)
	if #t0 ~= #t1 then
		return false
	end
	for i = 0, #t0 do
		if t0[i] ~= t1[i] then
			return false
		end
	end
	return true
end

---@param a any[]
---@param i uint
function irnext(a, i)
	i = i + 1
	if i <= #a then
		local r = a[#a - i + 1]
		return i, r
	else
		return nil, nil
	end
end

---@param a any[]
function irpairs(a)
	return irnext, a, 0
end

--- @generic K
--- @param t1 table<K, any>
--- @param t2 table<K, any>
--- @return fun(): K?
function dual_pairs(t1, t2)
	local state = true
	local key = nil
	return function()
		if state then
			key = next(t1, key)
			if key then
				return key
			end
			state = false
		end
		repeat
			key = next(t2, key)
		until t1[key] == nil
		return key
	end
end

---Filter an array by a predicate, creating a new array containing only those
---elements for which the predicate returns `true`.
---@generic T
---@param A T[]
---@param f fun(v: T): boolean
---@return T[]
function filter(A, f)
	local B = {}
	for i = 1, #A do
		local v = A[i]
		if f(v) then
			B[#B + 1] = v
		end
	end
	return B
end

---Filter an array in place by a predicate, removing all elements for which the
---predicate returns `false`.
---@generic T
---@param A T[]
---@param f fun(v: T): boolean
---@return T[] A The input array, with non-matching elements removed.
function filter_in_place(A, f)
	local j = 1
	for i = 1, #A do
		local v = A[i]
		if f(v) then
			A[j] = v
			j = j + 1
		end
	end
	for i = j, #A do
		A[i] = nil
	end
	return A
end

---Map an array to a new array by applying a function to each element. The
---non-`nil` return values are collected in order into the result array.
---@generic T, U
---@param A T[]
---@param f fun(v: T): U?
---@return U[]
function map(A, f)
	local B = {}
	for i = 1, #A do
		local x = f(A[i])
		if x ~= nil then
			B[#B + 1] = x
		end
	end
	return B
end

---Map an array in place by applying a function to each element. Elements
---are replaced by the return values of the function. If the function
---returns `nil`, the element is removed from the array.
---@generic T
---@param A T[]
---@param f fun(v: T): T?
---@return T[] A The input array, with elements mapped.
function map_in_place(A, f)
	local j = 1
	for i = 1, #A do
		local x = f(A[i])
		if x ~= nil then
			A[j] = x
			j = j + 1
		end
	end
	for i = j, #A do
		A[i] = nil
	end
	return A
end

---Map a table to a new array by applying a function to each key-value pair.
---The non-`nil` return values are collected into the result array.
---@generic K, V, O
---@param T table<K, V>
---@param f fun(v: V, k: K): O?
---@return O[]
function map_table(T, f)
	local A = {}
	for k, v in pairs(T) do
		local x = f(v, k)
		if x ~= nil then
			A[#A + 1] = x
		end
	end
	return A
end

---@param quality_id QualityID?
---@return string? quality_name The name of the quality, or `nil` if the quality is `nil`.
function quality_id_to_name(quality_id)
	if quality_id then
		if type(quality_id) == "string" then
			return quality_id
		else
			return quality_id.name
		end
	else
		return nil
	end
end

---Determine if two SignalID values are equal
---@param s0 SignalID?
---@param s1 SignalID?
---@return boolean
function signal_eq(s0, s1)
	if s0 == nil or s1 == nil then return s0 == s1 end
	if s0.name ~= s1.name then return false end
	local type0, type1 = s0.type or "item", s1.type or "item"
	if type0 ~= type1 then return false end
	local qual0, qual1 = quality_id_to_name(s0.quality), quality_id_to_name(s1.quality)
	if qual0 ~= qual1 then return false end
	return true
end

--- @param count integer
--- @return string
function format_signal_count(count)
	local function si_format(divisor, si_symbol)
		if math.abs(math.floor(count / divisor)) >= 10 then
			count = math.floor(count / divisor)
			return string.format("%.0f%s", count, si_symbol)
		else
			count = math.floor(count / (divisor / 10)) / 10
			return string.format("%.1f%s", count, si_symbol)
		end
	end

	local abs = math.abs(count)
	return -- signals are 32bit integers so Giga is enough
			abs >= 1e9 and si_format(1e9, "G") or
			abs >= 1e6 and si_format(1e6, "M") or
			abs >= 1e3 and si_format(1e3, "k") or
			tostring(count)
end

-- BoundingBox utils that avoid creating lua garbage. (The flib versions allocate numerous temporary tables.)

--- Get the four corners of any bbox.
---@param bbox BoundingBox
---@return number left
---@return number top
---@return number right
---@return number bottom
function bbox_get(bbox)
	local lt, rb
	if bbox.left_top then
		lt, rb = bbox.left_top, bbox.right_bottom
	else
		lt, rb = bbox[1], bbox[2]
	end
	if lt.x then
		if rb.x then
			return lt.x, lt.y, rb.x, rb.y
		else
			return lt.x, lt.y, rb[1], rb[2]
		end
	else
		if rb.x then
			return lt[1], lt[2], rb.x, rb.y
		else
			return lt[1], lt[2], rb[1], rb[2]
		end
	end
end

--- Mutate a bbox, setting its corners.
---@param bbox BoundingBox
---@param left number
---@param top number
---@param right number
---@param bottom number
---@return BoundingBox bbox The mutated bbox.
function bbox_set(bbox, left, top, right, bottom)
	local lt, rb
	if bbox.left_top then
		lt, rb = bbox.left_top, bbox.right_bottom
	else
		lt, rb = bbox[1], bbox[2]
	end
	if lt.x then
		if rb.x then
			lt.x, lt.y, rb.x, rb.y = left, top, right, bottom
		else
			lt.x, lt.y, rb[1], rb[2] = left, top, right, bottom
		end
	else
		if rb.x then
			lt[1], lt[2], rb.x, rb.y = left, top, right, bottom
		else
			lt[1], lt[2], rb[1], rb[2] = left, top, right, bottom
		end
	end
	return bbox
end

---Extend a bbox to contain another bbox, mutating the first.
---@param bbox1 BoundingBox
---@param bbox2 BoundingBox
---@return BoundingBox bbox1 The first bbox, extended to contain the second.
function bbox_contain(bbox1, bbox2)
	local l1, t1, r1, b1 = bbox_get(bbox1)
	local l2, t2, r2, b2 = bbox_get(bbox2)
	return bbox_set(bbox1, math.min(l1, l2), math.min(t1, t2), math.max(r1, r2), math.max(b1, b2))
end

---Grow a bbox by the given amount in the given ortho direction.
---@param bbox BoundingBox
---@param dir defines.direction
---@param amount number
---@return BoundingBox bbox The mutated bbox.
function bbox_extend(bbox, dir, amount)
	local l, t, r, b = bbox_get(bbox)
	if dir == defines.direction.north then
		t = t - amount
	elseif dir == defines.direction.south then
		b = b + amount
	elseif dir == defines.direction.east then
		r = r + amount
	elseif dir == defines.direction.west then
		l = l - amount
	end
	return bbox_set(bbox, l, t, r, b)
end

---Get the coordinates of a position.
---@param pos MapPosition
function pos_get(pos)
	if pos.x then
		return pos.x, pos.y
	else
		return pos[1], pos[2]
	end
end

---Move a position by the given amount in the given ortho direction.
---@param pos MapPosition
---@param dir defines.direction
---@param amount number
---@return MapPosition pos A new position moved in the given direction.
function pos_move(pos, dir, amount)
	local x, y = pos_get(pos)
	if dir == defines.direction.north then
		y = y - amount
	elseif dir == defines.direction.south then
		y = y + amount
	elseif dir == defines.direction.east then
		x = x + amount
	elseif dir == defines.direction.west then
		x = x - amount
	end
	return { x, y }
end

---Returns the primary orthogonal direction from `pos1` to `pos2`. This is one of the
---`defines.direction` constants.
---@param pos1 MapPosition
---@param pos2 MapPosition
---@return defines.direction
function dir_ortho(pos1, pos2)
	local x1, y1 = pos_get(pos1)
	local x2, y2 = pos_get(pos2)
	local dx, dy = x2 - x1, y2 - y1
	if abs(dx) > abs(dy) then
		return dx > 0 and defines.direction.east or defines.direction.west
	else
		return dy > 0 and defines.direction.south or defines.direction.north
	end
end

---Measure the distance of the given point along the given orthogonal axis
---of the given bounding box. The direction indicates the positive measurement
---axis, with the zero point of the axis being on the opposite side of the box.
---@param bbox BoundingBox
---@param direction defines.direction One of the four cardinal directions. Other directions will give invalid results.
---@param point MapPosition
---@return number distance The distance along the axis.
function dist_ortho_bbox(bbox, direction, point)
	local l, t, r, b = bbox_get(bbox)
	local x, y = pos_get(point)
	if direction == defines.direction.north then
		return b - y
	elseif direction == defines.direction.south then
		return y - t
	elseif direction == defines.direction.east then
		return x - l
	elseif direction == defines.direction.west then
		return r - x
	else
		error("dist_ortho_bbox: Invalid direction")
	end
end
