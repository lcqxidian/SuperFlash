import Foundation

final class RecentProjectStore: ObservableObject {
    @Published var recentProjects: [ProjectInfo] = []

    private let defaultsKey = "com.superflash.recent"
    private let maxItems = 10

    init() {
        load()
    }

    func add(_ project: ProjectInfo) {
        // 已存在时不调整顺序，仅更新显示名等信息
        if let index = recentProjects.firstIndex(where: { $0.rootURL == project.rootURL }) {
            recentProjects[index] = project
        } else {
            recentProjects.insert(project, at: 0)
            if recentProjects.count > maxItems {
                recentProjects = Array(recentProjects.prefix(maxItems))
            }
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
