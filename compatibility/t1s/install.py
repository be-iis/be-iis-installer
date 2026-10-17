#!/usr/bin/env python3
"""Compatibility-only unified T1S module staging entry point."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).resolve().parents[2] / "scripts/t1s_stack_install.py"), run_name="__main__")
