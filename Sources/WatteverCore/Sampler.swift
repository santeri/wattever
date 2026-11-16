import CoreFoundation
import Foundation
import WatteverSPI

public enum SamplerError: Error, LocalizedError {
  case noChannels
  case noSubscription

  public var errorDescription: String? {
    switch self {
    case .noChannels:
      return "Energy Model channels are not available"
    case .noSubscription:
      return "Could not subscribe to the Energy Model"
    }
  }
}

public final class EnergySampler {
  private let channels: CFDictionary
  private let subscription: IOReportSubscriptionRef
  private let pmpChannels: CFDictionary?
  private let pmpSubscription: IOReportSubscriptionRef?
  private var previous: CFDictionary?
  private var previousPMP: CFDictionary?
  private var previousInstant: ContinuousClock.Instant?

  public init() throws {
    guard let channels = wattever_copy_energy_channels() else {
      throw SamplerError.noChannels
    }
    guard let subscription = wattever_subscribe(channels) else {
      throw SamplerError.noSubscription
    }
    self.channels = channels
    self.subscription = subscription
    if let pmpChannels = wattever_copy_pmp_channels(), let pmpSubscription = wattever_subscribe(pmpChannels) {
      self.pmpChannels = pmpChannels
      self.pmpSubscription = pmpSubscription
    } else {
      self.pmpChannels = nil
      self.pmpSubscription = nil
    }
  }

  deinit {
    wattever_release_subscription(subscription)
    wattever_release_subscription(pmpSubscription)
  }

  /// The first call stores a baseline and returns nil. Each later call returns the
  /// average watts since the previous call.
  public func poll() -> EnergyReading? {
    let now = ContinuousClock.now
    guard let sample = wattever_copy_samples(subscription, channels) else { return nil }
    let pmpSample = pmpSampleNow()
    guard let previous, let previousInstant else {
      self.previous = sample
      self.previousInstant = now
      self.previousPMP = pmpSample
      return nil
    }
    let seconds = secondsBetween(previousInstant, now)
    let priorPMP = previousPMP
    defer {
      self.previous = sample
      self.previousInstant = now
      self.previousPMP = pmpSample
    }
    guard let delta = wattever_copy_delta(previous, sample) else { return nil }
    guard var reading = EnergyMath.reading(samples: readChannels(delta), seconds: seconds) else { return nil }
    let clusters = clusters(since: priorPMP, current: pmpSample)
    let dram = wattever_dram_watts()
    reading = reading.fillingFrozenComponents(cpu: clusters.cpu, gpu: clusters.gpu, dram: dram > 0 ? dram : nil)
    return reading
  }

  private func pmpSampleNow() -> CFDictionary? {
    guard let pmpChannels, let pmpSubscription else { return nil }
    return wattever_copy_samples(pmpSubscription, pmpChannels)
  }

  private func clusters(since previous: CFDictionary?, current: CFDictionary?) -> ClusterWatts {
    guard let previous, let current, let delta = wattever_copy_delta(previous, current) else {
      return ClusterWatts(cpu: nil, gpu: nil)
    }
    return readClusters(delta)
  }
}

private final class SampleList {
  var samples: [ChannelSample] = []
}

private let visitChannel: WatteverVisit = { name, unit, raw, context in
  guard let context else { return }
  let list = Unmanaged<SampleList>.fromOpaque(context).takeUnretainedValue()
  list.samples.append(ChannelSample(name: String(cString: name), unit: String(cString: unit), raw: raw))
}

private func readChannels(_ sample: CFDictionary) -> [ChannelSample] {
  let list = SampleList()
  let context = Unmanaged.passUnretained(list).toOpaque()
  wattever_visit_channels(sample, visitChannel, context)
  return list.samples
}

private final class StateList {
  var bins: [String: [PowerBin]] = [:]
  var names: [String: (subgroup: String, name: String)] = [:]
}

private let visitState: WatteverStateVisit = { name, subgroup, state, residency, context in
  guard let context else { return }
  let list = Unmanaged<StateList>.fromOpaque(context).takeUnretainedValue()
  let channelName = String(cString: name)
  let group = String(cString: subgroup)
  let key = group + "\u{0}" + channelName
  list.names[key] = (group, channelName)
  list.bins[key, default: []].append(PowerBin(label: String(cString: state), residency: residency))
}

private func readClusters(_ sample: CFDictionary) -> ClusterWatts {
  let list = StateList()
  wattever_visit_states(sample, visitState, Unmanaged.passUnretained(list).toOpaque())
  let channels = list.names.map { key, meta in
    PMPChannel(subgroup: meta.subgroup, name: meta.name, bins: list.bins[key] ?? [])
  }
  return clusterWatts(channels)
}

private func secondsBetween(_ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant) -> Double {
  let components = start.duration(to: end).components
  return Double(components.seconds) + Double(components.attoseconds) * 1e-18
}
