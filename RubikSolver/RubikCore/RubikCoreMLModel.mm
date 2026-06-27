//
//  RubikCoreMLModel.mm
//  RubikSolver - Apple Silicon Core ML & GPU Neural Pipeline
//

#import "RubikCoreMLModel.h"

@implementation RubikMLPrediction

- (instancetype)initWithCostToGo:(float)costToGo policyLogits:(NSArray<NSNumber *> *)policyLogits {
    self = [super init];
    if (self) {
        _costToGo = costToGo;
        _policyLogits = [policyLogits copy];
    }
    return self;
}

@end

@implementation RubikCoreMLModel {
    id<MTLDevice> _metalDevice;
    NSString *_inputFeatureName;
    NSString *_valueFeatureName;
    NSString *_policyFeatureName;
    NSURL *_loadedModelURL;
    MLModelConfiguration *_modelConfiguration;
    BOOL _gpuVerified;
    NSString *_gpuStatusDescription;
    NSInteger _maximumBatchSize;
    NSInteger _requiredBatchSize;
}

+ (instancetype)sharedInstance {
    static RubikCoreMLModel *sharedModel = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedModel = [[RubikCoreMLModel alloc] initWithModelURL:nil error:nil];
    });
    return sharedModel;
}

- (instancetype)init {
    return [self initWithModelURL:nil error:nil];
}

- (nullable instancetype)initWithModelURL:(nullable NSURL *)modelURL error:(NSError **)error {
    self = [super init];
    if (self) {
        _metalDevice = MTLCreateSystemDefaultDevice();
        _deviceDescription = _metalDevice ? _metalDevice.name : @"Apple CPU";
        _gpuVerified = NO;
        _gpuStatusDescription = _metalDevice
            ? @"GPU configured; verifying Core ML placement…"
            : @"No Metal device; using the CPU.";
        _maximumBatchSize = 512;
        _requiredBatchSize = 512;
        
        NSURL *resolvedURL = modelURL;
        if (!resolvedURL) {
            resolvedURL = [self locateCompiledModelURL];
        }
        
        if (resolvedURL) {
            _loadedModelURL = resolvedURL;
            MLModelConfiguration *config = [[MLModelConfiguration alloc] init];
            // Use the GPU explicitly. CPUAndGPU (not All) avoids silently
            // claiming Neural Engine/GPU acceleration we cannot verify.
            config.computeUnits = MLComputeUnitsCPUAndGPU;
            if (_metalDevice) {
                config.preferredMetalDevice = _metalDevice;
            }
            config.allowLowPrecisionAccumulationOnGPU = YES;
            _modelConfiguration = config;
            
            NSError *loadError = nil;
            _model = [MLModel modelWithContentsOfURL:resolvedURL configuration:config error:&loadError];
            if (!_model) {
                NSLog(@"[RubikCoreMLModel] Failed to load compiled model at %@: %@", resolvedURL, loadError);
                _gpuStatusDescription = @"Model could not be loaded.";
                if (error) *error = loadError;
            } else {
                NSLog(@"[RubikCoreMLModel] Loaded DeepCubeA onto %@ with MLComputeUnitsCPUAndGPU", _deviceDescription);
                [self inspectModelFeatures];
            }
        } else {
            _gpuStatusDescription = @"DeepCubeA.mlmodelc was not found.";
            NSLog(@"[RubikCoreMLModel] Warning: DeepCubeA.mlmodelc could not be located in bundle or resources.");
        }
    }
    return self;
}

- (BOOL)isAcceleratedOnGPU {
    return _gpuVerified;
}

- (NSString *)gpuStatusDescription {
    return _gpuStatusDescription ?: @"GPU status unknown.";
}

- (NSInteger)maximumBatchSize {
    return _maximumBatchSize;
}

- (NSInteger)requiredBatchSize {
    return _requiredBatchSize;
}

- (void)verifyGPUUsageWithCompletion:(void (^)(BOOL, NSString *))completion {
    if (!completion) return;
    if (!_model || !_loadedModelURL || !_modelConfiguration) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, @"No Core ML model is loaded.");
        });
        return;
    }

    if (@available(macOS 14.4, *)) {
        [MLComputePlan loadContentsOfURL:_loadedModelURL
                           configuration:_modelConfiguration
                       completionHandler:^(MLComputePlan * _Nullable plan, NSError * _Nullable error) {
            if (!plan) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, error.localizedDescription ?: @"Could not inspect the Core ML compute plan.");
                });
                return;
            }

            MLModelStructureProgram *program = plan.modelStructure.program;
            MLModelStructureProgramFunction *mainFunction = program.functions[@"main"];
            NSArray<MLModelStructureProgramOperation *> *operations = mainFunction.block.operations;
            NSUInteger gpuOperations = 0;
            NSUInteger totalOperations = 0;
            for (MLModelStructureProgramOperation *operation in operations) {
                MLComputePlanDeviceUsage *usage = [plan computeDeviceUsageForMLProgramOperation:operation];
                if (!usage) continue;
                ++totalOperations;
                if ([usage.preferredComputeDevice isKindOfClass:[MLGPUComputeDevice class]]) {
                    ++gpuOperations;
                }
            }
            BOOL usingGPU = totalOperations > 0 && gpuOperations > 0;
            NSString *details = totalOperations > 0
                ? [NSString stringWithFormat:@"Core ML prefers the GPU for %lu/%lu operations.",
                                             (unsigned long)gpuOperations, (unsigned long)totalOperations]
                : @"Core ML did not report a usable compute plan.";
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_gpuVerified = usingGPU;
                self->_gpuStatusDescription = details;
                completion(usingGPU, details);
            });
        }];
    } else {
        _gpuVerified = NO;
        _gpuStatusDescription = @"MLComputePlan requires macOS 14.4 or later.";
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, self->_gpuStatusDescription);
        });
    }
}

- (NSURL *)locateCompiledModelURL {
    // 1. Look in main application bundle
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"DeepCubeA" withExtension:@"mlmodelc"];
    if (url && [[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
        return url;
    }
    
    // 2. Look in bundle resources directory
    NSURL *resourcesDir = [[NSBundle mainBundle] resourceURL];
    if (resourcesDir) {
        NSURL *cand = [resourcesDir URLByAppendingPathComponent:@"DeepCubeA.mlmodelc"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:cand.path]) {
            return cand;
        }
    }
    
    // 3. Look in local directory relative to executable or current working directory
    NSArray<NSString *> *searchPaths = @[
        @"RubikSolver/Resources/DeepCubeA.mlmodelc",
        @"Resources/DeepCubeA.mlmodelc",
        @"DeepCubeA.mlmodelc",
        @"../Resources/DeepCubeA.mlmodelc"
    ];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *cwd = [fm currentDirectoryPath];
    for (NSString *p in searchPaths) {
        NSString *absPath = [cwd stringByAppendingPathComponent:p];
        if ([fm fileExistsAtPath:absPath]) {
            return [NSURL fileURLWithPath:absPath];
        }
        if ([fm fileExistsAtPath:p]) {
            return [NSURL fileURLWithPath:p];
        }
    }
    
    return nil;
}

- (void)inspectModelFeatures {
    if (!_model) return;
    
    // Identify input tensor name
    NSDictionary<NSString *, MLFeatureDescription *> *inputs = _model.modelDescription.inputDescriptionsByName;
    for (NSString *name in inputs) {
        if ([name containsString:@"state"] || inputs.count == 1) {
            _inputFeatureName = name;
            break;
        }
    }
    if (!_inputFeatureName) _inputFeatureName = @"cube_state";
    
    // Identify output tensor names
    NSDictionary<NSString *, MLFeatureDescription *> *outputs = _model.modelDescription.outputDescriptionsByName;
    for (NSString *name in outputs) {
        if ([name containsString:@"val"]) {
            _valueFeatureName = name;
        } else if ([name containsString:@"pol"]) {
            _policyFeatureName = name;
        }
    }
    if (!_valueFeatureName) _valueFeatureName = @"value";
    if (!_policyFeatureName) _policyFeatureName = @"policy";

    MLFeatureDescription *input = inputs[_inputFeatureName];
    if (input.multiArrayConstraint.shape.count >= 1) {
        NSInteger firstDimension = input.multiArrayConstraint.shape[0].integerValue;
        if (firstDimension > 1) {
            _requiredBatchSize = firstDimension;
            _maximumBatchSize = firstDimension;
        }
    }
    NSLog(@"[RubikCoreMLModel] Input %@, fixed batch %ld", _inputFeatureName, (long)_requiredBatchSize);
}

+ (nullable MLMultiArray *)multiArrayForFacelets:(const uint8_t *)facelets error:(NSError **)outError {
    return [self multiArrayForFaceletsBatch:facelets count:1 error:outError];
}

+ (nullable MLMultiArray *)multiArrayForFaceletsBatch:(const uint8_t *)facelets
                                                count:(NSUInteger)count
                                                error:(NSError **)outError {
    return [self multiArrayForFaceletsBatch:facelets count:count capacity:count error:outError];
}

+ (nullable MLMultiArray *)multiArrayForFaceletsBatch:(const uint8_t *)facelets
                                                count:(NSUInteger)count
                                             capacity:(NSUInteger)capacity
                                                error:(NSError **)outError {
    if (!facelets || count == 0 || capacity < count) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"RubikCoreML" code:-2
                                        userInfo:@{NSLocalizedDescriptionKey: @"No facelet data was provided."}];
        }
        return nil;
    }

    NSArray<NSNumber *> *shape = @[@(capacity), @324];
    MLMultiArray *array = [[MLMultiArray alloc] initWithShape:shape
                                                     dataType:MLMultiArrayDataTypeFloat32
                                                        error:outError];
    if (!array) return nil;

    float *ptr = (float *)array.dataPointer;
    memset(ptr, 0, capacity * 324 * sizeof(float));

    for (NSUInteger b = 0; b < count; ++b) {
        const uint8_t *state = facelets + b * 54;
        float *row = ptr + b * 324;
        for (int i = 0; i < 54; i++) {
            uint8_t color = state[i];
            if (color < 6) {
                row[i * 6 + color] = 1.0f;
            }
        }
    }
    return array;
}

static inline float floatFromMultiArray(MLMultiArray *arr, NSInteger index) {
    if (!arr) return 0.0f;
    if (arr.dataType == MLMultiArrayDataTypeFloat32) {
        return ((const float *)arr.dataPointer)[index];
    } else if (arr.dataType == MLMultiArrayDataTypeFloat16) {
        return (float)(((const __fp16 *)arr.dataPointer)[index]);
    } else if (arr.dataType == MLMultiArrayDataTypeDouble) {
        return (float)(((const double *)arr.dataPointer)[index]);
    }
    return [arr objectAtIndexedSubscript:index].floatValue;
}

- (nullable RubikMLPrediction *)predictForFacelets:(const uint8_t *)facelets error:(NSError **)outError {
    if (!_model) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"RubikCoreML" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Core ML model not loaded"}];
        }
        return nil;
    }

    // Even a single state must go through the padded batch path: the
    // production model has a fixed 512-state input to keep Core ML on the GPU.
    NSArray<RubikMLPrediction *> *predictions =
        [self predictBatchForFaceletsBuffer:facelets count:1 error:outError];
    return predictions.firstObject;
}

- (nullable NSArray<RubikMLPrediction *> *)predictBatchForFaceletsList:(const std::vector<const uint8_t *>&)states
                                                                 error:(NSError **)outError
{
    if (!_model || states.empty()) return @[];

    std::vector<uint8_t> buffer;
    buffer.reserve(states.size() * 54);
    for (const uint8_t *state : states) {
        if (!state) {
            if (outError) {
                *outError = [NSError errorWithDomain:@"RubikCoreML" code:-3
                                            userInfo:@{NSLocalizedDescriptionKey: @"A batch state was null."}];
            }
            return nil;
        }
        buffer.insert(buffer.end(), state, state + 54);
    }
    return [self predictBatchForFaceletsBuffer:buffer.data() count:states.size() error:outError];
}

- (nullable NSArray<RubikMLPrediction *> *)predictBatchForFaceletsBuffer:(const uint8_t *)facelets
                                                                  count:(NSUInteger)count
                                                                  error:(NSError **)outError
{
    if (!_model) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"RubikCoreML" code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"Core ML model not loaded"}];
        }
        return nil;
    }
    if (!facelets || count == 0) return @[];

    @autoreleasepool {
        NSString *featureKey = _inputFeatureName ?: @"cube_state";
        NSString *valueKey = _valueFeatureName ?: @"value";
        NSString *policyKey = _policyFeatureName ?: @"policy";
        NSMutableArray<RubikMLPrediction *> *predictions = [NSMutableArray arrayWithCapacity:count];

        const NSUInteger maxBatch = (NSUInteger)MAX((NSInteger)1, _maximumBatchSize);
        const NSUInteger capacity = _requiredBatchSize > 1 ? (NSUInteger)_requiredBatchSize : maxBatch;
        for (NSUInteger offset = 0; offset < count; offset += maxBatch) {
            const NSUInteger chunk = MIN(maxBatch, count - offset);
            NSError *encodeError = nil;
            MLMultiArray *inputArray =
                [RubikCoreMLModel multiArrayForFaceletsBatch:facelets + offset * 54
                                                       count:chunk
                                                    capacity:MAX(capacity, chunk)
                                                       error:&encodeError];
            if (!inputArray) {
                if (outError) *outError = encodeError;
                return nil;
            }

            MLDictionaryFeatureProvider *inputProvider =
                [[MLDictionaryFeatureProvider alloc] initWithDictionary:@{featureKey: inputArray}
                                                                  error:&encodeError];
            if (!inputProvider) {
                if (outError) *outError = encodeError;
                return nil;
            }

            NSError *inferError = nil;
            id<MLFeatureProvider> output = [_model predictionFromFeatures:inputProvider error:&inferError];
            if (!output) {
                if (outError) *outError = inferError;
                return nil;
            }

            MLMultiArray *valArray = [output featureValueForName:valueKey].multiArrayValue;
            MLMultiArray *polArray = [output featureValueForName:policyKey].multiArrayValue;
            if (!valArray || !polArray) {
                if (outError) {
                    *outError = [NSError errorWithDomain:@"RubikCoreML" code:-4
                                                userInfo:@{NSLocalizedDescriptionKey: @"The model output was missing value or policy tensors."}];
                }
                return nil;
            }

            for (NSUInteger i = 0; i < chunk; ++i) {
                float costToGo = floatFromMultiArray(valArray, (NSInteger)i);
                NSMutableArray<NSNumber *> *logits = [NSMutableArray arrayWithCapacity:18];
                for (int k = 0; k < 18; ++k) {
                    [logits addObject:@(floatFromMultiArray(polArray, (NSInteger)(i * 18 + k)))];
                }
                [predictions addObject:[[RubikMLPrediction alloc] initWithCostToGo:costToGo
                                                                     policyLogits:logits]];
            }
        }
        return predictions;
    }
}

- (BOOL)evaluateFacelets:(const uint8_t *)facelets
              outCostToGo:(float *)outCostToGo
             outLogits18:(float * _Nullable)outLogits18
                   error:(NSError **)outError
{
    RubikMLPrediction *pred = [self predictForFacelets:facelets error:outError];
    if (!pred) return NO;
    
    if (outCostToGo) *outCostToGo = pred.costToGo;
    if (outLogits18) {
        for (int i = 0; i < 18 && i < (int)pred.policyLogits.count; i++) {
            outLogits18[i] = [pred.policyLogits[i] floatValue];
        }
    }
    return YES;
}

@end
