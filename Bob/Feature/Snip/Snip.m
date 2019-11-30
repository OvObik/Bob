//
//  Snip.m
//  Bob
//
//  Created by ripper on 2019/11/27.
//  Copyright © 2019 ripperhe. All rights reserved.
//

#import "Snip.h"

@interface Snip ()

@property (nonatomic, strong) NSMutableArray<SnipWindowController *> *windowControllers;
@property (nonatomic, copy) void(^completion)(NSImage * _Nullable image);
@property (nonatomic, strong) MMEventMonitor *localMouseMonitor;
@property (nonatomic, strong) MMEventMonitor *globalMouseMonitor;
@property (nonatomic, weak) SnipWindowController *currentMainWindowController;

@end

@implementation Snip

static Snip *_instance;
+ (instancetype)shared {
    if (!_instance) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            _instance = [[self alloc] init];
        });
    }
    return _instance;
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [super allocWithZone:zone];
    });
    return _instance;
}

- (NSMutableArray *)windowControllers {
    if (!_windowControllers) {
        _windowControllers = [NSMutableArray array];
    }
    return _windowControllers;
}

- (MMEventMonitor *)localMouseMonitor {
    if (!_localMouseMonitor) {
        _localMouseMonitor = [MMEventMonitor localMonitorWithEvent:NSEventMaskMouseMoved handler:^(NSEvent * _Nonnull event) {
            [self mouseMoved:event];
        }];
    }
    return _localMouseMonitor;
}

- (MMEventMonitor *)globalMouseMonitor {
    if (!_globalMouseMonitor) {
        _globalMouseMonitor = [MMEventMonitor globalMonitorWithEvent:NSEventMaskMouseMoved handler:^(NSEvent * _Nonnull event) {
            [self mouseMoved:event];
        }];
    }
    return _globalMouseMonitor;
}

- (void)startWithCompletion:(void (^)(NSImage * _Nullable))completion {
    if (self.isSnapshotting) {
        if (completion) {
            self.completion = completion;
        }
        return;
    }
    self.isSnapshotting = YES;
    self.completion = completion;
    
    [self.windowControllers enumerateObjectsUsingBlock:^(SnipWindowController * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [obj close];
    }];
    [self.windowControllers removeAllObjects];

    [NSScreen.screens enumerateObjectsUsingBlock:^(NSScreen * _Nonnull screen, NSUInteger idx, BOOL * _Nonnull stop) {
        SnipWindowController *windowController = [SnipWindowController new];
        [windowController setStartBlock:^(SnipWindowController * _Nonnull windowController) {
            NSLog(@"截图开始");
        }];
        [windowController setEndBlock:^(SnipWindowController * _Nonnull windowController, NSImage * _Nullable image) {
            NSLog(@"截图结束：%@", image ? @"成功" : @"失败");
             [Snip.shared stop];
            if (self.completion) {
                self.completion(image);
            }
        }];
        [windowController captureWithScreen:screen];
        [self.windowControllers addObject:windowController];
    }];
    
    [self.localMouseMonitor start];
    [self.globalMouseMonitor start];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(screenChanged:) name:NSWorkspaceActiveSpaceDidChangeNotification object:[NSWorkspace sharedWorkspace]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(screenChanged:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
    
    [self mouseMoved:nil];
}

- (void)stop {
    if (!self.isSnapshotting) {
        return;
    }
    self.isSnapshotting = NO;
    self.completion = nil;
    
    [self.windowControllers enumerateObjectsUsingBlock:^(SnipWindowController * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [obj close];
    }];
    [self.windowControllers removeAllObjects];
    
    [self.localMouseMonitor stop];
    [self.globalMouseMonitor stop];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}

#pragma mark -

- (void)mouseMoved:(NSEvent *)event {
    NSPoint mouseLocation = [NSEvent mouseLocation];
    if (!self.currentMainWindowController) {
        [self.windowControllers enumerateObjectsUsingBlock:^(SnipWindowController * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if (NSPointInRect(mouseLocation, obj.window.frame)) {
                self.currentMainWindowController = obj;
                [obj.window makeMainWindow];
                [obj.window makeKeyWindow];
                [obj.snipViewController showAndUpdateFocusView];
            }
        }];
        return;
    }
    
    if (NSPointInRect(mouseLocation, self.currentMainWindowController.window.frame)) {
        // 在当前的 main window
        [self.currentMainWindowController.snipViewController showAndUpdateFocusView];
    }else {
        // 不再当前 main window
        if (self.currentMainWindowController.snipViewController.isStart) {
            // 如果已经开始拖拽
            [self.currentMainWindowController.snipViewController showAndUpdateFocusView];
        }else {
            // 切换 main window
            __block SnipWindowController *newMain = nil;
            [self.windowControllers enumerateObjectsUsingBlock:^(SnipWindowController * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                if (NSPointInRect(mouseLocation, obj.window.frame)) {
                    newMain = obj;
                    *stop = YES;
                }
            }];
            if (newMain) {
                [self.currentMainWindowController.snipViewController hiddenFocusView];
                self.currentMainWindowController = newMain;
                [newMain.window makeMainWindow];
                [newMain.window makeKeyWindow];
                [newMain.snipViewController showAndUpdateFocusView];
            }else {
                [self.currentMainWindowController.snipViewController showAndUpdateFocusView];
            }
        }
    }
}

- (void)screenChanged:(NSNotification *)notification {
    NSLog(@"%@", notification);
    [self stop];
}

@end