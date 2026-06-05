import SwiftUI
import AppKit
import Foundation
import Darwin
import StokerCore

// MARK: - Claude binary locator
//
// A launched .app inherits only the stripped agent PATH, so replicate the engine's PATH list
// (activate-ai-window.sh ~:27) to find `claude` and to hand the child a usable PATH for its
// own `open` (browser) call.
enum ClaudeLocator {
    static let searchPaths = [
        "\(NSHomeDirectory())/.local/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin"
    ]

    static func find() -> URL? {
        let fm = FileManager.default
        for dir in searchPaths {
            let path = "\(dir)/claude"
            if fm.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    static func augmentedPATH() -> String {
        let extra = searchPaths.joined(separator: ":")
        let current = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        return "\(extra):\(current)"
    }
}

// MARK: - Setup-token runner (PTY-backed)
//
// `claude setup-token` is an Ink/TTY interactive command: with a plain pipe it renders nothing,
// never opens the browser, and blocks on absent terminal input. So we run it attached to a
// PSEUDO-TERMINAL — it sees a real TTY (opens the browser, prints the token) but no visible
// terminal window is needed. We read the PTY master, capture the one-year `sk-ant-oat01-…`
// token, and hand it back via `onToken`.
//
// Truncation safety (a wrong token must never overwrite the user's working one) — see `extractToken`:
//  - The PTY is opened very wide (1000 cols) so the ~108-char token never wraps.
//  - Extraction runs on an ESCAPE-STRIPPED copy that removes ESC (CSI/OSC) and stray C0 controls
//    but KEEPS \r and \n, so an in-band cursor move that split the token mid-run is reassembled
//    rather than truncated.
//  - The stream is split into frames on \r and \n, so a stale redraw frame can't fuse with or
//    masquerade as the final token; only COMPLETE frames are scanned (the still-being-written
//    trailing one is held until EOF) and the LAST qualifying match wins.
//  - A realistic minimum length (80, against a measured 108) plus the prefix check in
//    `saveOAuthToken` reject any fragment.
//  - Any failure falls through to the always-available manual Terminal+paste path.
@MainActor
final class SetupTokenRunner: ObservableObject {
    enum Phase: Equatable { case idle, running, captured, failed }

    @Published var phase: Phase = .idle
    @Published var consoleText: String = ""
    @Published var loginURL: String?
    @Published var errorMessage: String?

    /// Invoked on the main actor when a token is captured; returns true if accepted (valid + saved).
    var onToken: ((String) -> Bool)?

    // Held nonisolated so `deinit` can tear down a still-running child if the sheet is dropped
    // without routing through cancel(); all other access is main-actor-only and deinit runs only
    // after the last reference is gone, so there is no concurrent access.
    nonisolated(unsafe) private var process: Process?
    nonisolated(unsafe) private var masterFD: Int32 = -1
    private var masterHandle: FileHandle?
    private var timeoutTask: Task<Void, Never>?
    private var rawBuffer = ""
    private var captured = false

    // Real setup tokens are ~108 chars; require a high floor so a truncated capture can't be written.
    private static let minTokenLength = 80
    private static let tokenPattern = try! NSRegularExpression(pattern: "sk-ant-oat01-[A-Za-z0-9_-]+")
    private static let urlPattern = try! NSRegularExpression(pattern: "https?://[^\\s'\"\\u001B]+")
    // For EXTRACTION: strip ESC (CSI/OSC) and stray C0 controls, but KEEP \r and \n so redraw
    // frames stay on separate lines — a partial earlier frame must never fuse with the final one.
    private static let extractEscapePattern = try! NSRegularExpression(
        pattern: "\\u001B\\[[0-9;?]*[ -/]*[@-~]|\\u001B\\][^\\u0007]*\\u0007|[\\u0000-\\u0009\\u000B\\u000C\\u000E-\\u001F\\u007F]"
    )
    // For DISPLAY: also drop \r so the console reads cleanly.
    private static let displayEscapePattern = try! NSRegularExpression(
        pattern: "\\u001B\\[[0-9;?]*[ -/]*[@-~]|\\u001B\\][^\\u0007]*\\u0007|[\\u0000-\\u0009\\u000B-\\u001F\\u007F]"
    )

    deinit {
        process?.terminate()
        if masterFD >= 0 { close(masterFD) }
    }

    func start() {
        guard phase != .running else { return }
        guard let claude = ClaudeLocator.find() else {
            phase = .failed
            errorMessage = L10n.authClaudeNotFound
            return
        }

        captured = false
        rawBuffer = ""
        consoleText = ""
        loginURL = nil
        errorMessage = nil
        phase = .running

        // Open a wide PTY so the long token never wraps.
        var master: Int32 = 0
        var slave: Int32 = 0
        var ws = winsize(ws_row: 100, ws_col: 1000, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &ws) == 0 else {
            phase = .failed
            errorMessage = L10n.authPtyFailed
            return
        }

        let process = Process()
        process.executableURL = claude
        process.arguments = ["setup-token"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ClaudeLocator.augmentedPATH()
        env["TERM"] = "xterm-256color"
        process.environment = env
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        do {
            try process.run()
        } catch {
            close(master)
            close(slave)
            phase = .failed
            errorMessage = error.localizedDescription
            return
        }
        // The child now owns its dup of the slave; drop the parent's copy so the master sees EOF
        // when the child exits.
        close(slave)

        self.process = process
        self.masterFD = master
        let handle = FileHandle(fileDescriptor: master, closeOnDealloc: false)
        self.masterHandle = handle
        handle.readabilityHandler = { [weak self] fh in
            // An empty read is the EOF signal (child exited, slave closed). It arrives AFTER every
            // data callback, so the buffer is complete by then — do the final scan there and never
            // block the main actor on a synchronous drain.
            let data = fh.availableData
            if data.isEmpty {
                Task { @MainActor in self?.handleEOF() }
            } else {
                let chunk = String(decoding: data, as: UTF8.self)
                Task { @MainActor in self?.ingest(chunk) }
            }
        }

        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(300))
            self?.handleTimeout()
        }
    }

    func cancel() {
        cleanup()
        phase = .idle
    }

    private func ingest(_ chunk: String) {
        rawBuffer += chunk
        if rawBuffer.count > 16000 { rawBuffer = String(rawBuffer.suffix(16000)) }
        consoleText = Self.stripForDisplay(rawBuffer)
        updateLoginURL(from: consoleText)
        if !captured, let token = extractToken(atEOF: false) {
            captured = true
            finishCaptured(token)
        }
    }

    private func handleEOF() {
        guard phase == .running else { return }
        // EOF means all output has been delivered; the final (possibly newline-less) line is now
        // complete and safe to match. No blocking read on the main actor.
        consoleText = Self.stripForDisplay(rawBuffer)
        if !captured, let token = extractToken(atEOF: true) {
            captured = true
            finishCaptured(token)
            return
        }
        cleanup()
        phase = .failed
        if errorMessage == nil { errorMessage = L10n.authFailed }
    }

    private func handleTimeout() {
        guard phase == .running else { return }
        cleanup()
        phase = .failed
        errorMessage = L10n.authTimedOut
    }

    private func finishCaptured(_ token: String) {
        let accepted = onToken?(token) ?? false
        cleanup()
        phase = accepted ? .captured : .failed
        if !accepted { errorMessage = L10n.authTokenInvalid }
    }

    private func cleanup() {
        timeoutTask?.cancel()
        timeoutTask = nil
        masterHandle?.readabilityHandler = nil
        masterHandle = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        if masterFD >= 0 { close(masterFD); masterFD = -1 }
    }

    private func updateLoginURL(from text: String) {
        let urls = Self.allMatches(Self.urlPattern, in: text)
        guard !urls.isEmpty else { return }
        // Don't latch the first URL — prefer the Anthropic/Claude auth host, else the most recent.
        loginURL = urls.last { $0.contains("anthropic") || $0.contains("claude") } ?? urls.last
    }

    /// Extract the token from the ESCAPE-STRIPPED stream. Stripping ESC/control bytes (while
    /// KEEPING \r and \n) reassembles a token that a repaint split with an in-band cursor move,
    /// while \r/\n keep redraw frames on separate lines so a stale partial can't fuse with the
    /// final token. We scan only COMPLETE lines (the still-being-written trailing line is held back
    /// until EOF), take the LAST qualifying match (latest frame wins), and require a realistic
    /// minimum length. Any shortfall → nil → the caller falls back to the manual path. Together this
    /// makes writing a truncated/garbled token to .env effectively impossible.
    private func extractToken(atEOF: Bool) -> String? {
        let cleaned = Self.stripEscapes(rawBuffer)
        // Split into terminal lines on CR or LF; CR (in-place redraw) bounds a frame.
        var segments = cleaned.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
        // Hold back the trailing segment while it's still being written (no terminator yet) unless
        // the process has exited.
        if !atEOF, let last = cleaned.last, last != "\n", last != "\r", !segments.isEmpty {
            segments.removeLast()
        }
        let tokens = segments
            .compactMap { Self.firstMatch(Self.tokenPattern, in: $0) }
            .filter { $0.count >= Self.minTokenLength }
        return tokens.last
    }

    private static func stripForDisplay(_ string: String) -> String {
        replacing(displayEscapePattern, in: string)
    }

    private static func stripEscapes(_ string: String) -> String {
        replacing(extractEscapePattern, in: string)
    }

    private static func replacing(_ regex: NSRegularExpression, in string: String) -> String {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.stringByReplacingMatches(in: string, range: range, withTemplate: "")
    }

    private static func firstMatch(_ regex: NSRegularExpression, in string: String) -> String? {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              let r = Range(match.range, in: string) else { return nil }
        return String(string[r])
    }

    private static func allMatches(_ regex: NSRegularExpression, in string: String) -> [String] {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.matches(in: string, range: range).compactMap { match in
            Range(match.range, in: string).map { String(string[$0]) }
        }
    }
}

// MARK: - Setup-token sheet

struct SetupTokenSheet: View {
    @ObservedObject var model: StokerAppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.stokerTheme) private var theme
    @StateObject private var runner = SetupTokenRunner()
    @State private var pasteToken = ""
    @State private var showManual = false
    @ObservedObject private var locale = LocaleStore.shared

    var body: some View {
        Group {
            if runner.phase == .captured {
                successView
            } else {
                normalFlow
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(theme.card)
        .onAppear {
            runner.onToken = { token in model.saveOAuthToken(token) }
        }
        .onChange(of: runner.phase) { _, newPhase in
            // Success is NOT auto-dismissed — the user closes it with the Done button so the
            // confirmation can't be missed. Only surface the manual fallback on failure.
            if newPhase == .failed { showManual = true }
        }
    }

    private var normalFlow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accentText)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(theme.accentOn.opacity(0.14))
                    )
                Text(L10n.authSheetTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.onSurface)
                Spacer()
            }

            Text(L10n.authSheetIntro)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            primaryArea

            Rectangle().fill(theme.hairline).frame(height: 1)

            // Full-row toggle (not a bare DisclosureGroup triangle) so the whole strip is the
            // hit target — mirrors the Advanced-settings collapsible header.
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showManual.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textMuted)
                    Text(L10n.authPasteManually)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                        .rotationEffect(.degrees(showManual ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(theme.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressButtonStyle())

            if showManual {
                VStack(alignment: .leading, spacing: 8) {
                    Button { SetupTokenLauncher.openInTerminal() } label: {
                        Label(L10n.authOpenInTerminal, systemImage: "terminal")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.link)

                    HStack(spacing: 8) {
                        TextField(L10n.authPastePlaceholder, text: $pasteToken)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { commit(pasteToken) }
                        Button(L10n.save) { commit(pasteToken) }
                            .disabled(!isPasteValid)
                    }
                }
                .padding(.top, 2)
                .transition(.advancedReveal)
            }

            HStack {
                Spacer()
                Button(L10n.close) {
                    runner.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    /// Prominent, non-auto-dismissing success panel — the user confirms with Done so the
    /// "token saved" result can't be missed.
    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(theme.positive)
                .frame(width: 76, height: 76)
                .background(Circle().fill(theme.positive.opacity(0.12)))
            Text(L10n.authSaved)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(theme.onSurface)
            Text(L10n.authSavedDetail)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.done) { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(theme.accentOn)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var primaryArea: some View {
        switch runner.phase {
        case .idle:
            Button { runner.start() } label: {
                Label(L10n.authStart, systemImage: "globe")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accentOn)
            .controlSize(.large)

        case .running:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.authWaiting)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }
            if let url = runner.loginURL {
                Button {
                    if let parsed = URL(string: url) { NSWorkspace.shared.open(parsed) }
                } label: {
                    Label(L10n.authOpenLoginPage, systemImage: "arrow.up.forward.app")
                        .font(.system(size: 12))
                }
                .buttonStyle(.link)
            }
            console
            Button(L10n.close) { runner.cancel() }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textMuted)
                .font(.system(size: 12))

        case .captured:
            // Routed to `successView` by `body`; this branch is unreachable.
            EmptyView()

        case .failed:
            if let message = runner.errorMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { runner.start() } label: {
                Label(L10n.authStart, systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private var console: some View {
        ScrollView {
            Text(runner.consoleText.isEmpty ? "…" : runner.consoleText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(height: 90)
        .padding(8)
        .background(theme.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1)
        )
    }

    private var isPasteValid: Bool {
        let trimmed = pasteToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("sk-ant-oat01-") && trimmed.count >= 80
    }

    private func commit(_ token: String) {
        if model.saveOAuthToken(token) {
            runner.cancel()
            dismiss()
        }
    }
}

// MARK: - Terminal launcher (manual fallback)

enum SetupTokenLauncher {
    /// Open Terminal.app running `claude setup-token` — the guaranteed real-TTY path behind the
    /// manual-paste fallback.
    static func openInTerminal() {
        let script = """
        tell application "Terminal"
        activate
        do script "claude setup-token"
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}
