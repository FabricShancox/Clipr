// Sources/Clipr/AdvancedMode/Export/PDFGuideExporter.swift
import AppKit
import WebKit

enum PDFExportError: Error, Equatable {
    case loadFailed
    case timedOut
    case printFailed
}

/// Prints the guide's embedded HTML through WebKit straight to a PDF file, so pagination follows
/// the template's `break-inside: avoid` and the PDF matches the HTML export exactly.
///
/// Main thread only (WebKit and AppKit printing). One export per instance. The web view lives in
/// a borderless window that is never shown: `NSPrintOperation.runModal(for:…)` needs a window to
/// run for, and a web view's print operation run without one prints blank pages.
@MainActor
final class PDFGuideExporter: NSObject, WKNavigationDelegate {
    nonisolated static let defaultTimeout: TimeInterval = 30
    /// 18 mm in points.
    nonisolated static let marginPoints: CGFloat = 18 / 25.4 * 72
    /// Regions that use US Letter; everywhere else gets A4.
    private static let letterRegions: Set<String> = ["US", "CA", "MX", "PH", "PR", "CL", "CO", "VE", "GT", "CR"]

    private let timeout: TimeInterval
    private var webView: WKWebView?
    private var window: NSWindow?
    private var destination: URL?
    private var paperSize = NSSize(width: 595.28, height: 841.89)
    private var continuation: CheckedContinuation<Void, Error>?

    init(timeout: TimeInterval = PDFGuideExporter.defaultTimeout) {
        self.timeout = timeout
    }

    static func paperSize(for locale: Locale) -> NSSize {
        letterRegions.contains(locale.region?.identifier ?? "")
            ? NSSize(width: 612, height: 792)
            : NSSize(width: 595.28, height: 841.89)
    }

    /// Throws `PDFExportError`. Gives up with `.timedOut` after `timeout` seconds.
    func export(html: String, to url: URL, locale: Locale = .current) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            destination = url
            paperSize = Self.paperSize(for: locale)
            let frame = NSRect(x: 0, y: 0, width: 800, height: 1000)
            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let webView = WKWebView(frame: frame)
            window.contentView = webView
            webView.navigationDelegate = self
            self.window = window
            self.webView = webView
            webView.loadHTMLString(html, baseURL: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(.failure(PDFExportError.timedOut))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        startPrinting()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(PDFExportError.loadFailed))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(PDFExportError.loadFailed))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failure(PDFExportError.loadFailed))
    }

    private func startPrinting() {
        guard let webView, let window, let destination, continuation != nil else { return }
        let info = NSPrintInfo()
        info.paperSize = paperSize
        info.topMargin = Self.marginPoints
        info.bottomMargin = Self.marginPoints
        info.leftMargin = Self.marginPoints
        info.rightMargin = Self.marginPoints
        info.horizontalPagination = .automatic
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        // The operation's view starts zero-sized; without a frame WebKit lays out nothing to print.
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: self,
                           didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        let written = destination.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        finish(success && written ? .success(()) : .failure(PDFExportError.printFailed))
    }

    /// Resumes the caller exactly once, whichever of success, failure or the timeout comes first.
    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        webView?.navigationDelegate = nil
        webView = nil
        window = nil
        continuation.resume(with: result)
    }
}
