//
//  ContentView.swift
//  Deafield
//
//  Created by Davide Perrotta on 16/12/23.
//

import SwiftUI
import AVFoundation
import Accelerate
import CoreHaptics

class AudioRecorderManager: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var numberOfRecords = 0
    @Published var recordings: [URL] = []
    @Published var showAlert = false
    @Published var showStopAlert = false
    @Published var audioRecorder: AVAudioRecorder?
    @Published var buttonColor: Color = .blue
    @Published var dominantFrequencies: [Double] = []

    private var coordinator: Coordinator?
    private var frequencyAnalysisTimer: Timer?

    override init() {
        super.init()
        loadPreviousRecords()
        requestRecordPermission()

        // Inizializza il timer per il campionamento periodico
        frequencyAnalysisTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Esegui l'analisi della frequenza sul file audio corrente
            if let lastRecordingURL = self?.recordings.last {
                self?.findDominantFrequencyInAudioFile(at: lastRecordingURL, sampleRate: 44100.0)
            }
        }
    }

    deinit {
        // Ferma il timer quando l'istanza viene deallocata
        frequencyAnalysisTimer?.invalidate()
    }
    
    
    private func findAverageFrequencyInSineWave(_ signal: [Double], sampleRate: Double, duration: Double) -> Double? {
        guard !signal.isEmpty else {
            return nil // Non ci sono dati nel segnale
        }

        // Calcola il numero totale di campioni nel periodo di tempo desiderato
        let numberOfSamplesInDuration = Int(duration * sampleRate)

        // Assicurati che il numero di campioni sia inferiore o uguale alla lunghezza del segnale
        let numberOfSamplesToUse = min(numberOfSamplesInDuration, signal.count)

        // Seleziona i primi numberOfSamplesToUse campioni
        let selectedSamples = Array(signal.prefix(numberOfSamplesToUse))

        // Calcola la media delle frequenze nel periodo di tempo desiderato
        let sumOfFrequencies = selectedSamples.reduce(0, +) //Somma di tutte le frequenze
        let averageFrequency = sumOfFrequencies / Double(selectedSamples.count)

        return averageFrequency
    }

    
    // Function to find dominant frequency in an audio file
    func findDominantFrequencyInAudioFile(at url: URL, sampleRate: Double) {
        do {
            // Load audio file
            let audioFile = try AVAudioFile(forReading: url)
            let audioFormat = audioFile.processingFormat
            let audioFrameCount = UInt32(audioFile.length)
            let audioBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: audioFrameCount)!

            try audioFile.read(into: audioBuffer)

            // Convert audio buffer to an array of Double
            let samples = Array(UnsafeBufferPointer(start: audioBuffer.floatChannelData?[0], count: Int(audioBuffer.frameLength)))
                .map { Double($0) }

            // Perform frequency analysis
            if let averageFrequency = findAverageFrequencyInSineWave(samples, sampleRate: sampleRate, duration: 2.0) {
                // Calculate nextAverageFrequency by analyzing the next second
                let nextAverageFrequency = findAverageFrequencyInSineWave(samples, sampleRate: sampleRate, duration: 4.0)  // Analyze the next second

                // Compare averageFrequency at second 2 with nextAverageFrequency at the next second
                if let nextAverageFrequency = nextAverageFrequency {
                    let feedbackIntensity: Float
                    let feedbackSharpness: Float

                    if averageFrequency < nextAverageFrequency {
                        // Increase the intensity and sharpness of the feedback
                        feedbackIntensity = 1.0
                        feedbackSharpness = 1.0
                    } else {
                        // Decrease the intensity and sharpness of the feedback
                        feedbackIntensity = 0.5
                        feedbackSharpness = 0.5
                    }

                    // Provide haptic feedback
                    provideHapticFeedback(intensity: feedbackIntensity, sharpness: feedbackSharpness)

                    // Update the published property
                    self.dominantFrequencies = [averageFrequency]
                }
            }
        } catch {
            print("Error loading audio file: \(error.localizedDescription)")
        }
    }

    
    // Funzione di esempio per fornire il feedback aptico
    // Funzione che fornisce un feedback aptico personalizzato utilizzando Core Haptics
    func provideHapticFeedback(intensity: Float, sharpness: Float) {
        // 1. UINotificationFeedbackGenerator per il feedback aptico predefinito
        let hapticGenerator = UINotificationFeedbackGenerator()
        hapticGenerator.notificationOccurred(.success)
        
        // 2. CHHapticEngine per il feedback aptico personalizzato
        let hapticEngine = try? CHHapticEngine()
        try? hapticEngine?.start()

        // 3. Creazione di un evento haptico con intensità e nitidezza specificate
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )

        // 4. Creazione di un modello haptico contenente l'evento haptico
        let pattern = try? CHHapticPattern(events: [event], parameters: [])

        // 5. Creazione di un giocatore haptico utilizzando il motore e il modello haptico
        let player = try? hapticEngine?.makePlayer(with: pattern!)

        // 6. Avvio del giocatore per riprodurre il feedback aptico
        try? player?.start(atTime: 0)
    }


    // Function to delete a recording
    func deleteRecording(at offsets: IndexSet) {
        numberOfRecords -= offsets.count
        for index in offsets {
            let recordingURL = recordings[index]
            do {
                try FileManager.default.removeItem(at: recordingURL)
                recordings.remove(at: index)
            } catch {
                print("Error deleting recording: \(error.localizedDescription)")
            }
        }
        UserDefaults.standard.set(numberOfRecords, forKey: "myNumber")
    }

    // Function to toggle recording
    func toggleRecording() {
        if isRecording {
            showStopAlert = true
        } else {
            // Assign a default name when starting to record
            startRecording()
            buttonColor = .red
        }
    }

    // Function to start recording
    func startRecording() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, options: .defaultToSpeaker)

            // Increment the record number and set the file name
            numberOfRecords += 1
            let filename = getDirectory().appendingPathComponent("\(numberOfRecords).m4a")

            // Settings for audio recording
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            // Create an instance of Coordinator and assign it as the delegate
            coordinator = Coordinator()
            audioRecorder = try AVAudioRecorder(url: filename, settings: settings)
            audioRecorder?.delegate = coordinator
            audioRecorder?.record()
            isRecording = true
        } catch {
            // Handle recording error
            displayAlert(title: "Ups!", message: "Recording failed")
        }
    }


    // Function to stop recording
    func stopRecording() {
        guard isRecording else {
            return
        }

        // Set recording state and button color
        isRecording = false
        buttonColor = .blue

        // Stop AVAudioRecorder and deallocate resources
        audioRecorder?.stop()
        audioRecorder?.delegate = nil
        audioRecorder = nil

        // Save the record number and load previous records
        UserDefaults.standard.set(numberOfRecords, forKey: "myNumber")
        loadPreviousRecords()
    }

    // Function to load previous records
    func loadPreviousRecords() {
        if let number = UserDefaults.standard.object(forKey: "myNumber") as? Int {
            numberOfRecords = number
            recordings = (1...number).map {
                getDirectory().appendingPathComponent("\($0).m4a")
            }
        }
    }

    // Function to request recording permission
    func requestRecordPermission() {
        AVAudioApplication.requestRecordPermission() { hasPermission in
            if !hasPermission {
                self.showAlert = true
            }
        }
    }

    // Function to get the document directory path
    func getDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // Function to open app settings
    func openSettings() {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:], completionHandler: nil)
    }

    // Function to display an alert
    func displayAlert(title: String, message: String) {
        showAlert = true
    }
}

// ContentView preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

// Coordinator class to handle AVAudioRecorderDelegate events
class Coordinator: NSObject, AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // Handle recording finished
        if !flag {
            // Implement any additional logic for unsuccessful recording
        }
    }
}
struct ContentView: View {
    @StateObject private var audioRecorderManager = AudioRecorderManager()

    var body: some View {
        NavigationView {
            VStack {
                List {
                    ForEach(0..<audioRecorderManager.numberOfRecords, id: \.self) { index in
                        if !audioRecorderManager.recordings.isEmpty, audioRecorderManager.recordings.indices.contains(index) {
                            let recordingURL = audioRecorderManager.recordings[index]

                            NavigationLink(
                                destination: RecordingDetailView(recordURL: recordingURL, index: index, audioRecorderManager: audioRecorderManager, newName: ""),
                                label: {
                                    Text("Recording \(index + 1)")
                                }
                            )
                        }
                    }
                    .onDelete { indices in
                        indices.forEach { index in
                            audioRecorderManager.deleteRecording(at: IndexSet(integer: index))
                        }
                    }
                }
                .padding(10)

                Button(action: {
                    audioRecorderManager.toggleRecording()
                }) {
                    Text(audioRecorderManager.isRecording ? "Stop Recording" : "Start Recording")
                        .padding()
                        .background(audioRecorderManager.buttonColor)
                        .foregroundColor(.white)
                        .cornerRadius(40)
                }

                // Display dominant frequencies
                Text("Dominant Frequencies: \(audioRecorderManager.dominantFrequencies.map { String($0) }.joined(separator: ", "))")
                    .padding()
            }
            .padding(10)
            .navigationBarTitle("Voice Memos")
            .alert(isPresented: $audioRecorderManager.showAlert) {
                Alert(
                    title: Text("Microphone Access"),
                    message: Text("This app requires access to your microphone to record audio. Enable access in Settings."),
                    primaryButton: .default(Text("Settings")) {
                        audioRecorderManager.openSettings()
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert(isPresented: $audioRecorderManager.showStopAlert) {
                Alert(
                    title: Text("Stop Recording"),
                    message: Text("Do you want to stop the recording?"),
                    primaryButton: .default(Text("Yes")) {
                        audioRecorderManager.stopRecording()
                    },
                    secondaryButton: .cancel()
                )
            }
            .onAppear {
                audioRecorderManager.loadPreviousRecords()
                audioRecorderManager.requestRecordPermission()
            }
        }
    }
}

// RecordingDetailView to accept the new name and rename handler
struct RecordingDetailView: View {
    var recordURL: URL
    var index: Int
    @ObservedObject var audioRecorderManager: AudioRecorderManager
    @State private var newName: String // Temporary variable for editing

    @State private var isEditing = false
    
    public init(recordURL: URL, index: Int, audioRecorderManager: AudioRecorderManager, newName: String) {
            self.recordURL = recordURL
            self.index = index
            self.audioRecorderManager = audioRecorderManager
            self._newName = State(initialValue: newName)
        }

    var body: some View {
        VStack {
            if isEditing {
                TextField("Enter a new name", text: $newName, onCommit: {
                    guard !newName.isEmpty else { return }
                    audioRecorderManager.recordings[index] = recordURL.deletingLastPathComponent().appendingPathComponent(newName)
                    audioRecorderManager.loadPreviousRecords()  // Update the record list
                    isEditing = false
                })
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
            } else {
                Text("Recording Detail: \(audioRecorderManager.recordings[index].lastPathComponent)")
                    .navigationBarTitle("Recording Detail")
            }

            // Button to analyze frequency for the current recording
            Button(action: {
                audioRecorderManager.findDominantFrequencyInAudioFile(at: recordURL, sampleRate: 44100.0)
            }) {
                Text("Analyze Frequency")
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(40)
            }
        }
        .padding()
    }
}

