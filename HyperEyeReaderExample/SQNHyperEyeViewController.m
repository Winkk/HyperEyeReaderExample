//
//  SQNHyperEyeViewController.m
//  HyperEyeReaderExample
//
//  Created by Konstantin Kalinin on 5/16/17.
//  Copyright © 2017 SQUARE NEST RESEARCH LABS, LLC. All rights reserved.
//

#import <GPUImage/GPUImage.h>

#import "SQNHyperEyeViewController.h"
#import <HyperEyeFramework/HyperEyeLib.h>

#define VIDEO_PRESET_4K AVCaptureSessionPreset3840x2160
#define VIDEO_PRESET_FULLHD AVCaptureSessionPreset1920x1080
#define VIDEO_PRESET_HD AVCaptureSessionPreset1280x720
#define VIDEO_PRESET_HIRES AVCaptureSessionPreset640x480

#define PINCH_ZOOM_MIN 1.0
#define PINCH_ZOOM_MAX 3.0

@interface SQNHyperEyeViewController () <SQNHyperEyeReaderDelegate>

@property (weak, nonatomic) IBOutlet UIView *cameraView;
@property (weak, nonatomic) IBOutlet UILabel *lbResult;

@end

@implementation SQNHyperEyeViewController
{
    // Object tracker
    CALayer *_objectTracker1;
    CALayer *_objectTracker2;
    BOOL _objectTrackerAnimation;
    CGRect _cameraViewTrackerFrame;
    CGRect _cameraTrackerFrame;
    float _zoomState;
    
    // Video
    AVCaptureDevicePosition _cameraPosition;
    GPUImageVideoCamera *_session;
    GPUImageView *_previewView;
    BOOL _setupPreviewLayer;
    int _video_width_camera;
    int _video_height_camera;
    CGAffineTransform _transformCameraToCameraView;
    CGAffineTransform _transformCameraViewToCamera;

    SQNHyperEyeReader *_hyperEyeReader;
}

#pragma mark - object tracker rectangle

- (void) initObjectTracker
{
    _objectTracker1 = [CALayer layer];
    _objectTracker1.frame = CGRectMake(-200,-200,100,100);
    _objectTracker1.borderColor = [UIColor colorWithRed:0.0f green:0.33f blue:0.0f alpha:0.7f].CGColor;
    _objectTracker1.borderWidth = 4;
    _objectTracker1.cornerRadius = 5;
    [self.cameraView.layer addSublayer:_objectTracker1];
    _objectTracker2 = [CALayer layer];
    _objectTracker2.frame = CGRectMake(-200,-200,100,100);
    _objectTracker2.borderColor = [UIColor colorWithRed:0.0f green:1.0f blue:0.0f alpha:0.7f].CGColor;
    _objectTracker2.borderWidth = 4;
    _objectTracker2.cornerRadius = 5;
    [self.cameraView.layer addSublayer:_objectTracker2];
    _zoomState = 1.f;
    
    [self setObjectTrackerRectHidden:YES];
}

- (void) setObjectTrackerRectHidden:(BOOL)hidden
{
    _objectTracker1.hidden = hidden;
    _objectTracker2.hidden = hidden;
    if (hidden) {
        _objectTracker1.frame = self.cameraView.bounds;
        _objectTracker2.frame = self.cameraView.bounds;
    }
}

- (void) setObjectTrackerFrameByCameraView:(CGRect)frame
{
    if (_objectTrackerAnimation) return;
    _objectTrackerAnimation = YES;
    frame = CGRectIntersection(frame, self.cameraView.bounds);
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.1f];
    _objectTracker1.frame = frame;
    _objectTracker2.frame = CGRectInset(frame, 4, 4);
    [CATransaction setCompletionBlock:^{ _objectTrackerAnimation = NO; }];
    [CATransaction commit];
}

#pragma mark - Pinch gesture for object tracker

- (IBAction) doPinchGesture:(UIPinchGestureRecognizer *)sender {
    float newZoom = _zoomState * sender.scale;
    newZoom = MAX(PINCH_ZOOM_MIN, newZoom);
    newZoom = MIN(PINCH_ZOOM_MAX, newZoom);
    if (sender.state == UIGestureRecognizerStateEnded || sender.state == UIGestureRecognizerStateCancelled || sender.state == UIGestureRecognizerStateFailed) {
        if (_hyperEyeReader.zoom != newZoom) {
            _hyperEyeReader.zoom = newZoom;
        }
        _zoomState = newZoom;
    }
    if (sender.state == UIGestureRecognizerStateChanged) {
        _previewView.transform = CGAffineTransformMakeScale(newZoom, newZoom);
    }
}

#pragma mark - GPUImage capture setup

- (void) initPreviewLayer
{
    if (!_session) return;
    // Configure preview layer
    
    int view_width = self.cameraView.bounds.size.width;
    int view_height = self.cameraView.bounds.size.height;
    int calc_width = view_height * _video_width_camera / _video_height_camera;
    int calc_height = view_width * _video_height_camera / _video_width_camera;
    int t;
    
    CGRect layerRect;
    
    if (calc_height >= view_height) {
        // Height will crop
        t = -(calc_height - view_height) / 2;
        layerRect = CGRectMake(
                               0,
                               t,
                               view_width,
                               calc_height
                               );
        _transformCameraToCameraView = CGAffineTransformConcat(CGAffineTransformMakeScale((float)view_width / _video_width_camera, (float)view_width / _video_width_camera), CGAffineTransformMakeTranslation(0, t));
    } else {
        // Width will crop
        t = -(calc_width - view_width) / 2;
        layerRect = CGRectMake(
                               t,
                               0,
                               calc_width,
                               view_height
                               );
        _transformCameraToCameraView = CGAffineTransformConcat(CGAffineTransformMakeScale((float)view_height / _video_height_camera, (float)view_height / _video_height_camera), CGAffineTransformMakeTranslation(t, 0));
    }
    _transformCameraViewToCamera = CGAffineTransformInvert(_transformCameraToCameraView);
    
    _previewView.frame = layerRect;
    
    
    AVCaptureVideoPreviewLayer *newCaptureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_session.captureSession];
    UIView *view = _previewView;
    CALayer *viewLayer = [view layer];
    
    newCaptureVideoPreviewLayer.frame = layerRect;
    
    [viewLayer addSublayer:newCaptureVideoPreviewLayer];
}

// Camera select method
+ (AVCaptureDevice *) deviceWithMediaType:(NSString *)mediaType preferringPosition:(AVCaptureDevicePosition)position
{
	NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
	AVCaptureDevice *captureDevice = [devices firstObject];
	
	for (AVCaptureDevice *device in devices)
	{
		if ([device position] == position)
		{
			captureDevice = device;
			break;
		}
	}
	
	return captureDevice;
}

- (void) initGPUImage
{
    _previewView = [[GPUImageView alloc] init];
    self.cameraView.layer.masksToBounds = YES;
    [self.cameraView insertSubview:_previewView atIndex:0];
}

- (void) initVideoCamera2:(AVCaptureDevicePosition)position
{
    _cameraPosition = position;
    
    // Find a suitable AVCaptureDevice
    AVCaptureDevice *device = [[self class] deviceWithMediaType:AVMediaTypeVideo preferringPosition:position];
    
    // Configure the session to produce resolution video frames
    NSString *sessionPreset;
    CGFloat iOSVersion = [[[UIDevice currentDevice] systemVersion] floatValue];
    if (iOSVersion>=9 && [device supportsAVCaptureSessionPreset:VIDEO_PRESET_4K]) {
                          sessionPreset = VIDEO_PRESET_4K;
    } else if ([device supportsAVCaptureSessionPreset:VIDEO_PRESET_FULLHD]) {
        sessionPreset = VIDEO_PRESET_FULLHD;
    } else if ([device supportsAVCaptureSessionPreset:VIDEO_PRESET_HD]) {
        sessionPreset = VIDEO_PRESET_HD;
    } else if ([device supportsAVCaptureSessionPreset:VIDEO_PRESET_HIRES]) {
        sessionPreset = VIDEO_PRESET_HIRES;
    } else {
        sessionPreset = AVCaptureSessionPresetMedium;
    }
    
    // Create the session
    _session = [[GPUImageVideoCamera alloc] initWithSessionPreset:sessionPreset cameraPosition:position];
    if (_session) {
        [_session setOutputImageOrientation:UIInterfaceOrientationPortrait];
        [_session setHorizontallyMirrorFrontFacingCamera:YES];
        [_session setHorizontallyMirrorRearFacingCamera:NO];
        
        AVCaptureVideoDataOutput *output = [[[_session captureSession] outputs] lastObject];
        NSDictionary *outputSettings = output.videoSettings;
        _video_height_camera = [[outputSettings objectForKey:@"Width"] intValue];
        _video_width_camera = [[outputSettings objectForKey:@"Height"] intValue];
        
    } else {
        [self showAlertWithString:nil];
    }
}

#pragma mark - Reader setup and delegate

- (void) initHyperEyeReader
{
    _hyperEyeReader = [[SQNHyperEyeReader alloc] initWithGPUImageVideoCamera:_session];
    _hyperEyeReader.delegate = self;
}

- (void)hyperEyeReader:(SQNHyperEyeReader *)reader hasRecognizedHyperEyeCode:(UInt64)code
{
    self.lbResult.text = [NSString stringWithFormat:@"%llu", code];
}

#pragma mark - View controller related stuff

- (void) viewDidLoad
{
    [super viewDidLoad];
    
    // Init GPUImage
    [self initGPUImage];
    
    // Init video input
    [self initVideoCamera2:AVCaptureDevicePositionBack];
    
    // Init reader
    [self initHyperEyeReader];
    
    // Object tracker
    [self initObjectTracker];
    
    // Set flags for layout
    _setupPreviewLayer = YES;
    
    // Application focus
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    
    // Begin frame processing
    [_hyperEyeReader beginFrameProcessing];
}

- (void) viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    
    if (_setupPreviewLayer) {
        _setupPreviewLayer = NO;
        [self initPreviewLayer];
        
        CGFloat width = CGRectGetWidth(self.cameraView.frame);
        CGFloat height = CGRectGetHeight(self.cameraView.frame);
    
        _cameraViewTrackerFrame = CGRectMake(width / 2 - width / 4, height / 2 - width / 4, width / 2, width / 2);
        _cameraTrackerFrame = CGRectApplyAffineTransform(_cameraViewTrackerFrame, _transformCameraViewToCamera);
        _cameraTrackerFrame.origin.x = (int)(_cameraTrackerFrame.origin.x + 0.5f);
        _cameraTrackerFrame.origin.y = (int)(_cameraTrackerFrame.origin.y + 0.5f);
        _cameraTrackerFrame.size.width = (int)(_cameraTrackerFrame.size.width + 0.5f);
        _cameraTrackerFrame.size.height = (int)(_cameraTrackerFrame.size.height + 0.5f);
        
        [self setObjectTrackerFrameByCameraView:_cameraViewTrackerFrame];
        [self setObjectTrackerRectHidden:NO];
        
        // Setup an area for HyperEyeReader to detect objects in
        [_hyperEyeReader setCameraTrackerFrame:_cameraTrackerFrame];
    }
}

- (void) didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) dealloc
{
    NSLog(@"View controller %@ deallocated", NSStringFromClass([self class]));
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) showAlertWithString:(NSString*) message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Capture error", nil) message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:NO completion:nil];
}

#pragma mark - appearing/disappearing/losing focus/receiving focus

// If a window disappears, or application loses focus, capturing and processing should be stopped to avoid battery drain.
- (void) deactivateCapture
{
    // Stop video stream
    [_session stopCameraCapture];
    
    NSLog(@"Capture window disappear");
}

// If a window appears or application becomes active, continue capturing from idle state.
- (void) activateCapture
{
    // Resume video stream
    [_session startCameraCapture];
    
    NSLog(@"Capture window appear");
}

- (void) applicationWillResignActive
{
    [self deactivateCapture];
}

- (void) applicationDidBecomeActive
{
    [self activateCapture];
}

- (void) viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    [self deactivateCapture];
}

- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self activateCapture];
}

#pragma mark - Some user actions

- (IBAction) saveImageAction:(id)sender
{
    [_hyperEyeReader requestSavingImageToCameraRoll];
}

- (IBAction) beginProcessingAction:(id)sender {
    [_hyperEyeReader beginFrameProcessing];
}

- (IBAction) stopProcessingAction:(id)sender {
    [_hyperEyeReader stopFrameProcessing];
}

#pragma mark - orientation

- (BOOL)shouldAutorotate
{
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return (UIInterfaceOrientationMaskPortrait);
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationPortrait;
}

@end
