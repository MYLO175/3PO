import SwiftUI

struct TodayBriefView: View {
    @Bindable var model: DashboardModel
    @Bindable var briefings: BriefingService
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Label("Today’s brief",systemImage:"sun.max").font(.title3.weight(.semibold))
                Spacer()
                if briefings.busy { ProgressView().controlSize(.small); Button("Stop") { briefings.cancel() } }
                else { Button { briefings.check(model,manual:true) } label: { Image(systemName:"arrow.clockwise") }.help("Prepare today’s brief").accessibilityLabel("Prepare today’s brief").disabled(briefings.today(model) != nil || !briefings.enabled || !model.assistant.contextEnabled || model.chatGPT.busy || model.assistant.busy || !model.chatGPT.inferenceVerified || model.chatGPT.usagePaused) }
            }
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.caption).foregroundStyle(.secondary)
            if let record = briefings.today(model) {
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        Text((try? AttributedString(markdown:BriefingRules.prose(record),options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(BriefingRules.prose(record))).font(.callout).lineSpacing(5).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                        DisclosureGroup("Sources and coverage") {
                            VStack(alignment:.leading,spacing:10) {
                                Text(record.coverage).font(.caption).foregroundStyle(.secondary)
                                ForEach(record.items) { item in
                                    Text(item.text).font(.caption)
                                    ForEach(item.sourceIDs,id:\.self) { id in
                                        if let source = record.sources.first(where: { $0.id == id }) {
                                            if source.kind == "mail", let message = model.emailSummaries.highlights(model).first(where:{ $0.0.id == source.originalID })?.0 { Button(source.label) { model.select(message) }.buttonStyle(.link).font(.caption) }
                                            else { Label(source.label,systemImage:source.kind == "calendar" ? "calendar" : "checklist").font(.caption).foregroundStyle(.secondary) }
                                        }
                                    }
                                }
                            }.padding(.top,8)
                        }.font(.caption)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
                Text("Prepared \(record.created.formatted(date:.omitted,time:.shortened)) · Saved for today").font(.caption2).foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("A clear start to your day",systemImage:"sun.horizon",description:Text(!model.assistant.contextEnabled ? "Enable assistant source context in Settings." : !briefings.enabled ? "Enable the 7:30 morning brief in Settings, then prepare today’s brief." : model.chatGPT.usagePaused ? "Subscription access is paused. Your Apple sources remain available." : briefings.busy ? "Your PA is preparing today’s message…" : "Your PA brings together today’s calendar, reminders and relevant recent mail. Prepared at 7:30, with catch-up after launch or wake."))
            }
            if let error = briefings.error { DisclosureGroup("Briefing details") { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }.font(.caption) }
            if model.chatGPT.usagePaused { Button("Check subscription access") { model.chatGPT.testConnection() }.controlSize(.small).disabled(model.chatGPT.busy || model.assistant.busy) }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
}
