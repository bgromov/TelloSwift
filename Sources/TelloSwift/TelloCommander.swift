//
//  TelloCommander.swift
//  TelloSwift
//
//  Created by Boris Gromov on 26.05.2020.
//  Copyright © 2020 Volaly. All rights reserved.


import Foundation
import Network
import Combine

/// A simplified control interface for DJI/Ryze Tello drone.
///
/// The interface internally uses Future/Promise from Combine
/// framework to chain the commands. The next command in the
/// chain executed only when the previous one completes. If one
/// of the commands fail, the rest of the chain is not executed.
///
/// ```
/// // Create Tello object with default connection parameters
/// let tello = Tello()
/// // Create commander
/// let commander = TelloCommander(tello: tello)
///
/// commander
///     // Connect
///     .connect()
///     // Take off to a given altitude
///     .takeoff(altitude: 0.5)
///     // Go to a new pose but keep the altitude
///     // and orientation unchanged
///     .goTo(x:  1.0, y:  0.0, z: nil, yaw: nil)
///     // Yaw can be omitted
///     .goTo(x:  0.0, y: -1.0, z: nil)
///     .goTo(x: -1.0, y:  0.0, z: nil)
///     .goTo(x:  0.0, y:  0.0, z: nil)
///     // Land
///     .land()
///     // Disconnect
///     .disconnect()
///     // Store the command chain and execute it
///     .commit()
/// ```
///
/// Alternatively, instead of `commit()` the regular `Publisher` methods
/// can be used to store and execute the chain.
///
/// ```
/// var subs: Set<AnyCancellable> = []
///
/// commander
///     .connect()
///     .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
///     .store(in: &subs)
/// ```
public class TelloCommander: ChainableCommand<Tello, Void, Error> {
    /// Connection error.
    public struct ConnectionError: Error {}
    /// Target error.
    public struct TargetError: Error {}
    /// Context was not specified.
    public struct NoContext: Error {}
    /// Functionality is not implemented yet.
    public struct NotImplemented: Error {}

    /// Command chain.
    public typealias Chain = TelloCommander

    /// Reference to Tello instance.
    public private(set) var tello: Tello

    private lazy var command = self

    private var subs: Set<AnyCancellable>

    /// Creates `TelloCommander` object.
    ///
    /// - Parameters:
    ///   - tello: `Tello` instance.
    public init(tello: Tello) {
        self.tello = tello
        self.subs = []
        super.init(context: self.tello) { $0(.success(Void())) }
    }

    // MARK: Commands
    /// Attempts to connect to the drone.
    ///
    /// Connects using the parameters specified in `Tello` constructor.
    /// - Returns: Modified command chain.
    public func connect() -> Chain {
        return command.enqueue(command: Command.connect)
    }

    /// Disconnects from the drone.
    ///
    /// - Returns: Modified command chain.
    public func disconnect() -> Chain {
        return command.enqueue(command: Command.disconnect)
    }

    /// Takes off the drone to a given altitude above the surface.
    ///
    /// - Parameters:
    ///   - altitude: Height to get to.
    /// - Returns: Modified command chain.
    public func takeoff(altitude: Double) -> Chain {
        return command.enqueue(command: Command.takeoff(altitude: altitude))
    }

    /// Throw and go.
    ///
    /// - Parameters:
    ///   - altitude: Height to get to.
    /// - Returns: Modified command chain.
    public func throwAndGo() -> Chain {
        return command.enqueue(command: Command.throwAndGo)
    }

    /// Lands the drone.
    ///
    /// - Returns: Modified command chain.
    public func land() -> Chain {
        return command.enqueue(command: Command.land)
    }

    /// Lands the drone on the user's palm.
    ///
    /// - Returns: Modified command chain.
    public func palmLand() -> Chain {
        return command.enqueue(command: Command.palmLand)
    }

    /// Commands the drone to move to a new pose in its odometry frame.
    ///
    /// All the components of the `pose` can take `nil` as a value. In this case,
    /// the corresponding control directions will be ignored.
    ///
    /// - Parameters:
    ///   - pose: New pose.
    /// - Returns: Modified command chain.
    public func goTo(pose: QuadrotorPose) -> Chain {
        return command.enqueue(command: Command.goTo(pose: pose))
    }

    /// Commands the drone to move to a new pose in its odometry frame.
    ///
    /// All the parameters can take `nil` as a value. In this case, the corresponding
    /// control directions will be ignored.
    ///
    /// - Parameters:
    ///   - x: Coordinate along X-axis.
    ///   - y: Coordinate along Y-axis.
    ///   - z: Coordinate along Z-axis.
    ///   - yaw: Rotation around Z-axis. Defaults to `nil`.
    /// - Returns: Modified command chain.
    public func goTo(x: Double?, y: Double?, z: Double?, yaw: Double? = nil) -> Chain {
        return command.enqueue(command: Command.goTo(pose: QuadrotorPose(x: x, y: y, z: z, yaw: yaw)))
    }

    // MARK: Sensors
    /// Network connection state.
    ///
    /// - Parameters:
    ///   - block: Closure to receive network connection state.
    ///   - state: Connection state passed to closure.
    /// - Returns: Unchanged command chain.
    @discardableResult
    public func connectionState(_ block: @escaping (_ state: ConnectionState) -> Void) -> Chain {
        tello.connectionState.sink(receiveValue: {block($0)}).store(in: &subs)
        return command
    }

    /// Flight state.
    ///
    /// - Parameters:
    ///   - block: Closure to receive flight state.
    ///   - state: Flight state passed to closure.
    /// - Returns: Unchanged command chain.
    @discardableResult
    public func flightState(_ block: @escaping (_ state: FlightState) -> Void) -> Chain {
        tello.flightState.sink(receiveValue: {block($0)}).store(in: &subs)
        return command
    }

    /// Flight data.
    ///
    /// - Parameters:
    ///   - block: Closure to receive flight data.
    ///   - data: Flight data passed to closure.
    /// - Returns: Unchanged command chain.
    @discardableResult
    public func flightData(_ block: @escaping (_ data: FlightData) -> Void) -> Chain {
        tello.flightData.sink(receiveValue: {block($0)}).store(in: &subs)
        return command
    }

    /// Wi-Fi signal strength.
    ///
    /// - Parameters:
    ///   - block: Closure to receive Wi-Fi signal strength data.
    ///   - strength: Wi-Fi signal strength passed to closure.
    /// - Returns: Unchanged command chain.
    @discardableResult
    public func wifiStrength(_ block: @escaping (_ strength: UInt8) -> Void) -> Chain {
        tello.wifiStrength.sink(receiveValue: {block($0)}).store(in: &subs)
        return command
    }

    /// Light conditions.
    ///
    /// - Parameters:
    ///   - block: Closure to receive light conditions data.
    ///   - insufficient: Value passed to closure.
    /// - Returns: Unchanged command chain.
    @discardableResult
    public func lightConditions(_ block: @escaping (_ insufficient: Bool) -> Void) -> Chain {
        tello.lightConditions.sink(receiveValue: {block($0)}).store(in: &subs)
        return command
    }

    /// Inertial Measurement Unit.
    ///
    /// - Parameters:
    ///   - block: Closure to receive IMU data.
    ///   - data: IMU data passed to closure.
    /// - Returns: Unchanged command chain.
    @discardableResult
    public func imu(_ block: @escaping (_ data: Imu) -> Void) -> Chain {
        tello.imu.sink(receiveValue: {block($0)}).store(in: &subs)
        return command
    }

    /// Multiview odometry.
    ///
    /// - Parameters:
    ///   - block: Closure to receive MVO data.
    ///   - data: MVO data passed to closure.
    /// - Returns: Unchanged command chain.
    @discardableResult
    public func mvo(_ block: @escaping (_ data: Mvo) -> Void) -> Chain {
        tello.mvo.sink(receiveValue: {block($0)}).store(in: &subs)
        return command
    }

    /// Visual odometry.
    ///
    /// - Parameters:
    ///   - block: Closure to receive VO data.
    ///   - data: VO data passed to closure.
    /// - Returns: Unchanged command chain.
    @discardableResult
    public func vo(_ block: @escaping (_ data: Vo) -> Void) -> Chain {
        tello.vo.sink(receiveValue: {block($0)}).store(in: &subs)
        return command
    }
}

private extension TelloCommander {
    enum Command: ExecutableCommand {

        typealias Output = Chain.Output
        typealias Failure = Chain.Failure
        typealias Context = Tello

        case connect
        case disconnect
        case takeoff(altitude: Double)
        case throwAndGo
        case land
        case palmLand
        case goTo(pose: QuadrotorPose)

        func execute(context: Tello?, promise: @escaping CommandResult) {
            guard let context = context else {
                promise(.failure(NoContext()))
                return
            }
            switch self {
            case .connect:
                context.connectionState.sink { state in
                    if state == .connected {
                        promise(.success(Void()))
                    }
                    if state == .error {
                        promise(.failure(ConnectionError()))
                    }
                }.store(in: &context.subs)
                context.connect()
            case .disconnect:
                context.connectionState.sink { state in
                    if state == .disconnected {
                        promise(.success(Void()))
                    }
                }.store(in: &context.subs)
                context.disconnect()
            case .takeoff(altitude: let altitude):
                context.controller.state.sink { state in
                    if case .reset( _ ) = state {
                        promise(.failure(TargetError()))
                    }
                    if case .running(let runningState) = state, case .converged = runningState {
                        promise(.success(Void()))
                    }
                }.store(in: &context.subs)
                context.manualTakeoff(altitude: altitude)
            case .throwAndGo:
                context.flightState.sink { state in
                    if state == .hovering {
                        promise(.success(Void()))
                    }
                }.store(in: &context.subs)
                _ = context.throwAndGo()
            case .land:
                context.flightState.sink { state in
                    if state == .landed {
                        promise(.success(Void()))
                    }
                }.store(in: &context.subs)
                context.land()
            case .palmLand:
                context.flightState.sink { state in
                    if state == .landed {
                        promise(.success(Void()))
                    }
                }.store(in: &context.subs)
                context.palmLand()
            case .goTo(pose: let pose):
                context.controller.state.sink { state in
                    if case .reset( _ ) = state {
                        promise(.failure(TargetError()))
                    }
                    if case .running(let runningState) = state, case .converged = runningState {
                        promise(.success(Void()))
                    }
                }.store(in: &context.subs)
                context.goTo(x: pose.x, y: pose.y, z: pose.z, yaw: pose.yaw)
            }
        }
    }
}
