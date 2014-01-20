/*==============================================================================
Copyright (c) 2010-2011 QUALCOMM Austria Research Center GmbH .
All Rights Reserved.
Qualcomm Confidential and Proprietary
==============================================================================*/


#import <UIKit/UIKit.h>
#import "EAGLView.h"

@class ARViewController;

@interface VirtualButtonsAppDelegate : NSObject <UIApplicationDelegate> {
    UIWindow *window;
    ARViewController *viewController;
    EAGLView* view;
	//MoviePlayerViewController *movieController;
}

@end
