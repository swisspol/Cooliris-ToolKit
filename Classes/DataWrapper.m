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

#import "DataWrapper.h"

@implementation DataWrapper

- (id) init {
  return [self initWithBytes:NULL length:0 freeFunction:NULL];
}

- (id) initWithBytes:(const void*)bytes length:(NSUInteger)length freeFunction:(DataWrapperFreeFunction)function {
  if ((self = [super init])) {
    _bytes = bytes;
    _length = length;
    _function = function;
  }
  return self;
}

- (void) dealloc {
  if (_bytes && _function) {
    (*_function)((void*)_bytes);
  }
  
  [super dealloc];
}

- (NSUInteger)length {
  return _length;
}

- (const void*) bytes {
  return _bytes;
}

@end
