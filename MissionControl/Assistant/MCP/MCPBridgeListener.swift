import Foundation
import Network

final class MCPBridgeListener: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MissionControl.mcp.bridge")
    private let token: String
    private let handler: @Sendable (Data) async -> Data
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var port: UInt16 = 0
    private var resolved = false
    private var stopped = false
    init(token: String, handler: @escaping @Sendable (Data) async -> Data) { self.token = token; self.handler = handler }
    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !self.resolved, let port = listener.port else { return }
                    self.resolved = true; self.port = port.rawValue; continuation.resume(returning: port.rawValue)
                case .failed(let error):
                    if !self.resolved { self.resolved = true; continuation.resume(throwing: error) }
                    self.stop()
                case .cancelled:
                    if !self.resolved { self.resolved = true; continuation.resume(throwing: CancellationError()) }
                    self.listener?.stateUpdateHandler = nil
                    self.listener = nil
                default: break
                }
            }
            listener.newConnectionHandler = { connection in
                guard !self.stopped, self.connections.count < 16 else { connection.cancel(); return }
                let id = UUID(); self.connections[id] = connection
                connection.start(queue: self.queue)
                self.receive(connection, id: id, bytes: Data())
                self.queue.asyncAfter(deadline: .now() + 30) { self.close(id) }
            }
            listener.start(queue: queue)
        }
    }
    func stop() {
        queue.async {
            self.stopped = true; self.listener?.cancel()
            self.listener?.newConnectionHandler = nil
            if self.resolved { self.listener?.stateUpdateHandler = nil; self.listener = nil }
            for connection in self.connections.values { connection.cancel() }
            self.connections.removeAll()
        }
    }
    private func close(_ id: UUID) { connections.removeValue(forKey: id)?.cancel() }
    private func receive(_ connection: NWConnection, id: UUID, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, complete, error in
            guard error == nil, !self.stopped else { self.close(id); return }
            let buffer = bytes + (data ?? Data())
            do {
                guard let request = try MCPBridgeHTTPRequest.parse(buffer) else {
                    if complete { self.close(id) } else { self.receive(connection, id: id, bytes: buffer) }; return
                }
                guard request.authorized(token: self.token, port: self.port) else { self.reply(connection, id: id, status: "403 Forbidden", body: Data("{}".utf8)); return }
                Task {
                    let body = await self.handler(request.body)
                    self.queue.async {
                        guard self.connections[id] != nil, !self.stopped else { return }
                        self.reply(connection, id: id, status: "200 OK", body: body)
                    }
                }
            } catch { self.reply(connection, id: id, status: "400 Bad Request", body: Data("{}".utf8)) }
        }
    }
    private func reply(_ connection: NWConnection, id: UUID, status: String, body: Data) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in self.close(id) })
    }
}
