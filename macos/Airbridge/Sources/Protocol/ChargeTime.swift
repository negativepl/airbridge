import Foundation

/// Formatuje pozostały czas ładowania (ms) na krótki tekst.
/// Zakłada `ms > 0` — wywołujący sam decyduje, że przy `<= 0` czasu nie pokazuje.
/// PL: „45 min" / „2 godz." / „1 godz. 20 min";  EN: "45 min" / "2 hr" / "1 hr 20 min".
public func formatChargeTime(_ ms: Int64, isPL: Bool) -> String {
    let totalMinutes = Int(ms / 60_000)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    let hourUnit = isPL ? "godz." : "hr"
    if hours == 0 {
        return "\(minutes) min"
    }
    if minutes == 0 {
        return "\(hours) \(hourUnit)"
    }
    return "\(hours) \(hourUnit) \(minutes) min"
}
