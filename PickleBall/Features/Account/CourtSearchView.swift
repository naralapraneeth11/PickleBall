//
//  CourtSearchView.swift
//  PickleBall
//
//  Find a court with Apple Maps search. Used for home courts, court tags
//  on matches, call outs and tournament schedules.
//

import SwiftUI
import MapKit
import CourtKit

struct CourtSearchView: View {
    let onPick: (CourtTag) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        pick(CourtTag(name: query.trimmingCharacters(in: .whitespaces)))
                    } label: {
                        Label("Use “\(query.trimmingCharacters(in: .whitespaces))”", systemImage: "text.cursor")
                    }
                }
                ForEach(results, id: \.self) { item in
                    Button {
                        let coordinate = item.placemark.coordinate
                        pick(CourtTag(name: item.name ?? query, latitude: coordinate.latitude, longitude: coordinate.longitude,
                                      mapItemID: item.identifier?.rawValue))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Court").foregroundStyle(.primary)
                            if let address = item.placemark.title {
                                Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            .overlay {
                if isSearching { ProgressView() }
                else if results.isEmpty && query.isEmpty {
                    ContentUnavailableView("Find a court", systemImage: "mappin.and.ellipse",
                                           description: Text("Search Apple Maps for a park, club or court."))
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Court or park")
            .onChange(of: query) { _, _ in search() }
            .navigationTitle("Court")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func pick(_ court: CourtTag) {
        Haptics.selection()
        onPick(court)
        dismiss()
    }

    private func search() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            request.resultTypes = [.pointOfInterest, .address]
            let response = try? await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            results = response?.mapItems ?? []
        }
    }
}
