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
// palette — the source tag under each reply — so it reuses the same
// meanings Selene already established: moon-white for her own (home/LAN,
// see seleneMoonWhite below), lilac for local, orange for cloud. Teal
// stays as the app's general accent/tint (nav bar, buttons) and, per
// Fia's own request, the user's own sent-message bubbles — no longer
// tied to a specific "home" meaning the way it is in Selene's own CSS.
extension Color {
    /// --ink — page/app background.
    static let seleneInk = Color(red: 0x02 / 255, green: 0x04 / 255, blue: 0x0A / 255)
    /// --cyan-bright — the wireframe shell's own resting color; Selene's
    /// signature teal. General app accent/tint here, and (2026-09-02,
    /// Fia's request) the user's own sent-message bubble color — see
    /// seleneMoonWhite below for the color that now carries the
    /// "home/Selene" meaning this used to.
    static let seleneTeal = Color(red: 0x4F / 255, green: 0xC6 / 255, blue: 0xBD / 255)
    /// --full-moon-white (2026-09-02, Fia's request: "more silver or
    /// white... references the fact that I'm talking to the moon when
    /// I'm home"). Not a made-up silver — this is literally the color
    /// sphere.js's wireframe shell (and styles.css's --cyan-bright,
    /// Pandia's own seleneTeal above) swaps to during an actual full
    /// moon (styles.css's `body.full-moon{ --cyan-bright:var(--full-moon-
    /// white); }`), pulled from Selene's real source the same way every
    /// other color in this file was. Used for anything meaning
    /// "connected to Selene / home" — the role seleneTeal used to play.
    static let seleneMoonWhite = Color(red: 0xF3 / 255, green: 0xEF / 255, blue: 0xE4 / 255)
    /// --gold — muted, not a bright yellow. The moon's color, previously
    /// also the user's own chat bubble accent (now teal — see above).
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
    static var seleneMoonWhite: Color { .seleneMoonWhite }
    static var seleneGold: Color { .seleneGold }
    static var seleneLilac: Color { .seleneLilac }
    static var seleneOrange: Color { .seleneOrange }
    static var seleneDangerRed: Color { .seleneDangerRed }
}
