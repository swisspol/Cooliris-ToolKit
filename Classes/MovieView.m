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

#import <MediaPlayer/MediaPlayer.h>

#import "MovieView.h"
#import "Logging.h"

#define kButtonSize 72.0

@implementation MovieView

@synthesize movieURL=_movieURL, delegate=_delegate;

- (void) _movieIsPreparedToPlay:(NSNotification*)notification {
  if ([notification object] == _movieController) {
    NSError* error = [[notification userInfo] objectForKey:@"error"];
    if (error) {
      if ([_delegate respondsToSelector:@selector(movieView:didFailPlayingMovieWithError:)]) {
        [_delegate movieView:self didFailPlayingMovieWithError:error];
      }
      [self unloadMovie];
      _button.enabled = NO;
    }
  }
}

- (void) _movieDidFinishPlayback:(NSNotification*)notification {
  if ([notification object] == _movieController) {
    MPMovieFinishReason reason = [[[notification userInfo] objectForKey:MPMoviePlayerPlaybackDidFinishReasonUserInfoKey] integerValue];
    if (reason == MPMovieFinishReasonPlaybackError) {
      NSError* error = [[notification userInfo] objectForKey:@"error"];
      if ([_delegate respondsToSelector:@selector(movieView:didFailPlayingMovieWithError:)]) {
        [_delegate movieView:self didFailPlayingMovieWithError:error];
      }
      [self unloadMovie];
      _button.enabled = NO;
    } else if (reason == MPMovieFinishReasonPlaybackEnded) {
      _movieController.currentPlaybackTime = 0.0;
      if (_movieController.fullscreen) {
        [_movieController setFullscreen:NO animated:YES];
      }
      _movieController.view.hidden = YES;  // Keep MPMovieController around to ensure the movie stays loaded
      _movieController.shouldAutoplay = NO;  // Disable autoplay to prevent movie to restart
      _button.hidden = NO;
    }
  }
}

- (void) _didBecomeActive:(NSNotification*)notification {
  if (_wasPlaying) {
    [_movieController play];
  }
}

- (void) _willResignActive:(NSNotification*)notification {
  _wasPlaying = _movieController.currentPlaybackRate != 0.0;
  if (_wasPlaying) {
    [_movieController pause];
  }
}

- (void) _playMovie:(id)sender {
  if (_movieController) {
    _button.hidden = YES;
    _movieController.view.hidden = NO;
    [_movieController play];
  } else {
    [self loadMovie];
  }
}

- (id) initWithMovieURL:(NSURL*)url {
  CHECK(url);
  if ((self = [super initWithFrame:CGRectZero])) {
    _movieURL = [url retain];
    _button = [[UIButton alloc] init];
    [_button setBackgroundImage:[UIImage imageNamed:@"MovieView-Button-Disabled.png"] forState:UIControlStateDisabled];
    [_button setBackgroundImage:[UIImage imageNamed:@"MovieView-Button-Off.png"] forState:UIControlStateNormal];
    [_button setBackgroundImage:[UIImage imageNamed:@"MovieView-Button-On.png"] forState:UIControlStateHighlighted];
    [_button addTarget:self action:@selector(_playMovie:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_button];
    
    self.autoresizesSubviews = NO;
    self.backgroundColor = [UIColor blackColor];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_movieIsPreparedToPlay:)
                                                 name:MPMediaPlaybackIsPreparedToPlayDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_movieDidFinishPlayback:)
                                                 name:MPMoviePlayerPlaybackDidFinishNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_didBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_willResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
  }
  return self;
}

- (void) dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerPlaybackDidFinishNotification object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMediaPlaybackIsPreparedToPlayDidChangeNotification object:nil];
  
  [self unloadMovie];
  
  [_movieURL release];
  [_button release];
  
  [super dealloc];
}

- (id) initWithCoder:(NSCoder*)coder {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (void) encodeWithCoder:(NSCoder*)coder {
  [self doesNotRecognizeSelector:_cmd];
}

- (void) loadMovie {
  if (_movieController == nil) {
    LOG_VERBOSE(@"MPMoviePlayerController movie loaded from \"%@\"", _movieURL);
    _movieController = [[MPMoviePlayerController alloc] initWithContentURL:_movieURL];
    if (_movieController) {
      _movieController.movieSourceType = MPMovieSourceTypeFile;
      _movieController.useApplicationAudioSession = YES;
      _movieController.shouldAutoplay = YES;
      
      _movieController.view.frame = self.bounds;
      [self insertSubview:_movieController.view atIndex:0];
      
      _button.hidden = YES;
    } else {
      DNOT_REACHED();
    }
  }
}

- (void) unloadMovie {
  if (_movieController) {
    [_movieController stop];
    [_movieController.view removeFromSuperview];
    [_movieController release];
    _movieController = nil;
    
    _button.hidden = NO;
    LOG_VERBOSE(@"MPMoviePlayerController movie unloaded");
  }
}

- (BOOL) isMovieLoaded {
  return _movieController ? YES : NO;
}

- (void) layoutSubviews {
  CGRect bounds = self.bounds;
  _button.frame = CGRectMake(roundf(bounds.size.width - kButtonSize) / 2.0, roundf(bounds.size.height - kButtonSize) / 2.0,
                             kButtonSize, kButtonSize);
  _movieController.view.frame = bounds;
}

@end
