//
//  Protocol.h
//  TelloSwift
//
//  Created by Boris Gromov on 27.03.2020.
//  Copyright © 2020 Volaly. All rights reserved.


#import <Foundation/Foundation.h>

typedef union __attribute__((packed)) {
    uint8_t byte;
    struct {
        uint8_t fromDrone: 1;
        uint8_t toDrone: 1;
        uint8_t packetType: 3;
        uint8_t packetSubtype: 3;
    };
} PacketTypeInfo;

typedef struct __attribute__((packed)) {
    uint8_t header;         // Always 0xCC
    union {
        uint16_t packetSize;
        struct {
            uint8_t __packetSizeL;
            uint8_t __packetSizeH;
        };
    } packetSize;
    uint8_t crc8;
    PacketTypeInfo packetTypeInfo;
    uint16_t messageID;
    uint16_t sequenceNo;
//    __unsafe_unretained NSData* payloadWithCRC16; // Last two bytes - CRC16
} PacketPreambula;

@interface TelloPacketCreator : NSObject

+ (nonnull NSData *)dataFrom:(PacketPreambula) preambula payload:(nullable NSData *) payload;

+ (PacketPreambula)preambulaFrom:(nonnull NSData *) packet;
+ (nullable NSData *)payloadFrom:(nonnull NSData *) packet;

@end

typedef struct __attribute__((packed)) {
    uint16_t height;                        // byte 0, 1
    uint16_t northSpeed;                    // byte 2, 3
    uint16_t eastSpeed;                     // byte 4, 5
    uint16_t groundSpeed;                   // byte 6, 7
    uint16_t flyTime;                       // byte 8, 9

    union {
        uint8_t __byte10;                   // byte 10
        struct {
            uint8_t imuState: 1;            // bit 0
            uint8_t pressureState: 1;       // bit 1
            uint8_t downVisualState: 1;     // bit 2
            uint8_t powerState: 1;          // bit 3
            uint8_t batteryState: 1;        // bit 4
            uint8_t gravityState: 1;        // bit 5
            uint8_t __unused_bit6: 1;       // bit 6
            uint8_t windState: 1;           // bit 7
        };
    };

    uint8_t imuCalibrationState;            // byte 11
    uint8_t batteryPercentage;              // byte 12
    uint16_t droneBatteryLeft;              // byte 13, 14
    uint16_t droneFlyTimeLeft;              // byte 15, 16

    union {
        uint8_t __byte17;                   // byte 17
        struct {
            uint8_t emSky: 1;               // bit 0
            uint8_t emGround: 1;            // bit 1
            uint8_t emOpen: 1;              // bit 2
            uint8_t droneHover: 1;          // bit 3
            uint8_t outageRecording: 1;     // bit 4
            uint8_t batteryLow: 1;          // bit 5
            uint8_t batteryLower: 1;        // bit 6
            uint8_t factoryMode: 1;         // bit 7
        };
    };

    uint8_t flyMode;                        // byte 18
    uint8_t throwFlyTimer;                  // byte 19
    uint8_t cameraState;                    // byte 20
    uint8_t electricalMachineryState;       // byte 21

    union {
        uint8_t __byte22;                   // byte 22
        struct {
            uint8_t frontIn: 1;             // bit 0
            uint8_t frontOut: 1;            // bit 1
            uint8_t frontLSC: 1;            // bit 2
            uint8_t __unused_bit3_7: 5;     // bit 3-7
        };
    };
    union {
        uint8_t __byte23;                   // byte 23
        struct {
            // NB: TelloPy calls this field 'temperature_height'
            uint8_t errorState: 1;          // bit 0
            uint8_t __unused_bit1_7: 6;     // bit 1-7
        };
    };
} FlightData;

@interface TelloFlightDataParser : NSObject

+ (FlightData)flightDataFrom:(nonnull NSData *) data;

@end

typedef struct __attribute__((packed)) {
    uint16_t axis1: 11;
    uint16_t axis2: 11;
    uint16_t axis3: 11;
    uint16_t axis4: 11;
    uint16_t axis5: 1;
} SticksData;

@interface TelloSticksDataCreator : NSObject

+ (nonnull NSData *)dataFrom:(SticksData) sticks;

@end

typedef struct __attribute__((packed)) {
    // Always 0x55
    uint8_t  header;               // byte  0
    uint16_t recordLength;         // bytes 1-2
    uint8_t  crc8;                 // byte  3
    uint16_t recordType;           // bytes 4-5
    uint8_t  xorValue;             // byte  6
    uint8_t  __unused_bytes7_9[3]; // bytes 7-9
} LogRecordHeader;

typedef struct {
    LogRecordHeader header;        // bytes 0-9
    __unsafe_unretained NSData * _Nonnull payload; // bytes 10 to ln-12
//    uint16_t crc16;                // bytes ln-2 to ln
} LogRecord;

@interface LogRecordCreator : NSObject

+ (LogRecord) from: (nonnull NSData *) data;

@end

// From https://github.com/BudWalkerJava/DatCon/blob/master/DatCon/src/DatConRecs/FromViewer/new_mvo_feedback_29.java#L49
typedef struct __attribute__((packed)) {
    int16_t observCount;    // bytes 0-1
    int16_t velX;           // bytes 2-3
    int16_t velY;           // bytes 4-5
    int16_t velZ;           // bytes 6-7

    float   posX;           // bytes 8-11
    float   posY;           // bytes 12-15
    float   posZ;           // bytes 16-19

//    float   hoverPointCov1;    // bytes 20-23
//    float   hoverPointCov2;    // bytes 24-27
//    float   hoverPointCov3;    // bytes 28-31
//    float   hoverPointCov4;    // bytes 32-35
//    float   hoverPointCov5;    // bytes 36-39
//    float   hoverPointCov6;    // bytes 40-43

    // NOTE: Originaly was called hoverPointUncertainty,
    // but it seems to be an element of position covariance matrix
    float   posCov1;        // bytes 20-23
    float   posCov2;        // bytes 24-27
    float   posCov3;        // bytes 28-31
    float   posCov4;        // bytes 32-35
    float   posCov5;        // bytes 36-39
    float   posCov6;        // bytes 40-43

    float   velCov1;        // bytes 44-47
    float   velCov2;        // bytes 48-51
    float   velCov3;        // bytes 52-55
    float   velCov4;        // bytes 56-59
    float   velCov5;        // bytes 60-63
    float   velCov6;        // bytes 64-67

    float   height;         // bytes 68-71
    float   heightVariance; // bytes 72-75

    union {
        uint8_t flags;      // byte 76
        struct {
            bool velX: 1;
            bool velY: 1;
            bool velZ: 1;
            bool __unused:  1;
            bool posX: 1;
            bool posY: 1;
            bool posZ: 1;
            bool __unused:  1;
        } isValid;
    };

    uint8_t __unused_byte77; // bytes 77
    uint8_t __unused_byte78; // bytes 78
    uint8_t __unused_byte79; // bytes 79
} MvoRecord;

@interface MvoRecordCreator : NSObject

+ (MvoRecord) from: (nonnull NSData *) data;

@end

// From https://github.com/BudWalkerJava/DatCon/blob/master/DatCon/src/DatConRecs/RecIMU.java#L179
// TODO
typedef struct __attribute__((packed)) {
    double   longitude;         // bytes 0-7
    double   latitude;          // bytes 8-15

    float    baromRaw;          // bytes 16-19

    float    accelX;            // bytes 20-23
    float    accelY;            // bytes 24-27
    float    accelZ;            // bytes 28-31

    float    gyroX;             // bytes 32-35
    float    gyroY;             // bytes 36-39
    float    gyroZ;             // bytes 40-43

    float    baromSmooth;       // bytes 44-47

    float    quatW;       // bytes 48-51
    float    quatX;       // bytes 52-55
    float    quatY;       // bytes 56-59
    float    quatZ;       // bytes 60-63

    // FIXME: Acceleration in intertial frame?
    float    agX;               // bytes 64-67
    float    agY;               // bytes 68-71
    float    agZ;               // bytes 72-75

    float    velN;              // bytes 76-79
    float    velE;              // bytes 80-83
    float    velD;              // bytes 84-87

    // FIXME: Gyro in body frame?
    float    gbX;               // bytes 88-91
    float    gbY;               // bytes 92-95
    float    gbZ;               // bytes 96-99

    uint16_t magX;              // bytes 100-101
    uint16_t magY;              // bytes 102-103
    uint16_t magZ;              // bytes 104-105

    uint16_t temperatute;       // bytes 106-107

    // TODO: Anything left? Check packed length
} ImuRecord;

@interface ImuRecordCreator : NSObject

+ (ImuRecord) from: (nonnull NSData *) data;

@end

// Some helpful info: https://github.com/o-gs/dji-firmware-tools/blob/master/comm_dissector/wireshark/dji-p3-flyrec-proto.lua
// TODO
typedef struct __attribute__((packed)) {
    // The header says the payload length is 76 bytes,
    // in reality there is more stuff. Who knowns what that is...

    // 76 bytes in total
    float   velX;            // 0-3
    float   velY;            // 4-7
    float   velZ;            // 8-11

    float   posX;            // 12-15
    float   posY;            // 16-19
    float   posZ;            // 20-23

    /// (?) Velocity from range finder (ultrasonic)
    float   usV;             // 24-27
    /// (?) Distance from range finder (ultrasonic)
    float   usP;             // 28-31

    double  rtkLong;         // 32-39
    double  rtkLat;          // 40-47
    float   rtkAlt;          // 48-51

    union {                  // 52-53
        uint16_t flags;
        struct {
            bool velX: 1;
            bool velY: 1;
            bool velZ: 1;

            bool posX: 1;
            bool posY: 1;
            bool posZ: 1;

            bool usV: 1;
            bool usP: 1;
        } isValid;
    };

    union {                  // 54-55
        uint16_t errorFlags;
        struct {
            uint16_t vgLarge: 1;
            uint16_t gpsYaw: 1;
            uint16_t magYaw: 1;
            uint16_t gpsConsist: 1;
            uint16_t usFail: 1;
            uint16_t initOk: 1;
        } error;
    };

    uint16_t __reserved_1;      // 56-57
    uint16_t count;          // 58-59

    // FIXME
//    // 16 bytes left
//    uint8_t bytes[16];

    uint32_t __reserved_2;
    // 12 bytes left
    //uint8_t bytes[12];
    float f1;
    float f2;
    float f3;

} ImuExRecord;

@interface ImuExRecordCreator : NSObject

+ (ImuExRecord) from: (nonnull NSData *) data;

@end
