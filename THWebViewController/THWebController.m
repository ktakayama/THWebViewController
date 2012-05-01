//
// Copyright 2011 Roger Chapman
// Copyright 2011 Benedikt Meurer
// Copyright 2012 Tokunaga HIromu
//
// Forked from Three20 July 29, 2011 - Copyright 2009-2011 Facebook
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "THWebController.h"

#define NI_RELEASE_SAFELY(__POINTER) { [__POINTER release]; __POINTER = nil; }

static CGRect NIRectContract(CGRect rect, CGFloat dx, CGFloat dy) {
    return CGRectMake(rect.origin.x, rect.origin.y, rect.size.width - dx, rect.size.height - dy);
}

static BOOL NIIsPad(void) {
#ifdef UI_USER_INTERFACE_IDIOM
    static NSInteger isPad = -1;
    if (isPad < 0) {
        isPad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
    }
    return isPad > 0;
#else
    return NO;
#endif
}

static CGFloat NIToolbarHeightForOrientation(UIInterfaceOrientation orientation) {
    return (NIIsPad()
            ? 44
            : (UIInterfaceOrientationIsPortrait(orientation)
               ? 44
               : 33));;
}

static UIInterfaceOrientation NIInterfaceOrientation(void) {
    UIInterfaceOrientation orient = [UIApplication sharedApplication].statusBarOrientation;
    
    // This code used to use the navigator to find the currently visible view controller and
    // fall back to checking its orientation if we didn't know the status bar's orientation.
    // It's unclear when this was actually necessary, though, so this assertion is here to try
    // to find that case. If this assertion fails then the repro case needs to be analyzed and
    // this method made more robust to handle that case.
    // XXX NSParameterAssert(UIDeviceOrientationUnknown != orient);
    
    return orient;
}

static NSString* NIPathForBundleResource(NSBundle* bundle, NSString* relativePath) {
    NSString* resourcePath = [(nil == bundle ? [NSBundle mainBundle] : bundle) resourcePath];
    return [resourcePath stringByAppendingPathComponent:relativePath];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
@implementation THWebController

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)releaseAllSubviews {
  _actionSheet.delegate = nil;
  _webView.delegate = nil;

  NI_RELEASE_SAFELY(_actionSheet);
  NI_RELEASE_SAFELY(_webView);
  NI_RELEASE_SAFELY(_toolbar);
  NI_RELEASE_SAFELY(_titleLabel);
  NI_RELEASE_SAFELY(_backButton);
  NI_RELEASE_SAFELY(_forwardButton);
  NI_RELEASE_SAFELY(_refreshButton);
  NI_RELEASE_SAFELY(_stopButton);
  NI_RELEASE_SAFELY(_actionButton);
  NI_RELEASE_SAFELY(_activityItem);
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)dealloc {
  NI_RELEASE_SAFELY(_actionSheetURL);
  NI_RELEASE_SAFELY(_loadingURL);
  [self releaseAllSubviews];

  [super dealloc];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
  if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
    self.hidesBottomBarWhenPushed = YES;
  }
  return self;
}

- (id)init {
    self = [self initWithNibName:nil bundle:nil];
    return self;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Private

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)backAction {
  [_webView goBack];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)forwardAction {
  [_webView goForward];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)refreshAction {
  [_webView reload];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)stopAction {
  [_webView stopLoading];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)shareAction {
  // Dismiss the action menu if the user taps the action button again on the iPad.
  if ([_actionSheet isVisible]) {
    // It shouldn't be possible to tap the share action button again on anything but the iPad.
    NSParameterAssert(NIIsPad());

    [_actionSheet dismissWithClickedButtonIndex:[_actionSheet cancelButtonIndex] animated:YES];

    // We remove the action sheet here just in case the delegate isn't properly implemented.
    _actionSheet.delegate = nil;
    NI_RELEASE_SAFELY(_actionSheet);
    NI_RELEASE_SAFELY(_actionSheetURL);

    // Don't show the menu again.
    return;
  }

  // Remember the URL at this point
  [_actionSheetURL release];
  _actionSheetURL = [self.URL copy];

  if (nil == _actionSheet) {
    _actionSheet =
    [[UIActionSheet alloc] initWithTitle:[_actionSheetURL absoluteString]
                                delegate:self
                       cancelButtonTitle:nil
                  destructiveButtonTitle:nil
                       otherButtonTitles:nil];
    // Let -shouldPresentActionSheet: setup the action sheet
    if (![self shouldPresentActionSheet:_actionSheet]) {
      // A subclass decided to handle the action in another way
      NI_RELEASE_SAFELY(_actionSheet);
      NI_RELEASE_SAFELY(_actionSheetURL);
      return;
    }
    // Add "Cancel" button except for iPads
    if (!NIIsPad()) {
      [_actionSheet setCancelButtonIndex:[_actionSheet addButtonWithTitle:NSLocalizedString(@"Cancel", @"")]];
    }
  }

  if (NIIsPad()) {
    [_actionSheet showFromBarButtonItem:_actionButton animated:YES];
  } else {
    [_actionSheet showInView:self.view];
  }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)updateToolbarWithOrientation:(UIInterfaceOrientation)interfaceOrientation {

  CGRect toolbarFrame = _toolbar.frame;
  toolbarFrame.size.height = NIToolbarHeightForOrientation(interfaceOrientation);
  toolbarFrame.origin.y = self.view.bounds.size.height - toolbarFrame.size.height;
  _toolbar.frame = toolbarFrame;

  CGRect webViewFrame = _webView.frame;
  webViewFrame.size.height = self.view.bounds.size.height - toolbarFrame.size.height;
  _webView.frame = webViewFrame;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark UIViewController

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)loadView {
  [super loadView];

  CGRect bounds = self.view.bounds;

  CGFloat toolbarHeight = NIToolbarHeightForOrientation(NIInterfaceOrientation());
  CGRect toolbarFrame = CGRectMake(0, bounds.size.height - toolbarHeight,
                                   bounds.size.width, toolbarHeight);

  _toolbar = [[UIToolbar alloc] initWithFrame:toolbarFrame];
  _toolbar.autoresizingMask = (UIViewAutoresizingFlexibleTopMargin
                               | UIViewAutoresizingFlexibleWidth);

  UIActivityIndicatorView* spinner =
  [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:
    UIActivityIndicatorViewStyleWhite] autorelease];
  [spinner startAnimating];
  _activityItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];

  UIImage* backIcon = [UIImage imageWithContentsOfFile:
                      NIPathForBundleResource(nil, @"THWebController.bundle/gfx/backIcon.png")];
  // We weren't able to find the forward or back icons in your application's resources.
  // Ensure that you've dragged the NimbusWebController.bundle from src/webcontroller/resources
  //into your application with the "Create Folder References" option selected. You can verify that
  // you've done this correctly by expanding the NimbusPhotos.bundle file in your project
  // and verifying that the 'gfx' directory is blue. Also verify that the bundle is being
  // copied in the Copy Bundle Resources phase.
  NSParameterAssert(nil != backIcon);

  _backButton =
  [[UIBarButtonItem alloc] initWithImage:backIcon
                                   style:UIBarButtonItemStylePlain
                                  target:self
                                  action:@selector(backAction)];
  _backButton.tag = 2;
  _backButton.enabled = NO;

  UIImage* forwardIcon = [UIImage imageWithContentsOfFile:
                  NIPathForBundleResource(nil, @"THWebController.bundle/gfx/forwardIcon.png")];
  // We weren't able to find the forward or back icons in your application's resources.
  // Ensure that you've dragged the NimbusWebController.bundle from src/webcontroller/resources
  // into your application with the "Create Folder References" option selected. You can verify that
  // you've done this correctly by expanding the NimbusPhotos.bundle file in your project
  // and verifying that the 'gfx' directory is blue. Also verify that the bundle is being
  // copied in the Copy Bundle Resources phase.
  NSParameterAssert(nil != forwardIcon);

  _forwardButton =
  [[UIBarButtonItem alloc] initWithImage:forwardIcon
                                   style:UIBarButtonItemStylePlain
                                  target:self
                                  action:@selector(forwardAction)];
  _forwardButton.tag = 1;
  _forwardButton.enabled = NO;
  _refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:
                    UIBarButtonSystemItemRefresh target:self action:@selector(refreshAction)];
  _refreshButton.tag = 3;
  _stopButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:
                 UIBarButtonSystemItemStop target:self action:@selector(stopAction)];
  _stopButton.tag = 3;
  _actionButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:
                   UIBarButtonSystemItemAction target:self action:@selector(shareAction)];

  UIBarButtonItem *fixedSpace =
  [[[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemFixedSpace
                                                 target: nil
                                                 action: nil] autorelease];
  fixedSpace.width = 10;

  UIBarItem* flexibleSpace =
  [[[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemFlexibleSpace
                                                 target: nil
                                                 action: nil] autorelease];

  if (NIIsPad()) {
     fixedSpace.width = 20;
     _toolbar.items = [NSArray arrayWithObjects:
                       flexibleSpace,
                       _backButton,
                       fixedSpace,
                       _forwardButton,
                       fixedSpace,
                       _refreshButton,
                       fixedSpace,
                       _actionButton,
                       fixedSpace,
                       nil];
  } else {
     _toolbar.items = [NSArray arrayWithObjects:
                       _backButton,
                       flexibleSpace,
                       _forwardButton,
                       fixedSpace,
                       flexibleSpace,
                       _refreshButton,
                       flexibleSpace,
                       _actionButton,
                       nil];
  }
  [self.view addSubview:_toolbar];

  CGRect webViewFrame = NIRectContract(bounds, 0, toolbarHeight);

  _webView = [[UIWebView alloc] initWithFrame:webViewFrame];
  _webView.delegate = self;
  _webView.autoresizingMask = (UIViewAutoresizingFlexibleWidth
                               | UIViewAutoresizingFlexibleHeight);
  _webView.scalesPageToFit = YES;
    {
        UIScrollView *subScrollView;
        if ([[[UIDevice currentDevice] systemVersion] floatValue] < 5.0) {
            for (UIView *subview in [_webView subviews]) {
                if ([[subview.class description] isEqualToString:@"UIScrollView"]) {
                    subScrollView = (UIScrollView *)subview;
                }
            }
        }else {
            subScrollView = (UIScrollView *)[_webView scrollView];
        }
        subScrollView.decelerationRate = UIScrollViewDecelerationRateNormal;
    }
  [self.view addSubview:_webView];

}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void) viewDidLoad {
   [super viewDidLoad];
   UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 400, 40)];
   label.backgroundColor = [UIColor clearColor];
   label.font = [UIFont boldSystemFontOfSize:12.0];
   label.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.5];
   label.textColor = [UIColor whiteColor];
   label.textAlignment = UITextAlignmentCenter;
   label.minimumFontSize = 8.0f;
   label.numberOfLines = 2;
   label.text = self.title;
   self.navigationItem.titleView = label;
   _titleLabel = [label retain];
   [label release];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)viewDidUnload {
  [super viewDidUnload];

  [self releaseAllSubviews];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self updateToolbarWithOrientation:self.interfaceOrientation];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)viewWillDisappear:(BOOL)animated {
  // If the browser launched the media player, it steals the key window and never gives it
  // back, so this is a way to try and fix that.
  [self.view.window makeKeyWindow];

  [super viewWillDisappear:animated];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (NIIsPad()) {
        return YES;
    } else {
        switch (interfaceOrientation) {
            case UIInterfaceOrientationPortrait:
            case UIInterfaceOrientationLandscapeLeft:
            case UIInterfaceOrientationLandscapeRight:
                return YES;
            default:
                return NO;
        }
    }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
                                         duration:(NSTimeInterval)duration {
  [super willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
  [self updateToolbarWithOrientation:toInterfaceOrientation];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark UIWebViewDelegate

///////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)webView:(UIWebView*)webView shouldStartLoadWithRequest:(NSURLRequest*)request
 navigationType:(UIWebViewNavigationType)navigationType {

  NSString *requestedHost = [[request mainDocumentURL] host];
  if([requestedHost isEqualToString:@"itunes.apple.com"]) {
    [[UIApplication sharedApplication] openURL:[request URL]];
    return NO;
  }

  [_loadingURL release];
  _loadingURL = [request.mainDocumentURL copy];
  _backButton.enabled = [_webView canGoBack];
  _forwardButton.enabled = [_webView canGoForward];
  return YES;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)webViewDidStartLoad:(UIWebView*)webView {

  if (!self.navigationItem.rightBarButtonItem) {
    [self.navigationItem setRightBarButtonItem:_activityItem animated:YES];
  }

  NSInteger buttonIndex = 0;
  for (UIBarButtonItem* button in _toolbar.items) {
    if (button.tag == 3) {
      NSMutableArray* newItems = [NSMutableArray arrayWithArray:_toolbar.items];
      [newItems replaceObjectAtIndex:buttonIndex withObject:_stopButton];
      _toolbar.items = newItems;
      break;
    }
    ++buttonIndex;
  }
  _backButton.enabled = [_webView canGoBack];
  _forwardButton.enabled = [_webView canGoForward];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)webViewDidFinishLoad:(UIWebView*)webView {

  NI_RELEASE_SAFELY(_loadingURL);
  self.title = [_webView stringByEvaluatingJavaScriptFromString:@"document.title"];
  _titleLabel.text = self.title;
  if (self.navigationItem.rightBarButtonItem == _activityItem) {
    [self.navigationItem setRightBarButtonItem:nil animated:YES];
  }

  NSInteger buttonIndex = 0;
  for (UIBarButtonItem* button in _toolbar.items) {
    if (button.tag == 3) {
      NSMutableArray* newItems = [NSMutableArray arrayWithArray:_toolbar.items];
      [newItems replaceObjectAtIndex:buttonIndex withObject:_refreshButton];
      _toolbar.items = newItems;
      break;
    }
    ++buttonIndex;
  }

  _backButton.enabled = [_webView canGoBack];
  _forwardButton.enabled = [_webView canGoForward];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)webView:(UIWebView*)webView didFailLoadWithError:(NSError*)error {

  NI_RELEASE_SAFELY(_loadingURL);
  [self webViewDidFinishLoad:webView];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark UIActionSheetDelegate

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)actionSheet:(UIActionSheet*)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
  if (actionSheet == _actionSheet) {
    if (buttonIndex == 0) {
      [[UIApplication sharedApplication] openURL:_actionSheetURL];
    } else if (buttonIndex == 1) {
      [[UIPasteboard generalPasteboard] setURL:_actionSheetURL];
    }
  }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
  if (actionSheet == _actionSheet) {
    _actionSheet.delegate = nil;
    NI_RELEASE_SAFELY(_actionSheet);
    NI_RELEASE_SAFELY(_actionSheetURL);
  }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Public

///////////////////////////////////////////////////////////////////////////////////////////////////
- (NSURL *)URL {
  return _loadingURL ? _loadingURL : _webView.request.mainDocumentURL;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)openURL:(NSURL*)URL {
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:URL];
  [self openRequest:request];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)openRequest:(NSURLRequest*)request {
  // The view must be loaded before you call this method.
    // NIDASSERT([self isViewLoaded]);
  self.title = NSLocalizedString(@"Loading...", @"");
  _titleLabel.text = self.title;
  [self view];
  [_webView loadRequest:request];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)setToolbarHidden:(BOOL)hidden {
  _toolbar.hidden = hidden;
  if (hidden) {
    _webView.frame = self.view.bounds;

  } else {
    _webView.frame = NIRectContract(self.view.bounds, 0, _toolbar.frame.size.height);
  }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)setToolbarTintColor:(UIColor*)color {
  _toolbar.tintColor = color;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)shouldPresentActionSheet:(UIActionSheet *)actionSheet {
  if (actionSheet == _actionSheet) {
    [_actionSheet addButtonWithTitle:NSLocalizedString(@"Open in Safari", @"")];
    [_actionSheet addButtonWithTitle:NSLocalizedString(@"Copy URL", @"")];
  }
  return YES;
}

@end
