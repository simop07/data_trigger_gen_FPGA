#include "waveformAnalysisPos.hpp"

#include <algorithm>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <numeric>

WaveformAnalysisPos::WaveformAnalysisPos(std::vector<double> const &s,
                                         double ts, double sp)
    : fSamples{s}, fTimeStamp{ts}, fSamplePeriod{sp} {
  WaveformAnalysisPos::analyseWaveform();  // Analyse waveform when found
}

std::vector<double> const &WaveformAnalysisPos::getSamples() const {
  return fSamples;
}

double WaveformAnalysisPos::getTimeStamp() const { return fTimeStamp; }

double WaveformAnalysisPos::getSamplePeriod() const { return fSamplePeriod; }

double WaveformAnalysisPos::getBaseline() const { return fBaseline; }

double WaveformAnalysisPos::getThreshold() const { return fThreshold; }

std::vector<Pulse> const &WaveformAnalysisPos::getPulses() const {
  return fPulses;
}

void WaveformAnalysisPos::analyseWaveform() {
  WaveformAnalysisPos::findPulses();
}

void WaveformAnalysisPos::findPulses(double threshold, int minWidth,
                                     int maxWidth, int minSep) {
  // Threshold for peak detection
  fThreshold = fBaseline + threshold;

  // Used to find the lower value of the interval for pulseStart and pulseEnd
  double const lowLimit = 79.;

  // Used to find the higher value of the interval for pulseStart and pulseEnd
  double const upLimit = 160.;

  int pulseStart{};
  int pulseEnd{};

  // Min separation between pulseEnd of previous pulse and next pulse peak
  int prevPulseEnd = -minSep;

  for (int i{1}; i < static_cast<int>(fSamples.size()) - 2; ++i) {
    // Detection of pulse's maximum value
    if (fSamples[i] > fThreshold && fSamples[i] > fSamples[i - 1] &&
        fSamples[i] > fSamples[i + 1]) {
      bool foundStart{false};  // Have I found startPulse?
      bool foundEnd{false};    // Have I found endPulse?

      // Try to find startPulse near baseline before the peak
      for (int j{i - 1}; j >= std::max(0, i - minWidth); --j) {
        if (fSamples[j] > lowLimit && fSamples[j] < upLimit) {
          foundStart = true;
          pulseStart = j;
          break;
        }
      }

      // Try to find endPulse near baseline after the peak if Start is found
      if (foundStart) {
        for (int j{i + 1};
             j <= std::min(static_cast<int>(fSamples.size()) - 1, i + maxWidth);
             ++j) {
          if (fSamples[j] > lowLimit && fSamples[j] < upLimit) {
            foundEnd = true;
            pulseEnd = j;
            break;
          } else if (j == static_cast<int>(fSamples.size()) - 1) {
            foundEnd = true;
            pulseEnd = j;
          }
        }
      }

      // Build pulse and save it into a vector
      if (foundStart && foundEnd && pulseStart < pulseEnd &&
          pulseStart - prevPulseEnd > minSep) {
        fPulses.push_back(integratePulse(pulseStart, pulseEnd));
        prevPulseEnd = pulseEnd;
      }
    }
  }

  // Print waveform's properties
  std::cout << std::fixed << std::setprecision(2);  // Use 2 decimal digit
  std::cout << "\n\n*** PROPERTIES OF THE FOLLOWING WF ***\n";
  std::cout << "Threshold for pulse detection   = " << fThreshold << '\n';
  std::cout << "Lower limit for pulse endpoints = " << lowLimit << '\n';
  std::cout << "Upper limit for pulse endpoints = " << upLimit << '\n';
}

// Find area of 1 pulse
Pulse WaveformAnalysisPos::integratePulse(int pulseStart, int pulseEnd) {
  // Find pulse maximum
  auto itMax = std::max_element(fSamples.begin() + pulseStart,
                                std::next(fSamples.begin() + pulseEnd));

  // Find index corresponding to the maximum
  auto maxPulseIndex = std::distance(fSamples.begin(), itMax);

  // Define peak to peak value
  double peakToPeak{std::abs(*itMax - fBaseline)};

  // Compute rise time
  auto itRiseBegin = std::find_if(
      fSamples.begin() + pulseStart, std::next(fSamples.begin() + pulseEnd),
      [&](double sample) { return sample >= (0.1 * peakToPeak + fBaseline); });
  auto itRiseEnd = std::find_if(
      fSamples.begin() + pulseStart, std::next(fSamples.begin() + pulseEnd),
      [&](double sample) { return sample >= (0.9 * peakToPeak + fBaseline); });
  // Find indices corresponding to rise time
  auto itRiseBeginIndex = std::distance(fSamples.begin(), itRiseBegin);
  auto itRiseEndIndex = std::distance(fSamples.begin(), itRiseEnd);
  double riseTime =
      static_cast<double>(itRiseEndIndex - itRiseBeginIndex) * fSamplePeriod;
  if (riseTime < fSamplePeriod) {
    riseTime = fSamplePeriod;
  }

  // Compute FWHM
  auto itFWHMBegin = std::find_if(
      fSamples.begin() + pulseStart, std::next(itMax),
      [&](double sample) { return sample >= (0.5 * peakToPeak + fBaseline); });
  auto itFWHMEnd = std::find_if(
      itMax, std::next(fSamples.begin() + pulseEnd),
      [&](double sample) { return sample <= (0.5 * peakToPeak + fBaseline); });
  auto itFWHMBeginIndex = std::distance(fSamples.begin(), itFWHMBegin);
  auto itFWHMEndIndex = std::distance(fSamples.begin(), itFWHMEnd);
  double FWHMTime =
      static_cast<double>(itFWHMEndIndex - itFWHMBeginIndex) * fSamplePeriod;
  if (FWHMTime < fSamplePeriod) {
    FWHMTime = fSamplePeriod;
  }

  // Compute sum of samples within a pulse
  auto sumSamples = std::accumulate(fSamples.begin() + pulseStart,
                                    std::next(fSamples.begin() + pulseEnd), 0.);

  // Find all negative values contributing to area
  double negSumSamples{};
  int negCounter{};
  std::for_each(fSamples.begin() + pulseStart,
                std::next(fSamples.begin() + pulseEnd), [&](double negVal) {
                  if (negVal < fBaseline) {
                    negSumSamples += std::abs(negVal);
                    ++negCounter;
                  }
                });
  // Subtract baseline in order to compute effective negative area
  auto negPulseArea = std::abs(negSumSamples - (negCounter * fBaseline));

  // Compute sample average within a pulse
  auto avg = sumSamples / (pulseEnd - pulseStart + 1);

  // Subtract baseline in order to compute effective area
  auto pulseArea = sumSamples - (pulseEnd - pulseStart + 1) * fBaseline;

  // Find pulse which is closest to average
  std::vector<double> values{};
  std::vector<double> times{};
  int closestToAvgIndex = pulseStart;
  double minimalDifference = std::abs(fSamples[pulseStart] - avg);
  for (int i = pulseStart; i <= pulseEnd; ++i) {
    // Take advantage of the loop building values and times objects
    values.push_back(fSamples[i]);
    times.push_back(i * fSamplePeriod);

    double currentVal = fSamples[i];
    auto diff = std::abs(currentVal - avg);
    if (diff < minimalDifference) {
      closestToAvgIndex = i;
      minimalDifference = diff;
    }
  }

  // Compute fractional area time (time width at which 90% of pulse area is
  // found, starting at the average point of the pulse)
  double pulseAreaPartial{};
  int rightTimeIndex{closestToAvgIndex};
  int leftTimeIndex{closestToAvgIndex - 1};
  while (pulseAreaPartial <= 0.9 * std::abs(pulseArea)) {
    bool advanced{false};
    if (rightTimeIndex <= pulseEnd) {
      pulseAreaPartial += (fSamples[rightTimeIndex] - fBaseline);
      ++rightTimeIndex;
      advanced = true;
    }
    if (leftTimeIndex >= pulseStart) {
      pulseAreaPartial += (fSamples[leftTimeIndex] - fBaseline);
      --leftTimeIndex;
      advanced = true;
    }
    if (!advanced) break;
  }
  double fractionalAreaTime =
      (rightTimeIndex - leftTimeIndex - 1) * fSamplePeriod;

  pulseArea *= fSamplePeriod;
  negPulseArea *= fSamplePeriod;
  double negFracArea = (pulseArea != 0.) ? negPulseArea / pulseArea : 0.;

  return Pulse{fTimeStamp + pulseStart * fSamplePeriod,
               fTimeStamp + pulseEnd * fSamplePeriod,
               fTimeStamp + maxPulseIndex * fSamplePeriod,
               *itMax,
               riseTime,
               FWHMTime,
               fractionalAreaTime,
               std::abs(pulseArea),
               negFracArea,
               (static_cast<double>(negCounter) /
                static_cast<double>((pulseEnd - pulseStart + 1))),
               values,
               times};
}