import subprocess
import os
import platform

def is_running():
    """Check if Premiere Pro is running"""
    if platform.system() == 'Darwin': # macOS
        try:
            output = subprocess.check_output(['osascript', '-e', 'application "Adobe Premiere Pro" is running'])
            return output.decode('utf-8').strip().lower() == 'true'
        except Exception:
            return False
    # For Windows, you'd check tasklist
    return False

def execute(command, payload):
    """
    Execute a command in Premiere Pro via ExtendScript.
    On Mac, we can send ExtendScript via AppleScript.
    """
    print(f"[Premiere Bridge] Executing: {command} with {payload}")
    
    if not is_running():
        return False, "Premiere Pro is not running."
        
    extend_script = ""
    
    if command == "add_marker":
        name = payload.get("name", "AI Marker")
        comments = payload.get("comments", "")
        # Basic ExtendScript to add a marker to the active sequence
        extend_script = f"""
        var seq = app.project.activeSequence;
        if (seq) {{
            var newMarker = seq.markers.createMarker(seq.getPlayerPosition().seconds);
            newMarker.name = "{name}";
            newMarker.comments = "{comments}";
        }}
        """
    elif command == "export_timeline":
        preset = payload.get("preset", "YouTube 1080p")
        # Example script...
        extend_script = "alert('AI Export triggered!');"
    else:
        return False, f"Unknown Premiere command: {command}"
        
    if platform.system() == 'Darwin':
        # Wrap the ExtendScript in AppleScript and execute
        apple_script = f'''
        tell application "Adobe Premiere Pro"
            activate
            set myScript to "{extend_script.replace('"', '\\"').replace('\\n', ' ')}"
            DoScript myScript
        end tell
        '''
        try:
            subprocess.run(['osascript', '-e', apple_script], check=True)
            return True, "Command executed successfully in Premiere Pro."
        except subprocess.CalledProcessError as e:
            return False, f"AppleScript execution failed: {e}"
            
    return False, "Unsupported platform for automated Premiere control yet."
