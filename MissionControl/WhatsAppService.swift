import SwiftUI
import AppKit
import Security
import CryptoKit

struct WhatsAppReadMessage: Codable, Identifiable {
    let id: String
    let chat: String
    let sender: String
    let text: String
    let sentByMe: Bool
    let time: Double
}
@MainActor @Observable final class WhatsAppService {
    var status = "Not connected"
    var connected = false
    var qr: NSImage?
    var messages: [WhatsAppReadMessage] = []
    var coverage = "No WhatsApp data received."
    private var process: Process?
    private var input: FileHandle?
    private var reader: WhatsAppOutputReader?
    private var generation=UUID()
    private let directory = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Mission Control/WhatsApp",isDirectory:true)
    private let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"com.mylomichael.missioncontrol.whatsapp",kSecAttrAccount as String:"session-encryption"]
    private func key() throws -> Data {
        var request=query; request[kSecReturnData as String]=true
        var result: CFTypeRef?
        let found=SecItemCopyMatching(request as CFDictionary,&result)
        if found == errSecSuccess, let data=result as? Data { return data }
        guard found == errSecItemNotFound else { throw CocoaError(.fileReadNoPermission) }
        let data=SymmetricKey(size:.bits256).withUnsafeBytes { Data($0) }
        var item=query; item[kSecValueData as String]=data; item[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary,nil)==errSecSuccess else { throw CocoaError(.fileWriteNoPermission) }
        return data
    }
    func connect() {
        guard process == nil else { return }
        guard let root=Bundle.main.resourceURL?.appendingPathComponent("WhatsAppBridge"), FileManager.default.fileExists(atPath:root.appendingPathComponent("reader.mjs").path) else { status="WhatsApp helper is missing from this build."; return }
        guard let node=["/usr/local/bin/node","/opt/homebrew/bin/node"].first(where:{ FileManager.default.isExecutableFile(atPath:$0) }) else { status="This experimental connector requires Node.js 20 or later installed on this Mac."; return }
        do {
            let secret=try key(), task=Process(), incoming=Pipe(), outgoing=Pipe()
            let token=UUID(); generation=token
            task.executableURL=URL(fileURLWithPath:node); task.arguments=[root.appendingPathComponent("reader.mjs").path]
            task.standardInput=incoming; task.standardOutput=outgoing; task.standardError=FileHandle.nullDevice
            let receiver=WhatsAppOutputReader { [weak self] data in Task { @MainActor in if self?.generation == token { self?.receive(data) } } }
            outgoing.fileHandleForReading.readabilityHandler={ handle in receiver.read(handle.availableData) }
            task.terminationHandler={ [weak self] _ in Task { @MainActor in guard self?.generation == token else { return }; self?.process=nil; self?.connected=false; self?.qr=nil; self?.status="Stopped · reconnect to resume reading" } }
            try task.run(); process=task; input=incoming.fileHandleForWriting; reader=receiver; status="Connecting…"
            let command:[String:String]=["action":"start","directory":directory.path,"key":secret.base64EncodedString()]
            try input?.write(contentsOf:JSONSerialization.data(withJSONObject:command)+Data([10]))
        } catch { stop(); status="Cannot start WhatsApp or access its encrypted session." }
    }
    func stop() { generation=UUID(); process?.terminationHandler=nil; input?.closeFile(); process?.terminate(); process=nil; input=nil; reader=nil; connected=false; qr=nil; status="Paused · session retained" }
    func disconnect() {
        stop()
        do { if FileManager.default.fileExists(atPath:directory.path) { try FileManager.default.removeItem(at:directory) }; SecItemDelete(query as CFDictionary); messages=[]; status="Disconnected · also remove Mission Control from WhatsApp’s Linked devices." }
        catch { status="Disconnected, but local encrypted session could not be removed." }
    }
    private func receive(_ data: Data) {
        guard process != nil, let event=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return }
        if let value=event["status"] as? String { status=value }
        if let value=event["connected"] as? Bool { connected=value; if value { qr=nil } }
        if let png=event["png"] as? String, let encoded=png.split(separator:",").last, let image=Data(base64Encoded:String(encoded)) { qr=NSImage(data:image) }
        if let list=event["messages"], let encoded=try? JSONSerialization.data(withJSONObject:list), let values=try? JSONDecoder().decode([WhatsAppReadMessage].self,from:encoded) { messages=values }
        if let value=event["coverage"] as? String { coverage=value }
    }
}
private final class WhatsAppOutputReader: @unchecked Sendable {
    private let lock=NSLock()
    private var buffer=Data()
    private let deliver: (Data)->Void
    init(deliver:@escaping(Data)->Void) { self.deliver=deliver }
    func read(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }; buffer.append(data)
        guard buffer.count < 40_000_000 else { buffer.removeAll(); return }
        while let newline=buffer.firstIndex(of:10) { let line=Data(buffer[..<newline]); buffer.removeSubrange(...newline); deliver(line) }
    }
}
struct WhatsAppSettings: View {
    @Bindable var service: WhatsAppService
    @State private var showMessages=false
    var body: some View {
        Section("WhatsApp · experimental, read-only") {
            Text("Link through a QR code as another device. This uses an unofficial WhatsApp Web connection; WhatsApp changes or account restrictions may interrupt it. No sending, read receipts or automatic AI processing. Sessions and received text are encrypted locally; the encryption key stays in Keychain.").font(.caption).foregroundStyle(.secondary)
            Text(service.status)
            if let qr=service.qr { Image(nsImage:qr).resizable().interpolation(.none).frame(width:240,height:240); Text("On your phone: WhatsApp → Settings → Linked devices → Link a device. Scan this code only if you want Mission Control to receive your chats.").font(.caption) }
            HStack { Button("Connect / show QR") { service.connect() }; Button("Pause") { service.stop() }; Button("Disconnect") { service.disconnect() }; Button("Received text (\(service.messages.count))") { showMessages=true } }
            Text(service.coverage).font(.caption).foregroundStyle(.secondary)
        }.sheet(isPresented:$showMessages) {
            VStack(alignment:.leading) {
                HStack { Text("WhatsApp received text").font(.title2); Spacer(); Button("Done") { showMessages=false } }
                Text(service.coverage).font(.caption).foregroundStyle(.secondary)
                List(service.messages) { message in VStack(alignment:.leading,spacing:4) { Text(message.sender).font(.headline); Text(message.text).textSelection(.enabled); Text(Date(timeIntervalSince1970:message.time/1000),style:.date).font(.caption).foregroundStyle(.secondary) } }
            }.padding(20).frame(width:650,height:550)
        }
    }
}
