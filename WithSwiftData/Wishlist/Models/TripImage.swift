/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A model that stores the full-size image data for a trip.
*/

import Foundation
import SwiftData
import UIKit

/// A model that stores the full-size image data for a trip.
@Model
class TripImage {

    /// The full-size image data, stored in a standalone file.
    @Attribute(.externalStorage) var data: Data

    var trip: Trip?

    init(data: Data) {
        self.data = data
    }

    convenience init(name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpeg") else {
            fatalError("Could not find resource '\(name).jpeg' in main bundle")
        }

        do {
            self.init(data: try Data(contentsOf: url))
        } catch {
            fatalError("Could not load resource '\(name).jpeg' from main bundle: \(error)")
        }
    }

    static func thumbnailData(from data: Data, maxDimension: CGFloat = 1290, compressionQuality: CGFloat = 0.7) -> Data? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary) {
            return UIImage(cgImage: image).jpegData(compressionQuality: compressionQuality)
        } else {
            return nil
        }
    }
}
