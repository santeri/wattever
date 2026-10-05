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
  private var previous: CFDictionary?
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
  }

  deinit {
    wattever_release_subscription(subscription)
  }

  /// The first call stores a baseline and returns nil. Each later call returns the
  /// average watts since the previous call.
  public func poll() -> EnergyReading? {
    let now = ContinuousClock.now
    guard let sample = wattever_copy_samples(subscription, channels) else { return nil }
    guard let previous, let previousInstant else {
      self.previous = sample
      self.previousInstant = now
      return nil
    }
    let seconds = secondsBetween(previousInstant, now)
    defer {
      self.previous = sample
      self.previousInstant = now
    }
    guard let delta = wattever_copy_delta(previous, sample) else { return nil }
    return EnergyMath.reading(samples: readChannels(delta), seconds: seconds)
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

private func secondsBetween(_ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant) -> Double {
  let components = start.duration(to: end).components
  return Double(components.seconds) + Double(components.attoseconds) * 1e-18
}
