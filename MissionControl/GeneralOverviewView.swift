import SwiftUI

struct GeneralOverviewView: View {
    @Bindable var model: DashboardModel
    @Bindable var briefings: BriefingService
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.firstTextBaseline) {
                VStack(alignment:.leading,spacing:3) {
                    Text("What's going on").font(.title3.weight(.semibold))
                    Text("Your next few days, in focus").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength:8)
                Button { briefings.checkOverview(model,manual:true) } label: { Image(systemName:"arrow.clockwise") }
                    .help("Update overview").accessibilityLabel("Update overview")
                    .disabled(!model.assistant.contextEnabled || !model.chatGPT.inferenceVerified || model.chatGPT.usagePaused || model.chatGPT.busy || briefings.busy || model.emailSummaries.busy)
                if briefings.busy { ProgressView().controlSize(.small); Button("Stop") { briefings.cancel() } }
            }
            if model.chatGPT.usagePaused {
                HStack(alignment:.top,spacing:8) {
                    Image(systemName:"pause.circle").foregroundStyle(.orange)
                    VStack(alignment:.leading,spacing:5) {
                        Text("AI updates paused").font(.callout.weight(.medium))
                        Text("Subscription access was rejected. Your saved overview and Apple sources are still available.").font(.caption).foregroundStyle(.secondary)
                        Button("Check access") { model.chatGPT.testConnection() }.controlSize(.small).disabled(model.chatGPT.busy || model.assistant.busy)
                    }
                }.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(.orange.opacity(0.07),in:RoundedRectangle(cornerRadius:10))
            } else if briefings.state.overviewPaused == true {
                Label("Overview paused · Update overview to try again",systemImage:"pause.circle").font(.caption).foregroundStyle(.orange)
                if let error = briefings.error { DisclosureGroup("Details") { Text(error).font(.caption).textSelection(.enabled) } }
            }
            if let record = briefings.overview(model) {
                Text("Updated \(record.created.formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:10) {
                        ForEach(Array(record.items.enumerated()),id:\.element.id) { index,item in
                            HStack(alignment:.top,spacing:10) {
                                Text("\(index+1)").font(.caption.weight(.semibold)).monospacedDigit()
                                    .frame(width:24,height:24).foregroundStyle(Color.accentColor)
                                    .background(Color.accentColor.opacity(0.1),in:Circle())
                                VStack(alignment:.leading,spacing:8) {
                                    Text(item.text).font(.callout).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                                    ForEach(item.sourceIDs,id:\.self) { id in
                                        if let source = record.sources.first(where: { $0.id == id }) {
                                            if source.kind == "mail", let message = model.emailSummaries.memories(model).first(where: { $0.0.id == source.originalID })?.0 {
                                                Button { model.select(message) } label: { Label(source.label,systemImage:"envelope") }.buttonStyle(.link).font(.caption).lineLimit(2)
                                            } else {
                                                Label(source.label,systemImage:source.kind == "calendar" ? "calendar" : "checklist").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                            }
                                        }
                                    }
                                }.frame(maxWidth:.infinity,alignment:.leading)
                            }.padding(12).background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:12))
                        }
                        DisclosureGroup("Sources and coverage") { Text(record.coverage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }.font(.caption).padding(.top,4)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
            } else {
                ContentUnavailableView {
                    Label(model.assistant.contextEnabled ? "Your overview is waiting" : "Bring your day together",systemImage:"sparkles")
                } description: {
                    Text(!model.assistant.contextEnabled ? "Enable assistant source context in Settings to prioritise your calendar, reminders and relevant incoming mail." : model.chatGPT.usagePaused ? "Check subscription access to create a new overview." : !model.chatGPT.inferenceVerified ? "Verify your ChatGPT connection in Settings first." : briefings.busy ? "Reading your enabled sources and preparing your overview…" : "Choose Update overview when you're ready. Historical mail is read only when you ask.")
                }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
}
