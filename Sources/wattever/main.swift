import AppKit
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
  let input = PowerInput.current()
  print(menuBarTitle(usageWatts: reading.total, inputWatts: input))
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
  private let subtitle = NSMenuItem()
  private let cpu = NSMenuItem()
  private let gpu = NSMenuItem()
  private let ane = NSMenuItem()
  private let dram = NSMenuItem()
  private let display = NSMenuItem()
  private let other = NSMenuItem()
  private let session = NSMenuItem()

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard notAlreadyRunning else {
      NSApp.terminate(nil)
      return
    }

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
    for entry in [header, inputItem, subtitle, cpu, gpu, ane, dram, display, other, session] {
      entry.target = self
      entry.action = #selector(ignore)
      menu.addItem(entry)
      if entry === subtitle || entry === other {
        menu.addItem(.separator())
      }
    }
    menu.addItem(.separator())
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
    guard let reading = sampler?.poll() else { return }
    history.record(reading.total)
    let input = PowerInput.current()
    let title = menuBarTitle(usageWatts: reading.total, inputWatts: input)
    statusItem?.button?.title = title
    statusItem?.button?.setAccessibilityValue(title)
    header.title = "-" + formatWatts(reading.total, fractionDigits: 2)
    inputItem.isHidden = input == nil
    if let input {
      inputItem.title = "+" + formatWatts(input, fractionDigits: 2)
    }
    subtitle.title = String(
      format: "%.2f s · SoC",
      locale: Locale(identifier: "en_US_POSIX"),
      reading.seconds
    )
    cpu.title = row("CPU", reading.cpu)
    gpu.title = row("GPU", reading.gpu)
    ane.title = row("ANE", reading.ane)
    dram.title = row("DRAM", reading.dram)
    display.title = row("Display", reading.display)
    other.title = row("Other", reading.other)
    session.title = String(
      format: "min %.2f   avg %.2f   max %.2f",
      locale: Locale(identifier: "en_US_POSIX"),
      history.minimum,
      history.average,
      history.maximum
    )
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
