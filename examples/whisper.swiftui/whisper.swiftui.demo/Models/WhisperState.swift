import Foundation
import SwiftUI
import AVFoundation

@MainActor
class WhisperState: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isModelLoaded = false
    @Published var messageLog = ""
    @Published var canTranscribe = false
    @Published var isRecording = false
    @Published var langCode = "de"
    
    private var whisperContext: WhisperContext?
    private let recorder = Recorder()
    private var recordedFile: URL? = nil
    private var audioPlayer: AVAudioPlayer?
    private var voice: AVSpeechSynthesisVoice?
    
    var synth = AVSpeechSynthesizer()
    
    
    private var modelUrl: URL? {
        Bundle.main.url(forResource: "ggml-base", withExtension: "bin", subdirectory: "models")
    }
    
    private var sampleUrl: URL? {
        Bundle.main.url(forResource: "jfk", withExtension: "wav", subdirectory: "samples")
    }
    
    private enum LoadError: Error {
        case couldNotLocateModel
    }
    
    override init() {
        super.init()
        do {
            try loadModel()
            try loadVoice()
            canTranscribe = true
        } catch {
            print(error.localizedDescription)
            messageLog += "\(error.localizedDescription)\n"
        }
    }
    
    private func loadModel() throws {
        messageLog += "Loading model...\n"
        if let modelUrl {
            whisperContext = try WhisperContext.createContext(path: modelUrl.path())
            messageLog += "Loaded model \(modelUrl.lastPathComponent)\n"
        } else {
            messageLog += "Could not locate model\n"
        }
    }
    
    private func loadVoice() throws {
        voice = AVSpeechSynthesisVoice(language: "en-GB-u-sd-gbsct")
        let voices = AVSpeechSynthesisVoice.speechVoices()
        for x_voice in voices {
            if (x_voice.name == "Fiona (Enhanced)") {
                messageLog += "LANG  " + x_voice.language
                messageLog += "\n"
                voice = x_voice
            }
        }
    }
    
    func getLanguages() async -> [String]? {
        return await whisperContext?.getLanguages()
    }
    
/*    func transcribeSample() async {
        if let sampleUrl {
            await transcribeAudio(sampleUrl)
        } else {
            messageLog += "Could not locate sample\n"
        }
    }*/
    
    private func transcribeAudio(_ url: URL) async {
        if (!canTranscribe) {
            return
        }
        guard let whisperContext else {
            return
        }
        
        do {
            canTranscribe = false
            messageLog += "Reading wave samples...\n"
            let data = try readAudioSamples(url)
            messageLog += "Transcribing data...\n"
            //messageLog += langCode
            let beginning = NSDate().timeIntervalSince1970
            await whisperContext.fullTranscribe(langCode: langCode, samples: data)
            let end = NSDate().timeIntervalSince1970
            let duration = end - beginning
            messageLog += "Duration: \(duration) s\n"
            let text = await whisperContext.getTranscription()
            /*do {
                let audioSession = AVAudioSession.sharedInstance()
                //try audioSession.setCategory(AVAudioSession.Category.ambient)
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                print("OK deactivate")
            } catch {
                print(error)
            }*/

            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice!
            utterance.rate = 0.3
            //utterance.volume = 1.0
            synth.speak(utterance)

            messageLog += "Done: \(text)\n"
        } catch {
            print(error.localizedDescription)
            messageLog += "\(error.localizedDescription)\n"
        }
        
        canTranscribe = true
    }
    
    private func readAudioSamples(_ url: URL) throws -> [Float] {
        stopPlayback()
        try startPlayback(url)
        return try decodeWaveFile(url)
    }
    
    func toggleRecord() async {
        if isRecording {
            await recorder.stopRecording()
            isRecording = false
            if let recordedFile {
                await transcribeAudio(recordedFile)
            }
        } else {
            requestRecordPermission { granted in
                if granted {
                    Task {
                        do {
                            self.stopPlayback()
                            let file = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                                .appending(path: "output.wav")
                            try await self.recorder.startRecording(toOutputFile: file, delegate: self)
                            self.isRecording = true
                            self.recordedFile = file
                        } catch {
                            print(error.localizedDescription)
                            self.messageLog += "\(error.localizedDescription)\n"
                            self.isRecording = false
                        }
                    }
                }
            }
        }
    }
    
    private func requestRecordPermission(response: @escaping (Bool) -> Void) {
#if os(macOS)
        response(true)
#else
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            response(granted)
        }
#endif
    }
    
    private func startPlayback(_ url: URL) throws {
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.play()
    }
    
    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    // MARK: AVAudioRecorderDelegate
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error {
            Task {
                await handleRecError(error)
            }
        }
    }
    
    private func handleRecError(_ error: Error) {
        print(error.localizedDescription)
        messageLog += "\(error.localizedDescription)\n"
        isRecording = false
    }
    
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task {
            await onDidFinishRecording()
        }
    }
    
    private func onDidFinishRecording() {
        isRecording = false
    }
}
