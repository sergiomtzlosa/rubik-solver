//
//  Rubik3DView.mm
//  RubikSolver - 3D Interactive Animated Rubik's Cube Viewer
//

#import "Rubik3DView.h"

static const CGFloat kCubieSize = 0.94;
static const CGFloat kChamferRadius = 0.06;
static const CGFloat kCubieSpacing = 1.0;

@implementation Rubik3DView {
    SCNScene* _scene;
    SCNNode* _cubeRootNode;
    SCNNode* _cameraNode;
    NSMutableArray<SCNNode*>* _cubieNodes;
    NSMutableArray<NSDictionary*>* _animationQueue;
    BOOL _isAnimating;

    // Interactive Spherical Orbit Control
    CGFloat _cameraAzimuth;    // horizontal angle around Y-axis (radians)
    CGFloat _cameraElevation;  // vertical angle from X-Z plane (radians)
    CGFloat _cameraDistance;   // radial distance from origin (0, 0, 0)
    NSPoint _lastMouseLocation;
    BOOL _isDragging;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _animationDuration = 0.28;
        _isAnimating = NO;
        _animationQueue = [NSMutableArray array];
        _cubieNodes = [NSMutableArray arrayWithCapacity:26];

        [self setupScene];
        [self buildCube];
        [self centerCubeInBounds];
        [self setAccessibilityElement:YES];
        self.accessibilityRole = NSAccessibilityGroupRole;
        self.accessibilityLabel = @"3D cube view";
    }
    return self;
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self centerCubeInBounds];
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea* area in self.trackingAreas) {
        [self removeTrackingArea:area];
    }
    NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited |
                                    NSTrackingActiveInActiveApp |
                                    NSTrackingInVisibleRect |
                                    NSTrackingCursorUpdate;
    NSTrackingArea* area = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                        options:options
                                                          owner:self
                                                       userInfo:nil];
    [self addTrackingArea:area];
}

- (void)cursorUpdate:(NSEvent *)event {
    if (_isDragging) {
        [[NSCursor closedHandCursor] set];
    } else {
        [[NSCursor openHandCursor] set];
    }
}

- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];
    if (event.clickCount == 2) {
        [self centerCubeInBounds];
        return;
    }
    _lastMouseLocation = [self convertPoint:event.locationInWindow fromView:nil];
    _isDragging = YES;
    [[NSCursor closedHandCursor] push];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_isDragging) return;

    NSPoint currentLoc = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat dx = currentLoc.x - _lastMouseLocation.x;
    CGFloat dy = currentLoc.y - _lastMouseLocation.y;
    _lastMouseLocation = currentLoc;

    // Direct, ultra-smooth orbiting around the cube center
    const CGFloat kSensitivity = 0.0075;
    _cameraAzimuth -= dx * kSensitivity;
    _cameraElevation += dy * kSensitivity;

    [self updateCameraTransformAnimated:NO];
}

- (void)mouseUp:(NSEvent *)event {
    if (_isDragging) {
        _isDragging = NO;
        [NSCursor pop];
    }
}

- (void)rightMouseDown:(NSEvent *)event {
    _lastMouseLocation = [self convertPoint:event.locationInWindow fromView:nil];
    _isDragging = YES;
    [[NSCursor closedHandCursor] push];
}

- (void)rightMouseDragged:(NSEvent *)event {
    [self mouseDragged:event];
}

- (void)rightMouseUp:(NSEvent *)event {
    [self mouseUp:event];
}

- (void)scrollWheel:(NSEvent *)event {
    CGFloat delta = event.scrollingDeltaY;
    if (event.hasPreciseScrollingDeltas) {
        delta *= 0.05;
    } else {
        delta *= 0.4;
    }

    _cameraDistance -= delta;
    [self updateCameraTransformAnimated:NO];
}

- (void)keyDown:(NSEvent *)event {
    NSString* chars = event.charactersIgnoringModifiers;
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;

    if ((flags & NSEventModifierFlagCommand) && [chars isEqualToString:@"0"]) {
        [self centerCubeInBounds];
        return;
    }

    if ((flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) == 0) {
        if ([chars isEqualToString:@" "] || [chars isEqualToString:@"0"] ||
            [chars caseInsensitiveCompare:@"c"] == NSOrderedSame ||
            [chars caseInsensitiveCompare:@"v"] == NSOrderedSame) {
            [self centerCubeInBounds];
            return;
        }
    }

    [super keyDown:event];
}

- (BOOL)isAnimating {
    return _isAnimating;
}

- (void)setupScene {
    _scene = [SCNScene scene];
    self.scene = _scene;
    self.backgroundColor = [NSColor colorWithCalibratedRed:0.09 green:0.10 blue:0.12 alpha:1.0];
    self.autoenablesDefaultLighting = NO;
    self.antialiasingMode = SCNAntialiasingModeMultisampling4X;
    self.allowsCameraControl = NO; // Using direct custom orbit control for instant response

    // Default isometric angles
    _cameraAzimuth = 42.0 * M_PI / 180.0;
    _cameraElevation = 32.0 * M_PI / 180.0;
    _cameraDistance = 8.8;

    // Camera
    _cameraNode = [SCNNode node];
    _cameraNode.camera = [SCNCamera camera];
    _cameraNode.camera.zNear = 0.1;
    _cameraNode.camera.zFar = 100.0;
    _cameraNode.camera.fieldOfView = 38;
    [_scene.rootNode addChildNode:_cameraNode];

    [self updateCameraTransformAnimated:NO];
    self.pointOfView = _cameraNode;

    // Lighting: Key Light (Soft directional with shadows)
    SCNNode* keyLightNode = [SCNNode node];
    keyLightNode.light = [SCNLight light];
    keyLightNode.light.type = SCNLightTypeDirectional;
    keyLightNode.light.color = [NSColor colorWithCalibratedWhite:1.0 alpha:1.0];
    keyLightNode.light.castsShadow = YES;
    keyLightNode.position = SCNVector3Make(5, 10, 8);
    keyLightNode.eulerAngles = SCNVector3Make(-M_PI / 4, M_PI / 6, 0);
    [_scene.rootNode addChildNode:keyLightNode];

    // Fill Light
    SCNNode* fillLightNode = [SCNNode node];
    fillLightNode.light = [SCNLight light];
    fillLightNode.light.type = SCNLightTypeDirectional;
    fillLightNode.light.color = [NSColor colorWithCalibratedRed:0.4 green:0.45 blue:0.55 alpha:1.0];
    fillLightNode.position = SCNVector3Make(-6, -4, -6);
    fillLightNode.eulerAngles = SCNVector3Make(M_PI / 4, -M_PI / 4, 0);
    [_scene.rootNode addChildNode:fillLightNode];

    // Ambient Light
    SCNNode* ambientLightNode = [SCNNode node];
    ambientLightNode.light = [SCNLight light];
    ambientLightNode.light.type = SCNLightTypeAmbient;
    ambientLightNode.light.color = [NSColor colorWithCalibratedWhite:0.35 alpha:1.0];
    [_scene.rootNode addChildNode:ambientLightNode];

    // Root node for all cubies
    _cubeRootNode = [SCNNode node];
    [_scene.rootNode addChildNode:_cubeRootNode];
}

- (NSColor*)colorForRubikIndex:(int)colorIndex {
    switch (colorIndex) {
        case COLOR_WHITE:  return [NSColor colorWithCalibratedRed:0.96 green:0.96 blue:0.97 alpha:1.0];
        case COLOR_RED:    return [NSColor colorWithCalibratedRed:0.92 green:0.22 blue:0.21 alpha:1.0];
        case COLOR_GREEN:  return [NSColor colorWithCalibratedRed:0.13 green:0.77 blue:0.37 alpha:1.0];
        case COLOR_YELLOW: return [NSColor colorWithCalibratedRed:0.98 green:0.80 blue:0.08 alpha:1.0];
        case COLOR_ORANGE: return [NSColor colorWithCalibratedRed:0.98 green:0.45 blue:0.09 alpha:1.0];
        case COLOR_BLUE:   return [NSColor colorWithCalibratedRed:0.18 green:0.49 blue:0.96 alpha:1.0];
        default:           return [NSColor colorWithCalibratedWhite:0.12 alpha:1.0];
    }
}

- (SCNMaterial*)materialWithColor:(NSColor*)color {
    SCNMaterial* mat = [SCNMaterial material];
    mat.diffuse.contents = color;
    mat.roughness.contents = @0.3;
    mat.metalness.contents = @0.05;
    return mat;
}

- (void)buildCube {
    [_cubieNodes removeAllObjects];
    for (SCNNode* child in [_cubeRootNode.childNodes copy]) {
        [child removeFromParentNode];
    }

    NSColor* blackPlastic = [NSColor colorWithCalibratedWhite:0.10 alpha:1.0];

    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            for (int z = -1; z <= 1; z++) {
                if (x == 0 && y == 0 && z == 0) continue; // center core is empty

                SCNBox* box = [SCNBox boxWithWidth:kCubieSize
                                            height:kCubieSize
                                            length:kCubieSize
                                     chamferRadius:kChamferRadius];

                // Materials: 0:Front(+Z), 1:Right(+X), 2:Back(-Z), 3:Left(-X), 4:Top(+Y), 5:Bottom(-Y)
                SCNMaterial* mFront  = [self materialWithColor:(z == 1)  ? [self colorForRubikIndex:COLOR_GREEN]  : blackPlastic];
                SCNMaterial* mRight  = [self materialWithColor:(x == 1)  ? [self colorForRubikIndex:COLOR_RED]    : blackPlastic];
                SCNMaterial* mBack   = [self materialWithColor:(z == -1) ? [self colorForRubikIndex:COLOR_BLUE]   : blackPlastic];
                SCNMaterial* mLeft   = [self materialWithColor:(x == -1) ? [self colorForRubikIndex:COLOR_ORANGE] : blackPlastic];
                SCNMaterial* mTop    = [self materialWithColor:(y == 1)  ? [self colorForRubikIndex:COLOR_WHITE]  : blackPlastic];
                SCNMaterial* mBottom = [self materialWithColor:(y == -1) ? [self colorForRubikIndex:COLOR_YELLOW] : blackPlastic];

                box.materials = @[mFront, mRight, mBack, mLeft, mTop, mBottom];

                SCNNode* cubie = [SCNNode nodeWithGeometry:box];
                cubie.position = SCNVector3Make(x * kCubieSpacing, y * kCubieSpacing, z * kCubieSpacing);
                [_cubeRootNode addChildNode:cubie];
                [_cubieNodes addObject:cubie];
            }
        }
    }
}

- (void)resetCube {
    [_animationQueue removeAllObjects];
    _isAnimating = NO;
    [self buildCube];
    [self centerCubeInBounds];
}

- (void)updateCameraTransformAnimated:(BOOL)animated {
    // Clamp elevation so camera does not flip upside down
    const CGFloat kMaxElevation = 1.45; // ~83 degrees
    const CGFloat kMinElevation = -1.45;
    if (_cameraElevation > kMaxElevation) _cameraElevation = kMaxElevation;
    if (_cameraElevation < kMinElevation) _cameraElevation = kMinElevation;

    // Clamp distance
    if (_cameraDistance < 4.0) _cameraDistance = 4.0;
    if (_cameraDistance > 35.0) _cameraDistance = 35.0;

    CGFloat camX = _cameraDistance * cos(_cameraElevation) * sin(_cameraAzimuth);
    CGFloat camY = _cameraDistance * sin(_cameraElevation);
    CGFloat camZ = _cameraDistance * cos(_cameraElevation) * cos(_cameraAzimuth);
    SCNVector3 targetPos = SCNVector3Make(camX, camY, camZ);

    if (animated) {
        [SCNTransaction begin];
        [SCNTransaction setAnimationDuration:0.35];
        [SCNTransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
        _cameraNode.position = targetPos;
        [_cameraNode lookAt:SCNVector3Make(0, 0, 0)];
        [SCNTransaction commit];
    } else {
        [SCNTransaction begin];
        [SCNTransaction setAnimationDuration:0.0];
        _cameraNode.position = targetPos;
        [_cameraNode lookAt:SCNVector3Make(0, 0, 0)];
        [SCNTransaction commit];
    }
}

- (void)centerCubeInBounds {
    NSRect b = self.bounds;
    if (b.size.width <= 0 || b.size.height <= 0) return;

    CGFloat aspect = b.size.width / b.size.height;
    CGFloat cubeRadius = 2.8;

    CGFloat fovDegrees = 38.0;
    CGFloat fovRad = fovDegrees * M_PI / 180.0;

    CGFloat halfFovV = fovRad / 2.0;
    CGFloat halfFovH = atan(aspect * tan(halfFovV));

    CGFloat distV = cubeRadius / sin(halfFovV);
    CGFloat distH = cubeRadius / sin(halfFovH);
    _cameraDistance = std::max(distV, distH) * 1.25;

    // Reset to optimal symmetrical isometric perspective viewing Top (U), Right (R), and Front (F)
    _cameraAzimuth = 42.0 * M_PI / 180.0;
    _cameraElevation = 32.0 * M_PI / 180.0;

    _cameraNode.camera.fieldOfView = fovDegrees;
    [self updateCameraTransformAnimated:YES];
}

// Convert a RubikCube model state into exact materials on the 26 cubies
- (void)updateWithCubeState:(const RubikCube&)cube {
    [_animationQueue removeAllObjects];
    _isAnimating = NO;
    [self buildCube];
    // To sync arbitrary state directly, rebuild cubies with corresponding facelet colors
    // Facelet layout:
    // U: 0..8 (y=1), R: 9..17 (x=1), F: 18..26 (z=1), D: 27..35 (y=-1), L: 36..44 (x=-1), B: 45..53 (z=-1)
    for (SCNNode* cubie in _cubieNodes) {
        SCNVector3 pos = cubie.position;
        int x = (int)round(pos.x / kCubieSpacing);
        int y = (int)round(pos.y / kCubieSpacing);
        int z = (int)round(pos.z / kCubieSpacing);

        SCNBox* box = (SCNBox*)cubie.geometry;
        NSMutableArray<SCNMaterial*>* mats = [box.materials mutableCopy];

        NSColor* blackPlastic = [NSColor colorWithCalibratedWhite:0.10 alpha:1.0];

        // Front face (+Z, index 0): z=1, row=(1-y), col=(x+1) -> F facelet: 18 + row*3 + col
        if (z == 1) {
            int fIdx = 18 + (1 - y) * 3 + (x + 1);
            mats[0] = [self materialWithColor:[self colorForRubikIndex:cube.getFacelet(fIdx)]];
        } else {
            mats[0] = [self materialWithColor:blackPlastic];
        }

        // Right face (+X, index 1): x=1, row=(1-y), col=(1-z) -> R facelet: 9 + row*3 + col
        if (x == 1) {
            int rIdx = 9 + (1 - y) * 3 + (1 - z);
            mats[1] = [self materialWithColor:[self colorForRubikIndex:cube.getFacelet(rIdx)]];
        } else {
            mats[1] = [self materialWithColor:blackPlastic];
        }

        // Back face (-Z, index 2): z=-1, row=(1-y), col=(1-x) -> B facelet: 45 + row*3 + col
        if (z == -1) {
            int bIdx = 45 + (1 - y) * 3 + (1 - x);
            mats[2] = [self materialWithColor:[self colorForRubikIndex:cube.getFacelet(bIdx)]];
        } else {
            mats[2] = [self materialWithColor:blackPlastic];
        }

        // Left face (-X, index 3): x=-1, row=(1-y), col=(z+1) -> L facelet: 36 + row*3 + col
        if (x == -1) {
            int lIdx = 36 + (1 - y) * 3 + (z + 1);
            mats[3] = [self materialWithColor:[self colorForRubikIndex:cube.getFacelet(lIdx)]];
        } else {
            mats[3] = [self materialWithColor:blackPlastic];
        }

        // Top face (+Y, index 4): y=1, row=(z+1), col=(x+1) -> U facelet: 0 + row*3 + col
        if (y == 1) {
            int uIdx = 0 + (z + 1) * 3 + (x + 1);
            mats[4] = [self materialWithColor:[self colorForRubikIndex:cube.getFacelet(uIdx)]];
        } else {
            mats[4] = [self materialWithColor:blackPlastic];
        }

        // Bottom face (-Y, index 5): y=-1, row=(1-z), col=(x+1) -> D facelet: 27 + row*3 + col
        if (y == -1) {
            int dIdx = 27 + (1 - z) * 3 + (x + 1);
            mats[5] = [self materialWithColor:[self colorForRubikIndex:cube.getFacelet(dIdx)]];
        } else {
            mats[5] = [self materialWithColor:blackPlastic];
        }

        box.materials = mats;
    }
}

- (void)animateMove:(int)move completion:(void(^ _Nullable)(void))completion {
    if (move < 0 || move >= NUM_MOVES) {
        if (completion) completion();
        return;
    }

    if (_isAnimating) {
        [_animationQueue addObject:@{
            @"move": @(move),
            @"completion": completion ? [completion copy] : [NSNull null]
        }];
        return;
    }

    [self performMoveAnimation:move completion:completion];
}

- (void)performMoveAnimation:(int)move completion:(void(^ _Nullable)(void))completion {
    _isAnimating = YES;

    int face = move / 3;
    int suffix = move % 3; // 0: CW (90°), 1: CCW (-90°), 2: 180°

    SCNVector3 axis;
    CGFloat baseAngle = 0;

    switch (face) {
        case FACE_U: // Up: axis (0, 1, 0), CW is -M_PI_2
            axis = SCNVector3Make(0, 1, 0);
            baseAngle = -M_PI_2;
            break;
        case FACE_D: // Down: axis (0, 1, 0), CW is +M_PI_2
            axis = SCNVector3Make(0, 1, 0);
            baseAngle = M_PI_2;
            break;
        case FACE_R: // Right: axis (1, 0, 0), CW is -M_PI_2
            axis = SCNVector3Make(1, 0, 0);
            baseAngle = -M_PI_2;
            break;
        case FACE_L: // Left: axis (1, 0, 0), CW is +M_PI_2
            axis = SCNVector3Make(1, 0, 0);
            baseAngle = M_PI_2;
            break;
        case FACE_F: // Front: axis (0, 0, 1), CW is -M_PI_2
            axis = SCNVector3Make(0, 0, 1);
            baseAngle = -M_PI_2;
            break;
        case FACE_B: // Back: axis (0, 0, 1), CW is +M_PI_2
            axis = SCNVector3Make(0, 0, 1);
            baseAngle = M_PI_2;
            break;
        default:
            axis = SCNVector3Make(0, 1, 0);
            baseAngle = 0;
            break;
    }

    CGFloat finalAngle = baseAngle;
    if (suffix == 1) finalAngle = -baseAngle;        // CCW
    else if (suffix == 2) finalAngle = baseAngle * 2.0; // 180°

    // Find the 9 cubies in the target face layer based on world position
    NSMutableArray<SCNNode*>* layerCubies = [NSMutableArray arrayWithCapacity:9];
    const CGFloat kEpsilon = 0.4;

    for (SCNNode* cubie in _cubieNodes) {
        SCNVector3 worldPos = [cubie convertPosition:SCNVector3Zero toNode:_cubeRootNode];
        BOOL belongs = NO;
        switch (face) {
            case FACE_U: belongs = (worldPos.y > kEpsilon); break;
            case FACE_D: belongs = (worldPos.y < -kEpsilon); break;
            case FACE_R: belongs = (worldPos.x > kEpsilon); break;
            case FACE_L: belongs = (worldPos.x < -kEpsilon); break;
            case FACE_F: belongs = (worldPos.z > kEpsilon); break;
            case FACE_B: belongs = (worldPos.z < -kEpsilon); break;
        }
        if (belongs) {
            [layerCubies addObject:cubie];
        }
    }

    // Temporary rotation pivot node
    SCNNode* pivotNode = [SCNNode node];
    [_cubeRootNode addChildNode:pivotNode];

    for (SCNNode* cubie in layerCubies) {
        SCNMatrix4 transformInRoot = [cubie convertTransform:SCNMatrix4Identity toNode:_cubeRootNode];
        [cubie removeFromParentNode];
        cubie.transform = transformInRoot;
        [pivotNode addChildNode:cubie];
    }

    SCNAction* rotateAction = [SCNAction rotateByAngle:finalAngle
                                                aroundAxis:axis
                                                  duration:_animationDuration];
    rotateAction.timingMode = SCNActionTimingModeEaseInEaseOut;

    __weak Rubik3DView* weakSelf = self;
    [pivotNode runAction:rotateAction completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            Rubik3DView* strongSelf = weakSelf;
            if (!strongSelf) return;

            // Re-parent cubies to cubeRootNode with baked transforms & grid snapping
            for (SCNNode* cubie in layerCubies) {
                SCNMatrix4 worldTransform = [cubie convertTransform:SCNMatrix4Identity toNode:strongSelf->_cubeRootNode];
                [cubie removeFromParentNode];
                cubie.transform = worldTransform;

                // Snap positions to exact cubie spacing multiples to eliminate drift
                SCNVector3 p = cubie.position;
                p.x = round(p.x / kCubieSpacing) * kCubieSpacing;
                p.y = round(p.y / kCubieSpacing) * kCubieSpacing;
                p.z = round(p.z / kCubieSpacing) * kCubieSpacing;
                cubie.position = p;

                [strongSelf->_cubeRootNode addChildNode:cubie];
            }

            [pivotNode removeFromParentNode];

            if ([strongSelf.rubikDelegate respondsToSelector:@selector(rubik3DViewDidFinishMove:)]) {
                [strongSelf.rubikDelegate rubik3DViewDidFinishMove:move];
            }

            if (completion) {
                completion();
            }

            // Check if queue has more moves waiting
            if (strongSelf->_animationQueue.count > 0) {
                NSDictionary* nextItem = strongSelf->_animationQueue.firstObject;
                [strongSelf->_animationQueue removeObjectAtIndex:0];
                int nextMove = [nextItem[@"move"] intValue];
                id nextCompObj = nextItem[@"completion"];
                void (^nextCompletion)(void) = (nextCompObj != [NSNull null]) ? nextCompObj : nil;
                [strongSelf performMoveAnimation:nextMove completion:nextCompletion];
            } else {
                strongSelf->_isAnimating = NO;
            }
        });
    }];
}

- (void)animateInverseMove:(int)move completion:(void(^ _Nullable)(void))completion {
    int inv = RubikCube::invertMove(move);
    [self animateMove:inv completion:completion];
}

- (void)playMoves:(const std::vector<int>&)moves completion:(void(^ _Nullable)(void))completion {
    if (moves.empty()) {
        if (completion) completion();
        return;
    }

    __block size_t idx = 0;
    __weak Rubik3DView* weakSelf = self;
    __block __weak void (^weakStepBlock)(void);
    void (^stepBlock)(void);

    weakStepBlock = stepBlock = ^{
        Rubik3DView* strongSelf = weakSelf;
        void (^strongStepBlock)(void) = weakStepBlock;
        if (!strongSelf || idx >= moves.size()) {
            if (completion) completion();
            return;
        }
        int m = moves[idx++];
        [strongSelf animateMove:m completion:^{
            if (strongStepBlock) strongStepBlock();
        }];
    };

    stepBlock();
}

@end
