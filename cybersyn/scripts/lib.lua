local util = require "__core__.lualib.util"
local table_insert = table.insert

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

--- Map an array into an array using a mapping function.
---@generic I
---@generic O
---@param array I[]
---@param fn fun(value: I, index: uint): O?
---@return O[]
function map(array, fn)
	local new_array = {}
	for i, v in ipairs(array) do
		local x = fn(v, i)
		if x ~= nil then table_insert(new_array, x) end
	end
	return new_array
end

--- Map a table into an array using a mapping function.
---@generic K
---@generic V
---@generic T
---@param tbl table<K, V>
---@param fn fun(value: V, key: K): T?
---@return T[]
function tmap(tbl, fn)
	local array = {}
	for k, v in pairs(tbl) do
		local x = fn(v, k)
		if x ~= nil then table_insert(array, x) end
	end
	return array
end
