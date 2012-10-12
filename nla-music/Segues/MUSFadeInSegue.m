//
//  MUSFadeInSegue.m
//  nla-music
//
//  Copyright © 2012 Jake MacMullin
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of
//  this software and associated documentation files (the "Software"), to deal in
//  the Software without restriction, including without limitation the rights to
//  use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
//  of the Software, and to permit persons to whom the Software is furnished to do
//  so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

#import <QuartzCore/QuartzCore.h>
#import "MUSFadeInSegue.h"

@implementation MUSFadeInSegue

- (void)perform {
    UIViewController *source = self.sourceViewController;
    UIViewController *destination = self.destinationViewController;
    
    // grab an image of the source view
    UIGraphicsBeginImageContext(source.view.bounds.size);
    [source.view.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *sourceImage = UIGraphicsGetImageFromCurrentImageContext();
    UIImageView *sourceImageView = [[UIImageView alloc] initWithImage:sourceImage];
    UIGraphicsEndImageContext();
    
    [source presentViewController:destination animated:NO completion:NULL];
    [destination.view addSubview:sourceImageView];
    
    [UIView animateWithDuration:0.25
                     animations:^{
                         [sourceImageView setAlpha:0.0];
                     }
                     completion:^(BOOL finished) {
                         [sourceImageView removeFromSuperview];
                     }
     ];
}

@end
