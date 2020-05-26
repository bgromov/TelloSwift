//
//  Transform.swift
//  TelloSwift
//
//  Created by Boris Gromov on 24/05/2019.
//  Copyright © 2019 Volaly. All rights reserved.


import Foundation
import simd

public extension simd_double4x4 {
    var diag: simd_double4 { simd_double4((0..<4).map { self[$0, $0] }) }

    init(_ m: simd_float4x4) {
        self.init(columns: (simd_double4(m.columns.0),
                            simd_double4(m.columns.1),
                            simd_double4(m.columns.2),
                            simd_double4(m.columns.3)))
    }
}

public extension simd_float4x4 {
    var diag: simd_float4 { simd_float4((0..<4).map { self[$0, $0] }) }

    init(_ m: simd_double4x4) {
        self.init(columns: (simd_float4(m.columns.0),
                            simd_float4(m.columns.1),
                            simd_float4(m.columns.2),
                            simd_float4(m.columns.3)))
    }
}

public extension simd_double3x3 {
    var diag: simd_double3 { simd_double3((0..<3).map { self[$0, $0] }) }

    /// Plain data in row-major order
    var rm_data: [Double] {
        return [columns.0[0], columns.1[0], columns.2[0],
                columns.0[1], columns.1[1], columns.2[1],
                columns.0[2], columns.1[2], columns.2[2]]
    }

    init(_ m: simd_float3x3) {
        self.init(columns: (simd_double3(m.columns.0),
                            simd_double3(m.columns.1),
                            simd_double3(m.columns.2)))
    }
}

public extension simd_float3x3 {
    var diag: simd_float3 { simd_float3((0..<3).map { self[$0, $0] }) }

    /// Plain data in row-major order
    var rm_data: [Float] {
        return [columns.0[0], columns.1[0], columns.2[0],
                columns.0[1], columns.1[1], columns.2[1],
                columns.0[2], columns.1[2], columns.2[2]]
    }

    init(_ m: simd_double3x3) {
        self.init(columns: (simd_float3(m.columns.0),
                            simd_float3(m.columns.1),
                            simd_float3(m.columns.2)))
    }
}

public extension simd_quatd {
    /// The x-component of the imaginary (vector) part.
    var x: Double { return imag.x }
    /// The y-component of the imaginary (vector) part.
    var y: Double { return imag.y }
    /// The z-component of the imaginary (vector) part.
    var z: Double { return imag.z }
    /// The real (scalar) part.
    var w: Double { return real }

    var rpy: (roll: Double, pitch: Double, yaw: Double) {
        get {
            let mat: simd_double3x3 = simd_double3x3(self)

            var yaw = Double.nan
            var pitch = Double.nan
            var roll = Double.nan

            pitch = atan2(-mat.rm_data[6], sqrt((mat.rm_data[0] * mat.rm_data[0] + mat.rm_data[3] * mat.rm_data[3])))

            if fabs(pitch) > (Double.pi / 2 - Double.ulpOfOne) {
                yaw  = atan2(-mat.rm_data[1], mat.rm_data[4])
                roll = 0.0
            } else {
                roll = atan2(mat.rm_data[7], mat.rm_data[8])
                yaw  = atan2(mat.rm_data[3], mat.rm_data[0])
            }

            return (roll: roll, pitch: pitch, yaw: yaw)
        }
    }

    init(roll: Double = 0.0, pitch: Double = 0.0, yaw: Double = 0.0) {
        let hy = yaw / 2.0
        let hp = pitch / 2.0
        let hr = roll / 2.0

        let cy = cos(hy)
        let sy = sin(hy)
        let cp = cos(hp)
        let sp = sin(hp)
        let cr = cos(hr)
        let sr = sin(hr)

        let quat: simd_double4 =
            simd_double4(x: sr * cp * cy - cr * sp * sy,
                         y: cr * sp * cy + sr * cp * sy,
                         z: cr * cp * sy - sr * sp * cy,
                         w: cr * cp * cy + sr * sp * sy)

        self.init(vector: quat)
    }
}

public extension simd_quatf {
    /// The x-component of the imaginary (vector) part.
    var x: Float { return imag.x }
    /// The y-component of the imaginary (vector) part.
    var y: Float { return imag.y }
    /// The z-component of the imaginary (vector) part.
    var z: Float { return imag.z }
    /// The real (scalar) part.
    var w: Float { return real }

    var rpy: (roll: Float, pitch: Float, yaw: Float) {
        get {
            let mat: simd_float3x3 = simd_float3x3(self)

            var yaw = Float.nan
            var pitch = Float.nan
            var roll = Float.nan

            pitch = atan2(-mat.rm_data[6], sqrt((mat.rm_data[0] * mat.rm_data[0] + mat.rm_data[3] * mat.rm_data[3])))

            if abs(pitch) > (Float.pi / 2 - Float.ulpOfOne) {
                yaw  = atan2(-mat.rm_data[1], mat.rm_data[4])
                roll = 0.0
            } else {
                roll = atan2(mat.rm_data[7], mat.rm_data[8])
                yaw  = atan2(mat.rm_data[3], mat.rm_data[0])
            }

            return (roll: roll, pitch: pitch, yaw: yaw)
        }
    }

    init(roll: Float = 0.0, pitch: Float = 0.0, yaw: Float = 0.0) {
        let hy = yaw / 2.0
        let hp = pitch / 2.0
        let hr = roll / 2.0

        let cy = cos(hy)
        let sy = sin(hy)
        let cp = cos(hp)
        let sp = sin(hp)
        let cr = cos(hr)
        let sr = sin(hr)

        let quat: simd_float4 =
            simd_float4(x: sr * cp * cy - cr * sp * sy,
                         y: cr * sp * cy + sr * cp * sy,
                         z: cr * cp * sy - sr * sp * cy,
                         w: cr * cp * cy + sr * sp * sy)

        self.init(vector: quat)
    }
}

public extension String.StringInterpolation {
    mutating func appendInterpolation(_ v: simd_float3x3, _ width: Int = 8) {
        var str: String = "["
        for i in 0..<v.rm_data.count {
            if (i + 1) % 3 == 1 {
                if i == 0 {
                    str += "["

                } else {
                    str += String(repeating: " ", count: description.count + 1)
                    str += "["
                }
            }
            str += String(format: "%\(width).2g", v.rm_data[i])
            if (i + 1) % 3 == 0 {
                if (i + 1) != v.rm_data.count {
                    str += "],\n"
                } else {
                    str += "]\n"
                }
            } else {
                str += ", "
            }
        }
        str = str.trimmingCharacters(in: .controlCharacters) + "]"
        appendInterpolation(str)
    }
    
    mutating func appendInterpolation(_ v: simd_double3x3, _ width: Int = 8) {
        var str: String = "["
        for i in 0..<v.rm_data.count {
            if (i + 1) % 3 == 1 {
                if i == 0 {
                    str += "["

                } else {
                    str += String(repeating: " ", count: description.count + 1)
                    str += "["
                }
            }
            str += String(format: "%\(width).2g", v.rm_data[i])
            if (i + 1) % 3 == 0 {
                if (i + 1) != v.rm_data.count {
                    str += "],\n"
                } else {
                    str += "]\n"
                }
            } else {
                str += ", "
            }
        }
        str = str.trimmingCharacters(in: .controlCharacters) + "]"
        appendInterpolation(str)
    }
}

public extension SIMD where Scalar: Numeric {
    var flat: [Scalar] { indices.map{ self[$0] }}
    
    func str(_ scalarFormat: String = "%3.2g") -> String {
        let vals = indices.map{ self[$0] }
        let strs = vals.map { String(format: scalarFormat, $0 as! CVarArg) }
        return "[" + strs.joined(separator: ", ") + "]"
    }
}

// Inspired by ROS tf library
public class Transform: NSObject {
    public static let identity: Transform = Transform(simd_double3x3(1.0), simd_double3(repeating: 0.0))

    private var mBasis: simd_double3x3 = simd_double3x3(1.0) // identity rotation matrix
    private var mOrigin: simd_double3 = simd_double3(repeating: 0.0) // zero vector

    public var basis: simd_double3x3 {
        get {
            return mBasis
        }
        set {
            mBasis = newValue
        }
    }
    public var rotation: simd_quatd {
        get {
            return simd_quatd(mBasis)
        }
        set {
            mBasis = simd_double3x3.init(newValue)
        }
    }
    public var origin: simd_double3 {
        get {
            return mOrigin
        }
        set {
            mOrigin = newValue
        }
    }
    public var inversed: Transform {
        let inv = mBasis.transpose
        return Transform(inv, inv * -mOrigin)
    }

    public var matrix: simd_double4x4 {
        let m = simd_double4x4(simd_double4(mBasis.columns.0.x, mBasis.columns.0.y, mBasis.columns.0.z, 0.0),
                               simd_double4(mBasis.columns.1.x, mBasis.columns.1.y, mBasis.columns.1.z, 0.0),
                               simd_double4(mBasis.columns.2.x, mBasis.columns.2.y, mBasis.columns.2.z, 0.0),
                               simd_double4(mOrigin.x,          mOrigin.y,          mOrigin.z,          1.0))
        return m
    }

    public override init() {}

    public init(_ matrix: simd_double4x4) {
        mBasis = simd_double3x3(simd_double3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
                                simd_double3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
                                simd_double3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))

        mOrigin = simd_double3(x: matrix.columns.3.x, y: matrix.columns.3.y, z: matrix.columns.3.z)
    }

    public init(_ quaternion: simd_quatd, _ origin: simd_double3 = simd_double3(repeating: 0.0)) {
        mBasis = simd_double3x3(quaternion)
        mOrigin = origin
    }

    public init(_ basis: simd_double3x3, _ origin: simd_double3 = simd_double3(repeating: 0.0)) {
        mBasis = basis
        mOrigin = origin
    }

    public init(_ copyFrom: Transform) {
        mBasis = copyFrom.mBasis
        mOrigin = copyFrom.mOrigin
    }

    public func mult(_ t1: Transform, _ t2: Transform) -> Void {
        mBasis = t1.mBasis * t2.mBasis
        mOrigin = t1.transformVector(t2.mOrigin)
    }

    private func transformVector(_ vector: simd_double3) -> simd_double3 {
        let rot = mBasis.transpose
        return simd_double3(x: simd_dot(rot[0], vector) + mOrigin.x,
                            y: simd_dot(rot[1], vector) + mOrigin.y,
                            z: simd_dot(rot[2], vector) + mOrigin.z)
    }

    public static func * (_ t1: Transform, _ t2: Transform) -> Transform {
        return Transform(t1.mBasis * t2.mBasis, t1.transformVector(t2.mOrigin))
    }

    public static func * (_ transform: Transform, _ vector: simd_double3) -> simd_double3 {
        return transform.transformVector(vector)
    }

    public static func * (_ transform: Transform, _ quaternion: simd_quatd) -> simd_quatd {
        return transform.rotation * quaternion
    }

    public static func *= (_ transform: inout Transform, _ other: Transform) -> Void {
        transform.mBasis *= other.mBasis
        transform.mOrigin += other.mOrigin
    }

    public func setIdentity() -> Void {
        mBasis = simd_double3x3(1.0)
        mOrigin = simd_double3(repeating: 0.0)
    }

    public func inverse() -> Void {
        let inv = mBasis.transpose

        mBasis = inv
        mOrigin = inv * -mOrigin
    }
}

func vectorToTransform(v: simd_double3) -> Transform {
    let ray_vec = simd_normalize(-v)
    let ray_yaw_rot = simd_quatd(roll: 0.0, pitch: 0.0, yaw: atan2(ray_vec.y, ray_vec.x))
    let ray_new_x = simd_double3x3(ray_yaw_rot) * simd_double3(x: 1.0, y: 0.0, z: 0.0)
    let ray_pitch_rot = simd_quatd(roll: 0.0,
                                   pitch: atan2(-ray_vec.z, simd_dot(ray_vec, ray_new_x)),
                                   yaw: 0.0)

    return Transform(ray_yaw_rot * ray_pitch_rot, simd_double3())
}
