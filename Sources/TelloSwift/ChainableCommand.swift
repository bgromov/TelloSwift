//
//  ChainableCommand.swift
//  TelloSwift
//
//  Created by Boris Gromov on 27.05.2020.
//  Copyright © 2020 Volaly. All rights reserved.


import Foundation
import Combine

public enum Sensors {
}

/// Declares an executable command.
public protocol ExecutableCommand {
    associatedtype Output
    associatedtype Failure: Error
    associatedtype Context
    typealias CommandResult = (Result<Output, Failure>) -> Void

    func execute(context: Context?, promise: @escaping CommandResult)
}

/// A chainable command.
public class ChainableCommand<Context, Output, Failure>: Publisher where Failure: Error {
    public typealias CommandFuture = Future<Output, Failure>
    public typealias CommandPromise = CommandFuture.Promise

    /// Context associated with this command chain.
    public let context: Context?

    private var trailing: AnyPublisher<Output, Failure>
    private var committed: Bool
    private var subs: Set<AnyCancellable>
    private var semaphore: DispatchSemaphore = DispatchSemaphore(value: 1)

    internal func enqueue<Command>(command: Command) -> Self
        where Command: ExecutableCommand, Context == Command.Context, Output == Command.Output, Failure == Command.Failure
    {
        let future = CommandFuture { promise in
            command.execute(context: self.context, promise: promise)
        }

        if committed {
            // if committed, start the chain over
            trailing = future.eraseToAnyPublisher()
            committed = false
        } else {
            // otherwise, chain to the tail
            trailing = trailing
                .flatMap { _ in
                    return future
                }.eraseToAnyPublisher()
        }

        return self
    }

    /// Executes a command closure asynchronously.
    ///
    /// Executes the `block` asynchronously using a given scheduler after
    /// the previous command completes. The method can be used for reporting
    /// the state of a system.
    ///
    /// ```
    /// chain
    ///     .command()
    ///     .async(scheduler: DispatchQueue.global()) { context in
    ///         guard let context = context else {return}
    ///         print("State:", context.state)
    ///     }
    ///     .commit()
    /// ```
    ///
    /// - Parameters:
    ///   - scheduler: Scheduler, e.g. `RunLoop` or `DispatchQueue`.
    ///   - block: Closure that receives the `context`.
    ///
    public func async<S: Scheduler>(scheduler: S, block: @escaping (Context?) -> Void) -> Self {
        // FIXME: Check if committed and ignore if so
        trailing = trailing
            .map { val in
                scheduler.schedule {
                    block(self.context)
                }
                return val
            }.eraseToAnyPublisher()

        return self
    }

    /// Executes a command closure synchronously.
    ///
    /// Executes the `block` synchronously after the previous command
    /// completes. The method can be used to do additional work before
    /// executing the next command in the chain.
    ///
    /// ```
    /// chain
    ///     .initialize()
    ///     .sync { context in
    ///         guard let context = context else {return}
    ///         if context.state == .initialized {
    ///             context.loadCameraCalibration(from: "calibration.dat")
    ///         }
    ///     }
    ///     .runClassifier()
    ///     .commit()
    /// ```
    ///
    /// - Parameters:
    ///   - scheduler: Scheduler, e.g. `RunLoop` or `DispatchQueue`.
    ///   - block: Closure that receives the `context`.
    public func sync(block: @escaping (Context?) -> Void) -> Self {
        // FIXME: Check if committed and ignore if so
        trailing = trailing
            .map { val in
                block(self.context)
                return val
            }.eraseToAnyPublisher()

        return self
    }

    // FIXME: Release lock when subscription is cancelled
    public func wait(timeout: TimeInterval = TimeInterval.nan) {
        let lock = DispatchSemaphore(value: 0)
        let cancellable = trailing.sink(receiveCompletion: {_ in lock.signal()}, receiveValue: {_ in })

        if timeout != .nan {
            _ = lock.wait(timeout: .now() + timeout)
        } else {
            lock.wait()
        }
    }

    /// Commits the command chain.
    ///
    /// Subscribes to the chain of underlying `Publisher` and internally
    /// stores the reference to a cancellable.
    public func commit() {
        trailing.sink(receiveCompletion: {_ in }, receiveValue: {_ in }).store(in: &subs)
        committed = true
    }

    public func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
        trailing.receive(subscriber: subscriber)
    }

    /// Creates `ChainableCommand`.
    ///
    /// - Parameters:
    ///   - context: Arbitrary context to associate with this chain.
    ///   - attemptToFulfill: Closure to execute.
    public init(context: Context? = nil, _ attemptToFulfill: @escaping (@escaping CommandPromise) -> Void) {
        self.context = context
        committed = false
        trailing = CommandFuture(attemptToFulfill).eraseToAnyPublisher()
        subs = []
    }
}
