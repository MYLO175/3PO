import Foundation

/// A small private HTTP bridge; the Node SDK owns MCP framing and lifecycle.
struct MCPBridgeHTTPRequest {
    var headers: [String: String]
    var body: Data
    static let maxBody = 80_000
    static let maxHeader = 8192
    static func parse(_ bytes: Data) throws -> Self? {
        guard bytes.count <= maxHeader + maxBody else { throw MCPBridgeHTTPError.invalid }
        let divider = Data("\r\n\r\n".utf8)
        guard let range = bytes.range(of: divider) else {
            guard bytes.count <= maxHeader else { throw MCPBridgeHTTPError.invalid }; return nil
        }
        guard range.lowerBound <= maxHeader, let header = String(data: bytes[..<range.lowerBound], encoding: .utf8) else { throw MCPBridgeHTTPError.invalid }
        let lines = header.components(separatedBy: "\r\n")
        guard lines.first == "POST /bridge HTTP/1.1" else { throw MCPBridgeHTTPError.invalid }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else { throw MCPBridgeHTTPError.invalid }
            let name = String(line[..<colon]).lowercased(), value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, headers[name] == nil else { throw MCPBridgeHTTPError.invalid }
            headers[name] = value
        }
        guard headers["transfer-encoding"] == nil, headers["origin"] == nil,
              let length = headers["content-length"], !length.isEmpty, length.allSatisfy(\.isNumber),
              let count = Int(length), count > 0, count <= maxBody,
              headers["content-type"]?.split(separator: ";").first == "application/json" else { throw MCPBridgeHTTPError.invalid }
        let body = bytes[range.upperBound...]
        guard body.count <= count else { throw MCPBridgeHTTPError.invalid }
        guard body.count == count else { return nil }
        return .init(headers: headers, body: Data(body))
    }
    func authorized(token: String, port: UInt16) -> Bool {
        guard headers["host"] == "127.0.0.1:\(port)", let supplied = headers["authorization"] else { return false }
        // Compare all bytes, including when a wrong token has the right length.
        let left = Array(supplied.utf8), right = Array(("Bearer " + token).utf8)
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
enum MCPBridgeHTTPError: Error { case invalid }
