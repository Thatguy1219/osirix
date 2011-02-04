/*=========================================================================
  Program:   OsiriX

  Copyright (c) OsiriX Team
  All rights reserved.
  Distributed under GNU - LGPL
  
  See http://www.osirix-viewer.com/copyright.html for details.

     This software is distributed WITHOUT ANY WARRANTY; without even
     the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
     PURPOSE.
=========================================================================*/


#import "CPRGeometry.h"
#import "CPRTransverseView.h"
#import "CPRCurvedPath.h"
#import "CPRBezierPath.h"
#import "CPRVolumeData.h"
#import "CPRGeneratorRequest.h"
#import "CPRBezierCore.h"
#import "CPRBezierCoreAdditions.h"
#import "DCMPix.h"
#import "CPRMPRDCMView.h"
#import "CPRController.h"

extern int CLUTBARS, ANNOTATIONS;

@interface CPRTransverseView ()

@property (nonatomic, readwrite, retain) CPRStraightenedGeneratorRequest *lastRequest;
@property (nonatomic, readwrite, retain) CPRVolumeData *generatedVolumeData;

- (CGFloat)_relativeSegmentPosition;

- (CPRBezierPath*)_requestBezierAndInitialNormal:(CPRVectorPointer)initialNormal;

- (void)_setNeedsNewRequest;
- (void)_sendNewRequestIfNeeded;
- (void)_sendNewRequest;

@end


@implementation CPRTransverseView

@synthesize delegate = _delegate;
@synthesize curvedPath = _curvedPath;
@synthesize sectionType = _sectionType;
@synthesize sectionWidth = _sectionWidth;
@synthesize volumeData = _volumeData;
@synthesize lastRequest = _lastRequest;
@synthesize generatedVolumeData = _generatedVolumeData;


- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
    }
    return self;
}

- (void)dealloc
{
    _generator.delegate = nil;
    [_generator release];
    _generator = nil;
    [_volumeData release];
    _volumeData = nil;
    [_generatedVolumeData release];
    _generatedVolumeData = nil;
    [_curvedPath release];
    _curvedPath = nil;
    [_lastRequest release];
    _lastRequest = nil;
    
    [super dealloc];
}

- (void)mouseDraggedWindowLevel:(NSEvent *)event
{
	[super mouseDraggedWindowLevel: event];
	
	[[self windowController] propagateWLWW: self];
}

- (void)setVolumeData:(CPRVolumeData *)volumeData
{
    if (volumeData != _volumeData) {
        _generator.delegate = nil;
        [_generator release];
        [_volumeData release];
        _volumeData = [volumeData retain];
        _generator = [[CPRGenerator alloc] initWithVolumeData:_volumeData];
        _generator.delegate = self;
        [self _setNeedsNewRequest];
    }
}

- (void)setCurvedPath:(CPRCurvedPath *)curvedPath
{
    if (curvedPath != _curvedPath) {
        if (curvedPath.thickness != _curvedPath.thickness) {
            [self setNeedsDisplay:YES];
        }
        
        [_curvedPath release];
        _curvedPath = [curvedPath copy];
        [self _setNeedsNewRequest];
    }
}


- (void)setSectionWidth:(CGFloat)sectionWidth
{
    if (_sectionWidth != sectionWidth) {
        _sectionWidth = sectionWidth;
        [self _setNeedsNewRequest];
    }
}

- (void)setSectionType:(CPRTransverseViewSection)sectionType
{
    if (_sectionType != sectionType) {
        _sectionType = sectionType;
        [self _setNeedsNewRequest];
    }
}

- (void)setFrame:(NSRect)frameRect
{
    BOOL needsUpdate;
    
    needsUpdate = NO;
	if( NSEqualRects( frameRect, [self frame]) == NO) {
        needsUpdate = YES;
    }
    
    [super setFrame: frameRect];
    
    if (needsUpdate) {
        [self _setNeedsNewRequest];
	}
}

- (void)scrollWheel:(NSEvent *)theEvent
{
    CGFloat transverseSectionPosition;
    
    transverseSectionPosition = MIN(MAX(_curvedPath.transverseSectionPosition + [theEvent deltaY] * .004, 0.0), 1.0); 
    
    if ([_delegate respondsToSelector:@selector(CPRViewWillEditCurvedPath:)]) {
        [_delegate CPRViewWillEditCurvedPath:self];
    }
    _curvedPath.transverseSectionPosition = transverseSectionPosition;
    if ([_delegate respondsToSelector:@selector(CPRViewDidEditCurvedPath:)])  {
        [_delegate CPRViewDidEditCurvedPath:self];
    }
    [self _setNeedsNewRequest];
}

- (void) drawRect:(NSRect)aRect withContext:(NSOpenGLContext *)ctx
{
	long clutBars = CLUTBARS, annotations = ANNOTATIONS;
	
	CLUTBARS = barHide;
	ANNOTATIONS = annotNone;
	
	[super drawRect: aRect withContext: ctx];
	
	CLUTBARS = clutBars;
	ANNOTATIONS = annotations;
}

- (void)subDrawRect:(NSRect)rect
{
    CPRVector lineStart;
    CPRVector lineEnd;
    CPRVector cursorVector;
    CPRAffineTransform3D pixToSubDrawRectTransform;
    CGFloat pixelsPerMm;
    CGLContextObj cgl_ctx;
    
    cgl_ctx = [[NSOpenGLContext currentContext] CGLContextObj];    
    
    pixToSubDrawRectTransform = [self pixToSubDrawRectTransform];
    pixelsPerMm = (CGFloat)curDCM.pwidth/_sectionWidth;
    
    glColor4d(0.0, 1.0, 0.0, 1.0);
    lineStart = CPRVectorApplyTransform(CPRVectorMake((CGFloat)curDCM.pwidth/2.0, 0, 0), pixToSubDrawRectTransform);
    lineEnd = CPRVectorApplyTransform(CPRVectorMake((CGFloat)curDCM.pwidth/2.0, curDCM.pheight, 0), pixToSubDrawRectTransform);
    glLineWidth(1.0);
    glBegin(GL_LINE_STRIP);
    glVertex2f(lineStart.x, lineStart.y);
    glVertex2f(lineEnd.x, lineEnd.y);
    glEnd();
    
    if (_curvedPath.thickness > 2.0) {
        glLineWidth(1.0);
        glBegin(GL_LINES);
        lineStart = CPRVectorApplyTransform(CPRVectorMake(((CGFloat)curDCM.pwidth+_curvedPath.thickness*pixelsPerMm)/2.0, 0, 0), pixToSubDrawRectTransform);
        lineEnd = CPRVectorApplyTransform(CPRVectorMake(((CGFloat)curDCM.pwidth+_curvedPath.thickness*pixelsPerMm)/2.0, curDCM.pheight, 0), pixToSubDrawRectTransform);
        glVertex2f(lineStart.x, lineStart.y);
        glVertex2f(lineEnd.x, lineEnd.y);
        lineStart = CPRVectorApplyTransform(CPRVectorMake(((CGFloat)curDCM.pwidth-_curvedPath.thickness*pixelsPerMm)/2.0, 0, 0), pixToSubDrawRectTransform);
        lineEnd = CPRVectorApplyTransform(CPRVectorMake(((CGFloat)curDCM.pwidth-_curvedPath.thickness*pixelsPerMm)/2.0, curDCM.pheight, 0), pixToSubDrawRectTransform);
        glVertex2f(lineStart.x, lineStart.y);
        glVertex2f(lineEnd.x, lineEnd.y);
        glEnd();
    }
}


- (void)generator:(CPRGenerator *)generator didGenerateVolume:(CPRVolumeData *)volume request:(CPRGeneratorRequest *)request
{
    NSLog(@"didGenerateVolume");
    float wl;
    float ww;
    NSUInteger i;
    NSMutableArray *pixArray;
    DCMPix *newPix;
        
    [self getWLWW:&wl :&ww];
    [[self.generatedVolumeData retain] autorelease]; // make sure this is around long enough so that it doesn't disapear under the old DCMPix
    self.generatedVolumeData = volume;
    
    pixArray = [[NSMutableArray alloc] init];
    
    for (i = 0; i < self.generatedVolumeData.pixelsDeep; i++) {
        newPix = [[DCMPix alloc] initWithData:(float *)[self.generatedVolumeData floatBytes] + (i*self.generatedVolumeData.pixelsWide*self.generatedVolumeData.pixelsHigh) :32 
                                             :self.generatedVolumeData.pixelsWide :self.generatedVolumeData.pixelsHigh :self.generatedVolumeData.pixelSpacingX :self.generatedVolumeData.pixelSpacingY
                                             :0.0 :0.0 :0.0 :NO];
        [pixArray addObject:newPix];
        [newPix release];
    }
    
    for( i = 0; i < [pixArray count]; i++)
    {
        [[pixArray objectAtIndex: i] setArrayPix:pixArray :i];
    }
    
    [self setPixels:pixArray files:NULL rois:NULL firstImage:0 level:'i' reset:YES];
    
    [self setWLWW:wl :ww];
    
    [pixArray release];
    [self setNeedsDisplay:YES];
}

- (void)_sendNewRequest
{
    CPRStraightenedGeneratorRequest *request;
    CPRVector initialNormal;
    
    if ([_curvedPath.bezierPath elementCount] >= 2) {
        request = [[CPRStraightenedGeneratorRequest alloc] init];
        
        request.pixelsWide = [self bounds].size.width;
        request.pixelsHigh = [self bounds].size.height;
        request.slabWidth = 0;
        request.slabSampleDistance = 0;
        request.bezierPath = [self _requestBezierAndInitialNormal:&initialNormal];
        request.initialNormal = initialNormal;
        request.vertical = NO;
        request.bezierStartPosition = 0;
        request.bezierEndPosition = 1;
        request.middlePosition = 0;
        
        if ([_lastRequest isEqual:request] == NO) {
            [_generator requestVolume:request];
            self.lastRequest = request;
        }
        
        [request release];
    }
    _needsNewRequest = NO;
}

- (CGFloat)_relativeSegmentPosition
{
    switch (_sectionType) {
        case CPRTransverseViewLeftSectionType:
            return _curvedPath.leftTransverseSectionPosition;
            break;
        case CPRTransverseViewCenterSectionType:
            return _curvedPath.transverseSectionPosition;
            break;
        case CPRTransverseViewRightSectionType:
            return _curvedPath.rightTransverseSectionPosition;
            break;
        default:
            assert(0);
            break;
    }
    return 0;
}

- (CPRBezierPath*)_requestBezierAndInitialNormal:(CPRVectorPointer)initialNormal
{
    CPRMutableBezierPath *bezierPath;
    CPRVector vector;
    CPRVector normal;
    CPRVector tangent;
    CPRVector cross;
    
    vector = [_curvedPath.bezierPath vectorAtRelativePosition:[self _relativeSegmentPosition]];
    tangent = [_curvedPath.bezierPath tangentAtRelativePosition:[self _relativeSegmentPosition]];
    normal = [_curvedPath.bezierPath normalAtRelativePosition:[self _relativeSegmentPosition] initialNormal:_curvedPath.initialNormal];
    
    cross = CPRVectorNormalize(CPRVectorCrossProduct(normal, tangent));
    
    bezierPath = [CPRMutableBezierPath bezierPath];
    [bezierPath moveToVector:CPRVectorAdd(vector, CPRVectorScalarMultiply(cross, _sectionWidth / 2))]; 
    [bezierPath lineToVector:CPRVectorAdd(vector, CPRVectorScalarMultiply(cross, -_sectionWidth / 2))]; 
    
    if (initialNormal) {
        *initialNormal = normal;
    }
    return bezierPath;
}
            
- (void)_setNeedsNewRequest
{
    _needsNewRequest = YES;
    [self performSelector:@selector(_sendNewRequestIfNeeded) withObject:nil afterDelay:0 inModes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
}

- (void)_sendNewRequestIfNeeded
{
    if (_needsNewRequest) {
        [self _sendNewRequest];
    }
}



@end








