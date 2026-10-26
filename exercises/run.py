"""Convenience runner: Python with lupa installed (uses its Lua 5.1 runtime)."""
from pathlib import Path
import os
from lupa.lua51 import LuaRuntime

os.chdir(Path(__file__).resolve().parents[1])
LuaRuntime().execute(Path("exercises/run.lua").read_text())
