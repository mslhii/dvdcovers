/*==============================================================================
Copyright (c) 2010-2011 QUALCOMM Austria Research Center GmbH .
All Rights Reserved.
Qualcomm Confidential and Proprietary
==============================================================================*/


#import "ARViewController.h"


@implementation ARViewController


// Allow the application to start only in landscape right orientation
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return UIInterfaceOrientationLandscapeRight == interfaceOrientation;
}
 
@end
