import SwiftUI
struct DiscoveryEvidenceView:View {
    var record:PADiscovery
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text(record.sourceKind == "whatsapp" ? "WhatsApp · " + (record.sourceLabel ?? "Selected chat") : "Source evidence").font(.title3.weight(.semibold))
            Text(record.evidence).textSelection(.enabled)
            Text(record.sourceKind == "whatsapp" ? "This suggestion is based on the quoted message. Linked-device history can be incomplete." : "This suggestion is based on the email’s quoted evidence; other source coverage may be incomplete.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer();Button("Done") { dismiss() } }
        }.padding(24).frame(width:460)
    }
}
