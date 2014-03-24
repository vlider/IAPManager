//
//  IAPManager.h
//  IAPManager
//
//  Created by Valerii Lider on 3/6/14.
//  Copyright (c) 2014 Spire LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString const *kReceiptBundleIdentifier;
extern NSString const *kReceiptBundleIdentifierData;
extern NSString const *kReceiptVersion;
extern NSString const *kReceiptOpaqueValue;
extern NSString const *kReceiptHash;
extern NSString const *kReceiptInApp;
extern NSString const *kReceiptOriginalVersion;
extern NSString const *kReceiptExpirationDate;

extern NSString const *kReceiptInAppQuantity;
extern NSString const *kReceiptInAppProductIdentifier;
extern NSString const *kReceiptInAppTransactionIdentifier;
extern NSString const *kReceiptInAppPurchaseDate;
extern NSString const *kReceiptInAppOriginalTransactionIdentifier;
extern NSString const *kReceiptInAppOriginalPurchaseDate;
extern NSString const *kReceiptInAppSubscriptionExpirationDate;
extern NSString const *kReceiptInAppCancellationDate;
extern NSString const *kReceiptInAppWebOrderLineItemID;

@class SKPaymentTransaction;

typedef void (^onStoreLoadedBlock)(NSArray *validProducts, NSArray *invalidProductIds);
typedef void (^onPurchaseBlock)(SKPaymentTransaction *transaction);
typedef void (^onFailPurchaseBlock)(SKPaymentTransaction *transaction, BOOL cancelled);

@interface IAPManager : NSObject

@property (nonatomic, strong) NSString *bundleId;
@property (nonatomic, strong) NSString *versionString;

@property (nonatomic, readonly, strong) NSArray *validProducts;
@property (nonatomic, readonly, strong) NSArray *invalidProductIds;

+ (instancetype)sharedInstanse;

- (void)addObserver:(NSObject *)observer forProductWithId:(NSString *)productId performOnSuccessfulPurchase:(onPurchaseBlock)onSuccessBlock performOnFailedPurchase:(onFailPurchaseBlock)onFailureBlock;
- (void)addObserver:(NSObject *)observer forProductsWithIds:(NSArray *)productIds performOnSuccessfulPurchase:(onPurchaseBlock)onSuccessBlock performOnFailedPurchase:(onFailPurchaseBlock)onFailureBlock;

- (void)removeObserver:(NSObject *)observer forProductWithId:(NSString *)productId;

- (void)loadStoreWithCompletion:(onStoreLoadedBlock)completionBlock;
- (void)restorePurchases;
- (BOOL)canMakePurchases;

- (BOOL)placePaymentForProductWithId:(NSString *)productId;
- (BOOL)canPlacePaymentForProductWithId:(NSString *)productId;
@end
