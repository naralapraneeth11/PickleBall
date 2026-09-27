//
//  ProfileSetupView.swift
//  PickleBall
//
//  Name, username, photo, sports, and (optionally) home courts. Also used
//  to edit the profile later from Me.
//

import SwiftUI
import PhotosUI
import CourtKit
import CourtNet

struct ProfileSetupView: View {
    var isEditing = false
    @Environment(\.dismiss) private var dismiss
    private let social = Social.shared

    @State private var displayName = ""
    @State private var username = ""
    @State private var sports: Set<Sport> = [.pickleball]
    @State private var homeCourts: [CourtTag] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var availability: Availability = .unknown
    @State private var isSaving = false
    @State private var showCourtSearch = false
    @State private var checkTask: Task<Void, Never>?

    enum Availability: Equatable {
        case unknown, checking, available, taken
        case invalid(String)
    }

    private var normalized: String { Username.normalize(username) }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty && availability == .available && !sports.isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            avatar
                        }
                        .accessibilityLabel("Choose a profile photo")
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Name") {
                    TextField("Your name", text: $displayName)
                        .textContentType(.name)
                        .submitLabel(.next)
                }

                Section {
                    HStack(spacing: 4) {
                        Text("@").foregroundStyle(.secondary)
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                        availabilityBadge
                    }
                } header: {
                    Text("Username")
                } footer: {
                    Text(availabilityMessage)
                }

                Section("Sports") {
                    ForEach(Sport.allCases) { sport in
                        Toggle(isOn: Binding(
                            get: { sports.contains(sport) },
                            set: { on in if on { sports.insert(sport) } else { sports.remove(sport) } }
                        )) {
                            Label(sport.displayName, systemImage: sport.symbolName)
                        }
                        .tint(sport.theme.accent)
                    }
                }

                Section {
                    ForEach(homeCourts, id: \.self) { court in
                        Label(court.name, systemImage: "mappin.and.ellipse")
                    }
                    .onDelete { homeCourts.remove(atOffsets: $0) }
                    Button {
                        showCourtSearch = true
                    } label: {
                        Label("Add a court", systemImage: "plus")
                    }
                } header: {
                    Text("Home courts")
                } footer: {
                    Text("Optional. Helps friends know where you play.")
                }
            }
            .navigationTitle(isEditing ? "Edit profile" : "Set up your profile")
            .toolbar {
                if isEditing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Done") { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showCourtSearch) {
                CourtSearchView { court in
                    if !homeCourts.contains(court) { homeCourts.append(court) }
                }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    photoData = ImageResizer.jpeg(data, maxDimension: 800)
                }
            }
            .onChange(of: username) { _, _ in checkUsername() }
            .onAppear(perform: prefill)
            .disabled(isSaving)
            .noticeToast()
        }
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let userID = social.userID, social.profile?.avatarPath != nil {
                    ProfileAvatar(userID: userID, size: 96)
                } else {
                    Avatar(name: displayName.isEmpty ? "?" : displayName, color: DS.Palette.courtBlue, size: 96)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            Image(systemName: "camera.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(DS.Palette.royalBlue))
                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
        }
    }

    @ViewBuilder
    private var availabilityBadge: some View {
        switch availability {
        case .checking: ProgressView().controlSize(.small)
        case .available: Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.Palette.win)
        case .taken, .invalid: Image(systemName: "xmark.circle.fill").foregroundStyle(DS.Palette.loss)
        case .unknown: EmptyView()
        }
    }

    private var availabilityMessage: String {
        switch availability {
        case .taken: return "That username is taken."
        case .invalid(let message): return message
        case .available: return "Friends can find you as @\(normalized)."
        default: return "3–20 characters: letters, numbers, _ and ."
        }
    }

    private func prefill() {
        guard displayName.isEmpty else { return }
        if let profile = social.profile {
            displayName = profile.displayName
            username = profile.username
            sports = Set(profile.sports)
            homeCourts = profile.homeCourts
            availability = .available
        } else {
            let appleName = UserDefaults.standard.string(forKey: "apple_full_name") ?? ""
            let local = PlayerDirectory.profileDisplayName()
            displayName = appleName.isEmpty ? (local == "You" ? "" : local) : appleName
            if !displayName.isEmpty { username = Username.suggestion(from: displayName) }
        }
    }

    private func checkUsername() {
        checkTask?.cancel()
        let name = normalized
        if let problem = Username.problem(with: name) {
            availability = name.isEmpty ? .unknown : .invalid(problem.message)
            return
        }
        if name == social.profile?.username {
            availability = .available
            return
        }
        availability = .checking
        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let free = await social.isUsernameAvailable(name)
            guard !Task.isCancelled else { return }
            availability = free == false ? .taken : .available
        }
    }

    private func save() {
        guard let cleaned = ContentFilter.standard.cleaned(displayName.trimmingCharacters(in: .whitespaces)) else {
            social.notice = "Please choose a different name."
            return
        }
        isSaving = true
        Haptics.medium()
        Task {
            let ok = await social.saveProfile(username: normalized, displayName: cleaned,
                                              sports: Sport.allCases.filter(sports.contains), homeCourts: homeCourts, avatar: photoData)
            isSaving = false
            if ok, isEditing { dismiss() }
        }
    }
}
