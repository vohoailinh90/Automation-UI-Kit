#if os(iOS)
import AVFoundation
import UIKit

/// Says a short confirmation aloud in a Vietnamese voice, as a shop's payment
/// speaker does: `LedgerEntry.readback`, "Đã ghi thu bốn trăm năm mươi nghìn
/// đồng", once an entry is saved.
///
/// It speaks as a courtesy, never as a surprise:
/// - Through the app's audio session, as the app sets it up; the speaker
///   never changes it, since the app may record or play audio its own way.
///   An app with no other sound sets `.ambient` once, at launch (the demo
///   does): other apps' audio keeps playing under the voice, and the Silent
///   switch and the screen lock silence it, as Apple has it for an app that
///   "also works with the sound turned off". Left at the default,
///   `.soloAmbient`, the Silent switch silences it too, but other apps'
///   audio stops.
/// - Never while VoiceOver runs: VoiceOver already reads the app's own
///   confirmation (`labToast` announces its text), and two voices would talk
///   over each other. VoiceOver turning on mid-sentence stops it.
/// - Only with a voice for `language` on the phone: another language's voice
///   would mangle the words.
/// - A newer sentence cuts the one before short, so quick saves never queue
///   up behind each other.
@MainActor
public final class LabSpeaker: NSObject {
    /// One for the app: a speaker says nothing once it is gone, so keep it.
    public static let shared = LabSpeaker()

    /// The voice's language, a BCP 47 code.
    public let language: String
    private let synthesizer = AVSpeechSynthesizer()

    public init(language: String = "vi-VN") {
        self.language = language
        super.init()
        // A selector observer: NotificationCenter drops it with the speaker.
        NotificationCenter.default.addObserver(
            self, selector: #selector(voiceOverChanged), name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil
        )
    }

    /// Says `text`, cutting short whatever it was saying; says nothing while
    /// VoiceOver runs, or with no voice for `language` on the phone.
    public func say(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        guard !UIAccessibility.isVoiceOverRunning, let voice = AVSpeechSynthesisVoice(language: language) else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    /// Stops at once: when the saved entry is undone, say.
    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// VoiceOver turned on: it speaks now, so the speaker stops. UIKit posts
    /// the change on the main thread; the hop keeps that an assumption this
    /// does not rest on.
    @objc nonisolated private func voiceOverChanged() {
        Task { @MainActor in
            if UIAccessibility.isVoiceOverRunning {
                self.stop()
            }
        }
    }
}
#endif
