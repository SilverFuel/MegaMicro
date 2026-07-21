import XCTest
@testable import MegaMicro

final class GitBranchResolverTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("megamicro-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ relativePath: String, _ contents: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func testReadsBranchFromNormalRepo() throws {
        try write("repo/.git/HEAD", "ref: refs/heads/main\n")
        XCTAssertEqual(GitBranchResolver.branch(atPath: root.appendingPathComponent("repo").path), "main")
    }

    func testBranchWithSlashes() throws {
        try write("repo/.git/HEAD", "ref: refs/heads/jessewaites/font-color-changes\n")
        XCTAssertEqual(
            GitBranchResolver.branch(atPath: root.appendingPathComponent("repo").path),
            "jessewaites/font-color-changes")
    }

    func testWalksUpFromSubdirectory() throws {
        try write("repo/.git/HEAD", "ref: refs/heads/dev\n")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("repo/src/deep"), withIntermediateDirectories: true)
        XCTAssertEqual(
            GitBranchResolver.branch(atPath: root.appendingPathComponent("repo/src/deep").path), "dev")
    }

    func testWorktreeGitFilePointer() throws {
        // A worktree's `.git` is a file pointing at the real gitdir, where HEAD
        // holds this worktree's branch (how Conductor lays out workspaces).
        let gitDir = root.appendingPathComponent("main/.git/worktrees/bozeman")
        try write("main/.git/worktrees/bozeman/HEAD", "ref: refs/heads/jessewaites/kaleidoscope\n")
        try write("workspaces/bozeman/.git", "gitdir: \(gitDir.path)\n")
        XCTAssertEqual(
            GitBranchResolver.branch(atPath: root.appendingPathComponent("workspaces/bozeman").path),
            "jessewaites/kaleidoscope")
    }

    func testDetachedHeadReturnsNil() throws {
        try write("repo/.git/HEAD", "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0\n")
        XCTAssertNil(GitBranchResolver.branch(atPath: root.appendingPathComponent("repo").path))
    }

    func testNonRepoReturnsNil() {
        XCTAssertNil(GitBranchResolver.branch(atPath: root.path))
    }

    // MARK: agentLabel — default branches show the repo, feature branches
    // show the branch.

    func testAgentLabelUsesRepoNameOnDefaultBranch() {
        XCTAssertEqual(AppState.agentLabel(branch: "main", folder: "designed-with-ai"), "designed-with-ai")
        XCTAssertEqual(AppState.agentLabel(branch: "master", folder: "felt"), "felt")
        XCTAssertEqual(AppState.agentLabel(branch: "MAIN", folder: "felt"), "felt")
    }

    func testAgentLabelUsesBranchOnFeatureBranch() {
        XCTAssertEqual(AppState.agentLabel(branch: "redesign-nav", folder: "designed-with-ai"), "redesign-nav")
        XCTAssertEqual(
            AppState.agentLabel(branch: "jessewaites/font-color-changes", folder: "repo"),
            "jessewaites/font-color-changes")
    }

    func testAgentLabelFallsBackToFolderWhenNotARepo() {
        XCTAssertEqual(AppState.agentLabel(branch: nil, folder: "some-folder"), "some-folder")
    }
}
