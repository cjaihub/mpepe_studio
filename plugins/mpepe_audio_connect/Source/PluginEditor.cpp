#include "PluginProcessor.h"
#include "PluginEditor.h"

MpepeAudioConnectEditor::MpepeAudioConnectEditor (MpepeAudioConnectProcessor& p)
    : AudioProcessorEditor (&p), audioProcessor (p)
{
    setSize (400, 400);
}

MpepeAudioConnectEditor::~MpepeAudioConnectEditor() {}

void MpepeAudioConnectEditor::paint (juce::Graphics& g)
{
    g.fillAll (juce::Colour (0xff232323)); // Dark theme

    g.setColour (juce::Colours::white);
    g.setFont (15.0f);
    
    juce::String msg = "MPEPE Studio Connect\n\nSession ID: " + audioProcessor.sessionId;
    msg << "\n\nStatus: CONNECTED TO MOBILE!";
    msg << "\n\nWaiting for 'Render & Send' command from phone...";
    
    g.setColour (juce::Colours::greenyellow);
    g.drawFittedText (msg, getLocalBounds().reduced (20), juce::Justification::centred, 5);
}

void MpepeAudioConnectEditor::resized()
{
    // Layout QR code placeholder
}
