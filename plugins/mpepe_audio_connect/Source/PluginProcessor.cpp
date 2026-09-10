#include "PluginProcessor.h"
#include "PluginEditor.h"

MpepeAudioConnectProcessor::MpepeAudioConnectProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
     : AudioProcessor (BusesProperties()
                     #if ! JucePlugin_IsMidiEffect
                      #if ! JucePlugin_IsSynth
                       .withInput  ("Input",  juce::AudioChannelSet::stereo(), true)
                      #endif
                       .withOutput ("Output", juce::AudioChannelSet::stereo(), true)
                     #endif
                       )
#endif
{
    sessionId = juce::Uuid().toString();
}

MpepeAudioConnectProcessor::~MpepeAudioConnectProcessor() {}

const juce::String MpepeAudioConnectProcessor::getName() const { return JucePlugin_Name; }
bool MpepeAudioConnectProcessor::acceptsMidi() const { return true; }
bool MpepeAudioConnectProcessor::producesMidi() const { return true; }
bool MpepeAudioConnectProcessor::isMidiEffect() const { return false; }
double MpepeAudioConnectProcessor::getTailLengthSeconds() const { return 0.0; }

int MpepeAudioConnectProcessor::getNumPrograms() { return 1; }
int MpepeAudioConnectProcessor::getCurrentProgram() { return 0; }
void MpepeAudioConnectProcessor::setCurrentProgram (int index) {}
const juce::String MpepeAudioConnectProcessor::getProgramName (int index) { return {}; }
void MpepeAudioConnectProcessor::changeProgramName (int index, const juce::String& newName) {}

void MpepeAudioConnectProcessor::prepareToPlay (double sampleRate, int samplesPerBlock) {}
void MpepeAudioConnectProcessor::releaseResources() {}
bool MpepeAudioConnectProcessor::isBusesLayoutSupported (const BusesLayout& layouts) const { return true; }

void MpepeAudioConnectProcessor::processBlock (juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages)
{
    juce::ScopedNoDenormals noDenormals;
    auto totalNumInputChannels  = getTotalNumInputChannels();
    auto totalNumOutputChannels = getTotalNumOutputChannels();

    for (auto i = totalNumInputChannels; i < totalNumOutputChannels; ++i)
        buffer.clear (i, 0, buffer.getNumSamples());

    // In a real implementation, we would poll Firebase commands via a separate thread 
    // and apply DSP or send MIDI here based on the remote AI command.
}

juce::AudioProcessorEditor* MpepeAudioConnectProcessor::createEditor() { return new MpepeAudioConnectEditor (*this); }
bool MpepeAudioConnectProcessor::hasEditor() const { return true; }
void MpepeAudioConnectProcessor::getStateInformation (juce::MemoryBlock& destData) {}
void MpepeAudioConnectProcessor::setStateInformation (const void* data, int sizeInBytes) {}

// This creates new instances of the plugin..
juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter() { return new MpepeAudioConnectProcessor(); }
