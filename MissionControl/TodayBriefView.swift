import SwiftUI

struct TodayBriefView: View {
    @Bindable var model: DashboardModel
    @Bindable var briefings: BriefingService
    @State private var showMemory=false
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Label("Today’s brief",systemImage:"sun.max").font(.title3.weight(.semibold))
                Spacer()
                if briefings.busy { ProgressView().controlSize(.small); Button("Stop") { briefings.cancel() } }
                else { Button { briefings.updateToday(model) } label: { Image(systemName:"arrow.clockwise") }.help(!briefings.hasCurrentToday(model) ? "Prepare today’s brief" : "Update brief with fresh sources; keeps the morning message").accessibilityLabel(!briefings.hasCurrentToday(model) ? "Prepare today’s brief" : "Update today’s brief").disabled(model.heartbeat.busy) }
            }.buttonStyle(.borderless)
            if model.heartbeat.busy && !briefings.busy {Text("The heartbeat will update your brief shortly…").font(.caption).foregroundStyle(.secondary)}
            if briefings.busy { Text(briefings.phase.isEmpty ? "Preparing today’s brief…" : briefings.phase).font(.caption).foregroundStyle(.secondary) }
            if let record = briefings.savedToday(model) ?? briefings.current(model) {
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        WeatherBriefCard(weather:model.weather)
                        if let note=briefings.freshnessNote(record,model:model) {
                            Label(note,systemImage:"clock.arrow.circlepath").font(.caption).foregroundStyle(.secondary).padding(10).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:8))
                        }
                        Text((try? AttributedString(markdown:BriefingRules.prose(record),options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(BriefingRules.prose(record))).font(.callout).lineSpacing(5).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                        if record.morningID != nil, let morning = briefings.savedMorning(model) {
                            DisclosureGroup("Original morning message") {
                                Text((try? AttributedString(markdown:BriefingRules.prose(morning),options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(BriefingRules.prose(morning))).font(.callout).lineSpacing(5).textSelection(.enabled).padding(.top,8)
                            }.font(.caption)
                        }
                        DisclosureGroup("Sources and coverage") {
                            VStack(alignment:.leading,spacing:10) {
                                Text(record.coverage).font(.caption).foregroundStyle(.secondary)
                                MemoryAdviceEvidenceView(model:model,registration:record.registration,dependencies:record.memoryDependencies,use:.brief)
                                ForEach(record.items) { item in
                                    Text((try? AttributedString(markdown:item.text,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(item.text)).font(.caption)
                                    ForEach(item.sourceIDs,id:\.self) { id in
                                        if let source = record.sources.first(where: { $0.id == id }) {
                                            if source.kind == "mail", let message = model.emailSummaries.highlights(model).first(where:{ $0.0.id == source.originalID })?.0 { Button(source.label) { model.select(message) }.buttonStyle(.link).font(.caption) }
                                            else if source.kind == "weather" { Link(source.label,destination:WeatherRules.provider).font(.caption) }
                                            else if source.kind == "whatsapp" { WhatsAppBriefSource(service:model.whatsapp,registration:model.chatGPT.activeID,source:source) }
                                            else if source.kind == "memory" { Button(source.label) { showMemory=true }.buttonStyle(.link).font(.caption) }
                                            else { Label(source.label,systemImage:source.kind == "calendar" ? "calendar" : "checklist").font(.caption).foregroundStyle(.secondary) }
                                        }
                                    }
                                }
                            }.padding(.top,8)
                        }.font(.caption)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
                Text("\(record.morningID == nil && record.heartbeatID == nil && record.widgetOnly != true ? "Prepared" : "Updated") \(record.created.formatted(date:.omitted,time:.shortened)) · Refreshes with each heartbeat").font(.caption2).foregroundStyle(.secondary)
            } else {
                WeatherBriefCard(weather:model.weather)
                ContentUnavailableView("A clear start to your day",systemImage:"sun.horizon",description:Text(!model.assistant.contextEnabled ? "Enable assistant source context in Settings." : briefings.busy ? "Your PA is preparing today’s message…" : briefings.hasCurrentToday(model) ? "Your morning message is saved with earlier source choices. Update the brief to use your current sources." : !briefings.enabled ? "Prepare a brief whenever you like. Automatic 7:30 preparation is optional in Settings." : model.chatGPT.usagePaused ? "Subscription access is paused. Your Apple sources remain available." : "Your PA brings together today’s calendar, reminders and relevant recent mail. Prepared at 7:30, with catch-up after launch or wake."))
            }
            if briefings.current(model) == nil && !briefings.busy { Button(briefings.hasCurrentToday(model) ? "Update brief" : "Prepare brief") { briefings.updateToday(model) }.buttonStyle(.bordered).controlSize(.small).disabled(model.heartbeat.busy) }
            if let error = briefings.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if model.chatGPT.usagePaused { Button("Check subscription access") { model.chatGPT.testConnection() }.controlSize(.small).disabled(model.chatGPT.busy || model.assistant.busy) }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .sheet(isPresented:$showMemory) { PAMemoryView(memory:model.assistant.memory,registration:model.chatGPT.activeID,model:model) }
        .onChange(of:model.chatGPT.activeID) { showMemory=false }
    }
}
