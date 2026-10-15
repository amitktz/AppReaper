import SwiftUI

@MainActor
final class AppListViewModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var search = ""
    @Published var selection: InstalledApp.ID?
    @Published var isLoading = false
    @Published var leftovers: [LeftoverItem] = []
    @Published var selectedLeftovers: Set<URL> = []
    @Published var isScanning = false
    @Published var message: String?

    var filtered: [InstalledApp] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q) }
    }

    var selectedApp: InstalledApp? { apps.first { $0.id == selection } }

    func load() async {
        isLoading = true
        let found = await Task.detached { AppDiscoveryService().discover() }.value
        apps = found
        isLoading = false
    }

    func scanLeftovers() async {
        guard let app = selectedApp else { leftovers = []; return }
        isScanning = true
        let others = Set(apps.map(\.id))
        let items = await Task.detached { LeftoverFinder().find(for: app, otherBundleIDs: others) }.value
        guard selection == app.id else { return }
        leftovers = items
        // Only pre-check items whose confidence tier calls for it — name-only
        // matches start unchecked so the user reviews them before anything is trashed.
        selectedLeftovers = Set(items.filter(\.confidence.isSelectedByDefault).map(\.url))
        isScanning = false
    }

    var chosenLeftovers: [LeftoverItem] { leftovers.filter { selectedLeftovers.contains($0.url) } }
}
