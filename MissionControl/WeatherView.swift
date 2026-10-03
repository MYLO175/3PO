import SwiftUI
import AppKit

struct WeatherSettings: View {
    @Bindable var weather: WeatherService
    var body: some View {
        Section("Local weather") {
            Toggle("Use nearby weather in the PA and morning brief",isOn:$weather.enabled)
            Text(weather.status).font(.caption).foregroundStyle(weather.error == nil ? Color.secondary : Color.orange)
            HStack {
                Button(weather.allowed ? "Refresh forecast" : "Request location") { weather.startRefresh(allowPrompt:true,force:true) }.disabled(!weather.enabled || weather.loading || (weather.authorization != .notDetermined && !weather.allowed))
                Button("Location settings") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!) }
            }
            Text("One location check per refresh. Coordinates are rounded to a nearby area (about 11 km) before requesting Open-Meteo. The PA receives the forecast, never coordinates. No AI request is made by weather refresh.").font(.caption).foregroundStyle(.secondary)
            Link("Forecast by Open-Meteo",destination:WeatherRules.provider).font(.caption)
        }
    }
}
struct WeatherBriefCard: View {
    @Bindable var weather: WeatherService
    var body: some View {
        if weather.enabled {
            VStack(alignment:.leading,spacing:5) {
                if weather.allowed, let forecast = weather.forecast, forecast.usable(), let today = forecast.days.first {
                    Label("\(today.description) · \(today.low.formatted(.number.precision(.fractionLength(0))))–\(today.high.formatted(.number.precision(.fractionLength(0))))°C",systemImage:"cloud.sun").font(.callout.weight(.medium))
                    Text("Rain chance \(Int(today.rainChance))% · Wind up to \(Int(today.windKmh)) km/h").font(.caption)
                    Text(weather.status).font(.caption2).foregroundStyle(.secondary)
                    Link("Open-Meteo · Nearby area",destination:WeatherRules.provider).font(.caption2)
                } else {
                    Label(weather.status,systemImage:"cloud.sun").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth:.infinity,alignment:.leading).padding(10).background(.quaternary,in:RoundedRectangle(cornerRadius:10))
        }
    }
}
