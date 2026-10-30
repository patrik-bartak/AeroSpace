import AppKit
import Common

func windowTitleObs(_: AXObserver, ax: AXUIElement, _: CFString, _: UnsafeMutableRawPointer?) {
    let nativeWindowId = ax.containingNativeWindowId()
    let pid = ax.pid
    let title = ax.get(Ax.titleAttr) ?? ""
    Task.startUnstructured { @MainActor in
        guard let nativeWindowId,
              let pid,
              let window = Window.get(byNativeId: nativeWindowId, pid: pid)
        else { return }
        window.cachedTitle = title
        broadcastWorkspaceTreeIfChanged()
    }
}
