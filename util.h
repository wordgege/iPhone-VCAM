//此方法放在@interface XXXViewController 之前
// @see https://www.jianshu.com/p/c2f8ef80e925

// RotatePixelBufferToAngle(pixelBuffer, radians(90));
static double radians (double degrees) {return degrees * M_PI/180;}

static double ScalingFactorForAngle(double angle, CGSize originalSize) {
    double oriWidth = originalSize.height;
    double oriHeight = originalSize.width;
    double horizontalSpace = fabs( oriWidth*cos(angle) ) + fabs( oriHeight*sin(angle) );
    double scalingFactor = oriWidth / horizontalSpace ;
    return scalingFactor;
}

CGColorSpaceRef rgbColorSpace = NULL;
CIContext *context = nil;
CIImage *ci_originalImage = nil;
CIImage *ci_transformedImage = nil;
CIImage *ci_userTempImage = nil;

static inline void RotatePixelBufferToAngle(CVPixelBufferRef thePixelBuffer, double theAngle) {

    @autoreleasepool {

        if (context==nil) {
            rgbColorSpace = CGColorSpaceCreateDeviceRGB();
            context = [CIContext contextWithOptions:@{kCIContextWorkingColorSpace: (__bridge id)rgbColorSpace,
                                                       kCIContextOutputColorSpace : (__bridge id)rgbColorSpace}];
        }

        long int w = CVPixelBufferGetWidth(thePixelBuffer);
        long int h = CVPixelBufferGetHeight(thePixelBuffer);

        ci_originalImage = [CIImage imageWithCVPixelBuffer:thePixelBuffer];
        ci_userTempImage = [ci_originalImage imageByApplyingTransform:CGAffineTransformMakeScale(0.6, 0.6)];
        //        CGImageRef UICG_image = [context createCGImage:ci_userTempImage fromRect:[ci_userTempImage extent]];

        double angle = theAngle;
        angle = angle+M_PI;
        double scalingFact = ScalingFactorForAngle(angle, CGSizeMake(w, h));


        CGAffineTransform transform =  CGAffineTransformMakeTranslation(w/2.0, h/2.0);
        transform = CGAffineTransformRotate(transform, angle);
        transform = CGAffineTransformTranslate(transform, -w/2.0, -h/2.0);

        //rotate it by applying a transform
        ci_transformedImage = [ci_originalImage imageByApplyingTransform:transform];

        CVPixelBufferLockBaseAddress(thePixelBuffer, 0);

        CGRect extentR = [ci_transformedImage extent];
        CGPoint centerP = CGPointMake(extentR.size.width/2.0+extentR.origin.x,
                                      extentR.size.height/2.0+extentR.origin.y);
        CGSize scaledSize = CGSizeMake(w*scalingFact, h*scalingFact);
        CGRect cropRect = CGRectMake(centerP.x-scaledSize.width/2.0, centerP.y-scaledSize.height/2.0,
                                     scaledSize.height, scaledSize.width);


        CGImageRef cg_img = [context createCGImage:ci_transformedImage fromRect:cropRect];
        ci_transformedImage = [CIImage imageWithCGImage:cg_img];

        ci_transformedImage = [ci_transformedImage imageByApplyingTransform:CGAffineTransformMakeScale(1.0/scalingFact, 1.0/scalingFact)];
        [context render:ci_transformedImage toCVPixelBuffer:thePixelBuffer bounds:CGRectMake(0, 0, w, h) colorSpace:NULL];

        CGImageRelease(cg_img);
        CVPixelBufferUnlockBaseAddress(thePixelBuffer, 0);
    }
}