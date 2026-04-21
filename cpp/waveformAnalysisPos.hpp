#ifndef WAVEFORMANALYSISPOS_HPP
#define WAVEFORMANALYSISPOS_HPP

#include <string>
#include <vector>

// Pulse struct allows to define the properties of pulses in a waveform
struct Pulse {
  double startTime{};            // Overall start time of the pulse
  double endTime{};              // Overall end time of the pulse
  double peakTime{};             // Overall time at which peak takes place
  double peakValue{};            // Value of the pulse's peak in ADC
  double riseTime{};             // Time it takes to go from 10% to 90%
  double FWHMTime{};             // Time correspondent with the FWHM of the peak
  double areaFractionTime{};     // Fractional area time
  double area{};                 // Area of pulse
  double negFracArea{};          // Negative / overall area fraction
  double negFrac{};              // Negative / overall samples
  std::vector<double> values{};  // Values defining the pulse
  std::vector<double> times{};   // Times defining the pulse
};

// Waveform class allows to perform waveform analysis
class WaveformAnalysisPos {
 public:
  WaveformAnalysisPos(std::vector<double> const &s = {}, double ts = {},
                      double sp = {});

  // Getters for waveform member data

  std::vector<double> const &getSamples() const;
  double getTimeStamp() const;
  double getSamplePeriod() const;
  double getBaseline() const;
  double getThreshold() const;
  std::vector<Pulse> const &getPulses() const;

  // Analyse a waveform by extracting its noise and its pulses
  void analyseWaveform();

  // Detect pulses
  void findPulses(double threshold = 40., int minWidth = 10, int maxWidth = 70,
                  int minSep = 1);

  // Find area of 1 pulse
  Pulse integratePulse(int pulseStart, int pulseEnd);

 private:
  std::vector<double> fSamples{};  // Vector of samples generating the waveform
  double fTimeStamp{};             // Overall timestamp of the waveform
  double fSamplePeriod{};          // Sampling period
  double const fBaseline{111.5};   // Baseline of the waveform
  double fThreshold{};             // Threshold for pulse detection
  std::vector<Pulse> fPulses{};    // Vector of pulses composing the waveform
};

#endif