//
//  MediaSupport.swift
//  PickleBall
//
//  Photos in, photos out: resizing before upload, and Apple's on-device
//  Sensitive Content Analysis before posting and before showing. Nothing
//  leaves the phone for the check.
//

import SwiftUI
import UIKit
import SensitiveContentAnalysis
import CourtKit

enum ImageResizer {
    /// Downscaled JPEG, longest side at most `maxDimension`.
    static func jpeg(_ data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return jpeg(image, maxDimension: maxDimension, quality: quality)
    }

    static func jpeg(_ image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

enum ContentSafety {
    /// False when the photo looks sensitive. When the person hasn't turned
    /// on Sensitive Content Warning (or Communication Safety) in Settings
    /// the system doesn't analyse, and reports and blocks still apply.
    static func isSafe(imageData: Data) async -> Bool {
        let analyzer = SCSensitivityAnalyzer()
        guard analyzer.analysisPolicy != .disabled,
              let image = UIImage(data: imageData)?.cgImage else { return true }
        let result = try? await analyzer.analyzeImage(image)
        return !(result?.isSensitive ?? false)
    }

    static func isSafe(videoAt url: URL) async -> Bool {
        let analyzer = SCSensitivityAnalyzer()
        guard analyzer.analysisPolicy != .disabled else { return true }
        let result = try? await analyzer.videoAnalysis(forFileAt: url).hasSensitiveContent()
        return !(result?.isSensitive ?? false)
    }

    static var isActive: Bool { SCSensitivityAnalyzer().analysisPolicy != .disabled }
}

/// A friends-only photo from storage, blurred behind a tap if the system
/// flags it.
struct RemotePhoto: View {
    let path: String
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?
    @State private var isSensitive = false
    @State private var revealed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .blur(radius: isSensitive && !revealed ? 40 : 0)
                    .clipped()
                if isSensitive && !revealed {
                    VStack(spacing: 8) {
                        Image(systemName: "eye.slash.fill").font(.title2)
                        Text("This may be sensitive").font(.subheadline.weight(.semibold))
                        Button("Show") { revealed = true }
                            .buttonStyle(.borderedProminent)
                            .tint(.white.opacity(0.25))
                    }
                    .foregroundStyle(.white)
                }
            } else {
                Rectangle().fill(DS.Palette.fieldGrey)
                ProgressView()
            }
        }
        .task(id: path) {
            guard let url = await Social.shared.mediaURL(path),
                  let response = try? await URLSession.shared.data(from: url),
                  let loaded = UIImage(data: response.0) else { return }
            let data = response.0
            isSensitive = !(await ContentSafety.isSafe(imageData: data))
            image = loaded
        }
    }
}
