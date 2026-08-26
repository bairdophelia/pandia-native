import SwiftUI

// Pandia's colors, pulled directly from Selene's own stylesheet
// (../../selene/static/v2/styles.css :root block) and her 3D scene
// (../../selene/static/v2/js/sphere.js) rather than picked to "look
// similar" from memory — same family as the app icon (Assets.xcassets/
// AppIcon.appiconset, generate_icon.py), so the phone and the PC match on
// sight, not just in spirit.
//
// The color *meanings* carry over too, not just the hex values — Selene's
// CSS explicitly keeps a state palette where "the same color always means
// the same thing everywhere on screen" (LINK source, weather CONDITION,
// load bars all share it). Pandia only has one place that needs a state
// palette — the source tag under each reply — so it reuses the same two
// meanings Selene already established: teal for her own (home/LAN),
// lilac for local, orange for cloud.
extension Color {
    /// --ink — page/app background.
    static let seleneInk = Color(red: 0x02 / 255, green: 0x04 / 255, blue: 0x0A / 255)
    /// --cyan-bright — the wireframe shell's own resting color; Selene's
    /// signature teal. Used here for anything meaning "connected to
    /// Selene / home," matching sphere.js's SHELL_TEAL.
    static let seleneTeal = Color(red: 0x4F / 255, green: 0xC6 / 255, blue: 0xBD / 255)
    /// --gold — muted, not a bright yellow. The moon's color, and the
    /// user's own chat bubble (a small "this is you" accent).
    static let seleneGold = Color(red: 0xD9 / 255, green: 0xB7 / 255, blue: 0x68 / 255)
    /// --lilac — sphere.js's WALKER_COLOR, used there for local
    /// processing. Reused here for the exact same meaning: Pandia's own
    /// on-device model (LocalBrain.swift's "device" source).
    static let seleneLilac = Color(red: 0xC9 / 255, green: 0xA8 / 255, blue: 0xF5 / 255)
    /// --warn-orange — Selene's own color for "cloud brain source." Reused
    /// here for Pandia's cloud fallback, same meaning.
    static let seleneOrange = Color(red: 0xE0 / 255, green: 0x92 / 255, blue: 0x3C / 255)
    /// --danger-red — reused here only for "couldn't reach anything."
    static let seleneDangerRed = Color(red: 0xE0 / 255, green: 0x5A / 255, blue: 0x44 / 255)
}

// SwiftUI's own colors (.red, .teal, etc.) are reachable as bare
// `.foregroundStyle(.teal)` shorthand because Apple declares them twice:
// once as `Color` statics (for `Color`-typed contexts like `.background`),
// and again as `ShapeStyle` statics constrained to `Self == Color` (for
// generic-ShapeStyle contexts like `.foregroundStyle`/`.tint`). The Color
// extension above only covers the first — CI caught the gap
// (2026-08-26): `.foregroundStyle(.seleneTeal)` failed to compile with
// "type 'ShapeStyle' has no member 'seleneTeal'", since `.foregroundStyle`
// infers its type from a *generic* ShapeStyle, not from Color directly.
// This mirrors Apple's own second declaration to close that gap.
extension ShapeStyle where Self == Color {
    static var seleneInk: Color { .seleneInk }
    static var seleneTeal: Color { .seleneTeal }
    static var seleneGold: Color { .seleneGold }
    static var seleneLilac: Color { .seleneLilac }
    static var seleneOrange: Color { .seleneOrange }
    static var seleneDangerRed: Color { .seleneDangerRed }
}
