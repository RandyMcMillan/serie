use std::path::Path;

use serie::git::{
    Commit as GitCommit, CommitType as GitCommitType, FileChange as GitFileChange,
    Head as GitHead, Ref as GitRef, Repository, SortCommit,
};

uniffi::setup_scaffolding!();

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum SerieCommitKind {
    Commit,
    Stash,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum SerieCommitOrderType {
    Chrono,
    Topo,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum SerieRepositoryHead {
    Branch { name: String },
    Detached { target: String },
    None,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum SerieRepositoryRef {
    Tag { name: String, target: String },
    Branch { name: String, target: String },
    RemoteBranch { name: String, target: String },
    Stash {
        name: String,
        message: String,
        target: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum SerieFileChange {
    Add { path: String },
    Modify { path: String },
    Delete { path: String },
    Move { from: String, to: String },
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SerieCommitSummary {
    pub hash: String,
    pub short_hash: String,
    pub author_name: String,
    pub author_email: String,
    pub author_date: String,
    pub committer_name: String,
    pub committer_email: String,
    pub committer_date: String,
    pub subject: String,
    pub body: String,
    pub parents: Vec<String>,
    pub kind: SerieCommitKind,
    pub refs: Vec<SerieRepositoryRef>,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SerieRepositorySnapshot {
    pub path: String,
    pub head: SerieRepositoryHead,
    pub commits: Vec<SerieCommitSummary>,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SerieCommitDetail {
    pub commit: SerieCommitSummary,
    pub changes: Vec<SerieFileChange>,
}

#[uniffi::export]
fn rust_hello() -> String {
    "Hello from Rust!".to_string()
}

#[uniffi::export]
pub fn rust_add(a: u32, b: u32) -> u32 {
    a + b
}

#[uniffi::export]
pub fn serie_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[uniffi::export]
pub fn serie_repository_snapshot(
    path: String,
    max_count: Option<u32>,
    order: SerieCommitOrderType,
) -> SerieRepositorySnapshot {
    let repository = load_repository(&path, max_count, order);
    let commits = repository
        .all_commits()
        .into_iter()
        .map(|commit| {
            let refs = repository
                .refs(&commit.commit_hash)
                .into_iter()
                .map(from_git_ref)
                .collect();
            commit_summary(commit, refs)
        })
        .collect();

    SerieRepositorySnapshot {
        path,
        head: from_git_head(repository.head()),
        commits,
    }
}

#[uniffi::export]
pub fn serie_commit_detail(path: String, commit_hash: String) -> SerieCommitDetail {
    let repository = load_repository(&path, None, SerieCommitOrderType::Chrono);
    let commit_hash = serie::git::CommitHash::from(commit_hash.as_str());
    let (commit, changes) = repository.commit_detail(&commit_hash);
    let refs = repository
        .refs(&commit.commit_hash)
        .into_iter()
        .map(from_git_ref)
        .collect();

    SerieCommitDetail {
        commit: commit_summary(&commit, refs),
        changes: changes.into_iter().map(from_git_file_change).collect(),
    }
}

fn load_repository(path: &str, max_count: Option<u32>, order: SerieCommitOrderType) -> Repository {
    let sort = match order {
        SerieCommitOrderType::Chrono => SortCommit::Chronological,
        SerieCommitOrderType::Topo => SortCommit::Topological,
    };
    let max_count = max_count.map(|count| count as usize);
    Repository::load(Path::new(path), sort, max_count)
        .unwrap_or_else(|error| panic!("failed to load repository at {path}: {error}"))
}

fn commit_summary(commit: &GitCommit, refs: Vec<SerieRepositoryRef>) -> SerieCommitSummary {
    SerieCommitSummary {
        hash: commit.commit_hash.as_str().to_string(),
        short_hash: commit.commit_hash.as_short_hash().to_string(),
        author_name: commit.author_name.clone(),
        author_email: commit.author_email.clone(),
        author_date: commit.author_date.to_rfc3339(),
        committer_name: commit.committer_name.clone(),
        committer_email: commit.committer_email.clone(),
        committer_date: commit.committer_date.to_rfc3339(),
        subject: commit.subject.clone(),
        body: commit.body.clone(),
        parents: commit
            .parent_commit_hashes
            .iter()
            .map(|hash| hash.as_str().to_string())
            .collect(),
        kind: match &commit.commit_type {
            GitCommitType::Commit => SerieCommitKind::Commit,
            GitCommitType::Stash => SerieCommitKind::Stash,
        },
        refs,
    }
}

fn from_git_head(head: &GitHead) -> SerieRepositoryHead {
    match head {
        GitHead::Branch { name } => SerieRepositoryHead::Branch { name: name.clone() },
        GitHead::Detached { target } => SerieRepositoryHead::Detached {
            target: target.as_str().to_string(),
        },
        GitHead::None => SerieRepositoryHead::None,
    }
}

fn from_git_ref(reference: &GitRef) -> SerieRepositoryRef {
    match reference {
        GitRef::Tag { name, target } => SerieRepositoryRef::Tag {
            name: name.clone(),
            target: target.as_str().to_string(),
        },
        GitRef::Branch { name, target } => SerieRepositoryRef::Branch {
            name: name.clone(),
            target: target.as_str().to_string(),
        },
        GitRef::RemoteBranch { name, target } => SerieRepositoryRef::RemoteBranch {
            name: name.clone(),
            target: target.as_str().to_string(),
        },
        GitRef::Stash {
            name,
            message,
            target,
        } => SerieRepositoryRef::Stash {
            name: name.clone(),
            message: message.clone(),
            target: target.as_str().to_string(),
        },
    }
}

fn from_git_file_change(change: GitFileChange) -> SerieFileChange {
    match change {
        GitFileChange::Add { path } => SerieFileChange::Add { path },
        GitFileChange::Modify { path } => SerieFileChange::Modify { path },
        GitFileChange::Delete { path } => SerieFileChange::Delete { path },
        GitFileChange::Move { from, to } => SerieFileChange::Move { from, to },
    }
}
