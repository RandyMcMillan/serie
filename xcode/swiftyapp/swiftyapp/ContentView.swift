import SwiftUI
import RustyLib

struct ContentView: View {
    @StateObject private var model = SerieAppModel()

    var body: some View {
        NavigationSplitView {
            SerieCommitListPane(model: model)
        } detail: {
            SerieCommitDetailPane(model: model)
        }
        .task {
            if model.snapshot == nil {
                loadRepository()
            }
        }
        .alert("Unable to load repository", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                model.clearError()
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )
    }

    private func loadRepository() {
        do {
            try model.loadRepositorySnapshot()
        } catch {
            model.clearError()
        }
    }
}

private struct SerieCommitListPane: View {
    @ObservedObject var model: SerieAppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle("Serie")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Reload") { reload() }
                Button("Copy SHA") { model.copySelectedCommitHash() }
                Button("Copy Short SHA") { model.copySelectedCommitHash(short: true) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TextField("Repository path", text: repositoryPathBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button("Load", action: reload)
                    .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 8) {
                TextField("Search commits", text: searchQueryBinding)
                    .textFieldStyle(.roundedBorder)

                Toggle("Case", isOn: ignoreCaseBinding)
                    .toggleStyle(.button)

                Toggle("Fuzzy", isOn: fuzzyBinding)
                    .toggleStyle(.button)

                Spacer()

                Text("\(model.filteredCommits.count) / \(model.commits.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var content: some View {
        Group {
            if model.isLoading && model.snapshot == nil {
                ProgressView("Loading commits...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.filteredCommits.isEmpty {
                ContentUnavailableView("No commits", systemImage: "tray", description: Text("Load a git repository or adjust the search query."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.filteredCommits.enumerated()), id: \.element.hash) { index, commit in
                                SerieCommitRow(
                                    commit: commit,
                                    isSelected: commit.hash == model.selectedCommitHash,
                                    onSelect: {
                                        try? model.selectFilteredCommit(index: index)
                                    },
                                    onCopyShort: {
                                        try? model.selectCommit(hash: commit.hash)
                                        model.copySelectedCommitHash(short: true)
                                    },
                                    onCopyFull: {
                                        try? model.selectCommit(hash: commit.hash)
                                        model.copySelectedCommitHash()
                                    }
                                )
                                .id(commit.hash)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: model.selectedCommitHash) { _, hash in
                        guard let hash else { return }
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(hash, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var repositoryPathBinding: Binding<String> {
        Binding(
            get: { model.repositoryPath },
            set: { model.repositoryPath = $0 }
        )
    }

    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { model.searchState.query },
            set: { model.updateSearchQuery($0) }
        )
    }

    private var ignoreCaseBinding: Binding<Bool> {
        Binding(
            get: { model.searchState.ignoreCase },
            set: { _ in model.toggleIgnoreCase() }
        )
    }

    private var fuzzyBinding: Binding<Bool> {
        Binding(
            get: { model.searchState.fuzzy },
            set: { _ in model.toggleFuzzy() }
        )
    }

    private func reload() {
        do {
            try model.loadRepositorySnapshot()
        } catch {
            model.clearError()
        }
    }
}

private struct SerieCommitRow: View {
    let commit: SerieCommitSummary
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopyShort: () -> Void
    let onCopyFull: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                commitGlyph

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(commit.shortHash)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(commit.subject.isEmpty ? "(no subject)" : commit.subject)
                            .font(.body)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        Text(commit.authorName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(commit.authorDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !commit.refs.isEmpty {
                            Text(commit.refs.map(\.name).joined(separator: " "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)

                Menu {
                    Button("Copy Short SHA", action: onCopyShort)
                    Button("Copy SHA", action: onCopyFull)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            .padding(.horizontal, 8)
    }

    private var commitGlyph: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.7))
                .frame(width: 10, height: 10)
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 2, height: 28)
                .opacity(commit.parents.isEmpty ? 0 : 1)
        }
        .frame(width: 18)
        .padding(.top, 4)
    }
}

private struct SerieCommitDetailPane: View {
    @ObservedObject var model: SerieAppModel

    var body: some View {
        Group {
            if let detail = model.selectedCommitDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(detail.commit)
                        Divider()
                        bodySection(detail)
                    }
                    .padding(24)
                }
                .scrollIndicators(.hidden)
            } else {
                ContentUnavailableView(
                    "Select a commit",
                    systemImage: "list.bullet.rectangle",
                    description: Text("The selected commit appears here.")
                )
            }
        }
    }

    private func header(_ commit: SerieCommitSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(commit.subject.isEmpty ? "(no subject)" : commit.subject)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Text(commit.shortHash)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(commit.authorName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(commit.authorDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !commit.refs.isEmpty {
                Text(commit.refs.map(\.name).joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bodySection(_ detail: SerieCommitDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            detailCard(title: "Commit") {
                LabeledContent("Hash", value: detail.commit.hash)
                LabeledContent("Parents", value: detail.commit.parents.joined(separator: " "))
                LabeledContent("Kind", value: String(describing: detail.commit.kind))
            }

            if !detail.commit.body.isEmpty {
                detailCard(title: "Message") {
                    Text(detail.commit.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            detailCard(title: "Files") {
                if detail.changes.isEmpty {
                    Text("No file changes")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(detail.changes.enumerated()), id: \.offset) { _, change in
                            Text(change.summary)
                                .font(.callout.monospaced())
                        }
                    }
                }
            }
        }
    }

    private func detailCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

#Preview {
    ContentView()
}
