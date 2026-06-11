local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local Pokedex = WidgetContainer:extend{
    name = "pokedex",
    _data = nil,  -- lazy-loaded lookup table
}

-- Resolve the data directory relative to this file
local plugin_dir = (debug.getinfo(1, "S").source:sub(2)):match("^(.*)/[^/]+$") or "."

function Pokedex:_loadData()
    if self._data then return self._data end
    local path = plugin_dir .. "/data/pokedex.lua"
    local ok, data = pcall(dofile, path)
    if not ok then
        logger.warn("Pokedex: failed to load data:", data)
        self._data = {}
    else
        self._data = data
    end
    return self._data
end

function Pokedex:lookup(word)
    if not word or word == "" then return nil end
    local data = self:_loadData()
    return data[word:lower()]
end

function Pokedex:init()
    -- hook installed in Task 5
end

function Pokedex:onCloseWidget()
end

return Pokedex
