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

#import <Foundation/Foundation.h>

// This will set appropriately the "Date" and "Authorization" HTTP headers
// Request URL host is expected to be "s3.amazonaws.com" or "bucket.s3.amazonaws.com"
@interface NSMutableURLRequest (AmazonS3)
- (void) setAmazonS3AuthorizationWithAccessKeyID:(NSString*)accessKeyID secretAccessKey:(NSString*)secretAccessKey;
@end
