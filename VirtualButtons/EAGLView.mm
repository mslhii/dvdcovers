/*==============================================================================
Copyright (c) 2010-2011 QUALCOMM Austria Research Center GmbH .
All Rights Reserved.
Qualcomm Confidential and Proprietary
==============================================================================*/


#import <QuartzCore/QuartzCore.h>
#import "EAGLView.h"
#import <QCAR/QCAR.h>
#import <QCAR/CameraDevice.h>
#import <QCAR/Tracker.h>
#import "Texture.h"
#import "Teapot.h"
#import <QCAR/VideoBackgroundConfig.h>
#import <QCAR/Renderer.h>
#import <QCAR/Tool.h>
#import <QCAR/Trackable.h>
#import <QCAR/ImageTarget.h>
#import <QCAR/Rectangle.h>
#import <QCAR/VirtualButton.h>
#import <QCAR/UpdateCallback.h>

#import <MediaPlayer/MediaPlayer.h>
#import "Reachability.h"

#ifndef USE_OPENGL1
#import "ShaderUtils.h"
#define MAKESTRING(x) #x
#import "Shaders/CubeShader.fsh"
#import "Shaders/CubeShader.vsh"
#import "Shaders/LineShader.fsh"
#import "Shaders/LineShader.vsh"
#endif


namespace {
    enum tagButtons {
        BUTTON_1 = 1,
        BUTTON_2 = 1 << 1,
        BUTTON_3 = 1 << 2,
        BUTTON_4 = 1 << 3,
        NUM_BUTTONS = 4
    };
    
    // Virtual button mask
    int buttonMask = 0;
    
    // Model scale factor
    const float kObjectScale = 3.0f;
        
    // Teapot texture filenames
    const char* textureFilenames[] = {
        "TextureTeapotBrass.png",
        "TextureTeapotRed.png",
        "TextureTeapotBlue.png",
        "TextureTeapotYellow.png",
        "TextureTeapotGreen.png"
    };
    
    // Menu entries
    const char* menuEntries[] = {
        "Toggle red virtual button",
        "Toggle blue virtual button",
        "Toggle yellow virtual button",
        "Toggle green virtual button",
        "Camera torch on",
        "Camera torch off",
        "Autofocus on",
        "Autofocus off",
		"Stop video playback"
    };
    
    class VirtualButton_UpdateCallback : public QCAR::UpdateCallback {
        virtual void QCAR_onUpdate(QCAR::State& state);
    } qcarUpdate;
}


@interface EAGLView (PrivateMethods)
- (void)setFramebuffer;
- (BOOL)presentFramebuffer;
- (void)createFramebuffer;
- (void)deleteFramebuffer;
- (int)loadTextures;
- (void)updateApplicationStatus:(status)newStatus;
- (void)bumpAppStatus;
- (void)initApplication;
- (void)initQCAR;
- (void)initApplicationAR;
- (void)loadTracker;
- (void)startCamera;
- (void)stopCamera;
- (void)configureVideoBackground;
- (void)initRendering;
@end


@implementation EAGLView

// Global variables
bool isPlaying = 0;
int tIdx = -1;
unsigned int screenWidth = 0;
unsigned int screenHeight = 0;
int trackingNumber = 0;

// Trackable info class
int numActiveTrackables = 0;

class ActiveTrackableInfo
{
public:
	int tI;
	float pixelsCoord[4];	
};

ActiveTrackableInfo trackableInfo[10];

// You must implement this method
+ (Class)layerClass
{
    return [CAEAGLLayer class];
}


- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
	if (self) {
        CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
        
        eaglLayer.opaque = TRUE;
        eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithBool:FALSE], kEAGLDrawablePropertyRetainedBacking,
                                        kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat,
                                        nil];
        
#ifdef USE_OPENGL1
        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
        ARData.QCARFlags = QCAR::GL_11;
#else
        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        ARData.QCARFlags = QCAR::GL_20;
#endif
        
        NSLog(@"QCAR OpenGL flag: %d", ARData.QCARFlags);
        
        if (!context) {
            NSLog(@"Failed to create ES context");
        }
    }
    
    return self;
}

- (void)dealloc
{
    [self deleteFramebuffer];
    
    // Tear down context
    if ([EAGLContext currentContext] == context) {
        [EAGLContext setCurrentContext:nil];
    }
    
    [context release];
    [super dealloc];
}

- (void)createFramebuffer
{
#ifdef USE_OPENGL1
    if (context && !defaultFramebuffer) {
        [EAGLContext setCurrentContext:context];
        
        // Create default framebuffer object
        glGenFramebuffersOES(1, &defaultFramebuffer);
        glBindFramebufferOES(GL_FRAMEBUFFER_OES, defaultFramebuffer);
        
        // Create colour renderbuffer and allocate backing store
        glGenRenderbuffersOES(1, &colorRenderbuffer);
        glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
        
        // Allocate the renderbuffer's storage (shared with the drawable object)
        [context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:(CAEAGLLayer*)self.layer];
        glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &framebufferWidth);
        glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &framebufferHeight);
        
        // Create the depth render buffer and allocate storage
        glGenRenderbuffersOES(1, &depthRenderbuffer);
        glBindRenderbufferOES(GL_RENDERBUFFER_OES, depthRenderbuffer);
        glRenderbufferStorageOES(GL_RENDERBUFFER_OES, GL_DEPTH_COMPONENT16_OES, framebufferWidth, framebufferHeight);
        
        // Attach colour and depth render buffers to the frame buffer
        glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, colorRenderbuffer);
        glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_DEPTH_ATTACHMENT_OES, GL_RENDERBUFFER_OES, depthRenderbuffer);
        
        // Leave the colour render buffer bound so future rendering operations will act on it
        glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
    }
#else
    if (context && !defaultFramebuffer) {
        [EAGLContext setCurrentContext:context];
        
        // Create default framebuffer object
        glGenFramebuffers(1, &defaultFramebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
        
        // Create colour render buffer and allocate backing store
        glGenRenderbuffers(1, &colorRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);

        // Allocate the renderbuffer's storage (shared with the drawable object)
        [context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &framebufferWidth);
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &framebufferHeight);
        
        // Create the depth render buffer and allocate storage
        glGenRenderbuffers(1, &depthRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, depthRenderbuffer);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, framebufferWidth, framebufferHeight);
        
        // Attach colour and depth render buffers to the frame buffer
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorRenderbuffer);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer);
        
        // Leave the colour render buffer bound so future rendering operations will act on it
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
        
        if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
            NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
        }
    }
#endif
}

- (void)deleteFramebuffer
{
    if (context) {
        [EAGLContext setCurrentContext:context];
        
#ifdef USE_OPENGL1
        if (defaultFramebuffer) {
            glDeleteFramebuffersOES(1, &defaultFramebuffer);
            defaultFramebuffer = 0;
        }
        
        if (colorRenderbuffer) {
            glDeleteRenderbuffersOES(1, &colorRenderbuffer);
            colorRenderbuffer = 0;
        }
        
        if (depthRenderbuffer) {
            glDeleteRenderbuffersOES(1, &depthRenderbuffer);
            depthRenderbuffer = 0;
        }
#else
        if (defaultFramebuffer) {
            glDeleteFramebuffers(1, &defaultFramebuffer);
            defaultFramebuffer = 0;
        }
        
        if (colorRenderbuffer) {
            glDeleteRenderbuffers(1, &colorRenderbuffer);
            colorRenderbuffer = 0;
        }
        
        if (depthRenderbuffer) {
            glDeleteRenderbuffers(1, &depthRenderbuffer);
            depthRenderbuffer = 0;
        }
#endif
    }
}

- (void)setFramebuffer
{
    if (context) {
        [EAGLContext setCurrentContext:context];
        
        if (!defaultFramebuffer) {
            // Perform on the main thread to ensure safe memory allocation for
            // the shared buffer.  Block until the operation is complete to
            // prevent simultaneous access to the OpenGL context
            [self performSelectorOnMainThread:@selector(createFramebuffer) withObject:self waitUntilDone:YES];
        }
        
#ifdef USE_OPENGL1
        glBindFramebufferOES(GL_FRAMEBUFFER_OES, defaultFramebuffer);
#else
        glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
#endif
    }
}

- (BOOL)presentFramebuffer
{
    BOOL success = FALSE;
    
    if (context) {
        [EAGLContext setCurrentContext:context];
        
#ifdef USE_OPENGL1
        glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
#else
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
#endif
        
        success = [context presentRenderbuffer:GL_RENDERBUFFER];
    }
    
    return success;
}

- (void)layoutSubviews
{
    // The framebuffer will be re-created at the beginning of the next
    // setFramebuffer method call.
    [self deleteFramebuffer];
}


// User touched the screen
- (void) touchesBegan: (NSSet*) touches withEvent: (UIEvent*) event
{
    UITouch* touch = [touches anyObject];
	
	// Pass coordinates to see if user tapped in rectangle
    CGPoint location = [touch locationInView:self];
	//int xcoord = location.x;
	//int ycoord = location.y;
	    
	if(isPlaying == 0)
	{
		/********* Xingwei's modified code ************/
		if( numActiveTrackables > 0 )
		{
			float xx;
			QCAR::CameraDevice& cameraDevice = QCAR::CameraDevice::getInstance();
			QCAR::VideoMode videoMode = cameraDevice.getVideoMode(QCAR::CameraDevice::MODE_DEFAULT);
			xx=((float)videoMode.mHeight*screenWidth/videoMode.mWidth-screenHeight)/2.0f;
			QCAR::State state = QCAR::Renderer::getInstance().begin();
			const QCAR::Trackable* trackable;
			
			/*********** FIRST TEST **************
			for( int i = 0; i < numActiveTrackables ; i ++ )
			{
				if( ( xcoord >= trackableInfo[ i ].pixelsCoord[0] && xcoord <= trackableInfo[ i ].pixelsCoord[2] )||
				   ( xcoord >= trackableInfo[ i ].pixelsCoord[2] && xcoord <= trackableInfo[ i ].pixelsCoord[0] ) )
					if( ( ycoord >= ( trackableInfo[ i ].pixelsCoord[1] - xx )&& ycoord <= (trackableInfo[ i ].pixelsCoord[3]-xx) )||
					   ( ycoord >= ( trackableInfo[ i ].pixelsCoord[3] - xx )&& ycoord <= (trackableInfo[ i ].pixelsCoord[1]-xx) ) )
						tIdx = trackableInfo[ i ].tI;
			}
			 /*************************************/
			
			/************* SECOND TEST ***************/
			for( int i = 0; i < numActiveTrackables ; i ++ )
			{
				trackable = state.getActiveTrackable(i);
				float xstuff = trackableInfo[ i ].pixelsCoord[2] - trackableInfo[ i ].pixelsCoord[0];
				float ystuff = trackableInfo[ i ].pixelsCoord[3] - trackableInfo[ i ].pixelsCoord[1];
				
				//float xstuff = trackableInfo[ i ].pixelsCoord[2] - trackableInfo[ i ].pixelsCoord[0];
				//float ystuff = (trackableInfo[ i ].pixelsCoord[3] - xx) - (trackableInfo[ i ].pixelsCoord[1] - xx);
				
				if( CGRectContainsPoint(CGRectMake(trackableInfo[ i ].pixelsCoord[0], trackableInfo[ i ].pixelsCoord[1], xstuff, ystuff), location) )
				{
					tIdx = trackableInfo[ i ].tI;
					if((!strcmp(trackable->getName(), "numberfour")))
					{
						trackingNumber = 1;
					}
					else if((!strcmp(trackable->getName(), "hp72")))
					{
						trackingNumber = 2;
					}
					else if((!strcmp(trackable->getName(), "hangover")))
					{
						trackingNumber = 3;
					}					
					else if((!strcmp(trackable->getName(), "ironman2")))
					{
						trackingNumber = 4;
					}	
				}
				
				//CGRectContainsPoint(CGRectMake(<#CGFloat x#>, <#CGFloat y#>, <#CGFloat width#>, <#CGFloat height#>), <#CGPoint point#>)
			}
			/*****************************************/
		}
		else
		{
			tIdx = -1;
		}
		/*****************************/
	}
	
	// Comparison check using tIdx
    if (1 == [touch tapCount]) {
		if(tIdx == -1)
		{
			// Show virtual button toggle and camera control action sheet
			UIActionSheet* actionSheet = [[UIActionSheet alloc] initWithTitle:nil
																	 delegate:self
															cancelButtonTitle:@"Cancel"
													   destructiveButtonTitle:nil
															otherButtonTitles:
										  [NSString stringWithCString:menuEntries[4] encoding:NSASCIIStringEncoding],
										  [NSString stringWithCString:menuEntries[5] encoding:NSASCIIStringEncoding],
										  [NSString stringWithCString:menuEntries[6] encoding:NSASCIIStringEncoding],
										  [NSString stringWithCString:menuEntries[7] encoding:NSASCIIStringEncoding],
										  //[NSString stringWithCString:menuEntries[8] encoding:NSASCIIStringEncoding],
										  nil];
			
			[actionSheet showInView:self];
			[actionSheet release];
		}
		else if(tIdx == 100)
		{
			// Stop video playback
		}
		else
		{
			// Check for internet first to handle exceptions
			if([self reachable])
			{
				[self performSelectorOnMainThread:@selector(trackedSuccess) withObject:nil waitUntilDone:NO];
				// Begin playing video
				[self performSelectorOnMainThread:@selector(playVideo) withObject:nil waitUntilDone:NO];
			}
			else
			{
				// Not reachable
				[self performSelectorOnMainThread:@selector(internetFailure) withObject:nil waitUntilDone:NO];
			}
		}
		
    }
}

// Method for checking internet settings
- (BOOL)reachable
{
	Reachability *r = [Reachability reachabilityWithHostName:@"google.com"];
	NetworkStatus internetStatus = [r currentReachabilityStatus];
	if(internetStatus == NotReachable)
	{
		return NO;
	}
	return YES;
}

// Custom UI for internet failure
-(void)internetFailure
{
	UIAlertView *test = [[UIAlertView alloc] initWithTitle:@"Cannot Play Video" 
												   message:@"Your phone cannot connect to the internet to play video. Please check your connection settings." 
												  delegate:nil 
										 cancelButtonTitle:@"OK"
										 otherButtonTitles:nil];
	[test setTag:11];
	[test show];
	[test release];
}

// UIActionSheetDelegate event handler
- (void) actionSheet:(UIActionSheet*)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (0 <= buttonIndex){
        if (NUM_BUTTONS > buttonIndex) {
            buttonMask = 1 << buttonIndex;
        }
        else {
            switch (buttonIndex) {
                case NUM_BUTTONS:       // Turn on camera torch (4)
                    QCAR::CameraDevice::getInstance().setFlashTorchMode(true);
                    break;
                case NUM_BUTTONS + 1:   // Turn off camera torch (5)
                    QCAR::CameraDevice::getInstance().setFlashTorchMode(false);
                    break;
                case NUM_BUTTONS + 2:   // Turn on camera autofocus (6)
                    QCAR::CameraDevice::getInstance().startAutoFocus();
                    break;
                case NUM_BUTTONS + 3:   // Turn off camera autofocus (7)
                    QCAR::CameraDevice::getInstance().stopAutoFocus();
                    break;
                default:
                    break;
            }
        }
    }
}


////////////////////////////////////////////////////////////////////////////////
- (void)onCreate
{
    NSLog(@"EAGLView onCreate()");
    ARData.appStatus = APPSTATUS_UNINITED;
    
    // Load textures
    int nErr = [self loadTextures];
    
    if (noErr == nErr) {
        [self updateApplicationStatus:APPSTATUS_INIT_APP];
    }
}


////////////////////////////////////////////////////////////////////////////////
- (void)onDestroy
{
    NSLog(@"EAGLView onDestroy()");
    // Release the textures array
    [ARData.textures release];
    
    // Deinitialise QCAR SDK
    QCAR::deinit();
}


////////////////////////////////////////////////////////////////////////////////
- (void)onResume
{
    NSLog(@"EAGLView onResume()");
    
    // If the app status is APPSTATUS_CAMERA_STOPPED, QCAR must have been fully
    // initialised
    if (APPSTATUS_CAMERA_STOPPED == ARData.appStatus) {
        // QCAR-specific resume operation
        QCAR::onResume();
    
        [self updateApplicationStatus:APPSTATUS_CAMERA_RUNNING];
    }
}


////////////////////////////////////////////////////////////////////////////////
- (void)onPause
{
    NSLog(@"EAGLView onPause()");
    
    // If the app status is APPSTATUS_CAMERA_RUNNING, QCAR must have been fully
    // initialised
    if (APPSTATUS_CAMERA_RUNNING == ARData.appStatus) {
        [self updateApplicationStatus:APPSTATUS_CAMERA_STOPPED];
        
        // QCAR-specific pause operation
        QCAR::onPause();
    }
}

////////////////////////////////////////////////////////////////////////////////
// Load the textures for use by OpenGL
- (int)loadTextures
{
    int nErr = noErr;
    int nTextures = sizeof(textureFilenames) / sizeof(textureFilenames[0]);
    ARData.textures = [[NSMutableArray array] retain];
    
    @try {
        for (int i = 0; i < nTextures; ++i) {
            Texture* tex = [[[Texture alloc] init] autorelease];
            NSString* file = [NSString stringWithCString:textureFilenames[i] encoding:NSASCIIStringEncoding];
            
            nErr = [tex loadImage:file] == YES ? noErr : 1;
            [ARData.textures addObject:tex];
            
            if (noErr != nErr) {
                break;
            }
        }
    }
    @catch (NSException* e) {
        NSLog(@"NSMutableArray addObject exception");
    }
    
    assert([ARData.textures count] == nTextures);
    if ([ARData.textures count] != nTextures) {
        nErr = 1;
    }
    
    return nErr;
}

////////////////////////////////////////////////////////////////////////////////
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    exit(0);
}

////////////////////////////////////////////////////////////////////////////////
- (void)updateApplicationStatus:(status)newStatus
{
	
	/** Fix to initialize after app loads **
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Instructions" 
													message:@"Track image by pointing at object." 
												   delegate:nil 
										  cancelButtonTitle:@"Begin!"
										  otherButtonTitles:nil];
	/**************/
	 
    if (newStatus != ARData.appStatus && APPSTATUS_ERROR != ARData.appStatus) {
        ARData.appStatus = newStatus;
        
        switch (ARData.appStatus) {
            case APPSTATUS_INIT_APP:
                // Initialise the application
                [self initApplication];
                [self updateApplicationStatus:APPSTATUS_INIT_QCAR];
                break;
                
            case APPSTATUS_INIT_QCAR:
                // Initialise QCAR
                [self performSelectorInBackground:@selector(initQCAR) withObject:nil];
                break;
                
            case APPSTATUS_INIT_APP_AR:
                // AR-specific initialisation
				//[alert show];
				//[alert release];
                [self initApplicationAR];
                [self updateApplicationStatus:APPSTATUS_INIT_TRACKER];
                break;
                
            case APPSTATUS_INIT_TRACKER:
                // Load tracker data
                [self performSelectorInBackground:@selector(loadTracker) withObject:nil];
                break;
                
            case APPSTATUS_INITED:
                // These two calls to setHint tell QCAR to split work over multiple
                // frames.  Depending on your requirements you can opt to omit these.
                //QCAR::setHint(QCAR::HINT_IMAGE_TARGET_MULTI_FRAME_ENABLED, 1);
                //QCAR::setHint(QCAR::HINT_IMAGE_TARGET_MILLISECONDS_PER_MULTI_FRAME, 25);
				
                // Here we could also make a QCAR::setHint call to set the maximum
                // number of simultaneous targets 
				QCAR::setHint(QCAR::HINT_MAX_SIMULTANEOUS_IMAGE_TARGETS, 2);
                
                // Register a callback function that gets called every time a
                // tracking cycle has finished and we have a new AR state
                // available
                QCAR::registerCallback(&qcarUpdate);
                
                // Initialisation is complete, start QCAR
                QCAR::onResume();
                
                [self updateApplicationStatus:APPSTATUS_CAMERA_RUNNING];
                break;
                
            case APPSTATUS_CAMERA_RUNNING:
                [self startCamera];
                break;
                
            case APPSTATUS_CAMERA_STOPPED:
                [self stopCamera];
                break;
                
            default:
                NSLog(@"updateApplicationStatus: invalid app status");
                break;
        }
    }
    
    if (APPSTATUS_ERROR == ARData.appStatus) {
        // Application initialisation failed, display an alert view
        UIAlertView* alert = [[UIAlertView alloc] initWithTitle:@"Error" message:@"Application initialisation failed." delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil];
        
        [alert show];
        [alert release];
    }
}


////////////////////////////////////////////////////////////////////////////////
// Bump the application status on one step
- (void)bumpAppStatus
{
    [self updateApplicationStatus:(status)(ARData.appStatus + 1)];
}


////////////////////////////////////////////////////////////////////////////////
// Initialise the application
- (void)initApplication
{
    // Get the device screen dimensions
    ARData.screenRect = [[UIScreen mainScreen] bounds];
    
    // Inform QCAR that the drawing surface has been created
    QCAR::onSurfaceCreated();
    
    // Inform QCAR that the drawing surface size has changed
    QCAR::onSurfaceChanged(ARData.screenRect.size.height, ARData.screenRect.size.width);
	
	//Plug screen width and height into variables
	screenHeight = ARData.screenRect.size.height;
	screenWidth = ARData.screenRect.size.width;
}


////////////////////////////////////////////////////////////////////////////////
// Initialise QCAR [performed on a background thread]
- (void)initQCAR
{
    // Background thread must have its own autorelease pool
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    QCAR::setInitParameters(ARData.QCARFlags);
    
    int nPercentComplete = 0;
    
    do {
        nPercentComplete = QCAR::init();
    } while (0 <= nPercentComplete && 100 > nPercentComplete);
    
    NSLog(@"QCAR::init percent: %d", nPercentComplete);
    
    if (0 > nPercentComplete) {
        ARData.appStatus = APPSTATUS_ERROR;
    }

    // Continue execution on the main thread
    [self performSelectorOnMainThread:@selector(bumpAppStatus) withObject:nil waitUntilDone:NO];
    
    [pool release];
    
} 


////////////////////////////////////////////////////////////////////////////////
// Initialise the AR parts of the application
- (void)initApplicationAR
{
    // Initialise rendering
    [self initRendering];
}


////////////////////////////////////////////////////////////////////////////////
// Load the tracker data [performed on a background thread]
- (void)loadTracker
{
    int nPercentComplete = 0;

    // Background thread must have its own autorelease pool
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    // Load the tracker data
    do {
        nPercentComplete = QCAR::Tracker::getInstance().load();
    } while (0 <= nPercentComplete && 100 > nPercentComplete);

    if (0 > nPercentComplete) {
        ARData.appStatus = APPSTATUS_ERROR;
    }
    
    // Continue execution on the main thread
    [self performSelectorOnMainThread:@selector(bumpAppStatus) withObject:nil waitUntilDone:NO];
    
    [pool release];
}


////////////////////////////////////////////////////////////////////////////////
// Start capturing images from the camera
- (void)startCamera
{
    // Initialise the camera
    if (QCAR::CameraDevice::getInstance().init()) {
        // Configure video background
        [self configureVideoBackground];
        
        // Select the default mode
        if (QCAR::CameraDevice::getInstance().selectVideoMode(QCAR::CameraDevice::MODE_DEFAULT)) {
            // Start camera capturing
            if (QCAR::CameraDevice::getInstance().start()) {
                // Start the tracker
                QCAR::Tracker::getInstance().start();
                
                // Cache the projection matrix
                const QCAR::CameraCalibration& cameraCalibration = QCAR::Tracker::getInstance().getCameraCalibration();
                projectionMatrix = QCAR::Tool::getProjectionGL(cameraCalibration, 2.0f, 2000.0f);
            }
        }
    }
}


////////////////////////////////////////////////////////////////////////////////
// Stop capturing images from the camera
- (void)stopCamera
{
    QCAR::Tracker::getInstance().stop();
    QCAR::CameraDevice::getInstance().stop();
    QCAR::CameraDevice::getInstance().deinit();
}


////////////////////////////////////////////////////////////////////////////////
// Configure the video background
- (void)configureVideoBackground
{
    // Get the default video mode
    QCAR::CameraDevice& cameraDevice = QCAR::CameraDevice::getInstance();
    QCAR::VideoMode videoMode = cameraDevice.getVideoMode(QCAR::CameraDevice::MODE_DEFAULT);
    
    // Configure the video background
    QCAR::VideoBackgroundConfig config;
    config.mEnabled = true;
    config.mSynchronous = true;
    config.mPosition.data[0] = 0.0f;
    config.mPosition.data[1] = 0.0f;
    
    // Compare aspect ratios of video and screen.  If they are different
    // we use the full screen size while maintaining the video's aspect
    // ratio, which naturally entails some cropping of the video.
    // Note - screenRect is portrait but videoMode is always landscape,
    // which is why "width" and "height" appear to be reversed.
    float arVideo = (float)videoMode.mWidth / (float)videoMode.mHeight;
    float arScreen = ARData.screenRect.size.height / ARData.screenRect.size.width;
    
    if (arVideo > arScreen)
    {
        // Video mode is wider than the screen.  We'll crop the left and right edges of the video
        config.mSize.data[0] = (int)ARData.screenRect.size.width * arVideo;
        config.mSize.data[1] = (int)ARData.screenRect.size.width;
    }
    else
    {
        // Video mode is taller than the screen.  We'll crop the top and bottom edges of the video.
        // Also used when aspect ratios match (no cropping).
        config.mSize.data[0] = (int)ARData.screenRect.size.height;
        config.mSize.data[1] = (int)ARData.screenRect.size.height / arVideo;
    }
    
    // Set the config
    QCAR::Renderer::getInstance().setVideoBackgroundConfig(config);
}


////////////////////////////////////////////////////////////////////////////////
// Initialise OpenGL rendering
- (void)initRendering
{
    // Define the clear colour
    glClearColor(0.0f, 0.0f, 0.0f, QCAR::requiresAlpha() ? 0.0f : 1.0f);
    
    // Generate the OpenGL texture objects
    for (int i = 0; i < [ARData.textures count]; ++i) {
        GLuint nID;
        Texture* texture = [ARData.textures objectAtIndex:i];
        glGenTextures(1, &nID);
        [texture setTextureID: nID];
        glBindTexture(GL_TEXTURE_2D, nID);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, [texture width], [texture height], 0, GL_RGBA, GL_UNSIGNED_BYTE, (GLvoid*)[texture pngData]);
    }
    
#ifndef USE_OPENGL1
    if (QCAR::GL_20 & ARData.QCARFlags) {
        // OpenGL 2 initialisation
        shaderProgramID = ShaderUtils::createProgramFromBuffer(cubeVertexShader, cubeFragmentShader);
        vertexHandle = glGetAttribLocation(shaderProgramID, "vertexPosition");
        normalHandle = glGetAttribLocation(shaderProgramID, "vertexNormal");
        textureCoordHandle = glGetAttribLocation(shaderProgramID, "vertexTexCoord");
        mvpMatrixHandle = glGetUniformLocation(shaderProgramID, "modelViewProjectionMatrix");
        
        // Virtual buttons
        vbShaderProgramID = ShaderUtils::createProgramFromBuffer(lineVertexShader, lineFragmentShader);
        vbVertexHandle = glGetAttribLocation(vbShaderProgramID, "vertexPosition");
    }
#endif
}


////////////////////////////////////////////////////////////////////////////////
// Draw the current frame using OpenGL
//
// This method is called by QCAR when it wishes to render the current frame to
// the screen.
//
// *** QCAR will call this method on a single background thread ***
- (void)renderFrameQCAR
{
	/********** TESTING PURPOSES ONLY ***********
	
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"ALERT" 
													message:@"You touched a button." 
												   delegate:nil 
										  cancelButtonTitle:@"Cool"
										  otherButtonTitles:nil];
	
	/**********************************************/
	
	QCAR::Matrix44F modelViewProjection;
	
    if (APPSTATUS_CAMERA_RUNNING == ARData.appStatus) {
        [self setFramebuffer];
        
        // Clear colour and depth buffers
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        
        // Render video background and retrieve tracking state
        QCAR::State state = QCAR::Renderer::getInstance().begin();
        //NSLog(@"active trackables: %d", state.getNumActiveTrackables());
        
        if (QCAR::GL_11 & ARData.QCARFlags) {
            glDisable(GL_LIGHTING);
            glEnableClientState(GL_VERTEX_ARRAY);
            glEnableClientState(GL_NORMAL_ARRAY);
            glEnableClientState(GL_TEXTURE_COORD_ARRAY);
        }
        
        glEnable(GL_DEPTH_TEST);
        glEnable(GL_CULL_FACE);
		 
		 for (int i = 0; i < state.getNumActiveTrackables(); ++i) {
            // Get the trackable
            const QCAR::Trackable* trackable = state.getActiveTrackable(i);
            QCAR::Matrix44F modelViewMatrix = QCAR::Tool::convertPose2GLMatrix(trackable->getPose());
			
			assert(trackable->getType() == QCAR::Trackable::IMAGE_TARGET);
            
            // The image target
            const QCAR::ImageTarget* target = static_cast<const QCAR::ImageTarget*>(trackable);

            GLfloat vbVertices[24];
            unsigned char vbCounter=0;
			
			/************** DRAW RECTANGLE AROUND TRACKABLE****************/
			
			if ( target->getNumVirtualButtons() )
	        {
				const QCAR::VirtualButton* button = target->getVirtualButton(0);
				const QCAR::Area* vbArea = &button->getArea();
                assert(vbArea->getType() == QCAR::Area::RECTANGLE);
                const QCAR::Rectangle* vbRectangle = static_cast<const QCAR::Rectangle*>(vbArea);
				
				vbVertices[vbCounter+ 0]=vbRectangle->getLeftTopX();
                vbVertices[vbCounter+ 1]=vbRectangle->getLeftTopY();
                vbVertices[vbCounter+ 2]=0.0f;
                vbVertices[vbCounter+ 3]=vbRectangle->getRightBottomX();
                vbVertices[vbCounter+ 4]=vbRectangle->getLeftTopY();
                vbVertices[vbCounter+ 5]=0.0f;
                vbVertices[vbCounter+ 6]=vbRectangle->getRightBottomX();
                vbVertices[vbCounter+ 7]=vbRectangle->getLeftTopY();
                vbVertices[vbCounter+ 8]=0.0f;
                vbVertices[vbCounter+ 9]=vbRectangle->getRightBottomX();
                vbVertices[vbCounter+10]=vbRectangle->getRightBottomY();
                vbVertices[vbCounter+11]=0.0f;
                vbVertices[vbCounter+12]=vbRectangle->getRightBottomX();
                vbVertices[vbCounter+13]=vbRectangle->getRightBottomY();
                vbVertices[vbCounter+14]=0.0f;
                vbVertices[vbCounter+15]=vbRectangle->getLeftTopX();
                vbVertices[vbCounter+16]=vbRectangle->getRightBottomY();
                vbVertices[vbCounter+17]=0.0f;
                vbVertices[vbCounter+18]=vbRectangle->getLeftTopX();
                vbVertices[vbCounter+19]=vbRectangle->getRightBottomY();
                vbVertices[vbCounter+20]=0.0f;
                vbVertices[vbCounter+21]=vbRectangle->getLeftTopX();
                vbVertices[vbCounter+22]=vbRectangle->getLeftTopY();
                vbVertices[vbCounter+23]=0.0f;
                vbCounter+=24;
				
			}
			
			if (vbCounter>0)
            {
				/********* Xingwei's modified part *************/
				glUseProgram(vbShaderProgramID);
				
	            glVertexAttribPointer(vbVertexHandle, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)vbVertices);
	            glEnableVertexAttribArray(vbVertexHandle);
				
	            glUniformMatrix4fv(mvpMatrixHandle, 1, GL_FALSE, (GLfloat*)&modelViewProjection.data[0] );
				
				glLineWidth( 5.0f );	
				glDrawArrays(GL_LINES, 0, 8 );
				
				glDisableVertexAttribArray(vbVertexHandle);
				/************************************************/
            }
			

				/********* Xingwei's modified part *************/
				glUseProgram(vbShaderProgramID);
				
	            glVertexAttribPointer(vbVertexHandle, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)vbVertices);
	            glEnableVertexAttribArray(vbVertexHandle);
				
	            glUniformMatrix4fv(mvpMatrixHandle, 1, GL_FALSE, (GLfloat*)&modelViewProjection.data[0] );
    
				glLineWidth( 5.0f );	
				glDrawArrays(GL_LINES, 0, 8 );
				
				glDisableVertexAttribArray(vbVertexHandle);
				/************************************************/
				
                // Render a frame around the button using the appropriate
                // version of OpenGL
                if (QCAR::GL_11 & ARData.QCARFlags) {
                    // Load the projection matrix
                    glMatrixMode(GL_PROJECTION);
                    glLoadMatrixf(projectionMatrix.data);
                    
                    // Load the model-view matrix
                    glMatrixMode(GL_MODELVIEW);
                    glLoadMatrixf(modelViewMatrix.data);
                    
                    glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
                    glVertexPointer(3, GL_FLOAT, 0, (const GLvoid*) &vbVertices[0]);

                    // We multiply by 8 because that's the number of vertices per button
                    // The reason is that GL_LINES considers only pairs. So some vertices
                    // must be repeated.
                    glDrawArrays(GL_LINES, 0, target->getNumVirtualButtons()*8); 
					glDisableVertexAttribArray(vbVertexHandle);
                }
#ifndef USE_OPENGL1
                else {                    
                    ShaderUtils::multiplyMatrix(&projectionMatrix.data[0], &modelViewMatrix.data[0], &modelViewProjection.data[0]);
                    glUseProgram(vbShaderProgramID);
                    glVertexAttribPointer(vbVertexHandle, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid*) &vbVertices[0]);
                    glEnableVertexAttribArray(vbVertexHandle);
                    glUniformMatrix4fv(mvpMatrixHandle, 1, GL_FALSE, (GLfloat*)&modelViewProjection.data[0] );
                    glDrawArrays(GL_LINES, 0, target->getNumVirtualButtons()*8);
                    glDisableVertexAttribArray(vbVertexHandle);
                }
#endif
            }
			/****************************************************/
            
        
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_CULL_FACE);
        
        if (QCAR::GL_11 & ARData.QCARFlags) {
            glDisableClientState(GL_VERTEX_ARRAY);
            glDisableClientState(GL_NORMAL_ARRAY);
            glDisableClientState(GL_TEXTURE_COORD_ARRAY);
        }
#ifndef USE_OPENGL1
        else {
            glDisableVertexAttribArray(vertexHandle);
            glDisableVertexAttribArray(normalHandle);
            glDisableVertexAttribArray(textureCoordHandle);
        }
#endif
        
        QCAR::Renderer::getInstance().end();
        [self presentFramebuffer];
    }
}


////////////////////////////////////////////////////////////////////////////////
// Callback function called by the tracker when each tracking cycle has finished
void VirtualButton_UpdateCallback::QCAR_onUpdate(QCAR::State& state)
{
    // Set the active/inactive state of the virtual buttons (if the user has
    // made a selection from the menu)
	
	if(state.getNumActiveTrackables() > 0)
	{
		numActiveTrackables = state.getNumActiveTrackables();
			
		QCAR::CameraDevice& cameraDevice = QCAR::CameraDevice::getInstance();	//ºÚªØ≥…π≤”–±‰¡ø*********************************
		QCAR::VideoMode videoMode = cameraDevice.getVideoMode(QCAR::CameraDevice::MODE_DEFAULT);
		
		const QCAR::Tracker& tracker = QCAR::Tracker::getInstance();
		const QCAR::CameraCalibration& cameraCalibration = tracker.getCameraCalibration();
		
		int i , j;	
		
		const QCAR::Trackable* trackable;
		const QCAR::Trackable* trackable1;
		const QCAR::ImageTarget* target;        		
		const QCAR::VirtualButton* button;
		const QCAR::Area* vbArea;
		const QCAR::Rectangle* vbRectangle;
		
		
		QCAR::Vec3F vecCoords3F;
		QCAR::Vec2F vecCoords2F;    
		
		for( i = 0 ; i < numActiveTrackables; i ++ )
		{
			trackable = state.getActiveTrackable( i );  
			assert(trackable->getType() == QCAR::Trackable::IMAGE_TARGET);
			
			for( j = 0; j < tracker.getNumTrackables(); j ++ )
			{														
				if( strcmp( trackable->getName(), tracker.getTrackable( j )->getName() ) == 0 )
					break;
			}				
			trackableInfo[i].tI = j;
			
			trackable1 = tracker.getTrackable(j);
			target = static_cast<const QCAR::ImageTarget*>(trackable1);				        
			button = target->getVirtualButton( 0 );                   
			vbArea = &button->getArea();
			assert(vbArea->getType() == QCAR::Area::RECTANGLE);
			vbRectangle = static_cast<const QCAR::Rectangle*>(vbArea);
			
			vecCoords3F.data[0] = vbRectangle->getLeftTopX();
			vecCoords3F.data[1] = vbRectangle->getLeftTopY();
			vecCoords3F.data[2] = 0.0f;				    			
			vecCoords2F = QCAR::Tool::projectPoint(cameraCalibration, trackable->getPose() , vecCoords3F );
			trackableInfo[i].pixelsCoord[0] = vecCoords2F.data[0] *(screenWidth/(float)videoMode.mWidth);
			trackableInfo[i].pixelsCoord[1] = vecCoords2F.data[1] *(screenWidth/(float)videoMode.mWidth);
			
			vecCoords3F.data[0] = vbRectangle->getRightBottomX();
			vecCoords3F.data[1] = vbRectangle->getRightBottomY();
			vecCoords2F = QCAR::Tool::projectPoint(cameraCalibration, trackable->getPose() , vecCoords3F );
			trackableInfo[i].pixelsCoord[2] = vecCoords2F.data[0] *(screenWidth/(float)videoMode.mWidth);
			trackableInfo[i].pixelsCoord[3] = vecCoords2F.data[1] *(screenWidth/(float)videoMode.mWidth);
		}
	}
	else {
		numActiveTrackables = 0;
	}    
}

// Function for streaming video
-(void)playVideo
{
	isPlaying = 1;
	tIdx = 100; // Video mode
	NSURL *url;
	if(trackingNumber == 1)
	{
		url = [NSURL URLWithString:@"http://60.247.48.28/videos/numberfour.mp4"];
	}
	else if(trackingNumber == 2)
	{
		url = [NSURL URLWithString:@"http://60.247.48.28/videos/hp72.mp4"];
	}
	else if(trackingNumber == 3)
	{
		url = [NSURL URLWithString:@"http://60.247.48.28/videos/hangover.mp4"];
	}
	else if(trackingNumber == 4)
	{
		url = [NSURL URLWithString:@"http://60.247.48.28/videos/ironman2.mp4"];
	}
	MPMoviePlayerController *player = [[MPMoviePlayerController alloc] initWithContentURL:url];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(moviePlaybackDidFinish:)
												 name:MPMoviePlayerPlaybackDidFinishNotification object:player];
	//[player.view setFrame:self.bounds];
	
	int screenX = 0;
	int screenY = 0;
	int offsetX = 0;
	int offsetY = 0;
	if(screenWidth == 480)
	{
		// iPhone 3GS
		screenX = 240;
		screenY = 160;
		offsetX = 120;
		offsetY = 80;
	}
	else if(screenWidth == 960)
	{
		// iPhone 4
		screenX = 480;
		screenY = 320;
		offsetX = 240;
		offsetY = 160;
	}
	
	// Render video in a box instead of full screen.
	// Coordinates are (x offset, y offset, width, height)
	//player.view.frame = CGRectMake(offsetX, offsetY, screenX, screenY);
	
	//Hardcoding for testing purposes
	player.view.frame = CGRectMake(120, 80, 240, 160); // iPhone 3GS
	//player.view.frame = CGRectMake(240, 160, 480, 320); // iPhone 4
	[self addSubview:player.view];
	[player play];
}

// Function for stopping video
-(void)moviePlaybackDidFinish:(NSNotification*)aNotification
{
	isPlaying = 0;
	tIdx = -1;
	MPMoviePlayerController *player = [aNotification object];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerPlaybackDidFinishNotification object:player];
	[player stop];
	player.initialPlaybackTime = -1.0;
	
	//player.view.frame = CGRectMake(0, 0, 0, 0);
	player.view.hidden = YES;
	[player.view removeFromSuperview];
	[player release];
	player = nil;
	
	//CRASHES HERE
}

/******** Test function to display alertbox if application has detected image *******/
-(void)trackedSuccess
{
	UIAlertView *test = [[UIAlertView alloc] initWithTitle:@"Trackable Found" 
												   message:@"Video will now load. Please wait." 
												  delegate:nil 
										 cancelButtonTitle:@"OK"
										 otherButtonTitles:nil];
	[test setTag:10];
	[test show];
	[test release];
}

-(void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
	if([alertView tag] == 10)
	{
		if(buttonIndex == 0)
		{
			isPlaying = 0;
		}
	}
}
/***********************************************************************/

@end
