#import "ViewController+MotionPhoto.h"

#import "MotionPhoto/MotionPhotoEditorViewController.h"

@implementation ViewController (MotionPhoto)

- (void)motionPhotoButtonTapped:(UIButton *)sender {
    MotionPhotoEditorViewController *controller = [[MotionPhotoEditorViewController alloc] init];
    controller.hidesBottomBarWhenPushed = YES;
    [self.navigationController setNavigationBarHidden:NO animated:YES];
    [self.navigationController pushViewController:controller animated:YES];
}

@end
