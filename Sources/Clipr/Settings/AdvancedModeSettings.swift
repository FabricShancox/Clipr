import Foundation

/// Everything Advanced Mode can be configured to do, stored as one value so a session can
/// snapshot it at start — changing Preferences mid-session applies to the next session, never
/// half of the current one.
struct AdvancedModeSettings: Codable, Equatable {
    enum MarkerStyle: String, Codable, CaseIterable { case ring, dot }
    enum Scope: String, Codable, CaseIterable { case window, screen, fixedArea }

    var clickMarker = true
    var markerStyle: MarkerStyle = .ring
    var autoCaptions = true
    var cursorTrail = false
    var zoomOnClick = false
    var typingSteps = false
    var scope: Scope = .window
    var captureDelay: TimeInterval = 0.3
    var stepHotkey: HotkeyBinding?

    static let `default` = AdvancedModeSettings()

    /// Never below 0.2 s: that's the debounce that merges a double-click into one step, so a
    /// 0 s delay would otherwise turn every double-click into two.
    var effectiveDelay: TimeInterval { min(max(captureDelay, 0.2), 2) }

    init() {}

    /// Hand-written so a key added in a later version — or missing from an older stored value —
    /// falls back to its default instead of failing the whole decode and resetting every setting.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AdvancedModeSettings.default
        clickMarker = try c.decodeIfPresent(Bool.self, forKey: .clickMarker) ?? d.clickMarker
        markerStyle = try c.decodeIfPresent(MarkerStyle.self, forKey: .markerStyle) ?? d.markerStyle
        autoCaptions = try c.decodeIfPresent(Bool.self, forKey: .autoCaptions) ?? d.autoCaptions
        cursorTrail = try c.decodeIfPresent(Bool.self, forKey: .cursorTrail) ?? d.cursorTrail
        zoomOnClick = try c.decodeIfPresent(Bool.self, forKey: .zoomOnClick) ?? d.zoomOnClick
        typingSteps = try c.decodeIfPresent(Bool.self, forKey: .typingSteps) ?? d.typingSteps
        scope = try c.decodeIfPresent(Scope.self, forKey: .scope) ?? d.scope
        captureDelay = try c.decodeIfPresent(TimeInterval.self, forKey: .captureDelay) ?? d.captureDelay
        stepHotkey = try c.decodeIfPresent(HotkeyBinding.self, forKey: .stepHotkey)
    }
}
