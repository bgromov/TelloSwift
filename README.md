#  TelloSwift

A Swift package for controlling DJI/Ryze Tello drone using its proprietary binary protocol.

The package is heavily inspired by implementations in other languages, namely [TelloPy](https://github.com/hanyazou/TelloPy) and [Tello Go](https://github.com/SMerrony/tello) libraries and leverages information gathered from the Tello Pilots forum and multiple other sources and repositories.

If you are looking to start hacking with Tello, these pages should give a good start: [Low-level protocol](https://tellopilots.com/wiki/protocol/) (quite incomplete but still useful), [Tello. What's possible?](https://tellopilots.com/threads/tello-whats-possible.88/), and [Has anyone decoded the log headers/messages from the Tello?](https://tellopilots.com/threads/has-anyone-decoded-the-log-headers-messages-from-the-tello.511/).

The package provides two interfaces: `Tello` and `TelloCommander`. The latter provides a simplified interface to the drone that allows to chain a few simple network and motion commands.

## Example

```swift

import TelloSwift

// Create Tello object with default connection parameters
let tello = Tello()
// Create commander
let commander = TelloCommander(tello: tello)

commander
    // Subscribe to IMU events
    .imu { imu in
        print(String(format: "Yaw: %3.2f", imu.rotation.rpy.yaw)
    }
    // Connect
    .connect()
    // Take off to a given altitude
    .takeoff(altitude: 0.5)
    // Go to a new pose but keep the altitude and orientation unchanged
    .goTo(x:  1.0, y:  0.0, z: nil, yaw: nil)
    // Yaw can be omitted
    .goTo(x:  0.0, y: -1.0, z: nil)
    .goTo(x: -1.0, y:  0.0, z: nil)
    .goTo(x:  0.0, y:  0.0, z: nil)
    // Land
    .land()
    // Disconnect
    .disconnect()
    // Store the command chain and execute it
    .commit()
```
## Functionality

*N.B. Video streaming is not supported yet but it is on my To Do list.*

The main goal of this project was to implement position control and therefore all the functionality is tailored to this need.

### `TelloSwift.Tello`
The `class Tello` public API provides the following main function (the list is not complete, please refer to the source code):

- `init(host: String = "192.168.10.1", port: UInt16 = 8889)` — constructor.
- `func connect()` — connects to Tello using the parameters specified in constructor. If connection timeouts for some reason, the library will attempt to reconnect.
- `func disconnect()` — disconnects from Tello.
- `func takeoff()` — automatically takes off the drone to a factory-defined altitude (approx. 1.0–1.2 m). 
- `func manualTakeoff(altitude: Double)` — takes off the drone to the given altitude.
- `func land()` — lands the drone.
- `func setControllerSource(position: PositionSource, orientation: OrientationSource)` — specifies position controller measurement sources, and eventually its input coordinate frame. By default the position source is `.vo` (visual odometry), see below for more details.
- `func goTo(x: Double?, y: Double?, z: Double?, yaw: Double? = nil)` — uses position controller to reach the given 3D pose in the position controller's input frame. See `setControllerSource` above.
- `func hover()` — cancels the current position target. Same as `cancelGoTo()`.
- `func emergency()` — sends emergency command that immediately kills the motors (*known bug*: the command fails sometimes).

The TelloKit reports the states and sensors data using Apple's [Combine](https://developer.apple.com/documentation/combine) publishers. All the sensor measurements are reported in SI units, i.e. [m], [m/s], etc. The following public publishers are available:

- `var connectionState: Status<ConnectionState>` (repeated values are ignored) — connection state.
- `var flightState: Status<FlightState>` (repeated values are ignored) — flight state.
- `var flightData: Sensor<FlightData>` — provides raw flight data.
- `var wifiStrength: Sensor<UInt8>` — Wi-Fi signal strength.
- `var lightConditions: Sensor<Bool>` — reports only `true` in case of insufficient light. (TODO: the name needs refactoring, perhaps).
- `var imu: Sensor<Imu>` — IMU measurements: accelerometer, gyro, orientation, and temperature.
- `var mvo: Sensor<Mvo>` — MVO measurements: linear position and velocity in MVO frame, height (from proximity sensor), and measurement covariances (these ones are quite tricky, TelloKit's interpretation might be wrong).
- `var vo: Sensor<Vo>` — VO measurements: linear position and velocity in VO frame.
- `var proximity: Sensor<Double>` — proximity sensor measurements.
- `var controller: (state: Sensor<PositionController.State>, input: Sensor<QuadrotorPose>, output: Sensor<QuadrotorControls>, target: Sensor<QuadrotorPose>, origin: Sensor<QuadrotorPose>)` — inputs and outputs of the position controller. The `target` and the `origin` are reported only when changed and `input` and `output` are reported at input's rate.

### `TelloSwift.TelloCommander`
The `TelloCommander` class public API provides the following main function that correspond to `Tello` API almost one-to-one but that support chaining (please see the descriptions above):

- `connect()`
- `disconnect()`
- `takeoff()`
- `land()`
- `goTo()`

It also allows one to access various sensors and states in a simplified way through a callback mechanism:

- `connectionState()`
- `flightState()`
- `flightData()`
- `wifiStrength()`
- `lightConditions()`
- `imu()`
- `mvo()`
- `vo()`

The chaining is implemented using Apple's [Combine](https://developer.apple.com/documentation/combine) framework through the Future/Promise mechanism. Correspondingly the `Chain` returned by the methods listed above is a `Combine.Publisher`. 

## Conventions

### Coordinate frames

The library uses the right-hand coordinate system convention with drone's body frame axes defined in the following way:  

- X-axis: points forward (towards the drone's main camera).
- Y-axis: points to the drone's left.
- Z-axis: points up.

Respectively, rotations are defined in body frame:

- Roll: rotation around X-axis.
- Pitch: rotation around Y-axis.
- Yaw: rotation around Z-axis.

## Sensors and other measurements

#### Proximity sensor

Infra-red proximity sensor reports distance from a surface under the drone (along the Z-axis). The minimal detectable distance is 0.10 m (10 cm).

#### IMU (Inertial Measurement Unit)

Reports at **10 Hz**:

- *Rotation* is reported in body frame as a quaternion.
- *Angular velocity* is reported in body frame.
- *Acceleration* is gravity-compensated and reported in the inertial frame.

IMU also reports the temperature of the motherboard(?). When the drone is not flying, it quickly raises to 65ºC and the drone switches off after a couple of minutes.

#### Odometry

There are at least two sources of odometry that Tello provides:

- *MVO (Multi-view (visual) odometry?)*, reported at **5 Hz**. It is not entirely clear how it is calculated but it does not seem to be very reliable, i.e. with insufficient lighting it may reinitialize to 50-60 m away from current position.
- *VO (Visual Odometry / Visual Inertial Odometry)*, reported at **10 Hz**. A more robust odometry source. Reported within `ImuEx` packet and perhaps fuses several sensors together, namely: visual odometry for XY axes and barometer for Z-axis. When readings are unreliable for 3 seconds (after 30 samples), resets X and Y to zeros. The reset can be monitored through `PositionController`.

#### Wi-Fi signal strength

As reported by many others, maxes out at 90 (per cent?).

#### Flight Data

There are many more other parameters reported through the `FlightData` structure, including battery level and flight time left.

## Control

The primary control mode is position control. The mode is implemented with simple independent PID controllers for each of four control axes: X, Y, Z, and Yaw. See `goTo()` methods.

It is also possible to control the drone with a joystick using manual sticks control. See `manualSticks()` method.

## Development status

The library (as well as the documentation) is still a work-in-progress. Many of the functions were minimally tested, and therefore, may exhibit undefined behavior in a real setting. Please exercise extra caution when using the library.

## Author

Boris Gromov, [Volaly](volaly.ch) / [IDSIA](idsia.ch).

## License

TelloSwift is available under the BSD-3-Clause license. See the LICENSE file for more information.
