import SwiftUI
import AppKit

struct WeatherWidgetView:View {
    @Bindable var weather:WeatherService
    @Environment(\.widgetLayout) private var layout
    var body:some View {
        Group {
            if layout.compact,weather.enabled,weather.allowed,let forecast=weather.forecast,let today=forecast.today() { glance(today:today,forecast:forecast) }
            else { full }
        }.onAppear { weather.startRefresh() }
    }
    /// Today's temperature and sky, with the coming days beside or below once there is room.
    private func glance(today:WeatherDay,forecast:WeatherForecast)->some View {
        VStack(alignment:.leading,spacing:layout == .small ? 6 : 10) {
            WidgetHeader(title:"Weather",symbol:"cloud.sun") {
                if layout != .small {
                    if weather.loading { ProgressView().controlSize(.small) }
                    Button { weather.startRefresh(allowPrompt:true,force:true) } label:{Image(systemName:"arrow.clockwise")}
                        .buttonStyle(.borderless).help("Refresh nearby forecast").accessibilityLabel("Refresh weather").disabled(weather.loading)
                }
            }.fixedSize(horizontal:false,vertical:true)
            if layout == .tall {
                WeatherTodayGlance(today:today)
                WeatherDaysGlance(today:today,days:forecast.days,timezone:forecast.timezone,vertical:true)
            } else {
                HStack(alignment:.top,spacing:18) {
                    WeatherTodayGlance(today:today)
                    if layout == .medium { WeatherDaysGlance(today:today,days:forecast.days,timezone:forecast.timezone,vertical:false) }
                }
            }
            Spacer(minLength:0)
            Link(layout == .small ? "Open-Meteo" : "Open-Meteo · Nearby area",destination:WeatherRules.provider).font(.caption2).lineLimit(1)
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
    private var full:some View {
        VStack(alignment:.leading,spacing:10) {
            WidgetHeader(title:"Weather",symbol:"cloud.sun") {
                if weather.loading { ProgressView().controlSize(.small) }
                Button { weather.startRefresh(allowPrompt:true,force:true) } label:{Image(systemName:"arrow.clockwise")}
                    .buttonStyle(.borderless).help("Refresh nearby forecast").accessibilityLabel("Refresh weather")
                    .disabled(!weather.enabled || weather.loading || (!weather.allowed && weather.authorization != .notDetermined))
            }.fixedSize(horizontal:false,vertical:true)
            if weather.enabled,weather.allowed,let forecast=weather.forecast,let today=forecast.today() {
                WeatherForecastFace(today:today,days:forecast.days,timezone:forecast.timezone)
                HStack(alignment:.firstTextBaseline) {
                    Link("Open-Meteo · Nearby area",destination:WeatherRules.provider)
                    Spacer(minLength:4)
                    Text(forecast.fetched.formatted(date:.omitted,time:.shortened)).foregroundStyle(.secondary)
                }.font(.caption2).fixedSize(horizontal:false,vertical:true)
                if let error=weather.error { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2) }
            } else {
                VStack(spacing:12) {
                    Image(systemName:"cloud.sun").font(.system(size:42,weight:.light)).foregroundStyle(.secondary)
                    Text(weather.enabled ? "Your nearby forecast" : "Local weather is off").font(.headline)
                    Text(weather.status).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if !weather.enabled { Button("Enable local weather") { weather.enabled=true } }
                    else if !weather.allowed {
                        if weather.authorization == .notDetermined { Button("Use my location") { weather.startRefresh(allowPrompt:true,force:true) }.disabled(weather.loading) }
                        else { Button("Location settings") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!) } }
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
}
private func weatherTemperature(_ value:Double)->String { value.formatted(.number.precision(.fractionLength(0)))+"°" }
private struct WeatherTodayGlance:View {
    var today:WeatherDay
    @Environment(\.workspacePalette) private var palette
    var body:some View {
        VStack(alignment:.leading,spacing:2) {
            HStack(alignment:.center,spacing:8) {
                Image(systemName:today.symbol).symbolRenderingMode(.hierarchical).foregroundStyle(palette[.accent]).font(.system(size:26,weight:.light))
                Text(weatherTemperature(today.high)).font(.system(size:34,weight:.light,design:.rounded)).monospacedDigit().rollingNumber(today.high)
            }
            Text(today.description).font(.callout.weight(.medium)).lineLimit(1)
            Text("Low \(weatherTemperature(today.low)) · \(Int(today.rainChance))% rain").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.fixedSize().accessibilityElement(children:.combine)
    }
}
/// The coming days after today: columns across a wide widget, rows down a tall one.
private struct WeatherDaysGlance:View {
    var today:WeatherDay
    var days:[WeatherDay]
    var timezone:String
    var vertical:Bool
    @Environment(\.workspacePalette) private var palette
    private func label(_ day:WeatherDay)->String {
        let parser=DateFormatter();parser.locale=Locale(identifier:"en_US_POSIX");parser.timeZone=TimeZone(identifier:timezone);parser.dateFormat="yyyy-MM-dd"
        guard let date=parser.date(from:day.date) else { return day.date }
        let formatter=DateFormatter();formatter.timeZone=parser.timeZone;formatter.dateFormat="EEE";return formatter.string(from:date)
    }
    var body:some View {
        let coming=days.filter{$0.date > today.date}
        if vertical {
            VStack(alignment:.leading,spacing:7) {
                ForEach(coming.prefix(6)) { day in
                    HStack(spacing:8) {
                        Text(label(day)).font(.callout.weight(.medium)).frame(width:38,alignment:.leading)
                        Image(systemName:day.symbol).symbolRenderingMode(.hierarchical).foregroundStyle(palette[.accent]).frame(width:22)
                        Spacer(minLength:4)
                        Text(weatherTemperature(day.high)).font(.callout.monospacedDigit())
                        Text(weatherTemperature(day.low)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }.accessibilityElement(children:.combine)
                }
            }
        } else {
            ViewThatFits(in:.horizontal) {
                ForEach([6,5,4,3,2,1],id:\.self) { count in columns(Array(coming.prefix(count))) }
            }
        }
    }
    private func columns(_ shown:[WeatherDay])->some View {
        HStack(spacing:6) {
            ForEach(shown) { day in
                VStack(spacing:5) {
                    Text(label(day)).font(.caption.weight(.medium))
                    Image(systemName:day.symbol).symbolRenderingMode(.hierarchical).foregroundStyle(palette[.accent]).font(.system(size:16)).frame(height:20)
                    HStack(spacing:4) { Text(weatherTemperature(day.high)); Text(weatherTemperature(day.low)).foregroundStyle(.secondary) }.font(.caption.monospacedDigit())
                }.frame(width:58).padding(.vertical,8).background(palette[.assistantBubble].opacity(0.55),in:RoundedRectangle(cornerRadius:12))
                    .accessibilityElement(children:.combine)
            }
        }
    }
}

struct WeatherForecastFace:View {
    var today:WeatherDay
    var days:[WeatherDay]
    var timezone:String
    @Environment(\.workspacePalette) private var palette
    private func temperature(_ value:Double)->String { value.formatted(.number.precision(.fractionLength(0)))+"°" }
    private func label(_ day:WeatherDay)->String {
        if day.id == today.id { return "Today" }
        let parser=DateFormatter();parser.locale=Locale(identifier:"en_US_POSIX");parser.timeZone=TimeZone(identifier:timezone);parser.dateFormat="yyyy-MM-dd"
        guard let date=parser.date(from:day.date) else { return day.date }
        let formatter=DateFormatter();formatter.timeZone=parser.timeZone;formatter.dateFormat="EEE";return formatter.string(from:date)
    }
    var body:some View {
        GeometryReader { bounds in
        let compact=bounds.size.height < 155
        VStack(alignment:.leading,spacing:compact ? 6 : 10) {
            GeometryReader { geometry in
                let size=geometry.size
                HStack(spacing:16) {
                    Image(systemName:today.symbol).symbolRenderingMode(.hierarchical).foregroundStyle(palette[.accent])
                        .font(.system(size:max(18,min(size.height*0.62,size.width*0.23)),weight:.light)).frame(width:size.width*0.32)
                    VStack(alignment:.leading,spacing:2) {
                        Text(temperature(today.high)).font(.system(size:max(18,min(size.height*0.54,size.width*0.27)),weight:.light,design:.rounded)).monospacedDigit().rollingNumber(today.high)
                        Text(today.description).font((bounds.size.height < 85 ? Font.caption : Font.callout).weight(.medium)).lineLimit(1)
                        if bounds.size.height >= 85 { Text("Forecast high · Low \(temperature(today.low))C").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }.frame(width:size.width,height:size.height)
            }
            if bounds.size.height >= 65 { HStack {
                Label("\(Int(today.rainChance))% rain",systemImage:"drop.fill")
                Spacer(minLength:4)
                Label("Up to \(Int(today.windKmh)) km/h",systemImage:"wind")
            }.font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75) }
            if !compact { HStack(spacing:8) {
                ForEach(days.filter{$0.date >= today.date}.prefix(3)) { day in
                    VStack(spacing:5) {
                        Text(label(day)).font(.caption.weight(.medium))
                        HStack(spacing:5) { Image(systemName:day.symbol).foregroundStyle(palette[.accent]);Text(temperature(day.high));Text(temperature(day.low)).foregroundStyle(.secondary) }.font(.caption)
                    }.frame(maxWidth:.infinity).padding(.vertical,9).background(palette[.assistantBubble].opacity(0.65),in:RoundedRectangle(cornerRadius:12))
                }
            }.fixedSize(horizontal:false,vertical:true) }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        }
    }
}
