import AppKit
import Foundation

/// Per-host screenshots for the start page, kept across launches.
///
/// Mirrors `SitePreviewStore` in the shared desktop engine: each host owns one
/// `<hex key>.jpg` file holding a 640-by-400-pixel, 16:10 crop of the top of
/// the page, the store is bounded to the most recently captured hosts, and
/// clearing history removes every screenshot that is not a favourite's.
@MainActor
final class SitePreviewCache: ObservableObject {
    private static let instance = KelpieProfileValue<SitePreviewCache>()
    static var shared: SitePreviewCache { instance.get { SitePreviewCache() } }

    static let previewSize = CGSize(width: 640, height: 400)
    private static let capacity = 96

    @Published private(set) var images: [String: NSImage] = [:]

    private let directory: URL
    /// Capture order per host; the lowest is evicted first.
    private var order: [String: Int] = [:]
    private var nextOrder = 1

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        directory = KelpieStorage.isolated(base).appendingPathComponent("SitePreviews", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    func image(forHost host: String) -> NSImage? {
        images[host.lowercased()]
    }

    /// Crops, scales and stores a viewport snapshot. Snapshots that show
    /// nothing yet, such as an unpainted page, are discarded.
    func store(_ snapshot: NSImage, forHost host: String) {
        let key = host.lowercased()
        guard !key.isEmpty, let preview = Self.preview(from: snapshot),
              let jpeg = NSBitmapImageRep(cgImage: preview)
                .representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { return }
        images[key] = NSImage(cgImage: preview, size: Self.previewSize)
        order[key] = nextOrder
        nextOrder += 1
        let file = fileURL(forHost: key)
        Task.detached(priority: .utility) { try? jpeg.write(to: file, options: .atomic) }
        evictIfNeeded()
    }

    /// Removes every screenshot except those of `hosts`.
    func retainOnly(_ hosts: Set<String>) {
        for key in images.keys where !hosts.contains(key) { remove(key) }
    }

    // MARK: - Private

    private func load() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let dated = files.compactMap { url -> (String, Date, URL)? in
            guard url.pathExtension == "jpg", let host = Self.host(forKey: url.deletingPathExtension().lastPathComponent)
            else { return nil }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (host, date ?? .distantPast, url)
        }
        for (host, _, url) in dated.sorted(by: { $0.1 < $1.1 }) {
            guard let image = NSImage(contentsOf: url) else { continue }
            images[host] = image
            order[host] = nextOrder
            nextOrder += 1
        }
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        while images.count > Self.capacity, let oldest = order.min(by: { $0.value < $1.value })?.key {
            remove(oldest)
        }
    }

    private func remove(_ key: String) {
        images[key] = nil
        order[key] = nil
        try? FileManager.default.removeItem(at: fileURL(forHost: key))
    }

    private func fileURL(forHost host: String) -> URL {
        directory.appendingPathComponent(Self.key(forHost: host)).appendingPathExtension("jpg")
    }

    /// Lower-case hex of the host, as the desktop engine names its files.
    static func key(forHost host: String) -> String {
        host.lowercased().utf8.map { String(format: "%02x", $0) }.joined()
    }

    static func host(forKey key: String) -> String? {
        guard !key.isEmpty, key.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var index = key.startIndex
        while index < key.endIndex {
            let next = key.index(index, offsetBy: 2)
            guard let byte = UInt8(key[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    /// The top of the page at the card's 16:10 shape, scaled down to at most
    /// `previewSize`, or nil when the snapshot is effectively one flat colour.
    static func preview(from snapshot: NSImage) -> CGImage? {
        guard let source = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
              source.width > 0, source.height > 0 else { return nil }
        let width = CGFloat(source.width)
        let height = CGFloat(source.height)
        let crop: CGRect
        if width / height > 1.6 {
            let cropWidth = (height * 1.6).rounded(.down)
            crop = CGRect(x: ((width - cropWidth) / 2).rounded(.down), y: 0, width: cropWidth, height: height)
        } else {
            crop = CGRect(x: 0, y: 0, width: width, height: (width / 1.6).rounded(.down))
        }
        guard let cropped = source.cropping(to: crop) else { return nil }
        let scale = min(1, previewSize.width / crop.width)
        let target = CGSize(width: (crop.width * scale).rounded(), height: (crop.height * scale).rounded())
        guard let context = CGContext(
            data: nil, width: Int(target.width), height: Int(target.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(origin: .zero, size: target))
        guard let scaled = context.makeImage(), !looksBlank(context) else { return nil }
        return scaled
    }

    /// Mirrors `site_preview::LooksBlank`: a luminance spread of 12 or less.
    private static func looksBlank(_ context: CGContext) -> Bool {
        guard let data = context.data else { return true }
        let pixels = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * context.height)
        var lowest = 255
        var highest = 0
        for row in 0..<context.height {
            let start = row * context.bytesPerRow
            for column in stride(from: 0, to: context.width * 4, by: 4) {
                let red = Int(pixels[start + column])
                let green = Int(pixels[start + column + 1])
                let blue = Int(pixels[start + column + 2])
                let luma = (red * 299 + green * 587 + blue * 114) / 1000
                lowest = min(lowest, luma)
                highest = max(highest, luma)
                if highest - lowest > 12 { return false }
            }
        }
        return true
    }
}
