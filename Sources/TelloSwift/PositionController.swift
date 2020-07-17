//
//  PositionController.swift
//  TelloSwift
//
//  Created by Boris Gromov on 25.04.2020.
//  Copyright © 2020 Volaly. All rights reserved.


import Foundation
import Combine

import Transform

/// Quadrotor controls
public struct QuadrotorControls: Equatable, CustomDebugStringConvertible {
    /// Rotation around X-axis (positive counter-clockwise)
    public var roll: Double?
    /// Rotation around Y-axis (positive counter-clockwise)
    public var pitch: Double?
    /// Rotation around Z-axis (positive counter-clockwise)
    public var yaw: Double?
    /// Thrust
    public var thrust: Double?

    /// Creates QuadrotorControls with all members set to nil.
    public init() {}

    /// Creates QuadrotorControls with specified parameters.
    public init(roll: Double?, pitch: Double?, yaw: Double?, thrust: Double?) {
        self.roll = roll
        self.pitch = pitch
        self.yaw = yaw
        self.thrust = thrust
    }

    @discardableResult
    fileprivate mutating func assignNonEmpty(other: QuadrotorControls) -> QuadrotorControls {
        if let r = other.roll   {roll = r}
        if let p = other.pitch  {pitch = p}
        if let y = other.yaw    {yaw = y}
        if let t = other.thrust {thrust = t}

        return self
    }

    public var isEmpty: Bool {
        get {
            return roll == nil && pitch == nil && yaw == nil && thrust == nil
        }
    }

    public var debugDescription: String {
        get {
            String(format: "Controls(r: %@, p: %@, y: %@, t: %@)",
                   roll   != nil ? String(format: "%3.3f", roll!)   : "nil",
                   pitch  != nil ? String(format: "%3.3f", pitch!)  : "nil",
                   yaw    != nil ? String(format: "%3.3f", yaw!)    : "nil",
                   thrust != nil ? String(format: "%3.3f", thrust!) : "nil")
        }
    }
}

/// Quadrotor pose
public struct QuadrotorPose: Equatable, CustomDebugStringConvertible {
    /// Position along X-axis
    public var x: Double?
    /// Position along Y-axis
    public var y: Double?
    /// Position along Z-axis
    public var z: Double?
    /// Rotation around Z-axis
    public var yaw: Double?

    /// Creates QuadrotorPose with all members set to nil.
    public init() {}
    /// Creates QuadrotorPose with specified parameters.
    public init(x: Double?, y: Double?, z: Double?, yaw: Double?) {
        self.x = x
        self.y = y
        self.z = z
        self.yaw = yaw
    }

    @discardableResult
    fileprivate mutating func assignNonEmpty(other: QuadrotorPose) -> QuadrotorPose {
        if let x   = other.x   {self.x = x}
        if let y   = other.y   {self.y = y}
        if let z   = other.z   {self.z = z}
        if let yaw = other.yaw {self.yaw = yaw}

        return self
    }

    static public func - (lhs: QuadrotorPose, rhs: QuadrotorPose) -> QuadrotorPose {
        var x, y, z, yaw: Double?

        if let lx = lhs.x, let rx = rhs.x {
            x = lx - rx
        }

        if let ly = lhs.y, let ry = rhs.y {
            y = ly - ry
        }

        if let lz = lhs.z, let rz = rhs.z {
            z = lz - rz
        }

        if let lyaw = lhs.yaw, let ryaw = rhs.yaw {
            yaw = lyaw - ryaw
        }

        return QuadrotorPose(x: x, y: y, z: z, yaw: yaw)
    }

    public var debugDescription: String {
        get {
            String(format: "Pose(x: %@, y: %@, z: %@, yaw: %@)",
                   x   != nil ? String(format: "%3.3f", x!)   : "nil",
                   y   != nil ? String(format: "%3.3f", y!)   : "nil",
                   z   != nil ? String(format: "%3.3f", z!)   : "nil",
                   yaw != nil ? String(format: "%3.2f deg", rad2deg(yaw!)) : "nil")
        }
    }
}

/// Position controller for a quadrotor.
///
/// Takes 3D position and orientation in horizontal plane (`x`, `y`, `z`, and `yaw`) as input
/// and outputs four velocity controls (`roll`, `pitch`, `yaw`, and `thrust`).
/// Each control axis uses its own independent PID controller.
public class PositionController {
    /// PID controllers for four control axes
    public struct Pid3D {
        var x: Pid
        var y: Pid
        var z: Pid
        var yaw: Pid
    }

    public enum ResetReason {
        case originChanged
        case sensorFailure
        case targetCompleted
        case targetCanceled
    }

    public enum Running {
        case correcting
        case converged
    }

    public enum State: Equatable {
        /// Initialized and has nothing to do
        case idle
        /// Running
        case running(Running)
        /// Controller was reset
        case reset(ResetReason)
    }

    /// Controller state
    public private(set) var state: Sensor<State>

    /// Controllers for each control axis
    public let pid: Pid3D

    /// User-specified target pose (read-only). To set the target use `setTarget()`.
    public private(set) var target: Sensor<QuadrotorPose>
    ///
    public private(set) var holdTarget: Bool = false

    public private(set) var origin: QuadrotorPose = QuadrotorPose(x: 0.0, y: 0.0, z: 0.0, yaw: 0.0) {
        didSet {
            print("New origin: ", origin)
        }
    }

    /// Time-aggregated measurements.
    ///
    /// Since measurements for each axis may arrive independently, at any given moment some of the values could be `nil`.
    /// This property aggregates all the latest non-nil measurements.
    public private(set) var input: Sensor<QuadrotorPose>

    /// Time-aggregated controls.
    ///
    /// Since all PIDs update independently, some of the controlls might be `nil`.
    /// This property aggregates all the latest non-nil controls.
    public private(set) var output: Sensor<QuadrotorControls>

    private var sourcesSubs: Set<AnyCancellable> = []

    private var stateSub: AnyCancellable?

    private var posSensorFailCount: Int = 0
    private let posSensorFailThreshold: Int = 30
    private var posSensorFailed: Bool = false

    /// Creates position controller with four independent axes
    ///
    /// - Parameters:
    ///   - x: PID controller for X-axis
    ///   - y: PID controller for Y-axis
    ///   - z: PID controller for Z-axis
    ///   - yaw: PID controller for Yaw (rotation around Z-axis)
    public init(x: Pid, y: Pid, z: Pid, yaw: Pid){
        self.pid = Pid3D(x: x, y: y, z: z, yaw: yaw)

        input = Sensor<QuadrotorPose>()
        input.value = QuadrotorPose()

        output = Sensor<QuadrotorControls>()
        output.value = QuadrotorControls()

        target = Sensor<QuadrotorPose>() // Initialize with nil value

        state = Sensor<State>(repeatedValues: false)
        stateSub = state.sink { print("Controller State:", $0) }

        state <- .idle
    }

    /// Connects the controller to position and orientation measurement sources.
    public func source<P, O>(position: Sensor<P>, orientation: Sensor<O>) -> Sensor<QuadrotorControls>
        where P: PositionMeasurement, O: OrientationMeasurement
    {
        // Clean previously stored subscribers
        sourcesSubs = []

        // Subscribe to position measurements updates
        position.sink {
            // Count number of sensor failures
            if $0.isValid.pos.x && $0.isValid.pos.y {
                self.posSensorFailCount = 0
                self.posSensorFailed = false
            } else {
                if !self.posSensorFailed {
                    self.posSensorFailCount += 1

                    if self.posSensorFailCount >= self.posSensorFailThreshold {
                        self.posSensorFailed = true
                        self.reset(.sensorFailure)
                    }
                }
            }

            // Make pose
            let pose = QuadrotorPose(x: $0.position.x, y: $0.position.y, z: $0.position.z, yaw: nil) - self.origin
            // Aggregate inputs (measurements)
            self.input.value?.assignNonEmpty(other: pose)
            // Calculate correction
            if let corr = self.update(measured: pose) {
                // Aggregate outputs (controls)
                self.output.value?.assignNonEmpty(other: corr)
            }
        }.store(in: &sourcesSubs)

        // Subscribe to orientation measurements updates
        orientation.sink {
            // Make pose
            let pose = QuadrotorPose(x: nil, y: nil, z: nil, yaw: $0.orientation.rpy.yaw) - self.origin
            // Aggregate inputs (measurements)
            self.input.value?.assignNonEmpty(other: pose)
            // Calculate correction
            if let corr = self.update(measured: pose) {
                // Aggregate outputs (controls)
                self.output.value?.assignNonEmpty(other: corr)
            }
        }.store(in: &sourcesSubs)

        // Chain output
        return output
    }

    /// Sets new target (desired) pose.
    ///
    /// - Remark: This method resets all internal PID controllers.
    ///
    /// - Parameters:
    ///   - target: four-dimensional pose.
    public func setTarget(target: QuadrotorPose) {
        self.target <- target

        // TODO: Maybe reset only those which targets are not nil, so
        // the non-reset controllers keep react to disturbances
        pid.x.reset()
        pid.y.reset()
        pid.z.reset()
        pid.yaw.reset()

        print("New target: ", target)
    }

    /// Sets controller frame origin to given pose in input frame.
    public func setOrigin(origin: QuadrotorPose) {
        self.reset(.originChanged)

        self.origin = origin
    }

    /// Sets controller frame origin to current input pose.
    public func setOriginToCurrentPose() {
        if let pose = input.value {
            setOrigin(origin: pose)
        }
    }

    /// Sets controller frame origin to input frame origin
    public func resetOrigin() {
        setOrigin(origin: QuadrotorPose(x: 0.0, y: 0.0, z: 0.0, yaw: 0.0))
    }

    /// Resets target, controls, and PIDs.
    public func reset(_ reason: ResetReason) {
        guard state.value! != .idle else { return }

        self.target <- nil

        input.value = QuadrotorPose()
        output.value = QuadrotorControls()

        pid.x.reset()
        pid.y.reset()
        pid.z.reset()
        pid.yaw.reset()

        state <- .reset(reason)
        state <- .idle
        // FIXME: Publish controller state
        //print("Controlled did reset: \(reason)")
    }

    /// Calculates the control values based on the actual (measured) pose of the quadrotor.
    ///
    /// - Parameters:
    ///   - measured: Actual (measured) pose of the quadrotor.
    /// - Returns: Control values for `roll`, `pitch`, `yaw`, and `thrust`.
    public func update(measured: QuadrotorPose) -> QuadrotorControls? {
        guard let t = target.value else {
            state <- .idle
            //print("error: No target set")
            return nil
        }

        state <- .running(.correcting)

        var result: QuadrotorControls = QuadrotorControls() // all set to nil
        var converged: [Bool?] = []

        // +X is proportional to +Pitch
        if let targetX = t.x, let measuredX = measured.x {
            if !(targetX.isNaN || measuredX.isNaN) {
                result.pitch = pid.x.update(setPoint: targetX, measuredValue: measuredX)
            }
            converged.append(pid.x.converged)
            //print("debug: Update pitch control")
        }

        // +Y is proportional to -Roll
        if let targetY = t.y, let measuredY = measured.y {
            if !(targetY.isNaN || measuredY.isNaN) {
                // Invert roll
                result.roll = -1.0 * pid.y.update(setPoint: targetY, measuredValue: measuredY)
            }
            converged.append(pid.y.converged)
            //print("debug: Update roll control")
        }

        // +Z is proportional to +Thrust
        if let targetZ = t.z, let measuredZ = measured.z {
            if !(targetZ.isNaN || measuredZ.isNaN) {
                result.thrust = pid.z.update(setPoint: targetZ, measuredValue: measuredZ)
            }
            converged.append(pid.z.converged)
            //print("debug: Update thrust control")
        }

        // Yaw
        if let targetYaw = t.yaw, let measuredYaw = measured.yaw {
            if !(targetYaw.isNaN || measuredYaw.isNaN) {
                result.yaw = pid.yaw.update(setPoint: targetYaw, measuredValue: measuredYaw)
            }
            converged.append(pid.yaw.converged)
            //print("debug: Update yaw control")
        }

        result.assignNonEmpty(other: result)

        if !converged.isEmpty && converged.allSatisfy({ $0 == true }) {
            state <- .running(.converged)
        }

        return result
    }
}
