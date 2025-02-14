//
//  ViewController.m
//  Browser
//
//  Created by Steven Troughton-Smith on 20/09/2015.
//  Improved by Jip van Akker on 14/10/2015 through 10/01/2019
//  Butchered by RobinInle on 14/01/2025 through 6/01/2025

// Icons made by https://www.flaticon.com/authors/daniel-bruce Daniel Bruce from https://www.flaticon.com/ Flaticon" is licensed by  http://creativecommons.org/licenses/by/3.0/  CC 3.0 BY


#import "ViewController.h"
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>

@interface ViewController ()

@property (nonatomic, strong) id wkWebView;         // We'll dynamically create WKWebView at runtime
@property (nonatomic, strong) id wkConfiguration;   // We'll dynamically create WKWebViewConfiguration

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 1) Attempt to disable Apple TV screensaver (idle timer) via runtime
    //    Because [UIApplication sharedApplication].idleTimerDisabled = YES
    //    is publicly "unavailable" on tvOS.
    [self disableIdleTimerIfPossible];
    
    // 2) Set up audio session so embedded <audio> or <video> in the webpage
    //    can actually play sound. This is the usual iOS code—tvOS typically
    //    respects it for audio output.
    [self setupAudioSession];
    
    // 3) Dynamically create WKWebViewConfiguration + WKWebView
    [self createWKWebView];
    
    // 4) Finally, load the MagicMirror page
    [self loadMagicMirror];
}

#pragma mark - (1) Attempt to Disable Screensaver

- (void)disableIdleTimerIfPossible {
    Class uiApplicationClass = NSClassFromString(@"UIApplication");
    if (uiApplicationClass) {
        SEL sharedAppSel = NSSelectorFromString(@"sharedApplication");
        if ([uiApplicationClass respondsToSelector:sharedAppSel]) {
            // Get UIApplication instance
            id sharedApplication = [uiApplicationClass performSelector:sharedAppSel];
            
            // Attempt setIdleTimerDisabled:YES
            SEL setIdleTimerDisabledSEL = NSSelectorFromString(@"setIdleTimerDisabled:");
            if ([sharedApplication respondsToSelector:setIdleTimerDisabledSEL]) {
                // Because 'performSelector' takes object, pass @(YES)
                [sharedApplication performSelector:setIdleTimerDisabledSEL
                                         withObject:@(YES)];
            }
        }
    }
}

#pragma mark - (2) Audio Session

- (void)setupAudioSession {
    // For iOS/tvOS, this is typically enough to allow media playback:
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    
    // Use Playback category so audio can play even if there's no user “interaction”.
    [session setCategory:AVAudioSessionCategoryPlayback error:&error];
    if (error) {
        NSLog(@"Error setting audio category: %@", error.localizedDescription);
    }
    
    [session setActive:YES error:&error];
    if (error) {
        NSLog(@"Error activating audio session: %@", error.localizedDescription);
    }
}

#pragma mark - (3) Create WKWebView Dynamically

- (void)createWKWebView {
    Class WKWebViewConfigurationClass = NSClassFromString(@"WKWebViewConfiguration");
    Class WKWebViewClass = NSClassFromString(@"WKWebView");
    
    if (!WKWebViewConfigurationClass || !WKWebViewClass) {
        NSLog(@"WKWebView or WKWebViewConfiguration not available on this tvOS version.");
        return;
    }
    
    // --- Create a WKWebViewConfiguration ---
    self.wkConfiguration = [[WKWebViewConfigurationClass alloc] init];
    
    // If you want to allow autoplay, inline media playback, etc.
    // For iOS it might be .requiresUserActionForMediaPlayback = NO, etc.
    // We'll do it with the same dynamic approach:
    
    // Example: set "requiresUserActionForMediaPlayback" = NO
    SEL setReqUserActionSEL = NSSelectorFromString(@"setRequiresUserActionForMediaPlayback:");
    if ([self.wkConfiguration respondsToSelector:setReqUserActionSEL]) {
        [self.wkConfiguration performSelector:setReqUserActionSEL withObject:@(NO)];
    }
    
    // Example: set "allowsInlineMediaPlayback" = YES
    SEL setInlineSEL = NSSelectorFromString(@"setAllowsInlineMediaPlayback:");
    if ([self.wkConfiguration respondsToSelector:setInlineSEL]) {
        [self.wkConfiguration performSelector:setInlineSEL withObject:@(YES)];
    }
    
    // --- Allocate WKWebView ---
    id wkWebViewAlloc = [WKWebViewClass alloc];
    SEL initSelector = NSSelectorFromString(@"initWithFrame:configuration:");
    
    // We'll use NSInvocation because initWithFrame:configuration: takes a CGRect
    if ([wkWebViewAlloc respondsToSelector:initSelector]) {
        NSMethodSignature *signature = [wkWebViewAlloc methodSignatureForSelector:initSelector];
        if (signature) {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:wkWebViewAlloc];
            [invocation setSelector:initSelector];
            
            // Pass the CGRect by reference
            CGRect frame = self.view.bounds;
            [invocation setArgument:&frame atIndex:2];
            
            // Pass the configuration object
            id configArg = self.wkConfiguration;
            [invocation setArgument:&configArg atIndex:3];
            
            [invocation invoke];
            
            id result = nil;
            [invocation getReturnValue:&result];
            self.wkWebView = result;
        }
    }
    
    // If we still have no wkWebView, fallback to init?
    if (!self.wkWebView) {
        self.wkWebView = [[WKWebViewClass alloc] init];
        // setFrame if needed
        if ([self.wkWebView respondsToSelector:@selector(setFrame:)]) {
            [self.wkWebView performSelector:@selector(setFrame:)
                                 withObject:[NSValue valueWithCGRect:self.view.bounds]];
        }
    }
    
    // Turn off scrolling if you want a purely static kiosk
    if ([self.wkWebView respondsToSelector:@selector(scrollView)]) {
        UIScrollView *scrollView = [self.wkWebView performSelector:@selector(scrollView)];
        scrollView.scrollEnabled = NO;
        scrollView.bounces = NO;
    }
    
    // Add to the view
    if ([self.wkWebView isKindOfClass:[UIView class]]) {
        [self.view addSubview:(UIView *)self.wkWebView];
    }
    
    // Optional: set navigationDelegate
    SEL setNavDelegateSEL = NSSelectorFromString(@"setNavigationDelegate:");
    if ([self.wkWebView respondsToSelector:setNavDelegateSEL]) {
        [self.wkWebView performSelector:setNavDelegateSEL withObject:self];
    }
}

- (void)loadMagicMirror {
    NSURL *url = [NSURL URLWithString:@"http://192.168.1.198:8099"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    // loadRequest:
    SEL loadRequestSEL = NSSelectorFromString(@"loadRequest:");
    if ([self.wkWebView respondsToSelector:loadRequestSEL]) {
        [self.wkWebView performSelector:loadRequestSEL withObject:request];
    }
}

#pragma mark - “Fake” WKNavigationDelegate

// If TV’s WebKit calls these delegate methods, you'll see logs:
- (void)webView:(id)webView didFinishNavigation:(id)navigation {
    NSLog(@"Finished loading MagicMirror page in WKWebView (audio/click/etc. might be available).");
}
- (void)webView:(id)webView didFailNavigation:(id)navigation withError:(NSError *)error {
    NSLog(@"Failed to load MagicMirror page: %@", error.localizedDescription);
}

#pragma mark - Remote / Menu Handling

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    UIPress *press = presses.anyObject;
    if (press.type == UIPressTypeMenu) {
        // Quit the app on Menu press
        exit(EXIT_SUCCESS);
    }
    [super pressesEnded:presses withEvent:event];
}

@end
