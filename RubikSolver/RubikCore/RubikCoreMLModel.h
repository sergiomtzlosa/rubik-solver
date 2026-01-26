//
//  RubikCoreMLModel.h
//  RubikSolver - Apple Silicon Core ML & GPU Neural Pipeline
//

#import <Foundation/Foundation.h>
#import <CoreML/CoreML.h>
#import <Metal/Metal.h>
#include <vector>

NS_ASSUME_NONNULL_BEGIN

/// Neural network prediction output for a Rubik's Cube state.
@interface RubikMLPrediction : NSObject

/// Estimated cost-to-go (distance heuristic to solved state)
@property (nonatomic, readonly) float costToGo;

/// Action preference logits across all 18 Singmaster moves
@property (nonatomic, readonly) NSArray<NSNumber *> *policyLogits;

- (instancetype)initWithCostToGo:(float)costToGo policyLogits:(NSArray<NSNumber *> *)policyLogits NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

/// High-performance Core ML model manager optimized for Apple Silicon GPU & Neural Engine.
@interface RubikCoreMLModel : NSObject

/// Underlying MLModel instance
@property (nonatomic, readonly, nullable) MLModel *model;

/// Active compute device name (e.g. Apple M-series GPU)
@property (nonatomic, readonly) NSString *deviceDescription;

/// Whether Core ML has been observed to prefer the GPU for this model.
/// This is only set after MLComputePlan inspection; a Metal device alone is
/// not enough to claim GPU acceleration.
@property (nonatomic, readonly) BOOL isAcceleratedOnGPU;

/// Human-readable GPU verification state (for diagnostics and the UI).
@property (nonatomic, readonly) NSString *gpuStatusDescription;

/// Maximum batch size accepted by the exported model.
@property (nonatomic, readonly) NSInteger maximumBatchSize;

/// Shared singleton instance with pre-warmed GPU pipelines
+ (instancetype)sharedInstance;

/// Verify the actual compute placement using MLComputePlan (macOS 14.4+).
/// The completion handler is called on an arbitrary queue.
- (void)verifyGPUUsageWithCompletion:(void (^)(BOOL usingGPU, NSString *details))completion;

/// Initialize with optional custom compiled model URL
- (nullable instancetype)initWithModelURL:(nullable NSURL *)modelURL error:(NSError **)error;

/// Encode 54-facelet state matrix into a 1x324 float32 MLMultiArray
+ (nullable MLMultiArray *)multiArrayForFacelets:(const uint8_t *)facelets error:(NSError **)outError;

/// Encode `count` contiguous 54-facelet states into one [count, 324] tensor.
+ (nullable MLMultiArray *)multiArrayForFaceletsBatch:(const uint8_t *)facelets
                                                count:(NSUInteger)count
                                                error:(NSError **)outError;

/// Encode `count` states into a tensor with a fixed model batch `capacity`,
/// zero-padding the unused rows.
+ (nullable MLMultiArray *)multiArrayForFaceletsBatch:(const uint8_t *)facelets
                                                count:(NSUInteger)count
                                             capacity:(NSUInteger)capacity
                                                error:(NSError **)outError;

/// Predict cost-to-go and policy logits for a single 54-facelet state
- (nullable RubikMLPrediction *)predictForFacelets:(const uint8_t *)facelets error:(NSError **)outError;

/// High-throughput batch prediction for multiple states on Apple Silicon GPU
- (nullable NSArray<RubikMLPrediction *> *)predictBatchForFaceletsList:(const std::vector<const uint8_t *>&)states
                                                                 error:(NSError **)outError;

/// True batched inference: a single [count, 324] tensor and one model call.
/// `facelets` must contain count * 54 contiguous color indices.
- (nullable NSArray<RubikMLPrediction *> *)predictBatchForFaceletsBuffer:(const uint8_t *)facelets
                                                                  count:(NSUInteger)count
                                                                  error:(NSError **)outError;

/// Direct raw evaluation filling C-arrays for zero-overhead inference in inner loops
- (BOOL)evaluateFacelets:(const uint8_t *)facelets
              outCostToGo:(float *)outCostToGo
             outLogits18:(float * _Nullable)outLogits18
                   error:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
