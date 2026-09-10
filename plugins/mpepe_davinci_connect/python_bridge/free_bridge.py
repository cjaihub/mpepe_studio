import logging
import sys
import os

logger = logging.getLogger("cj_grader.free_bridge")

def is_running_inside_resolve() -> bool:
    """Detects if we are running from Workspace -> Scripts inside Resolve."""
    executable = sys.executable or ""
    return executable.rstrip("/").endswith("/Resolve") or "fuscript" in executable.lower()

def launch_bridge_server(port: int = 50051):
    """
    Launches the gRPC server. If running inside Resolve (Free Edition), 
    it will have access to the DaVinciResolveScript API internally.
    """
    logger.info("Starting CJ Grader In-App Bridge Server...")
    
    # We will import the gRPC server here (to be implemented)
    try:
        from .grpc_server import serve_grpc
        serve_grpc(port=port)
    except ImportError:
        logger.warning("gRPC server not yet implemented. Bridge is idle.")
        
if __name__ == "__main__":
    # Configure basic logging for when launched directly
    logging.basicConfig(level=logging.INFO)
    
    if is_running_inside_resolve():
        logger.info("Detected in-app environment (Free Edition compatible).")
    else:
        logger.info("Detected external environment (Studio Edition required).")
        
    launch_bridge_server()
