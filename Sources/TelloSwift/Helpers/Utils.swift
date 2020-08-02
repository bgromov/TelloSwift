//
//  Utils.swift
//  TelloSwift
//
//  Created by Boris Gromov on 24.04.2020.
//  Copyright © 2020 Volaly. All rights reserved.


import Foundation
import QuartzCore.CoreAnimation

public func rad2deg<T: FloatingPoint>(_ rad: T) -> T {
    return (rad * 180 / .pi)
}

public func deg2rad<T: FloatingPoint>(_ deg: T) -> T {
    return (deg / 180 * .pi)
}

/*
 Source: https://github.com/raywenderlich/swift-algorithm-club/tree/dd1ed39fca150d4fa2905b902736f12a49f3efb1/Ring%20Buffer

 Fixed-length ring buffer
 In this implementation, the read and write pointers always increment and
 never wrap around. On a 64-bit platform that should not get you into trouble
 any time soon.
 Not thread-safe, so don't read and write from different threads at the same
 time! To make this thread-safe for one reader and one writer, it should be
 enough to change read/writeIndex += 1 to OSAtomicIncrement64(), but I haven't
 tested this...
 */
public struct RingBuffer<T> {
    private var array: [T?]
    private var readIndex = 0
    private var writeIndex = 0

    public let size: Int

    public init(count: Int) {
        size = count
        array = [T?](repeating: nil, count: count)
    }

    /* Returns false if out of space. */
    @discardableResult
    public mutating func write(_ element: T) -> Bool {
        guard !isFull else { return false }
        defer {
            writeIndex += 1
        }
        array[wrapped: writeIndex] = element
        return true
    }

    /* Returns nil if the buffer is empty. */
    public mutating func read() -> T? {
        guard !isEmpty else { return nil }
        defer {
            array[wrapped: readIndex] = nil
            readIndex += 1
        }
        return array[wrapped: readIndex]
    }

    public var availableSpaceForReading: Int {
        return writeIndex - readIndex
    }

    public var isEmpty: Bool {
        return availableSpaceForReading == 0
    }

    public var availableSpaceForWriting: Int {
        return array.count - availableSpaceForReading
    }

    public var isFull: Bool {
        return availableSpaceForWriting == 0
    }
}

extension RingBuffer: Sequence {
    public func makeIterator() -> AnyIterator<T> {
        var index = readIndex
        return AnyIterator {
            guard index < self.writeIndex else { return nil }
            defer {
                index += 1
            }
            return self.array[wrapped: index]
        }
    }
}

extension RingBuffer where T: BinaryFloatingPoint {
    public func average<R>() -> R where R: BinaryFloatingPoint {
        let sum = self.reduce(T.zero, +)
        return R(sum) / R(availableSpaceForReading)
    }
}

private extension Array {
    subscript (wrapped index: Int) -> Element {
        get {
            return self[index % count]
        }
        set {
            self[index % count] = newValue
        }
    }
}

public protocol StopWatchDelegate: class {
    func stopWatch(_ stopWatch: StopWatch, window: Int, didEstimateHz value: Double)
    func stopWatch(_ stopWatch: StopWatch, window: Int, didEstimateTime value: CFTimeInterval)
}

public class StopWatch {
    /// Class delegate
    public weak var delegate: StopWatchDelegate?
    /// How often to report statistics
    public var statsInterval: CFTimeInterval
    /// Current window size. Can be less than maxWindow
    private(set) public var window: Int

    private var buf: RingBuffer<CFTimeInterval>
    private var startTime: CFTimeInterval
    private var stopTime: CFTimeInterval
    private var avgTime: CFTimeInterval?
    private var stdTime: CFTimeInterval?
    private var maxDevTime: CFTimeInterval?

    private var throttleLastTime: CFTimeInterval?
    private var hzLastTime: CFTimeInterval?
    private let statsQueue: DispatchQueue

    private let bufSize: Int

    public init(maxWindow: Int, statsInterval: CFTimeInterval = 1.0, delegate: StopWatchDelegate? = nil) {
        bufSize = maxWindow
        buf = RingBuffer(count: maxWindow)
        startTime = 0.0
        stopTime = 0.0

        self.statsInterval = statsInterval
        self.delegate = delegate
        self.window = 0

        statsQueue = DispatchQueue(label: "ch.volaly.tello.stopwatch", attributes: [])
    }

    private func printTime() {
        guard let avg = self.avgTime,
            let std = self.stdTime,
            let max = self.maxDevTime else {return}

        let str = String(format: "StopWatch: [\(bufSize)], time: %3.6f, std: %3.8f, max_dev: %3.8", avg, std, max)
        print(str)
    }

    private func printHz() {
        guard let avg = self.avgTime,
              let std = self.stdTime,
              let max = self.maxDevTime else {return}

        let str = String(format: "StopWatch: [\(bufSize)], freq: %3.2f, std: %3.3f, max_dev: %3.3f", 1.0 / avg, 1.0 / std, 1.0 / max)
        print(str)
    }

    func throttle(timeInterval: TimeInterval, _ closure: () -> ()) {
        let now = CACurrentMediaTime()

        if let last = throttleLastTime {
            if now < last + timeInterval {
                return
            }
        }

        throttleLastTime = now

        closure()
    }

    private func average() -> (Int, CFTimeInterval, CFTimeInterval, CFTimeInterval) {
        let sum = buf.reduce(CFTimeInterval(), +)
        let count = buf.availableSpaceForReading
        let avg = sum / Double(count)

        // Sequence of differences
        let diff = buf.map {curVal in
            return curVal - avg
        }

        // Max deviation
        let max = diff.max { a, b in abs(a) < abs(b)}

        // Sum of squared differences
        var std = diff.reduce(CFTimeInterval()) { prevRes, curVal in
            return prevRes + pow(curVal, 2.0)
        }

        // Standard deviation
        std = sqrt(std) / Double(count - 1)

        return (count, avg, std, max!)
    }

    public func start() {
        startTime = CACurrentMediaTime()
    }

    public func stop() {
        stopTime = CACurrentMediaTime()
        let dt = stopTime - startTime
        statsQueue.async {
            self.buf.write(dt)

            let (count, avg, std, max) = self.average()
            (self.window, self.avgTime, self.stdTime, self.maxDevTime) = (count, avg, std, max)

            if self.buf.availableSpaceForWriting == 0 {
                _ = self.buf.read()
            }
        }

        if let avg = self.avgTime {
            throttle(timeInterval: statsInterval) {
                guard let delegate = delegate else {
                    printTime()
                    return
                }

                DispatchQueue.main.async {
                    delegate.stopWatch(self, window: self.window, didEstimateTime: avg)
                }
            }
        }
    }

    public func hz() {
        let now = CACurrentMediaTime()

        if let last = self.hzLastTime {
            let dt = now - last
            statsQueue.async {
                self.buf.write(dt)

                let (count, avg, std, max) = self.average()
                (self.window, self.avgTime, self.stdTime, self.maxDevTime) = (count, avg, std, max)

                if self.buf.availableSpaceForWriting == 0 {
                    _ = self.buf.read()
                }
            }
        }

        if let avg = self.avgTime {
            throttle(timeInterval: statsInterval) {
                guard let delegate = delegate else {
                    printHz()
                    printTime()
                    return
                }

                DispatchQueue.main.async {
                    delegate.stopWatch(self, window: self.window, didEstimateHz: 1.0 / avg)
                }
            }
        }

        self.hzLastTime = now
    }
}

// From https://stackoverflow.com/a/30754194

enum Network: String {
    case wifi = "en0"
    case en5 = "en5"
    case cellular = "pdp_ip0"
    case ipv4 = "ipv4"
    //... case ipv6 = "ipv6"
}

public func getAddress() -> [String:String] {
    var address: [String:String] = [:]

    // Get list of all interfaces on the local machine:
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return [:] }
    guard let firstAddr = ifaddr else { return [:] }

    // For each interface ...
    for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let interface = ifptr.pointee

        // Check for IPv4 or IPv6 interface:
        let addrFamily = interface.ifa_addr.pointee.sa_family
        if addrFamily == UInt8(AF_INET) { // || addrFamily == UInt8(AF_INET6) {

            // Check interface name:
            let iface = String(cString: interface.ifa_name)
//            print("iface: \(name)")

            if ["lo0", "en0", "en2", "pdp_ip0"].contains(iface) {
                // Convert interface address to a human readable string:
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, socklen_t(0), NI_NUMERICHOST)
                let addr = String(cString: hostname)
                address[iface] = addr

//                print(addr)
            }
        }
    }
    freeifaddrs(ifaddr)

    return address
}
