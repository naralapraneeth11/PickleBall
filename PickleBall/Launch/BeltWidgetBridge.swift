//
//  BeltWidgetBridge.swift
//  PickleBall
//
//  Keeps the belt widget's snapshot fresh: the belts around me, who's
//  wearing them, and their faces, written into the shared App Group
//  container the widget reads. Called whenever the belts change.
//

import Foundation
import WidgetKit
import CourtKit
import CourtNet

@MainActor
enum BeltWidgetBridge {
    static let appGroup = "group.ME.PickleBall"
    static let snapshotFile = "belt-widget.json"

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    private static var lastWritten: BeltWidgetSnapshot?

    static func update(belts: BeltLedger) {
        guard let container else { return }
        let social = Social.shared
        let me = PlayerDirectory.shared.me.id
        let avatars = container.appendingPathComponent("avatars", isDirectory: true)
        let snapshot = BeltWidgetSnapshot.make(
            me: me,
            ledger: belts,
            names: { id in
                let first = social.firstName(of: id.rawValue)
                return first == "Player" ? nil : first
            },
            avatarFile: { id in
                let file = "\(id.rawValue.uuidString.lowercased()).jpg"
                return FileManager.default.fileExists(atPath: avatars.appendingPathComponent(file).path) ? file : nil
            }
        )
        // Only the belts matter; skip rewrites that change nothing.
        guard snapshot.entries != lastWritten?.entries else { return }
        lastWritten = snapshot
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: container.appendingPathComponent(snapshotFile), options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // The widget keeps its last snapshot.
        }
        Task { await fetchAvatars(for: belts, into: avatars) }
    }

    /// Downloads the faces the widget needs (public avatars), then
    /// refreshes the snapshot so it picks them up.
    private static func fetchAvatars(for belts: BeltLedger, into folder: URL) async {
        let social = Social.shared
        guard let backend = social.backend else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var fetched = false
        let holders = Set(belts.belts(involving: PlayerDirectory.shared.me.id).compactMap { $0.holder }.filter { $0.count == 1 }.map { $0[0] })
        for id in holders {
            let file = folder.appendingPathComponent("\(id.rawValue.uuidString.lowercased()).jpg")
            guard !FileManager.default.fileExists(atPath: file.path),
                  let path = social.profiles[id.rawValue]?.avatarPath ?? (id.rawValue == social.userID ? social.profile?.avatarPath : nil),
                  let url = try? await backend.url(for: path, in: .avatars),
                  let (data, _) = try? await URLSession.shared.data(from: url), !data.isEmpty else { continue }
            try? data.write(to: file, options: .atomic)
            fetched = true
        }
        if fetched {
            lastWritten = nil
            update(belts: belts)
        }
    }
}
