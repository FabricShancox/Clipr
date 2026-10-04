import CoreGraphics

/// The 8-bit device-RGB bitmap contexts every off-screen render in Clipr draws into.
enum BitmapContext {
    /// A `width`×`height` pixel context. `opaque` drops the alpha channel (for JPEG and GIF,
    /// which have none); otherwise it is premultiplied RGBA and starts fully transparent.
    /// `data`/`bytesPerRow` draw into caller-owned memory; by default CoreGraphics allocates it.
    static func rgb(
        width: Int, height: Int, opaque: Bool = false,
        data: UnsafeMutableRawPointer? = nil, bytesPerRow: Int = 0
    ) -> CGContext? {
        CGContext(
            data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue
        )
    }
}
