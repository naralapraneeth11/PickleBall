//
//  ServeViews.swift
//  PickleBall
//
//  Writing a Serve (text, photos or a video; or "Serve this result") and
//  a Serve's page with its Returns: comments, chants and photos. Photos
//  and videos are checked on the device before they go up.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import CourtKit
import CourtNet

struct ServeComposerView: View {
    /// Set for "Serve this result".
    var matchID: UUID?
    var matchSummary: String?

    @Environment(\.dismiss) private var dismiss
    private let social = Social.shared
    @State private var text = ""
    @State private var items: [PhotosPickerItem] = []
    @State private var photos: [Data] = []
    @State private var video: Data?
    @State private var isPosting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Group {
                        TextField(matchID == nil ? "What’s happening on court?" : "Say something about it", text: $text, axis: .vertical)
                            .lineLimit(3...8)
                        if let matchSummary {
                            Label(matchSummary, systemImage: "sportscourt.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .courtRows()
                }
                if matchID == nil {
                    Section {
                        Group {
                            PhotosPicker(selection: $items, maxSelectionCount: 4, matching: .any(of: [.images, .videos])) {
                                Label("Photos or a video", systemImage: "photo.on.rectangle.angled")
                            }
                            if !photos.isEmpty {
                                ScrollView(.horizontal) {
                                    HStack {
                                        ForEach(Array(photos.enumerated()), id: \.offset) { _, data in
                                            if let image = UIImage(data: data) {
                                                Image(uiImage: image).resizable().scaledToFill()
                                                    .frame(width: 80, height: 80)
                                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            }
                                        }
                                    }
                                }
                            }
                            if video != nil { Label("Video attached", systemImage: "video.fill") }
                        }
                        .courtRows()
                    }
                }
                Section {
                } footer: {
                    Text("Only your friends see Serves. Never public.")
                }
            }
            .courtList()
            .navigationTitle(matchID == nil ? "New Serve" : "Serve this result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Serve") { post() }
                        .fontWeight(.semibold)
                        .disabled(isPosting || (text.trimmingCharacters(in: .whitespaces).isEmpty && photos.isEmpty && video == nil && matchID == nil))
                }
            }
            .onChange(of: items) { _, newItems in
                Task { await load(newItems) }
            }
            .overlay { if isPosting { ProgressView().controlSize(.large) } }
            .noticeToast()
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        var loadedPhotos: [Data] = []
        var loadedVideo: Data?
        for item in items {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                if let movie = try? await item.loadTransferable(type: Data.self), movie.count < 50_000_000 {
                    loadedVideo = movie
                } else {
                    social.notice = "Videos need to be under 50 MB."
                }
            } else if let data = try? await item.loadTransferable(type: Data.self), let jpeg = ImageResizer.jpeg(data) {
                loadedPhotos.append(jpeg)
            }
        }
        photos = loadedPhotos
        video = loadedVideo
    }

    private func post() {
        isPosting = true
        Task {
            for photo in photos {
                guard await ContentSafety.isSafe(imageData: photo) else {
                    social.notice = "One of those photos can’t be posted."
                    isPosting = false
                    return
                }
            }
            if let video {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("serve-\(UUID().uuidString).mp4")
                try? video.write(to: url)
                let safe = await ContentSafety.isSafe(videoAt: url)
                try? FileManager.default.removeItem(at: url)
                guard safe else {
                    social.notice = "That video can’t be posted."
                    isPosting = false
                    return
                }
            }
            let ok = await social.serve(text: text, photos: photos, video: video, matchID: matchID)
            isPosting = false
            if ok {
                Haptics.success()
                dismiss()
            }
        }
    }
}

struct ServeDetailView: View {
    let serveID: UUID
    private let social = Social.shared
    @State private var text = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var reporting: ReportTarget?
    @State private var confirmBlock: UUID?

    struct ReportTarget: Identifiable {
        let id: UUID
        let kind: ReportDraft.Target
    }

    private var serve: ServeRow? {
        (social.feed + social.myServes).first { $0.id == serveID }
    }

    var body: some View {
        if let serve {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ServeCard(serve: serve)
                        ForEach(serve.mediaPaths.dropFirst(), id: \.self) { path in
                            RemotePhoto(path: path)
                                .frame(height: 240)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        if !serve.isInPlay() {
                            Label("Dead ball: no Returns for a day, so it left the Feed.", systemImage: "moon.zzz.fill")
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(social.returns[serve.id] ?? []) { row in
                            ReturnRowView(row: row)
                                .contextMenu {
                                    if row.authorID == social.userID || serve.authorID == social.userID {
                                        Button("Delete", role: .destructive) { Task { await social.deleteReturn(row) } }
                                    }
                                    if row.authorID != social.userID {
                                        Button("Report", role: .destructive) { reporting = ReportTarget(id: row.id, kind: .return) }
                                    }
                                }
                        }
                    }
                    .padding(16)
                }
                returnBar(serve)
            }
            .courtGround()
            .navigationTitle("Serve")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if serve.authorID == social.userID {
                            Button("Delete Serve", role: .destructive) { Task { await social.deleteServe(serve) } }
                        } else {
                            Button("Report", role: .destructive) { reporting = ReportTarget(id: serve.id, kind: .serve) }
                            Button("Block \(social.firstName(of: serve.authorID))", role: .destructive) { confirmBlock = serve.authorID }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(item: $reporting) { target in ReportSheet(target: target.kind, id: target.id) }
            .confirmationDialog("Block?", isPresented: Binding(get: { confirmBlock != nil }, set: { if !$0 { confirmBlock = nil } })) {
                Button("Block", role: .destructive) {
                    if let id = confirmBlock { Task { await social.block(id) } }
                }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self), let jpeg = ImageResizer.jpeg(data) else { return }
                    photoItem = nil
                    guard await ContentSafety.isSafe(imageData: jpeg) else {
                        social.notice = "That photo can’t be sent."
                        return
                    }
                    await social.sendReturn(.photo, photo: jpeg, to: serve)
                }
            }
            .task { await social.loadReturns(for: serve) }
        } else {
            ContentUnavailableView("This Serve is gone", systemImage: "wind")
        }
    }

    private func returnBar(_ serve: ServeRow) -> some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Chant.presets) { chant in
                        Button {
                            Haptics.light()
                            Task { await social.sendReturn(.chant, text: chant.name, to: serve) }
                        } label: {
                            Text(chant.name)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(DS.Palette.electricBlue.opacity(0.12)))
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo").font(.system(size: 20)).frame(width: 34, height: 34)
                }
                TextField("Return it", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .courtRaised(cornerRadius: 20)
                Button {
                    let body = text
                    text = ""
                    Task { await social.sendReturn(.comment, text: body, to: serve) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
        .padding(.bottom, 64)
        .background(.bar)
    }
}

private struct ReturnRowView: View {
    let row: ReturnRow
    private let social = Social.shared

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProfileAvatar(userID: row.authorID, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(social.firstName(of: row.authorID)).font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(RelativeTime.short(row.createdAt)).font(.caption).foregroundStyle(.secondary)
                }
                switch row.kind {
                case .comment:
                    Text(row.body ?? "").font(.system(size: 15, design: .rounded))
                case .chant:
                    Label(row.body ?? "Chant", systemImage: "hands.clap.fill")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Palette.electricBlue)
                case .photo:
                    if let path = row.mediaPath {
                        RemotePhoto(path: path)
                            .frame(width: 180, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            Spacer()
        }
    }
}
