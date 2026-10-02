//
//  PlayerSlotField.swift
//  PickleBall
//
//  A player slot in match setup. Type to search people you've played, pick
//  one (exact ID), or add a new guest. Whatever is typed but not picked is
//  resolved to an ID when the match starts.
//

import SwiftUI
import CourtKit

enum SlotEntry: Equatable {
    case empty
    case typed(String)
    case player(PlayerRef)

    var player: PlayerRef? {
        if case .player(let ref) = self { return ref }
        return nil
    }

    var text: String {
        switch self {
        case .empty: return ""
        case .typed(let text): return text
        case .player(let ref): return ref.displayName
        }
    }

    /// Turns the slot into a player, creating a guest when needed.
    @MainActor
    func resolved(placeholder: String) -> PlayerRef {
        switch self {
        case .player(let ref): return ref
        case .typed(let text): return PlayerDirectory.shared.resolve(typedName: text)
        case .empty: return PlayerDirectory.shared.resolve(typedName: placeholder)
        }
    }
}

struct PlayerSlotField: View {
    @Binding var entry: SlotEntry
    let placeholder: String
    let accent: Color
    /// Players already used in other slots.
    var excluded: Set<PlayerID> = []

    @ObservedObject private var directory = PlayerDirectory.shared
    @FocusState private var focused: Bool

    private var typedText: Binding<String> {
        Binding(
            get: { entry.player == nil ? entry.text : "" },
            set: { entry = $0.isEmpty ? .empty : .typed($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let player = entry.player {
                selectedChip(player)
            } else {
                TextField(placeholder, text: typedText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Court.text)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(commitTyped)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .courtField()
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .stroke(focused ? Court.text.opacity(0.5) : .clear, lineWidth: 1.5)
                    )
                    .accessibilityLabel(placeholder)

                if focused {
                    suggestions
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(DS.Motion.snappy, value: focused)
        .animation(DS.Motion.snappy, value: entry)
    }

    private func selectedChip(_ player: PlayerRef) -> some View {
        HStack(spacing: 10) {
            Text(initials(player.displayName))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(ProfileAvatar.color(for: player.id.rawValue)))

            VStack(alignment: .leading, spacing: 1) {
                Text(player.id == directory.me.id ? "\(player.displayName) (you)" : player.displayName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Court.text)
                    .lineLimit(1)
                Text(player.kind == .guest ? "Guest" : "Player")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Court.muted)
            }

            Spacer(minLength: 0)

            Button {
                Haptics.light()
                entry = .empty
                focused = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Court.muted.opacity(0.7))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.press)
            .accessibilityLabel("Change player")
        }
        .padding(.leading, 8)
        .frame(height: 46)
        .courtField()
    }

    private var suggestions: some View {
        let typed = entry.text.trimmingCharacters(in: .whitespaces)
        let matches = directory.suggestions(for: typed, excluding: excluded)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(matches) { player in
                    Button {
                        Haptics.selection()
                        entry = .player(player)
                        focused = false
                    } label: {
                        Text(player.id == directory.me.id ? "You" : player.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Court.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Court.raised))
                            .overlay(Capsule().stroke(Court.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.press)
                }
                if !typed.isEmpty {
                    Button {
                        Haptics.selection()
                        entry = .player(directory.addGuest(named: typed))
                        focused = false
                    } label: {
                        Label("New guest “\(typed)”", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Court.ground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Court.text))
                    }
                    .buttonStyle(.press)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func commitTyped() {
        let typed = entry.text.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return }
        entry = .player(directory.resolve(typedName: typed))
    }

    private func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
