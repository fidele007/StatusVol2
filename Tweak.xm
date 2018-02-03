#import <AudioToolbox/AudioServices.h> // Temporary fix for silent mode vibrate support
#import <QuartzCore/QuartzCore.h>
#import "statusvollite.h"
#import <objc/runtime.h>

// Global vars
StatusVol *svol;
bool sVolIsVisible = NO;
bool IsCurrentAppStatusBarHidden;

// StatusVol needs an auto-rotating UIWindow
@implementation svolWindow
  // Un-hide after rotation
- (void)_finishedFullRotation:(id)arg1 finished:(id)arg2 context:(id)arg3 {
  [super _finishedFullRotation:arg1 finished:arg2 context:arg3];
  [self fixSvolWindow];
  if (sVolIsVisible) {
    [self setHidden:NO]; // Mitigate black box issue
  }
}

// Fix frame after orientation
- (void)fixSvolWindow {
  // Reset frame
  // long orientation = [(SpringBoard *)[UIApplication sharedApplication] _frontMostAppOrientation];
  CGRect windowRect=self.frame;
  windowRect.origin.x = 0;
  windowRect.origin.y = 0;

  if (!sVolIsVisible) {
    windowRect.origin.y = -20;
  }

  [self setFrame:windowRect];
}

// Force support auto-rotation. Hide on rotation events
- (BOOL)_shouldAutorotateToInterfaceOrientation:(int)arg1 {
  [self setHidden:YES]; // Mitigate black box issue
  return YES;
}
@end

@implementation StatusVol
- (id)init {
  self = [super init];
  if (self != nil) {
    preferences = [[NSDictionary alloc] init];
    cachedBrightness = [[NSMutableDictionary alloc] init];
    isAnimatingClose = NO;
    svolCloseInterrupt = NO;

    [self loadPreferences];
    [self initializeWindow];

    hideTimer=nil;
  }
  return self;
}

- (void)loadPreferences {
  NSMutableDictionary *tmpPrefs;
  CFStringRef appID = CFSTR("com.chewmieser.statusvollite");
  CFArrayRef keyList = CFPreferencesCopyKeyList(appID,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
  if (!keyList) {
    tmpPrefs = [[NSMutableDictionary alloc] init];
  } else {
    tmpPrefs = (__bridge NSMutableDictionary *)CFPreferencesCopyMultiple(keyList,appID,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    CFRelease(keyList);
  }

  // Add missing prefs
  if ([tmpPrefs objectForKey:@"UseSquares"] == nil) {
    [tmpPrefs setObject:@"0" forKey:@"UseSquares"];
  }
  if ([tmpPrefs objectForKey:@"HideIcons"] == nil) {
    [tmpPrefs setObject:@"0" forKey:@"HideIcons"];
  }
  if ([tmpPrefs objectForKey:@"InvertColors"] == nil) {
    [tmpPrefs setObject:@"0" forKey:@"InvertColors"];
  }
  if ([tmpPrefs objectForKey:@"DynamicColors"] == nil) {
    [tmpPrefs setObject:@"0" forKey:@"DynamicColors"];
  }
  if ([tmpPrefs objectForKey:@"DisableBackground"] == nil) {
    [tmpPrefs setObject:@"0" forKey:@"DisableBackground"];
  }
  if ([tmpPrefs objectForKey:@"HideTime"] == nil) {
    [tmpPrefs setObject:@"0" forKey:@"HideTime"];
  }
  if ([tmpPrefs objectForKey:@"AnimationDuration"] == nil) {
    [tmpPrefs setObject:@"0.25" forKey:@"AnimationDuration"];
  }
  if ([tmpPrefs objectForKey:@"StickyDuration"] == nil) {
    [tmpPrefs setObject:@"1.0" forKey:@"StickyDuration"];
  }

  preferences = [tmpPrefs copy];
}

- (void)initializeWindow{
  // Setup window
  CGRect mainFrame = UIApplication.sharedApplication.statusBar.bounds;//[UIApplication sharedApplication].keyWindow.frame;
  mainFrame.origin.x = 0;
  mainFrame.origin.y = -20;
  mainFrame.size.height = 20;
  sVolWindow = [[svolWindow alloc] initWithFrame:mainFrame];
  if ([sVolWindow respondsToSelector:@selector(_setSecure:)]) {
    [sVolWindow _setSecure:YES];
  }
  sVolWindow.windowLevel = 10580;

  mainFrame.origin.y = 0;

  // Main view controller
  primaryVC = [[UIViewController alloc] init];
  [primaryVC.view setAutoresizingMask:UIViewAutoresizingFlexibleWidth];

  // Blur view
  if ([%c(UIBlurEffect) class]) {
    UIBlurEffect *blurEffect = [%c(UIBlurEffect) effectWithStyle:UIBlurEffectStyleDark];
    blurView = [[%c(UIVisualEffectView) alloc] initWithEffect:blurEffect];
    [blurView setFrame:mainFrame];
    [blurView setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
    [primaryVC.view addSubview:blurView];
  } else {
    back=[[%c(_UIBackdropView) alloc] initWithStyle:1];
    [back setAutosizesToFitSuperview:NO];
    [back setFrame:mainFrame];
    [back setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
    [primaryVC.view addSubview:back];
  }

  // Label
  indicatorLabel = [[UILabel alloc] initWithFrame:mainFrame];
  [indicatorLabel setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
  [indicatorLabel setTextColor:[UIColor whiteColor]];
  [indicatorLabel setTextAlignment:NSTextAlignmentCenter];

  UIFont *labelFont = [UIFont fontWithName:@"Helvetica Neue" size:12];
  [indicatorLabel setFont:labelFont];

  [primaryVC.view addSubview:indicatorLabel];

  // Make visible and hide window
  sVolWindow.rootViewController=primaryVC;
  [sVolWindow makeKeyAndVisible];
  [sVolWindow setHidden:YES];
}

- (CGRect)getScreenBoundsForOrientation:(int)orientation {
  UIScreen *mainScreen = [UIScreen mainScreen];
  if ([mainScreen respondsToSelector:@selector(_boundsForInterfaceOrientation:)]) {
    return [mainScreen _boundsForInterfaceOrientation:orientation];
  }

  if (orientation != 3 && orientation != 4) return mainScreen.bounds;

  return CGRectMake(mainScreen.bounds.origin.x,
                    mainScreen.bounds.origin.y,
                    mainScreen.bounds.size.height,
                    mainScreen.bounds.size.width);
}


- (void)_updateSvolLabel:(int)level type:(int)type{
  BOOL isLockScreenVisible = NO;
  SBLockScreenManager *manager = [%c(SBLockScreenManager) sharedInstanceIfExists];
  if (manager != nil) {
    SBLockScreenViewController *lockScreenViewController = (SBLockScreenViewController *)[manager lockScreenViewController];
    if ([lockScreenViewController respondsToSelector:@selector(isLockScreenVisible)]) {
      isLockScreenVisible = [lockScreenViewController isLockScreenVisible];
    } else if ([manager respondsToSelector:@selector(isLockScreenVisible)]) {
      isLockScreenVisible = [manager isLockScreenVisible];
    }
  }

  NSMutableString *timeString = [[NSMutableString alloc] init];

  // Are we dynamic?
  int dynColor=-1;
  if ([[preferences objectForKey:@"DynamicColors"] intValue] == 1 && !isLockScreenVisible) {
    SpringBoard *SB=(SpringBoard *)[UIApplication sharedApplication];
    SBApplication *SBA=(SBApplication *)[SB _accessibilityFrontMostApplication];

    // Are we in SpringBoard?
    if (SBA == nil) {
      UIStatusBar *springStatus = [SB statusBar];
      UIStatusBarForegroundView *springForeground = MSHookIvar<UIStatusBarForegroundView *>(springStatus,"_foregroundView");
      UIStatusBarForegroundStyleAttributes *springForegroundStyle=[springForeground foregroundStyle];
      UIColor *sColor=[springForegroundStyle tintColor];

      CGFloat white;
      [sColor getWhite:&white alpha:nil];

      if (white > 0.5) {
        dynColor=0;
      } else {
        dynColor=1;
      }
    } else {
      // Is the StatusBar hidden?
      if (([SBA respondsToSelector:@selector(statusBarHiddenForCurrentOrientation)] && [SBA statusBarHiddenForCurrentOrientation]) || IsCurrentAppStatusBarHidden) {
        // Build our snapshot path
        NSArray *brightnessArray=[cachedBrightness objectForKey:[SBA bundleIdentifier]];
        double thePast = [[NSDate date] timeIntervalSince1970];
        double mostRecent = [(NSDate *)[brightnessArray objectAtIndex:1] timeIntervalSince1970];
        // Do we have a cached brightness?
        if (brightnessArray != nil && [brightnessArray count] > 1 && (thePast - mostRecent) < 60*5) {
          float dynamicColorsBrightness = [[brightnessArray objectAtIndex:0] floatValue];
          if (dynamicColorsBrightness > 0.5) {
            dynColor = 1;
          } else {
            dynColor = 0;
          }
        } else { // No cached brightness
          // Figure out brightness of top 40 lines of screenshot
          NSFileManager *fileManager = [[NSFileManager alloc] init];
          NSString *snapshotPath;
          if ([SBA respondsToSelector:@selector(_baseAppSnapshotPath)]) {
            snapshotPath = [SBA _baseAppSnapshotPath];
          } else if ([SBA respondsToSelector:@selector(_snapshotManifest)]) {
            snapshotPath = [[SBA _snapshotManifest] containerPath];
          }

          NSURL *newestURL;
          if (snapshotPath != nil) {
            NSString *path = [NSString stringWithFormat:@"%@/%@", snapshotPath, [SBA bundleIdentifier]];
            NSURL *directoryURL = [NSURL URLWithString:path];
            NSArray *keys = [NSArray arrayWithObjects:NSURLAttributeModificationDateKey,
                                                      NSURLIsRegularFileKey,
                                                      nil];

            // Find newest screenshot
            NSDirectoryEnumerator *screenshotEnum = [fileManager enumeratorAtURL:directoryURL
                                                      includingPropertiesForKeys:keys
                                                                         options:0
                                                                    errorHandler:nil];
            NSDate *newestDate;
            for (NSURL *url in screenshotEnum) {
              NSError *err;
              NSDate *fileDate = nil;
              NSNumber *isFile = nil;
              [url getResourceValue:&fileDate forKey:NSURLAttributeModificationDateKey error:&err];
              [url getResourceValue:&isFile forKey:NSURLIsRegularFileKey error:&err];

              if (newestDate == nil || [newestDate compare:fileDate] == NSOrderedAscending) {
                if (isFile != nil && [isFile integerValue] == 1) {
                  newestDate=fileDate;
                  newestURL=url;
                }
              }
            }
          }

          if (newestURL != nil) {
            // Load screenshot
            CGImageRef theImage = [[UIImage imageWithData:[NSData dataWithContentsOfURL:newestURL]] CGImage];
            CFDataRef pixelData = CGDataProviderCopyData(CGImageGetDataProvider(theImage));
            const UInt8 *pData = CFDataGetBytePtr(pixelData);
            int pWidth = CGImageGetWidth(theImage);

            int samples = 0;
            float brightness = 0.0;
            for (int y = 0; y < 40; y++) {
              for (int x = 0; x < pWidth; x++) {
                samples++;
                CGPoint point = CGPointMake(x,y);
                  int pixelInfo = ((pWidth * point.y) + point.x) * 4; // The image is png
                  brightness += (pData[pixelInfo] / 255.0) * 0.3 +
                                (pData[(pixelInfo + 1)] / 255.0) * 0.59 +
                                (pData[(pixelInfo + 2)] / 255.0) * 0.11;
              }
            }

            // Cache brightness
            float dynamicColorsBrightness = brightness/samples;
            NSNumber *newBrightness = [NSNumber numberWithFloat:dynamicColorsBrightness];
            NSDate *currentDate = [NSDate date];
            [cachedBrightness setObject:[NSArray arrayWithObjects:newBrightness, currentDate, nil]
                                 forKey:[SBA bundleIdentifier]];

            if (dynamicColorsBrightness > 0.5) {
              dynColor = 1;
            } else {
              dynColor = 0;
            }
          }
        }
      } else { // Status bar not hidden
        // Pull the statusbar's style
        int style = 0;
        if ([SBA respondsToSelector:@selector(effectiveStatusBarStyleRequest)]) {
          style = [[SBA effectiveStatusBarStyleRequest] style];
        } else if ([SBA respondsToSelector:@selector(info)]) {
          style = SBA.info.defaultStatusBarStyle;
        }
        if (style == 0 || style == 300) {
          dynColor = 1;
        } else {
          dynColor = 0;
        }
      }
    }
  }

  // Not dynamic color
  bool colorChoice = [[preferences objectForKey:@"InvertColors"] intValue];
  if (dynColor > -1) {
    // IN: 1 white, 0 black
    // DYN: 1 white, 0 black
    colorChoice = dynColor;
    if ([[preferences objectForKey:@"InvertColors"] intValue] == 1) {
      colorChoice = !colorChoice;
    }
  }

  if (colorChoice) {
    //[[SBApplicationController sharedInstance] applicationWithDisplayIdentifier:@"com.apple.springboard"];
    //[[[UIApplication sharedApplication] keyWindow] _statusBarControllingWindow]
    [indicatorLabel setTextColor:[UIColor blackColor]];

    if ([%c(UIBlurEffect) class]) { // iOS8
      UIBlurEffect *blurEffect = [%c(UIBlurEffect) effectWithStyle:UIBlurEffectStyleExtraLight];
      [blurView _setEffect:blurEffect];
    } else { // iOS7
      [back removeFromSuperview];
      back=[[%c(_UIBackdropView) alloc] initWithStyle:0];
      [back setAutosizesToFitSuperview:NO];
      [back setFrame:sVolWindow.frame];
      [back setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
      [primaryVC.view insertSubview:back atIndex:0];
    }
  } else {
    [indicatorLabel setTextColor:[UIColor whiteColor]];

    if ([%c(UIBlurEffect) class]) { // iOS8
      UIBlurEffect *blurEffect=[%c(UIBlurEffect) effectWithStyle:UIBlurEffectStyleDark];
      [blurView _setEffect:blurEffect];
    }else{ // iOS7
      [back removeFromSuperview];
      back=[[%c(_UIBackdropView) alloc] initWithStyle:1];
      [back setAutosizesToFitSuperview:NO];
      [back setFrame:sVolWindow.frame];
      [back setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
      [primaryVC.view insertSubview:back atIndex:0];
    }
  }

  if ([[preferences objectForKey:@"DisableBackground"] intValue] == 1) {
    [back setAlpha:0.0];
    [blurView setAlpha:0.0];
  } else {
    [back setAlpha:1.0];
    [blurView setAlpha:1.0];
  }

  if ([[preferences objectForKey:@"HideTime"] intValue] == 1) {
    SBMainStatusBarStateProvider *statusBarStateProvider = [%c(SBMainStatusBarStateProvider) sharedInstance];
    [statusBarStateProvider enableTime:NO crossfade:NO crossfadeDuration:0];
    [statusBarStateProvider setTimeCloaked:YES];
  }

  // Silent switch
  if (level == 17) {
    [timeString appendString:@"S i l e n t"];
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate); // Temporary silent vibrate fix
  } else {
    // Get the proper system volume when leaving silent mode - doesn't work if "change with buttons" not set
    if (level == 18) {
      level = [[%c(VolumeControl) sharedVolumeControl] volume]*16;
    }

    // Icons for system vs media volume - if enabled
    if ([[preferences objectForKey:@"HideIcons"] intValue] == 0) {
      if (type == 0) {
        [timeString appendString:@"♫  "];
      }else{
        [timeString appendString:@"☎︎  "];
      }
    }

    // Make level into string - circles or squares?
    for (int i = 0; i < level; i++) {
      if ([[preferences objectForKey:@"UseSquares"] intValue]==0) {
        [timeString appendString:@"⚫︎"];
      } else {
        [timeString appendString:@"◾︎"];//@"■"];
      }
    }

    for (int i = 0; i < 16 - level; i++) {
      if ([[preferences objectForKey:@"UseSquares"] intValue] == 0) {
        [timeString appendString:@"⚪︎"];
      } else {
        [timeString appendString:@"◽︎"];//@"□"];
      }
    }
  }

  // Fix kerning with circles
  NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:timeString];
  if ([[preferences objectForKey:@"UseSquares"] intValue]==0) {
    [attributedString addAttribute:NSKernAttributeName value:[NSNumber numberWithFloat:-2.0]
                                                       range:NSMakeRange(0, [timeString length])];
  }
  [indicatorLabel setAttributedText:attributedString];

  // Manually rotate sVolWindow
  long orientation = (long)[(SpringBoard *)[UIApplication sharedApplication] _frontMostAppOrientation];
  [sVolWindow _rotateWindowToOrientation:orientation
                         updateStatusBar:NO
                                duration:0
                           skipCallbacks:YES];

  CGRect windowRect = sVolWindow.frame;
  CGRect mainScreenRect = [self getScreenBoundsForOrientation:orientation];
  windowRect = CGRectMake(0, 0, CGRectGetWidth(mainScreenRect), 20);
  [sVolWindow setFrame:windowRect];

  // Show and set hide timer
  if (!sVolIsVisible || isAnimatingClose) {
    // Window adjustments
    if (!isAnimatingClose) {
      [sVolWindow fixSvolWindow];
      sVolIsVisible = YES;
      [sVolWindow setHidden:NO];
    } else {
      svolCloseInterrupt = YES;
    }

    // Animate entry
    [UIView animateWithDuration:[[preferences objectForKey:@"AnimationDuration"] floatValue]
                          delay:nil
                        options:(UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction)
                     animations:^{

        CGRect windowRect=sVolWindow.frame;
        windowRect.origin.y = 0;
        [sVolWindow setFrame:windowRect];
      } completion:^(BOOL finished) {
        // Reset the timer
        svolCloseInterrupt = NO;
        if (hideTimer != nil) {
          [hideTimer invalidate];
          hideTimer = nil;
        }
        hideTimer = [NSTimer scheduledTimerWithTimeInterval:[[preferences objectForKey:@"StickyDuration"] floatValue]
                                                     target:self
                                                   selector:@selector(hideSvolWindow)
                                                   userInfo:nil
                                                    repeats:NO];
      }];
  } else {
    // Reset the timer
    if (hideTimer != nil) {
      [hideTimer invalidate];
      hideTimer = nil;
    }
    hideTimer = [NSTimer scheduledTimerWithTimeInterval:[[preferences objectForKey:@"StickyDuration"] floatValue]
                                                 target:self
                                               selector:@selector(hideSvolWindow)
                                               userInfo:nil
                                                repeats:NO];
  }
}

- (void)hideSvolWindow{
  // Unset hide timer
  hideTimer=nil;

  // Animate hide
  [UIView animateWithDuration:[[preferences objectForKey:@"AnimationDuration"] floatValue]
                        delay:0
                      options:(UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction)
                   animations:^{

      isAnimatingClose = YES;
      CGRect windowRect = sVolWindow.frame;
      windowRect.origin.y = -20;
      [sVolWindow setFrame:windowRect];
    } completion:^(BOOL finished) {
      // Hide the window
      isAnimatingClose = NO;

      if (finished && !svolCloseInterrupt) {
        sVolIsVisible = NO;
        [sVolWindow setHidden:YES];

        if ([[preferences objectForKey:@"HideTime"] intValue] == 1) {
          SBMainStatusBarStateProvider *statusBarStateProvider = [%c(SBMainStatusBarStateProvider) sharedInstance];
          [statusBarStateProvider enableTime:YES crossfade:NO crossfadeDuration:0];
          [statusBarStateProvider setTimeCloaked:NO];
        }
      }
    }];
}
@end

// Force hide silent switch HUD - would prefer a better solution here
%hook SBRingerHUDController
+ (void)activate:(int)arg1 {
  [svol _updateSvolLabel:17+arg1 type:1];
}
%end

// Hook volume change events
%hook VolumeControl
- (void)_changeVolumeBy:(float)arg1 {
  %orig;

  int theMode = MSHookIvar<int>(self,"_mode");
  if (theMode == 0) {
    [svol _updateSvolLabel:[self getMediaVolume]*16 type:0];
  } else {
    [svol _updateSvolLabel:[self volume]*16 type:1];
  }
}

// Force HUDs hidden
- (_Bool)_HUDIsDisplayableForCategory:(id)arg1 {
  return NO;
}

- (_Bool)_isCategoryAlwaysHidden:(id)arg1 {
  return YES;
}
%end

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)arg1{
  %orig;
  // Create StatusVol inside SpringBoard
  svol = [[StatusVol alloc] init];
}
%end

static void PreferencesChanged(CFNotificationCenterRef center,
                               void *observer,
                               CFStringRef name,
                               const void *object,
                               CFDictionaryRef userInfo)
{
  if (svol != nil) {
    [svol loadPreferences];
  }
}

static void SetCurrentAppStatusBarHidden() {
  IsCurrentAppStatusBarHidden = true;
}

static void SetCurrentAppStatusBarVisible() {
  IsCurrentAppStatusBarHidden = false;
}


%ctor{
  CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                  NULL,
                                  PreferencesChanged,
                                  CFSTR("com.chewmieser.statusvollite.prefs-changed"),
                                  NULL,
                                  CFNotificationSuspensionBehaviorDeliverImmediately);

  CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    (CFNotificationCallback)SetCurrentAppStatusBarHidden,
                                    CFSTR("com.fidele007.statusvollite/SetStatusBarHidden"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
  CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    (CFNotificationCallback)SetCurrentAppStatusBarVisible,
                                    CFSTR("com.fidele007.statusvollite/SetStatusBarVisible"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

  if (access("/var/lib/dpkg/info/com.chewmieser.statusvollite.list",F_OK) == -1) {
    NSLog(@"[StatusVol 2] This package came from an unofficial repo. Please re-download from http://apt.steverolfe.com.");
  }
}