--[[
  Spell names and macro text.

  A macro's first cast is not always reported with the rank the player wrote,
  and some names have spaces. These helpers read the macro body and split the
  "(Rank N)" suffix without a client call, so the tests can cover them.
]]

local _, ns = ...

--- "Renew(Rank 1)" -> "Renew", 1. Anything else keeps its name and nil rank.
function ns.SplitRankSuffix(text)
	if type(text) ~= "string" then
		return nil
	end
	local name, rank = text:match("^(.-)%s*%(%a+%s+(%d+)%)%s*$")
	if name and name ~= "" then
		return name, tonumber(rank)
	end
	return text, nil
end

--- The spell name on the first /cast, /use, or /castsequence line.
function ns.FirstCastToken(body)
	if type(body) ~= "string" then
		return nil
	end
	for line in body:gmatch("[^\r\n]+") do
		local command, rest = line:match("^%s*/(%a+)%s*(.-)%s*$")
		if command then
			command = command:lower()
			if command == "cast" or command == "use" then
				rest = rest:gsub("%b[]", "")
				rest = rest:match("^([^;]+)") or rest
				rest = rest:gsub("^%s*!?%s*", "")
				rest = rest:gsub("%s+$", "")
				if rest ~= "" then
					return rest
				end
			elseif command == "castsequence" then
				rest = rest:gsub("%b[]", "")
				rest = rest:gsub("^%s*reset%s*=%s*%S+%s*", "")
				local token = rest:match("^%s*!?%s*([^,]+)")
				if token then
					token = token:gsub("%s+$", "")
					if token ~= "" then
						return token
					end
				end
			end
		end
	end
	return nil
end
