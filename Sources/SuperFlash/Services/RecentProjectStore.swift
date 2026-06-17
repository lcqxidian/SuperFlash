import Foundation

final class RecentProjectStore: ObservableObject {
    @Published var recentProjects: [ProjectInfo] = []

    private let defaultsKey = "com.superflash.recent"
    private let maxItems = 10

    init() {
        load()
    }

    func add(_ project: ProjectInfo) {
        recentProjects.removeAll { $0.rootURL == project.rootURL }
        recentProjects.insert(project, at: 0)
        if recentProjects.count > maxItems {
            recentProjects = Array(recentProjects.prefix(maxItems))
        }
        save()
    }

    func remove(_ project: ProjectInfo) {
        recentProjects.removeAll { $0.id == project.id }
        save()
    }

    func clear() {
        recentProjects = []
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(recentProjects) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let projects = try? JSONDecoder().decode([ProjectInfo].self, from: data) else { return }
        recentProjects = projects
    }
}
