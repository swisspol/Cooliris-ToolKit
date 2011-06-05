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

#import "MapAnnotation.h"

@implementation MapAnnotation

@synthesize coordinate=_coordinate, title=_title, subtitle=_subtitle;

- (id) initWithCoordinate:(CLLocationCoordinate2D)coordinate title:(NSString*)title subtitle:(NSString*)subtitle {
  if ((self = [super init])) {
    _coordinate = coordinate;
    _title = [title copy];
    _subtitle = [subtitle copy];
  }
  return self;
}

- (void) dealloc {
  [_title release];
  [_subtitle release];
  
  [super dealloc];
}

@end
