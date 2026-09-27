#if os(iOS)
import StoreKit
import SwiftUI

extension View {
    /// At the app's root: shows the App Store's messages in this view's
    /// window when no screen holds them, and gives `messages` to the
    /// screens below, which hold them with `holdsStoreMessages()`.
    public func showsStoreMessages(_ messages: LabMessages) -> some View {
        modifier(ShowsStoreMessages(messages: messages))
    }

    /// On a screen that needs the customer's whole attention (a parent
    /// answering a dose, an entry made in ten seconds): the App Store's
    /// messages wait until it goes. Does nothing without
    /// `showsStoreMessages(_:)` above it.
    public func holdsStoreMessages() -> some View {
        modifier(HoldsStoreMessages())
    }
}

private struct ShowsStoreMessages: ViewModifier {
    let messages: LabMessages
    @Environment(\.displayStoreKitMessage) private var display
    @Environment(\.scenePhase) private var scenePhase
    /// This window's root, the same while it lives.
    @State private var id = UUID().uuidString

    func body(content: Content) -> some View {
        content
            .environment(messages)
            .onAppear {
                messages.attach(id) { message in
                    // StoreKit shows only a message still pending, once;
                    // one it could not show waits for the next try.
                    try display(message)
                }
            }
            .onDisappear {
                messages.detach(id)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    messages.retry()
                }
            }
    }
}

private struct HoldsStoreMessages: ViewModifier {
    @Environment(LabMessages.self) private var messages: LabMessages?
    /// This screen's hold, the same while it lives.
    @State private var id = UUID().uuidString

    func body(content: Content) -> some View {
        content
            .onAppear {
                messages?.hold(id)
            }
            .onDisappear {
                messages?.release(id)
            }
    }
}
#endif
