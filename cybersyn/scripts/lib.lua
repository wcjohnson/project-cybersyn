local util = require "__core__.lualib.util"

--By Mami
---@param v string
---@param h string?
function once(v, h)
	return not h and v or nil--[[@as string|nil]]
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
		count = math.floor(count / divisor)
		local format = (math.abs(count) >= 10) and "%.0f%s" or "%.1f%s"
		return string.format(format, count, si_symbol)
	end

	local abs = math.abs(count)
	return -- signals are 32bit integers so Giga is enough
		abs >= 1e9 and si_format(1e9, "G") or
		abs >= 1e6 and si_format(1e6, "M") or
		abs >= 1e3 and si_format(1e3, "k") or
		tostring(count)
end
