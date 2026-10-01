import Foundation
import os

/// Moves what the built-in features kept before plugins had storage of their own (0.18):
/// to-dos in todos.json at the top of the app's folder, and the timers and the Done-tab
/// watermark in UserDefaults. Each goes into its plugin's folder, in the JSON the plugin
/// storage writes, and the original goes into a backup folder, so nothing is left behind to
/// be read as stale — an older CLI finds no to-dos rather than outdated ones.
///
/// A step whose destination already exists is skipped, which makes running this at every
/// launch harmless. A step that fails leaves its original where it was and is logged.
enum StorageMigration {
    private static let log = Logger(subsystem: "com.snghnl.deskbuddy", category: "storage")

    /// `appFolder` is Application Support/DeskBuddy; plugin data goes under its plugins/ folder
    static func run(appFolder: URL, defaults: UserDefaults, now: Date = Date()) {
        let plugins = appFolder.appendingPathComponent("plugins", isDirectory: true)
        let backup = Backup(folder: appFolder.appendingPathComponent("backups", isDirectory: true)
            .appendingPathComponent("\(stamp(now))-before-plugin-storage", isDirectory: true))

        migrate("to-dos") {
            let destination = plugins.appendingPathComponent("todo/todos.json")
            guard !exists(destination) else { return }
            let current = appFolder.appendingPathComponent("todos.json")
            // Data from before the DeskBuddy name, which earlier versions copied over the same way
            let floating = appFolder.deletingLastPathComponent().appendingPathComponent("FloatingTodo/todos.json")
            if exists(current) {
                try copy(current, to: destination)
                try backup.move(current)
            } else if exists(floating) {
                try copy(floating, to: destination)
            }
        }

        migrate("timers") {
            let key = "DeskBuddy.timers"
            let destination = plugins.appendingPathComponent("pomodoro/timers.json")
            // Already the JSON the timers encode to
            guard !exists(destination), let data = defaults.data(forKey: key) else { return }
            try write(data, to: destination)
            try backup.write(data, named: "timers.json")
            defaults.removeObject(forKey: key)
        }

        migrate("Done-tab watermark") {
            let key = "DeskBuddy.historyClearedAt"
            let destination = plugins.appendingPathComponent("todo/historyClearedAt.json")
            guard !exists(destination), let seconds = defaults.object(forKey: key) as? Double else { return }
            let data = try JSONEncoder().encode(Date(timeIntervalSinceReferenceDate: seconds))
            try write(data, to: destination)
            try backup.write(data, named: "historyClearedAt.json")
            defaults.removeObject(forKey: key)
        }
    }

    private static func migrate(_ what: String, _ step: () throws -> Void) {
        do {
            try step()
        } catch {
            log.error("Could not move \(what, privacy: .public) to plugin storage: \(String(describing: error), privacy: .public)")
        }
    }

    /// Where the originals go, created only once there is something to keep
    private struct Backup {
        let folder: URL

        func move(_ file: URL) throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
        }

        func write(_ data: Data, named name: String) throws {
            try StorageMigration.write(data, to: folder.appendingPathComponent(name))
        }
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private static func copy(_ source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private static func write(_ data: Data, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }

    /// 20261002-153000, sortable and safe in a file name
    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }
}
