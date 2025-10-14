//
//  AnimationProtocol.m
//  AudioSampleBuffer
//
//

#import "AnimationProtocol.h"

@implementation BaseAnimationManager

- (instancetype)initWithTargetView:(UIView *)targetView {
    if (self = [super init]) {
        _targetView = targetView;
        _state = AnimationStateStopped;
        _parameters = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)startAnimation {
    self.state = AnimationStateRunning;
}

- (void)stopAnimation {
    self.state = AnimationStateStopped;
}

- (void)pauseAnimation {
    self.state = AnimationStatePaused;
}

- (void)resumeAnimation {
    self.state = AnimationStateRunning;
}

- (AnimationState)animationState {
    return self.state;
}

- (void)setAnimationParameters:(NSDictionary *)parameters {
    [self.parameters addEntriesFromDictionary:parameters];
}

- (NSDictionary *)animationParameters {
    return [self.parameters copy];
}

@end
