//
//  AdminView.swift
//  PickleBall
//
//  Moderation for admins: reported content with who wrote it, one-tap
//  dismiss / remove / ban, the ban list, and the launch numbers (top
//  countries, weekly return rate, crashes). The server checks every call;
//  this screen only shows for accounts in private.admins.
//

import SwiftUI
import CourtKit
import CourtNet

struct AdminView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab = Pane.reports

    enum Pane: String, CaseIterable, Identifiable {
        case reports, bans, numbers
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .reports: return "Reports"
            case .bans: return "Bans"
            case .numbers: return "Numbers"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch tab {
                case .reports: ReportsQueue()
                case .bans: BanList()
                case .numbers: LaunchNumbers()
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Section", selection: $tab) {
                    ForEach(Pane.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 6)
                .background(.bar)
            }
            .navigationTitle("Moderation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .noticeToast()
    }
}

private struct ReportsQueue: View {
    private let social = Social.shared
    @State private var reports: [AdminReportRow] = []
    @State private var openOnly = true
    @State private var loading = true
    @State private var pending: (AdminReportRow, ReportResolution)?

    var body: some View {
        List {
            Toggle("Open reports only", isOn: $openOnly)
            if reports.isEmpty, !loading {
                ContentUnavailableView("Nothing to review", systemImage: "checkmark.shield")
            }
            ForEach(reports) { report in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(report.targetType.rawValue.capitalized).font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(DS.Palette.electricBlue.opacity(0.15)))
                        Text(report.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if let resolution = report.resolution {
                            Text(resolution.rawValue.capitalized).font(.caption.bold()).foregroundStyle(.secondary)
                        }
                    }
                    Text("“\(report.reason)”").font(.subheadline)
                    if let body = report.body {
                        Text(body).font(.body).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                    }
                    ForEach(report.media, id: \.self) { path in
                        RemotePhoto(path: path)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    if let name = report.authorName {
                        Text("By \(name) · reported \(report.authorReports) time(s)").font(.caption).foregroundStyle(.secondary)
                    }
                    if report.resolvedAt == nil {
                        HStack {
                            Button("Dismiss") { pending = (report, .dismissed) }.buttonStyle(.bordered)
                            Button("Remove") { pending = (report, .removed) }.buttonStyle(.bordered).tint(.orange)
                            if report.author != nil {
                                Button("Ban") { pending = (report, .banned) }.buttonStyle(.borderedProminent).tint(DS.Palette.loss)
                            }
                        }
                        .font(.subheadline.bold())
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .overlay { if loading { ProgressView() } }
        .refreshable { await load() }
        .task(id: openOnly) { await load() }
        .confirmationDialog(title, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            if let item = pending {
                Button(confirmLabel(item.1), role: item.1 == .dismissed ? nil : .destructive) {
                    Task {
                        if await social.resolve(item.0, as: item.1) { await load() }
                    }
                }
            }
        }
    }

    private var title: String {
        switch pending?.1 {
        case .banned: return String(localized: "Ban this account? Their reported content is removed and they’re signed out everywhere.")
        case .removed: return String(localized: "Remove this content?")
        default: return String(localized: "Dismiss this report?")
        }
    }

    private func confirmLabel(_ resolution: ReportResolution) -> LocalizedStringKey {
        switch resolution {
        case .banned: return "Ban"
        case .removed: return "Remove"
        case .dismissed: return "Dismiss"
        }
    }

    private func load() async {
        loading = true
        reports = await social.adminReports(openOnly: openOnly)
        loading = false
    }
}

private struct BanList: View {
    private let social = Social.shared
    @State private var bans: [AdminBanRow] = []
    @State private var loading = true

    var body: some View {
        List {
            if bans.isEmpty, !loading {
                ContentUnavailableView("No bans", systemImage: "hand.thumbsup")
            }
            ForEach(bans) { ban in
                VStack(alignment: .leading, spacing: 4) {
                    Text(ban.name).font(.headline)
                    Text(ban.reason.isEmpty ? String(localized: "No reason given") : ban.reason).font(.subheadline).foregroundStyle(.secondary)
                    Text(ban.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Unban") {
                        Task { if await social.unban(ban.userID) { await load() } }
                    }
                    .tint(DS.Palette.win)
                }
            }
        }
        .overlay { if loading { ProgressView() } }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = true
        bans = await social.adminBans()
        loading = false
    }
}

/// The two numbers that say whether launch worked: where people are, and
/// whether they come back.
private struct LaunchNumbers: View {
    private let social = Social.shared
    @State private var stats: AdminStats?

    var body: some View {
        List {
            if let stats {
                Section {
                    LabeledContent("Installs (all time)", value: "\(stats.installs)")
                    if let week = stats.weeks.first {
                        LabeledContent("Active this week", value: "\(week.active)")
                        if let retention = stats.weeks.dropFirst().first?.retention ?? week.retention {
                            LabeledContent("Weekly return rate", value: retention.formatted(.percent.precision(.fractionLength(0))))
                        }
                    }
                }
                Section("Top countries · last 30 days") {
                    ForEach(Array(stats.countries.enumerated()), id: \.offset) { index, country in
                        HStack {
                            Text("\(index + 1).").foregroundStyle(.secondary).frame(width: 26, alignment: .leading)
                            Text(flag(country.country) + " " + (Locale.current.localizedString(forRegionCode: country.country) ?? country.country))
                            Spacer()
                            Text("\(country.installs)").monospacedDigit().bold()
                        }
                    }
                }
                Section("Weeks") {
                    ForEach(stats.weeks) { week in
                        HStack {
                            Text(week.week).monospacedDigit()
                            Spacer()
                            Text("\(week.active) active").monospacedDigit()
                            Text(week.retention.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—")
                                .monospacedDigit().foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
                        }
                        .font(.subheadline)
                    }
                }
                Section("Crashes · last 14 days") {
                    if stats.crashes.isEmpty { Text("None. Nice.").foregroundStyle(.secondary) }
                    ForEach(stats.crashes) { crash in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(crash.kind.capitalized).bold()
                                Text(crash.appVersion ?? "").foregroundStyle(.secondary)
                                Spacer()
                                Text("×\(crash.count)").monospacedDigit().bold()
                            }
                            if let summary = crash.summary { Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .refreshable { stats = await social.adminStats() }
        .task { stats = await social.adminStats() }
    }

    private func flag(_ code: String) -> String {
        guard code.count == 2 else { return "🏳️" }
        return code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }.map(String.init).joined()
    }
}
