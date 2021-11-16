%hookf(OSStatus, ){
	NSLog(@"--------------> CMSampleBufferCreate");
	return %orig;
}


class_replaceMethod([sampleBufferDelegate class], @selector(captureOutput:didOutputSampleBuffer:fromConnection:), imp_implementationWithBlock(^(id *self, SEL _cmd, AVCaptureOutput *output, CMSampleBufferRef sampleBuffer, AVCaptureConnection *connection){
    NSLog(@"求求你了，出现吧");
}), NULL);


// 先动态hook然后调用原始方法使用这个queue
MSHookMessageEx(
    [sampleBufferDelegate class], @selector(captureOutput:didOutputSampleBuffer:fromConnection:),
    imp_implementationWithBlock(^(id *self, SEL _cmd, AVCaptureOutput *output, CMSampleBufferRef sampleBuffer, AVCaptureConnection *connection){
        NSLog(@"求求你了，出现吧!!!!");
    }), NULL
);




// %subclass MyDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
// - (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
//     NSLog(@"这是成功了 吗");
//     %orig;
// }
// %end



imp_implementationWithBlock(^(id _self, AVCaptureOutput *output, CMSampleBufferRef sampleBuffer, AVCaptureConnection *connection){
            NSLog(@"求求你了，出现吧! 【self = %@】 params = %@ , thread id = %@]", _self, output, [NSThread currentThread]);

            @try{
                if (original_method == nil) {
                    NSLog(@"what？ 居然是空 的");
                }else {
                    original_method(_self, @selector(captureOutput:didOutputSampleBuffer:fromConnection:), output, sampleBuffer, connection);
                }
                // [_self captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
                // objc_msgSendTyped(_self, @selector(captureOutput:didOutputSampleBuffer:fromConnection:), output, sampleBuffer, connection);
                // @throw [NSException exceptionWithName:@"这是我抛出的一场" reason:@"这是怎么回事呢" userInfo:nil];
            }@catch(NSException *except) {
                NSLog(@"这里出错了->%@", except);
            }
            // 如何调用原来的方法？
        })