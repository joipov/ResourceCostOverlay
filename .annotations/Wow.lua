---@meta

--- Forever secret-value helpers. Ketho Core may omit them.

---@type fun(value: any): boolean
issecretvalue = issecretvalue

---@type fun(value: any): boolean
canaccessvalue = canaccessvalue

---@type fun(value: any): boolean
issecrettable = issecrettable

---@type fun(value: any): boolean
canaccesstable = canaccesstable

-- Optional frames are read through `_G.<name>`. LuaLS has
-- the Lua builtins disabled, so `_G` has no index type and every such lookup is
-- an "undefined-field". Type `_G` here so those lookups resolve.
---@type table<string, any>
_G = _G
