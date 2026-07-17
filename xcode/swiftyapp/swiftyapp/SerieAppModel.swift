import Foundation
import SwiftUI
import RustyLib

struct SerieListState: Equatable {
    var selectedIndex: Int = 0
    var scrollOffset: Int = 0
    var visibleHeight: Int = 0
    var scrollToTop: Bool = true
}

struct SerieSearchState: Equatable {
    var query: String = ""
    var ignoreCase: Bool = false
    var fuzzy: Bool = false
    var matchIndex: Int = 0
    var matchCount: Int = 0
    var transientMessage: String?
}

struct SerieRefsState: Equatable {
    var selectedPath: [String] = []
    var openedPaths: [[String]] = []
}

struct SerieUserCommandState: Equatable {
    var number: Int = 0
}

enum SerieScreen: Equatable {
    case list
    case detail
    case refs
    case userCommand(Int)
    case help
}

struct SerieListRefreshState: Equatable {
    var commitHash: String
    var selected: Int
    var height: Int
    var scrollToTop: Bool
}

struct SerieUserCommandRefreshState: Equatable {
    var number: Int
}

struct SerieRefsRefreshState: Equatable {
    var selected: [String]
    var opened: [[String]]
}

enum SerieRefreshContext: Equatable {
    case list(SerieListRefreshState)
    case detail(SerieListRefreshState)
    case userCommand(list: SerieListRefreshState, command: SerieUserCommandRefreshState)
    case refs(list: SerieListRefreshState, refs: SerieRefsRefreshState)
}

@MainActor
final class SerieAppModel: ObservableObject {
    @Published var repositoryPath: String
    @Published var maxCount: UInt32?
    @Published var commitOrder: SerieCommitOrderType

    @Published private(set) var snapshot: SerieRepositorySnapshot?
    @Published private(set) var selectedCommitHash: String?
    @Published private(set) var selectedCommitDetail: SerieCommitDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    @Published var listState = SerieListState()
    @Published var searchState = SerieSearchState()
    @Published var refsState = SerieRefsState()
    @Published var userCommandState = SerieUserCommandState()
    @Published var activeScreen: SerieScreen = .list
    @Published var refreshContext: SerieRefreshContext?

    init(
        repositoryPath: String = FileManager.default.currentDirectoryPath,
        maxCount: UInt32? = nil,
        commitOrder: SerieCommitOrderType = .chrono
    ) {
        self.repositoryPath = repositoryPath
        self.maxCount = maxCount
        self.commitOrder = commitOrder
    }

    var commits: [SerieCommitSummary] {
        snapshot?.commits ?? []
    }

    var selectedCommit: SerieCommitSummary? {
        selectedCommitDetail?.commit
    }

    var filteredCommits: [SerieCommitSummary] {
        filter(commits: commits)
    }

    var selectedCommitIndex: Int? {
        guard let selectedCommitHash else {
            return nil
        }
        return filteredCommits.firstIndex(where: { $0.hash == selectedCommitHash })
    }

    func loadRepositorySnapshot() throws {
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = serieRepositorySnapshot(
                path: repositoryPath,
                maxCount: maxCount,
                order: commitOrder
            )
            self.snapshot = snapshot
            self.errorMessage = nil

            if let selectedCommitHash,
               snapshot.commits.contains(where: { $0.hash == selectedCommitHash }) {
                try loadCommitDetail(hash: selectedCommitHash)
            } else if let firstCommit = snapshot.commits.first {
                try selectCommit(hash: firstCommit.hash)
            } else {
                self.selectedCommitHash = nil
                self.selectedCommitDetail = nil
            }
        } catch {
            snapshot = nil
            selectedCommitHash = nil
            selectedCommitDetail = nil
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func selectCommit(index: Int) throws {
        guard commits.indices.contains(index) else {
            return
        }
        try selectCommit(hash: commits[index].hash)
    }

    func selectCommit(hash: String) throws {
        selectedCommitHash = hash
        try loadCommitDetail(hash: hash)
    }

    func loadCommitDetail(hash: String) throws {
        do {
            let detail = serieCommitDetail(path: repositoryPath, commitHash: hash)
            selectedCommitDetail = detail
            selectedCommitHash = hash
            errorMessage = nil
        } catch {
            selectedCommitDetail = nil
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func selectNextCommit() throws {
        guard !filteredCommits.isEmpty else {
            return
        }
        let nextIndex = min((selectedCommitIndex ?? -1) + 1, filteredCommits.count - 1)
        try selectCommit(hash: filteredCommits[nextIndex].hash)
        listState.selectedIndex = nextIndex
    }

    func selectPreviousCommit() throws {
        guard !filteredCommits.isEmpty else {
            return
        }
        let previousIndex = max((selectedCommitIndex ?? filteredCommits.count) - 1, 0)
        try selectCommit(hash: filteredCommits[previousIndex].hash)
        listState.selectedIndex = previousIndex
    }

    func selectFirstCommit() throws {
        guard let first = filteredCommits.first else {
            return
        }
        try selectCommit(hash: first.hash)
        listState.selectedIndex = 0
    }

    func selectLastCommit() throws {
        guard let lastIndex = filteredCommits.indices.last else {
            return
        }
        try selectCommit(hash: filteredCommits[lastIndex].hash)
        listState.selectedIndex = lastIndex
    }

    func copySelectedCommitHash(short: Bool = false) {
        guard let selectedCommit = selectedCommit else {
            return
        }
        copyToPasteboard(short ? selectedCommit.shortHash : selectedCommit.hash)
    }

    func restore(listState: SerieListRefreshState) {
        if let commit = commits.first(where: { $0.hash == listState.commitHash }) {
            selectedCommitHash = commit.hash
        }
        self.listState.selectedIndex = listState.selected
        self.listState.visibleHeight = listState.height
        self.listState.scrollToTop = listState.scrollToTop
        self.listState.scrollOffset = listState.scrollToTop ? 0 : max(0, listState.selected)
    }

    func restore(refsState: SerieRefsRefreshState) {
        self.refsState.selectedPath = refsState.selected
        self.refsState.openedPaths = refsState.opened
    }

    func restore(userCommandState: SerieUserCommandRefreshState) {
        self.userCommandState.number = userCommandState.number
    }

    func captureListRefreshState() -> SerieListRefreshState? {
        guard let selectedCommitHash else {
            return nil
        }
        return SerieListRefreshState(
            commitHash: selectedCommitHash,
            selected: listState.selectedIndex,
            height: listState.visibleHeight,
            scrollToTop: listState.scrollToTop
        )
    }

    func captureRefreshContext() -> SerieRefreshContext? {
        guard let listState = captureListRefreshState() else {
            return nil
        }

        switch activeScreen {
        case .list:
            return .list(listState)
        case .detail:
            return .detail(listState)
        case let .userCommand(number):
            return .userCommand(
                list: listState,
                command: SerieUserCommandRefreshState(number: number)
            )
        case .refs:
            return .refs(
                list: listState,
                refs: SerieRefsRefreshState(
                    selected: refsState.selectedPath,
                    opened: refsState.openedPaths
                )
            )
        case .help:
            return .list(listState)
        }
    }

    func updateSearchQuery(_ query: String) {
        searchState.query = query
        if let selectedCommitHash, !filteredCommits.contains(where: { $0.hash == selectedCommitHash }) {
            selectedCommitHash = filteredCommits.first?.hash
            if let hash = selectedCommitHash {
                try? loadCommitDetail(hash: hash)
            }
        }
        searchState.matchCount = filteredCommits.count
    }

    func toggleIgnoreCase() {
        searchState.ignoreCase.toggle()
        updateSearchQuery(searchState.query)
    }

    func toggleFuzzy() {
        searchState.fuzzy.toggle()
        updateSearchQuery(searchState.query)
    }

    private func filter(commits: [SerieCommitSummary]) -> [SerieCommitSummary] {
        let query = searchState.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return commits
        }

        return commits.filter { commit in
            let haystack = searchableText(for: commit)
            if searchState.fuzzy {
                return isSubsequence(query: normalized(query), in: normalized(haystack))
            } else {
                return normalized(haystack).contains(normalized(query))
            }
        }
    }

    private func searchableText(for commit: SerieCommitSummary) -> String {
        [
            commit.hash,
            commit.shortHash,
            commit.authorName,
            commit.authorEmail,
            commit.subject,
            commit.body,
            commit.parents.joined(separator: " "),
            commit.refs.map(\.name).joined(separator: " ")
        ]
        .joined(separator: " ")
    }

    private func normalized(_ value: String) -> String {
        searchState.ignoreCase ? value.lowercased() : value
    }

    private func isSubsequence(query: String, in candidate: String) -> Bool {
        guard !query.isEmpty else {
            return true
        }

        var candidateIndex = candidate.startIndex
        for character in query {
            guard let found = candidate[candidateIndex...].firstIndex(of: character) else {
                return false
            }
            candidateIndex = candidate.index(after: found)
        }
        return true
    }

    private func copyToPasteboard(_ string: String) {
#if canImport(UIKit)
        UIPasteboard.general.string = string
#elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
#endif
    }
}

extension SerieRepositorySnapshot {
    func commit(at index: Int) -> SerieCommitSummary? {
        commits.indices.contains(index) ? commits[index] : nil
    }
}

extension SerieCommitSummary {
    var parentHashesText: String {
        parents.joined(separator: " ")
    }
}

extension SerieRepositoryHead {
    var label: String {
        switch self {
        case let .branch(name):
            return "branch \(name)"
        case let .detached(target):
            return "detached \(target)"
        case .none:
            return "none"
        }
    }
}

extension SerieRepositoryRef {
    var name: String {
        switch self {
        case let .tag(name, _):
            return name
        case let .branch(name, _):
            return name
        case let .remoteBranch(name, _):
            return name
        case let .stash(name, _, _):
            return name
        }
    }
}

extension SerieFileChange {
    var summary: String {
        switch self {
        case let .add(path):
            return "A \(path)"
        case let .modify(path):
            return "M \(path)"
        case let .delete(path):
            return "D \(path)"
        case let .move(from, to):
            return "R \(from) -> \(to)"
        }
    }
}
