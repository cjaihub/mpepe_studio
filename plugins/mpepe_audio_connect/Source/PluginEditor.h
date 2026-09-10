#pragma once
#include <JuceHeader.h>
#include "PluginProcessor.h"

class MpepeAudioConnectEditor : public juce::AudioProcessorEditor
{
public:
    MpepeAudioConnectEditor (MpepeAudioConnectProcessor&);
    ~MpepeAudioConnectEditor() override;

    void paint (juce::Graphics&) override;
    void resized() override;

private:
    MpepeAudioConnectProcessor& audioProcessor;
    juce::Image qrCodeImage; // Placeholder for actual QR code rendering
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (MpepeAudioConnectEditor)
};
