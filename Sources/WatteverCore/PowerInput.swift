import Foundation
import IOKit

public enum BatteryClock: Equatable, Sendable {
  case full
  case untilFull(minutes: Int)
  case untilEmpty(minutes: Int)
}

public struct PowerNow: Equatable, Sendable {
  public var usageWatts: Double?
  public var inputWatts: Double?
  public var battery: BatteryClock?

  public init(usageWatts: Double?, inputWatts: Double?, battery: BatteryClock? = nil) {
    self.usageWatts = usageWatts
    self.inputWatts = inputWatts
    self.battery = battery
  }
}

public func formatBatteryClock(_ clock: BatteryClock) -> String {
  switch clock {
  case .full:
    return "full"
  case .untilFull(let minutes):
    return "\(formatMinutes(minutes)) to full"
  case .untilEmpty(let minutes):
    return "\(formatMinutes(minutes)) to empty"
  }
}

private func formatMinutes(_ minutes: Int) -> String {
  if minutes < 1 { return "< 1 min" }
  let hours = minutes / 60
  let rest = minutes % 60
  if hours == 0 { return "\(rest) min" }
  if rest == 0 { return "\(hours) h" }
  return "\(hours) h \(rest) min"
}

public enum PowerInput {
  /// Whole-machine draw from `SystemLoad` (milliwatts), and adapter input while plugged in.
  ///
  /// While charging, system load is adapter input minus power going into the battery.
  /// `SystemVoltageIn` is millivolts and `SystemCurrentIn` is milliamps. `SystemPowerIn` is the same input in milliwatts.
  public static func now(in properties: [String: Any]) -> PowerNow {
    let telemetry = dictionary(properties["PowerTelemetryData"]) ?? [:]
    return PowerNow(
      usageWatts: plausible(milliwatts: doubleValue(telemetry["SystemLoad"])),
      inputWatts: inputWatts(in: telemetry, connected: isConnected(properties["ExternalConnected"])),
      battery: batteryClock(in: properties)
    )
  }

  /// Time until the battery is empty or full.
  ///
  /// `AvgTimeToEmpty` and `AvgTimeToFull` are minutes. `65535` means the gauge has no estimate.
  /// The fallback is milliamp-hours over `Amperage` (positive while charging, negative while discharging).
  /// `AppleRawCurrentCapacity` is milliamp-hours. `CurrentCapacity` is a percentage, so it is not used.
  public static func batteryClock(in properties: [String: Any]) -> BatteryClock? {
    guard properties["FullyCharged"] != nil || properties["AppleRawCurrentCapacity"] != nil
      || properties["CurrentCapacity"] != nil
    else { return nil }

    let charging = isConnected(properties["IsCharging"])
    if isConnected(properties["FullyCharged"]), !charging { return .full }
    if charging {
      guard let minutes = publishedMinutes(in: properties, keys: ["AvgTimeToFull", "TimeRemaining"])
        ?? chargeMinutes(in: properties)
      else { return nil }
      return .untilFull(minutes: minutes)
    }
    guard !isConnected(properties["ExternalConnected"]) else { return nil }
    guard let minutes = publishedMinutes(in: properties, keys: ["AvgTimeToEmpty", "TimeRemaining"])
      ?? emptyMinutes(in: properties)
    else { return nil }
    return .untilEmpty(minutes: minutes)
  }

  public static func watts(in properties: [String: Any]) -> Double? {
    now(in: properties).inputWatts
  }

  public static func now() -> PowerNow {
    guard let raw = copyProperties() else { return PowerNow(usageWatts: nil, inputWatts: nil) }
    return now(in: raw)
  }

  public static func current() -> Double? {
    now().inputWatts
  }
}

private func inputWatts(in telemetry: [String: Any], connected: Bool) -> Double? {
  guard connected else { return nil }
  if let millivolts = doubleValue(telemetry["SystemVoltageIn"]),
    let milliamps = doubleValue(telemetry["SystemCurrentIn"]),
    millivolts > 0, milliamps > 0
  {
    let watts = millivolts * milliamps / 1_000_000
    if (0.5...500).contains(watts) { return watts }
  }
  return plausible(milliwatts: doubleValue(telemetry["SystemPowerIn"]), floor: 0.5)
}

private let publishedMinuteRange = 1...2_880

private func publishedMinutes(in properties: [String: Any], keys: [String]) -> Int? {
  for key in keys {
    guard let value = doubleValue(properties[key]) else { continue }
    let minutes = Int(value.rounded())
    if publishedMinuteRange.contains(minutes) { return minutes }
  }
  return nil
}

private func chargeMinutes(in properties: [String: Any]) -> Int? {
  guard let milliamps = doubleValue(properties["Amperage"]), milliamps > 1,
    let current = doubleValue(properties["AppleRawCurrentCapacity"]),
    let capacity = doubleValue(properties["AppleRawMaxCapacity"])
  else { return nil }
  return minutes(milliampHours: capacity - current, milliamps: milliamps)
}

private func emptyMinutes(in properties: [String: Any]) -> Int? {
  guard let milliamps = doubleValue(properties["Amperage"]), milliamps < -1,
    let current = doubleValue(properties["AppleRawCurrentCapacity"])
  else { return nil }
  return minutes(milliampHours: current, milliamps: -milliamps)
}

private func minutes(milliampHours: Double, milliamps: Double) -> Int? {
  guard milliampHours >= 0, milliamps > 1 else { return nil }
  let minutes = Int((milliampHours / milliamps * 60).rounded())
  guard (0...2_880).contains(minutes) else { return nil }
  return minutes
}

private func plausible(milliwatts: Double?, floor: Double = 0.05) -> Double? {
  guard let milliwatts, milliwatts > 0 else { return nil }
  let watts = milliwatts / 1000
  guard (floor...500).contains(watts) else { return nil }
  return watts
}

private func copyProperties() -> [String: Any]? {
  let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
  guard service != 0 else { return nil }
  defer { IOObjectRelease(service) }
  var properties: Unmanaged<CFMutableDictionary>?
  guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
    let properties
  else { return nil }
  return properties.takeRetainedValue() as? [String: Any]
}

private func isConnected(_ value: Any?) -> Bool {
  switch value {
  case let flag as Bool:
    return flag
  case let number as NSNumber:
    return number.boolValue
  case let text as String:
    return text == "Yes" || text == "true"
  default:
    return false
  }
}

private func dictionary(_ value: Any?) -> [String: Any]? {
  if let dict = value as? [String: Any] { return dict }
  guard let dict = value as? NSDictionary else { return nil }
  var converted: [String: Any] = [:]
  for (key, value) in dict {
    guard let key = key as? String else { continue }
    converted[key] = value
  }
  return converted
}

private func doubleValue(_ value: Any?) -> Double? {
  switch value {
  case let number as Double:
    return number
  case let number as Int:
    return Double(number)
  case let number as NSNumber:
    return number.doubleValue
  default:
    return nil
  }
}
