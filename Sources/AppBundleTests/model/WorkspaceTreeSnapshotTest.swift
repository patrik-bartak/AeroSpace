@testable import AppBundle
import Common
import Network
import XCTest

@MainActor
final class WorkspaceTreeSnapshotTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testNestedTreePreservesChildOrderAndRepeatedApps() throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let first = TestWindow.new(id: 30, parent: root)
        first.cachedTitle = "Zebra"
        let nested = TilingContainer.newVTiles(parent: root, adaptiveWeight: 1)
        TestWindow.new(id: 10, parent: nested).cachedTitle = "Alpha"
        TestWindow.new(id: 20, parent: nested)
        TestWindow.new(id: 40, parent: root).lifeStatus = .dead
        XCTAssertTrue(first.focusWindow())

        let snapshot = WorkspaceTreeSnapshot.capture()
        let tree = try XCTUnwrap(snapshot.workspaces.first { $0.workspace == workspace.name })
        XCTAssertTrue(tree.isFocused)
        XCTAssertTrue(tree.isVisible)
        XCTAssertEqual(tree.monitorAppKitNsScreenScreensId, 1)
        XCTAssertEqual(snapshot.focusedWindowId, 30)
        XCTAssertEqual(tree.root.orientation, "horizontal")
        let children = try XCTUnwrap(tree.root.children)
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children[0].windowId, 30)
        XCTAssertEqual(children[0].title, "Zebra")
        XCTAssertEqual(children[1].orientation, "vertical")
        XCTAssertEqual(children[1].children?.map(\.windowId), [10, 20])
        XCTAssertEqual(children[0].appBundleId, children[1].children?.first?.appBundleId)

        let data = try JSONEncoder().encode(ServerEvent.workspaceTreeChanged(snapshot))
        XCTAssertEqual(try JSONDecoder().decode(ServerEvent.self, from: data).eventType, .workspaceTreeChanged)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["_event"] as? String, "workspace-tree-changed")
        XCTAssertNotNil(json["tree"])
    }

    func testReorderMoveAndCloseChangeSnapshotWithoutChangingFocus() async {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        XCTAssertTrue(first.focusWindow())
        let before = WorkspaceTreeSnapshot.capture()
        XCTAssertEqual(before, .capture())

        _ = await parseCommand("swap right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        let reordered = WorkspaceTreeSnapshot.capture()
        XCTAssertNotEqual(reordered, before)
        XCTAssertEqual(reordered.focusedWindowId, before.focusedWindowId)

        second.bindAsFloatingWindow(to: Workspace.get(byName: "other"))
        let moved = WorkspaceTreeSnapshot.capture()
        XCTAssertNotEqual(moved, reordered)
        XCTAssertEqual(moved.focusedWindowId, before.focusedWindowId)
        XCTAssertEqual(moved.workspaces.first { $0.workspace == "other" }?.floatingWindows.first?.windowId, 2)

        second.closeAxWindow()
        let closed = WorkspaceTreeSnapshot.capture()
        XCTAssertNotEqual(closed, moved)
        XCTAssertEqual(closed.focusedWindowId, before.focusedWindowId)
    }

    func testTitleAndLayoutChangesAreIncluded() {
        let root = Workspace.get(byName: name).rootTilingContainer
        let window = TestWindow.new(id: 1, parent: root)
        let before = WorkspaceTreeSnapshot.capture()
        window.cachedTitle = "Changed"
        let renamed = WorkspaceTreeSnapshot.capture()
        XCTAssertNotEqual(renamed, before)
        root.layout = .accordion
        XCTAssertNotEqual(WorkspaceTreeSnapshot.capture(), renamed)
    }

    func testSubscriptionSendsInitialTreeAndUnfocusedWindowChanges() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer
        let first = TestWindow.new(id: 1, parent: root)
        let second = TestWindow.new(id: 2, parent: root)
        XCTAssertTrue(first.focusWindow())
        let args = try XCTUnwrap(parseSubscribeCmdArgs(["workspace-tree-changed"].slice).cmdOrNil)
        let path = "/private/tmp/aerospace-tree-\(UUID().uuidString).sock"
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .unix(path: path)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            Task.startUnstructured { @MainActor in
                defer { connection.cancel() }
                await handleSubscribeAndWaitTillError(connection, args)
            }
        }
        listener.start(queue: .global())
        defer {
            listener.cancel()
            try? FileManager.default.removeItem(atPath: path)
        }
        for _ in 0 ..< 200 where !FileManager.default.fileExists(atPath: path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let client = NWConnection(to: .unix(path: path), using: .tcp)
        client.start(queue: .global())
        defer { client.cancel() }
        let timeout = Task.startUnstructured {
            try await Task.sleep(for: .seconds(10))
            client.cancel()
        }
        defer { timeout.cancel() }
        _ = await client.writeUInt32(1)

        func readTree() async throws -> WorkspaceTreeSnapshot {
            let data = try await client.readNonAtomic().get()
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["_event"] as? String, "workspace-tree-changed")
            XCTAssertNotNil(object["revision"])
            return try JSONDecoder().decode(WorkspaceTreeSnapshot.self,
                                            from: JSONSerialization.data(withJSONObject: try XCTUnwrap(object["tree"])))
        }
        let initial = try await readTree()
        XCTAssertEqual(initial, .capture())

        broadcastWorkspaceTreeIfChanged()
        _ = await parseCommand("swap right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        broadcastWorkspaceTreeIfChanged()
        let reordered = try await readTree()
        XCTAssertEqual(reordered, .capture())
        XCTAssertEqual(reordered.focusedWindowId, 1)

        broadcastWorkspaceTreeIfChanged()
        second.closeAxWindow()
        broadcastWorkspaceTreeIfChanged()
        let afterClose = try await readTree()
        XCTAssertEqual(afterClose, .capture())
        XCTAssertEqual(afterClose.focusedWindowId, 1)

        let replacement = TestWindow.new(id: 3, parent: root)
        replacement.bindAsFloatingWindow(to: Workspace.get(byName: "other"))
        broadcastWorkspaceTreeIfChanged()
        let afterMove = try await readTree()
        XCTAssertEqual(afterMove, .capture())
    }
}
