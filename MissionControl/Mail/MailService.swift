import Foundation

struct MailAccount: Codable, Identifiable, Sendable {
    let id: String
    let title: String
}

struct MailMessage: Codable, Identifiable, Sendable {
    let id: String
    let accountID: String
    let account: String
    let messageID: Int
    let internetMessageID: String
    let sender: String
    let subject: String
    let received: Date
    let unread: Bool
    let replied: Bool
    let flagged: Bool

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        accountID = try values.decode(String.self, forKey: .accountID)
        account = try values.decode(String.self, forKey: .account)
        messageID = try values.decode(Int.self, forKey: .messageID)
        internetMessageID = try values.decode(String.self, forKey: .internetMessageID)
        sender = try values.decode(String.self, forKey: .sender)
        subject = try values.decode(String.self, forKey: .subject)
        if let receivedString = try? values.decode(String.self, forKey: .received) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsedDate = formatter.date(from: receivedString) {
                received = parsedDate
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                guard let parsedDate = formatter.date(from: receivedString) else {
                    throw DecodingError.dataCorruptedError(forKey: .received, in: values, debugDescription: "Invalid ISO8601 date")
                }
                received = parsedDate
            }
        } else if let referenceSeconds = try? values.decode(Double.self, forKey: .received) {
            // JSONEncoder's synthesized Date representation is seconds since 2001-01-01.
            received = Date(timeIntervalSinceReferenceDate: referenceSeconds)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .received, in: values, debugDescription: "Expected ISO8601 string or encoded Date")
        }
        unread = try values.decode(Bool.self, forKey: .unread)
        replied = try values.decode(Bool.self, forKey: .replied)
        flagged = try values.decode(Bool.self, forKey: .flagged)
    }
}

struct MailSnapshot: Codable, Sendable {
    let messages: [MailMessage]
    let accounts: [MailAccount]
    let errors: [String]
    var timedOut: Bool? = nil
}

extension MailSnapshot {
    func retainingFailedAccounts(from previous: MailSnapshot, now: Date = .now) -> MailSnapshot {
        let known = accounts + previous.accounts
        let failed = Set(known.filter { account in errors.contains { $0.hasPrefix("Account " + account.id + ":") } }.map(\.id))
        let retainAll = errors.contains { $0.hasPrefix("Mail:") }
        let successful = Set(accounts.map(\.id)).subtracting(failed)
        let retained = previous.messages.filter { (retainAll || failed.contains($0.accountID)) && !successful.contains($0.accountID) }
        var byID: [String: MailMessage] = [:]
        for message in retained + messages where message.received >= now.addingTimeInterval(-30 * 86400) { byID[message.id] = message }
        var byAccount: [String: MailAccount] = [:]
        for account in previous.accounts where retainAll || failed.contains(account.id) { byAccount[account.id] = account }
        for account in accounts { byAccount[account.id] = account }
        return MailSnapshot(messages: byID.values.sorted { $0.received > $1.received }, accounts: byAccount.values.sorted { $0.title < $1.title }, errors: errors, timedOut: timedOut)
    }
}

actor MailService {
    private let scriptURL: URL?
    private let timeout: TimeInterval

    init(scriptURL: URL? = Bundle.main.url(forResource: "MailReader", withExtension: "js"), timeout: TimeInterval = 45) {
        self.scriptURL = scriptURL
        self.timeout = timeout
    }

    func headers() async throws -> MailSnapshot {
        let discovery = try JSONDecoder().decode(MailDiscovery.self, from: run(arguments: ["operation": "probe"]))
        var messages: [MailMessage] = []
        var errors = discovery.errors
        var timedOut = false
        // Each account has its own serial helper and timeout. Preserve a healthy
        // account's result even if the other account stalls or denies access.
        for account in discovery.accounts {
            do {
                let data = try run(arguments: ["operation": "headers", "accountID": account.id])
                let snapshot = try JSONDecoder().decode(MailSnapshot.self, from: data)
                messages.append(contentsOf: snapshot.messages)
                errors.append(contentsOf: snapshot.errors)
            } catch {
                if case MailServiceError.timedOut = error { timedOut = true }
                errors.append("Account \(account.id): \(error.localizedDescription)")
            }
        }
        return MailSnapshot(messages: messages.sorted { $0.received > $1.received }, accounts: discovery.accounts, errors: errors, timedOut: timedOut)
    }

    func body(accountID: String, messageID: Int, expectedInternetMessageID: String? = nil) async throws -> String {
        let data = try run(arguments: [
            "operation": "body",
            "accountID": accountID,
            "messageID": messageID
        ])
        let response = try JSONDecoder().decode(BodyResponse.self, from: data)
        if let error = response.errors.first {
            throw MailServiceError.mail(error)
        }
        if let expected = expectedInternetMessageID, !expected.isEmpty, expected != response.internetMessageID {
            throw MailServiceError.mail("This message changed or moved. Refresh the inbox before previewing it.")
        }
        if let before = response.unreadBefore, let after = response.unreadAfter, before != after {
            throw MailServiceError.mail("Mail changed the read state during preview retrieval. Refresh Mail before continuing.")
        }
        return response.body
    }

    private func run(arguments: [String: Any]) throws -> Data {
        guard let scriptURL, FileManager.default.isReadableFile(atPath: scriptURL.path) else {
            throw MailServiceError.scriptUnavailable
        }
        let inputData = try JSONSerialization.data(withJSONObject: arguments)
        guard let input = String(data: inputData, encoding: .utf8) else {
            throw MailServiceError.invalidInput
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", scriptURL.path, input]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Drain both pipes as the process runs so a large inbox cannot block osascript.
        let outputData = LockedData()
        let errorData = LockedData()
        let outputRead = DispatchSemaphore(value: 0)
        let errorRead = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            outputData.set(outputPipe.fileHandleForReading.readDataToEndOfFile())
            outputRead.signal()
        }
        DispatchQueue.global(qos: .utility).async {
            errorData.set(errorPipe.fileHandleForReading.readDataToEndOfFile())
            errorRead.signal()
        }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForWriting.closeFile()
            errorPipe.fileHandleForWriting.closeFile()
            outputPipe.fileHandleForReading.closeFile()
            errorPipe.fileHandleForReading.closeFile()
            throw MailServiceError.launch(error.localizedDescription)
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                let killer = Process()
                killer.executableURL = URL(fileURLWithPath: "/bin/kill")
                killer.arguments = ["-KILL", String(process.processIdentifier)]
                do {
                    try killer.run()
                    killer.waitUntilExit()
                    _ = exited.wait(timeout: .now() + 2)
                } catch {
                    // Preserve the timeout result if the fallback kill command cannot launch.
                }
            }
            throw MailServiceError.timedOut
        }
        _ = outputRead.wait(timeout: .now() + 2)
        _ = errorRead.wait(timeout: .now() + 2)

        let stdout = outputData.get()
        let stderr = errorData.get()
        guard process.terminationStatus == 0 else {
            let detail = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw MailServiceError.process(detail.isEmpty ? "osascript exited with status \(process.terminationStatus)" : detail)
        }
        guard !stdout.isEmpty else {
            throw MailServiceError.process("osascript returned no JSON")
        }
        return stdout
    }
}

private struct MailDiscovery: Decodable {
    let accounts: [MailAccount]
    let errors: [String]
}

private struct BodyResponse: Decodable {
    let body: String
    let internetMessageID: String
    let unreadBefore: Bool?
    let unreadAfter: Bool?
    let errors: [String]
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Data()

    func set(_ data: Data) {
        lock.lock()
        value = data
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

enum MailServiceError: LocalizedError {
    case scriptUnavailable
    case invalidInput
    case launch(String)
    case timedOut
    case process(String)
    case mail(String)

    var errorDescription: String? {
        switch self {
        case .scriptUnavailable:
            return "MailReader.js was not found in the app bundle."
        case .invalidInput:
            return "Could not encode the Mail request."
        case .launch(let message):
            return "Could not start Mail reader: \(message)"
        case .timedOut:
            return "Mail did not respond within 45 seconds."
        case .process(let message), .mail(let message):
            return message
        }
    }
}
