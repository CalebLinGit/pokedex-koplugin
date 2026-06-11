# Pokédex KOReader Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A KOReader plugin that intercepts dictionary lookup for Pokémon names and shows a popup with the Pokémon's official artwork and English flavor text.

**Architecture:** A Python script generates a Lua lookup table and copies resized images into the plugin directory. At runtime, the plugin monkey-patches `ReaderDictionary.onLookupWord` to intercept word lookups — if the word is a Pokémon name it shows a custom image+text popup, otherwise the normal dictionary flow runs.

**Tech Stack:** Python 3 (data generation), Lua (KOReader plugin), Pillow (image resizing), KOReader's `ImageWidget` / `TextBoxWidget` / `FrameContainer`

---

## File Map

| File | Role |
|------|------|
| `make_pokedex_data.py` | One-time data generation: reads `pokedex.json`, writes `pokedex.lua`, resizes + copies images |
| `pokedex.koplugin/_meta.lua` | Plugin metadata (name, description) |
| `pokedex.koplugin/main.lua` | Plugin logic: hook, lookup, popup |
| `pokedex.koplugin/data/pokedex.lua` | Generated Lua table: name → entry |
| `pokedex.koplugin/data/hires/*.png` | Resized 150×150 images, copied by script |

---

## Task 1: Data generation script

**Files:**
- Create: `make_pokedex_data.py`

Prereq: download `pokedex.json` from `https://raw.githubusercontent.com/Purukitto/pokemon-data.json/master/pokedex.json` and the `images/pokedex/hires/` folder from the same repo. Easiest: `git clone https://github.com/Purukitto/pokemon-data.json.git` into a temp directory.

- [ ] **Install Pillow if needed**

```bash
pip install Pillow
```

- [ ] **Write `make_pokedex_data.py`**

```python
#!/usr/bin/env python3
"""
Generate pokedex.koplugin/data/ from a local clone of Purukitto/pokemon-data.json.
Usage: python make_pokedex_data.py <path-to-pokemon-data.json-repo>
"""

import json, sys, shutil
from pathlib import Path
from PIL import Image

REPO = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("pokemon-data.json")
OUT_DIR = Path("pokedex.koplugin/data")
IMG_DIR = OUT_DIR / "hires"
IMG_SIZE = (150, 150)

def escape_lua(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")

def main():
    data = json.loads((REPO / "pokedex.json").read_text(encoding="utf-8"))
    IMG_DIR.mkdir(parents=True, exist_ok=True)

    lua_lines = ["return {"]

    for entry in data:
        pid   = entry["id"]
        zh    = entry["name"].get("chinese", "")
        en    = entry["name"].get("english", "")
        typ   = ", ".join(entry.get("type", []))
        spec  = entry.get("species", "")
        desc  = entry.get("description", "")

        lua_entry = (
            f'  id={pid}, en="{escape_lua(en)}", '
            f'zh="{escape_lua(zh)}", type="{escape_lua(typ)}", '
            f'species="{escape_lua(spec)}", desc="{escape_lua(desc)}"'
        )
        entry_str = f"  {{ {lua_entry} }}"

        # Index by lowercase Chinese and lowercase English name
        for key in [zh.lower(), en.lower()]:
            if key:
                lua_lines.append(f'  ["{escape_lua(key)}"] = {entry_str},')

        # Resize and copy image
        src = REPO / "images" / "pokedex" / "hires" / f"{pid}.png"
        dst = IMG_DIR / f"{pid}.png"
        if src.exists() and not dst.exists():
            img = Image.open(src).convert("RGBA")
            img = img.resize(IMG_SIZE, Image.LANCZOS)
            img.save(dst, "PNG", optimize=True)
            print(f"  #{pid} {en}")

    lua_lines.append("}")
    (OUT_DIR / "pokedex.lua").write_text("\n".join(lua_lines), encoding="utf-8")
    print(f"\nWrote {OUT_DIR}/pokedex.lua")
    print(f"Images in {IMG_DIR}/")

if __name__ == "__main__":
    main()
```

- [ ] **Run the script**

```bash
# Assuming you cloned the repo alongside this project:
git clone https://github.com/Purukitto/pokemon-data.json.git /tmp/pokemon-data.json
python make_pokedex_data.py /tmp/pokemon-data.json
```

Expected output: prints each Pokémon as it resizes, then reports file paths.

- [ ] **Verify output**

```bash
wc -l pokedex.koplugin/data/pokedex.lua   # should be ~1800 lines (2 keys × 898 + 2)
ls pokedex.koplugin/data/hires/ | wc -l   # should be 898
python3 -c "
l = open('pokedex.koplugin/data/pokedex.lua').read()
assert '蔓藤怪' in l
assert 'tangela' in l
print('OK')
"
```

- [ ] **Commit**

```bash
git add make_pokedex_data.py pokedex.koplugin/data/
git commit -m "feat: add pokedex data generation script and generated data"
```

---

## Task 2: Plugin metadata

**Files:**
- Create: `pokedex.koplugin/_meta.lua`

- [ ] **Write `_meta.lua`**

```lua
return {
    name = "pokedex",
    fullname = "Pokédex Lookup",
    description = "Long-press a Pokémon name to view its artwork and description.",
}
```

- [ ] **Commit**

```bash
git add pokedex.koplugin/_meta.lua
git commit -m "feat: add pokedex plugin metadata"
```

---

## Task 3: Plugin skeleton + lookup table

**Files:**
- Create: `pokedex.koplugin/main.lua`

- [ ] **Write the plugin skeleton with lookup logic**

```lua
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local DATA_PATH = require("datastorage").getDataDir()  -- we'll override below

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
```

- [ ] **Smoke-test the lookup on desktop KOReader**

Install to local KOReader plugins dir:
```bash
cp -r pokedex.koplugin ~/Library/Application\ Support/koreader/plugins/
```
Open KOReader, open any book, open the Lua console (if available) or check that the plugin loads without errors in the log.

- [ ] **Commit**

```bash
git add pokedex.koplugin/main.lua
git commit -m "feat: add pokedex plugin skeleton with lazy data loading"
```

---

## Task 4: Popup widget

**Files:**
- Modify: `pokedex.koplugin/main.lua`

The popup shows:
- Left: 150×150 Pokémon image (grayscale on e-ink naturally)
- Right: `#ID 中文名 / English`, type, species
- Below divider: flavor text description

KOReader widgets used:
- `ImageWidget` — renders a PNG file
- `TextWidget` / `TextBoxWidget` — renders text
- `HorizontalGroup`, `VerticalGroup` — layout
- `FrameContainer` — border + background
- `ButtonDialog` or `UIManager:show()` — display

- [ ] **Add popup imports at the top of `main.lua`**

Replace the existing `local` block at the top with:

```lua
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local ImageWidget = require("ui/widget/imagewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Blitbuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local Font = require("ui/font")
local logger = require("logger")
local Geom = require("ui/geometry")
```

- [ ] **Add `showPopup` method to `Pokedex`**

Add this method to the `Pokedex` table (before `return Pokedex`):

```lua
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
        HorizontalGroup:new{ width = padding },
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
            VerticalGroup:new{ height = padding },
            divider,
            VerticalGroup:new{ height = padding },
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
```

- [ ] **Test popup on desktop: manually call it**

Temporarily add to `init`:
```lua
function Pokedex:init()
    -- TEMP: show popup for Tangela on load
    local entry = self:lookup("tangela")
    if entry then self:showPopup(entry) end
end
```
Restart KOReader and open a book. The popup should appear immediately. Verify image and text render correctly.

- [ ] **Remove the temp test code from `init`**

```lua
function Pokedex:init()
    -- hook installed in Task 5
end
```

- [ ] **Commit**

```bash
git add pokedex.koplugin/main.lua
git commit -m "feat: add pokedex popup widget with image and flavor text"
```

---

## Task 5: Hook into dictionary word lookup

**Files:**
- Modify: `pokedex.koplugin/main.lua`

KOReader's dictionary lookup is triggered by `ReaderDictionary:onLookupWord(word)`. We monkey-patch this method in our plugin's `init` so we get first look at every word. If it's a Pokémon name we show our popup and return; otherwise the original dictionary runs normally.

- [ ] **Replace `init` with the hook**

```lua
function Pokedex:init()
    local dict = self.ui.dictionary
    if not dict then
        logger.warn("Pokedex: ReaderDictionary not found, hook not installed")
        return
    end

    local orig_lookup = dict.onLookupWord
    local pokedex = self

    dict.onLookupWord = function(d, word, ...)
        local entry = pokedex:lookup(word)
        if entry then
            pokedex:showPopup(entry)
            return true  -- stop propagation; skip normal dictionary
        end
        return orig_lookup(d, word, ...)
    end

    logger.info("Pokedex: hook installed on ReaderDictionary.onLookupWord")
end
```

- [ ] **Test the hook on desktop KOReader**

Open KOReader with the test file `pokedex_test.txt` (it contains names like 皮卡丘, 妙蛙种子, 喷火龙). Long-press one of those names and select "Dict". The Pokédex popup should appear instead of the dictionary.

Long-press a non-Pokémon word (e.g., "今天"). The normal dictionary should appear as usual.

- [ ] **Test on Kindle**

Deploy:
```bash
scp -P 2222 -i ~/.ssh/id_ed25519 -r pokedex.koplugin root@192.168.68.130:/mnt/us/koreader/plugins/
```
Restart KOReader. Open a book, long-press a Pokémon name, verify popup appears.

- [ ] **Commit**

```bash
git add pokedex.koplugin/main.lua
git commit -m "feat: hook pokedex into dictionary word lookup"
```

---

## Task 6: Cleanup

**Files:**
- Delete: `make_pokedex_dict.py` (old StarDict approach, replaced)

- [ ] **Delete old script**

```bash
git rm make_pokedex_dict.py
```

- [ ] **Verify nothing references it**

```bash
grep -r "make_pokedex_dict" . --include="*.py" --include="*.md" --include="*.lua"
# Expected: no output
```

- [ ] **Final commit**

```bash
git commit -m "chore: remove old stardict pokedex script"
```

---

## Self-Review

- [x] Spec coverage: data generation ✓, plugin skeleton ✓, lookup ✓, popup ✓, hook ✓, deploy ✓
- [x] No placeholders or TBDs
- [x] Type consistency: `entry.id`, `entry.zh`, `entry.en`, `entry.type`, `entry.species`, `entry.desc` used consistently across Tasks 1, 3, 4
- [x] `plugin_dir` defined in Task 3 and used in Tasks 3 and 4 — consistent
- [x] `self:lookup(word)` defined in Task 3 and called in Tasks 4 and 5 — consistent
