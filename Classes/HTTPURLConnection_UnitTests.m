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

#import "HTTPURLConnection.h"
#import "UnitTest.h"

#define kTestFileURL @"http://images.apple.com/movies/us/pr/photos/exec/stevejobs.tif.zip"  // 2.5Mb
#define kTestPageURL @"http://www.apple.com/"

@interface HTTPURLConnectionTests : UnitTest
@end

@implementation HTTPURLConnectionTests

- (void) testDownload {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  
  // Headers download
  NSDictionary* headers = [HTTPURLConnection downloadHeaderFieldsFromHTTPURL:[NSURL URLWithString:kTestFileURL]
                                                                   userAgent:nil
                                                               handleCookies:NO
                                                                    delegate:nil];
  AssertNotNil(headers);
  NSInteger contentLength = [[headers objectForKey:@"Content-Length"] integerValue];
  AssertGreaterThan(contentLength, (NSInteger)0);
  
  // Download to memory
  {
    NSData* data = [HTTPURLConnection downloadContentsToMemoryFromHTTPURL:[NSURL URLWithString:kTestFileURL]
                                                                userAgent:nil
                                                            handleCookies:NO
                                                                 delegate:nil
                                                             headerFields:NULL];
    AssertNotNil(data);
    AssertEqual(data.length, (NSUInteger)contentLength);
  }
  
  // Download to file
  {
    BOOL result = [HTTPURLConnection downloadContentsFromHTTPURL:[NSURL URLWithString:kTestFileURL]
                                                    toFileAtPath:path
                                                          resume:NO
                                                       userAgent:nil
                                                   handleCookies:NO
                                                        delegate:nil
                                                    headerFields:NULL];
    AssertTrue(result);
    NSInteger size = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize];
    AssertEqual(size, contentLength);
  }
  
  // Check HTTP-Range
  {
    AssertTrue(truncate([path fileSystemRepresentation], contentLength / 2) == 0);
    BOOL result = [HTTPURLConnection downloadContentsFromHTTPURL:[NSURL URLWithString:kTestFileURL]
                                                    toFileAtPath:path
                                                          resume:YES
                                                       userAgent:nil
                                                   handleCookies:NO
                                                        delegate:nil
                                                    headerFields:NULL];
    AssertTrue(result);
    NSInteger size = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize];
    AssertEqual(size, contentLength);
  }
  
  [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

- (void) testGZip {
  NSDictionary* headers = nil;
  NSData* data = [HTTPURLConnection downloadContentsToMemoryFromHTTPURL:[NSURL URLWithString:kTestPageURL]
                                                              userAgent:nil
                                                          handleCookies:NO
                                                               delegate:nil
                                                           headerFields:&headers];
  AssertNotNil(data);
  AssertNotNil(headers);
  AssertTrue([[headers objectForKey:@"Content-Type"] hasPrefix:@"text/html"]);
  AssertEqualObjects([headers objectForKey:@"Content-Encoding"], @"gzip");
  AssertGreaterThan([[headers objectForKey:kHTTPURLConnection_HeaderField_DataLength] integerValue],
                    [[headers objectForKey:@"Content-Length"] integerValue]);
  
  NSString* html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  AssertTrue([html hasPrefix:@"<!DOCTYPE html>"]);
  AssertNotNil(html);
  [html release];
}

@end
