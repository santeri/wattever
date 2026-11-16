import AppKit
import Darwin
import Foundation
import WatteverCore

private let appDelegate = AppDelegate()

if CommandLine.arguments.contains("--once") {
  do {
    try runOnce()
  } catch {
    fputs("wattever: \(error.localizedDescription)\n", stderr)
    exit(1)
  }
  exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = appDelegate
app.run()

private func runOnce() throws {
  let powerMetrics = PowerMetricsMonitor()
  powerMetrics.ensureRunning()
  let sampler = try EnergySampler()
  if sampler.poll() != nil {
    fputs("wattever: unexpected reading on the baseline sample\n", stderr)
    exit(1)
  }
  Thread.sleep(forTimeInterval: 1)
  guard let reading = sampler.poll() else {
    fputs("wattever: no energy delta\n", stderr)
    exit(1)
  }
  let power = PowerInput.now()
  print(menuBarTitle(usageWatts: power.usageWatts ?? reading.total, inputWatts: power.inputWatts))
  if let battery = power.battery {
    print(formatBatteryClock(battery))
  }
  let line = String(
    format: "cpu %.2f  gpu %.2f  ane %.2f  dram %.2f  display %.2f  other %.2f  (%.2f s)",
    locale: Locale(identifier: "en_US_POSIX"),
    reading.cpu,
    reading.gpu,
    reading.ane,
    reading.dram,
    reading.display,
    reading.other,
    reading.seconds
  )
  print(line)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem?
  private var sampler: EnergySampler?
  private var timer: Timer?
  private var history = EnergyHistory()
  private let header = NSMenuItem()
  private let inputItem = NSMenuItem()
  private let batteryItem = NSMenuItem()
  private let subtitle = NSMenuItem()
  private let historyItem = NSMenuItem()
  private let historyView = HistoryView(frame: NSRect(x: 0, y: 0, width: 280, height: 52))
  private let chip = NSMenuItem()
  private let cpu = NSMenuItem()
  private let gpu = NSMenuItem()
  private let ane = NSMenuItem()
  private let dram = NSMenuItem()
  private let display = NSMenuItem()
  private let other = NSMenuItem()
  private let session = NSMenuItem()
  private let helperItem = NSMenuItem()
  private let powerMetrics = PowerMetricsMonitor()

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard notAlreadyRunning else {
      NSApp.terminate(nil)
      return
    }
    powerMetrics.ensureRunning()

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem = item
    if let button = item.button {
      button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
      button.title = "-…W"
      button.setAccessibilityLabel("wattever")
    }

    let menu = NSMenu()
    menu.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    inputItem.isHidden = true
    batteryItem.isHidden = true
    chip.title = "chip"
    historyItem.view = historyView
    let rows: [(NSMenuItem, Bool)] = [
      (header, false),
      (inputItem, false),
      (batteryItem, false),
      (subtitle, true),
      (historyItem, false),
      (session, true),
      (chip, false),
      (cpu, false),
      (gpu, false),
      (ane, false),
      (dram, false),
      (display, false),
      (other, true),
    ]
    for (entry, separatorAfter) in rows {
      if entry !== historyItem {
        entry.target = self
        entry.action = #selector(ignore)
      }
      menu.addItem(entry)
      if separatorAfter { menu.addItem(.separator()) }
    }
    helperItem.title = "make enable for exact chip power"
    helperItem.target = self
    helperItem.action = #selector(ignore)
    helperItem.isHidden = powerMetrics.isInstalled
    menu.addItem(helperItem)
    let quit = NSMenuItem(title: "Quit wattever", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    quit.target = NSApp
    menu.addItem(quit)
    item.menu = menu

    header.title = "-… W"
    subtitle.title = "measuring 1 s"
    session.title = "session"

    do {
      let sampler = try EnergySampler()
      self.sampler = sampler
      _ = sampler.poll()
    } catch {
      item.button?.title = "-!W"
      header.title = error.localizedDescription
      return
    }

    let timer = Timer(timeInterval: 1.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  @objc private func tick() {
    powerMetrics.ensureRunning()
    helperItem.isHidden = powerMetrics.isInstalled || PowerMetricsMonitor.binaryRunning(PowerMetricsMonitor.powermetricsPath)
    guard let reading = sampler?.poll() else { return }
    let power = PowerInput.now()
    let usage = power.usageWatts ?? reading.total
    history.record(usage)
    let title = menuBarTitle(usageWatts: usage, inputWatts: power.inputWatts)
    statusItem?.button?.title = title
    statusItem?.button?.setAccessibilityValue(title)
    header.title = "-" + formatWatts(usage, fractionDigits: 2)
    inputItem.isHidden = power.inputWatts == nil
    if let input = power.inputWatts {
      inputItem.title = "+" + formatWatts(input, fractionDigits: 2)
    }
    if let battery = power.battery {
      batteryItem.isHidden = false
      batteryItem.title = formatBatteryClock(battery)
    } else {
      batteryItem.isHidden = true
    }
    subtitle.title = String(
      format: "%.2f s",
      locale: Locale(identifier: "en_US_POSIX"),
      reading.seconds
    )
    cpu.title = row("CPU", reading.cpu)
    gpu.title = row("GPU", reading.gpu)
    ane.title = row("ANE", reading.ane)
    dram.title = row("DRAM", reading.dram)
    display.title = row("Display", reading.display)
    other.title = row("Other", reading.other)
    let stats = String(
      format: "min %.2f   avg %.2f   max %.2f",
      locale: Locale(identifier: "en_US_POSIX"),
      history.minimum,
      history.average,
      history.maximum
    )
    session.title = stats
    historyView.samples = history.samples
    historyView.now = Date()
    historyView.setAccessibilityValue(stats)
  }

  @objc private func ignore(_ sender: Any?) {}

  private func row(_ name: String, _ watts: Double) -> String {
    name.padding(toLength: 8, withPad: " ", startingAt: 0) + formatWatts(watts, fractionDigits: 2)
  }

  private var notAlreadyRunning: Bool {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.santeri.wattever")
    return !others.contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
  }
}

/// Launches the setuid helper, which is root and therefore cannot be signaled
/// from here. The helper watches this process and stops sampling when it exits.
private final class PowerMetricsMonitor {
  static let path = "/usr/local/libexec/wattever-powermetrics"
  static let powermetricsPath = "/usr/bin/powermetrics"

  private var process: Process?
  private var startedAt: Date?
  private var gaveUp = false

  var isInstalled: Bool { Self.isInstalled(at: Self.path) }

  func ensureRunning() {
    if let process {
      if process.isRunning { return }
      process.waitUntilExit()
      if let startedAt, Date().timeIntervalSince(startedAt) < 2 {
        gaveUp = true
      }
      self.process = nil
      self.startedAt = nil
    }
    guard isInstalled, !gaveUp else { return }
    guard !Self.binaryRunning(Self.powermetricsPath) else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: Self.path)
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      gaveUp = true
      return
    }
    self.process = process
    self.startedAt = Date()
  }

  static func isInstalled(at path: String) -> Bool {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
      let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value,
      let mode = (attributes[.posixPermissions] as? NSNumber)?.uint16Value
    else { return false }
    return HelperInstall.isSetuidRoot(owner: owner, permissions: mode)
  }

  static func binaryRunning(_ path: String) -> Bool {
    // The buffer length is in bytes. The return value is a pid count.
    let needed = proc_listallpids(nil, 0)
    guard needed > 0 else { return false }
    let count = Int(needed) + 32
    var pids = [pid_t](repeating: 0, count: count)
    let written = proc_listallpids(&pids, Int32(count * MemoryLayout<pid_t>.size))
    guard written > 0 else { return false }
    let available = min(count, Int(written))
    for pid in pids.prefix(available) where pid > 0 {
      var buffer = [CChar](repeating: 0, count: 4096)
      guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
      let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
      if String(decoding: bytes, as: UTF8.self) == path { return true }
    }
    return false
  }
}

private final class HistoryView: NSView {
  var samples: [HistorySample] = [] {
    didSet { needsDisplay = true }
  }
  var now = Date() {
    didSet { needsDisplay = true }
  }

  override var intrinsicContentSize: NSSize { NSSize(width: 280, height: 52) }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    setAccessibilityLabel("10 min history")
  }

  required init?(coder: NSCoder) { nil }

  override func draw(_ dirtyRect: NSRect) {
    let highlighted = enclosingMenuItem?.isHighlighted ?? false
    let lineColor = highlighted ? NSColor.selectedMenuItemTextColor : NSColor.labelColor
    let caption = highlighted ? NSColor.selectedMenuItemTextColor : NSColor.secondaryLabelColor
    let plot = bounds.insetBy(dx: 14, dy: 6)
    let first = samples.map(\.time).min()
    let span = first.map { min(EnergyHistory.window, now.timeIntervalSince($0)) } ?? 0
    let captionText = historyCaption(span: span)
    setAccessibilityLabel(captionText + " history")
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
      .foregroundColor: caption,
    ]
    (captionText as NSString).draw(at: NSPoint(x: plot.minX, y: plot.maxY - 12), withAttributes: attributes)

    let graph = NSRect(x: plot.minX, y: plot.minY, width: plot.width, height: max(plot.height - 14, 1))
    let path = NSBezierPath()
    path.lineWidth = 1.25
    path.lineJoinStyle = .round
    path.lineCapStyle = .round

    let axisStart = (span >= EnergyHistory.window - 1) ? now.addingTimeInterval(-EnergyHistory.window) : (first ?? now)
    let axisSpan = max(span, 1)
    let finite = samples.filter { $0.time >= axisStart && $0.time <= now.addingTimeInterval(1) }
    guard let lowSample = finite.map(\.watts).min(), let highSample = finite.map(\.watts).max() else {
      path.move(to: NSPoint(x: graph.minX, y: graph.midY))
      path.line(to: NSPoint(x: graph.maxX, y: graph.midY))
      lineColor.withAlphaComponent(0.35).setStroke()
      path.lineWidth = 1
      path.stroke()
      return
    }

    var low = lowSample
    var high = highSample
    if high - low < 0.5 {
      let mid = (low + high) / 2
      low = mid - 0.25
      high = mid + 0.25
    }
    let range = high - low
    func point(for sample: HistorySample) -> NSPoint {
      let x = graph.minX + graph.width * CGFloat(sample.time.timeIntervalSince(axisStart) / axisSpan)
      let y = graph.minY + graph.height * CGFloat((sample.watts - low) / range)
      return NSPoint(
        x: min(max(x, graph.minX), graph.maxX),
        y: min(max(y, graph.minY), graph.maxY)
      )
    }

    if finite.count < 2 {
      let y = finite.isEmpty ? graph.midY : point(for: finite[0]).y
      path.move(to: NSPoint(x: graph.minX, y: y))
      path.line(to: NSPoint(x: graph.maxX, y: y))
      lineColor.withAlphaComponent(finite.isEmpty ? 0.35 : 1).setStroke()
      path.stroke()
      return
    }

    for (index, sample) in finite.enumerated() {
      let dot = point(for: sample)
      if index == 0 { path.move(to: dot) } else { path.line(to: dot) }
    }
    lineColor.setStroke()
    path.stroke()
  }
}
