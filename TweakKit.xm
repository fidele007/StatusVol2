@interface _UILegibilityLabel : UIView
	- (id)initWithSettings:(id)arg1 strength:(float)arg2 string:(id)arg3 font:(id)arg4;
@end

@interface _UILegibilitySettings : NSObject
	- (id)initWithContentColor:(id)arg1 contrast:(float)arg2;
	- (id)initWithStyle:(int)arg1 primaryColor:(id)arg2 secondaryColor:(id)arg3 shadowColor:(id)arg4;
	+ (id)sharedInstanceForStyle:(int)arg1;
	- (void)setSecondaryColor:(id)arg1;
	- (void)setPrimaryColor:(id)arg1;
@end

@interface UIApplication (SVLUIApplication)
- (long long)_frontMostAppOrientation;
- (bool)_isStatusBarHiddenForOrientation:(long long)arg1;
@end

%hook _UILegibilityLabel
	- (id)initWithSettings:(id)arg1 strength:(float)arg2 string:(id)arg3 font:(id)arg4{
		id tmp=%orig;

		//_UILegibilitySettings *legSet=arg1;

		NSLog(@"!---- leg: %@ %@ %@ %f",arg1,tmp,arg3,arg2);
		return tmp;
	}

	- (id)initWithSettings:(id)arg1 strength:(float)arg2 string:(id)arg3 font:(id)arg4 options:(int)arg5{
		id tmp=%orig;

		//_UILegibilitySettings *legSet=arg1;

		NSLog(@"!---- OPT: %@ %@ %@ %f %d",arg1,tmp,arg3,arg2,arg5);
		return tmp;
	}
%end

%hook _UILegibilityView
	- (void)updateForChangedSettings:(id)arg1{
		%orig;
		NSLog(@"!--- UCS %@",arg1);
	}
%end

/*%hook _UILegibilitySettings
	+ (id)sharedInstanceForStyle:(int)arg1{
		NSLog(@"!-- Style requsted: %d",arg1);
		return %orig;
	}
%end*/

static void SendAppStatusBarVisibility(bool hidden) {
  if (hidden) {
    notify_post("com.fidele007.statusvollite/SetStatusBarHidden");
  } else {
    notify_post("com.fidele007.statusvollite/SetStatusBarVisible");
  }
}

%hook UIApplication
- (bool)_isStatusBarHiddenForOrientation:(long long)arg1 {
  SendAppStatusBarVisibility(%orig);
  return %orig;
}
- (void)_setStatusBarHidden:(bool)arg1 animationParameters:(id)arg2 changeApplicationFlag:(bool)arg3 {
  %orig;
  SendAppStatusBarVisibility(arg1);
}
- (void)setStatusBarHidden:(bool)arg1 {
  %orig;
  SendAppStatusBarVisibility(arg1);
}
- (void)setStatusBarHidden:(bool)arg1 animated:(bool)arg2 {
  %orig;
  SendAppStatusBarVisibility(arg1);
}
- (void)setStatusBarHidden:(bool)arg1 animationParameters:(id)arg2 {
  %orig;
  SendAppStatusBarVisibility(arg1);
}
- (void)setStatusBarHidden:(bool)arg1 animationParameters:(id)arg2 changeApplicationFlag:(bool)arg3 {
  %orig;
  SendAppStatusBarVisibility(arg1);
}
- (void)setStatusBarHidden:(bool)arg1 duration:(double)arg2 {
  %orig;
  SendAppStatusBarVisibility(arg1);
}
- (void)setStatusBarHidden:(bool)arg1 duration:(double)arg2 changeApplicationFlag:(bool)arg3 {
  %orig;
  SendAppStatusBarVisibility(arg1);
}
- (void)setStatusBarHidden:(bool)arg1 withAnimation:(long long)arg2 {
  %orig;
  SendAppStatusBarVisibility(arg1);
}
- (void)applicationDidBecomeActive:(UIApplication *)arg1 {
  %orig;
  SendAppStatusBarVisibility([self _isStatusBarHiddenForOrientation:[self _frontMostAppOrientation]]);
}
%end