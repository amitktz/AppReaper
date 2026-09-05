import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash.circle")
                .font(.system(size: 48))
            Text("AppReaper")
                .font(.title)
            Text("Scaffold — feature views land in later commits.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 480, height: 320)
    }
}

#Preview {
    ContentView()
}
