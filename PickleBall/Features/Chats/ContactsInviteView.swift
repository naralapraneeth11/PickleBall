//
//  ContactsInviteView.swift
//  PickleBall
//
//  Invite people from your contacts with a text. Contacts are read on the
//  phone only, after you allow it, and never uploaded: tapping Invite opens
//  Messages with your friend link already written.
//

import SwiftUI
import Contacts
import MessageUI
import CourtKit
import CourtNet

struct ContactsInviteView: View {
    @Environment(\.dismiss) private var dismiss
    private let social = Social.shared

    @State private var access: CNAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    @State private var contacts: [InviteContact] = []
    @State private var query = ""
    @State private var isLoading = false
    @State private var link: URL?
    @State private var composing: MessageDraft?
    @State private var sharing: MessageDraft?
    @State private var invited: Set<String> = []

    var body: some View {
        NavigationStack {
            content
                .courtGround()
                .navigationTitle("Invite contacts")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .task { await prepare() }
                .sheet(item: $composing) { draft in
                    MessageComposer(draft: draft) { sent in
                        if sent { invited.insert(draft.contactID) }
                        composing = nil
                    }
                    .ignoresSafeArea()
                }
                .sheet(item: $sharing) { draft in
                    ShareSheet(items: [draft.body])
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch access {
        case .authorized, .limited:
            list
        case .denied, .restricted:
            explainer(denied: true)
        default:
            explainer(denied: false)
        }
    }

    // MARK: Ask

    private func explainer(denied: Bool) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Court.text)
                .frame(width: 76, height: 76)
                .courtRaised(cornerRadius: 24)
            Text("Bring your people")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Court.text)
            Text(denied
                 ? "PickleBall can’t see your contacts. You can turn it on in Settings, or share your link instead."
                 : "Pick who you play with and text them an invite. Your contacts stay on your iPhone and are never uploaded.")
                .font(.system(size: 15))
                .foregroundStyle(Court.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button {
                if denied {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } else {
                    Task { await requestAccess() }
                }
            } label: {
                Text(denied ? "Open Settings" : "Show my contacts")
                    .courtBigButton()
            }
            .buttonStyle(.press)
            .padding(.horizontal, 24)
            Button {
                sharing = MessageDraft(contactID: "", recipients: [], body: inviteText(for: nil))
            } label: {
                Text("Share my link instead")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Court.muted)
            }
            Spacer()
            Spacer()
        }
    }

    // MARK: List

    private var filtered: [InviteContact] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return contacts }
        return contacts.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var list: some View {
        List {
            if access == .limited {
                Section {
                    Text("You’re sharing some contacts with PickleBall. Change which ones in Settings → Apps → PickleBall → Contacts.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(Court.muted)
                        .listRowBackground(Color.clear)
                }
            }
            Section {
                Group {
                    ForEach(filtered) { contact in
                        row(contact)
                    }
                }
                .courtRows()
            } footer: {
                Text("Invites go out as a normal text from your phone. Contacts are never uploaded.")
            }
        }
        .courtList()
        .searchable(text: $query, prompt: "Search contacts")
        .overlay {
            if isLoading {
                ProgressView()
            } else if contacts.isEmpty {
                ContentUnavailableView("No contacts with a phone number", systemImage: "person.crop.circle",
                                       description: Text("Share your link instead."))
            }
        }
    }

    private func row(_ contact: InviteContact) -> some View {
        HStack(spacing: 12) {
            Group {
                if let data = contact.thumbnail, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Avatar(name: contact.name, color: Court.avatarBackground, size: 38)
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Court.text)
                    .lineLimit(1)
                Text(contact.phone)
                    .font(DS.Typography.caption)
                    .foregroundStyle(Court.muted)
                    .lineLimit(1)
            }
            Spacer()
            if invited.contains(contact.id) {
                Label("Sent", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.win)
            } else {
                Button("Invite") { invite(contact) }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Court.text)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .courtRaisedCapsule()
                    .buttonStyle(.press)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Actions

    private func prepare() async {
        if access == .authorized || access == .limited { await load() }
        if link == nil, social.phase == .ready, let invite = await social.inviteLink(.friend) {
            link = social.shareURL(for: invite)
        }
    }

    private func requestAccess() async {
        let granted = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
        access = CNContactStore.authorizationStatus(for: .contacts)
        if granted { await load() }
    }

    private func load() async {
        isLoading = true
        contacts = await Task.detached(priority: .userInitiated) { InviteContact.fetchAll() }.value
        isLoading = false
    }

    private func invite(_ contact: InviteContact) {
        Haptics.light()
        let draft = MessageDraft(contactID: contact.id, recipients: [contact.phone], body: inviteText(for: contact))
        if MFMessageComposeViewController.canSendText() {
            composing = draft
        } else {
            // No Messages (iPad, simulator): the share sheet still works.
            sharing = draft
        }
    }

    private func inviteText(for contact: InviteContact?) -> String {
        let hello = contact.map { String(localized: "Hey \($0.firstName)! ") } ?? ""
        if let link {
            return hello + String(localized: "I’m keeping score on PickleBall. Tap to add me and let’s play: \(link.absoluteString)")
        }
        if let site = social.backend?.config.site {
            let username = social.profile.map { " @\($0.username)" } ?? ""
            return hello + String(localized: "I’m keeping score on PickleBall. Get it here and add me\(username): \(site.absoluteString)")
        }
        return hello + String(localized: "I’m keeping score on PickleBall. Get it on the App Store and let’s play.")
    }
}

// MARK: - Contacts

nonisolated struct InviteContact: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let firstName: String
    let phone: String
    let thumbnail: Data?

    /// Everyone with a phone number, by name. Runs off the main thread.
    static func fetchAll() -> [InviteContact] {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        var list: [InviteContact] = []
        try? store.enumerateContacts(with: request) { contact, _ in
            guard let number = contact.phoneNumbers.first?.value.stringValue else { return }
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? number
            list.append(InviteContact(id: contact.identifier, name: name,
                                      firstName: contact.givenName.isEmpty ? name : contact.givenName,
                                      phone: number, thumbnail: contact.thumbnailImageData))
        }
        return list
    }
}

struct MessageDraft: Identifiable {
    let id = UUID()
    let contactID: String
    let recipients: [String]
    let body: String
}

/// Messages, with the invite written and the number filled in.
private struct MessageComposer: UIViewControllerRepresentable {
    let draft: MessageDraft
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = draft.recipients
        controller.body = draft.body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            onFinish(result == .sent)
        }
    }
}
