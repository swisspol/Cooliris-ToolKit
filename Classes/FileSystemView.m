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

#import "FileSystemView.h"

@implementation FileSystemView

@synthesize basePath=_basePath, showHiddenItems=_showHidden;

- (void) dealloc {
  [_basePath release];
  
  [super dealloc];
}

- (void) setBasePath:(NSString*)path {
  if (path != _basePath) {
    [_basePath release];
    _basePath = [path copy];
    
    NSMutableArray* items = [[NSMutableArray alloc] init];
    for (NSString* path in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_basePath error:NULL]) {
      if (_showHidden || ![path hasPrefix:@"."]) {
        [(NSMutableArray*)items addObject:path];
      }
    }
    self.items = items;
    [items release];
  }
}

- (UIView*) defaultViewForItem:(id)item {
  BOOL isDirectory;
  NSString* path = _basePath ? [_basePath stringByAppendingPathComponent:item] : item;
  NSString* name = _basePath ? item : [path lastPathComponent];
  if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]) {
    UIImage* image = [UIImage imageNamed:(isDirectory ? @"FileSystemView-Directory.png" : @"FileSystemView-File.png")];
    UIImageView* view = [[[UIImageView alloc] initWithImage:image] autorelease];
    UILabel* label = [[UILabel alloc] initWithFrame:CGRectOffset(CGRectInset(view.bounds, isDirectory ? 10.0 : 25.0, 30.0),
                                                                 0.0, 10.0)];
    label.text = name;
    label.textColor = isDirectory ? [UIColor whiteColor] : [UIColor darkGrayColor];
    label.shadowColor = isDirectory ? [UIColor darkGrayColor] : [UIColor whiteColor];
    label.shadowOffset = CGSizeMake(0.0, isDirectory ? -1.0 : 1.0);
    label.font = [UIFont boldSystemFontOfSize:14.0];
    label.textAlignment = UITextAlignmentCenter;
    label.lineBreakMode = UILineBreakModeCharacterWrap;
    label.numberOfLines = 0;
    label.backgroundColor = nil;
    label.opaque = NO;
    [view addSubview:label];
    [label release];
    return view;
  }
  return nil;
}

@end
