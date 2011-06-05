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

#import <UIKit/UIKit.h>

@class MovieView, MPMoviePlayerController;

@protocol MovieViewDelegate <NSObject>
@optional
- (void) movieView:(MovieView*)movieView didFailPlayingMovieWithError:(NSError*)error;
@end

@interface MovieView : UIView {
@private
  NSURL* _movieURL;
  id<MovieViewDelegate> _delegate;
  
  UIButton* _button;
  MPMoviePlayerController* _movieController;
  BOOL _wasPlaying;
}
@property(nonatomic, assign) id<MovieViewDelegate> delegate;
@property(nonatomic, readonly) NSURL* movieURL;
@property(nonatomic, readonly, getter=isMovieLoaded) BOOL movieLoaded;
- (id) initWithMovieURL:(NSURL*)url;
- (void) loadMovie;
- (void) unloadMovie;
@end
