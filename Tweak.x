#include <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
// #import "util.h"

static NSFileManager *g_fileManager = nil; // 文件管理对象
static UIPasteboard *g_pasteboard = nil; // 剪贴板对象
static BOOL g_canReleaseBuffer = YES; // 根据此标识检测是否可以释放buffer
static BOOL g_bufferReload = YES; // 根据此标识判断是否需要重新刷新视频文件
static AVSampleBufferDisplayLayer *g_previewLayer = nil; // 原生相机预览
static BOOL g_haveVideoDataOutput = NO; // 如果存在 VideoDataOutput, 预览画面会同步VideoDataOutput的画面, 如果没有则会直接读取视频显示
static BOOL g_cameraRunning = NO;

NSString *g_tempFile = @"/var/mobile/Library/Caches/temp.mov"; // 临时文件位置

// 原生相机预览处理
/*AVPlayer *g_player = nil;
AVPlayerLayer *g_previewLayer = nil;
AVPlayerItemVideoOutput *g_playerOutput = nil;
CVPixelBufferRef g_pixelBuffer = nil;*/


@interface GetFrame : NSObject
+ (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef) originSampleBuffer;
+ (UIWindow*)getKeyWindow;
@end

@implementation GetFrame
+ (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef _Nullable) originSampleBuffer{
    static AVAssetReader *reader = nil;
    static AVAssetReaderTrackOutput *trackout = nil;
    static CMSampleBufferRef sampleBuffer = nil;
    static BOOL previewBuffer = NO;

    // 没有替换视频则使用原来的数据
    if ([g_fileManager fileExistsAtPath:g_tempFile] == NO) return originSampleBuffer;
    if (sampleBuffer != nil && !g_canReleaseBuffer) return sampleBuffer; // 不能释放buffer时返回上一个buffer

    // 如果上一次是预览，但是获得了新的output输出就按照originSampleBuffer生成新的reader pool
    if (originSampleBuffer != nil && previewBuffer) {
        g_bufferReload = YES;
        NSLog(@"新的buffer");
    }

    if (originSampleBuffer == nil) {
        static NSTimeInterval previewReadTime = 0;
        if (previewReadTime == 0 || previewBuffer == NO) {
            previewReadTime = ([[NSDate date] timeIntervalSince1970] + 1) * 1000;
        }
        previewBuffer = YES; // 当前为纯视频预览
        NSTimeInterval nowTime = [[NSDate date] timeIntervalSince1970] * 1000;
        // TODO:: 帧率控制，锁定在了30帧
        if ((nowTime - previewReadTime) <= (1000 / 33)) return nil;
        previewReadTime = nowTime;
    } else {
        previewBuffer = NO; // 当前借用 VideoDataOutput 预览
    }

    static NSTimeInterval renewTime = 0;
    // 选择了新的替换视频
    if ([g_fileManager fileExistsAtPath:[NSString stringWithFormat:@"%@.new", g_tempFile]]) {
        NSTimeInterval nowTime = [[NSDate date] timeIntervalSince1970];
        if (nowTime - renewTime > 3) {
            renewTime = nowTime;
            g_bufferReload = YES;
        }
    }

    // 播放完成重新读取
    if (reader != nil && [reader status] != AVAssetReaderStatusReading) {
        g_bufferReload = YES;
    }

    if (g_bufferReload) {
        g_bufferReload = NO;
        // AVAsset *asset = [AVAsset assetWithURL: [NSURL URLWithString:downloadFilePath]];
        AVAsset *asset = [AVAsset assetWithURL: [NSURL URLWithString:[NSString stringWithFormat:@"file://%@", g_tempFile]]];
        reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
        
        AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject]; // 获取轨道
        // kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange  : YUV420 用于标清视频[420v]
        // kCVPixelFormatType_420YpCbCr8BiPlanarFullRange   : YUV422 用于高清视频[420f] 
        // kCVPixelFormatType_32BGRA : 输出的是BGRA的格式，适用于OpenGL和CoreImage

        OSType type = kCVPixelFormatType_32BGRA;
        if (originSampleBuffer != nil) {
            type = CVPixelBufferGetPixelFormatType(CMSampleBufferGetImageBuffer(originSampleBuffer));
        }
        NSDictionary *readerOutputSettings = @{(id)kCVPixelBufferPixelFormatTypeKey:@(type)}; // 将视频帧解压缩为 32 位 BGRA 格式

        trackout = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:readerOutputSettings];
        
        [reader addOutput:trackout];
        [reader startReading];
        // NSLog(@"这是初始化读取");
    }
    // NSLog(@"刷新了");

    // TODO:: 这个buffer还需要一些调整
    CMSampleBufferRef newsampleBuffer = [trackout copyNextSampleBuffer];
    if (newsampleBuffer != nil) {
        if (sampleBuffer != nil) CFRelease(sampleBuffer);
        sampleBuffer = newsampleBuffer;
        if (originSampleBuffer == nil) { // 处理新的buffer  - 预览的buffer
            // CMSampleBufferSetOutputPresentationTimeStamp(sampleBuffer, [[NSDate date] timeIntervalSince1970] * 1000);
        }else { //  处理新的buffer  - videooutput的buffer
            CMSampleBufferSetOutputPresentationTimeStamp(sampleBuffer, CMSampleBufferGetOutputPresentationTimeStamp(originSampleBuffer));
        }
    }
    return sampleBuffer;
}
// 下载文件
-(NSString*)downloadFile:(NSString*)url{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString  *documentsDirectory = [paths objectAtIndex:0];
    NSString  *filePath = [NSString stringWithFormat:@"%@/%@", documentsDirectory,@"temp.mp4"];
    NSString *downloadFilePath = nil;
    if ([g_fileManager fileExistsAtPath:filePath]){
        downloadFilePath = [NSString stringWithFormat:@"file://%@", filePath];
    }else {
        if (downloadFilePath == nil) {
            NSLog(@"开始下载 url = %@", url);
            downloadFilePath = @"正在下载";
            NSData *urlData = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
            if (urlData) {
                if ([urlData writeToFile:filePath atomically:YES]){
                    downloadFilePath = [NSString stringWithFormat:@"file://%@", filePath];
                    NSLog(@"保存完成 downloadFilePath = %@", downloadFilePath);
                }else {
                    downloadFilePath = nil;
                    NSLog(@"保存失败 downloadFilePath = %@", downloadFilePath);
                }
            }
        }else {
            NSLog(@"暂停下载 url = %@", url);
        }
    }
    return downloadFilePath;
}
+(UIWindow*)getKeyWindow{
    // need using [GetFrame getKeyWindow].rootViewController
    UIWindow *keyWindow = nil;
    if (keyWindow == nil) {
        NSArray *windows = UIApplication.sharedApplication.windows;
        for(UIWindow *window in windows){
            if(window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
    }
    return keyWindow;
}
@end

%hook AVCaptureVideoPreviewLayer
- (void)addSublayer:(CALayer *)layer{
    %orig;
    // self.opacity = 0;
    // self.borderColor = [UIColor blackColor].CGColor;

    static CADisplayLink *displayLink = nil;
    if (displayLink == nil) {
        displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(step:)];
        [displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    }

    // 播放条目
    if ([g_fileManager fileExistsAtPath:g_tempFile] && ![[self sublayers] containsObject:g_previewLayer]) {
        g_previewLayer = [[AVSampleBufferDisplayLayer alloc] init];
        [g_previewLayer setVideoGravity:AVLayerVideoGravityResize];

        // black mask
        CALayer *mask = [CALayer new];
        mask.backgroundColor = [UIColor blackColor].CGColor;
        [self insertSublayer:mask above:layer];
        [self insertSublayer:g_previewLayer above:mask];

        // layer size init
        dispatch_async(dispatch_get_main_queue(), ^{
            g_previewLayer.frame = [UIApplication sharedApplication].keyWindow.bounds;
            mask.frame = [UIApplication sharedApplication].keyWindow.bounds;
        });
        // NSLog(@"添加了 %@", [self sublayers]);
    }
}
%new
-(void)step:(CADisplayLink *)sender{
    // NSLog(@"我被调用了");
    if (g_cameraRunning && g_previewLayer != nil) {
        // NSLog(@"g_previewLayer.readyForMoreMediaData %@ %@", g_previewLayer.readyForMoreMediaData?@"yes":@"no", g_haveVideoDataOutput?@"yes":@"no");
        g_previewLayer.frame = self.bounds;
        static CMSampleBufferRef copyBuffer = nil;
        if (!g_haveVideoDataOutput && g_previewLayer.readyForMoreMediaData) {
            CMSampleBufferRef newBuffer = [GetFrame getCurrentFrame:nil];
            if (newBuffer != nil) {
                [g_previewLayer flush];
                if (copyBuffer != nil) CFRelease(copyBuffer);
                CMSampleBufferCreateCopy(kCFAllocatorDefault, newBuffer, &copyBuffer);
                if (copyBuffer != nil) [g_previewLayer enqueueSampleBuffer:copyBuffer];
            }
        }
    }
}
%end


%hook AVCaptureSession
-(void) startRunning {
    g_cameraRunning = YES;
    g_bufferReload = YES;
    g_haveVideoDataOutput = NO;
	NSLog(@"开始使用摄像头了， 预设值是 %@", [self sessionPreset]);
	%orig;
}
-(void) stopRunning {
    g_cameraRunning = NO;
	NSLog(@"停止使用摄像头了");
    g_haveVideoDataOutput = YES;
	%orig;
}
- (void)addInput:(AVCaptureDeviceInput *)input {
    if ([[input device] position] > 0) {
        // [CCNotice notice:@"开始使用前置摄像头" :[NSString stringWithFormat:@"format=%@", [[input device] activeFormat]]];
        NSDate *datenow = [NSDate date];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"YYYY-MM-dd HH:mm:ss"];

        AVCaptureDeviceFormat *activeFormat = [[input device] activeFormat];

        NSString *format= [NSString stringWithFormat:@"%@", activeFormat];

        NSString *str = [NSString stringWithFormat:@"%@\n%@-%@\n%@",
            [formatter stringFromDate:datenow],
            [NSProcessInfo processInfo].processName,
            [[input device] position] == 1 ? @"back" : @"front", 
            [NSString stringWithFormat:@"<%@", [format substringFromIndex: 36]]
        ];
        NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];

        [g_pasteboard setString:[NSString stringWithFormat:@"CCVCAM%@", [data base64EncodedStringWithOptions:0]]];
    }
    g_haveVideoDataOutput = NO;
 	// NSLog(@"添加了一个输入设备 %@", [[input device] activeFormat]);
	%orig;
}
- (void)addOutput:(AVCaptureOutput *)output{
	NSLog(@"添加了一个输出设备 %@", output);
    g_haveVideoDataOutput = NO;
	%orig;
}
%end


%hook AVCaptureStillImageOutput
- (void)captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection completionHandler:(void (^)(CMSampleBufferRef imageDataSampleBuffer, NSError *error))handler{
    g_canReleaseBuffer = NO;
    NSLog(@"拍照了 %@", handler);
    void (^newHandler)(CMSampleBufferRef imageDataSampleBuffer, NSError *error) = ^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
        NSLog(@"拍照调用 %@", handler);
        handler([GetFrame getCurrentFrame:imageDataSampleBuffer], error);
        g_canReleaseBuffer = YES;
    };
    %orig(connection, [newHandler copy]);
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate{
    if (settings == nil || delegate == nil) return %orig;
    static NSMutableArray *hooked;
    if (hooked == nil) hooked = [NSMutableArray new];
    NSString *className = NSStringFromClass([delegate class]);
    if ([hooked containsObject:className] == NO) {
        [hooked addObject:className];

        if (@available(iOS 10.0, *)) {
            __block void (*original_method)(id self, SEL _cmd, AVCapturePhotoOutput *output, CMSampleBufferRef photoSampleBuffer, CMSampleBufferRef previewPhotoSampleBuffer, AVCaptureResolvedPhotoSettings *resolvedSettings, AVCaptureBracketedStillImageSettings *bracketSettings, NSError *error) = nil;
            MSHookMessageEx(
                [delegate class], @selector(captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:),
                imp_implementationWithBlock(^(id self, AVCapturePhotoOutput *output, CMSampleBufferRef photoSampleBuffer, CMSampleBufferRef previewPhotoSampleBuffer, AVCaptureResolvedPhotoSettings *resolvedSettings, AVCaptureBracketedStillImageSettings *bracketSettings, NSError *error){
                    g_canReleaseBuffer = NO;
                    
                    static CMSampleBufferRef copyBuffer = nil;
                    CMSampleBufferRef newBuffer = [GetFrame getCurrentFrame:photoSampleBuffer];
                    if (newBuffer != nil) {
                        if (copyBuffer != nil) CFRelease(copyBuffer); // 加上这句 中途取消替换的时候会闪退
                        CMSampleBufferRef copyBuffer = nil;
                        CMSampleBufferCreateCopy(kCFAllocatorDefault, newBuffer, &copyBuffer);

                        // photoSampleBuffer = copyBuffer;

                        NSLog(@"新的buffer = %@", copyBuffer);
                        NSLog(@"旧的buffer = %@", photoSampleBuffer);
                        NSLog(@"旧的previewPhotoSampleBuffer = %@", previewPhotoSampleBuffer);
                    }
                    g_canReleaseBuffer = YES;

                    NSLog(@"captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:");
                    // photoSampleBuffer = newPhotoBuffer;
                    // previewPhotoSampleBuffer = newPhotoBuffer;
                    return original_method(self, @selector(captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:), output, photoSampleBuffer, previewPhotoSampleBuffer, resolvedSettings, bracketSettings, error);
                }), (IMP*)&original_method
            );
            __block void (*original_method2)(id self, SEL _cmd, AVCapturePhotoOutput *output, CMSampleBufferRef rawSampleBuffer, CMSampleBufferRef previewPhotoSampleBuffer, AVCaptureResolvedPhotoSettings *resolvedSettings, AVCaptureBracketedStillImageSettings *bracketSettings, NSError *error) = nil;
            MSHookMessageEx(
                [delegate class], @selector(captureOutput:didFinishProcessingRawPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:),
                imp_implementationWithBlock(^(id self, AVCapturePhotoOutput *output, CMSampleBufferRef rawSampleBuffer, CMSampleBufferRef previewPhotoSampleBuffer, AVCaptureResolvedPhotoSettings *resolvedSettings, AVCaptureBracketedStillImageSettings *bracketSettings, NSError *error){
                    static CMSampleBufferRef copyBuffer = nil;
                    if (copyBuffer != nil) CFRelease(copyBuffer);

                    CMSampleBufferCreateCopy(kCFAllocatorDefault, [GetFrame getCurrentFrame:nil], &copyBuffer);
                    __block CMSampleBufferRef newPhotoBuffer = copyBuffer;

                    g_canReleaseBuffer = YES;

                    if (newPhotoBuffer != nil) {
                        NSLog(@"-=--=新的buffer = %@", newPhotoBuffer);
                    }

                    NSLog(@"---raw->captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:");
                    // rawSampleBuffer = newPhotoBuffer;
                    // previewPhotoSampleBuffer = newPhotoBuffer;
                    return original_method2(self, @selector(captureOutput:didFinishProcessingRawPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:), output, rawSampleBuffer, previewPhotoSampleBuffer, resolvedSettings, bracketSettings, error);
                }), (IMP*)&original_method2
            );
        }

        if (@available(iOS 11.0, *)){ // iOS 11 之后
            __block void (*original_method)(id self, SEL _cmd, AVCapturePhotoOutput *captureOutput, AVCapturePhoto *photo, NSError *error) = nil;
            MSHookMessageEx(
                [delegate class], @selector(captureOutput:didFinishProcessingPhoto:error:),
                imp_implementationWithBlock(^(id self, AVCapturePhotoOutput *captureOutput, AVCapturePhoto *photo, NSError *error){
                    g_canReleaseBuffer = NO;
                    
                    static CMSampleBufferRef copyBuffer = nil;
                    
                    CMSampleBufferRef newBuffer = [GetFrame getCurrentFrame:nil];
                    if (newBuffer != nil) { // 如果存在新的替换数据则挂钩属性
                        if (copyBuffer != nil) CFRelease(copyBuffer);
                        CMSampleBufferCreateCopy(kCFAllocatorDefault, newBuffer, &copyBuffer);

                        __block CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(copyBuffer);
                        CIImage *ciimage = [CIImage imageWithCVImageBuffer:imageBuffer];
                        __block UIImage *uiimage = [UIImage imageWithCIImage:ciimage];
                        __block NSData *theNewPhoto = UIImageJPEGRepresentation(uiimage, .0);

                        // 获取到了新的buffer之后开始挂钩属性
                        __block NSData *(*fileDataRepresentationWithCustomizer)(id self, SEL _cmd, id<AVCapturePhotoFileDataRepresentationCustomizer> customizer);
                        MSHookMessageEx(
                            [photo class], @selector(fileDataRepresentationWithCustomizer:),
                            imp_implementationWithBlock(^(id self, SEL _cmd, id<AVCapturePhotoFileDataRepresentationCustomizer> customizer){
                                NSLog(@"fileDataRepresentationWithCustomizer");
                                return theNewPhoto;
                            }), (IMP*)&fileDataRepresentationWithCustomizer
                        );

                        __block NSData *(*fileDataRepresentation)(id self, SEL _cmd);
                        MSHookMessageEx(
                            [photo class], @selector(fileDataRepresentation),
                            imp_implementationWithBlock(^(id self, SEL _cmd){
                                // NSData *thefileDataRepresentation = fileDataRepresentation(self, @selector(fileDataRepresentation));
                                // NSLog(@"拦截成功 %@", thefileDataRepresentation);
                                NSLog(@"fileDataRepresentation");
                                return theNewPhoto;
                            }), (IMP*)&fileDataRepresentation
                        );

                        __block CVPixelBufferRef *(*previewPixelBuffer)(id self, SEL _cmd);
                        MSHookMessageEx(
                            [photo class], @selector(previewPixelBuffer),
                            imp_implementationWithBlock(^(id self, SEL _cmd){
                                NSLog(@"previewPixelBuffer");
                                // RotatePixelBufferToAngle(imageBuffer, radians(-90));
                                return nil;
                            }), (IMP*)&previewPixelBuffer
                        );

                        __block CVPixelBufferRef *(*pixelBuffer)(id self, SEL _cmd);
                        MSHookMessageEx(
                            [photo class], @selector(pixelBuffer),
                            imp_implementationWithBlock(^(id self, SEL _cmd){
                                NSLog(@"pixelBuffer");
                                return imageBuffer;
                            }), (IMP*)&pixelBuffer
                        );

                        __block CGImageRef *(*CGImageRepresentation)(id self, SEL _cmd);
                        MSHookMessageEx(
                            [photo class], @selector(CGImageRepresentation),
                            imp_implementationWithBlock(^(id self, SEL _cmd){
                                NSLog(@"CGImageRepresentation");
                                return uiimage.CGImage;
                            }), (IMP*)&CGImageRepresentation
                        );

                        __block CGImageRef *(*previewCGImageRepresentation)(id self, SEL _cmd);
                        MSHookMessageEx(
                            [photo class], @selector(previewCGImageRepresentation),
                            imp_implementationWithBlock(^(id self, SEL _cmd){
                                NSLog(@"previewCGImageRepresentation");
                                return uiimage.CGImage;
                            }), (IMP*)&previewCGImageRepresentation
                        );
                    }
                    g_canReleaseBuffer = YES;
                    
                    // NSLog(@"原生拍照了 previewPixelBuffer = %@", photo.previewPixelBuffer );
                    // NSLog(@"原生拍照了 fileDataRepresentatio = %@", [photo fileDataRepresentation]);

                    return original_method(self, @selector(captureOutput:didFinishProcessingPhoto:error:), captureOutput, photo, error);
                }), (IMP*)&original_method
            );
        }
    }
    
    NSLog(@"capturePhotoWithSettings--->[%@]   [%@]", settings, delegate);
    %orig;
}
%end

%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue{
    // NSLog(@"sampleBufferDelegate--->%@", [sampleBufferDelegate class]); // TODO:: 同一个软件可能会有不同的代理对象，需要每个对象替换一次
    if (sampleBufferDelegate == nil || sampleBufferCallbackQueue == nil) return %orig;
    static NSMutableArray *hooked;
    if (hooked == nil) hooked = [NSMutableArray new];
    NSString *className = [NSString stringWithFormat:@"%p", [sampleBufferDelegate class]];
    if ([hooked containsObject:className] == NO) {
        [hooked addObject:className];
        __block void (*original_method)(id self, SEL _cmd, AVCaptureOutput *output, CMSampleBufferRef sampleBuffer, AVCaptureConnection *connection) = nil;
        // NSLog(@"准备hook-->%@ %p", [sampleBufferDelegate class], original_method);

        // NSLog(@"---------> AVCaptureVideoDataOutput -> videoSettings = %@", [self videoSettings]);
        // 先动态hook然后调用原始方法使用这个queue
        MSHookMessageEx(
            [sampleBufferDelegate class], @selector(captureOutput:didOutputSampleBuffer:fromConnection:),
            imp_implementationWithBlock(^(id self, AVCaptureOutput *output, CMSampleBufferRef sampleBuffer, AVCaptureConnection *connection){
                // NSLog(@"求求你了，出现吧! 【self = %@】 params = %p", self, original_method);
                g_haveVideoDataOutput = YES;
                CMSampleBufferRef newBuffer = [GetFrame getCurrentFrame:sampleBuffer];
                if (newBuffer != nil) {
                    sampleBuffer = newBuffer;
                }
                // 用buffer来刷新预览
                if (g_previewLayer != nil && g_previewLayer.readyForMoreMediaData) {
                    static CMSampleBufferRef copyBuffer = nil;
                    if (copyBuffer != nil) CFRelease(copyBuffer); 
                    CMSampleBufferCreateCopy(kCFAllocatorDefault, sampleBuffer, &copyBuffer);
                    [g_previewLayer flush];
                    [g_previewLayer enqueueSampleBuffer:copyBuffer];
                }
                return original_method(self, @selector(captureOutput:didOutputSampleBuffer:fromConnection:), output, sampleBuffer, connection);
            }), (IMP*)&original_method
        );
    }
	// NSLog(@"AVCaptureVideoDataOutput -> setSampleBufferDelegate [%@] [%@]", sampleBufferDelegate, sampleBufferCallbackQueue);
	%orig;
}
%end

// 元数据
// %hook AVCaptureMetadataOutput
// - (void)setMetadataObjectsDelegate:(id<AVCaptureMetadataOutputObjectsDelegate>)objectsDelegate queue:(dispatch_queue_t)objectsCallbackQueue{
//     if (objectsDelegate == nil || objectsCallbackQueue == nil) {
//         NSLog(@"咋是空的啊 AVCaptureMetadataOutput");
//         return %orig;
//     }
//     static void *(*original_method)(id self, SEL _cmd, AVCaptureOutput *output, NSArray<__kindof AVMetadataObject *> *metadataObjects, AVCaptureConnection *connection) = NULL;
//     if (original_method == NULL) {
//         NSLog(@"挂钩setMetadataObjectsDelegate");
//         MSHookMessageEx(
//             [objectsDelegate class], @selector(captureOutput:didOutputMetadataObjects:fromConnection:),
//             imp_implementationWithBlock(^(id self, AVCaptureOutput *output, NSArray<__kindof AVMetadataObject *> *metadataObjects, AVCaptureConnection *connection){
//                 // NSLog(@"捕获到元数据 %@", metadataObjects);

//                 original_method(self, @selector(captureOutput:didOutputMetadataObjects:fromConnection:), output, metadataObjects, connection);
//             }), (IMP*)&original_method
//         );
//     }
// 	NSLog(@"AVCaptureMetadataOutput -> setMetadataObjectsDelegate [%@]   [%@]", objectsDelegate, objectsCallbackQueue);
// 	%orig;
// }
// %end


// UI
@interface CCUIImagePickerDelegate : NSObject <UINavigationControllerDelegate,UIImagePickerControllerDelegate>
@end
@implementation CCUIImagePickerDelegate
// 选择图片成功调用此方法
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    [[GetFrame getKeyWindow].rootViewController dismissViewControllerAnimated:YES completion:nil];
    NSLog(@"%@", info);
    // NSString *result = @"应用失败!";
    // 选择的图片信息存储于info字典中
    NSString *selectFile = info[@"UIImagePickerControllerMediaURL"];
    if ([g_fileManager fileExistsAtPath:g_tempFile]) [g_fileManager removeItemAtPath:g_tempFile error:nil];

    if ([g_fileManager copyItemAtPath:selectFile toPath:g_tempFile error:nil]) {
        [g_fileManager createDirectoryAtPath:[NSString stringWithFormat:@"%@.new", g_tempFile] withIntermediateDirectories:YES attributes:nil error:nil];
        // result = @"应用成功!";
        sleep(1);
        [g_fileManager removeItemAtPath:[NSString stringWithFormat:@"%@.new", g_tempFile] error:nil];  
    }
    // UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"VCAM" message:result preferredStyle:UIAlertControllerStyleAlert];
    // UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"oj8k" style:UIAlertActionStyleDefault handler:nil];
    // [alertController addAction:cancel];
    // [[GetFrame getKeyWindow].rootViewController presentViewController:alertController animated:YES completion:nil];

}
// 取消图片选择调用此方法
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [[GetFrame getKeyWindow].rootViewController dismissViewControllerAnimated:YES completion:nil];
    // selectFile = nil;
}
@end


// UI
static NSTimeInterval g_volume_up_time = 0;
static NSTimeInterval g_volume_down_time = 0;

%hook VolumeControl
-(void)increaseVolume {
    // NSLog(@"增加了音量？%@", [NSThread currentThread]);
    // NSLog(@"开始下载了");
    // NSString *file = [[GetFrame alloc] downloadFile:@"http://192.168.1.3:8080/nier.mp4"];
    // NSLog(@"下载完成了file = %@", file);
    NSTimeInterval nowtime = [[NSDate date] timeIntervalSince1970];
    if (g_volume_down_time != 0 && nowtime - g_volume_down_time < 1) {
        static CCUIImagePickerDelegate *delegate = nil;
        if (delegate == nil) delegate = [CCUIImagePickerDelegate new];
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.mediaTypes = [NSArray arrayWithObjects:@"public.movie",/* @"public.image",*/ nil];
        picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
        picker.allowsEditing = YES;
        picker.delegate = delegate;
        [[GetFrame getKeyWindow].rootViewController presentViewController:picker animated:YES completion:nil];
    }
    g_volume_up_time = nowtime;
    %orig;
}
-(void)decreaseVolume {
    static CCUIImagePickerDelegate *delegate = nil;
    if (delegate == nil) delegate = [CCUIImagePickerDelegate new];

    NSTimeInterval nowtime = [[NSDate date] timeIntervalSince1970];
    if (g_volume_up_time != 0 && nowtime - g_volume_up_time < 1) {

        // 剪贴板上的分辨率信息
        NSString *str = g_pasteboard.string;
        NSString *infoStr = @"";
        if (str != nil && [str hasPrefix:@"CCVCAM"]) {
            str = [str substringFromIndex:6]; //截取掉下标3之后的字符串
            // NSLog(@"获取到的字符串是:%@", str);
            NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:str options:0];
            NSString *decodedString = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
            infoStr = decodedString;
            // NSLog(@"-----=-=-=-=--=-=-%@", decodedString);
        }

        static CCUIImagePickerDelegate *delegate = nil;
        if (delegate == nil)  delegate = [CCUIImagePickerDelegate new];
        
        // 提示视频质量
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"虚拟📷" message:infoStr preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *next = [UIAlertAction actionWithTitle:@"选择视频" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            // 选择视频
            UIImagePickerController *picker = [[UIImagePickerController alloc] init];
            picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
            picker.mediaTypes = [NSArray arrayWithObjects:@"public.movie",/* @"public.image",*/ nil];
            picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
            picker.allowsEditing = YES;
            picker.delegate = delegate;
            [[GetFrame getKeyWindow].rootViewController presentViewController:picker animated:YES completion:nil];
        }];
        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消操作" style:UIAlertActionStyleDefault handler:nil];
        UIAlertAction *cancelReplace = [UIAlertAction actionWithTitle:@"禁用替换" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            if ([g_fileManager fileExistsAtPath:g_tempFile]) [g_fileManager removeItemAtPath:g_tempFile error:nil];
        }];
        [alertController addAction:next];
        [alertController addAction:cancelReplace];
        [alertController addAction:cancel];
        [[GetFrame getKeyWindow].rootViewController presentViewController:alertController animated:YES completion:nil];
    }
    g_volume_down_time = nowtime;
    %orig;

    // NSLog(@"减小了音量？%@ %@", [NSProcessInfo processInfo].processName, [NSProcessInfo processInfo].hostName);
    // %orig;
}
%end


%ctor {
	NSLog(@"我被载入成功啦");
    if([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){13, 0, 0}]) {
        %init(VolumeControl = NSClassFromString(@"SBVolumeControl"));
    }
    // if ([[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"] isEqual:@"com.apple.springboard"]) {
    // NSLog(@"我在哪儿啊 %@ %@", [NSProcessInfo processInfo].processName, [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"]);
    // }
    g_fileManager = [NSFileManager defaultManager];
    g_pasteboard = [UIPasteboard generalPasteboard];
}