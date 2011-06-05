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

@interface RichAttachment : NSObject <NSCoding> {
@private
  NSUInteger _location;
}
@property(nonatomic, readonly) NSUInteger location;
@end

@interface RichString : NSObject <NSCoding> {
@private
  NSMutableString* _string;
  NSUInteger _maxStateRuns;
  NSUInteger _stateRunCount;
  void* _stateRunList;
  NSMutableArray* _attachments;
  NSUInteger _lastStateRunIndex;
}
@property(nonatomic, readonly) NSUInteger length;
@property(nonatomic, readonly) NSString* string;  // Returns backing storage for efficiency
@property(nonatomic, readonly) NSUInteger numberOfAttachments;
@property(nonatomic, readonly) NSArray* attachments;  // Returns backing storage for efficiency
- (void) trimToLocation:(NSUInteger)location;
- (void) clearString;  // Also reset attachments locations
- (void) appendString:(NSString*)string;
- (void) setState:(NSUInteger)state;
- (NSUInteger) findFirstState:(NSUInteger*)state;  // Returns NSNotFound if none
- (NSUInteger) findLastState:(NSUInteger*)state;  // Returns NSNotFound if none
- (NSUInteger) findPreviousStateFromLocation:(NSUInteger)location state:(NSUInteger*)state;  // Returns state at passed location if there's one or NSNotFound if there's no previous state at all
- (NSUInteger) findNextStateFromLocation:(NSUInteger)location state:(NSUInteger*)state;  // Returns state at passed location if there's one or NSNotFound if there's no next state at all
- (void) insertAttachment:(RichAttachment*)attachment;  // Must conform to <NSCoding> if for RichString instances that are archived
- (NSUInteger) findFirstAttachment:(RichAttachment**)attachment;  // Returns NSNotFound if none
- (NSUInteger) findLastAttachment:(RichAttachment**)attachment;  // Returns NSNotFound if none
- (NSUInteger) findNextAttachmentFromLocation:(NSUInteger)location attachment:(RichAttachment**)attachment;  // Returns attachement at passed location if there's one or NSNotFound if there's no next attachment at all
- (NSArray*) findAttachmentsInRange:(NSRange)range;  // Returns attachments stricly before the end of the range (except if the range end is the string end)
@end
