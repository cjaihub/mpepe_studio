import os
import sys

def get_resolve_api_paths():
    """Returns a tuple of (RESOLVE_SCRIPT_API, RESOLVE_SCRIPT_LIB) paths based on OS."""
    if sys.platform == "darwin":
        api = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting"
        lib = "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so"
    elif sys.platform.startswith("win"):
        api = os.path.expandvars(r"%PROGRAMDATA%\Blackmagic Design\DaVinci Resolve\Support\Developer\Scripting")
        lib = r"C:\Program Files\Blackmagic Design\DaVinci Resolve\fusionscript.dll"
    else:  # linux
        api = "/opt/resolve/Developer/Scripting"
        lib = "/opt/resolve/libs/Fusion/fusionscript.so"
    return api, lib

def setup_resolve_env():
    """Sets up PYTHONPATH and environment variables for DaVinciResolveScript."""
    api, lib = get_resolve_api_paths()
    
    os.environ['RESOLVE_SCRIPT_API'] = api
    os.environ['RESOLVE_SCRIPT_LIB'] = lib
    
    modules_path = os.path.join(api, "Modules")
    if modules_path not in sys.path:
        sys.path.append(modules_path)
    
    return True
