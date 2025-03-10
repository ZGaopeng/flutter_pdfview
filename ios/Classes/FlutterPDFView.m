// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#import "FlutterPDFView.h"

@implementation FLTPDFViewFactory {
    NSObject<FlutterBinaryMessenger>* _messenger;
}

- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger>*)messenger {
    self = [super init];
    if (self) {
        _messenger = messenger;
    }
    return self;
}

- (NSObject<FlutterMessageCodec>*)createArgsCodec {
    return [FlutterStandardMessageCodec sharedInstance];
}

- (NSObject<FlutterPlatformView>*)createWithFrame:(CGRect)frame
                                   viewIdentifier:(int64_t)viewId
                                        arguments:(id _Nullable)args {
    FLTPDFViewController* pdfviewController = [[FLTPDFViewController alloc] initWithFrame:frame
                                                                           viewIdentifier:viewId
                                                                                arguments:args
                                                                          binaryMessenger:_messenger];
    return pdfviewController;
}

@end

@implementation FLTPDFViewController {
    PDFView* _pdfView;
    int64_t _viewId;
    FlutterMethodChannel* _channel;
    NSNumber* _pageCount;
    NSNumber* _currentPage;
    BOOL _preventLinkNavigation;
}

- (instancetype)initWithFrame:(CGRect)frame
               viewIdentifier:(int64_t)viewId
                    arguments:(id _Nullable)args
              binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger {
    if ([super init]) {
        _viewId = viewId;
        
        NSString* channelName = [NSString stringWithFormat:@"plugins.endigo.io/pdfview_%lld", viewId];
        _channel = [FlutterMethodChannel methodChannelWithName:channelName binaryMessenger:messenger];
        
        _pdfView = [[PDFView alloc] initWithFrame: [[UIScreen mainScreen] bounds]];
        __weak __typeof__(self) weakSelf = self;
        _pdfView.delegate = self;
        
        
        [_channel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
            [weakSelf onMethodCall:call result:result];
        }];
        
        BOOL autoSpacing = [args[@"autoSpacing"] boolValue];
        BOOL pageFling = [args[@"pageFling"] boolValue];
        BOOL enableSwipe = [args[@"enableSwipe"] boolValue];
        _preventLinkNavigation = [args[@"preventLinkNavigation"] boolValue];
        
        NSInteger defaultPage = [args[@"defaultPage"] integerValue];

        NSString* filePath = args[@"filePath"];
        FlutterStandardTypedData* pdfData = args[@"pdfData"];

        PDFDocument* document;
        if ([filePath isKindOfClass:[NSString class]]) {
            NSURL* sourcePDFUrl = [NSURL fileURLWithPath:filePath];
            document = [[PDFDocument alloc] initWithURL: sourcePDFUrl];
        } else if ([pdfData isKindOfClass:[FlutterStandardTypedData class]]) {
            NSData* sourcePDFdata = [pdfData data];
            document = [[PDFDocument alloc] initWithData: sourcePDFdata];
        }

        if (document == nil) {
            [_channel invokeMethod:@"onError" arguments:@{@"error" : @"cannot create document: File not in PDF format or corrupted."}];
        } else {
            _pdfView.minScaleFactor = _pdfView.scaleFactorForSizeToFit * 0.1;
            _pdfView.maxScaleFactor = 4.0;
            _pdfView.scaleFactor = _pdfView.scaleFactorForSizeToFit;

            _pdfView.autoresizesSubviews = YES;
            _pdfView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            _pdfView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
            BOOL swipeHorizontal = [args[@"swipeHorizontal"] boolValue];
            if (swipeHorizontal) {
                _pdfView.displayDirection = kPDFDisplayDirectionHorizontal;
            } else {
                _pdfView.displayDirection = kPDFDisplayDirectionVertical;
            }

            [_pdfView usePageViewController:pageFling withViewOptions:nil];
            _pdfView.displayMode = enableSwipe ? kPDFDisplaySinglePageContinuous : kPDFDisplaySinglePage;
            _pdfView.document = document;
            _pdfView.autoScales = autoSpacing;
            NSString* password = args[@"password"];
            if ([password isKindOfClass:[NSString class]] && [_pdfView.document isEncrypted]) {
                [_pdfView.document unlockWithPassword:password];
            }

            UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onDoubleTap:)];
            tapGestureRecognizer.numberOfTapsRequired = 2;
            tapGestureRecognizer.numberOfTouchesRequired = 1;
            [_pdfView addGestureRecognizer:tapGestureRecognizer];

            NSUInteger pageCount = [document pageCount];

            if (pageCount <= defaultPage) {
                defaultPage = pageCount - 1;
            }

             PDFPage* page = [document pageAtIndex: defaultPage];
             [_pdfView goToPage: page];
            
            /// 修复iOS不能按照屏宽展示的问题
            PDFPage* pageInitial = [document pageAtIndex: 0];
            CGRect pageRectInitial = [pageInitial boundsForBox:[_pdfView displayBox]];
            CGRect parentRectInitial = [[UIScreen mainScreen] bounds];
            
            if (frame.size.width > 0 && frame.size.height > 0) {
                parentRectInitial = frame;
            }else {
                NSLog(@"FRAME size is 0....");
            }
            CGFloat scaleInitial = 1.0f;
            CGFloat parentWidth = parentRectInitial.size.width;
            CGFloat parentHeight = parentRectInitial.size.width;
            
            CGFloat pageWidth = pageRectInitial.size.width + 8;
            CGFloat pageHeight = pageRectInitial.size.width + 10;
            
            CGFloat parentScale = parentWidth / parentHeight;
            CGFloat pageScale = pageWidth / pageHeight;
            
            if (parentScale >= pageScale) {
                scaleInitial = parentHeight / pageHeight;
            } else {
                scaleInitial = parentWidth / pageWidth;
            }
            _pdfView.scaleFactor = scaleInitial;

            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf handleRenderCompleted:[NSNumber numberWithUnsignedLong: [document pageCount]]];
            });
        }
        
        if (@available(iOS 11.0, *)) {
            UIScrollView *_scrollView;

            for (id subview in _pdfView.subviews) {
                if ([subview isKindOfClass: [UIScrollView class]]) {
                    _scrollView = subview;
                }
            }
            
            _scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
            if (@available(iOS 13.0, *)) {
                _scrollView.automaticallyAdjustsScrollIndicatorInsets = NO;
            }
        }
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handlePageChanged:) name:PDFViewPageChangedNotification object:_pdfView];
        
    }
    return self;
}

- (UIView*)view {
    return _pdfView;
}


- (void)onMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([[call method] isEqualToString:@"pageCount"]) {
        [self getPageCount:call result:result];
    } else if ([[call method] isEqualToString:@"currentPage"]) {
        [self getCurrentPage:call result:result];
    } else if ([[call method] isEqualToString:@"setPage"]) {
        [self setPage:call result:result];
    } else if ([[call method] isEqualToString:@"updateSettings"]) {
        [self onUpdateSettings:call result:result];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)getPageCount:(FlutterMethodCall*)call result:(FlutterResult)result {
    _pageCount = [NSNumber numberWithUnsignedLong: [[_pdfView document] pageCount]];
    result(_pageCount);
}

- (void)getCurrentPage:(FlutterMethodCall*)call result:(FlutterResult)result {
    _currentPage = [NSNumber numberWithUnsignedLong: [_pdfView.document indexForPage: _pdfView.currentPage]];
    result(_currentPage);
}

- (void)setPage:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSDictionary<NSString*, NSNumber*>* arguments = [call arguments];
    NSNumber* page = arguments[@"page"];
    
    [_pdfView goToPage: [_pdfView.document pageAtIndex: page.unsignedLongValue ]];
    result([NSNumber numberWithBool: YES]);
}

- (void)onUpdateSettings:(FlutterMethodCall*)call result:(FlutterResult)result {
    result(nil);
}

-(void)handlePageChanged:(NSNotification*)notification {
    [_channel invokeMethod:@"onPageChanged" arguments:@{@"page" : [NSNumber numberWithUnsignedLong: [_pdfView.document indexForPage: _pdfView.currentPage]], @"total" : [NSNumber numberWithUnsignedLong: [_pdfView.document pageCount]]}];
}

-(void)handleRenderCompleted: (NSNumber*)pages {
    [_channel invokeMethod:@"onRender" arguments:@{@"pages" : pages}];
}

- (void)PDFViewWillClickOnLink:(PDFView *)sender
                       withURL:(NSURL *)url{
    if (!_preventLinkNavigation){
        [[UIApplication sharedApplication] openURL:url];
    }
    [_channel invokeMethod:@"onLinkHandler" arguments:url.absoluteString];
}

- (void) onDoubleTap: (UITapGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        if ([_pdfView scaleFactor] == _pdfView.scaleFactorForSizeToFit) {
            CGPoint point = [recognizer locationInView:_pdfView];
            PDFPage* page = [_pdfView pageForPoint:point nearest:YES];
            PDFPoint pdfPoint = [_pdfView convertPoint:point toPage:page];
            PDFRect rect = [page boundsForBox:kPDFDisplayBoxMediaBox];
            PDFDestination* destination = [[PDFDestination alloc] initWithPage:page atPoint:CGPointMake(pdfPoint.x - (rect.size.width / 4),pdfPoint.y + (rect.size.height / 4))];
            [UIView animateWithDuration:0.2 animations:^{
                self-> _pdfView.scaleFactor = self->_pdfView.scaleFactorForSizeToFit *2;
                [self->_pdfView goToDestination:destination];
            }];
        } else {
          [UIView animateWithDuration:0.2 animations:^{
            self->_pdfView.scaleFactor = self->_pdfView.scaleFactorForSizeToFit;
          }];
        }
    }
}

@end
