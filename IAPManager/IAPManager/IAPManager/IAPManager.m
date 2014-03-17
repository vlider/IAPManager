//
//  IAPManager.m
//  IAPManager
//
//  Created by Valerii Lider on 3/6/14.
//  Copyright (c) 2014 Spire LLC. All rights reserved.
//

#import "IAPManager.h"

@import StoreKit;

typedef void (^onPurchaseBlock)(SKPaymentTransaction *);

@interface IAPObserver : NSObject
@property (nonatomic, strong) NSObject *purchaseObserver;
@property (nonatomic, copy) onPurchaseBlock onSuccessPurchaseBlock;
@property (nonatomic, copy) onPurchaseBlock onFailPurchaseBlock;
@end

@implementation IAPObserver

- (NSUInteger)hash {
    
    return self.purchaseObserver.hash;
}

- (BOOL)isEqual:(IAPObserver *)object {
    
    BOOL result = NO;
    if ([object isKindOfClass:[IAPObserver class]]) {
        result = [self.purchaseObserver isEqual:object.purchaseObserver];
    }
    
    return result;
}

@end
@interface IAPurchase : NSObject
@property (nonatomic, strong) NSString *productId;
@property (nonatomic, strong) SKProduct *product;
@property (nonatomic, strong) NSMutableSet *observers;
@end

@implementation IAPurchase

- (instancetype)init
{
    self = [super init];
    if (self) {
        
        self.observers = [NSMutableSet new];
    }
    return self;
}

- (NSUInteger)hash {
    
    return self.productId.hash;
}

- (BOOL)isEqual:(IAPurchase *)object {

    BOOL result = NO;
    if ([object isKindOfClass:[IAPurchase class]]) {
        result = [self.productId isEqual:object.productId];
    }

    return result;
}

@end

@interface IAPManager () <SKPaymentTransactionObserver, SKProductsRequestDelegate>
@property (nonatomic, strong) NSMapTable *products;
@property (nonatomic, strong) SKProductsRequest *productsRequest;
@property (nonatomic, copy) onStoreLoadedBlock loadStoreCompletionBlock;
@property (nonatomic, strong) NSArray *validProducts;
@end

@implementation IAPManager

static IAPManager *_gSharedIAPManagerInstanse;

#pragma mark -
#pragma mark public methods
#pragma mark -

+ (instancetype)sharedInstanse {
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        _gSharedIAPManagerInstanse = [[IAPManager alloc] init];
    });
    
    return _gSharedIAPManagerInstanse;
}

- (void)addObserver:(NSObject *)observer forProductWithId:(NSString *)productId performOnSuccessfulPurchase:(void (^)(SKPaymentTransaction *))onSuccessBlock performOnFailedPurchase:(void (^)(SKPaymentTransaction *))onFailureBlock {
    
    NSParameterAssert(nil != observer);
    NSParameterAssert(productId != nil);
    NSParameterAssert(onSuccessBlock != NULL);
    NSParameterAssert(onFailureBlock != NULL);
    
    @synchronized(self) {
     
        IAPurchase *purchase = [self.products objectForKey:productId];
        if (nil == purchase) {
            
            purchase = [[IAPurchase alloc] init];
            purchase.productId = productId;
            [self.products setObject:purchase forKey:productId];
        }
        
        NSSet *observers = [purchase.observers objectsPassingTest:^BOOL(IAPObserver *obj, BOOL *stop) {
            
            *stop = ((obj.purchaseObserver == observer) && obj.onSuccessPurchaseBlock == onSuccessBlock && obj.onFailPurchaseBlock == onFailureBlock);
            
            return *stop;
        }];
        
        IAPObserver *purchaseObserver = observers.anyObject;
        if (nil == purchaseObserver) {
            
            purchaseObserver = [[IAPObserver alloc] init];
            purchaseObserver.purchaseObserver = observer;
            [purchase.observers addObject:purchaseObserver];
            purchaseObserver.onSuccessPurchaseBlock = onSuccessBlock;
            purchaseObserver.onFailPurchaseBlock = onFailureBlock;
        }
    }
}

- (void)addObserver:(NSObject *)observer forProductsWithIds:(NSArray *)productIds performOnSuccessfulPurchase:(transactionCompletionBlock)onSuccessBlock performOnFailedPurchase:(transactionCompletionBlock)onFailureBlock {
    
    NSParameterAssert(nil != observer);
    NSParameterAssert(productIds != nil);
    NSParameterAssert(onSuccessBlock != NULL);
    NSParameterAssert(onFailureBlock != NULL);
    
    @synchronized(self) {
        
        NSSet *temp = [NSSet setWithArray:productIds];
        for (NSString *productId in temp) {
            
            [self addObserver:observer forProductWithId:productId performOnSuccessfulPurchase:onSuccessBlock performOnFailedPurchase:onFailureBlock];
        }
    }
}

- (void)removeObserver:(NSObject *)observer forProductWithId:(NSString *)productId {

    NSParameterAssert(nil != observer);
    NSParameterAssert(nil != productId);
    
    @synchronized(self) {
     
        IAPurchase *purchase = [self.products objectForKey:productId];
        
        NSSet *observers = [purchase.observers objectsPassingTest:^BOOL(IAPObserver *obj, BOOL *stop) {
            
            *stop = (obj == observer);
            return NO;
        }];
        [purchase.observers minusSet:observers];
    }
}

- (void)loadStoreWithCompletion:(onStoreLoadedBlock)completionBlock {

    NSMutableSet *productIds = [NSMutableSet new];
    
    @synchronized(self) {
    
        self.loadStoreCompletionBlock = completionBlock;
        
        NSEnumerator *enumerator = [self.products keyEnumerator];
        NSString *productId = nil;
        while ((productId = [enumerator nextObject])) {
            
            [productIds addObject:productId];
        }
    }

    SKProductsRequest *productsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:productIds];
    productsRequest.delegate = self;
    [productsRequest start];
}

- (void)restorePurchases {
    
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

- (BOOL)canMakePurchases {
    
    return [SKPaymentQueue canMakePayments];
}

- (BOOL)canPlacePaymentForProductWithId:(NSString *)productId {
    
    BOOL result = [self canMakePurchases];
    if (result) {
        
        @synchronized(self) {
        
            IAPurchase *purchase = [self.products objectForKey:productId];
            result = (nil != purchase.product);
        }
    }
    
    return result;
}

- (BOOL)placePaymentForProductWithId:(NSString *)productId {

    NSParameterAssert(nil != productId);
    
    BOOL result = NO;
    @synchronized(self) {
     
        IAPurchase *purchase = [self.products objectForKey:productId];
        SKProduct *product = purchase.product;
        
        result = (nil != product);
        if (result) {
            
            SKPayment *payment = [SKPayment paymentWithProduct:product];
            [[SKPaymentQueue defaultQueue] addPayment:payment];
        }
    }
    
    return result;
}

#pragma mark -
#pragma mark private methods
#pragma mark -

- (instancetype)init {
    
    NSAssert(nil == _gSharedIAPManagerInstanse, @"IAPManager's init method should not be called dirrectly. Use sharedInstanse instead");
    self = [super init];
    if (self) {
        
        self.products = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPersonality valueOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPersonality];
        
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    }
    return self;
}

#pragma mark -
#pragma mark SKproductsRequestDelegate methods
#pragma mark -

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
    
    NSMutableArray *validProducts = [@[] mutableCopy];

    for(SKProduct *product in response.products) {
        
        @synchronized(self) {
         
            IAPurchase *purchase = [self.products objectForKey:product.productIdentifier];
            NSAssert(nil != purchase, @"Invalid configuration. No accosiated records for transaction with productId=%@", product.productIdentifier);
            
            purchase.product = product;
        }
        
        [validProducts addObject:product];
        
#if DEBUG
        NSLog(@"Received SKProduct with productId: %@" , product.productIdentifier);
#endif
    }
    
#if DEBUG
    for(NSString *invalidProductID in response.invalidProductIdentifiers)
        NSLog(@"Invalid productId: %@" , invalidProductID);
#endif

    @synchronized(self) {
    
        self.validProducts = validProducts;
        
        if (self.loadStoreCompletionBlock) {
            
            self.loadStoreCompletionBlock(response.products, response.invalidProductIdentifiers);
        }
    }
}

#pragma mark -
#pragma mark Purchase helpers
#pragma mark -

- (void)recordTransaction:(SKPaymentTransaction *)transaction {
    
    @synchronized(self) {
    
        IAPurchase *purchase = [self.products objectForKey:transaction.payment.productIdentifier];
        NSAssert(nil != purchase, @"Invalid configuration. No accosiated records for transaction with productId=%@", transaction.payment.productIdentifier);
    }
    
    if ([transaction respondsToSelector:@selector(transactionReceipt)]) {
        NSString *receiptKey = transaction.payment.productIdentifier;
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"
        [defaults setValue:transaction.transactionReceipt forKey:receiptKey ];
#pragma clang diagnostic pop        
        [defaults synchronize];
    }
}

- (void)finishTransaction:(SKPaymentTransaction *)transaction wasSuccessful:(BOOL)wasSuccessful {
    
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
    
    __block IAPurchase *purchase = nil;
    @synchronized(self) {
    
        purchase = [self.products objectForKey:transaction.payment.productIdentifier];
        NSAssert(nil != purchase, @"Invalid configuration. No accosiated records for transaction with productId=%@", transaction.payment.productIdentifier);
    }

#warning validate receipt here
//    if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_6_1) {
//        // Load resources for iOS 6.1 or earlier
//    } else {
//        // Load resources for iOS 7 or later
//        [[NSBundle mainBundle] appStoreReceiptURL]
//    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        @synchronized(self) {
         
            if (wasSuccessful) {
                
                for (IAPObserver *observer in purchase.observers) {
                    
                    if (observer.onSuccessPurchaseBlock) {
                        
                        observer.onSuccessPurchaseBlock(transaction);
                    }
                }
            } else {
                
                for (IAPObserver *observer in purchase.observers) {
                    
                    if (observer.onFailPurchaseBlock) {
                        
                        observer.onFailPurchaseBlock(transaction);
                    }
                }
            }
        }
    });
}

- (void)completeTransaction:(SKPaymentTransaction *)transaction {
    
    [self recordTransaction:transaction];
    [self finishTransaction:transaction wasSuccessful:YES];
}

- (void)restoreTransaction:(SKPaymentTransaction *)transaction {
    
    [self recordTransaction:transaction.originalTransaction];
    [self finishTransaction:transaction wasSuccessful:YES];
}

- (void)failedTransaction:(SKPaymentTransaction *)transaction {
    
    if (SKErrorPaymentCancelled != transaction.error.code) {
        
        [self finishTransaction:transaction wasSuccessful:NO];
    } else {
        
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
    }
}

#pragma mark -
#pragma mark SKPaymentTransactionObserver methods
#pragma mark -

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions {
    
    for (SKPaymentTransaction *transaction in transactions) {
        
        switch (transaction.transactionState) {
                
            case SKPaymentTransactionStatePurchased:
                [self completeTransaction:transaction];
                break;
                
            case SKPaymentTransactionStateFailed:
                [self failedTransaction:transaction];
                break;
                
            case SKPaymentTransactionStateRestored:
                [self restoreTransaction:transaction];
                break;
                
            default:
                break;
        }
    }
}

@end
