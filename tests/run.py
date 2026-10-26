"""Optional Lua 5.1 runner; install lupa in your development environment."""
from pathlib import Path
import os
import sys
from lupa.lua51 import LuaRuntime
os.chdir(Path(__file__).resolve().parents[1])
LuaRuntime().execute(Path(sys.argv[1] if len(sys.argv)>1 else 'tests/run.lua').read_text())
