#include <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
// #import "util.h"

static NSFileManager *g_fileManager = nil; // 文件管理对象
static UIPasteboard *g_pasteboard = nil; // 剪贴板对象
static BOOL g_lockeBuffer = NO; // 根据此标识检测是否锁定buffer
static BOOL g_bufferReload = YES; // 根据此标识判断是否需要重新刷新视频文件
static NSTimeInterval g_bufferReloadTime = 0;
static AVSampleBufferDisplayLayer *g_previewLayer = nil; // 原生相机预览
static NSTimeInterval g_refreshPreviewByVideoDataOutputTime = 0; // 如果存在 VideoDataOutput, 预览画面会同步VideoDataOutput的画面, 如果没有则会直接读取视频显示
static BOOL g_cameraRunning = NO;

NSString *g_tempFile = @"/var/mobile/Library/Caches/temp.mov"; // 临时文件位置


@interface GetFrame : NSObject
+ (NSDictionary*)getCurrentFrame;
+ (UIWindow*)getKeyWindow;
@end

@implementation GetFrame
+ (NSDictionary*)getCurrentFrame{
    static AVAssetReader *reader = nil;

    // static AVAssetReaderTrackOutput *videoTrackout = nil;
    static AVAssetReaderTrackOutput *videoTrackout_kCVPixelFormatType_32BGRA = nil;
    static AVAssetReaderTrackOutput *videoTrackout_kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange = nil;
    static AVAssetReaderTrackOutput *videoTrackout_kCVPixelFormatType_420YpCbCr8BiPlanarFullRange = nil;

    static NSDictionary *sampleBuffer = nil;

    // static NSTimeInterval refreshTime = 0;
    // NSTimeInterval nowTime = [[NSDate date] timeIntervalSince1970] * 1000;
    // if (sampleBuffer != nil && nowTime - refreshTime < 1000 / 33) {
    //     refreshTime = nowTime;
    //     NSLog(@"帧率太快了");
    //     return sampleBuffer;
    // }

    // 没有替换视频则返回nil以便使用原来的数据
    if ([g_fileManager fileExistsAtPath:g_tempFile] == NO) return nil;
    // if (g_lockeBuffer && sampleBuffer != nil) return sampleBuffer; // 不能释放buffer时返回上一个buffer

    // 当前时间
    NSTimeInterval nowTime = [[NSDate date] timeIntervalSince1970];

    static NSTimeInterval renewTime = 0;
    // 选择了新的替换视频
    if ([g_fileManager fileExistsAtPath:[NSString stringWithFormat:@"%@.new", g_tempFile]]) {
        if (nowTime - renewTime > 3) {
            renewTime = nowTime;
            g_bufferReload = YES;
        }
    }
    @try{
        if (g_bufferReload) {
            g_bufferReload = NO;
            if (nowTime - g_bufferReloadTime < 3) {
                return sampleBuffer;
            }
            g_bufferReloadTime = nowTime;
            // AVAsset *asset = [AVAsset assetWithURL: [NSURL URLWithString:downloadFilePath]];
            AVAsset *asset = [AVAsset assetWithURL: [NSURL URLWithString:[NSString stringWithFormat:@"file://%@", g_tempFile]]];
            reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
            
            // video track
            AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject]; // 获取轨道

            // videoTrackout = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:nil];
            // [reader addOutput:videoTrackout];

            // AVAssetTrack *videoTrack2 = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject]; // 获取轨道
            // kCVPixelFormatType_32BGRA : 输出的是BGRA的格式，适用于OpenGL和CoreImage
            NSDictionary *readerOutputSettings = @{
                (id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)
            }; // 将视频帧解压缩为 32 位 BGRA 格式
            videoTrackout_kCVPixelFormatType_32BGRA = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:readerOutputSettings];
            [reader addOutput:videoTrackout_kCVPixelFormatType_32BGRA];

            // AVAssetTrack *videoTrack3 = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject]; // 获取轨道
            // kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange  : YUV420 用于标清视频[420v]
            videoTrackout_kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)}];
            [reader addOutput:videoTrackout_kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange];

            // AVAssetTrack *videoTrack4 = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject]; // 获取轨道
            // kCVPixelFormatType_420YpCbCr8BiPlanarFullRange   : YUV422 用于高清视频[420f] 
            videoTrackout_kCVPixelFormatType_420YpCbCr8BiPlanarFullRange = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)}];
            [reader addOutput:videoTrackout_kCVPixelFormatType_420YpCbCr8BiPlanarFullRange];

            [reader startReading];
            NSLog(@"这是初始化读取 %@", [NSThread currentThread]);
        }

        // CMSampleBufferRef t = [videoTest copyNextSampleBuffer];
        // NSLog(@"---->%@", CMSampleBufferGetImageBuffer(t));

        // CMSampleBufferRef videoTrackoutBuffer = [videoTrackout copyNextSampleBuffer];
        CMSampleBufferRef videoTrackout_kCVPixelFormatType_32BGRABuffer = [videoTrackout_kCVPixelFormatType_32BGRA copyNextSampleBuffer];
        CMSampleBufferRef videoTrackout_kCVPixelFormatType_420YpCbCr8BiPlanarVideoRangeBuffer = [videoTrackout_kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange copyNextSampleBuffer];
        CMSampleBufferRef videoTrackout_kCVPixelFormatType_420YpCbCr8BiPlanarFullRangeBuffer = [videoTrackout_kCVPixelFormatType_420YpCbCr8BiPlanarFullRange copyNextSampleBuffer];

        if (videoTrackout_kCVPixelFormatType_32BGRABuffer == nil
            || videoTrackout_kCVPixelFormatType_420YpCbCr8BiPlanarVideoRangeBuffer == nil
            || videoTrackout_kCVPixelFormatType_420YpCbCr8BiPlanarFullRangeBuffer == nil
        ) {
            NSLog(@"因为buffer为空所以需要重制 %@", g_bufferReload?@"yes":@"no");
            // NSLog(@"videoTrackoutBuffer = %@", videoTrackoutBuffer);
            NSLog(@"videoTrackout_kCVPixelFormatType_32BGRABuffer = %@", videoTrackout_kCVPixelFormatType_32BGRABuffer);
            NSLog(@"videoTrackout_kCVPixelFormatType_420YpCbCr8BiPlanarVideoRangeBuffer = %@", videoTrackout_kCVPixelFormatType_420YpCbCr8BiPlanarVideoRangeBuffer);
            NSLog(@"videoTrackout_kCVPixelFormatType_420YpCbCr8BiPlanarFullRangeBuffer = %@", videoTrackout_kCVPixelFormatType_420YpCbCr8BiPlanarFullRangeBuffer);
            g_bufferReload = YES;
            return sampleBuffer;
        }

        // 赋值前清理之前的buffer
        if (sampleBuffer != nil) {
            for (NSString *key in [sampleBuffer allKeys]){
                if ([sampleBuffer objectForKey:key] != nil) {
                    CFRelease((__bridge CFTypeRef)[sampleBuffer objectForKey:key]);
                }
            }
        }
        // NSLog(@"创建了新的buffer");
        sampleBuffer = @{
            // @"h264": (__bridge id)videoTrackoutBuffer,
            @(kCVPixelFormatType_32BGRA): (__bridge id)videoTrackout_kCVPixelFormatType_32BGRABuffer,
            @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange): (__bridge id)videoTrackout_kCVPixelFormatType_420YpCbCr8BiPlanarVideoRangeBuffer,
            @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange): (__bridge id)videoTrackout_kCVPixelFormatType_420YpCbCr8BiPlanarFullRangeBuffer
        };
        // NSLog(@"刷新了 %@", sampleBuffer);
    }@catch(NSException *except){
        // g_bufferReload = YES;
        NSLog(@"read buffer 出错了 %@", except);
    }
    return sampleBuffer;
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
        g_previewLayer.frame = self.bounds;

        // 帧率控制
        static NSTimeInterval refreshTime = 0;
        NSTimeInterval nowTime = [[NSDate date] timeIntervalSince1970] * 1000;

        // 防止和VideoOutput的预览冲突，VideoOutput更新后一秒内这里不会执行
        if (nowTime - g_refreshPreviewByVideoDataOutputTime > 1000) {
            // NSLog(@"纯预览更新");
            static CMSampleBufferRef copyBuffer = nil;
            if (nowTime - refreshTime > 1000 / 33 && g_previewLayer.readyForMoreMediaData) {
                g_lockeBuffer = YES;
                refreshTime = nowTime;
                NSDictionary *dict = [GetFrame getCurrentFrame];
                if (dict != nil) {
                    CMSampleBufferRef newBuffer = (__bridge CMSampleBufferRef)dict[@(kCVPixelFormatType_32BGRA)];
                    [g_previewLayer flush];
                    if (copyBuffer != nil) CFRelease(copyBuffer);
                    CMSampleBufferCreateCopy(kCFAllocatorDefault, newBuffer, &copyBuffer);
                    if (copyBuffer != nil) [g_previewLayer enqueueSampleBuffer:copyBuffer];
                }
                g_lockeBuffer = NO;
            }
        }
    }
}
%end


%hook AVCaptureSession
-(void) startRunning {
    g_cameraRunning = YES;
    g_bufferReload = YES;
    g_refreshPreviewByVideoDataOutputTime = [[NSDate date] timeIntervalSince1970] * 1000;
	NSLog(@"开始使用摄像头了， 预设值是 %@", [self sessionPreset]);
	%orig;
}
-(void) stopRunning {
    g_cameraRunning = NO;
	NSLog(@"停止使用摄像头了");
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
 	// NSLog(@"添加了一个输入设备 %@", [[input device] activeFormat]);
	%orig;
}
- (void)addOutput:(AVCaptureOutput *)output{
	NSLog(@"添加了一个输出设备 %@", output);
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


MSHook(CVImageBufferRef, CMSampleBufferGetImageBuffer, CMSampleBufferRef sbuf) {
    CFDictionaryRef exifAttachments = CMGetAttachment(sbuf, (CFStringRef)@"{Exif}", NULL);
    CVImageBufferRef orig = _CMSampleBufferGetImageBuffer(sbuf);
    @try{
        if (
            [g_fileManager fileExistsAtPath:g_tempFile]
            && exifAttachments != nil
        ) { // 如果有exif信息表示来自相机的buffer
            g_refreshPreviewByVideoDataOutputTime = ([[NSDate date] timeIntervalSince1970] + 3) * 1000;

            // NSLog(@"------->%@", sbuf);
            // NSLog(@"---->%@", CMSampleBufferGetFormatDescription(sbuf)); 
            // NSLog(@"线程 %@", [NSThread currentThread]);
            // NSLog(@"--%@", exifAttachments);
            id cvImageBufferAttachments = CMGetAttachment(sbuf, (CFStringRef)@"{_cvImageBufferAttachmen}", NULL);
            if (cvImageBufferAttachments == nil) {
                // NSLog(@"产生新的数据");
                g_lockeBuffer = YES;
                NSDictionary *dict = [GetFrame getCurrentFrame];
                if (dict != nil) {
                    OSType type = CVPixelBufferGetPixelFormatType(orig);
                    CMSampleBufferRef newBuffer = (__bridge CMSampleBufferRef)dict[@(type)];
                    // NSLog(@"====>%@", CMSampleBufferGetFormatDescription(newBuffer));
                    CMSetAttachment(sbuf, (CFStringRef)@"{_cvImageBufferAttachmen}", _CMSampleBufferGetImageBuffer(newBuffer), kCMAttachmentMode_ShouldNotPropagate);
                    if (g_previewLayer != nil && g_previewLayer.readyForMoreMediaData) {
                        [g_previewLayer flush];
                        [g_previewLayer enqueueSampleBuffer:newBuffer];
                    }
                }
                cvImageBufferAttachments = CMGetAttachment(sbuf, (CFStringRef)@"{_cvImageBufferAttachmen}", NULL);
                g_lockeBuffer = NO;
                // NSLog(@"新的数据");
            }else {
                // NSLog(@"旧的数据了");
            }
            if (cvImageBufferAttachments != nil) return (__bridge CVImageBufferRef)cvImageBufferAttachments;
        }
    }@catch(NSException *except){
        NSLog(@"出错了---》%@", except);
    }
    
    return orig;
}
MSHook(CMBlockBufferRef, CMSampleBufferGetDataBuffer, CMSampleBufferRef sbuf) {
    // g_lockeBuffer = NO;
    // CMBlockBufferRef newData = _CMSampleBufferGetDataBuffer([GetFrame getCurrentFrame]);
    // g_lockeBuffer = YES;
    // NSLog(@"newData = %@", newData);
    // NSLog(@"oldData = %@", _CMSampleBufferGetDataBuffer(sbuf));
    // return newData;
    return _CMSampleBufferGetDataBuffer(sbuf);
}
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

    MSHookFunction(CMSampleBufferGetImageBuffer, MSHake(CMSampleBufferGetImageBuffer));
    MSHookFunction(CMSampleBufferGetDataBuffer, MSHake(CMSampleBufferGetDataBuffer));
}