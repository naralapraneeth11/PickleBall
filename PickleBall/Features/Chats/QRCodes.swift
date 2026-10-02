//
//  QRCodes.swift
//  PickleBall
//
//  Show your friend code as a QR, or scan someone else's. Scanning uses
//  VisionKit's live scanner; codes are invite links.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import Vision
import VisionKit
import CourtKit
import CourtNet

struct MyQRCodeView: View {
    @Environment(\.dismiss) private var dismiss
    private let social = Social.shared
    @State private var url: URL? = MyQRCodeView.lastURL
    @State private var failed = false

    /// The last code made, so the QR shows instantly and with no signal.
    /// Friend links last 30 days; an older one is dropped.
    private static let lastURLKey = "qr.lastFriendLink"
    private static let lastDateKey = "qr.lastFriendLinkDate"
    private static var lastURL: URL? {
        let defaults = UserDefaults.standard
        guard let made = defaults.object(forKey: lastDateKey) as? Date,
              Date().timeIntervalSince(made) < 25 * 86_400 else { return nil }
        return defaults.string(forKey: lastURLKey).flatMap(URL.init(string:))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                if let userID = social.userID {
                    ProfileAvatar(userID: userID, size: 64)
                }
                Text(social.profile?.displayName ?? "")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("@\(social.profile?.username ?? "")").foregroundStyle(.secondary)
                Group {
                    if let url, let image = QRCode.image(for: url.absoluteString) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .padding(18)
                            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white))
                    } else if failed {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(Court.muted)
                            Text(social.backend == nil
                                 ? "Your code needs the PickleBall server. This build isn’t connected to one."
                                 : "Couldn’t make your code. Check your connection.")
                                .font(DS.Typography.caption)
                                .foregroundStyle(Court.muted)
                                .multilineTextAlignment(.center)
                            if social.backend != nil {
                                Button("Try again") { Task { await makeLink() } }
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Court.text)
                                    .padding(.horizontal, 18)
                                    .frame(height: 40)
                                    .courtRaisedCapsule()
                            }
                        }
                        .padding(20)
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: 260, height: 260)
                Text("Friends scan this in PickleBall (or with the Camera app) to add you.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 24)
            .frame(maxHeight: .infinity, alignment: .top)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .courtGround()
            .task { await makeLink() }
        }
    }

    private func makeLink() async {
        failed = false
        if let link = await social.inviteLink(.friend) {
            let fresh = social.shareURL(for: link)
            url = fresh
            UserDefaults.standard.set(fresh.absoluteString, forKey: Self.lastURLKey)
            UserDefaults.standard.set(Date(), forKey: Self.lastDateKey)
        } else if url == nil {
            failed = true
        }
    }
}

enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static let context = CIContext()

    /// Clears the cached code (on sign-out).
    static func forget() {
        UserDefaults.standard.removeObject(forKey: "qr.lastFriendLink")
        UserDefaults.standard.removeObject(forKey: "qr.lastFriendLinkDate")
    }
}

struct QRScannerView: View {
    let onFound: (InviteLink) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    DataScannerRepresentable(onFound: onFound)
                        .ignoresSafeArea()
                } else {
                    ContentUnavailableView("Camera unavailable", systemImage: "camera.fill",
                                           description: Text("Ask your friend for their link or code instead."))
                }
            }
            .navigationTitle("Scan a friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onFound: (InviteLink) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (InviteLink) -> Void
        private var handled = false

        init(onFound: @escaping (InviteLink) -> Void) {
            self.onFound = onFound
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !handled else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item, let text = barcode.payloadStringValue,
                      let link = InviteLink(text: text) else { continue }
                handled = true
                dataScanner.stopScanning()
                Haptics.success()
                onFound(link)
                return
            }
        }
    }
}
