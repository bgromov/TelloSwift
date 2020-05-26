//
//  Sensor.swift
//  TelloSwift
//
//  Created by Boris Gromov on 16.05.2020.
//  Copyright © 2020 Volaly. All rights reserved.


import Foundation
import Combine
import simd

infix operator <- : AssignmentPrecedence

public class Sensor<T>: Publisher where T: Equatable {
    public typealias DataType = T
    public typealias Output = T
    public typealias Failure = Never

    private let repeatedValues: Bool

    private var subj: PassthroughSubject<Output, Failure>?
    public func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
        // We don't need share() or multicast() here as PassthroughSubject
        // wraps the value into a class and thus is passed by reference
        subj?.receive(subscriber: subscriber)
    }

    public internal(set) var testVal: Int = 0
    public internal(set) var value: Output? {
        willSet {
            if let val = newValue {
                if (!repeatedValues) && (newValue == value) {
                    return
                }
                // send new value, old one can be accessed with `value` property
                subj?.send(val)
            }
        }
    }

    init(with value: T?, repeatedValues: Bool = true) {
        // First initialize value, so send() is not triggered
        self.value = value
        self.subj = PassthroughSubject<Output, Failure>()
        self.repeatedValues = repeatedValues
    }

    init(repeatedValues: Bool = true) {
        self.subj = PassthroughSubject<Output, Failure>()
        self.repeatedValues = repeatedValues
    }

    internal static func <- (left: Sensor<Output>, right: Output?) {
        left.value = right
    }

    public static func == (left: Sensor<Output>, right: Output?) -> Bool {
        return left.value == right
    }

    public static func != (left: Sensor<Output>, right: Output?) -> Bool {
        return left.value != right
    }
}

public struct IsValid: Equatable {
    var x: Bool
    var y: Bool
    var z: Bool
}

public struct IsValidVelPos: Equatable {
    var vel: IsValid
    var pos: IsValid
}

public extension Bool {
    init(_ isValid: IsValid) {
        self = (isValid.x && isValid.y && isValid.z)
    }
}

public protocol PositionMeasurement: Equatable {
    var velocity: simd_double3 { get }
    var position: simd_double3 { get }

    var isValid: IsValidVelPos { get }
}

public protocol OrientationMeasurement: Equatable {
    var orientation: simd_quatd { get }
}

//public protocol OdometryMeasurement: PositionMeasurement, OrientationMeasurement { }

public struct AnyPositionMeasurement: PositionMeasurement {
    public var velocity: simd_double3
    public var position: simd_double3

    public var isValid: IsValidVelPos

    public init(velocity: simd_double3, position: simd_double3, isValid: IsValidVelPos) {
        self.velocity = velocity
        self.position = position
        self.isValid = isValid
    }

    public init<T>(_ measurement: T) where T: PositionMeasurement {
        self.velocity = measurement.velocity
        self.position = measurement.position
        self.isValid = measurement.isValid
    }
}

public struct AnyOrientationMeasurement: OrientationMeasurement {
    public var orientation: simd_quatd

    public init(orientation: simd_quatd) {
        self.orientation = orientation
    }

    public init<T>(_ measurement: T) where T: OrientationMeasurement {
        self.orientation = measurement.orientation
    }
}
