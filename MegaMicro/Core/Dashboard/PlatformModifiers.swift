import SwiftUI

/// Interaction modifiers that exist on macOS/iOS but not watchOS. The shared
/// board views use these so they compile everywhere; on the Watch (a pure
/// monitor) they no-op.
extension View {
    @ViewBuilder
    func platformHover(_ action: @escaping (Bool) -> Void) -> some View {
        #if os(watchOS)
        self
        #else
        self.onHover(perform: action)
        #endif
    }

    @ViewBuilder
    func platformHelp(_ text: String) -> some View {
        #if os(watchOS)
        self
        #else
        self.help(text)
        #endif
    }

    @ViewBuilder
    func platformDraggable(_ payload: String, enabled: Bool) -> some View {
        #if os(watchOS)
        self
        #else
        if enabled { self.draggable(payload) } else { self }
        #endif
    }

    @ViewBuilder
    func platformKeyDrop(onDrop: @escaping (String) -> Bool,
                         isTargeted: @escaping (Bool) -> Void) -> some View {
        #if os(watchOS)
        self
        #else
        self.dropDestination(for: String.self) { items, _ in
            guard let payload = items.first else { return false }
            return onDrop(payload)
        } isTargeted: { targeted in
            isTargeted(targeted)
        }
        #endif
    }
}
