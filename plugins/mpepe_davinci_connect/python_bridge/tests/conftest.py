"""
conftest.py — adds the server directory to sys.path so all bridge tests
can do `from bridge.xxx import yyy` and `from orchestrator.xxx import yyy`.
"""
import sys
import os

# server/ directory (parent of bridge/ and orchestrator/)
_SERVER_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "..")
sys.path.insert(0, os.path.abspath(_SERVER_DIR))

# Also add server/bridge/ so bare imports like `import ledger_pb2` work
_BRIDGE_DIR = os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, os.path.abspath(_BRIDGE_DIR))
