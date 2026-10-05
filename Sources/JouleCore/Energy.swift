import Foundation

public struct ChannelSample: Equatable, Sendable {
  public var name: String
  public var unit: String
  public var raw: Int64

  public init(name: String, unit: String, raw: Int64) {
    self.name = name
    self.unit = unit
    self.raw = raw
  }
}

public struct EnergyReading: Equatable, Sendable {
  public var cpu: Double
  public var gpu: Double
  public var ane: Double
  public var dram: Double
  public var display: Double
  public var other: Double
  public var seconds: Double

  public init(
    cpu: Double, gpu: Double, ane: Double, dram: Double, display: Double, other: Double, seconds: Double
  ) {
    self.cpu = cpu
    self.gpu = gpu
    self.ane = ane
    self.dram = dram
    self.display = display
    self.other = other
    self.seconds = seconds
  }

  public var total: Double { cpu + gpu + ane + dram + display + other }
}

public struct EnergyHistory: Equatable, Sendable {
  public private(set) var count = 0
  public private(set) var minimum = 0.0
  public private(set) var maximum = 0.0
  public private(set) var sum = 0.0

  public init() {}

  public var average: Double { count == 0 ? 0 : sum / Double(count) }

  public mutating func record(_ watts: Double) {
    guard watts.isFinite else { return }
    if count == 0 {
      minimum = watts
      maximum = watts
    } else {
      minimum = min(minimum, watts)
      maximum = max(maximum, watts)
    }
    sum += watts
    count += 1
  }
}

enum EnergyComponent: Equatable {
  case cpu
  // "GPU Energy" is the nanojoule counter. "GPU" is the same quantity in millijoules.
  case gpuPrecise
  case gpuCoarse
  case gpuSRAM
  case ane
  case dram
  case display
  case other
}

func energyComponent(forChannel name: String) -> EnergyComponent? {
  let name = stripDiePrefix(name.trimmingCharacters(in: .whitespacesAndNewlines))
  switch name {
  case "CPU Energy":
    return .cpu
  case "GPU Energy":
    return .gpuPrecise
  case "GPU":
    return .gpuCoarse
  case "GPU SRAM":
    return .gpuSRAM
  case "ANE Energy":
    return .ane
  case "DISP", "DISPEXT":
    return .display
  case "ISP", "AVE", "MSR", "AFR", "AMCC", "DCS", "FAB":
    return .other
  default:
    if name.wholeMatch(of: /ANE\d*/) != nil { return .ane }
    if name.wholeMatch(of: /DRAM\d*(_\d+)?/) != nil { return .dram }
    if name.wholeMatch(of: /PCIe Port \d+ Energy/) != nil { return .other }
    if name.wholeMatch(of: /apciec\d+ Energy/) != nil { return .other }
    return nil
  }
}

public enum EnergyMath {
  /// Intervals shorter than this are quantization noise, not a power reading.
  public static let minimumInterval = 0.05

  public static func joules(raw: Int64, unit: String) -> Double? {
    let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
    let magnitude = Double(max(raw, 0))
    switch unit {
    case "mJ":
      return magnitude / 1e3
    case "uJ":
      return magnitude / 1e6
    case "nJ":
      return magnitude / 1e9
    default:
      return nil
    }
  }

  /// Power over `seconds`, in joules per second.
  ///
  /// Energy Model publishes an aggregate per block and also the pieces that add up to it
  /// (`EACC_CPU0`, cluster totals, DTL rails). Only the aggregates are summed. When both
  /// `GPU` and `GPU Energy` are present they are one counter, and the nanojoule one wins.
  public static func reading(samples: [ChannelSample], seconds: Double) -> EnergyReading? {
    guard seconds.isFinite, seconds >= minimumInterval else { return nil }
    let preciseGPU = samples.contains { energyComponent(forChannel: $0.name) == .gpuPrecise }
    var cpu = 0.0
    var gpu = 0.0
    var ane = 0.0
    var dram = 0.0
    var display = 0.0
    var other = 0.0
    var saw = false
    for sample in samples {
      guard let component = energyComponent(forChannel: sample.name) else { continue }
      if component == .gpuCoarse, preciseGPU { continue }
      guard let joules = joules(raw: sample.raw, unit: sample.unit) else { continue }
      let watts = joules / seconds
      saw = true
      switch component {
      case .cpu:
        cpu += watts
      case .gpuPrecise, .gpuCoarse, .gpuSRAM:
        gpu += watts
      case .ane:
        ane += watts
      case .dram:
        dram += watts
      case .display:
        display += watts
      case .other:
        other += watts
      }
    }
    guard saw else { return nil }
    return EnergyReading(
      cpu: cpu, gpu: gpu, ane: ane, dram: dram, display: display, other: other, seconds: seconds)
  }
}

public func formatWatts(_ watts: Double, fractionDigits: Int) -> String {
  String(format: "%.\(fractionDigits)f W", locale: posix, finiteWatts(watts))
}

/// Menu bar label. Usage is always shown as `-W`. Adapter input is appended as `+W` when the Mac is on external power.
public func menuBarTitle(usageWatts: Double, inputWatts: Double? = nil) -> String {
  let usage = compactWatts(usageWatts, sign: "-")
  guard let inputWatts else { return usage }
  return "\(usage) \(compactWatts(inputWatts, sign: "+"))"
}

func finiteWatts(_ watts: Double) -> Double {
  watts.isFinite ? max(watts, 0) : 0
}

private func compactWatts(_ watts: Double, sign: String) -> String {
  let number = String(format: "%.1f", locale: posix, finiteWatts(watts))
  return "\(sign)\(number)W"
}

private let posix = Locale(identifier: "en_US_POSIX")

private func stripDiePrefix(_ name: String) -> String {
  guard let match = name.wholeMatch(of: /DIE_\d+_(.+)/) else { return name }
  return String(match.1)
}
