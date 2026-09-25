import Foundation
import AppKit

struct GitHubRelease: Decodable {
    let tag_name: String
    let name: String?
    let body: String?
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
    }
}

// Checks GitHub releases for a newer version and replaces the running
// app bundle in place (unsigned builds, so no Sparkle).
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case downloading
        case installing
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var latestNotes: String = ""

    private let repo = "Malti2/Beam"

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var availableVersion: String? {
        if case .available(let version) = state { return version }
        return nil
    }

    func checkForUpdates(automatic: Bool = false) {
        if case .downloading = state { return }
        if case .installing = state { return }
        state = .checking
        Task {
            do {
                let release = try await fetchLatestRelease()
                let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                if isNewer(latest, than: currentVersion) {
                    latestNotes = release.body ?? ""
                    state = .available(latest)
                } else {
                    state = .upToDate
                }
            } catch {
                state = automatic ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    func downloadAndInstall() {
        guard case .available = state else { return }
        state = .downloading
        Task {
            do {
                try await performInstall()
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Beam-Updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw updaterError("GitHub returned HTTP \(http.statusCode).")
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func performInstall() async throws {
        let release = try await fetchLatestRelease()
        guard let asset = release.assets.first(where: { $0.name == "Beam.zip" }),
              let url = URL(string: asset.browser_download_url) else {
            throw updaterError("The latest release has no Beam.zip asset.")
        }
        let (downloaded, _) = try await URLSession.shared.download(from: url)
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeamUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let zipPath = workDirectory.appendingPathComponent("Beam.zip")
        try FileManager.default.moveItem(at: downloaded, to: zipPath)
        try await runProcess("/usr/bin/ditto", ["-x", "-k", zipPath.path, workDirectory.path])
        let newApp = workDirectory.appendingPathComponent("Beam.app")
        guard FileManager.default.fileExists(atPath: newApp.path) else {
            throw updaterError("The downloaded archive did not contain Beam.app.")
        }

        let currentApp = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier
        // Helper: wait for this process to exit, swap the bundle, relaunch.
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        sleep 0.5
        rm -rf '\(currentApp)'
        mv '\(newApp.path)' '\(currentApp)'
        /usr/bin/xattr -dr com.apple.quarantine '\(currentApp)' 2>/dev/null
        open '\(currentApp)'
        rm -rf '\(workDirectory.path)'
        """
        state = .installing
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/bash")
        helper.arguments = ["-c", script]
        try helper.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let newParts = candidate.split(separator: ".").compactMap { Int($0) }
        let oldParts = current.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(newParts.count, oldParts.count) {
            let new = index < newParts.count ? newParts[index] : 0
            let old = index < oldParts.count ? oldParts[index] : 0
            if new != old { return new > old }
        }
        return false
    }

    private func runProcess(_ launchPath: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: self.updaterError("\(launchPath) failed with code \(finished.terminationStatus)."))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func updaterError(_ message: String) -> NSError {
        NSError(domain: "BeamUpdater", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
