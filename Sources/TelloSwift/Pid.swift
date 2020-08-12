//
//  Pid.swift
//  TelloSwift
//
//  Created by Boris Gromov on 25.04.2020.
//  Copyright © 2020 Volaly. All rights reserved.


import Foundation
import QuartzCore.CoreAnimation

/// Implementation of a simple [Proportional-Integral-Derivative](https://en.wikipedia.org/wiki/PID_controller) (PID) controller with a deadband.
///
/// - Remark: The controller uses wall-time clock to estimate the time
/// between measurements to calculate the integrals and derivatives, and
/// therefore can be only used for online control.
public class Pid {
    private var kP: Double
    private var kI: Double
    private var kD: Double

    /// The error within the closed interval [`-deadband`; `deadband`]
    /// is considered to be zero. In other words, the controller output is set to 0.0,
    /// if the difference between measured and target values is less than `deadband`.
    public var deadband: Double

    /// Indicates that error converged to dead band interval.
    public private(set) var converged: Bool

    private var ringBuf: RingBuffer<Double>

    /// Proportional (P) gain of the controller. Must be more than or equal to zero.
    ///
    /// Setting this parameter will reset the integral and derivative of the error.
    public var p: Double {
        get { return kP }
        set {
            guard kP >= 0.0 else {
                print("error: PID gains can't be less than zero. Requested: {P: \(newValue)}")
                return
            }
            // Reset controller
            self.reset()
            kP = newValue
            print("info: New gains: {P: \(kP), I: \(kI), D: \(kD)}")
        }
    }

    /// Integral (I) gain of the controller. Must be more than or equal to zero.
    ///
    /// Setting this parameter will reset the integral and derivative of the error.
    public var i: Double {
        get { return kI }
        set {
            guard kI >= 0.0 else {
                print("error: PID gains can't be less than zero. Requested: {I: \(newValue)}")
                return
            }
            // Reset controller
            self.reset()
            kI = newValue
            print("info: New gains: {P: \(kP), I: \(kI), D: \(kD)}")
        }
    }

    /// Derivative (D) gain of the controller. Must be more than or equal to zero.
    ///
    /// Setting this parameter will reset the integral and derivative of the error.
    public var d: Double {
        get { return kD }
        set {
            guard kD >= 0.0 else {
                print("error: PID gains can't be less than zero. Requested: {D: \(newValue)}")
                return
            }
            // Reset controller
            self.reset()
            kD = newValue
            print("info: New gains: {P: \(kP), I: \(kI), D: \(kD)}")
        }
    }

    /// Array of the controller gains [P, I, D]. All must be more than or equal to zero.
    ///
    /// Setting this parameter will reset the integral and derivative of the error.
    public var gains: [Double] {
        get { [kP, kI, kD] }
        set(pid) {
            precondition(pid.count == 3, "Number of PID gains must be exactly 3")
            if (pid.first { $0 < 0.0 }) != nil {
                print("error: PID gains can't be less than zero: {P: \(kP), I: \(kI), D: \(kD)}")
                return
            }
            (kP, kI, kD) = (pid[0], pid[1], pid[2])
            // Reset controller
            self.reset()
            print("info: New gains: {P: \(kP), I: \(kI), D: \(kD)}")
        }
    }

    public private(set) var lastError: Double?
    public private(set) var lastDError: Double?
    public private(set) var integralError: Double?
    private var lastTime: CFTimeInterval?

    /// Creates a PID controller with specified gains and a deadband.
    ///
    /// The integral and derivative gains start contributing to the controller output only on the second call to `update()`.
    ///
    /// - Parameters:
    ///   - p: Proportional gain of the controller. Must be more than or equal to zero.
    ///   - i: Integral gain of the controller. Must be more than or equal to zero.
    ///   - d: Derivative gain of the controller. Must be more than or equal to zero.
    ///   - deadband: Allows controller to threshold and ignore errors smaller than the specified value. That is particularly useful for measurements with high variance (noise).
    ///   - windowSize: Number of last samples to consider when calculating convergence.
    public init?(p: Double, i: Double, d: Double, deadband: Double = 0.001, windowSize: Int = 5) {
        guard p >= 0.0 && i >= 0.0 && d >= 0.0 else {
            print("error: PID gains can't be less than zero: {P: \(p), I: \(i), D: \(d)}")
            return nil
        }

        guard deadband >= 0 else {
            print("error: PID deadband can't be less than zero: \(deadband)")
            return nil
        }

        self.kP = p
        self.kI = i
        self.kD = d

        self.deadband = deadband
        self.converged = false
        self.ringBuf = RingBuffer(count: windowSize)
    }

    /// Convenience initializer. Creates PID controller with gains specified as elements of array.
    /// - Parameters:
    ///   - pid: Array of 3 doubles corresponding to [P, I, D] terms of the controller.
    ///   - deadband: Allows controller to threshold and ignore errors smaller than the specified value. That is particularly useful for measurements with high variance (noise).
    public convenience init?(_ pid: [Double], deadband: Double = 0.001) {
        precondition(pid.count == 3, "Number of PID gains must be exactly 3")
        self.init(p: pid[0], i: pid[1], d: pid[2], deadband: deadband)
    }

    /// Resets the integral and derivative of the controller.
    public func reset() {
        lastError = nil
        lastDError = nil
        lastTime = nil
        integralError = nil
        converged = false
        ringBuf = RingBuffer(count: ringBuf.size)
    }

    /// Calculates the correction based on the desired and the actual values of the process variable.
    ///
    /// - Parameters:
    ///   - setPoint: Desired (target) value of the process variable.
    ///   - measuredValue: Actual value of the process variable.
    /// - Returns: Corrected value of the control variable.
    public func update(setPoint: Double, measuredValue: Double) -> Double {
        // FIXME: Pass current time as a parameter / evaluate from user-specified closure
        let now = CACurrentMediaTime()
        let error: Double = setPoint - measuredValue
        var avgError: Double = .infinity

        // Wait until the buffer is full
        if ringBuf.isFull {
            avgError = ringBuf.average()
            _ = ringBuf.read()
        }
        ringBuf.write(error)

        self.converged = (-deadband...deadband).contains(avgError)

        var dE: Double = 0.0
        var res: Double

        if let lastE = lastError {
            dE = error - lastE
        }

        // Proportional
        let p = kP * error
        // Integral
        var i: Double = 0.0
        // Derivative
        var d: Double = 0.0

        if let lastT = lastTime {
            let dt = now - lastT

            let newIntegral = dE * dt

            integralError = (integralError == nil) ?  newIntegral : integralError! + newIntegral

            i = kI * integralError!
            d = kD * dE / dt
        }

        res = p + i + d

        lastError = error
        lastDError = dE
        lastTime = now

        return res
    }
}

extension Pid: CustomDebugStringConvertible {
    public var debugDescription: String {
        return String(format: "PID E: %3.3f, dE: %3.3f", lastError ?? Double("NaN")!, lastDError ?? Double("NaN")!)
    }
}
