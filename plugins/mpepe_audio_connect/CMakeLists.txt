cmake_minimum_required(VERSION 3.15)
project(MpepeAudioConnect VERSION 1.0.0)

# Add JUCE (Assumes JUCE is available globally or installed via FetchContent)
# For this prototype, we'll assume the user points JUCE_DIR to their JUCE install
find_package(JUCE CONFIG REQUIRED)

juce_add_plugin(MpepeAudioConnect
    IS_SYNTH FALSE
    NEEDS_MIDI_INPUT TRUE
    NEEDS_MIDI_OUTPUT TRUE
    IS_MIDI_EFFECT FALSE
    EDITOR_WANTS_KEYBOARD_FOCUS TRUE
    COPY_PLUGIN_AFTER_BUILD TRUE
    PLUGIN_MANUFACTURER_CODE Mpep
    PLUGIN_CODE Mpe1
    FORMATS VST3 AU Standalone
    PRODUCT_NAME "MPEPE Studio Connect")

target_sources(MpepeAudioConnect PRIVATE
    Source/PluginProcessor.cpp
    Source/PluginEditor.cpp)

target_compile_definitions(MpepeAudioConnect PUBLIC
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=1)

target_link_libraries(MpepeAudioConnect PRIVATE
    juce::juce_audio_utils
    juce::juce_core
    juce::juce_events
    juce::juce_graphics
    juce::juce_gui_basics
    juce::juce_gui_extra
    juce::juce_audio_processors
    RECOMMENDED)
