//
//  ProtocolConstants.swift
//  TelloSwift
//
//  Created by Boris Gromov on 27.03.2020.
//  Copyright © 2020 Volaly. All rights reserved.


import Foundation

enum PacketType: UInt8 {
    case extended    = 0
    case getInfo     = 1
    case data1       = 2
    case __unknown_3 = 3
    case data2       = 4
    case setInfo     = 5
    case flip        = 6
    case __unknown_7 = 7
}

let packetHeader: UInt8 = 0xcc

// Adopted from TelloPy
enum MessageId: UInt16 {
    case connectCmd            = 0x0001
    case connectMsg            = 0x0002

    case ssidMsg               = 0x0011
    case ssidCmd               = 0x0012
    case ssidPasswordMsg       = 0x0013
    case ssidPasswordCmd       = 0x0014
    case wifiRegionMsg         = 0x0015
    case wifiRegionCmd         = 0x0016
    case wifiMsg               = 0x001A
    case videoEncoderRateCmd   = 0x0020
    case videoDynAdjRateCmd    = 0x0021
    case eisCmd                = 0x0024
    case videoStartCmd         = 0x0025
    case videoRateQuery        = 0x0028
    case takePictureCommand    = 0x0030
    case videoModeCmd          = 0x0031
    case videoRecordCmd        = 0x0032
    case exposureCmd           = 0x0034
    case lightMsg              = 0x0035
    case jpegQualityMsg        = 0x0037
    case error1Msg             = 0x0043
    case error2Msg             = 0x0044
    case versionMsg            = 0x0045
    case timeCmd               = 0x0046
    case activationTimeMsg     = 0x0047
    case loaderVersionMsg      = 0x0049
    case stickCmd              = 0x0050
    case takeoffCmd            = 0x0054
    case landCmd               = 0x0055
    case flightMsg             = 0x0056
    case altLimitCmd           = 0x0058
    case flipCmd               = 0x005C
    case throwAndGoCmd         = 0x005D
    case palmLandCmd           = 0x005E
    case telloCmdFileSize      = 0x0062  // pt50
    case telloCmdFileData      = 0x0063  // pt50
    case telloCmdFileComplete  = 0x0064  // pt48
    case smartVideoCmd         = 0x0080
    case smartVideoStatusMsg   = 0x0081
    case logHeaderMsg          = 0x1050
    case logDataMsg            = 0x1051
    case logConfigMsg          = 0x1052
    case bounceCmd             = 0x1053
    case calibrateCmd          = 0x1054
    case lowBatThresholdCmd    = 0x1055
    case altLimitMsg           = 0x1056
    case lowBatThresholdMsg    = 0x1057
    case attLimitCmd           = 0x1058  // Stated incorrectly by Wiki (checked from raw packets)
    case attLimitMsg           = 0x1059
}

public enum CalibrationType: UInt8 {
    case imu = 0
    case centerOfGravity = 1
}

public enum FlipCmd: UInt8 {
    case front        = 0
    case left         = 1
    case back         = 2
    case right        = 3

    case forwardLeft  = 4
    case backLeft     = 5
    case backRight    = 6
    case forwardRight = 7
}

let logRecordSeparator: UInt8 = 0x55 // Character("U").asciiValue!

public enum LogRecordType: UInt16 {
    case mvo             = 0x001d
    case imu             = 0x0800
    case imuEx           = 0x0810 // contains visual odometry

    // Experimental
    // https://github.com/Kragrathea/TelloLib/blob/master/TelloLib/parsedRecSpecs.json
    case goTxtOrOsd      = 0x000c
    case uSonic          = 0x0010
    case controller      = 0x03e8
    case aircraftCond    = 0x03e9
    case serialApiInputs = 0x03ea
    case battInfo        = 0x06ae
    case attiMini        = 0x08a0
    case nsDataDebug     = 0x2765
    case nsDataComponent = 0x2766
    case recAirComp      = 0x2774

    // Once in the air, the following also reported
    // https://github.com/o-gs/dji-firmware-tools/blob/master/comm_dissector/wireshark/dji-mavic-flyrec-proto.lua
    case ctrlVertDbg        = 0x04b0
    case ctrlVertVelDbg     = 0x04b2
    case ctrlVertAccDbg     = 0x04b3

    case ctrlHorizDbg       = 0x0514
    case _unknown_x0517     = 0x0517
    case ctrlHorizAttDbg    = 0x0518
    case ctrlHorizAngVelDbg = 0x0519
    /// CCPM - Cyclic/Collective Pitch Mixing Control?
    case ctrlHorizCcpmDbg   = 0x051a
    case ctrlHorizMotorDbg  = 0x051b
}

public enum LogMvoFlags: UInt8 {
    case validVelX = 0x01
    case validVelY = 0x02
    case validVelZ = 0x04
    case validVel  = 0x07

    case validPosX = 0x10
    case validPosY = 0x20
    case validPosZ = 0x40
    case validPos  = 0x70
}
