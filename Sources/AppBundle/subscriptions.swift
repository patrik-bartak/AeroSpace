import Common
import Foundation
import Network

private struct Subscriber {
    let connection: NWConnection
    let events: Set<ServerEventType>
}

@MainActor private var subscribers: [UniqueToken: Subscriber] = [:]
@MainActor private var lastBroadcastTree: WorkspaceTreeSnapshot?

@MainActor
func handleSubscribeAndWaitTillError(_ connection: NWConnection, _ args: SubscribeCmdArgs) async {
    let id = UniqueToken()
    subscribers[id] = Subscriber(connection: connection, events: args.events)
    defer { subscribers.removeValue(forKey: id) }
    if args.events.contains(.workspaceTreeChanged),
       subscribers.values.count(where: { $0.events.contains(.workspaceTreeChanged) }) == 1
    {
        lastBroadcastTree = .capture()
    }
    if args.sendInitial {
        let f = globalFocus
        for eventType in args.events {
            let event: ServerEvent
            switch eventType {
                case .focusChanged:
                    event = .focusChanged(windowId: f.windowOrNil?.windowId, workspace: f.workspace.name)
                case .workspaceChanged:
                    event = .workspaceChanged(workspace: f.workspace.name, prevWorkspace: f.workspace.name)
                case .modeChanged:
                    event = .modeChanged(mode: activeMode)
                case .focusedMonitorChanged:
                    event = .focusedMonitorChanged(
                        workspace: f.workspace.name,
                        monitorId_oneBased: f.workspace.workspaceMonitorInfo.monitorId_oneBased ?? 0,
                    )
                case .windowDetected, .bindingTriggered: continue
                case .workspaceTreeChanged:
                    event = .workspaceTreeChanged(.capture())
            }
            if await connection.writeAtomic(event, jsonEncoder).error != nil {
                return
            }
        }
    }

    // Keep connection alive - wait for client to disconnect
    await connection.readTillError()
}

@MainActor
func broadcastWorkspaceTreeIfChanged() {
    guard subscribers.values.contains(where: { $0.events.contains(.workspaceTreeChanged) }) else {
        lastBroadcastTree = nil
        return
    }
    let tree = WorkspaceTreeSnapshot.capture()
    guard tree != lastBroadcastTree else { return }
    lastBroadcastTree = tree
    broadcastEvent(.workspaceTreeChanged(tree))
}

private let jsonEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
    return e
}()

func broadcastEvent(_ event: ServerEvent) {
    Task.startUnstructured { @MainActor in
        for (id, subscriber) in subscribers {
            guard subscriber.events.contains(event.eventType) else { continue }
            if await subscriber.connection.writeAtomic(event, jsonEncoder).error != nil {
                _ = subscribers.removeValue(forKey: id)
            }
        }
    }
}
