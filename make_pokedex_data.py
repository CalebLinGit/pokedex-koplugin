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
        entry_str = f"{{ {lua_entry} }}"

        # Index by lowercase Chinese and lowercase English name
        for key in [zh.lower(), en.lower()]:
            if key:
                lua_lines.append(f'  ["{escape_lua(key)}"] = {entry_str},')

        # Resize and copy image
        src = REPO / "images" / "pokedex" / "hires" / f"{pid:03d}.png"
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
