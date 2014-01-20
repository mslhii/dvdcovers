/*==============================================================================
Copyright (c) 2010-2011 QUALCOMM Austria Research Center GmbH .
All Rights Reserved.
Qualcomm Confidential and Proprietary
==============================================================================*/


#import "VirtualButtonsAppDelegate.h"
#import "ARViewController.h"

@implementation VirtualButtonsAppDelegate

/****************** OVERLAY VERSION 1 *******************/

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	BOOL ret = YES;
	CGRect screenBounds = [[UIScreen mainScreen] bounds];
	
	window = [[UIWindow alloc] initWithFrame: screenBounds];
	viewController = [[ARViewController alloc] init];
	UIView* parentV = [[UIView alloc] initWithFrame: screenBounds];
	
	screenBounds = CGRectMake(0, 0, parentV.frame.size.height, parentV.frame.size.width);
	view = [[EAGLView alloc] initWithFrame: screenBounds];
	[parentV addSubview:view];
	
	CGRect subScreenBounds = CGRectMake(0, 0, 200, 200);
	UIView* videoV = [[UIView alloc] initWithFrame:subScreenBounds];
	[parentV addSubview:videoV];
	
	[viewController setView: parentV];
	
	[window addSubview: viewController.view];
	[window makeKeyAndVisible];
	
	if (YES == ret) {
		[view onCreate];
	}
	
	return ret;
}

/*************************************************/


/************** OLD VERSION *******************
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{	
    BOOL ret = YES;
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    
    window = [[UIWindow alloc] initWithFrame: screenBounds];
    view = [[EAGLView alloc] initWithFrame: screenBounds];
    viewController = [[ARViewController alloc] init];
    [viewController setView:view];
    
    [window addSubview: viewController.view];
    [window makeKeyAndVisible];
    
    if (YES == ret) {
        [view onCreate];
    }

    return ret;
}
/*******************************************/

- (void)applicationWillResignActive:(UIApplication *)application
{
    // AR-specific actions
    [view onPause];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // AR-specific actions
    [view onResume];
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // AR-specific actions
    [view onDestroy];
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Handle any background procedures not related to animation here.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Handle any foreground procedures not related to animation here.
}

- (void)dealloc
{
    [view release];
    [viewController release];
    [window release];
    
    [super dealloc];
}

@end
