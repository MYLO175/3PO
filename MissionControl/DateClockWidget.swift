import SwiftUI

struct DateClockWidget: View {
    @Binding var configuration: WidgetConfiguration
    private var showsTime: Bool { configuration.clockShowsTime ?? true }
    private var seconds: Bool { configuration.clockShowsSeconds ?? false }
    var body: some View {
        TimelineView(.periodic(from:.now,by:seconds && showsTime ? 1 : 30)) { context in
            GeometryReader { geometry in
                VStack(alignment:.leading,spacing:8) {
                    HStack {
                        Text(context.date.formatted(.dateTime.weekday(.wide))).font(.subheadline.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Menu {
                            Toggle("Show clock",isOn:Binding(get:{ showsTime },set:{ configuration.clockShowsTime = $0 }))
                            Toggle("Show seconds",isOn:Binding(get:{ seconds },set:{ configuration.clockShowsSeconds = $0 })).disabled(!showsTime)
                        } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).frame(width:22).accessibilityLabel("Date and clock options")
                    }
                    Spacer(minLength:0)
                    Text(context.date.formatted(.dateTime.day().month(.wide))).font(.system(size:min(40,max(23,geometry.size.width/10)),weight:.semibold,design:.rounded)).lineLimit(1).minimumScaleFactor(0.65)
                    if showsTime {
                        Text(seconds ? context.date.formatted(.dateTime.hour().minute().second()) : context.date.formatted(date:.omitted,time:.shortened)).font(.system(size:min(52,max(28,geometry.size.width/7)),weight:.light,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    }
                    Spacer(minLength:0)
                }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading)
            }.padding(16)
        }
    }
}
