import Cocoa

/// Checks GitHub for a newer Clipr release. Clipr isn't notarized and has no self-updater, so an
/// update is announced rather than installed: the alert points at `brew upgrade` or the release page.
final class UpdateChecker {
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/FabricShancox/Clipr/releases/latest")!
    private static let lastCheckKey = "lastUpdateCheck"
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    /// `brew update` first: Homebrew only refreshes taps about once a day on its own, so a bare
    /// `brew upgrade` soon after a release still sees the old version and reports it's up to date.
    private static let upgradeCommand = "brew update && brew upgrade --cask clipr"

    private struct Release: Decodable {
        let tagName: String
        /// Optional so a malformed value doesn't fail the whole check; it's never opened as-is
        /// anyway — see `releasePage(for:)`.
        let htmlURL: URL?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var currentVersion: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }

    /// The releases page opened when the API's own link isn't one we trust.
    static let releasesPage = URL(string: "https://github.com/FabricShancox/Clipr/releases")!

    /// The page "Open Release Page" opens for the API's `html_url`.
    ///
    /// The link comes from the network, so it is only opened when it is plainly this repository's
    /// releases page on github.com over https — anything else (a `file://` URL, a custom scheme
    /// that launches another app, a look-alike host, credentials or `..` in the path) is replaced
    /// by the fixed releases page. Otherwise a compromised account, API response or intercepted
    /// connection could make Clipr open anything at all.
    static func releasePage(for url: URL?) -> URL {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "github.com",
              components.user == nil, components.password == nil, components.port == nil
        else { return releasesPage }
        let path = components.path
        let prefix = "/FabricShancox/Clipr/releases"
        guard path == prefix || path.hasPrefix(prefix + "/"),
              !path.split(separator: "/").contains(where: { $0 == ".." || $0 == "." })
        else { return releasesPage }
        return url
    }

    /// Whether the once-a-day launch check may run. On unless the user turned it off in
    /// Preferences (`SettingsStore.checkForUpdatesAutomatically`).
    var isAutomaticCheckEnabled: Bool {
        defaults.object(forKey: SettingsStore.checkForUpdatesAutomaticallyKey) as? Bool ?? true
    }

    /// The launch-time check: at most once a day, and silent unless there's something to install.
    /// Skipped entirely when automatic checks are off; "Check for Updates…" still works.
    func checkInBackgroundIfDue() {
        guard isAutomaticCheckEnabled else { return }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < Self.checkInterval { return }
        check(userInitiated: false)
    }

    /// "Check for Updates…": always reports back, including "up to date" and failures.
    func checkNow() {
        check(userInitiated: true)
    }

    private func check(userInitiated: Bool) {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let result: Result<Release, Error>
            if let error {
                result = .failure(error)
            } else if let data, (response as? HTTPURLResponse)?.statusCode == 200 {
                result = Result { try JSONDecoder().decode(Release.self, from: data) }
            } else {
                result = .failure(URLError(.badServerResponse))
            }
            DispatchQueue.main.async { self?.handle(result, userInitiated: userInitiated) }
        }.resume()
    }

    private func handle(_ result: Result<Release, Error>, userInitiated: Bool) {
        switch result {
        case .failure(let error):
            // A background check failing (offline, rate-limited) isn't worth interrupting anyone
            // for, and isn't recorded, so the next launch tries again.
            NSLog("Clipr: update check failed: \(error)")
            guard userInitiated else { return }
            showAlert(title: "Couldn't check for updates", text: error.localizedDescription)
        case .success(let release):
            defaults.set(Date(), forKey: Self.lastCheckKey)
            guard let latest = AppVersion(release.tagName), let current = currentVersion, current < latest else {
                if userInitiated {
                    showAlert(title: "Clipr is up to date", text: "You're running the latest version.")
                }
                return
            }
            showUpdateAvailable(release)
        }
    }

    private func showUpdateAvailable(_ release: Release) {
        let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        let detail = """
            If you installed Clipr with Homebrew, update it by running:

            \(Self.upgradeCommand)

            Otherwise, download the new version from the release page.
            """
        switch Alerts.run("Clipr \(version) is available", detail,
                          buttons: ["Copy Command", "Open Release Page", "Later"], activate: true) {
        case .alertFirstButtonReturn:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Self.upgradeCommand, forType: .string)
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(Self.releasePage(for: release.htmlURL))
        default:
            break
        }
    }

    private func showAlert(title: String, text: String) {
        Alerts.run(title, text, activate: true)
    }
}
