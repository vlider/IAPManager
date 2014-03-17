//
//  IAPManager.h
//  IAPManager
//
//  Created by Valerii Lider on 3/6/14.
//  Copyright (c) 2014 Spire LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SKPaymentTransaction;

typedef void (^onStoreLoadedBlock)(NSArray *validProducts, NSArray *invalidProductIds);
typedef void (^transactionCompletionBlock)(SKPaymentTransaction *transaction);

@interface IAPManager : NSObject

@property (nonatomic, readonly, strong) NSArray *validProducts;

+ (instancetype)sharedInstanse;

- (void)addObserver:(NSObject *)observer forProductWithId:(NSString *)productId performOnSuccessfulPurchase:(transactionCompletionBlock)onSuccessBlock performOnFailedPurchase:(transactionCompletionBlock)onFailureBlock;
- (void)addObserver:(NSObject *)observer forProductsWithIds:(NSArray *)productIds performOnSuccessfulPurchase:(transactionCompletionBlock)onSuccessBlock performOnFailedPurchase:(transactionCompletionBlock)onFailureBlock;
//- (void)addObserver:(NSObject *)observer forProductWithId:(NSString *)productId actionOnSuccessfulPurchase:(SEL)onSuccess actionOnFailedPurchase:(SEL)onFailure;

- (void)removeObserver:(NSObject *)observer forProductWithId:(NSString *)productId;

- (void)loadStoreWithCompletion:(onStoreLoadedBlock)completionBlock;
- (void)restorePurchases;
- (BOOL)canMakePurchases;

- (BOOL)placePaymentForProductWithId:(NSString *)productId;
- (BOOL)canPlacePaymentForProductWithId:(NSString *)productId;
@end
