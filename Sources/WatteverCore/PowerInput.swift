import Foundation
import IOKit

public enum PowerInput {
  /// Watts coming in from the adapter, or nil on battery and when the sensor is absent.
  ///
  /// `SystemVoltageIn` is millivolts and `SystemCurrentIn` is milliamps on Apple Smart Battery.
  /// `SystemPowerIn` is the same quantity in milliwatts and is the fallback.
  public static func watts(in properties: [String: Any]) -> Double? {
    guard isConnected(properties["ExternalConnected"]) else { return nil }
    guard let telemetry = dictionary(properties["PowerTelemetryData"]) else { return nil }
    if let millivolts = doubleValue(telemetry["SystemVoltageIn"]),
      let milliamps = doubleValue(telemetry["SystemCurrentIn"]),
      millivolts > 0, milliamps > 0
    {
      let watts = millivolts * milliamps / 1_000_000
      if (0.5...500).contains(watts) { return watts }
    }
    if let milliwatts = doubleValue(telemetry["SystemPowerIn"]), milliwatts > 0 {
      let watts = milliwatts / 1000
      if (0.5...500).contains(watts) { return watts }
    }
    return nil
  }

  public static func current() -> Double? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    var properties: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
      let properties
    else { return nil }
    guard let raw = properties.takeRetainedValue() as? [String: Any] else { return nil }
    return watts(in: raw)
  }
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
