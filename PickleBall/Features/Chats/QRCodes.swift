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
    @State private var url: URL?

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
            .task {
                if let link = await social.inviteLink(.friend) { url = social.shareURL(for: link) }
            }
        }
    }
}

enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
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
