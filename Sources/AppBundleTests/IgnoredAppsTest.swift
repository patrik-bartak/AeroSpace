@testable import AppBundle
import Common
import XCTest

@MainActor
final class IgnoredAppsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    override func tearDown() async throws {
        appForTests = nil
        setUpWorkspacesForTests()
    }

    func testIgnoredAppFocusDoesNotSwitchWorkspace() async throws {
        let current = Workspace.get(byName: "current")
        assertTrue(current.focusWorkspace())
        let popup = TestWindow.new(id: 1, parent: Workspace.get(byName: "other").floatingWindowsContainer)
        config.ignoredApps = [TestApp.shared.rawAppBundleId.orDie()]
        popup.nativeFocus()

        let focused = try await getNativeFocusedWindow(.cancellable)
        assertNil(focused)
        updateFocusCache(focused)
        assertEquals(globalFocus.workspace.name, "current")
        assertNil(globalFocus.windowOrNil)
    }

    func testUnmatchedAppStillProvidesNativeFocus() async throws {
        let window = TestWindow.new(id: 1, parent: globalFocus.workspace.rootTilingContainer)
        config.ignoredApps = ["com.electron.gitify"]
        window.nativeFocus()
        let focused = try await getNativeFocusedWindow(.cancellable)
        assertEquals(focused, window)
    }
}
