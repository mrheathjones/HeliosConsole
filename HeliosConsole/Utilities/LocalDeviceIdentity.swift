//
//  LocalDeviceIdentity.swift
//  HeliosConsole
//
//  The hardware identity of the Mac Helios is running on, read from the
//  IORegistry. Used ONLY by My Devices' fallback path: when the directory
//  lookup finds nothing assigned to the signed-in user, the one device we can
//  always speak about with certainty is the one under their hands.
//
//  Deliberately not a service: no network, no state, no configuration. The
//  serial is read once and memoized — IOPlatformSerialNumber cannot change
//  while the process is alive.
//

import Foundation
import IOKit

enum LocalDeviceIdentity {

    /// This Mac's hardware serial number, or nil when the IORegistry lookup
    /// fails (never expected on real hardware, but the fallback path must
    /// degrade to "nothing to show" rather than crash).
    static let serialNumber: String? = readRegistryString(kIOPlatformSerialNumberKey)

    /// This Mac's model identifier (e.g. `Mac15,7`). Display only — the Jamf
    /// lookup keys on the serial.
    static let modelIdentifier: String? = readModelIdentifier()

    /// The local host name, shown while the Jamf record is still loading so
    /// the fallback card is never blank.
    static var localHostName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    // MARK: - IORegistry

    private static func platformExpert() -> io_service_t {
        IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    }

    private static func readRegistryString(_ key: String) -> String? {
        let service = platformExpert()
        guard service != IO_OBJECT_NULL else {
            NSLog("⚠️ LocalDeviceIdentity: IOPlatformExpertDevice not found")
            return nil
        }
        defer { IOObjectRelease(service) }

        guard let property = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? String else {
            return nil
        }

        let trimmed = property.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `model` is published as raw Data (a NUL-terminated C string), not a
    /// CFString, so it needs its own reader.
    private static func readModelIdentifier() -> String? {
        let service = platformExpert()
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        guard let data = IORegistryEntryCreateCFProperty(
            service, "model" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Data else {
            return nil
        }

        let model = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
        return model.isEmpty ? nil : model
    }
}
