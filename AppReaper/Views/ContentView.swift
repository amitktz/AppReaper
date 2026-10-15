import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppListViewModel()

    var body: some View {
        NavigationSplitView {
            List(model.filtered, selection: $model.selection) { app in
                AppRow(app: app).tag(app.id)
            }
            .searchable(text: $model.search, prompt: "Search apps")
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            .overlay { if model.isLoading { ProgressView() } }
        } detail: {
            if let app = model.selectedApp {
                AppDetailView(app: app, model: model)
                    .id(app.id)
            } else {
                Text("Select an app to uninstall").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .task { await model.load() }
        .onChange(of: model.selection) { _ in Task { await model.scanLeftovers() } }
    }
}

struct AppRow: View {
    let app: InstalledApp
    var body: some View {
        HStack {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                .resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading) {
                Text(app.name)
                Text(app.source.label + (app.version.isEmpty ? "" : " · \(app.version)"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct AppDetailView: View {
    let app: InstalledApp
    @ObservedObject var model: AppListViewModel
    @State private var confirm = false
    @State private var showDryRun = false
    @State private var report: String?
    @State private var askQuit = false
    private let uninstaller = Uninstaller()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path)).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading) {
                    Text(app.name).font(.title2)
                    Text(app.id).font(.caption).foregroundStyle(.secondary)
                    if let t = app.teamIdentifier { Text("Team \(t)").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if !app.isRemovable {
                Label("This is a protected system or Apple app and cannot be removed.", systemImage: "lock.fill")
                    .foregroundStyle(.orange)
            }
            List {
                Section("Application") {
                    Label(app.bundleURL.path, systemImage: "app")
                }
                Section("Related files (\(ByteFormat.string(model.chosenLeftovers.reduce(0) { $0 + $1.size })))") {
                    if model.isScanning { ProgressView() }
                    ForEach(model.leftovers) { item in
                        Toggle(isOn: Binding(
                            get: { model.selectedLeftovers.contains(item.url) },
                            set: { on in if on { model.selectedLeftovers.insert(item.url) } else { model.selectedLeftovers.remove(item.url) } }
                        )) {
                            HStack {
                                if item.confidence != .exact {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .help(item.confidence == .possible
                                              ? "Matched by app name only, not a bundle ID — review before deleting."
                                              : "Shared Group Container — other apps on the same team ID may use this too.")
                                }
                                VStack(alignment: .leading) {
                                    Text(item.url.lastPathComponent)
                                    Text("\(item.category.rawValue) · \(item.reason)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(ByteFormat.string(item.size)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !model.isScanning && model.leftovers.isEmpty { Text("No related files found").foregroundStyle(.secondary) }
                }
            }
            HStack {
                Button("Preview (Dry Run)") { showDryRun = true }
                Spacer()
                Button("Move to Trash…", role: .destructive) { confirm = true }
                    .disabled(!app.isRemovable)
            }
        }
        .padding()
        .sheet(isPresented: $showDryRun) { dryRunSheet }
        .confirmationDialog("Move \(app.name) and \(model.chosenLeftovers.count) related items to the Trash?",
                            isPresented: $confirm, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { start() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Items can be restored from the Trash.") }
        .alert("\(app.name) is running", isPresented: $askQuit) {
            Button("Quit and Continue") { Task { if await uninstaller.quit(app) { perform() } else { report = "\(app.name) did not quit. Quit it manually and try again." } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("It must be quit before it can be removed.") }
        .alert("Result", isPresented: Binding(get: { report != nil }, set: { if !$0 { report = nil } })) {
            Button("OK") {}
        } message: { Text(report ?? "") }
    }

    private var dryRunSheet: some View {
        let plan = try? uninstaller.makePlan(app: app, leftovers: model.chosenLeftovers)
        return VStack(alignment: .leading) {
            Text("Dry run: nothing will be changed").font(.headline)
            if let plan {
                Text("\(plan.allURLs.count) items, \(ByteFormat.string(plan.totalSize))")
                List(uninstaller.dryRun(plan), id: \.self) { Text($0).font(.caption) }
            } else { Text("This app is protected.") }
            Button("Close") { showDryRun = false }
        }.padding().frame(width: 560, height: 400)
    }

    private func start() {
        if !uninstaller.runningInstances(of: app).isEmpty { askQuit = true } else { perform() }
    }

    private func perform() {
        guard let plan = try? uninstaller.makePlan(app: app, leftovers: model.chosenLeftovers) else { return }
        let r = uninstaller.execute(plan)
        var text = "Moved \(r.trashed.count) items to the Trash."
        if !r.failures.isEmpty {
            text += "\n\nFailed (\(r.failures.count)):"
            for f in r.failures { text += "\n• \(f.url.lastPathComponent): \(f.message)" + (f.needsAdmin ? " (needs administrator rights; remove manually in Finder)" : "") }
        }
        report = text
        Task { await model.load() }
    }
}
