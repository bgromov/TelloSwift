//
//  Extensions.swift
//  TelloSwift
//
//  Created by Boris Gromov on 23.05.2020.
//  Copyright © 2020 Volaly. All rights reserved.


import Foundation
import Combine

// MARK: Data Extensions
extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
        static let dontSpaceBytes = HexEncodingOptions(rawValue: 1 << 1)
    }

    var hex: String { hex() }

    func hex(options: HexEncodingOptions = []) -> String {
        let fmt = options.contains(.upperCase) ? "%02X" : "%02x"
        return self.map { String(format: fmt, $0) }.joined(separator: options.contains(.dontSpaceBytes) ? "" : " ")
    }
}

extension Data {
    init(from shortInt: UInt16) {
        self.init([UInt8(shortInt & 0xff), UInt8(shortInt >> 8 & 0xff)])
    }
    mutating func appendLe(shortInt: UInt16) {
        self.append(UInt8(shortInt & 0xff))
        self.append(UInt8(shortInt >> 8 & 0xff))
    }
}

// MARK: Clamped
// From https://stackoverflow.com/a/40868784
extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

extension Strideable where Stride: SignedInteger {
    func clamped(to limits: CountableClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

// MARK: Combine Publishers

// Inspired by OpenCombine Publishers.Buffer implementation: https://github.com/broadwaylamb/OpenCombine

extension Publisher where Output: BinaryFloatingPoint {
    public func movingAverageByCount(count: Int, strategy: Publishers.MovingAverageStrategy) -> Publishers.MovingAverageByCount<Self> {
        return .init(upstream: self, count: count, strategy: strategy)
    }
}

extension Publishers {
    /// A strategy for calculating a sliding average.
    ///
    /// - whenFull: A strategy to calculate the first average value only when the buffer is full,
    /// and then every time a new value arrives from upstream publisher.
    /// - everyTime: A strategy to calculate the first average value every time a new value arrives
    /// from upstream publisher.
    ///
    public enum MovingAverageStrategy {
        case whenFull
        case everyTime
    }
}

extension Publishers {
    public struct MovingAverageByCount<Upstream: Publisher>: Publisher where Upstream.Output: BinaryFloatingPoint {
        public typealias Output = Double
        public typealias Failure = Upstream.Failure

        public let upstream: Upstream
        public let count: Int
        public let strategy: MovingAverageStrategy

        public init(upstream: Upstream, count: Int, strategy: MovingAverageStrategy) {
            self.upstream = upstream
            self.count = count
            self.strategy = strategy
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream) where Self.Failure == Downstream.Failure, Self.Output == Downstream.Input {
            upstream.receive(subscriber: Inner(downstream: subscriber, slidingAverage: self))
        }
    }
}

extension Publishers.MovingAverageByCount {
    private final class Inner<Downstream: Subscriber>: Subscriber, Subscription where Downstream.Input == Output, Downstream.Failure == Upstream.Failure {
        typealias Input = Upstream.Output
        typealias Failure = Upstream.Failure

        private enum State {
            case ready(Publishers.MovingAverageByCount<Upstream>, Downstream)
            case subscribed(Publishers.MovingAverageByCount<Upstream>, Downstream, Subscription)
            case terminal
        }

        private var state: State

        private var downstreamDemand = Subscribers.Demand.none

        private var terminal: Subscribers.Completion<Failure>?

        private var ringBuf: RingBuffer<Input>

        init(downstream: Downstream, slidingAverage: Publishers.MovingAverageByCount<Upstream>) {
            self.ringBuf = .init(count: slidingAverage.count)
            state = .ready(slidingAverage, downstream)
        }

        func receive(subscription: Subscription) {
            guard case let .ready(slidingAverage, downstream) = state else {
                subscription.cancel()
                return
            }

            state = .subscribed(slidingAverage, downstream, subscription)

            subscription.request(.max(ringBuf.size))
            downstream.receive(subscription: self)
        }

        func receive(_ input: Input) -> Subscribers.Demand {
            guard case .subscribed = state else {
                return .none
            }

            // Check if upstream finished
            switch terminal {
            case nil, .finished?:
                // The drain() guarantees there is at least one space in the buffer
                ringBuf.write(input)
                // Calculate an average, send it downstream, and free up space for a new item
                return drain()
            case .failure?:
                return .none
            }
        }

        // Upstream has finished
        func receive(completion: Subscribers.Completion<Upstream.Failure>) {
            guard case .subscribed = state, terminal == nil else {
                return
            }

            terminal = completion
        }

        // Downstream demands
        func request(_ demand: Subscribers.Demand) {
            guard case let .subscribed(_, _, subscription) = state else {
                return
            }
            downstreamDemand += demand
            subscription.request(downstreamDemand)
        }

        func cancel() {
            guard case let .subscribed(_, _, subscription) = state else {
                return
            }

            state = .terminal
            ringBuf = RingBuffer<Input>(count: ringBuf.size)
            subscription.cancel()
        }

        private func drain() -> Subscribers.Demand {
            var upstreamDemand = Subscribers.Demand.none

            guard case let .subscribed(slidingAverage, downstream, _) = state else {
                return upstreamDemand
            }

            // Did upstream complete?
            if let completion = terminal {
                state = .terminal
                downstream.receive(completion: completion)
            }

            // Calculate average of current buffer
            let value: Double = ringBuf.average()
            var newDownstreamDemand = Subscribers.Demand.none

            // Are we full?
            if ringBuf.availableSpaceForWriting == 0 {
                // Drop first
                _ = ringBuf.read()
                if slidingAverage.strategy == .whenFull {
                    // Send the value downstream
                    newDownstreamDemand += downstream.receive(value)
                }
            }

            if slidingAverage.strategy == .everyTime {
                newDownstreamDemand = downstream.receive(value)
            }

            downstreamDemand -= 1
            downstreamDemand += newDownstreamDemand

            upstreamDemand = Subscribers.Demand.max(ringBuf.availableSpaceForWriting)

            return upstreamDemand
        }
    }
}
