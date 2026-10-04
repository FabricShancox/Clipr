// Sources/Clipr/AdvancedMode/Export/PDFGuideExporter.swift
import AppKit
import PDFKit
import WebKit

enum PDFExportError: Error, Equatable {
    case loadFailed
    case timedOut
    case printFailed
    /// `export` was called a second time on the same exporter.
    case alreadyUsed
    /// `cancel()` was called.
    case cancelled
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
    /// WebKit prints here, never straight to the destination, so a failed or timed-out print (or a
    /// stale file already at the destination) can never be mistaken for a finished export.
    private var tempURL: URL?
    private var timeoutItem: DispatchWorkItem?
    private var used = false
    private var printing = false
    /// Holds the exporter (and so its window and web view) while a print runs: the operation keeps
    /// only an unretained pointer to its delegate, and prints from the window's web view, so neither
    /// may go away before it reports back — even after a timeout or cancel has already finished.
    private var printKeepAlive: PDFGuideExporter?
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
        guard !used else { throw PDFExportError.alreadyUsed }
        used = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            destination = url
            tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
            paperSize = Self.paperSize(for: locale)
            let frame = NSRect(x: 0, y: 0, width: 800, height: 1000)
            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            // The guide is static markup; nothing in it needs to run script while it prints.
            let configuration = WKWebViewConfiguration()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            let webView = WKWebView(frame: frame, configuration: configuration)
            window.contentView = webView
            webView.navigationDelegate = self
            self.window = window
            self.webView = webView
            webView.loadHTMLString(html, baseURL: nil)
            let item = DispatchWorkItem { [weak self] in
                self?.finish(.failure(PDFExportError.timedOut))
            }
            timeoutItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: item)
        }
    }

    /// Stops the export now: halts the page load, ends the print run if it is modal for this
    /// exporter's own window, deletes the temp file and throws `.cancelled` from `export`.
    /// Does nothing once the export has finished.
    func cancel() {
        guard continuation != nil else { return }
        webView?.stopLoading()
        finish(.failure(PDFExportError.cancelled))
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
        guard let webView, let window, let tempURL, continuation != nil else { return }
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
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = tempURL
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        // The operation's view starts zero-sized; without a frame WebKit lays out nothing to print.
        operation.view?.frame = webView.bounds
        printing = true
        printKeepAlive = self
        operation.runModal(for: window, delegate: self,
                           didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    /// AppKit calls this from the print operation's own thread, so hop to the main actor before
    /// touching the window, the continuation or the file system state.
    @objc private nonisolated func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.printDidFinish(success: success) } }
    }

    private func printDidFinish(success: Bool) {
        printing = false
        printKeepAlive = nil
        // A late completion after a timeout or cancel finds no continuation and must not touch the
        // destination; it only clears away whatever the print wrote and the window it printed from.
        guard continuation != nil else {
            if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
            tempURL = nil
            tearDown()
            return
        }
        guard success, let tempURL, let destination, Self.isValidPDF(tempURL) else {
            finish(.failure(PDFExportError.printFailed))
            return
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: destination)
            }
            finish(.success(()))
        } catch {
            finish(.failure(PDFExportError.printFailed))
        }
    }

    private static func isValidPDF(_ url: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return size > 0 && PDFDocument(url: url) != nil
    }

    /// Resumes the caller exactly once, whichever of success, failure or the timeout comes first.
    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutItem?.cancel()
        timeoutItem = nil
        // End a print run a timeout or cancel interrupted, so its sheet doesn't outlive the window —
        // but only if it is this exporter's own modal run, never some other window's.
        if printing, let window, NSApp.modalWindow === window { NSApp.abortModal() }
        webView?.navigationDelegate = nil
        // Whatever happened, the temp file is gone: on success it was already moved to the destination.
        if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
        // A print still running keeps its window and the temp name until it reports back
        // (`printDidFinish`), so it never prints from a freed view and its late file is deleted.
        if !printing {
            tempURL = nil
            tearDown()
        }
        continuation.resume(with: result)
    }

    private func tearDown() {
        webView?.navigationDelegate = nil
        webView = nil
        window?.orderOut(nil)
        window = nil
    }

    /// Whether an export has started and not finished yet (for tests that cancel mid-way).
    var isInFlight: Bool { continuation != nil }
    /// Whether the print operation has been started and hasn't reported back.
    var isPrinting: Bool { printing }
}
