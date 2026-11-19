"""
conftest.py — puts the plugin root (parent of bridge/ and orchestrator/) on sys.path
so tests can `import bridge.xxx` / `import orchestrator.xxx`, plus bridge/ itself for
the generated `*_pb2` modules.
"""
import os
import sys

_PLUGIN_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_BRIDGE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
for _p in (_PLUGIN_ROOT, _BRIDGE_DIR):
    if _p not in sys.path:
        sys.path.insert(0, _p)
