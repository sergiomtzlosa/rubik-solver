//
//  AppDelegate.mm
//  RubikSolver
//

#import "AppDelegate.h"
#import "MainWindowController.h"
#import "RubikHelpWindowController.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self setupMainMenu];

    self.mainWindowController = [[MainWindowController alloc] init];
    [self.mainWindowController showWindow:nil];
    [self.mainWindowController.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)setupMainMenu {
    NSMenu* menubar = [[NSMenu alloc] init];

    // App Menu
    NSMenuItem* appMenuItem = [[NSMenuItem alloc] init];
    [menubar addItem:appMenuItem];

    NSMenu* appMenu = [[NSMenu alloc] init];
    NSString* appName = @"RubikSolver";

    [appMenu addItemWithTitle:[NSString stringWithFormat:@"About %@", appName]
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:[NSString stringWithFormat:@"Hide %@", appName]
                       action:@selector(hide:)
                keyEquivalent:@"h"];

    NSMenuItem* hideOthers = [appMenu addItemWithTitle:@"Hide Others"
                                                action:@selector(hideOtherApplications:)
                                         keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagOption | NSEventModifierFlagCommand;

    [appMenu addItemWithTitle:@"Show All"
                       action:@selector(unhideAllApplications:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:[NSString stringWithFormat:@"Quit %@", appName]
                       action:@selector(terminate:)
                keyEquivalent:@"q"];

    appMenuItem.submenu = appMenu;

    // File Menu
    NSMenuItem* fileMenuItem = [[NSMenuItem alloc] init];
    [menubar addItem:fileMenuItem];

    NSMenu* fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"Upload Cube Face Photos..." action:@selector(uploadFaceImageMenuAction:) keyEquivalent:@"u"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"w"];
    fileMenuItem.submenu = fileMenu;

    // Edit Menu (standard text editing for sheets and paste fields)
    NSMenuItem* editMenuItem = [[NSMenuItem alloc] init];
    [menubar addItem:editMenuItem];

    NSMenu* editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:NSSelectorFromString(@"undo:") keyEquivalent:@"z"];
    NSMenuItem* redo = [editMenu addItemWithTitle:@"Redo" action:NSSelectorFromString(@"redo:") keyEquivalent:@"z"];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editMenuItem.submenu = editMenu;

    // View Menu
    NSMenuItem* viewMenuItem = [[NSMenuItem alloc] init];
    [menubar addItem:viewMenuItem];

    NSMenu* viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [viewMenu addItemWithTitle:@"Center 3D View in Viewport" action:@selector(centerView3DMenuAction:) keyEquivalent:@"0"];
    [viewMenu addItemWithTitle:@"Reset Camera" action:@selector(centerView3DMenuAction:) keyEquivalent:@""];
    viewMenuItem.submenu = viewMenu;

    // Actions Menu
    NSMenuItem* actionsMenuItem = [[NSMenuItem alloc] init];
    [menubar addItem:actionsMenuItem];

    NSMenu* actionsMenu = [[NSMenu alloc] initWithTitle:@"Actions"];
    [actionsMenu addItemWithTitle:@"Random Cube & Solve" action:@selector(randomSolveMenuAction:) keyEquivalent:@"r"];
    [actionsMenu addItemWithTitle:@"Generate Random Cube..." action:@selector(openRandomGeneratorMenuAction:) keyEquivalent:@"R"];
    [actionsMenu addItemWithTitle:@"Solve Current Cube" action:@selector(solveCubeMenuAction:) keyEquivalent:@"s"];
    NSMenuItem* stopItem = [actionsMenu addItemWithTitle:@"Stop Solver" action:@selector(stopSolverMenuAction:) keyEquivalent:@"."];
    stopItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [actionsMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* cameraItem = [actionsMenu addItemWithTitle:@"Scan Cube with Camera..."
                                                    action:@selector(cameraScannerMenuAction:)
                                             keyEquivalent:@"k"];
    cameraItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    NSMenuItem* copyState = [actionsMenu addItemWithTitle:@"Copy Cube State for OpenCode"
                                                   action:@selector(copyCubeStateMenuAction:)
                                            keyEquivalent:@"c"];
    copyState.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [actionsMenu addItem:[NSMenuItem separatorItem]];
    [actionsMenu addItemWithTitle:@"Reset Cube to Solved" action:@selector(resetCubeMenuAction:) keyEquivalent:@"k"];
    actionsMenuItem.submenu = actionsMenu;

    // Window Menu
    NSMenuItem* windowMenuItem = [[NSMenuItem alloc] init];
    [menubar addItem:windowMenuItem];

    NSMenu* windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
    windowMenuItem.submenu = windowMenu;

    // Help Menu
    NSMenuItem* helpMenuItem = [[NSMenuItem alloc] init];
    [menubar addItem:helpMenuItem];

    NSMenu* helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    [helpMenu addItemWithTitle:@"Rubik's Solver Help"
                        action:@selector(showHelp:)
                 keyEquivalent:@"?"];
    helpMenuItem.submenu = helpMenu;

    [NSApp setMainMenu:menubar];
    [NSApp setWindowsMenu:windowMenu];
    [NSApp setHelpMenu:helpMenu];
}

- (void)showHelp:(id)sender {
    [[RubikHelpWindowController sharedHelpController] showHelpWindow];
}

- (void)uploadFaceImageMenuAction:(id)sender {
    [self.mainWindowController uploadFaceImage];
}

- (void)randomSolveMenuAction:(id)sender {
    [self.mainWindowController generateRandomCubeAndSolveDefault];
}

- (void)openRandomGeneratorMenuAction:(id)sender {
    [self.mainWindowController openRandomCubeGeneratorSheet];
}

- (void)solveCubeMenuAction:(id)sender {
    [self.mainWindowController solveWithMetalGPU];
}

- (void)stopSolverMenuAction:(id)sender {
    [self.mainWindowController stopSolver];
}

- (void)cameraScannerMenuAction:(id)sender {
    [self.mainWindowController toggleCameraScanner];
}

- (void)copyCubeStateMenuAction:(id)sender {
    [self.mainWindowController copyCubeStateForOpenCode];
}

- (void)resetCubeMenuAction:(id)sender {
    [self.mainWindowController resetCubeToSolved];
}

- (void)centerView3DMenuAction:(id)sender {
    [self.mainWindowController resetView3DToViewport];
}

@end
