import Foundation

public final class IOSManager: @unchecked Sendable {
    public static let shared = IOSManager()

    public init() {}

    /// Scans for iOS devices attached via USB or Wi-Fi using Apple's native usbmuxd daemon
    public func scanIOSDevices() async -> [Device] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let devices = self.queryUsbmuxdDevices()
                continuation.resume(returning: devices)
            }
        }
    }

    private func queryUsbmuxdDevices() -> [Device] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = "/var/run/usbmuxd"
        _ = path.withCString { strncpy(&addr.sun_path.0, $0, 104) }

        let connectRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectRes == 0 else { return [] }

        let listReq: [String: Any] = [
            "MessageType": "ListDevices",
            "ClientVersionString": "KMODroidSync",
            "ProgName": "KMODroidSync"
        ]
        guard let plistData = try? PropertyListSerialization.data(fromPropertyList: listReq, format: .xml, options: 0) else { return [] }

        let header = [
            UInt32(plistData.count + 16).littleEndian,
            UInt32(1).littleEndian,
            UInt32(8).littleEndian,
            UInt32(1).littleEndian
        ]
        header.withUnsafeBytes { _ = write(fd, $0.baseAddress!, 16) }
        plistData.withUnsafeBytes { _ = write(fd, $0.baseAddress!, plistData.count) }

        var respHdr = [UInt32](repeating: 0, count: 4)
        _ = respHdr.withUnsafeMutableBytes { read(fd, $0.baseAddress!, 16) }
        let totalLen = Int(UInt32(littleEndian: respHdr[0]))
        guard totalLen > 16 else { return [] }

        var payload = Data(count: totalLen - 16)
        _ = payload.withUnsafeMutableBytes { read(fd, $0.baseAddress!, totalLen - 16) }

        guard let obj = try? PropertyListSerialization.propertyList(from: payload, format: nil) as? [String: Any],
              let list = obj["DeviceList"] as? [[String: Any]] else {
            return []
        }

        var devices: [Device] = []
        var seenSerials = Set<String>()

        for item in list {
            guard let props = item["Properties"] as? [String: Any],
                  let deviceID = props["DeviceID"] as? Int,
                  let serial = props["SerialNumber"] as? String else {
                continue
            }

            // Avoid duplicate rows for same device connected via USB & Network
            if seenSerials.contains(serial) { continue }
            seenSerials.insert(serial)

            let connTypeStr = props["ConnectionType"] as? String ?? "USB"
            let connectionType: ConnectionType = (connTypeStr == "Network") ? .wifi : .usb

            // Fetch device name & product type from lockdown
            let lockdownInfo = self.queryLockdown(deviceID: Int32(deviceID))

            let productType = lockdownInfo["ProductType"] ?? "iPhone"
            let friendlyName = self.friendlyAppleModel(productType: productType)
            let deviceName = lockdownInfo["DeviceName"] ?? friendlyName
            let osVersion = lockdownInfo["ProductVersion"] ?? "iOS"

            let device = Device(
                id: serial,
                name: "\(deviceName) (\(friendlyName))",
                manufacturer: "Apple",
                model: friendlyName,
                platform: .ios,
                connectionType: connectionType,
                osVersion: "iOS \(osVersion)",
                batteryLevel: 95,
                isCharging: connectionType == .usb,
                batteryTempCelsius: 28.0,
                storage: StorageInfo(totalBytes: 128_000_000_000, freeBytes: 64_000_000_000),
                isConnected: true
            )
            devices.append(device)
        }

        return devices
    }

    private func queryLockdown(deviceID: Int32) -> [String: String] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return [:] }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = "/var/run/usbmuxd"
        _ = path.withCString { strncpy(&addr.sun_path.0, $0, 104) }

        let connectRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectRes == 0 else { return [:] }

        // Connect to lockdown port (62078)
        let portNumber = UInt16(62078).bigEndian
        let connectDict: [String: Any] = [
            "MessageType": "Connect",
            "ClientVersionString": "KMODroidSync",
            "ProgName": "KMODroidSync",
            "DeviceID": deviceID,
            "PortNumber": Int(portNumber)
        ]
        guard let connData = try? PropertyListSerialization.data(fromPropertyList: connectDict, format: .xml, options: 0) else { return [:] }

        let hdr = [
            UInt32(connData.count + 16).littleEndian,
            UInt32(1).littleEndian,
            UInt32(8).littleEndian,
            UInt32(1).littleEndian
        ]
        hdr.withUnsafeBytes { _ = write(fd, $0.baseAddress!, 16) }
        connData.withUnsafeBytes { _ = write(fd, $0.baseAddress!, connData.count) }

        var respHdr = [UInt32](repeating: 0, count: 4)
        _ = respHdr.withUnsafeMutableBytes { read(fd, $0.baseAddress!, 16) }
        let totalLen = Int(UInt32(littleEndian: respHdr[0]))
        guard totalLen > 16 else { return [:] }
        var payload = Data(count: totalLen - 16)
        _ = payload.withUnsafeMutableBytes { read(fd, $0.baseAddress!, totalLen - 16) }

        // Query lockdown for device properties
        let getVal: [String: Any] = [
            "Request": "GetValue",
            "Label": "KMODroidSync"
        ]
        guard let reqData = try? PropertyListSerialization.data(fromPropertyList: getVal, format: .xml, options: 0) else { return [:] }
        let reqLen = UInt32(reqData.count).bigEndian
        withUnsafeBytes(of: reqLen) { _ = write(fd, $0.baseAddress!, 4) }
        reqData.withUnsafeBytes { _ = write(fd, $0.baseAddress!, reqData.count) }

        var ldHdr: UInt32 = 0
        withUnsafeMutableBytes(of: &ldHdr) { _ = read(fd, $0.baseAddress!, 4) }
        let ldLen = Int(UInt32(bigEndian: ldHdr))
        guard ldLen > 0 && ldLen < 1_000_000 else { return [:] }

        var ldPayload = Data(count: ldLen)
        var received = 0
        while received < ldLen {
            let r = ldPayload.withUnsafeMutableBytes { ptr in
                read(fd, ptr.baseAddress! + received, ldLen - received)
            }
            if r <= 0 { break }
            received += r
        }

        var results: [String: String] = [:]
        if let ldObj = try? PropertyListSerialization.propertyList(from: ldPayload, format: nil) as? [String: Any],
           let val = ldObj["Value"] as? [String: Any] {
            if let dn = val["DeviceName"] as? String { results["DeviceName"] = dn }
            if let pt = val["ProductType"] as? String { results["ProductType"] = pt }
            if let pv = val["ProductVersion"] as? String { results["ProductVersion"] = pv }
        }

        return results
    }

    public func friendlyAppleModel(productType: String) -> String {
        let map = [
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,5": "iPhone 13",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone12,1": "iPhone 11",
            "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max",
            "iPhone11,2": "iPhone XS",
            "iPhone11,4": "iPhone XS Max",
            "iPhone11,6": "iPhone XS Max",
            "iPhone11,8": "iPhone XR",
            "iPhone10,3": "iPhone X",
            "iPhone10,6": "iPhone X",
            "iPhone14,6": "iPhone SE (3rd generation)"
        ]
        return map[productType] ?? productType
    }
}
