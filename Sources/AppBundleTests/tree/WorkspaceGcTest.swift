@testable import AppBundle
import Common
import XCTest

@MainActor
final class WorkspaceGcTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testGcUnbindsCollectedWorkspace() {
        let collected = Workspace.get(byName: "collected")
        XCTAssertTrue(collected.isBound)

        Workspace.garbageCollectUnusedWorkspaces()

        XCTAssertFalse(collected.isBound)
        XCTAssertFalse(Workspace.all.contains { $0 === collected })
    }

    func testRecreatedWorkspaceIsVisibleWorkspace() {
        _ = Workspace.get(byName: "recreated")
        Workspace.garbageCollectUnusedWorkspaces()

        let fresh = Workspace.get(byName: "recreated")
        XCTAssertTrue(fresh.focusWorkspace())

        XCTAssertTrue(mainMonitorInfo.visibleWorkspace === fresh)
        XCTAssertTrue(globalFocus.workspace === fresh)
        assertEquals(workspaceObjectCount(named: "recreated"), 1)
    }

    func testRefreshDoesNotDuplicateForceAssignedWorkspaces() {
        config.workspaceToMonitorForceAssignment = ["forced": [.main]]
        defer { config.workspaceToMonitorForceAssignment = [:] }

        for _ in 1 ... 3 {
            Workspace.garbageCollectUnusedWorkspaces()
            Workspace.forceAssignWorkspaces()
        }

        assertEquals(workspaceObjectCount(named: "forced"), 1)
    }

    func testUpdateTrayTextAfterWorkspaceIsRecreated() {
        _ = Workspace.get(byName: "tray")
        Workspace.garbageCollectUnusedWorkspaces()
        XCTAssertTrue(Workspace.get(byName: "tray").focusWorkspace())

        updateTrayText() // Used to die in Workspace.== because two objects were named "tray"
    }

    private func workspaceObjectCount(named name: String) -> Int {
        mainMonitorInfo.toMonitorOrRearrangeMonitors().getWorkspacesContainerOrCreate().children
            .filterIsInstance(of: Workspace.self)
            .count { $0.name == name }
    }
}
