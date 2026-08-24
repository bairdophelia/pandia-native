import SwiftUI

// First-pass placeholder. The point of this exact screen is to prove the
// whole pipeline end to end — GitHub Actions builds it, AltStore signs and
// installs it, this text shows up on the phone — before any of Pandia's
// real behavior (LAN chat to Selene, cloud fallback, the on-device model)
// gets layered in on top of a working baseline. See ../README.md's
// "Status" section for what comes next once this is confirmed working.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 44))
                .foregroundStyle(.yellow)
            Text("Pandia")
                .font(.title)
                .bold()
            Text("Native build pipeline — online.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
