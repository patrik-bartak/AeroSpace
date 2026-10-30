import Common

struct WorkspaceTreeSnapshot: Codable, Equatable, Sendable {
    let focusedWindowId: OpaqueWindowId?
    let workspaces: [WorkspaceTree]

    @MainActor static func capture() -> Self {
        .init(
            focusedWindowId: globalFocus.windowOrNil?.windowId,
            workspaces: Workspace.all.sorted().map(WorkspaceTree.init),
        )
    }
}

struct WorkspaceTree: Codable, Equatable, Sendable {
    let workspace: String
    let isFocused: Bool
    let isVisible: Bool
    let monitorAppKitNsScreenScreensId: Int
    let root: WorkspaceTreeNode
    let floatingWindows: [WorkspaceTreeNode]
    let fullscreenWindows: [WorkspaceTreeNode]
    let hiddenWindows: [WorkspaceTreeNode]

    @MainActor init(_ workspace: Workspace) {
        self.workspace = workspace.name
        isFocused = globalFocus.workspace == workspace
        isVisible = workspace.isVisible
        monitorAppKitNsScreenScreensId = workspace.workspaceMonitorInfo.monitorAppKitNsScreenScreensId
        root = WorkspaceTreeNode(workspace.rootTilingContainer)
        floatingWindows = workspace.floatingWindows.compactMap(WorkspaceTreeNode.init)
        fullscreenWindows = workspace.macOsNativeFullscreenWindowsContainer.children.compactMap(WorkspaceTreeNode.init)
        hiddenWindows = workspace.macOsNativeHiddenAppsWindowsContainer.children.compactMap(WorkspaceTreeNode.init)
    }
}

struct WorkspaceTreeNode: Codable, Equatable, Sendable {
    enum Kind: String, Codable { case container, window }

    let type: Kind
    var layout: String?
    var orientation: String?
    var children: [WorkspaceTreeNode]?
    var windowId: OpaqueWindowId?
    var appBundleId: String?
    var appName: String?
    var title: String?

    @MainActor init(_ container: TilingContainer) {
        type = .container
        layout = container.layout.rawValue
        orientation = container.orientation == .h ? "horizontal" : "vertical"
        children = container.children.compactMap(Self.init)
    }

    @MainActor init?(_ node: TreeNode) {
        if let window = node as? Window, window.lifeStatus.isInhabited {
            type = .window
            windowId = window.windowId
            appBundleId = window.app.rawAppBundleId
            appName = window.app.name
            title = window.cachedTitle
        } else if let container = node as? TilingContainer, container.lifeStatus.isInhabited {
            self = Self(container)
        } else {
            return nil
        }
    }
}
