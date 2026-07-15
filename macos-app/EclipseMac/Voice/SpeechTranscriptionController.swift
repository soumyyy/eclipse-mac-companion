import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechTranscriptionController: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func startListening() {
        guard !isListening else { return }
        transcript = ""
        errorMessage = nil

        Task {
            guard await requestPermissions() else { return }
            do {
                try beginRecognition()
            } catch {
                errorMessage = error.localizedDescription
                isListening = false
            }
        }
    }

    func stopListening() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        isListening = false
    }

    func cancelListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
    }

    private func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            errorMessage = Self.message(for: speechStatus)
            return false
        }

        let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard microphoneAllowed else {
            errorMessage = "Microphone permission is required for push-to-talk."
            return false
        }

        return true
    }

    private func beginRecognition() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    transcript = result.bestTranscription.formattedString
                }
                if let error {
                    errorMessage = error.localizedDescription
                    cancelListening()
                } else if result?.isFinal == true {
                    stopListening()
                }
            }
        }
    }

    private static func message(for status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            "Speech recognition is allowed."
        case .denied:
            "Speech recognition permission is required for voice chat."
        case .restricted:
            "Speech recognition is restricted on this Mac."
        case .notDetermined:
            "Speech recognition permission has not been granted yet."
        @unknown default:
            "Speech recognition is unavailable."
        }
    }
}

enum SpeechTranscriptionError: LocalizedError {
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            "Speech recognition is currently unavailable."
        }
    }
}
