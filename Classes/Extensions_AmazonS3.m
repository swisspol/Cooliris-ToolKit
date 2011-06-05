// Copyright 2011 Cooliris, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import <CommonCrypto/CommonHMAC.h>
#import <libkern/OSAtomic.h>

#import "Extensions_AmazonS3.h"
#import "Extensions_Foundation.h"

static char* NewBase64Encode(const void *buffer, size_t length, bool separateLines, size_t *outputLength);

static NSData* _ComputeSHA1HMAC(NSData* data, NSString* key) {
  NSMutableData* hash = [NSMutableData dataWithLength:CC_SHA1_DIGEST_LENGTH];
  const char* keyString = [key UTF8String];
  CCHmac(kCCHmacAlgSHA1, keyString, strlen(keyString), [data bytes], [data length], [hash mutableBytes]);
  return hash;
}

static NSString* _EncodeBase64(NSData* data) {
  NSString* string = nil;
  size_t length;
  char* buffer = NewBase64Encode([data bytes], [data length], false, &length);
  if(buffer) {
    string = [[[NSString alloc] initWithBytes:buffer length:length encoding:NSUTF8StringEncoding] autorelease];
    free(buffer);
  }
  return string;
}

@implementation NSMutableURLRequest (AmazonS3)

// http://docs.amazonwebservices.com/AmazonS3/latest/dev/index.html?RESTAuthentication.html
- (void) setAmazonS3AuthorizationWithAccessKeyID:(NSString*)accessKeyID secretAccessKey:(NSString*)secretAccessKey {
  static OSSpinLock spinLock = 0;
  OSSpinLockLock(&spinLock);
  static NSDateFormatter* formatter = nil;
  if (formatter == nil) {
    formatter = [NSDateFormatter new];
    [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"] autorelease]];
    [formatter setTimeZone:[NSTimeZone GMTTimeZone]];
    [formatter setDateFormat:@"EEE, d MMM yyyy HH:mm:ss Z"];
  }
  NSString* dateString = [formatter stringFromDate:[NSDate date]];
  OSSpinLockUnlock(&spinLock);
  
  NSURL* url = [self URL];
  NSDictionary* headers = [self allHTTPHeaderFields];
  NSMutableString* buffer = [[NSMutableString alloc] init];
  [buffer appendFormat:@"%@\n", [self HTTPMethod]];
  [buffer appendFormat:@"%@\n", ([headers objectForKey:@"Content-MD5"] ? [headers objectForKey:@"Content-MD5"] : @"")];
  [buffer appendFormat:@"%@\n", ([headers objectForKey:@"Content-Type"] ? [headers objectForKey:@"Content-Type"] : @"")];
  [buffer appendFormat:@"%@\n", dateString];
  NSMutableString* amzHeaders = [[NSMutableString alloc] init];
  for (NSString* header in [[headers allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    if ([header hasPrefix:@"x-amz-"] || [header hasPrefix:@"X-Amz-"]) {
      [amzHeaders appendFormat:@"%@:%@\n", [header lowercaseString], [headers objectForKey:header]];
    }
  }
  [buffer appendString:amzHeaders];
  [amzHeaders release];
  NSString* host = [url host];
  if ([host isEqualToString:@"s3.amazonaws.com"]) {
    [buffer appendString:[url path]];
  } else {
    if ([host hasSuffix:@".amazonaws.com"]) {
      NSRange range = [host rangeOfString:@"." options:NSBackwardsSearch range:NSMakeRange(0, [host length] - [@".amazonaws.com" length])];
      if (range.location != NSNotFound) {  // This is not supposed to ever happen
        host = [host substringToIndex:range.location];
      }
    }
    if ([[url path] length]) {
      [buffer appendFormat:@"/%@%@", host, [url path]];
    } else {
      [buffer appendFormat:@"/%@/", host];
    }
  }
  NSString* query = [url query];
  if ([query isEqualToString:@"location"] || [query isEqualToString:@"logging"] || [query isEqualToString:@"torrent"]) {
    [buffer appendFormat:@"?%@", query];
  }
  NSString* authorization = _EncodeBase64(_ComputeSHA1HMAC([buffer dataUsingEncoding:NSUTF8StringEncoding], secretAccessKey));
  [buffer release];
  
  [self setValue:dateString forHTTPHeaderField:@"Date"];
  [self setValue:[NSString stringWithFormat:@"AWS %@:%@", accessKeyID, authorization] forHTTPHeaderField:@"Authorization"];
}

@end

// Source below was copied from http://cocoawithlove.com/2009/06/base64-encoding-options-on-mac-and.html

//
//  NSData+Base64.h
//  base64
//
//  Created by Matt Gallagher on 2009/06/03.
//  Copyright 2009 Matt Gallagher. All rights reserved.
//
//  Permission is given to use this source code file, free of charge, in any
//  project, commercial or otherwise, entirely at your risk, with the condition
//  that any redistribution (in part or whole) of source code must retain
//  this copyright and permission notice. Attribution in compiled projects is
//  appreciated but not required.
//

static unsigned char base64EncodeLookup[65] =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

//
// Fundamental sizes of the binary and base64 encode/decode units in bytes
//
#define BINARY_UNIT_SIZE 3
#define BASE64_UNIT_SIZE 4

//
// NewBase64Decode
//
// Encodes the arbitrary data in the inputBuffer as base64 into a newly malloced
// output buffer.
//
//  inputBuffer - the source data for the encode
//  length - the length of the input in bytes
//  separateLines - if zero, no CR/LF characters will be added. Otherwise
//    a CR/LF pair will be added every 64 encoded chars.
//  outputLength - if not-NULL, on output will contain the encoded length
//    (not including terminating 0 char)
//
// returns the encoded buffer. Must be free'd by caller. Length is given by
//  outputLength.
//
static char *NewBase64Encode(
  const void *buffer,
  size_t length,
  bool separateLines,
  size_t *outputLength)
{
  const unsigned char *inputBuffer = (const unsigned char *)buffer;
  
  #define MAX_NUM_PADDING_CHARS 2
  #define OUTPUT_LINE_LENGTH 64
  #define INPUT_LINE_LENGTH ((OUTPUT_LINE_LENGTH / BASE64_UNIT_SIZE) * BINARY_UNIT_SIZE)
  #define CR_LF_SIZE 2
  
  //
  // Byte accurate calculation of final buffer size
  //
  size_t outputBufferSize =
      ((length / BINARY_UNIT_SIZE)
        + ((length % BINARY_UNIT_SIZE) ? 1 : 0))
          * BASE64_UNIT_SIZE;
  if (separateLines)
  {
    outputBufferSize +=
      (outputBufferSize / OUTPUT_LINE_LENGTH) * CR_LF_SIZE;
  }
  
  //
  // Include space for a terminating zero
  //
  outputBufferSize += 1;

  //
  // Allocate the output buffer
  //
  char *outputBuffer = (char *)malloc(outputBufferSize);
  if (!outputBuffer)
  {
    return NULL;
  }

  size_t i = 0;
  size_t j = 0;
  const size_t lineLength = separateLines ? INPUT_LINE_LENGTH : length;
  size_t lineEnd = lineLength;
  
  while (true)
  {
    if (lineEnd > length)
    {
      lineEnd = length;
    }

    for (; i + BINARY_UNIT_SIZE - 1 < lineEnd; i += BINARY_UNIT_SIZE)
    {
      //
      // Inner loop: turn 48 bytes into 64 base64 characters
      //
      outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i] & 0xFC) >> 2];
      outputBuffer[j++] = base64EncodeLookup[((inputBuffer[i] & 0x03) << 4)
        | ((inputBuffer[i + 1] & 0xF0) >> 4)];
      outputBuffer[j++] = base64EncodeLookup[((inputBuffer[i + 1] & 0x0F) << 2)
        | ((inputBuffer[i + 2] & 0xC0) >> 6)];
      outputBuffer[j++] = base64EncodeLookup[inputBuffer[i + 2] & 0x3F];
    }
    
    if (lineEnd == length)
    {
      break;
    }
    
    //
    // Add the newline
    //
    outputBuffer[j++] = '\r';
    outputBuffer[j++] = '\n';
    lineEnd += lineLength;
  }
  
  if (i + 1 < length)
  {
    //
    // Handle the single '=' case
    //
    outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i] & 0xFC) >> 2];
    outputBuffer[j++] = base64EncodeLookup[((inputBuffer[i] & 0x03) << 4)
      | ((inputBuffer[i + 1] & 0xF0) >> 4)];
    outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i + 1] & 0x0F) << 2];
    outputBuffer[j++] =  '=';
  }
  else if (i < length)
  {
    //
    // Handle the double '=' case
    //
    outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i] & 0xFC) >> 2];
    outputBuffer[j++] = base64EncodeLookup[(inputBuffer[i] & 0x03) << 4];
    outputBuffer[j++] = '=';
    outputBuffer[j++] = '=';
  }
  outputBuffer[j] = 0;
  
  //
  // Set the output length and return the buffer
  //
  if (outputLength)
  {
    *outputLength = j;
  }
  return outputBuffer;
}
