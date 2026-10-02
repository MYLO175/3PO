import SwiftUI

struct GeneralOverviewView: View {
    @Bindable var model: DashboardModel
    @Bindable var briefings: BriefingService
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text("What's going on").font(.headline)
                Spacer()
                Button("Update overview") { briefings.checkOverview(model,manual:true) }
                    .disabled(!model.assistant.contextEnabled || !model.chatGPT.inferenceVerified || model.chatGPT.usagePaused || model.chatGPT.busy || briefings.busy || model.emailSummaries.busy)
                if briefings.busy { ProgressView().controlSize(.small); Button("Stop") { briefings.cancel() } }
            }
            if let error = briefings.error { Text(error).font(.caption).foregroundStyle(.orange) }
            if let record = briefings.overview(model) {
                Text("Updated \(record.created.formatted(date:.abbreviated,time:.shortened)) · Next seven days and outstanding work").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:12) {
                        ForEach(record.items) { item in
                            Text(item.text).textSelection(.enabled)
                            ForEach(item.sourceIDs,id:\.self) { id in
                                if let source = record.sources.first(where: { $0.id == id }) {
                                    if source.kind == "mail", let message = model.emailSummaries.memories(model).first(where: { $0.0.id == source.originalID })?.0 {
                                        Button(source.label) { model.select(message) }.buttonStyle(.link).font(.caption)
                                    } else { Text(source.label).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                            Divider()
                        }
                        Text(record.coverage).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
            } else {
                Text(model.assistant.contextEnabled ? "Preparing a prioritised view of your calendar, reminders and relevant incoming mail. Historical emails are read when you ask." : "Enable assistant source context in Settings to prepare your overview.").foregroundStyle(.secondary)
                Spacer()
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
}
