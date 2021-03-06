/*==============================================================================
Copyright (c) 2010-2011 QUALCOMM Austria Research Center GmbH .
All Rights Reserved.
Qualcomm Confidential and Proprietary
==============================================================================*/


const char* cubeFragmentShader = MAKESTRING(
precision mediump float;
varying vec2 texCoord;

uniform sampler2D texSampler2D;

void main()
{
    gl_FragColor = texture2D(texSampler2D, texCoord);
}
);
