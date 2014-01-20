/*==============================================================================
Copyright (c) 2010-2011 QUALCOMM Austria Research Center GmbH .
All Rights Reserved.
Qualcomm Confidential and Proprietary
==============================================================================*/

#import <UIKit/UIKit.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <QCAR/Tool.h>
#import <QCAR/UIGLViewProtocol.h>


// Application status
typedef enum _status {
    APPSTATUS_UNINITED,
    APPSTATUS_INIT_APP,
    APPSTATUS_INIT_QCAR,
    APPSTATUS_INIT_APP_AR,
    APPSTATUS_INIT_TRACKER,
    APPSTATUS_INITED,
    APPSTATUS_CAMERA_STOPPED,
    APPSTATUS_CAMERA_RUNNING,
    APPSTATUS_ERROR
} status;


// This class wraps the CAEAGLLayer from CoreAnimation into a convenient UIView
// subclass.  The view content is basically an EAGL surface you render your
// OpenGL scene into.  Note that setting the view non-opaque will only work if
// the EAGL surface has an alpha channel.
@interface EAGLView : UIView <UIActionSheetDelegate, UIGLViewProtocol>
{
@private
    EAGLContext *context;
    
    // The pixel dimensions of the CAEAGLLayer.
    GLint framebufferWidth;
    GLint framebufferHeight;
    
    // The OpenGL ES names for the framebuffer and renderbuffers used to render
    // to this view.
    GLuint defaultFramebuffer;
    GLuint colorRenderbuffer;
    GLuint depthRenderbuffer;
    
    // OpenGL projection matrix
    QCAR::Matrix44F projectionMatrix;
    
    struct tagARData {
        CGRect screenRect;
        NSMutableArray* textures;   // Teapot textures
        int QCARFlags;              // QCAR initialisation flags
        status appStatus;           // Current app status
    } ARData;
    
#ifndef USE_OPENGL1
    // OpenGL 2 data
    unsigned int shaderProgramID;
    unsigned int vbShaderProgramID;
    GLint vertexHandle;
    GLint vbVertexHandle;
    GLint normalHandle;
    GLint textureCoordHandle;
    GLint mvpMatrixHandle;
#endif
}

- (void)renderFrameQCAR;    // Render frame method called by QCAR
- (void)onCreate;
- (void)onDestroy;
- (void)onResume;
- (void)onPause;

@end
