//
//  Protocol.m
//  TelloSwift
//
//  Created by Boris Gromov on 27.03.2020.
//  Copyright © 2020 Volaly. All rights reserved.


#import "Protocol.h"
#import "Crc.h"

@implementation TelloPacketCreator: NSObject

+ (nonnull NSData *)dataFrom:(PacketPreambula) preambula payload:(nullable NSData *) payload {
    PacketPreambula pre = preambula;
    // fixup the packet size
    uint16_t sz = sizeof(PacketPreambula) + payload.length + 2;
    pre.packetSize.__packetSizeL = (sz << 3) & 0xff;
    pre.packetSize.__packetSizeH = (sz >> 5) & 0xff;

    NSData *header3 = [NSData dataWithBytes:&pre length:3];
    pre.crc8 = crc8(header3);

    NSMutableData *packetData = [NSMutableData dataWithBytes:&pre length:sizeof(PacketPreambula)];

    if (payload) {
        [packetData appendData:payload];
    }

    uint16_t crc = crc16(packetData);
    [packetData appendBytes:&crc length:sizeof(uint16_t)];

    return packetData;
}

+ (PacketPreambula)preambulaFrom:(nonnull NSData *) packet {
    PacketPreambula pre;
    NSUInteger preLen = sizeof(PacketPreambula);

    [packet getBytes:&pre length:preLen];

    // fixup the packet size
    uint16_t packetSize = pre.packetSize.__packetSizeL + ((pre.packetSize.__packetSizeH << 8) >> 3);
    pre.packetSize.packetSize = packetSize;

    return pre;
}

+ (nullable NSData *)payloadFrom:(nonnull NSData *) packet {
    NSUInteger preLen = sizeof(PacketPreambula);
    NSInteger payloadLen = packet.length - preLen - 2;
    NSData *data;

    if (payloadLen <= 0) {
        return NULL;
    }

    data = [packet subdataWithRange:NSMakeRange(preLen, payloadLen)];

    return data;
}

@end

@implementation TelloFlightDataParser: NSObject

+ (FlightData)flightDataFrom: (nonnull NSData *) data {
    FlightData flighData = {0};

    if (data.length == sizeof(FlightData)) {
        [data getBytes:&flighData length:sizeof(FlightData)];
    }

    return flighData;
}

@end

@implementation TelloSticksDataCreator : NSObject

+ (nonnull NSData *)dataFrom:(SticksData) sticksData {
    NSData *data = [NSData dataWithBytes:&sticksData length:sizeof(sticksData)];

    return data;
}

@end

@implementation LogRecordCreator : NSObject

+ (LogRecord) from: (nonnull NSData *) data {
    LogRecord rec;

    if (data.length < (sizeof(LogRecordHeader) + 2)) {
        NSLog(@"LogRecordCreator: No data. Corrupted packet?");
        return rec;
    }

    NSUInteger lenPayload = data.length - sizeof(LogRecordHeader) - 2; // minus CRC16

    [data getBytes:&rec.header length:sizeof(LogRecordHeader)];
    NSMutableData* payload = [NSMutableData dataWithBytes:(data.bytes + sizeof(LogRecordHeader)) length:lenPayload];

    char * bytes = [payload mutableBytes];
    // If not, don't decipher
    if (rec.header.header == 0x55) {
        // Decipher payload
        for (NSUInteger i = 0; i < payload.length; i++) {
            bytes[i] ^= rec.header.xorValue;
        }
    }

    rec.payload = payload;

    return rec;
}

@end

@implementation MvoRecordCreator : NSObject

+ (MvoRecord) from: (nonnull NSData *) data {
    MvoRecord mvo;

    [data getBytes:&mvo length:sizeof(MvoRecord)];

    return mvo;
}

@end

@implementation ImuRecordCreator : NSObject

+ (ImuRecord) from: (nonnull NSData *) data {
    ImuRecord imu;

    [data getBytes:&imu length:sizeof(ImuRecord)];

    return imu;
}

@end

@implementation ImuExRecordCreator : NSObject

+ (ImuExRecord) from: (nonnull NSData *) data {
    ImuExRecord imu;

    [data getBytes:&imu length:sizeof(ImuExRecord)];

    return imu;
}

@end
