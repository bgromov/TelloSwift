//
//  FlightLogParser.swift
//  TelloSwift
//
//  Created by Boris Gromov on 13.05.2020.
//  Copyright © 2020 Volaly. All rights reserved.


import Foundation
import simd

/// Holds MVO measurements reported by the drone.
public struct Mvo: PositionMeasurement {
    public var velocity: simd_double3
    public var velocityCov: simd_double3x3
    public var position: simd_double3
    public var positionCov: simd_double3x3

    public var height: Double
    public var heightVariance: Double

    public var isValid: IsValidVelPos
}

/// Holds IMU measurements and temperature reported by the drone.
public struct Imu: OrientationMeasurement {
    /// Acceleration (gravity-compensated) in inertial frame.
    public var accel: simd_double3
    /// Angular velocity in body frame.
    public var gyro:  simd_double3
    /// Orientation of the drone in inertial frame.
    public var orientation: simd_quatd

    /// Temperature of the drone's main board.
    ///
    /// When not flying the drone overheats rather quickly and powers down
    /// when temperature stays above 64 deg Celsius for a couple of minutes.
    public var temperature: Float
}

/// Holds VO measurements reported by the drone.
public struct Vo: PositionMeasurement {
    public var velocity: simd_double3
    public var position: simd_double3

    public var isValid: IsValidVelPos
}

/// Flight log records.
enum FlightLog {
    /// Multimotion visual odometry (?) (MVO).
    case mvo(Mvo)
    /// Inertial measurement unit (IMU).
    case imu(Imu)
    /// Visual odometry (VO).
    case vo(Vo)
    /// Proximity sensor.
    case proximity(Float)
    /// Log records that are known but not handled by the library.
    ///
    /// Parsed into (record type, record length, payload).
    /// - Remark: *Record length* maybe different from the actual payload length.
    case unhandled(LogRecordType, UInt16, Data)
    /// Log records that are not known to the library.
    case unknown(LogRecord)
}

/// Tello flight log parser.
class FlighLogParser {
    /// Parses the input `data` and calls `block` closure every record found.
    /// - Parameters:
    ///   - data: input data
    ///   - block: user-defined closure. Called everytime a new record is extracted.
    @discardableResult init?(data: Data, block: (FlightLog) -> Void ) {
        var bufPos = 0
        while bufPos < data.count - 2 {
            var rec = LogRecordCreator.from(data.advanced(by: bufPos))
            if rec.header.header == logRecordSeparator {} else {
                // FIXME: Something wrong here. Let's ignore the packet completely for now
                return nil

                // FIXME: Weird hack. Sometimes the very first 28 bytes are without a proper header
                let range = data.count < 28 ? data.indices : 0..<28
                print("warn: Corrupted log data at pos=\(bufPos), data=\(data[range].hex)")
                print("warn:   attempt to recover")
                // Move forward
                rec = LogRecordCreator.from(data.advanced(by: bufPos + 28))
                // and try again
                guard rec.header.header == logRecordSeparator else {
                    // Fail and discard the entire packet
                    print("error: Corrupted log data at pos=\(bufPos), data=\(data.hex)")
                    return nil
                }

                // if the hack did work, increment the pos and continue as if it never happened
                bufPos += 28
            }

            let recType = LogRecordType(rawValue: rec.header.recordType)

            switch recType {
            case .mvo:
                // MARK: MVO
                // MVO reports at 5 Hz
                let mvoRec = MvoRecordCreator.from(rec.payload.takeUnretainedValue() as Data)

                let vel = simd_double3([mvoRec.velX, mvoRec.velY, mvoRec.velZ]) / 1000.0
                let pos = simd_double3([mvoRec.posX, mvoRec.posY, mvoRec.posZ])

                let isValid = IsValidVelPos(
                                vel: IsValid(x: mvoRec.isValid.velX, y: mvoRec.isValid.velY, z: mvoRec.isValid.velZ),
                                pos: IsValid(x: mvoRec.isValid.posX, y: mvoRec.isValid.posY, z: mvoRec.isValid.posZ))

                let posCov = simd_double3x3(simd_float3x3(rows:
                    [.init(mvoRec.posCov1, mvoRec.posCov2, mvoRec.posCov3),
                     .init(mvoRec.posCov2, mvoRec.posCov4, mvoRec.posCov5),
                     .init(mvoRec.posCov3, mvoRec.posCov5, mvoRec.posCov6)]))

                let velCov = simd_double3x3(simd_float3x3(rows:
                    [.init(mvoRec.velCov1, mvoRec.velCov2, mvoRec.velCov3),
                     .init(mvoRec.velCov2, mvoRec.velCov4, mvoRec.velCov5),
                     .init(mvoRec.velCov3, mvoRec.velCov5, mvoRec.velCov6)]))

                //print("Height: \(mvoRec.height) var: \(mvoRec.heightVariance)")
                //print("Observation: \(mvoRec.observationCount)")

                let mvo = Mvo(velocity: vel,
                          velocityCov: velCov,
                          position: pos,
                          positionCov: posCov,
                          height: Double(mvoRec.height),
                          heightVariance: Double(mvoRec.heightVariance),
                          isValid: isValid)

                block(.mvo(mvo))

            case .imu:
                // MARK: IMU
                // IMU reports at 10 Hz
                let imuRec = ImuRecordCreator.from(rec.payload.takeUnretainedValue() as Data)

                let ag   = simd_double3([imuRec.agX, imuRec.agY, imuRec.agZ])
                let gyro = simd_double3([imuRec.gyroX, imuRec.gyroY, imuRec.gyroZ])
                let quat = simd_quatd(real: Double(imuRec.quatW),
                                      imag: simd_double3([imuRec.quatX, imuRec.quatY, imuRec.quatZ]))

                let imu = Imu(accel: ag, gyro:  gyro, orientation: quat,
                              temperature: Float(imuRec.temperatute) / 100.0)

                block(.imu(imu))

            case .uSonic:
                // MARK: Proximity
                let recData = rec.payload.takeUnretainedValue() as Data
                let dist: UInt16 = UInt16(recData[0]) + UInt16(recData[1]) << 8

                block(.proximity(Float(dist) / 1000.0))

            case .imuEx:
                // MARK: VO (ImuEx)
                let voRec = ImuExRecordCreator.from(rec.payload.takeUnretainedValue() as Data)

                let vel = simd_double3([voRec.velX, voRec.velY, voRec.velZ])
                let pos = simd_double3([voRec.posX, voRec.posY, voRec.posZ])
                let isValid = IsValidVelPos(
                                vel: IsValid(x: voRec.isValid.velX, y: voRec.isValid.velY, z: voRec.isValid.velZ),
                                pos: IsValid(x: voRec.isValid.posX, y: voRec.isValid.posY, z: voRec.isValid.posZ))

                let vo = Vo(velocity: vel, position: pos, isValid: isValid)

                block(.vo(vo))

            case .goTxtOrOsd, .controller, .aircraftCond, .serialApiInputs, .battInfo, .attiMini, .nsDataDebug, .nsDataComponent, .recAirComp:
                fallthrough
            case .ctrlVertDbg, .ctrlVertVelDbg, .ctrlVertAccDbg, .ctrlHorizDbg, ._unknown_x0517, .ctrlHorizAttDbg, .ctrlHorizAngVelDbg, .ctrlHorizCcpmDbg, .ctrlHorizMotorDbg:
                /// FIXME: Unhandled Log Records
                block(.unhandled(recType!, rec.header.recordLength, rec.payload.takeUnretainedValue() as Data))

            default:
                block(.unknown(rec))
            }

            bufPos += Int(rec.header.recordLength)
        }
    }
}
