//
//  SMOutputStream.m
//  SnoizeMIDI
//
//  Created by krevis on Tue Dec 04 2001.
//  Copyright (c) 2001 __MyCompanyName__. All rights reserved.
//

#import "SMOutputStream.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "SMMessage.h"


@interface SMOutputStream (Private)

- (MIDIPacketList *)_packetListForMessages:(NSArray *)messages;

@end


@implementation SMOutputStream

- (id)init;
{
    if (!(self = [super init]))
        return nil;

    flags.ignoresTimeStamps = NO;

    return self;
}

- (void)dealloc;
{
    [super dealloc];
}

- (BOOL)ignoresTimeStamps;
{
    return flags.ignoresTimeStamps;
}

- (void)setIgnoresTimeStamps:(BOOL)value;
{
    flags.ignoresTimeStamps = value;
}

- (MIDITimeStamp)sendImmediatelyTimeStamp;
{
    return 0;
}

- (void)takeMIDIMessages:(NSArray *)messages;
{
    MIDIPacketList *packetList;

    if ([messages count] == 0)
        return;

    packetList = [self _packetListForMessages:messages];
    [self sendMIDIPacketList:packetList];
    NSZoneFree(NSDefaultMallocZone(), packetList);
}

- (void)sendMIDIPacketList:(MIDIPacketList *)packetList;
{
    // Implement this in subclasses
    OBRequestConcreteImplementation(self, _cmd);
}

@end


@implementation SMOutputStream (Private)

const unsigned int maxPacketSize = 65535;

- (MIDIPacketList *)_packetListForMessages:(NSArray *)messages;
{
    unsigned int messageIndex, messageCount;
    unsigned int packetListSize;
    MIDIPacketList *packetList;
    MIDIPacket *packet;
    MIDITimeStamp sendImmediatelyTimeStamp;

    messageCount = [messages count];
    packetListSize = offsetof(MIDIPacketList, packet);

    for (messageIndex = 0; messageIndex < messageCount; messageIndex++) {
        SMMessage *message;
        unsigned int otherDataLength;
        unsigned int packetCount;

        message = [messages objectAtIndex:messageIndex];
        otherDataLength = [message otherDataLength];
        // Remember that all messages are at least 1 byte long; otherDataLength is on top of that.

        // Messages > maxPacketSize need to be split across multiple packets
        packetCount = 1 + (1 + otherDataLength) / (maxPacketSize + 1);            
        packetListSize += packetCount * offsetof(MIDIPacket, data) + 1 + otherDataLength;
    }

    packetList = (MIDIPacketList *)NSZoneMalloc(NSDefaultMallocZone(), packetListSize);
    packetList->numPackets = messageCount;

    if (flags.ignoresTimeStamps)
        sendImmediatelyTimeStamp = [self sendImmediatelyTimeStamp];

    packet = &(packetList->packet[0]);
    for (messageIndex = 0; messageIndex < messageCount; messageIndex++) {
        SMMessage *message;
        unsigned int otherDataLength;
        unsigned int packetCount, packetIndex;
        const Byte *messageData;
        unsigned int remainingLength;
        
        message = [messages objectAtIndex:messageIndex];
        otherDataLength = [message otherDataLength];
        packetCount = 1 + (1 + otherDataLength) / (maxPacketSize + 1);

        messageData = [message otherDataBuffer];
        remainingLength = 1 + otherDataLength;

        for (packetIndex = 0; packetIndex < packetCount; packetIndex++) {
            if (flags.ignoresTimeStamps)
                packet->timeStamp = sendImmediatelyTimeStamp;
            else
                packet->timeStamp = [message timeStamp];

            if (packetIndex + 1 == packetCount)		// last packet
                packet->length = remainingLength;
            else
                packet->length = maxPacketSize;
            
            if (packetIndex == 0) {	
                // First packet needs special copying of status byte
                packet->data[0] = [message statusByte];
                if (packet->length > 1)
                    memcpy(&packet->data[1], messageData, packet->length - 1);
            } else {
                memcpy(&packet->data[0], messageData, packet->length);
            }
            
            messageData += packet->length;
            remainingLength -= packet->length;

            packet = MIDIPacketNext(packet);
        }
    }
    
    return packetList;
}

@end
