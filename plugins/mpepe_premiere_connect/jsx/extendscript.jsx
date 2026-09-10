// This script runs in the ExtendScript engine inside Premiere Pro

function executeCommand(command, payloadString) {
    var payload = {};
    try {
        // Basic JSON parse (ExtendScript doesn't have native JSON, so we use eval)
        payload = eval('(' + payloadString + ')');
    } catch (e) {
        return "Error parsing payload: " + e.toString();
    }
    
    if (command === "add_marker") {
        return addMarkerToTimeline(payload);
    } else if (command === "export_timeline") {
        return exportTimeline(payload);
    } else if (command === "create_sequence") {
        return createSequence(payload);
    } else {
        return "Unknown command: " + command;
    }
}

function addMarkerToTimeline(payload) {
    var name = payload.name || "AI Marker";
    var comments = payload.comments || "Added by CJ AI";
    
    var seq = app.project.activeSequence;
    if (!seq) {
        return "No active sequence found.";
    }
    
    var time = seq.getPlayerPosition();
    var marker = seq.markers.createMarker(time.seconds);
    marker.name = name;
    marker.comments = comments;
    
    return "Marker added successfully.";
}

function exportTimeline(payload) {
    var seq = app.project.activeSequence;
    if (!seq) {
        return "No active sequence found to export.";
    }
    // Note: True automated export requires an EPR preset path. 
    // This is a placeholder for the logic.
    return "Export sequence logic triggered for " + seq.name;
}

function createSequence(payload) {
    var name = payload.name || "New AI Sequence";
    app.project.createNewSequence(name, "");
    return "Sequence '" + name + "' created.";
}
