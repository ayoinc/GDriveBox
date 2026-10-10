import AppKit
import DriveAPI
import SwiftUI

/// The debug window listing the My Drive root. Its `NSWindow` anchors the Google sign-in sheet.
struct DriveWindow: View {
    let model: AppModel
    // Property-wrapper type used directly: the macOS 27 SDK's `@State` macro needs Xcode's plugin.
    private let anchor = State(initialValue: WindowAnchor())
    private let hasWindow = State(initialValue: false)

    var body: some View {
        VStack(spacing: 0) {
            if model.isSignedIn {
                AccountHeader(account: model.account, isSigningOut: model.isSigningOut) {
                    Task { await model.signOut() }
                }
                Divider()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.isSignedIn, let problem = model.finderFolderProblem {
                Divider()
                Label("\(problem.title): \(problem.message)", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            if model.isSignedIn, model.finderFolderProblem == nil, model.finderFolderNeedsEnabling {
                Divider()
                HStack {
                    Label(
                        "Turn on GDriveBox under File Providers in System Settings to see My Drive in Finder, then click Refresh.",
                        systemImage: "info.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open System Settings…") {
                        NSWorkspace.shared.open(FinderFolder.settingsURL)
                    }
                }
                .padding(8)
            }
        }
        .frame(minWidth: 520, minHeight: 320)
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .disabled(!model.isSignedIn || model.listing == .loading)
            }
        }
        .background(WindowReader { window in
            anchor.wrappedValue.window = window
            hasWindow.wrappedValue = window != nil
        })
        .onChange(of: model.isSignInPending && hasWindow.wrappedValue, initial: true) { _, ready in
            if ready { signIn() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isSigningIn {
            ProgressView("Waiting for Google sign-in…")
        } else if model.isSigningOut {
            ProgressView("Signing out…")
        } else if let problem = model.sessionProblem {
            ProblemView(problem: problem, signIn: signIn, retry: signIn)
        } else if !model.isSignedIn {
            ContentUnavailableView {
                Label("Not signed in", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text(model.notice ?? "Sign in with Google to list My Drive.")
            } actions: {
                Button("Sign In with Google…", action: signIn)
            }
        } else {
            switch model.listing {
            case .idle, .loading:
                ProgressView("Loading My Drive…")
            case .failed(let problem):
                ProblemView(problem: problem, signIn: signIn, retry: { Task { await model.refresh() } })
            case .loaded(let files, _) where files.isEmpty:
                ContentUnavailableView("My Drive is empty", systemImage: "folder")
            case .loaded(let files, let isTruncated):
                FileTable(files: files, isTruncated: isTruncated)
            }
        }
    }

    private func signIn() {
        guard let window = anchor.wrappedValue.window else {
            model.requestSignIn()
            return
        }
        Task { await model.signIn(presenting: window) }
    }
}

private struct AccountHeader: View {
    let account: About?
    let isSigningOut: Bool
    let signOut: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            if let account {
                VStack(alignment: .leading) {
                    Text(account.user.displayName).font(.headline)
                    Text(account.user.emailAddress).foregroundStyle(.secondary)
                }
                Spacer()
                StorageUsage(quota: account.storageQuota)
            } else {
                Text("Loading account…").foregroundStyle(.secondary)
                Spacer()
            }
            Button("Sign Out", action: signOut)
                .disabled(isSigningOut)
        }
        .padding()
    }
}

private struct StorageUsage: View {
    let quota: About.StorageQuota

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let limit = quota.limit {
                Text("\(formattedBytes(quota.usage)) of \(formattedBytes(limit)) used")
                ProgressView(value: Double(min(quota.usage, limit)), total: Double(max(limit, 1)))
                    .frame(width: 160)
            } else {
                Text("\(formattedBytes(quota.usage)) used")
            }
        }
        .font(.callout)
    }
}

private struct ProblemView: View {
    let problem: Problem
    let signIn: () -> Void
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(problem.title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(problem.message)
        } actions: {
            switch problem.recovery {
            case .signInAgain:
                Button("Sign in again", action: signIn)
            case .retry:
                Button("Try Again", action: retry)
            case .none:
                EmptyView()
            }
        }
    }
}

private struct FileTable: View {
    let files: [DriveFile]
    let isTruncated: Bool

    var body: some View {
        VStack(spacing: 0) {
            Table(files) {
                TableColumn("Name") { file in
                    Label(file.name, systemImage: file.isFolder ? "folder.fill" : "doc")
                }
                TableColumn("Size") { file in
                    Text(file.size.map(formattedBytes) ?? "")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 60, ideal: 90, max: 140)
                TableColumn("Modified") { file in
                    Text(file.modifiedTime, format: .dateTime.year().month().day().hour().minute())
                        .foregroundStyle(.secondary)
                }
                .width(min: 120, ideal: 170)
            }
            if isTruncated {
                Divider()
                Text("Showing the first \(files.count) items.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
    }
}

private func formattedBytes(_ count: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
}

extension DriveFile: Identifiable {}

/// Weak holder so the window's own SwiftUI state does not retain the window.
private final class WindowAnchor {
    weak var window: NSWindow?
}

/// Reports the `NSWindow` hosting this view whenever it changes.
private struct WindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReportingView {
        let view = ReportingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReportingView, context: Context) {
        view.onChange = onChange
    }

    final class ReportingView: NSView {
        var onChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Called mid-layout; report on the next turn so SwiftUI state is not mutated during an update.
            let window = window
            Task { @MainActor [onChange] in onChange?(window) }
        }
    }
}
