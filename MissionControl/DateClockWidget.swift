import SwiftUI

struct DateClockWidget:View {
    @Binding var configuration:WidgetConfiguration
    private var showsTime:Bool { configuration.clockShowsTime ?? true }
    private var seconds:Bool { configuration.clockShowsSeconds ?? false }
    var body:some View {
        TimelineView(.periodic(from:.now,by:seconds && showsTime ? 1 : 30)) { context in
            VStack(spacing:8) {
                HStack {
                    Text(context.date.formatted(.dateTime.weekday(.wide))).font(.subheadline.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Menu {
                        Picker("Layout",selection:Binding(get:{configuration.clockStyle ?? "auto"},set:{configuration.clockStyle=$0})) { Text("Adaptive").tag("auto");Text("Digital").tag("digital");Text("Calendar").tag("calendar") }
                        Picker("Alignment",selection:Binding(get:{configuration.clockAlignment ?? "centre"},set:{configuration.clockAlignment=$0})) { Text("Centre").tag("centre");Text("Leading").tag("leading") }
                        Divider()
                        Toggle("Show clock",isOn:Binding(get:{showsTime},set:{configuration.clockShowsTime=$0}))
                        Toggle("Show seconds",isOn:Binding(get:{seconds},set:{configuration.clockShowsSeconds=$0})).disabled(!showsTime)
                        Toggle("24-hour time",isOn:Binding(get:{configuration.clockUses24Hour ?? false},set:{configuration.clockUses24Hour=$0})).disabled(!showsTime)
                    } label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width:22).accessibilityLabel("Date and clock options")
                }.fixedSize(horizontal:false,vertical:true)
                DateClockFace(date:context.date,configuration:configuration)
            }.padding(16)
        }
    }
}
struct DateClockFace:View {
    var date:Date
    var configuration:WidgetConfiguration
    private var showsTime:Bool { configuration.clockShowsTime ?? true }
    private var seconds:Bool { configuration.clockShowsSeconds ?? false }
    private var leading:Bool { configuration.clockAlignment == "leading" }
    private var time:String {
        if configuration.clockUses24Hour == true {
            var calendar=Calendar.current;calendar.timeZone = .current
            let parts=calendar.dateComponents([.hour,.minute,.second],from:date)
            return String(format:seconds ? "%02d:%02d:%02d" : "%02d:%02d",arguments:seconds ? [parts.hour ?? 0,parts.minute ?? 0,parts.second ?? 0] : [parts.hour ?? 0,parts.minute ?? 0])
        }
        return seconds ? date.formatted(.dateTime.hour().minute().second()) : date.formatted(date:.omitted,time:.shortened)
    }
    var body:some View {
        GeometryReader { geometry in
            let size=geometry.size,style=configuration.clockStyle ?? "auto"
            let horizontal=style == "auto" && size.width > size.height*1.8 && showsTime
            let alignment:HorizontalAlignment=leading ? .leading : .center
            Group {
                if style == "calendar" {
                    VStack(alignment:alignment,spacing:4) {
                        Text(date.formatted(.dateTime.day())).font(.system(size:min(180,max(36,min(size.width*0.42,size.height*0.5))),weight:.semibold,design:.rounded))
                        Text(date.formatted(.dateTime.month(.wide).year())).font(.system(size:min(32,max(16,size.height*0.1)),weight:.medium,design:.rounded)).foregroundStyle(.secondary)
                        if showsTime { Text(time).font(.system(size:min(42,max(18,size.height*0.14)),weight:.light,design:.rounded)).monospacedDigit() }
                    }
                } else if horizontal {
                    HStack(spacing:24) {
                        VStack(alignment:alignment,spacing:4) {
                            Text(date.formatted(.dateTime.day())).font(.system(size:min(140,max(32,size.height*0.55)),weight:.semibold,design:.rounded))
                            Text(date.formatted(.dateTime.month(.wide))).font(.system(size:min(32,max(15,size.height*0.12)),weight:.medium,design:.rounded)).foregroundStyle(.secondary)
                        }.frame(maxWidth:.infinity,alignment:leading ? .leading : .center)
                        Text(time).font(.system(size:min(180,max(28,min(size.width*0.065,size.height*0.38))),weight:.light,design:.rounded)).monospacedDigit().frame(maxWidth:.infinity)
                    }
                } else {
                    VStack(alignment:alignment,spacing:10) {
                        Text(date.formatted(.dateTime.day().month(.wide))).font(.system(size:min(46,max(20,min(size.width*0.095,size.height*0.18))),weight:.medium,design:.rounded)).foregroundStyle(showsTime ? .secondary : .primary)
                        if showsTime { Text(time).font(.system(size:min(180,max(28,min(size.width/(seconds ? 5.5 : 4.2),size.height*0.4))),weight:.light,design:.rounded)).monospacedDigit() }
                    }
                }
            }.lineLimit(1).minimumScaleFactor(0.5).frame(width:size.width,height:size.height,alignment:leading ? .leading : .center)
        }
    }
}
