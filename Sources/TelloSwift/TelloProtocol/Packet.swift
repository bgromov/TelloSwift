//
//  Packet.swift
//  TelloSwift
//
//  Created by Boris Gromov on 28.03.2020.
//  Copyright © 2020 Volaly. All rights reserved.


import Foundation

class TelloPacket {
    var pre: PacketPreambula
    var payload: Data?

    var rawData: Data?

    init(command: MessageId, packetTypeInfo: PacketTypeInfo, payload: Data? = nil) {
        self.pre = PacketPreambula(header: packetHeader,
                                   packetSize: .init(packetSize: 0),
                                   crc8: 0,
                                   packetTypeInfo: packetTypeInfo,
                                   messageID: command.rawValue,
                                   sequenceNo: 0)

        self.payload = payload
    }

    func getRawData(sequenceNo: UInt16 = 0) -> Data {
        if rawData == nil || pre.sequenceNo != sequenceNo {
            pre.sequenceNo = sequenceNo
            rawData = TelloPacketCreator.data(from: pre, payload: payload)
        }

        return rawData!
    }

    init?(rawData: Data) {
        guard rawData[0] == packetHeader else {return nil}

        pre = TelloPacketCreator.preambula(from: rawData)
        payload = TelloPacketCreator.payload(from: rawData)
    }

    func getPreambula() -> PacketPreambula {
        return pre
    }

    func getPayload() -> Data? {
        return payload
    }
}

extension FlightData: CustomStringConvertible {
    public var description: String {
        return "ALT: \(self.height) | SPD: \(self.groundSpeed) | BAT: \(self.batteryPercentage) | CAM: \(self.cameraState) | MODE: \(self.flyMode)"
    }
}
