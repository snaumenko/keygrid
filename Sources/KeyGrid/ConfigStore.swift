import Foundation
import os
import KeyGridCore

/// Owns the config file on disk: creates it with defaults on first launch,
/// reads it into a `Config`, watches it for edits, and keeps the last good
/// `Config` when a new edit is broken.
///
/// The file lives at `$XDG_CONFIG_HOME/keygrid/config.json`, or
/// `~/.config/keygrid/config.json` when that variable is unset or empty.
/// It is the only place the program keeps settings.
///
/// Reading happens in two steps: Foundation's `JSONDecoder` turns the text
/// into a `ConfigFile` (a plain copy of the JSON), then
/// `Config(validating:)` fills defaults and checks the rules. Every kind of
/// failure (cannot create the file, bad JSON, bad values, cannot watch)
/// ends up in `lastError` as one line of text, and `current` stays what it
/// was. `docs/ARCHITECTURE.md`, "How a setting travels", tells the whole
/// path.
///
/// Watching uses two `DispatchSource`s, because editors save in two ways.
/// Some write a new file and rename it over the old one; only a watch on
/// the directory sees that, since a watch on the old file's descriptor
/// would keep following the unlinked old file. Others write into the
/// existing file in place; only a watch on the file itself sees that, since
/// a directory does not report changes inside its entries. The file watch
/// is reopened after every load so it always follows the current file.
/// Events are debounced for 200 ms so one save produces one reload.
final class ConfigStore {
    /// `$XDG_CONFIG_HOME/keygrid`, or `~/.config/keygrid`.
    static let directory: URL = {
        let base: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config", isDirectory: true)
        }
        return base.appendingPathComponent("keygrid", isDirectory: true)
    }()

    /// `…/keygrid/config.json`: the only file the program reads or writes.
    static let file = directory.appendingPathComponent("config.json", isDirectory: false)

    /// The settings in force. Starts as `Config.default` and changes only
    /// when a load succeeds.
    private(set) var current: Config = .default

    /// What is wrong right now, as one line for a person, or nil when the
    /// most recent load succeeded and watching works. Covers a file that
    /// could not be created, could not be read, did not parse, failed
    /// validation, or cannot be watched.
    private(set) var lastError: String?

    /// Called after a load that produced a different `Config` than before.
    /// Runs on the thread `reload()` ran on; the watcher reloads on the main
    /// thread, and `AppController` creates the store there too.
    var onChange: ((Config) -> Void)?

    /// Called after every load and after `startWatching`, with the new
    /// value of `lastError`: a message when something is wrong, nil when an
    /// earlier problem has cleared. Fires even when `current` did not
    /// change, so a listener showing an error learns when the user fixed
    /// the file. Same thread rule as `onChange`.
    var onStatus: ((String?) -> Void)?

    private static let log = Logger(subsystem: "com.keygrid.app", category: "config")
    /// Why the directory cannot be watched, or nil when it is (or watching
    /// has not been asked for yet). Kept apart from load errors because a
    /// later good load does not fix it: edits stay unseen until restart, so
    /// `reload` reports this instead of clearing `lastError`.
    private var watchError: String?
    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var pendingReload: DispatchWorkItem?

    /// Makes sure the directory and file exist, writing the default file
    /// when there is none, then loads it. If the file cannot be created,
    /// that is the error kept, not the "no such file" a load would give.
    init() {
        do {
            try createDefaultFileIfMissing()
        } catch {
            report("could not create \(Self.file.path): \(error.localizedDescription)")
            return
        }
        reload()
    }

    deinit {
        directoryWatcher?.cancel()
        fileWatcher?.cancel()
    }

    /// Reads and validates the file. On success, clears `lastError` (back
    /// to the watch error, if watching failed, since a good load does not
    /// fix that), and if the result differs from `current`, stores it and
    /// calls `onChange`.
    /// On failure, leaves `current` alone and sets `lastError`. Either way
    /// `onStatus` is called with the new `lastError`.
    func reload() {
        defer { if directoryWatcher != nil { watchFile() } }
        do {
            let data = try Data(contentsOf: Self.file)
            let file = try JSONDecoder().decode(ConfigFile.self, from: data)
            let config = try Config(validating: file)
            lastError = watchError
            Self.log.info("\(Self.file.path, privacy: .public) loaded")
            if config != current {
                current = config
                onChange?(config)
            }
            onStatus?(watchError)
        } catch {
            report("\(Self.file.path): \(Self.describe(error))")
        }
    }

    /// Starts reloading on edits. Calling it again does nothing. If the
    /// directory cannot be opened for watching, `lastError` says that edits
    /// will not be picked up until restart; the loaded config stays valid.
    func startWatching() {
        guard directoryWatcher == nil else { return }
        let fd = open(Self.directory.path, O_EVTONLY)
        guard fd >= 0 else {
            let reason = String(cString: strerror(errno))
            watchError = "cannot watch \(Self.directory.path) (\(reason)); edits are not picked up until restart"
            report(watchError!)
            return
        }
        directoryWatcher = makeWatcher(fd: fd, events: [.write, .rename, .delete])
        watchFile()
    }

    /// Opens (or reopens) the watch on the file itself. Called after every
    /// load so the watch follows a file that was replaced by rename.
    private func watchFile() {
        fileWatcher?.cancel()
        fileWatcher = nil
        let fd = open(Self.file.path, O_EVTONLY)
        guard fd >= 0 else { return }   // no file right now; the directory watch sees it appear
        fileWatcher = makeWatcher(fd: fd, events: [.write, .extend, .rename, .delete])
    }

    /// A resumed `DispatchSource` on `fd` that schedules a debounced reload
    /// and closes `fd` when cancelled.
    private func makeWatcher(fd: Int32, events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject {
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleReload() }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    /// Coalesces a burst of file-system events into one `reload()` 200 ms
    /// after the last one.
    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200), execute: work)
    }

    /// Writes `Config.defaultJSON` to the file if the file does not exist,
    /// creating the directory first. Never overwrites an existing file.
    private func createDefaultFileIfMissing() throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: Self.file.path) else { return }
        try fm.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try Config.defaultJSON.write(to: Self.file, atomically: true, encoding: .utf8)
        Self.log.info("wrote default config to \(Self.file.path, privacy: .public)")
    }

    /// Records `message` as `lastError`, logs it, and tells the listener.
    private func report(_ message: String) {
        lastError = message
        Self.log.error("\(message, privacy: .public)")
        onStatus?(message)
    }

    /// One line of text for any error a load can produce. `DecodingError`
    /// gets its own wording because its default description is unreadable,
    /// and for malformed JSON the line and column live in the underlying
    /// error, which the default description drops.
    private static func describe(_ error: Error) -> String {
        switch error {
        case let error as ConfigError:
            return error.description
        case let DecodingError.keyNotFound(key, context):
            let path = (context.codingPath.map(\.stringValue) + [key.stringValue]).joined(separator: ".")
            return "\(path): \(context.debugDescription)"
        case let DecodingError.typeMismatch(_, context),
             let DecodingError.valueNotFound(_, context),
             let DecodingError.dataCorrupted(context):
            var text = context.debugDescription
            // For malformed JSON the line and column are in the underlying
            // NSError's debug description, not in its localized one.
            if let underlying = context.underlyingError as NSError?,
               let detail = underlying.userInfo[NSDebugDescriptionErrorKey] as? String {
                text += " (\(detail))"
            }
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? text : "\(path): \(text)"
        default:
            return error.localizedDescription
        }
    }
}
