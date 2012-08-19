//
//  HLSContainerStack.m
//  CoconutKit
//
//  Created by Samuel Défago on 09.07.12.
//  Copyright (c) 2012 Hortis. All rights reserved.
//

#import "HLSContainerStack.h"

#import "HLSAssert.h"
#import "HLSContainerContent.h"
#import "HLSContainerStackView.h"
#import "HLSFloat.h"
#import "HLSLogger.h"
#import "NSArray+HLSExtensions.h"
#import "UIViewController+HLSExtensions.h"

// Constants
const NSUInteger HLSContainerStackMinimalCapacity = 1;
const NSUInteger HLSContainerStackDefaultCapacity = 2;
const NSUInteger HLSContainerStackUnlimitedCapacity = NSUIntegerMax;

@interface HLSContainerStack ()

+ (HLSAnimation *)transitionAnimationWithClass:(Class)transitionClass
                                 appearingView:(UIView *)appearingView
                              disappearingView:(UIView *)disappearingView
                                        inView:(UIView *)view
                                      duration:(NSTimeInterval)duration;

+ (HLSAnimation *)reverseTransitionAnimationWithClass:(Class)transitionClass
                                        appearingView:(UIView *)appearingView
                                     disappearingView:(UIView *)disappearingView
                                               inView:(UIView *)view
                                             duration:(NSTimeInterval)duration;

@property (nonatomic, assign) UIViewController *containerViewController;
@property (nonatomic, retain) NSMutableArray *containerContents;
@property (nonatomic, assign) NSUInteger capacity;

- (HLSContainerContent *)topContainerContent;
- (HLSContainerContent *)secondTopContainerContent;

- (HLSContainerContent *)containerContentAtDepth:(NSUInteger)depth;

- (void)addViewForContainerContent:(HLSContainerContent *)containerContent
                         inserting:(BOOL)inserting
                          animated:(BOOL)animated;

@end

@implementation HLSContainerStack

#pragma mark Class methods

+ (id)singleControllerContainerStackWithContainerViewController:(UIViewController *)containerViewController
{
    return [[[[self class] alloc] initWithContainerViewController:containerViewController
                                                         capacity:HLSContainerStackMinimalCapacity 
                                                         removing:YES
                                          rootViewControllerFixed:NO] autorelease];
}

+ (HLSAnimation *)transitionAnimationWithClass:(Class)transitionClass
                                 appearingView:(UIView *)appearingView
                              disappearingView:(UIView *)disappearingView
                                        inView:(UIView *)view
                                      duration:(NSTimeInterval)duration
{
    NSAssert([transitionClass isSubclassOfClass:[HLSTransition class]], @"Transitions must be subclasses of HLSTransition");
    NSAssert((! appearingView || appearingView.superview == view) && (! disappearingView || disappearingView.superview == view),
             @"Both the appearing and disappearing views must be children of the view in which the transition takes place");
        
    // Calculate the exact frame in which the animations will occur (taking into account the transform applied
    // to the parent view)
    CGRect frame = CGRectApplyAffineTransform(view.frame, CGAffineTransformInvert(view.transform));
    
    // Build the animation with default parameters
    NSArray *animationSteps = [[transitionClass class] animationStepsWithAppearingView:appearingView
                                                                      disappearingView:disappearingView
                                                                               inFrame:frame];
    HLSAnimation *animation = [HLSAnimation animationWithAnimationSteps:animationSteps];
    
    // Generate an animation with the proper duration
    if (doubleeq(duration, kAnimationTransitionDefaultDuration)) {
        return animation;
    }
    else {
        return [animation animationWithDuration:duration];
    }
}

+ (HLSAnimation *)reverseTransitionAnimationWithClass:(Class)transitionClass
                                        appearingView:(UIView *)appearingView
                                     disappearingView:(UIView *)disappearingView
                                               inView:(UIView *)view
                                             duration:(NSTimeInterval)duration
{
    NSAssert([transitionClass isSubclassOfClass:[HLSTransition class]], @"Transitions must be subclasses of HLSTransition");
    NSAssert((! appearingView || appearingView.superview == view) && (! disappearingView || disappearingView.superview == view),
             @"Both the appearing and disappearing views must be children of the view in which the transition takes place");
    
    // Calculate the exact frame in which the animations will occur (taking into account the transform applied
    // to the parent view)
    CGRect frame = CGRectApplyAffineTransform(view.frame, CGAffineTransformInvert(view.transform));
    
    // Build the animation with default parameters
    NSArray *animationSteps = [[transitionClass class] reverseAnimationStepsWithAppearingView:appearingView
                                                                             disappearingView:disappearingView
                                                                                      inFrame:frame];
    // If custom reverse animation implemented by the animation class, use it
    if (animationSteps) {
        HLSAnimation *animation = [HLSAnimation animationWithAnimationSteps:animationSteps];
        
        // Generate an animation with the proper duration
        if (doubleeq(duration, kAnimationTransitionDefaultDuration)) {
            return animation;
        }
        else {
            return [animation animationWithDuration:duration];
        }
    }
    // If not implemented by the transition class, use the default reverse animation
    else {
        return [[HLSContainerStack transitionAnimationWithClass:transitionClass
                                                  appearingView:disappearingView
                                               disappearingView:appearingView
                                                         inView:view
                                                        duration:duration] reverseAnimation];
    }
}

#pragma mark Object creation and destruction

- (id)initWithContainerViewController:(UIViewController *)containerViewController 
                             capacity:(NSUInteger)capacity
                             removing:(BOOL)removing
              rootViewControllerFixed:(BOOL)rootViewControllerFixed
{
    if ((self = [super init])) {
        if (! containerViewController) {
            HLSLoggerError(@"Missing container view controller");
            [self release];
            return nil;
        }
                
        self.containerViewController = containerViewController;
        self.containerContents = [NSMutableArray array];
        self.capacity = capacity;
        m_removing = removing;
        m_rootViewControllerFixed = rootViewControllerFixed;
    }
    return self;
}

- (id)init
{
    HLSForbiddenInheritedMethod();
    return nil;
}

- (void)dealloc
{
    self.containerViewController = nil;
    self.containerContents = nil;
    self.containerView = nil;
    self.delegate = nil;

    [super dealloc];
}

#pragma mark Accessors and mutators

@synthesize containerViewController = m_containerViewController;

@synthesize containerContents = m_containerContents;

@synthesize containerView = m_containerView;

- (void)setContainerView:(UIView *)containerView
{
    if (m_containerView == containerView) {
        return;
    }
        
    if ([self.containerViewController isViewVisible]) {
        HLSLoggerError(@"Cannot change the container view when the container view controller is being displayed");
        return;
    }
    
    if (containerView) {
        if (! [self.containerViewController isViewLoaded]) {
            HLSLoggerError(@"Cannot set a container view when the container view controller's view has not been loaded");
            return;
        }
        
        if (! [containerView isDescendantOfView:[self.containerViewController view]]) {
            HLSLoggerError(@"The container view must be part of the container view controller's view hiearchy");
            return;
        }
        
        // All animations must take place inside the view controller's view
        containerView.clipsToBounds = YES;
        
        // Create the container base view maintaining the whole container view hiearchy
        HLSContainerStackView *containerStackView = [[[HLSContainerStackView alloc] initWithFrame:containerView.bounds] autorelease];
        [containerView addSubview:containerStackView];
    }
    
    [m_containerView release];
    m_containerView = [containerView retain];
}

- (HLSContainerStackView *)containerStackView
{
    return [self.containerView.subviews firstObject];
}

@synthesize capacity = m_capacity;

- (void)setCapacity:(NSUInteger)capacity
{
    if (capacity < HLSContainerStackMinimalCapacity) {
        capacity = HLSContainerStackMinimalCapacity;
        HLSLoggerWarn(@"The capacity cannot be smaller than %d; set to this value", HLSContainerStackMinimalCapacity);
    }
    
    m_capacity = capacity;
}

@synthesize delegate = m_delegate;

- (HLSContainerContent *)topContainerContent
{
    return [self.containerContents lastObject];
}

- (HLSContainerContent *)secondTopContainerContent
{
    if ([self.containerContents count] < 2) {
        return nil;
    }
    return [self.containerContents objectAtIndex:[self.containerContents count] - 2];
}

- (UIViewController *)rootViewController
{
    HLSContainerContent *rootContainerContent = [self.containerContents firstObject];
    return rootContainerContent.viewController;
}

- (UIViewController *)topViewController
{
    HLSContainerContent *topContainerContent = [self topContainerContent];
    return topContainerContent.viewController;
}

- (NSArray *)viewControllers
{
    NSMutableArray *viewControllers = [NSMutableArray array];
    for (HLSContainerContent *containerContent in self.containerContents) {
        [viewControllers addObject:containerContent.viewController];
    }
    return [NSArray arrayWithArray:viewControllers];
}

- (NSUInteger)count
{
    return [self.containerContents count];
}

- (HLSContainerContent *)containerContentAtDepth:(NSUInteger)depth
{
    if ([self.containerContents count] > depth) {
        return [self.containerContents objectAtIndex:[self.containerContents count] - depth - 1];
    }
    else {
        return nil;
    }
}

#pragma mark Adding and removing view controllers

- (void)pushViewController:(UIViewController *)viewController
       withTransitionClass:(Class)transitionClass
                  duration:(NSTimeInterval)duration
                  animated:(BOOL)animated
{
    [self insertViewController:viewController
                       atIndex:[self.containerContents count] 
           withTransitionClass:transitionClass
                      duration:duration
                      animated:animated];
}

- (void)popViewControllerAnimated:(BOOL)animated
{
    [self removeViewControllerAtIndex:[self.containerContents count] - 1 animated:animated];
}

- (void)popToViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    if (viewController) {
        NSUInteger index = [[self viewControllers] indexOfObject:viewController];
        if (index == NSNotFound) {
            HLSLoggerWarn(@"The view controller to pop to does not belong to the container");
            return;
        }
        else if (index == [self.containerContents count] - 1) {
            HLSLoggerInfo(@"Nothing to pop: The view controller displayed is already the one you try to pop to");
            return;
        }
        [self popToViewControllerAtIndex:index animated:animated];
    }
    else {        
        // Pop everything
        [self popToViewControllerAtIndex:NSUIntegerMax animated:animated];
    }
}

- (void)popToViewControllerAtIndex:(NSUInteger)index animated:(BOOL)animated
{
    if ([self.containerContents count] == 0) {
        HLSLoggerInfo(@"Nothing to pop: The view controller container is empty");
        return;
    }
    
    // Pop to a valid index
    NSUInteger firstRemovedIndex = 0;
    if (index != NSUIntegerMax) {
        // Remove in the middle
        if (index < [self.containerContents count] - 1) {
            firstRemovedIndex = index + 1;
        }
        // Nothing to do if we pop to the current top view controller
        else if (index == [self.containerContents count] - 1) {
            HLSLoggerInfo(@"Nothing to pop: The view controller displayed is already the one you try to pop to");
            return;            
        }
        else {
            HLSLoggerError(@"Invalid index %d. Expected in [0;%d]", index, [self.containerContents count] - 2);
            return;
        }
    }
    // Pop everything
    else {
        if (m_rootViewControllerFixed) {
            HLSLoggerWarn(@"The root view controller is fixed. Cannot pop everything");
            return;
        }
        
        firstRemovedIndex = 0;
    }
    
    // Remove the view controllers until the one we want to pop to (except the topmost one, for which we will play
    // the pop animation if desired)
    NSUInteger i = [self.containerContents count] - firstRemovedIndex - 1;
    while (i > 0) {
        [self.containerContents removeObjectAtIndex:firstRemovedIndex];
        --i;
    }
    
    // Resurrect view controller's views below the view controller we pop to so that the capacity criterium
    // is satisfied
    for (NSUInteger i = 0; i < MIN(self.capacity, [self.containerContents count]); ++i) {
        NSUInteger index = firstRemovedIndex - 1 - i;
        HLSContainerContent *containerContent = [self.containerContents objectAtIndex:index];
        [self addViewForContainerContent:containerContent inserting:NO animated:NO];
        
        if (index == 0) {
            break;
        }
    }
    
    // Now pop the top view controller
    [self popViewControllerAnimated:animated]; 
}

- (void)popToRootViewControllerAnimated:(BOOL)animated
{
    [self popToViewControllerAtIndex:0 animated:animated];    
}

- (void)popAllViewControllersAnimated:(BOOL)animated
{
    [self popToViewControllerAtIndex:NSUIntegerMax animated:animated];
}

- (void)insertViewController:(UIViewController *)viewController 
                     atIndex:(NSUInteger)index 
         withTransitionClass:(Class)transitionClass
                    duration:(NSTimeInterval)duration
                    animated:(BOOL)animated
{
    if (! viewController) {
        HLSLoggerError(@"Cannot push nil into a view controller container");
        return;
    }
    
    if (index > [self.containerContents count]) {
        HLSLoggerError(@"Invalid index %d. Expected in [0;%d]", index, [self.containerContents count]);
        return;
    }
    
    if (m_animating) {
        HLSLoggerWarn(@"Cannot insert a view controller while a transition animation is running");
        return;
    }
    
    if (m_rootViewControllerFixed && index == 0 && [self rootViewController]) {
        HLSLoggerError(@"The root view controller is fixed and cannot be changed anymore once set or after the container "
                       "has been displayed once");
        return;
    }
    
    if ([self.containerViewController isViewVisible]) {
        // Check that the view controller to be pushed is compatible with the current orientation
        if (! [viewController shouldAutorotateToInterfaceOrientation:self.containerViewController.interfaceOrientation]) {
            HLSLoggerError(@"The view controller does not support the current view container orientation");
            return;
        }
        
        // Notify the delegate before the view controller is actually installed on top of the stack and associated with the
        // container (see HLSContainerStackDelegate interface contract)
        if (index == [self.containerContents count]) {
            if ([self.delegate respondsToSelector:@selector(containerStack:willPushViewController:coverViewController:animated:)]) {
                [self.delegate containerStack:self
                       willPushViewController:viewController
                          coverViewController:[self topViewController]
                                     animated:animated];
            }
        }
    }
        
    // Associate the new view controller with its container (this increases [container count])
    HLSContainerContent *containerContent = [[[HLSContainerContent alloc] initWithViewController:viewController
                                                                         containerViewController:self.containerViewController
                                                                                 transitionClass:transitionClass
                                                                                        duration:duration] autorelease];
    [self.containerContents insertObject:containerContent atIndex:index];
    
    // If inserted in the capacity range, must add the view
    if ([self.containerViewController isViewVisible]) {
        // A correction needs to be applied here to account for the [container count] increase (since index was relative
        // to the previous value)
        if ([self.containerContents count] - index - 1 <= self.capacity) {
            [self addViewForContainerContent:containerContent inserting:YES animated:animated];
        }
    }
}

- (void)insertViewController:(UIViewController *)viewController
         belowViewController:(UIViewController *)siblingViewController
         withTransitionClass:(Class)transitionClass
                    duration:(NSTimeInterval)duration
{
    NSUInteger index = [[self viewControllers] indexOfObject:siblingViewController];
    if (index == NSNotFound) {
        HLSLoggerWarn(@"The given sibling view controller does not belong to the container");
        return;
    }
    [self insertViewController:viewController 
                       atIndex:index 
           withTransitionClass:transitionClass
                      duration:duration
                      animated:NO /* irrelevant since this method can never be used for pushing a view controller */];
}

- (void)insertViewController:(UIViewController *)viewController
         aboveViewController:(UIViewController *)siblingViewController
         withTransitionClass:(Class)transitionClass
                    duration:(NSTimeInterval)duration
                    animated:(BOOL)animated
{
    NSUInteger index = [[self viewControllers] indexOfObject:siblingViewController];
    if (index == NSNotFound) {
        HLSLoggerWarn(@"The given sibling view controller does not belong to the container");
        return;
    }
    [self insertViewController:viewController 
                       atIndex:index + 1
           withTransitionClass:transitionClass
                      duration:duration
                      animated:animated];
}

- (void)removeViewControllerAtIndex:(NSUInteger)index animated:(BOOL)animated
{
    if (index >= [self.containerContents count]) {
        HLSLoggerError(@"Invalid index %d. Expected in [0;%d]", index, [self.containerContents count] - 1);
        return;
    }
    
    if (m_animating) {
        HLSLoggerWarn(@"Cannot remove a view controller while a transition animation is running");
        return;
    }
    
    if (m_rootViewControllerFixed && index == 0 && [self rootViewController]) {
        HLSLoggerWarn(@"The root view controller is fixed and cannot be removed once set or after the container has been "
                      "displayed once");
        return;
    }
    
    if ([self.containerViewController isViewVisible]) {
        // Notify the delegate
        if (index == [self.containerContents count] - 1) {
            if ([self.delegate respondsToSelector:@selector(containerStack:willPopViewController:revealViewController:animated:)]) {
                [self.delegate containerStack:self
                        willPopViewController:[self topViewController]
                         revealViewController:self.secondTopContainerContent.viewController
                                     animated:animated];
            }
        }
    }
        
    HLSContainerContent *containerContent = [self.containerContents objectAtIndex:index];
    if (containerContent.addedToContainerView) {
        // Load the view controller'sview below so that the capacity criterium can be fulfilled (if needed). If we are popping a
        // view controller, we will have capacity + 1 view controller's views loaded during the animation. This ensures that no
        // view controllers magically pops up during animation (which could be noticed depending on the pop animation, or if view
        // controllers on top of it are transparent)
        HLSContainerContent *containerContentAtCapacity = [self containerContentAtDepth:self.capacity];
        if (containerContentAtCapacity) {
            [self addViewForContainerContent:containerContentAtCapacity inserting:NO animated:NO];
        }
        
        HLSContainerGroupView *groupView = [[self containerStackView] groupViewForContentView:[containerContent viewIfLoaded]];
        
        HLSAnimation *reverseAnimation = [HLSContainerStack reverseTransitionAnimationWithClass:containerContent.transitionClass
                                                                                  appearingView:groupView.backGroupView
                                                                               disappearingView:groupView.frontView
                                                                                         inView:groupView
                                                                                       duration:containerContent.duration];
        reverseAnimation.delegate = self;          // always set a delegate so that the animation is destroyed if the container gets deallocated
        if (index == [self.containerContents count] - 1) {
            // Some more work has to be done for pop animations in the animation begin / end callbacks. To identify such animations,
            // we give them a tag which we can test in those callbacks
            reverseAnimation.tag = @"pop_animation";
            reverseAnimation.lockingUI = YES;
            
            [reverseAnimation playAnimated:animated];
            
            // Check the animation callback implementations for what happens next
        }
        else {
            [reverseAnimation playAnimated:NO];
            [self.containerContents removeObject:containerContent];
        }        
    }
    else {
        [self.containerContents removeObjectAtIndex:index];
    }
}

- (void)removeViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    NSUInteger index = [[self viewControllers] indexOfObject:viewController];
    if (index == NSNotFound) {
        HLSLoggerWarn(@"The view controller to remove does not belong to the container");
        return;
    }
    [self removeViewControllerAtIndex:index animated:animated];
}

- (void)releaseViews
{
    for (HLSContainerContent *containerContent in self.containerContents) {
        [containerContent releaseViews];
    }
    
    self.containerView = nil;
}

- (void)viewWillAppear:(BOOL)animated
{
    if (! self.containerView) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"No container view has been set"
                                     userInfo:nil];
    }
    
    if (m_rootViewControllerFixed && [self.containerContents count] == 0) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"The root view controller is fixed but has not been defined when displaying the container"
                                     userInfo:nil];
    }
    
    // Create the container view hierarchy with those views required according to the capacity
    for (NSUInteger i = 0; i < MIN(self.capacity, [self.containerContents count]); ++i) {
        // Never play transitions (we are building the view hierarchy). Only the top view controller receives the animated
        // information
        HLSContainerContent *containerContent = [self containerContentAtDepth:i];
        if (containerContent) {
            [self addViewForContainerContent:containerContent inserting:NO animated:animated];
        }
    }
        
    // Forward events (willShow is sent to the delegate before willAppear is sent to the child)
    HLSContainerContent *topContainerContent = [self topContainerContent];
    if (topContainerContent && [self.delegate respondsToSelector:@selector(containerStack:willShowViewController:animated:)]) {
        [self.delegate containerStack:self willShowViewController:topContainerContent.viewController animated:animated];
    }
    
    if ([self.containerViewController respondsToSelector:@selector(isMovingToParentViewController)]) {
        [topContainerContent viewWillAppear:animated movingToParentViewController:[self.containerViewController isMovingToParentViewController]];
    }
    else {
        [topContainerContent viewWillAppear:animated movingToParentViewController:NO];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    // Forward events (didAppear is sent to the child before didShow is sent to the delegate)
    HLSContainerContent *topContainerContent = [self topContainerContent];
    if ([self.containerViewController respondsToSelector:@selector(isMovingToParentViewController)]) {
        [topContainerContent viewDidAppear:animated movingToParentViewController:[self.containerViewController isMovingToParentViewController]];
    }
    else {
        [topContainerContent viewDidAppear:animated movingToParentViewController:NO];
    }
    
    if (topContainerContent && [self.delegate respondsToSelector:@selector(containerStack:didShowViewController:animated:)]) {
        [self.delegate containerStack:self didShowViewController:topContainerContent.viewController animated:animated];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    // Forward events (willHide is sent to the delegate before willDisappear is sent to the child)
    HLSContainerContent *topContainerContent = [self topContainerContent];
    if (topContainerContent && [self.delegate respondsToSelector:@selector(containerStack:willHideViewController:animated:)]) {
        [self.delegate containerStack:self willHideViewController:topContainerContent.viewController animated:animated];
    }
    
    if ([self.containerViewController respondsToSelector:@selector(isMovingFromParentViewController)]) {
        [topContainerContent viewWillDisappear:animated movingFromParentViewController:[self.containerViewController isMovingFromParentViewController]];
    }
    else {
        [topContainerContent viewWillDisappear:animated movingFromParentViewController:NO];
    }
}

- (void)viewDidDisappear:(BOOL)animated
{
    // Forward events (didDisappear is sent to the child before didHide is sent to the delegate)
    HLSContainerContent *topContainerContent = [self topContainerContent];
    if ([self.containerViewController respondsToSelector:@selector(isMovingFromParentViewController)]) {
        [topContainerContent viewDidDisappear:animated movingFromParentViewController:[self.containerViewController isMovingFromParentViewController]];
    }
    else {
        [topContainerContent viewDidDisappear:animated movingFromParentViewController:NO];
    }
    
    if (topContainerContent && [self.delegate respondsToSelector:@selector(containerStack:didHideViewController:animated:)]) {
        [self.delegate containerStack:self didHideViewController:topContainerContent.viewController animated:animated];
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
    // Prevent rotations during animations. Can lead to erroneous animations
    if (m_animating) {
        HLSLoggerInfo(@"A transition animation is running. Rotation has been prevented");
        return NO;
    }
    
    // If one view controller in the stack does not support the orientation, neither will the container
    for (HLSContainerContent *containerContent in self.containerContents) {
        if (! [containerContent shouldAutorotateToInterfaceOrientation:toInterfaceOrientation]) {
            return NO;
        }
    }
        
    return YES;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    if ([self.containerContents count] != 0) {
        // Visible view controllers only
        for (NSUInteger i = 0; i < MIN(self.capacity, [self.containerContents count]); ++i) {
            NSUInteger index = [self.containerContents count] - 1 - i;
            HLSContainerContent *containerContent = [self.containerContents objectAtIndex:index];
            
            // To avoid issues when pushing - rotating - popping view controllers (which can lead to blurry views depending
            // on the animation style, most notably when scaling is involved), we negate each animation here, with the old
            // frame. We replay the animation just afterwards in willAnimateRotationToInterfaceOrientation:duration:,
            // where the frame is the final one obtained after rotation. This trick is invisible to the user and avoids
            // having issues because of view rotation (this can lead to small floating-point imprecisions, leading to
            // non-integral frames, and thus to blurry views)
            HLSContainerGroupView *groupView = [[self containerStackView] groupViewForContentView:[containerContent viewIfLoaded]];
            HLSAnimation *reverseAnimation = [[HLSContainerStack transitionAnimationWithClass:containerContent.transitionClass
                                                                                appearingView:groupView.frontView
                                                                             disappearingView:groupView.backGroupView
                                                                                       inView:groupView
                                                                                     duration:0.] reverseAnimation];
            [reverseAnimation playAnimated:NO];
            
            // Only view controllers potentially visible (i.e. not unloaded according to the capacity) receive rotation
            // events. This matches UINavigationController behavior, for which only the top view controller receives
            // such events
            [containerContent willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
            
            if (index == 0) {
                break;
            }
        }
    }
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    if ([self.containerContents count] != 0) {
        // Visible view controllers only
        for (NSUInteger i = 0; i < MIN(self.capacity, [self.containerContents count]); ++i) {
            NSUInteger index = [self.containerContents count] - 1 - i;
            HLSContainerContent *containerContent = [self.containerContents objectAtIndex:index];
            
            // See comment in -willRotateToInterfaceOrientation:duration:
            HLSContainerGroupView *groupView = [[self containerStackView] groupViewForContentView:[containerContent viewIfLoaded]];
            HLSAnimation *animation = [HLSContainerStack transitionAnimationWithClass:containerContent.transitionClass
                                                                        appearingView:groupView.frontView
                                                                     disappearingView:groupView.backGroupView
                                                                               inView:groupView
                                                                             duration:0.];
            [animation playAnimated:NO];
            
            // Same remark as in -willRotateToInterfaceOrientation:duration:
            [containerContent willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
            
            if (index == 0) {
                break;
            }
        }
    }
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    if ([self.containerContents count] != 0) {
        // Visible view controllers only
        for (NSUInteger i = 0; i < MIN(self.capacity, [self.containerContents count]); ++i) {
            NSUInteger index = [self.containerContents count] - 1 - i;
            HLSContainerContent *containerContent = [self.containerContents objectAtIndex:index];
            
            // Same remark as in -willAnimateRotationToInterfaceOrientation:duration:
            [containerContent didRotateFromInterfaceOrientation:fromInterfaceOrientation];
            
            if (index == 0) {
                break;
            }
        }   
    }
}

/**
 * Method to add the view for a container content to the stack view hierarchy. The container content parameter is mandatory
 * and must be part of the stack. If the view is added because the container content is being inserted into the container,
 * set inserting to YES, otherwise to NO
 */
- (void)addViewForContainerContent:(HLSContainerContent *)containerContent
                         inserting:(BOOL)inserting
                          animated:(BOOL)animated
{
    NSAssert(containerContent != nil, @"A container content is mandatory");
        
    if (! [self.containerViewController isViewVisible]) {
        return;
    }
        
    if (containerContent.addedToContainerView) {
        return;
    }
    
    NSUInteger index = [self.containerContents indexOfObject:containerContent];
    NSAssert(index != NSNotFound, @"Content not found in the stack");
    
    HLSContainerStackView *stackView = [self containerStackView];
    
    // Last element? Add to top
    if (index == [self.containerContents count] - 1) {
        [containerContent addAsSubviewIntoContainerStackView:stackView];
    }
    // Otherwise add below first content above for which a view is available (most probably the nearest neighbor above)
    else {
        // Find which container view above is available. We will insert the new one right below it (usually,
        // this is the one at index + 1, but this might not be the case if we are resurrecting a view controller
        // deep in the stack)
        BOOL inserted = NO;
        for (NSUInteger i = index + 1; i < [self.containerContents count]; ++i) {
            HLSContainerContent *aboveContainerContent = [self.containerContents objectAtIndex:i];
            if (aboveContainerContent.isAddedToContainerView) {
                [containerContent insertAsSubviewIntoContainerStackView:stackView
                                                                atIndex:[stackView.contentViews indexOfObject:[aboveContainerContent viewIfLoaded]]];
                inserted = YES;
                break;
            }
        }
        
        if (! inserted) {
            [containerContent addAsSubviewIntoContainerStackView:stackView];
        }
        
        // Play the corresponding animation to put the view into the correct location
        HLSContainerContent *aboveContainerContent = [self.containerContents objectAtIndex:index + 1];
        HLSContainerGroupView *aboveGroupView = [[self containerStackView] groupViewForContentView:[aboveContainerContent viewIfLoaded]];
        HLSAnimation *aboveAnimation = [HLSContainerStack transitionAnimationWithClass:aboveContainerContent.transitionClass
                                                                         appearingView:nil      /* only play the animation for the view we added */
                                                                      disappearingView:aboveGroupView.backGroupView
                                                                                inView:aboveGroupView
                                                                              duration:aboveContainerContent.duration];
        aboveAnimation.delegate = self;          // always set a delegate so that the animation is destroyed if the container gets deallocated
        [aboveAnimation playAnimated:NO];
    }
    
    // Play the corresponding animation so that the view controllers are brought into correct positions
    HLSContainerGroupView *groupView = [[self containerStackView] groupViewForContentView:[containerContent viewIfLoaded]];
    HLSAnimation *animation = [HLSContainerStack transitionAnimationWithClass:containerContent.transitionClass
                                                                appearingView:groupView.frontView
                                                             disappearingView:groupView.backGroupView
                                                                       inView:groupView
                                                                     duration:containerContent.duration];
    animation.delegate = self;          // always set a delegate so that the animation is destroyed if the container gets deallocated
    
    // Pushing a view controller onto the stack
    if (inserting && index == [self.containerContents count] - 1) {
        // Some more work has to be done for push animations in the animation begin / end callbacks. To identify such animations,
        // we give them a tag which we can test in those callbacks
        animation.tag = @"push_animation";
        animation.lockingUI = YES;
        
        [animation playAnimated:animated];
        
        // Check the animation callback implementations for what happens next
    }
    // All other cases (inserting in the middle or instantiating the view for a view controller already in the stack)
    else {
        [animation playAnimated:NO];
    }
}

#pragma mark HLSAnimationDelegate protocol implementation

- (void)animationWillStart:(HLSAnimation *)animation animated:(BOOL)animated
{
    m_animating = YES;
    
    // Extra work needed for push and pop animations
    if ([animation.tag isEqualToString:@"push_animation"] || [animation.tag isEqualToString:@"pop_animation"]) {
        HLSContainerContent *appearingContainerContent = nil;
        HLSContainerContent *disappearingContainerContent = nil;
        
        if ([animation.tag isEqualToString:@"push_animation"]) {
            appearingContainerContent = [self topContainerContent];
            disappearingContainerContent = [self secondTopContainerContent];        
        }
        else {
            appearingContainerContent = [self secondTopContainerContent];
            disappearingContainerContent = [self topContainerContent];
        }
        
        // Forward events (willHide is sent to the delegate before willDisappear is sent to the view controller)
        if (disappearingContainerContent && [self.delegate respondsToSelector:@selector(containerStack:willHideViewController:animated:)]) {
            [self.delegate containerStack:self willHideViewController:disappearingContainerContent.viewController animated:animated];
        }
        [disappearingContainerContent viewWillDisappear:animated movingFromParentViewController:YES];
        
        // Forward events (willShow is sent to the delegate before willAppear is sent to the view controller)
        if (appearingContainerContent && [self.delegate respondsToSelector:@selector(containerStack:willShowViewController:animated:)]) {
            [self.delegate containerStack:self willShowViewController:appearingContainerContent.viewController animated:animated];
        }
        [appearingContainerContent viewWillAppear:animated movingToParentViewController:YES];
    }    
}

- (void)animationDidStop:(HLSAnimation *)animation animated:(BOOL)animated
{
    m_animating = NO;
    
    // Extra work needed for push and pop animations
    if ([animation.tag isEqualToString:@"push_animation"] || [animation.tag isEqualToString:@"pop_animation"]) {
        HLSContainerContent *appearingContainerContent = nil;
        HLSContainerContent *disappearingContainerContent = nil;
        
        if ([animation.tag isEqualToString:@"push_animation"]) {
            appearingContainerContent = [self topContainerContent];
            disappearingContainerContent = [self secondTopContainerContent];
        }
        else {
            appearingContainerContent = [self secondTopContainerContent];
            disappearingContainerContent = [self topContainerContent];
        }
        
        // Forward events (didDisappear is sent to the view controller before didHide is sent to the delegate)
        [disappearingContainerContent viewDidDisappear:animated movingFromParentViewController:YES];
        if (disappearingContainerContent && [self.delegate respondsToSelector:@selector(containerStack:didHideViewController:animated:)]) {
            [self.delegate containerStack:self didHideViewController:disappearingContainerContent.viewController animated:animated];
        }
         
        // Forward events (didAppear is sent to the view controller before didShow is sent to the delegate)
        [appearingContainerContent viewDidAppear:animated movingToParentViewController:YES];
        if (appearingContainerContent && [self.delegate respondsToSelector:@selector(containerStack:didShowViewController:animated:)]) {
            [self.delegate containerStack:self didShowViewController:appearingContainerContent.viewController animated:animated];
        }
        
        // Keep the disappearing view controller alive a little bit longer
        UIViewController *disappearingViewController = [disappearingContainerContent.viewController retain];
        
        if ([animation.tag isEqualToString:@"push_animation"]) {
            // Now that the animation is over, get rid of the view or view controller which does not match the capacity criterium
            HLSContainerContent *containerContentAtCapacity = [self containerContentAtDepth:self.capacity];
            if (! m_removing) {
                [containerContentAtCapacity releaseViews];
            }
            else {
                [self.containerContents removeObject:containerContentAtCapacity];
            }
            
            // Notify the delegate
            if ([self.delegate respondsToSelector:@selector(containerStack:didPushViewController:coverViewController:animated:)]) {
                [self.delegate containerStack:self
                        didPushViewController:appearingContainerContent.viewController
                          coverViewController:disappearingViewController
                                     animated:animated];
            }
        }
        else if ([animation.tag isEqualToString:@"pop_animation"]) {
            [self.containerContents removeObject:disappearingContainerContent];
            
            // Notify the delegate after the view controller has been removed from the stack and the parent-child containment relationship
            // has been broken (see HLSContainerStackDelegate interface contract)
            if ([self.delegate respondsToSelector:@selector(containerStack:didPopViewController:revealViewController:animated:)]) {
                [self.delegate containerStack:self
                         didPopViewController:disappearingViewController
                         revealViewController:appearingContainerContent.viewController
                                     animated:animated];
            }
        }
    
        [disappearingViewController release];
    }    
}

#pragma mark Description

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p; containerViewController: %@; containerContents: %@; containerView: %@>",
            [self class],
            self,
            self.containerViewController,
            self.containerContents,
            self.containerView];
}

@end

@implementation UIViewController (HLSContainerStack)

- (id)containerViewControllerKindOfClass:(Class)containerViewControllerClass
{
    return [HLSContainerContent containerViewControllerKindOfClass:containerViewControllerClass
                                                 forViewController:self];
}

@end