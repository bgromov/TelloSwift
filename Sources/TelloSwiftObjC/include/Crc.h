//
//  Crc.h
//  TelloKit
//
//  Created by Boris Gromov on 29.03.2020.
//  Copyright © 2020 Volaly. All rights reserved.

#import <Foundation/Foundation.h>

uint8_t crc8(NSData *buf);
uint16_t crc16(NSData *buf);
