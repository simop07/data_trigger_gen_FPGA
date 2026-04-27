// To compile in SHELL:
// "g++ waveformAnalysisPos.cpp analysis.cpp `root-config --cflags --libs`"
// Best data to show fit is DataF_CH0@DT5730S_59483_run_new_1300_2-3.5 with Refl
// PMT conversion factor inside data/miscellaneous

#include <fstream>
#include <limits>
#include <sstream>

#include "TCanvas.h"
#include "TF1.h"
#include "TFile.h"
#include "TGraph.h"
#include "TH1.h"
#include "TH2.h"
#include "TLegend.h"
#include "TMath.h"
#include "TMultiGraph.h"
#include "TROOT.h"
#include "TStyle.h"
#include "waveformAnalysisPos.hpp"

// Define global constants
constexpr int nMinAnalysedRows{2};  // Minimum EXCLUDED (>= 2)
constexpr int nMaxAnalysedRows{200};  // Maximum INCLUDED

void setFitStyle() {
  gROOT->SetStyle("Plain");
  gStyle->SetOptStat(0);
  gStyle->SetOptFit(0);
  gStyle->SetPalette(57);
  gStyle->SetOptTitle(1);
  gStyle->SetStatY(0.9);
  gStyle->SetStatX(0.9);
  gStyle->SetStatW(0.2);
  gStyle->SetStatH(0.2);
  gStyle->SetTitleX(0.5);
  gStyle->SetTitleY(0.98);
  gStyle->SetTitleAlign(23);
  gStyle->SetTitleBorderSize(0);
  gStyle->SetTitleXOffset(0.8f);
  gStyle->SetTitleYOffset(.7f);
  gStyle->SetTitleXSize(0.05);
  gStyle->SetTitleYSize(0.05);
}

void waveformAnalysis() {
  // To avoid reloading manually if .so is present
  R__LOAD_LIBRARY(waveformAnalysisPos_cpp.so);

  // Input and output files
  std::string inFileName = "./../data/data.txt";
  std::string rootFileName = "./../data/wfAnalysis.root";

  // Area conversion factor (current assumption is 1 PE = 1 ADC*ns)
  auto const areaConvFactor = static_cast<double>(1);

  // Variables used later
  double const samplePeriod = 10.0;  // In [ns]
  std::ifstream inFile(inFileName.c_str());
  std::string line;
  std::vector<double> colours{1, 3, 4, 5, 6, 7, 8, 9};  // Colour vector
  TMultiGraph *mg = new TMultiGraph();
  TMultiGraph *mgSuperimposed = new TMultiGraph();
  std::vector<TGraph *> graphs{};
  std::vector<TGraph *> graphsSuperimposed{};
  std::map<int, double> map{};
  int row{0};

  // Select random generator seed for colours based on current time
  srand(time(NULL));

  // Creating TFile
  TFile *file1 = new TFile(rootFileName.c_str(), "RECREATE");

  // Defining loop variables for reading data
  std::vector<double> samples;
  double timestamp = 0.;

  // Loop over rows (waveforms)
  while (std::getline(inFile, line)) {
    // Control over analysed rows
    if (row < nMinAnalysedRows) {
      ++row;
      continue;
    }
    if (row >= nMaxAnalysedRows) {
      break;
    }

    // Read column
    std::stringstream ss(line);
    std::string item;
    int column{0};
    double adc_value{};
    double deltaT{};

    while (std::getline(ss, item, '\t')) {
      if (item.empty()) {
        ++column;
        continue;
      }

      if (column == 0) {
        adc_value = std::stod(item);  // ADC counts
      }

      if (column == 1) {
        deltaT = (std::stod(item) - 10);  // DeltaT in [ns]
      }
      ++column;
    }

    int nMissing = static_cast<int>(deltaT / 10);

    // Fill empty ADC with average of noise with dummy value
    for (int i = 0; i < nMissing; i++) {
      samples.push_back(110);
    }
    samples.push_back(adc_value);
    ++row;
  }

  // Creating WaveformAnalysis object
  WaveformAnalysisPos wf(samples, timestamp, samplePeriod);
  const auto &pulses1 = wf.getPulses();

  // Create pulseSum graph
  for (size_t i = 0; i < pulses1.size(); ++i) {
    const auto &p = pulses1[i];
    if (p.times.empty() || (p.endTime - p.startTime) <= 0.) continue;
    if (p.peakValue > 6000.) continue;

    double const t0 = p.times[0];
    for (int j = 0; j < static_cast<int>(p.times.size()); ++j) {
      int tRel = static_cast<int>(std::round(p.times[j] - t0));
      map[tRel] += p.values[j];
    }
  }

  // Create canvas for summing pulses
  TCanvas *cPulseSum = new TCanvas("cPulseSum", "Pulse sum", 1500, 700);
  std::vector<double> xValues{};
  std::vector<double> yValues{};
  xValues.reserve(map.size());
  yValues.reserve(map.size());
  for (auto const &[key, value] : map) {
    xValues.push_back(key);
    yValues.push_back(value);
  }

  // Create graph for summing pulses
  TGraph *gPulseSum = new TGraph(map.size(), xValues.data(), yValues.data());
  gPulseSum->SetTitle("; Time after transmission [ns]; ADC Counts");
  gPulseSum->SetLineColor(kBlue);
  gPulseSum->SetLineWidth(3);
  gPulseSum->SetMarkerStyle(20);
  gPulseSum->SetMarkerSize(1);
  gPulseSum->SetMarkerColor(kBlack);

  // gPulseSum relevant parameters
  // gPulseSum relevant parameters
  auto const maxId{TMath::LocMax(gPulseSum->GetN(), gPulseSum->GetY())};
  double const xPeak = gPulseSum->GetX()[maxId];
  double const yPeak = gPulseSum->GetY()[maxId];

  // Create Landau fit for summed pulses. Range covers the full pulse width
  // (600 ns after shift).
  TF1 *fLandau = new TF1("fLandau", "landau", 0., 700.);
  fLandau->SetLineColor(kRed);
  fLandau->SetLineWidth(4);
  fLandau->SetLineStyle(2);
  fLandau->SetParameter(0, yPeak);  // Amplitude
  fLandau->SetParameter(1, xPeak);  // MPV (Most Probable Value) peak position
  fLandau->SetParameter(2, 30.);    // Sigma controls width
  gPulseSum->Fit(fLandau, "R");

  // Save gPulseSum fit relevant parameters
  double const mpvSum{fLandau->GetParameter(1)};
  double const sigmaSum{fLandau->GetParameter(2)};

  // Count number of pulses
  int pulseCounter{0};

  // Get pulse vector from each single waveform
  const auto &pulses = wf.getPulses();
  std::cout << "\nNumber of Pulses without selection = " << pulses.size()
            << '\n';
  // Print pulse properties
  for (size_t i = 0; i < pulses.size(); ++i) {
    const auto &p = pulses[i];

    // Params of interest
    double heightOverWidth{p.peakValue / (p.endTime - p.startTime)};
    double peakFractionPos{(p.peakTime - p.startTime) /
                           (p.endTime - p.startTime)};
    double areaOverFullTime{p.area / ((p.endTime - p.startTime))};

    std::cout << "\n  *** Pulse n. " << i + 1 << " ***\n\n";
    std::cout << "  Overall start time           = " << p.startTime << " ns\n";
    std::cout << "  Overall end time             = " << p.endTime << " ns\n";
    std::cout << "  Overall peak time            = " << p.peakTime << " ns\n";
    std::cout << "  Relative start time          = "
              << p.startTime - wf.getTimeStamp() << " ns\n";
    std::cout << "  Relative end time            = "
              << p.endTime - wf.getTimeStamp() << " ns\n";
    std::cout << "  Relative peak time           = "
              << p.peakTime - wf.getTimeStamp() << " ns\n";
    std::cout << "  Peak time since startPulse   = "
              << p.peakTime - wf.getTimeStamp() - p.times[0] << " ns\n";
    std::cout << "  Peak value                   = " << p.peakValue << " ADC\n";
    std::cout << "  Width                        = " << p.endTime - p.startTime
              << " ns\n";
    std::cout << "  Rise time                    = " << p.riseTime << " ns\n";
    std::cout << "  FWHM                         = " << p.FWHMTime << " ns\n";
    std::cout << "  90% area time                = " << p.areaFractionTime
              << " ns\n";
    std::cout << "  Height over width            = " << heightOverWidth
              << " ADC/ns\n";
    std::cout << "  Peak fraction pos.           = " << peakFractionPos << '\n';
    std::cout << "  Area / full width            = " << areaOverFullTime
              << " ADC\n";
    std::cout << "  Area                         = " << p.area << " ADC*ns\n";
    std::cout << "  Area in PE                   = " << p.area / areaConvFactor
              << " PE\n";
    std::cout << "  Negative/overall area frac   = " << p.negFracArea << " \n";
    std::cout << "  Negative/overall counts      = " << p.negFrac << " \n";

    // Generate a random number between 0 and 7 (used for colour indices)
    int randIndex = rand() % 8;

    // Create vector to superimpose pulses
    std::vector<double> superimposedTimes = p.times;
    double shift{superimposedTimes[0]};
    for (int timeId{}; timeId < static_cast<int>(superimposedTimes.size());
         ++timeId) {
      superimposedTimes[timeId] -= shift;
    }

    ++pulseCounter;

    // Plot each pulse using a graph object
    TGraph *g = new TGraph(p.times.size(), p.times.data(), p.values.data());
    g->SetLineColor(colours[randIndex]);
    g->SetLineWidth(1);
    g->SetMarkerColor(kBlack);
    g->SetMarkerStyle(20);
    g->SetMarkerSize(1);
    g->SetTitle(Form("Pulse %d; Time after transmission [ns]; ADC counts",
                     pulseCounter));
    graphs.push_back(g);

    // Superimpose pulses from riseTime
    TGraph *gSuperimposed = new TGraph(
        superimposedTimes.size(), superimposedTimes.data(), p.values.data());
    gSuperimposed->SetLineColor(colours[randIndex]);
    gSuperimposed->SetLineWidth(1);
    gSuperimposed->SetMarkerColor(kBlack);
    gSuperimposed->SetMarkerStyle(20);
    gSuperimposed->SetMarkerSize(1);
    gSuperimposed->SetTitle(
        Form("Pulse %d; Time [ns]; ADC counts", pulseCounter));
    graphsSuperimposed.push_back(gSuperimposed);
  }

  setFitStyle();

  // Draw summed pulses
  cPulseSum->cd();
  gPad->Update();
  TLegend *legendPulse = new TLegend(0.65, 0.7, 0.88, 0.88);
  legendPulse->AddEntry(gPulseSum, "Pulse sum", "LP");
  legendPulse->AddEntry(fLandau, "Landau fit", "L");
  gPulseSum->Draw("ALP");
  fLandau->Draw("SAME");
  legendPulse->Draw("SAME");
  gPad->Update();

  // Print pulse sum fit info
  std::cout << "\n Print pulse sum fit info:\n";
  std::cout << "  Amplitude  = " << fLandau->GetParameter(0) << " +/- "
            << fLandau->GetParError(0) << '\n';
  std::cout << "  MPV        = " << mpvSum << " +/- " << fLandau->GetParError(1)
            << " ns\n";
  std::cout << "  Sigma      = " << sigmaSum << " +/- "
            << fLandau->GetParError(2) << " ns\n";
  std::cout << "  P-value    = " << fLandau->GetProb() << '\n';
  std::cout << "  Chi2/NDF   = " << fLandau->GetChisquare() / fLandau->GetNDF()
            << "\n\n";

  setFitStyle();

  // Create canvas to display all pulses of one file
  TCanvas *cPulses = new TCanvas("cPulses", "Pulses", 1500, 700);

  // Draw all pulses on multigraph object
  for (size_t i = 0; i < graphs.size(); ++i) {
    mg->Add(graphs[i]);
  }
  cPulses->cd();
  mg->Draw("ALP");
  mg->SetTitle("Pulses");
  mg->SetName("Regions of pulses");
  mg->GetXaxis()->SetTitle("Time after transmission [ns]");
  mg->GetYaxis()->SetTitle("ADC Counts");

  // Create canvas to superimpose all pulses of one file
  TCanvas *cPulsesSuperimp =
      new TCanvas("cPulsesSuperimp", "Superimposed pulses", 1500, 700);

  // Draw all pulses on multigraph object
  for (size_t i = 0; i < graphsSuperimposed.size(); ++i) {
    mgSuperimposed->Add(graphsSuperimposed[i]);
  }
  cPulsesSuperimp->cd();
  mgSuperimposed->Draw("ALP");
  mgSuperimposed->SetTitle("Superimposed pulses");
  mgSuperimposed->GetXaxis()->SetTitle("Time since startPulse [ns]");
  mgSuperimposed->GetYaxis()->SetTitle("ADC Counts");

  // Canvases
  cPulses->SaveAs("./../plots/pulses.pdf");
  cPulseSum->SaveAs("./../plots/cPulseSum.pdf");
  cPulsesSuperimp->SaveAs("./../plots/pulsesSuperimposed.pdf");

  // Write objects on file
  file1->cd();
  cPulseSum->Write();
  cPulseSum->Close();
  cPulses->Write();
  cPulses->Close();
  cPulsesSuperimp->Write();
  cPulsesSuperimp->Close();
  file1->Close();
}

void waveformTotal() {
  R__LOAD_LIBRARY(waveformAnalysisPos_cpp.so);

  TFile *file2 = new TFile("./../data/waveform.root", "RECREATE");
  TCanvas *c2 = new TCanvas("c2", "Waveform reconstruction", 1500, 700);

  std::ifstream infile("./../data/data.txt");
  std::string line;

  const double samplePeriod = 10.0;

  std::vector<double> samples;
  std::vector<double> times;

  int row = 0;
  double currentTime = 0.0;

  while (std::getline(infile, line)) {
    if (row < nMinAnalysedRows) {
      ++row;
      continue;
    }
    if (row >= nMaxAnalysedRows) {
      break;
    }

    std::stringstream ss(line);
    std::string item;

    double adc_value = 0.0;
    double deltaT = 0.0;

    int column = 0;
    while (std::getline(ss, item, '\t')) {
      if (item.empty()) {
        ++column;
        continue;
      }
      if (column == 0) {
        adc_value = std::stod(item);
      }
      if (column == 1) {
        deltaT = (std::stod(item) - 10);
      }
      ++column;
    }

    currentTime += deltaT;

    samples.push_back(adc_value);
    times.push_back(currentTime);

    ++row;
  }

  setFitStyle();

  TGraph *totG = new TGraph(samples.size(), times.data(), samples.data());

  totG->SetTitle("Reconstructed waveform; Time [ns]; ADC Counts");
  totG->SetLineColor(kBlue);
  totG->SetMarkerColor(kBlack);
  totG->SetLineWidth(3);
  totG->SetMarkerStyle(20);
  totG->SetMarkerSize(1);

  c2->cd();

  totG->Draw("ALP");

  file2->cd();
  c2->Write();
  c2->SaveAs("./../plots/full_waveform.pdf");
  file2->Close();
}

int main() {
  waveformAnalysis();
  waveformTotal();

  return EXIT_SUCCESS;
}