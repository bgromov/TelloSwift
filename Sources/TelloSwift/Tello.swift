//
//  Tello.swift
//  TelloSwift
//
//  Created by Boris Gromov on 28.03.2020.
//  Copyright © 2020 Volaly. All rights reserved.


import Foundation
import Network
import simd
import Combine

import Transform
import TelloSwiftObjC

/* */
/// UDP connection states.
public enum ConnectionState: String {
    case disconnected
    case connecting
    case connected
    case timedout
    case error
}

/// Flight states.
public enum FlightState: String {
    case unknown

    case landed
    case takingOff
    case hovering
    case flying
    case landing
}

/// FIXME: What do we want?
/// Roughly the following:
///
///     tello.command()
///          .connect { drone in
///             print("Connected")
///          }
///          .takeoff(altitude: 0.5) { drone
///          .goTo(pose: pose_1)
///          .goTo(pose: pose_2)
///          .goTo(pose: pose_3)
///          .land()
///          .disconnect()
///
//public enum TelloCommand {
//    case connect
//    case disconnect
//    case takeoff(altitude: Double)
//    case land
//    case emergency
//    case goTo(pose: QuadrotorPose)
//}

/// Position source for position controller.
public enum PositionSource {
    case mvo
    case vo
    case user(Sensor<AnyPositionMeasurement>)
}

/// Orientation source for position controller.
public enum OrientationSource {
    case imu
    case user(Sensor<AnyOrientationMeasurement>)
}

extension FlightData: Equatable {
    public static func == (lhs: FlightData, rhs: FlightData) -> Bool {
        precondition(false, "Not implemented")
        return false
    }
}

public typealias Status<T: Equatable> = Sensor<T>

public class Tello {
    // Connection parameters
    /// Hostname or IP.
    public let host: NWEndpoint.Host
    /// UDP port.
    public let port: NWEndpoint.Port

    // Doing this in real time is very slow
    private let timeZone = TimeInterval(TimeZone.current.secondsFromGMT())

    private var connection: NWConnection?
    private let netQueue: DispatchQueue

    private var connTimer: Timer?
    public private(set) var timeoutInterval: TimeInterval = 2.0

    private var keepAliveTimer: BackgroundTimer?
    public var keepAliveInterval: Double = 0.05 // in seconds, i.e. 20 Hz

    private var messageHandlers: [MessageId:((PacketPreambula, Data?) -> Void)] = [:]

    private var posCtrl: PositionController
    private var ctrl: QuadrotorControls

    public var fastMode: Bool = false

    /* Debug stuff */
    private let stopWatch: StopWatch = StopWatch(maxWindow: 100)
    // [id : [size : count]]
    private var recTypeStats: [UInt16:[Int:Int]] = [:]
    /* *********** */

    private var justTookOff: Bool = false

    internal var subs: Set<AnyCancellable> = []
    private var controllerSubs: Set<AnyCancellable> = []

    // MARK: Sensors
    /// Network connection state.
    public private(set) var connectionState = Status<ConnectionState>(repeatedValues: false)
    /// Flight state.
    public private(set) var flightState = Status<FlightState>(repeatedValues: false)

    /// Flight data.
    public private(set) var flightData = Sensor<FlightData>()
    /// Wi-Fi signal strength.
    public private(set) var wifiStrength = Sensor<UInt8>()
    /// Light conditions.
    public private(set) var lightConditions = Sensor<Bool>()
    /// Inertial Measurement Unit.
    public private(set) var imu = Sensor<Imu>()
    /// Multiview Odometry.
    public private(set) var mvo = Sensor<Mvo>()
    /// Visual Odometry.
    public private(set) var vo  = Sensor<Vo>()
    /// Proximity.
    public private(set) var proximity = Sensor<Double>()

    /// Controller data streams.
    public private(set) lazy var controller = (state: self.posCtrl.state,
                                               input: self.posCtrl.input,
                                               output: self.posCtrl.output,
                                               target: self.posCtrl.target,
                                               origin: self.posCtrl.origin)

    // MARK: Init
    /// Creates Tello interface class
    ///
    /// - Parameters:
    ///   - host: IP address or hostname of the drone. Defaults to `192.168.10.1`.
    ///   - port: Tello control port. Defaults to `8889`.
    public init(host: String = "192.168.10.1", port: UInt16 = 8889) {
        connectionState <- .disconnected
        flightState <- .unknown

        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!

        self.netQueue = DispatchQueue(label: "ch.volaly.tellokit.network", qos: .utility)

//        posCtrl = PositionController(x:   Pid(p: 0.9, i: 0.007, d: 0.08, deadband: 0.01)!,
//                                     y:   Pid(p: 0.9, i: 0.007, d: 0.08, deadband: 0.01)!,
//                                     z:   Pid(p: 2.0, i: 0.005, d: 0.01,  deadband: 0.05)!,
//                                     yaw: Pid(p: 3.0, i: 0.00,   d: 0.0,  deadband: deg2rad(1.0))!)

        posCtrl = PositionController(x:   Pid(p: 1.2, i: 0.3, d: 0.8, deadband: 0.05)!,
                                     y:   Pid(p: 1.2, i: 0.3, d: 0.8, deadband: 0.05)!,
                                     z:   Pid(p: 4.0, i: 0.5, d: 0.8, deadband: 0.05)!,
                                     yaw: Pid(p: 0.7, i: 0.0, d: 0.5,  deadband: deg2rad(1.0))!)

        ctrl = QuadrotorControls(roll: 0.0, pitch: 0.0, yaw: 0.0, thrust: 0.0)

        // Set default sensor sources for controller
        setControllerSource(position: .vo, orientation: .imu)

        setMessageHandler(messageId: .flightMsg, callback: flightDataHandler)
        setMessageHandler(messageId: .wifiMsg, callback: wifiPacketHandler)
        setMessageHandler(messageId: .logHeaderMsg, callback: logHeaderPacketHandler)
        setMessageHandler(messageId: .logDataMsg, callback: logDataPacketHandler)

        setMessageHandler(messageId: .lightMsg, callback: lightPacketHandler)

        setMessageHandler(messageId: .logConfigMsg) {pre, data in
            // FIXME: There might be some useful data here
            //print("LogConfig: \(pre.packetTypeInfo.packetSubtype)\n\n\(data!.hexEncodedString(options: .spaceBytes))")
        }

        setMessageHandler(messageId: .timeCmd) { pre, data in
            self.setTimeDate()
            print("info: Set TimeDate")
        }

        setMessageHandler(messageId: .calibrateCmd) { _, _ in
            print("ack: calibrateCmd")
        }

        setMessageHandler(messageId: .takeoffCmd) { _, _ in
            print("ack: takeoffCmd")
        }

        setMessageHandler(messageId: .landCmd) { _, _ in
            print("ack: landCmd")
        }

        flightState.sink {
            let newValue = $0
            let oldValue = self.flightState.value!
            self.justTookOff =
                (oldValue == .takingOff && newValue == .hovering) ||
                (oldValue == .landed    && newValue == .hovering)
                ? true : false
        }.store(in: &subs)
    }

    private func timerSet(timeout: TimeInterval) {
        DispatchQueue.main.async {
            self.connTimer?.invalidate()
            self.connTimer = nil

            self.connTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false, block: self.timerDidTimeout)
        }
    }

    private func timerDidTimeout(_ : Timer) {
        guard connectionState != .disconnected else {return}
        connectionState <- .timedout

        // Re-create the connection
        connection = nil
        connect()

        keepAliveTimer?.invalidate()
        keepAliveTimer = nil

        sendConnReq()
    }

    private func sendConnReq() {
        guard let conn = connection else {return}

        var conn_req = "conn_req:".data(using: .ascii)!
        conn_req.appendLe(shortInt: 6038) // 0x96 0x17

        // Prepare to recieve data
        conn.receiveMessage(completion: {(data, _, isComplete, err) in
            // Any meaningful data?
            if data != nil && isComplete && err == nil {
                if (String(data: data!, encoding: .ascii)?.starts(with: "conn_ack:"))! {
                    self.connectionState <- .connected

                    self.startKeepAliveTimer()

                    self.receiveData()
                }
            }
        })

        // Schedule connection timeout timer
        self.timerSet(timeout: timeoutInterval)
        // Send connection request
        sendData(data: conn_req)
    }

    private func startKeepAliveTimer() {
//        DispatchQueue.main.async {
//            self.keepAliveTimer?.invalidate()
//            self.keepAliveTimer = Timer.scheduledTimer(withTimeInterval: self.keepAliveInterval,
//                                                       repeats: true,
//                                                       block: self.keepAliveCallback(_:))
//        }

        self.keepAliveTimer?.invalidate()
        self.keepAliveTimer = BackgroundTimer(repeat: self.keepAliveInterval, event: self.keepAliveCallback)
    }

    // MARK: Keep Alive Timer
    private func keepAliveCallback(_ : BackgroundTimer) {
        self.sendSticksData(ctrlRx: self.ctrl.roll ?? 0.0,
                            ctrlRy: self.ctrl.pitch ?? 0.0,
                            ctrlLx: self.ctrl.yaw ?? 0.0,
                            ctrlLy: self.ctrl.thrust ?? 0.0,
                            fastMode: self.fastMode)
    }

    private func receiveData() {
        guard let conn = connection else {return}

        // Reschedule timer
        self.timerSet(timeout: self.timeoutInterval)

        conn.receiveMessage(completion: {(data, _, isComplete, err) in
            // Any meaningful data?
            if data != nil && isComplete && err == nil {
                if let packet = TelloPacket(rawData: data!) {
                    self.processPacket(packet: packet)
                } else {
                    let unknownCmdStr = "unknown command:"
                    if let str = String(data: data!, encoding:.ascii) {
                        if str.starts(with: unknownCmdStr) {
                            let wrongCmdData = data!.advanced(by: unknownCmdStr.count + 1) // plus space
                            print(unknownCmdStr, wrongCmdData.hex)
                        } else if str.starts(with: "conn_ack:") {
                            self.connectionState <- .connected
                        }
                    } else {
                        print("warn: Wrong packet header: \(data![0])")
                        if let str = String(data: data!, encoding:.ascii) {
                            print("warn: Wrong packet header: \(str)")
                        }
                    }
                }

                // Schedule next read
                self.receiveData()
            }
        })
    }

    private func sendData(data: Data) {
        guard let conn = connection else {return}

        //print("send:", data.hexEncodedString())
        conn.send(content: data, completion: .contentProcessed({(err) in
            if err != nil {
                print("error: Failed to send: \(err!)")
            }
        }))
    }

    private func processPacket(packet: TelloPacket) {
        let pre = packet.getPreambula()
        let payload = packet.getPayload()

        if let msgId = MessageId(rawValue: pre.messageID) {
            if let cb = messageHandlers[msgId] {
                cb(pre, payload)
            } else {
                print("warn: Unhandled message ID: \(msgId), payload size: \(payload?.count ?? 0) bytes")
            }
        } else {
            print("error: Unknown message ID: \(pre.messageID)")
        }
    }

    // MARK: Message Handlers

    private func setMessageHandler(messageId: MessageId, callback: ((PacketPreambula, Data?) -> Void)?) {
        if callback != nil {
            messageHandlers[messageId] = callback
        } else {
            messageHandlers.removeValue(forKey: messageId)
        }
    }

    // MARK: Flight Data
    private func flightDataHandler(pre: PacketPreambula, payload: Data?) {
        if let data = payload {
            let fd = TelloFlightDataParser.flightData(from: data)
            self.flightData <- fd

            // TODO: Handle battery state

            switch(fd.flyMode) {
            case 1:  // moving
                if fd.emSky == 1 {
                    flightState <- .flying
                } else {
                    // FIXME: Drone still could be landing while motors are off

                    //flightState = .unknown
                }
            case 6:  // still
                if fd.emSky == 1 {
                    flightState <- .hovering
                } else {
                    flightState <- .landed
                }
            case 11: // taking off
                if fd.emSky == 1 {
                    flightState <- .takingOff
                } else {
                    // FIXME: Motors are not running yet but the state is takingOff
                    // Just before it takes off, the motors are not spinning yet

                    //flightState = .unknown
                }
            case 12: // landing
                if fd.emSky == 1 {
                    flightState <- .landing
                } else {
                    // FIXME: Drone still could be landing while motors are off

                    //flightState = .unknown
                }
            default:
                //flightState = .unknown
                break
            }

            if flightState == .unknown {
                print("warn: Unknown flight state: emSky=\(fd.emSky), flyMode=\(fd.flyMode)")
            }

        } else {
            print("error: flight data payload is empty")
        }
    }

    // MARK: Wi-FI
    private func wifiPacketHandler(pre: PacketPreambula, payload: Data?) {
        if let data = payload {
            let wifiStrength = data[0]
            self.wifiStrength <- wifiStrength
        } else {
            print("error: wifi data payload is empty")
        }
    }

    // MARK: Light
    private func lightPacketHandler(pre: PacketPreambula, payload: Data?) {
        if let val = payload?[0] {
            lightConditions <- val == 1

            if val == 1 {
                print("warn: insufficient light")
            }
        } else {
            print("error: light data payload is empty")
        }
    }

    // MARK: Log Header
    private func logHeaderPacketHandler(pre: PacketPreambula, payload: Data?) {
        if let data = payload {
            var newPayload = Data([0])
            newPayload.append(data[0])
            newPayload.append(data[1])

            let packet = TelloPacket(command: .logHeaderMsg,
                                     packetTypeInfo: .init(byte: 0x50),
                                     payload: newPayload)
            sendData(data: packet.getRawData())
            //print("ack: log header payload: \(newPayload.hexEncodedString())")
            //print("ack: \(packet.getRawData().hexEncodedString())")
        } else {
            print("error: log header payload is empty")
        }
    }

    // MARK: Log Data
    private func logDataPacketHandler(pre: PacketPreambula, payload: Data?) {
        // Drop first byte (always 0x00)
        guard let data = payload?.advanced(by: 1) else {return}

        //print("Log data: \(data.hex)")

        // Rotate MVO & IMU coordinate systems to make Z-axis point up
        // MVO has its Z-axis pointing down, so let's roll
        let mvoFrame = Transform(simd_quatd(roll: .pi, pitch: 0.0, yaw: 0.0))

        // Parse the data
        FlighLogParser(data: data) { rec in
            switch(rec) {

            // MARK: Proximity
            case .proximity(let dist):
                // Publish sensor measurements
                self.proximity <- Double(dist)

            // MARK: IMU
            case .imu(var imu):
                // Acceleration in the inertial frame (world)
                imu.accel = mvoFrame * imu.accel

                // Transform IMU quat coordinate system
                let (tr, tp, ty) = (mvoFrame * imu.orientation).rpy
                // Set roll to zero
                imu.orientation = simd_quatd(roll: tr - .pi, pitch: tp, yaw: ty)
                imu.gyro = mvoFrame * imu.gyro

                // Publish sensor measurements
                self.imu <- imu

            // MARK: VO
            case .vo(var vo):
                let baseVel = mvoFrame * vo.velocity
                let basePos = mvoFrame * vo.position

                vo.velocity = baseVel
                vo.position = basePos //- (self.voOrigin ?? simd_double3())

                // Publish sensor measurements
                self.vo <- vo

            // MARK: MVO
            case .mvo(var mvo):
                // FIXME: Perhaps, need to rotate isValid vector as well, but how?
                let baseVel = mvoFrame * mvo.velocity
                let basePos = mvoFrame * mvo.position
                let baseVelCov = mvoFrame.basis * mvo.velocityCov * mvoFrame.basis.transpose
                let basePosCov = mvoFrame.basis * mvo.positionCov * mvoFrame.basis.transpose

                mvo.velocity = baseVel
                mvo.velocityCov = baseVelCov
                mvo.position = basePos
                mvo.positionCov = basePosCov

                // Publish sensor measurements
                self.mvo <- mvo

            case .unhandled(_, _, _):
                //print("Unhandled flight log record: \(recType), \(payload)")
                break

            case .unknown(let rec):
                // FIXME: Experimental stuff
                /**/
                //let recData = rec.payload.takeUnretainedValue() as Data
                let len = Int(rec.header.recordLength) //recData.count

                if var stats = recTypeStats[rec.header.recordType] {
                    if var count = stats[len] {
                        count += 1
                        stats[len] = count
                    } else {
                        stats[len] = 1
                    }
                    recTypeStats[rec.header.recordType] = stats
                } else {
                    recTypeStats[rec.header.recordType] = [len:1]
                }

                stopWatch.throttle(timeInterval: 1.0) {
                    print("Unknown flight log record types: \(recTypeStats.count)")
                    print("   id hex    dec    len count")
                    for rec in recTypeStats {
                        let id = String(format: "0x%04x: %5d", rec.key, rec.key)
                        print("  [\(id)]: \(rec.value)")
                    }
                }
                /**/
            }
        }
    }

    // MARK: Low-level commands
    private func sendCalibrate(type: UInt8) {
        let packet = TelloPacket(command: .calibrateCmd,
                                 packetTypeInfo: .init(byte: 0x68),
                                 payload: Data([type]))

        sendData(data: packet.getRawData())
    }

    private func sendAltitudeLimit(altitude: UInt16) {
        let packet = TelloPacket(command: .altLimitCmd,
                                 packetTypeInfo: .init(byte: 0x68),
                                 payload: Data(from: altitude))

        sendData(data: packet.getRawData())
    }

    private func sendTimeDate(date: Date = Date()) {
        let dateComp = Calendar.current.dateComponents(in: .current, from: date)

        // 15 bytes
        var payload = Data([0])
        payload.appendLe(shortInt: UInt16(dateComp.year!))
        payload.appendLe(shortInt: UInt16(dateComp.month!))
        payload.appendLe(shortInt: UInt16(dateComp.day!))
        payload.appendLe(shortInt: UInt16(dateComp.hour!))
        payload.appendLe(shortInt: UInt16(dateComp.minute!))
        payload.appendLe(shortInt: UInt16(dateComp.second!))
        // milliseconds
        payload.appendLe(shortInt: UInt16(dateComp.nanosecond! / 1000000))

        let packet = TelloPacket(command: .timeCmd,
                                 packetTypeInfo: .init(byte: 0x50),
                                 payload: payload)

        sendData(data: packet.getRawData())
    }

    /// Sends joystick controls to the drone.
    ///
    /// The method should not be used directly. It is periodically called by the internal
    /// keep-alive timer and thus calling it manually would probably have no effect.
    ///
    /// - Remark: To trigger manual takeoff procedure the input parameters must be set in the following way:
    ///  ```
    ///  sendSticksData(ctrlRx: -1.0, ctrlRy: -1.0, ctrlLx: 1.0, ctrlLy: -1.0)
    ///  ```
    ///  In this mode, Tello starts spinning slowly its rotors and can be taken off by increasing the thrust.
    ///
    /// - Parameters:
    ///   - ctrlRx: Right X control, corresponds to `roll`. Clamped to [`-1.0...1.0`] interval.
    ///   - ctrlRy: Right Y control, corresponds to `pitch`. Clamped to [`-1.0...1.0`] interval.
    ///   - ctrlLx: Left X control, corresponds to `yaw`. Clamped to [`-1.0...1.0`] interval.
    ///   - ctrlLy: Left Y control, corresponds to `thrust`. Clamped to [`-1.0...1.0`] interval.
    ///   - fastMode: switches the drone to fast mode. Can be used, e.g., when flying outdoors. Off by default.
    private func sendSticksData(ctrlRx: Double, ctrlRy: Double, ctrlLx: Double, ctrlLy: Double, fastMode: Bool = false) {
        let date = Date().addingTimeInterval(timeZone) //calendar.dateComponents(in: .current, from: Date())
        let now = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        var sticks = SticksData()

        sticks.axis1 = UInt16(1024.0 + 660.0 * ctrlRx.clamped(to: -1.0...1.0)) // x
        sticks.axis2 = UInt16(1024.0 + 660.0 * ctrlRy.clamped(to: -1.0...1.0)) // y
        sticks.axis3 = UInt16(1024.0 + 660.0 * ctrlLy.clamped(to: -1.0...1.0)) // y
        sticks.axis4 = UInt16(1024.0 + 660.0 * ctrlLx.clamped(to: -1.0...1.0)) // x
        sticks.axis5 = fastMode ? 1 : 0

        var payload = TelloSticksDataCreator.data(from: sticks)

        payload.append(UInt8(now.hour!))
        payload.append(UInt8(now.minute!))
        payload.append(UInt8(now.second!))

        let ms = UInt16(now.nanosecond! / 1000000)
        payload.appendLe(shortInt: UInt16(ms & 0xff))
        payload.appendLe(shortInt: UInt16((ms >> 8) & 0xff))

        let packet = TelloPacket(command: .stickCmd,
                                 packetTypeInfo: .init(byte: 0x60),
                                 payload: payload)

        sendData(data: packet.getRawData())
    }

    private func sendTakeoff() {
        let packet = TelloPacket(command: .takeoffCmd,
                                 packetTypeInfo: .init(byte: 0x68),
                                 payload: nil)

        sendData(data: packet.getRawData())
    }

    private func sendLand() {
        let packet = TelloPacket(command: .landCmd,
                                 packetTypeInfo: .init(byte: 0x68),
                                 payload: Data([UInt8(0)])) // Can be used to stop landing

        sendData(data: packet.getRawData())
    }

    private func sendCancelLanding() {
        let packet = TelloPacket(command: .landCmd,
                                 packetTypeInfo: .init(byte: 0x68),
                                 payload: Data([UInt8(1)]))

        sendData(data: packet.getRawData())
    }

    // MARK: Public interface

    /// Attempts to connect to Tello using connection parameters specified at initialization.
    ///
    /// The method runs asynchronously and will keep trying to connect every
    /// `connectionTimeout` interval until `disconnect()` is called.
    ///
    /// The connection state can be monitored through the delegate
    /// method `didUpdateConnectionState()`.
    public func connect() {
        if connection == nil {
            connection = NWConnection(host: self.host, port: self.port, using: .udp)
        }

        guard let conn = connection else {return}

        conn.stateUpdateHandler = {(connState) in
            switch connState {
            case .setup:
                print("debug: UDP connection is setting up")
            case .preparing:
                print("debug: UDP connection is preparing")
            case .ready:
                print("debug: UDP connection is ready")

                self.sendConnReq()
            case .cancelled:
                print("debug: UDP connection is cancelled")
                //self.connectionState = .disconnected
            case .failed(_):
                print("warn: UDP connection failed")
                self.connectionState <- .error
            default:
                print("warn: UDP connection is waiting")
            }
        }

        connectionState <- .connecting
        conn.start(queue: netQueue)
    }

    /// Closes network connection to Tello.
    ///
    /// Note that this method forcefully lands the drone before disconnecting.
    public func disconnect() {
        guard let conn = connection else {return}

        // FIXME: Wait for acknowledgement
        land()

        conn.cancel()

        // remove timers
        connTimer?.invalidate()
        connTimer = nil
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil

        connection = nil
        connectionState <- .disconnected
    }

    /// Sends emergency command to the drone that immediately kills the motors. Should be used with extra caution.
    /// - Bug: Does not always work: the drone replies with "unknown command".
    public func emergency() {
        sendData(data: Data(String("emergency").data(using: .ascii)!))
        print("warn: sent emergency command")
    }

    /// Starts the calibration procedure.
    ///
    /// - To perform IMU calibration the drone should be on the ground.
    /// - To perform Center-of-Gravity (CoG) calibration the drone should be in the air and hovering callibration.
    ///
    /// - Bug: The IMU calibration is not functional yet, as it requires to notify the user
    /// about the next steps to take, e.g. place the drone on its left side.
    ///
    /// - Parameters:
    ///   - type: Calibration type.
    ///
    public func calibrate(type: CalibrationType) {
        guard flightState != .unknown else {
            print("warn: Can't calibrate yet, repeat in a moment")
            return
        }

        switch type {
        case .imu:
            if flightState != .landed {
                print("error: Can't calibrate. Drone should rest on a flat horizontal surface")
            }
        case .centerOfGravity:
            if flightState != .hovering{
                print("error: Can't calibrate. Drone should hover")
            }
        }

        sendCalibrate(type: type.rawValue)
    }

    /// Sets the maximum altitude the drone could reach.
    ///
    /// - Parameters:
    ///   - altitude: altitude in meters
    public func setAltitudeLimit(altitude: UInt16) {
        sendAltitudeLimit(altitude: altitude)
    }

    /// Sets the internal clock of the drone.
    ///
    /// Typically, there is no need to call this function manually as it is
    /// called automatically when the drone requests it at the startup.
    ///
    /// - Parameters:
    ///   - date: time and date. Defaults to current local time and date.
    public func setTimeDate(date: Date = Date()) {
        sendTimeDate(date: date)
    }

    /// Sets joystick controls.
    ///
    /// The method immediatelly cancels a position controller target.
    ///
    /// - Remark: To trigger manual takeoff procedure the input parameters must be set in the following way:
    ///  ```
    ///  manualSticks(ctrlRx: -1.0, ctrlRy: -1.0, ctrlLx: 1.0, ctrlLy: -1.0)
    ///  ```
    ///  In this mode, Tello starts spinning slowly its rotors and can be taken off by increasing the thrust.
    ///
    /// - Parameters:
    ///   - ctrlRx: Right X control, corresponds to `roll`. Clamped to [`-1.0...1.0`] interval.
    ///   - ctrlRy: Right Y control, corresponds to `pitch`. Clamped to [`-1.0...1.0`] interval.
    ///   - ctrlLx: Left X control, corresponds to `yaw`. Clamped to [`-1.0...1.0`] interval.
    ///   - ctrlLy: Left Y control, corresponds to `thrust`. Clamped to [`-1.0...1.0`] interval.
    ///   - fastMode: switches the drone to fast mode. Can be used, e.g., when flying outdoors. Off by default.
    public func manualSticks(roll ctrlRx: Double, pitch ctrlRy: Double, yaw ctrlLx: Double, thrust ctrlLy: Double, fastMode: Bool = false) {
        self.cancelGoTo()

        self.ctrl = QuadrotorControls(roll:   ctrlRx.clamped(to: -1.0...1.0),
                                      pitch:  ctrlRy.clamped(to: -1.0...1.0),
                                      yaw:    ctrlLx.clamped(to: -1.0...1.0),
                                      thrust: ctrlLy.clamped(to: -1.0...1.0))
        self.fastMode = fastMode
    }

    /// Automatically takes off the drone to a factory-predefined altitude (about 1.0-1.2m)
    public func takeoff() -> Future<Void, Never> {
        //setAltitudeLimit(altitude: 1) // 30m

        let future = Future<Void, Never>() { promise in
            self.flightState
                .receive(on: DispatchQueue.global(qos: .userInteractive))
                .sink { (newState: FlightState) in
                    let oldState = self.flightState.value!
                    if (oldState == .takingOff && newState == .hovering) || (oldState == .landed && newState == .hovering) {
                        promise(.success(()))
                    }
                }.store(in: &self.subs)
        }

        cancelGoTo()
        sendTakeoff()

        return future
    }

    /// Makes Tello to take off to a given altitude
    ///
    /// - Parameters:
    ///   - altitude: altitude in meters. On practice, it is lower-bound to 10-15cm.

    // FIXME: Should the altitude be strictly positive value? Since it's just a position along Z-axis it can be anything.
    public func manualTakeoff(altitude: Double) {
        self.setOriginToVo()

        self.ctrl = QuadrotorControls(roll: -1.0, pitch: -1.0, yaw: 1.0, thrust: -1.0)
        DispatchQueue.global().asyncAfter(wallDeadline: .now() + 0.5) {
            self.goTo(x: nil, y: nil, z: altitude)
        }
    }

    /// Automatically lands the drone.
    ///
    /// The method immediatelly cancels a position controller target.
    public func land() {
        cancelGoTo()
        sendLand()
    }

    /// Cancels the automatic landing.
    public func cancelLanding() {
        sendCancelLanding()
    }

    /// Moves the drone to specified `x`, `y`, `z` coordinates in its
    /// odometry frame and orientation `yaw` in its body frame.
    ///
    /// The method allows to specify individual components of the target pose.
    ///
    /// - Remark:
    ///   The parameters that are set to `nil` will be ignored by the position controller,
    ///   e.g., if `z` is set to `nil`, the drone will keep its current altitude.
    ///
    ///   Note, however, that this also means the controller will not attempt to compensate
    ///   for external disturbances along these `nil`-axes. (Though, Tello might do it by itself).
    ///
    /// - Parameters:
    ///   - x: target position along X-axis.
    ///   - y: target position along Y-axis.
    ///   - z: target position along Z-axis.
    ///   - yaw: rotation (heading) around Z-axis of body frame.
    public func goTo(x: Double?, y: Double?, z: Double?, yaw: Double? = nil) {
        posCtrl.setTarget(target: .init(x: x, y: y, z: z, yaw: yaw))
    }

    /// Rotates the drone to a specified heading.
    ///
    /// - Parameters:
    ///   - yaw: rotation (heading) around Z-axis of body frame.
    public func goToYaw(yaw: Double) {
        posCtrl.setTarget(target: .init(x: nil, y: nil, z: nil, yaw: yaw))
    }

    /// Cancels any go-to commands by resetting the position controller.
    public func cancelGoTo() {
        posCtrl.reset(.targetCanceled)
    }

    /// Same as `cancelGoTo()`.
    public func hover() {
        cancelGoTo()
    }

    // MARK: Position Controller
    /// Sets position controller input sources.
    public func setControllerSource(position: PositionSource, orientation: OrientationSource) {
        var posSensor = Sensor<AnyPositionMeasurement>()
        var oriSensor = Sensor<AnyOrientationMeasurement>()

        // Clean any previously subscribed sources
        controllerSubs = []

        switch position {
        case .mvo:
            mvo.sink {
                posSensor.value = AnyPositionMeasurement($0)
            }.store(in: &controllerSubs)
        case .vo:
            vo.sink {
                posSensor.value = AnyPositionMeasurement($0)
            }.store(in: &controllerSubs)
        case .user(let userSensor):
            posSensor = userSensor
        }

        switch orientation {
        case .imu:
            imu.sink {
                oriSensor.value = AnyOrientationMeasurement($0)
            }.store(in: &controllerSubs)
        case .user(let userSensor):
            oriSensor = userSensor
        }

        posCtrl.source(position: posSensor, orientation: oriSensor)
            .assign(to: \.ctrl, on: self)
            .store(in: &controllerSubs)
    }

    /// Sets position controller gains.
    ///
    /// - Parameters:
    ///   - x: PID for X-axis
    ///   - y: PID for Y-axis
    ///   - z: PID for Z-axis
    ///   - yaw: PID for Yaw
    public func setControllerGains(x: Pid?, y: Pid?, z: Pid?, yaw: Pid?) {
        if let x = x {
            posCtrl.pid.x.gains = x.gains
        }
        if let y = y {
            posCtrl.pid.y.gains = y.gains
        }
        if let z = z {
            posCtrl.pid.z.gains = z.gains
        }
        if let yaw = yaw {
            posCtrl.pid.yaw.gains = yaw.gains
        }
    }

    /// Returns position controller gains.
    ///
    /// - Returns: Taged tuple with corresponding arrays of PID gains for each axis.
    public func getControllerGains() -> (x: [Double], y: [Double], z: [Double], yaw: [Double]) {
        return (x: posCtrl.pid.x.gains,
                y: posCtrl.pid.y.gains,
                z: posCtrl.pid.z.gains,
                yaw: posCtrl.pid.yaw.gains)
    }

    /// Sets the origin of position controller to given coordinates.
    public func setOrigin(x: Double, y: Double, z: Double, yaw: Double) {
        self.posCtrl.setOrigin(origin: .init(x: x, y: y, z: z, yaw: yaw))
    }

    /// Sets the origin of position controller to current pose in VO frame.
    ///
    /// - Warning: The method can only be used with position input source
    /// set to `.vo`. In all other cases the behavior is *undefined*.
    ///
    /// Individual terms of the origin pose are set from the following sources:
    ///  - `x`: from visual odometry (VO) sensor.
    ///  - `y`: from visual odometry (VO) sensor.
    ///  - `z`: from proximity sensor, i.e. height above the surface.
    ///  - `yaw`: from inertial measurement unit (IMU) sensor.
    public func setOriginToVo() {
        // FIXME: Enforce the input source to .vo
        if let vo = self.vo.value, let imu = self.imu.value, let height = self.proximity.value {
            setOrigin(x: vo.position.x, y: vo.position.y, z: vo.position.z - Double(height), yaw: imu.orientation.rpy.yaw)
        }
    }

    /// Sets the origin of position controller to current pose in controller's input frame.
    public func setOrigin() {
        posCtrl.setOriginToCurrentPose()
    }
}
/* */
