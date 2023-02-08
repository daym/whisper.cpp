import SwiftUI
import AVFoundation

struct PressActions: ViewModifier {
    var onPress: () -> Void
    var onRelease: () -> Void
    
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged({ _ in
                        onPress()
                    })
                    .onEnded({ _ in
                        onRelease()
                    })
            )
    }
}

//MPRemoteCommandCenter.
struct ContentView: View {
    @StateObject var whisperState = WhisperState()
    @State private var languages: [(String, String)] = []
    let locale: Locale = .current
    
    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    Picker("Language:", selection: $whisperState.langCode) {
                        ForEach(languages, id: \.self.0) { (code, text) in
                            Text(text).tag(code)
                        }
                    }
                    .task {
                        do {
                            let codes = await whisperState.getLanguages() ?? ["de", "en", "fr", "pt"]
                            languages = codes.map({ code in
                                (code, locale.localizedString(forLanguageCode: code) ?? code)
                            }).sorted(by: { a, b in
                                a.1 < b.1
                            })
                        } catch {
                            print("failed to get languages")
                        }
                    }
                    .padding()
                    /*Button("Transcribe", action: {
                     Task {
                     await whisperState.transcribeSample()
                     }
                     })
                     .buttonStyle(.bordered)
                     .disabled(!whisperState.canTranscribe)*/
                    
                    /*Button(whisperState.isRecording ? "Stop recording" : "Start recording", action: {
                        Task {
                            await whisperState.toggleRecord()
                        }
                    })*/
                    Button(whisperState.isRecording ? "Stop recording" : "Start recording", action: {
                        /*Task {
                            await whisperState.toggleRecord()
                        }*/
                    })
                    .modifier(PressActions(onPress: {
                        if (!whisperState.isRecording) {
                            Task {
                                await whisperState.toggleRecord()
                            }
                        }
                    }, onRelease: {
                        if (whisperState.isRecording) {
                            Task {
                                await whisperState.toggleRecord()
                            }
                        }
                    }))
                    .buttonStyle(.bordered)
                    .disabled(!whisperState.canTranscribe)
                }
                
                ScrollView {
                    Text(verbatim: whisperState.messageLog)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Translator")
            .padding()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
