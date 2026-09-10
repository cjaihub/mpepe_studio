#!/bin/bash
echo "Building MpepeConnect Desktop Agent for macOS..."

# Create necessary directories
mkdir -p build dist

# Ensure pyinstaller is installed
./.venv/bin/pip install pyinstaller

# Run pyinstaller to create a .app bundle
./.venv/bin/pyinstaller --noconfirm --windowed --name "MpepeConnect" \
    main.py

echo "Build complete! Check the dist/ directory for MpepeConnect.app"
