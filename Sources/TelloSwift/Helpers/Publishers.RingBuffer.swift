//
//  Publishers.RingBuffer.swift
//
//
//  Created by Boris Gromov on 25.07.2020.
//

import Foundation
import Combine

public extension Publisher {
    /// A publisher that buffers elements from an upstream publisher in a ring buffer.
    /// - Parameters:
    ///    - size: buffer size
    ///    - strategy: when set to `.always` (default) generates output with first upstream element; when set to `.whenFull` generates output after the buffer is full
    func ringBuffer(size: Int, strategy: Publishers.RingBuffer<Self>.OutputStrategy = .always) -> Publishers.RingBuffer<Self> {
        return Publishers.RingBuffer(upstream: self, size: size, strategy: strategy)
    }
}

public extension Publishers {
    /// A publisher that buffers elements from an upstream publisher in a ring buffer.
    struct RingBuffer<Upstream> : Publisher where Upstream : Publisher {
        /// The kind of values published by this publisher.
        public typealias Output = [Upstream.Output]

        /// The kind of errors this publisher might publish.
        ///
        /// Use `Never` if this `Publisher` does not publish errors.
        public typealias Failure = Upstream.Failure

        /// The publisher from which this publisher receives elements.
        public let upstream: Upstream

        /// The maximum number of elements to store.
        public let size: Int

        /// Output strategy
        public let strategy: OutputStrategy

        public init(upstream: Upstream, size: Int, strategy: OutputStrategy) {
            self.upstream = upstream
            self.size = size
            self.strategy = strategy
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where Downstream.Input == Output, Downstream.Failure == Failure
        {
            upstream.subscribe(Inner(downstream: subscriber, size: size, strategy: strategy))
        }
    }
}

public extension Publishers.RingBuffer {
    /// Output strategy for a ring buffer publisher.
    enum OutputStrategy {
        /// Start producing output immediately with the first upstream element.
        case always
        /// Start producing output only when the buffer is full.
        case whenFull
    }
}

extension Publishers.RingBuffer {
    private final class Inner<Downstream: Subscriber> : Subscriber where Downstream.Input == Output, Downstream.Failure == Upstream.Failure {

        typealias Input = Upstream.Output
        typealias Failure = Upstream.Failure

        let downstream: Downstream
        let strategy: OutputStrategy
        var buf: RingBuffer<Input>

        init(downstream: Downstream, size: Int, strategy: OutputStrategy) {
            self.downstream = downstream
            self.strategy = strategy
            self.buf = RingBuffer<Input>(count: size)
        }

        func receive(subscription: Subscription) {
            downstream.receive(subscription: subscription)
        }

        func receive(_ input: Upstream.Output) -> Subscribers.Demand {
            buf.write(input)

            let output = Array(buf)

            if strategy == .always {
                _ = downstream.receive(output)
            }

            if buf.isFull {
                if strategy == .whenFull {
                    _ = downstream.receive(output)
                }

                // Drop oldest
                _ = buf.read()
            }

            return .max(buf.availableSpaceForWriting)
        }

        func receive(completion: Subscribers.Completion<Upstream.Failure>) {
            downstream.receive(completion: completion)
        }
    }
}
