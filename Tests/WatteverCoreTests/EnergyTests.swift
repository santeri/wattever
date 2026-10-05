import XCTest

@testable import WatteverCore

final class EnergyTests: XCTestCase {
  func testUnitConversion() {
    XCTAssertEqual(EnergyMath.energy(raw: 465, unit: "mJ")!, 0.465, accuracy: 1e-12)
    XCTAssertEqual(EnergyMath.energy(raw: 1_000, unit: "uJ")!, 0.001, accuracy: 1e-15)
    XCTAssertEqual(EnergyMath.energy(raw: 356_994_777, unit: "nJ")!, 0.356994777, accuracy: 1e-12)
    XCTAssertEqual(EnergyMath.energy(raw: 1_000, unit: " uJ\n")!, 0.001, accuracy: 1e-15)
    XCTAssertEqual(EnergyMath.energy(raw: -5, unit: "mJ")!, 0, accuracy: 1e-12)
    XCTAssertNil(EnergyMath.energy(raw: 1, unit: "W"))
  }

  func testRejectsShortIntervalsAndUnknownChannels() {
    let cpu = ChannelSample(name: "CPU Energy", unit: "mJ", raw: 1_000)
    XCTAssertNil(EnergyMath.reading(samples: [cpu], seconds: 0))
    XCTAssertNil(EnergyMath.reading(samples: [cpu], seconds: -1))
    XCTAssertNil(EnergyMath.reading(samples: [cpu], seconds: 0.049))
    XCTAssertEqual(EnergyMath.reading(samples: [cpu], seconds: 0.05)?.total ?? -1, 20, accuracy: 1e-9)
    XCTAssertNil(EnergyMath.reading(samples: [ChannelSample(name: "EACC_CPU0", unit: "mJ", raw: 9_000)], seconds: 1))
    XCTAssertNil(
      EnergyMath.reading(samples: [ChannelSample(name: "CPU Energy", unit: "bananas", raw: 1_000)], seconds: 1))
  }

  func testIgnoresPartsThatAreAlreadyInTheAggregates() {
    let reading = EnergyMath.reading(
      samples: [
        ChannelSample(name: "CPU Energy", unit: "mJ", raw: 1_000),
        ChannelSample(name: "EACC_CPU0", unit: "mJ", raw: 9_000),
        ChannelSample(name: "EACC_CPU", unit: "mJ", raw: 9_000),
        ChannelSample(name: "PACC1_CPU", unit: "mJ", raw: 9_000),
        ChannelSample(name: "ECPUDTL00", unit: "mJ", raw: 9_000),
        ChannelSample(name: "EACC_CPU0_SRAM", unit: "mJ", raw: 9_000),
      ], seconds: 1)
    XCTAssertEqual(reading?.cpu ?? -1, 1, accuracy: 1e-12)
    XCTAssertEqual(reading?.total ?? -1, 1, accuracy: 1e-12)
  }

  func testSumsDiesAndPrefersFineGPU() {
    let reading = EnergyMath.reading(
      samples: [
        ChannelSample(name: "DIE_0_CPU Energy", unit: "mJ", raw: 100),
        ChannelSample(name: "DIE_1_CPU Energy", unit: "mJ", raw: 250),
        ChannelSample(name: "GPU", unit: "mJ", raw: 353),
        ChannelSample(name: "GPU Energy", unit: "nJ", raw: 356_994_777),
        ChannelSample(name: "GPU SRAM", unit: "mJ", raw: 5),
        ChannelSample(name: "ANE0", unit: "mJ", raw: 10),
        ChannelSample(name: "ANE1", unit: "mJ", raw: 20),
        ChannelSample(name: "ANE0_SRAM", unit: "mJ", raw: 100),
        ChannelSample(name: "DRAM0_0", unit: "mJ", raw: 100),
        ChannelSample(name: "DRAM0_1", unit: "mJ", raw: 50),
      ], seconds: 1)
    XCTAssertEqual(reading?.cpu ?? -1, 0.35, accuracy: 1e-12)
    XCTAssertEqual(reading?.gpu ?? -1, 0.356994777 + 0.005, accuracy: 1e-9)
    XCTAssertEqual(reading?.ane ?? -1, 0.030, accuracy: 1e-12)
    XCTAssertEqual(reading?.dram ?? -1, 0.15, accuracy: 1e-12)
  }

  func testCoarseGPUWhenTheFineCounterIsAbsent() {
    let reading = EnergyMath.reading(
      samples: [ChannelSample(name: "GPU", unit: "mJ", raw: 2_000)], seconds: 1)
    XCTAssertEqual(reading?.gpu ?? -1, 2, accuracy: 1e-12)
  }

  func testGroupsDisplayFabricAndPCIe() {
    let reading = EnergyMath.reading(
      samples: [
        ChannelSample(name: "DISP", unit: "mJ", raw: 233),
        ChannelSample(name: "DISPEXT", unit: "mJ", raw: 4),
        ChannelSample(name: "AMCC", unit: "mJ", raw: 784),
        ChannelSample(name: "DCS", unit: "mJ", raw: 370),
        ChannelSample(name: "AFR", unit: "mJ", raw: 29),
        ChannelSample(name: "FAB", unit: "mJ", raw: 1),
        ChannelSample(name: "ISP", unit: "mJ", raw: 2),
        ChannelSample(name: "AVE", unit: "mJ", raw: 2),
        ChannelSample(name: "MSR", unit: "mJ", raw: 2),
        ChannelSample(name: "PCIe Port 0 Energy", unit: "uJ", raw: 5_000_000),
        ChannelSample(name: "apciec1 Energy", unit: "uJ", raw: 1_000_000),
        ChannelSample(name: "ANE", unit: "mJ", raw: 0),
      ], seconds: 1)
    XCTAssertEqual(reading?.display ?? -1, 0.237, accuracy: 1e-12)
    XCTAssertEqual(reading?.other ?? -1, 0.784 + 0.370 + 0.029 + 0.001 + 0.002 * 3 + 5 + 1, accuracy: 1e-9)
    XCTAssertEqual(reading?.ane ?? -1, 0, accuracy: 1e-12)
    XCTAssertEqual(reading?.total ?? -1, (reading?.display ?? 0) + (reading?.other ?? 0), accuracy: 1e-9)
  }

  func testM4MaxSampleDoesNotTripleCountCPU() {
    let reading = EnergyMath.reading(
      samples: [
        ChannelSample(name: "EACC_CPU0", unit: "mJ", raw: 59),
        ChannelSample(name: "EACC_CPU", unit: "mJ", raw: 211),
        ChannelSample(name: "PACC1_CPU", unit: "mJ", raw: 254),
        ChannelSample(name: "CPU Energy", unit: "mJ", raw: 465),
        ChannelSample(name: "GPU", unit: "mJ", raw: 353),
        ChannelSample(name: "GPU SRAM", unit: "mJ", raw: 0),
        ChannelSample(name: "AFR", unit: "mJ", raw: 29),
        ChannelSample(name: "ANE", unit: "mJ", raw: 0),
        ChannelSample(name: "ISP", unit: "mJ", raw: 2),
        ChannelSample(name: "AVE", unit: "mJ", raw: 2),
        ChannelSample(name: "MSR", unit: "mJ", raw: 2),
        ChannelSample(name: "AMCC", unit: "mJ", raw: 784),
        ChannelSample(name: "DCS", unit: "mJ", raw: 370),
        ChannelSample(name: "DRAM", unit: "mJ", raw: 329),
        ChannelSample(name: "DISP", unit: "mJ", raw: 233),
        ChannelSample(name: "DISPEXT", unit: "mJ", raw: 4),
        ChannelSample(name: "PCIe Port 0 Energy", unit: "uJ", raw: 0),
        ChannelSample(name: "GPU Energy", unit: "nJ", raw: 356_994_777),
      ], seconds: 1)
    XCTAssertEqual(reading?.cpu ?? -1, 0.465, accuracy: 1e-12)
    XCTAssertEqual(reading?.gpu ?? -1, 0.356994777, accuracy: 1e-9)
    XCTAssertEqual(reading?.dram ?? -1, 0.329, accuracy: 1e-12)
    XCTAssertEqual(reading?.display ?? -1, 0.237, accuracy: 1e-12)
    XCTAssertEqual(reading?.total ?? -1, 2.576994777, accuracy: 1e-9)
  }

  func testHistoryAndMenuBarWidth() {
    var history = EnergyHistory()
    history.record(2)
    history.record(4)
    history.record(.nan)
    history.record(.infinity)
    XCTAssertEqual(history.count, 2)
    XCTAssertEqual(history.minimum, 2, accuracy: 1e-12)
    XCTAssertEqual(history.maximum, 4, accuracy: 1e-12)
    XCTAssertEqual(history.average, 3, accuracy: 1e-12)

    XCTAssertEqual(menuBarTitle(usageWatts: 2.57), "-2.6W")
    XCTAssertEqual(menuBarTitle(usageWatts: 12.44), "-12.4W")
    XCTAssertEqual(menuBarTitle(usageWatts: .nan), "-0.0W")
    XCTAssertEqual(menuBarTitle(usageWatts: 2.57, inputWatts: 32.97), "-2.6W +33.0W")
    XCTAssertEqual(formatWatts(2.573, fractionDigits: 2), "2.57 W")
    XCTAssertEqual(formatWatts(12.46, fractionDigits: 1), "12.5 W")
  }

  func testAdapterInputOnlyWhileOnExternalPower() {
    let telemetry: [String: Any] = [
      "SystemVoltageIn": 19508,
      "SystemCurrentIn": 1690,
      "SystemPowerIn": 32973,
    ]
    let charging: [String: Any] = [
      "ExternalConnected": true,
      "PowerTelemetryData": telemetry,
    ]
    XCTAssertEqual(PowerInput.watts(in: charging) ?? -1, 19508.0 * 1690.0 / 1_000_000, accuracy: 1e-9)

    var fallback = charging
    fallback["PowerTelemetryData"] = ["SystemPowerIn": 32973] as [String: Any]
    XCTAssertEqual(PowerInput.watts(in: fallback) ?? -1, 32.973, accuracy: 1e-9)

    var battery = charging
    battery["ExternalConnected"] = false
    XCTAssertNil(PowerInput.watts(in: battery))

    var idle = charging
    idle["PowerTelemetryData"] = [
      "SystemVoltageIn": 0, "SystemCurrentIn": 0, "SystemPowerIn": 0,
    ] as [String: Any]
    XCTAssertNil(PowerInput.watts(in: idle))
  }
}
