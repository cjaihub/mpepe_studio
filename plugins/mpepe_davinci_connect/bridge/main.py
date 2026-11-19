"""
CJ Grader Python Bridge — Entry Point

Usage:
  python -m bridge.main                # from plugins/mpepe_davinci_connect (Resolve Studio)
  # Or drop into Resolve > Workspace > Scripts for Free Edition mode
"""

import logging
import sys
import os

# ── Logging Setup ─────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger("cj_grader.bridge")

# ── Resolve Environment ────────────────────────────────────────────────────────
from .resolve_env import setup_resolve_env
setup_resolve_env()

# ── Launch ────────────────────────────────────────────────────────────────────
from .free_bridge import is_running_inside_resolve
from .grpc_server import serve_grpc

GRPC_PORT = int(os.environ.get("CJ_GRADER_PORT", "50051"))

if __name__ == "__main__":
    mode = "in-app (Free Edition)" if is_running_inside_resolve() else "external (Studio)"
    logger.info(f"CJ Grader Bridge starting in {mode} mode on port {GRPC_PORT}…")
    serve_grpc(port=GRPC_PORT)
