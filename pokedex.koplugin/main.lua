local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local ImageWidget = require("ui/widget/imagewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalSpan = require("ui/widget/verticalspan")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Blitbuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local Font = require("ui/font")
local logger = require("logger")
local Geom = require("ui/geometry")

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

function Pokedex:showPopup(entry)
    local popup_width = math.floor(Screen:getWidth() * 0.85)
    local img_size = 150
    local padding = 12
    local text_width = popup_width - img_size - padding * 3

    -- Image
    local img_path = plugin_dir .. "/data/hires/" .. entry.id .. ".png"
    local image_widget = ImageWidget:new{
        file = img_path,
        width = img_size,
        height = img_size,
        scale_factor = 0,
    }

    -- Header text (name, type, species)
    local header_text = string.format(
        "#%03d %s / %s\n%s  —  %s",
        entry.id, entry.zh, entry.en, entry.type, entry.species
    )
    local header = TextBoxWidget:new{
        text = header_text,
        width = text_width,
        face = Font:getFace("cfont", 18),
    }

    -- Top row: image + header
    local top_row = HorizontalGroup:new{
        align = "top",
        image_widget,
        HorizontalSpan:new{ width = padding },
        header,
    }

    -- Divider
    local divider = FrameContainer:new{
        margin = 0,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_BLACK,
        FrameContainer:new{
            width = popup_width - padding * 2,
            height = 1,
            margin = 0,
            padding = 0,
            bordersize = 0,
        }
    }

    -- Description text
    local desc = TextBoxWidget:new{
        text = entry.desc,
        width = popup_width - padding * 2,
        face = Font:getFace("cfont", 16),
    }

    -- Stack everything vertically
    local content = FrameContainer:new{
        padding = padding,
        bordersize = 2,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            top_row,
            VerticalSpan:new{ width = padding },
            divider,
            VerticalSpan:new{ width = padding },
            desc,
        }
    }

    -- Center on screen
    local popup = CenterContainer:new{
        dimen = Screen:getSize(),
        content,
    }

    UIManager:show(popup)

    -- Close on tap
    popup.onTapClose = function()
        UIManager:close(popup)
        return true
    end
    popup.onAnyKeyPressed = function()
        UIManager:close(popup)
        return true
    end
end

function Pokedex:onCloseWidget()
end

return Pokedex
