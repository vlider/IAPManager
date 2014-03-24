//
//  IAPManager.m
//  IAPManager
//
//  Created by Valerii Lider on 3/6/14.
//  Copyright (c) 2014 Spire LLC. All rights reserved.
//

#import "IAPManager.h"

#import <Security/Security.h>
#import <StoreKit/StoreKit.h>
#include <openssl/pkcs7.h>
#include <openssl/objects.h>
#include <openssl/sha.h>
#include <openssl/x509.h>
#include <openssl/err.h>

NSString *kReceiptBundleIdentifier                      = @"BundleIdentifier";
NSString *kReceiptBundleIdentifierData                  = @"BundleIdentifierData";
NSString *kReceiptVersion                               = @"Version";
NSString *kReceiptOpaqueValue                           = @"OpaqueValue";
NSString *kReceiptHash                                  = @"Hash";
NSString *kReceiptInApp                                 = @"InApp";
NSString *kReceiptOriginalVersion                       = @"OrigVer";
NSString *kReceiptExpirationDate                        = @"ExpDate";

NSString *kReceiptInAppQuantity                         = @"Quantity";
NSString *kReceiptInAppProductIdentifier                = @"ProductIdentifier";
NSString *kReceiptInAppTransactionIdentifier            = @"TransactionIdentifier";
NSString *kReceiptInAppPurchaseDate                     = @"PurchaseDate";
NSString *kReceiptInAppOriginalTransactionIdentifier    = @"OriginalTransactionIdentifier";
NSString *kReceiptInAppOriginalPurchaseDate             = @"OriginalPurchaseDate";
NSString *kReceiptInAppSubscriptionExpirationDate       = @"SubExpDate";
NSString *kReceiptInAppCancellationDate                 = @"CancelDate";
NSString *kReceiptInAppWebOrderLineItemID               = @"WebItemId";

// ASN.1 values for the App Store receipt
#define ATTR_START          1
#define BUNDLE_ID           2
#define VERSION             3
#define OPAQUE_VALUE        4
#define HASH                5
#define ATTR_END            6
#define INAPP_PURCHASE      17
#define ORIG_VERSION        19
#define EXPIRE_DATE         21

// ASN.1 values for In-App Purchase values
#define INAPP_ATTR_START	1700
#define INAPP_QUANTITY		1701
#define INAPP_PRODID		1702
#define INAPP_TRANSID		1703
#define INAPP_PURCHDATE		1704
#define INAPP_ORIGTRANSID	1705
#define INAPP_ORIGPURCHDATE	1706
#define INAPP_ATTR_END		1707
#define INAPP_SUBEXP_DATE   1708
#define INAPP_WEBORDER      1711
#define INAPP_CANCEL_DATE   1712

@interface IAPObserver : NSObject
@property (nonatomic, strong) NSObject *purchaseObserver;
@property (nonatomic, copy) onPurchaseBlock onSuccessPurchaseBlock;
@property (nonatomic, copy) onFailPurchaseBlock onFailPurchaseBlock;
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

@interface IAPManager () <SKPaymentTransactionObserver, SKProductsRequestDelegate, SKRequestDelegate>
@property (nonatomic, strong) NSMapTable *products;
@property (nonatomic, strong) SKProductsRequest *productsRequest;
@property (nonatomic, copy) onStoreLoadedBlock loadStoreCompletionBlock;
@property (nonatomic, copy) onPurchasesRestoredBlock retoreCompletionBlock;
@property (nonatomic, strong) NSArray *validProducts;
@property (nonatomic, strong) NSArray *invalidProductIds;
@end

@implementation IAPManager

static IAPManager *_gSharedIAPManagerInstanse = nil;

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

- (void)addObserver:(NSObject *)observer forProductWithId:(NSString *)productId performOnSuccessfulPurchase:(onPurchaseBlock)onSuccessBlock performOnFailedPurchase:(onFailPurchaseBlock)onFailureBlock {
    
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

- (void)addObserver:(NSObject *)observer forProductsWithIds:(NSArray *)productIds performOnSuccessfulPurchase:(onPurchaseBlock)onSuccessBlock performOnFailedPurchase:(onFailPurchaseBlock)onFailureBlock {
    
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

    NSAssert(nil != self.bundleId, @"bundleId property not set");
    NSAssert(nil != self.versionString, @"versionString property not set");
    
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

- (void)restorePurchasesWithCompletion:(onPurchasesRestoredBlock)completionBlock {
    
    self.retoreCompletionBlock = completionBlock;
    
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

/*
 * Thanks to Roddy's ValidateStoreReceipt code("https://github.com/roddi/ValidateStoreReceipt")
 * validateReceipt: and parseInAppPurchasesData: methods are uses code from ValidateStoreReceipt with some modifications.
 *
 * Created by Ruotger Skupin on 23.10.10.
 * Copyright 2010-2011 Matthew Stevens, Ruotger Skupin, Apple, Dave Carlton, Fraser Hess, anlumo, David Keegan, Alessandro Segala.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification, are permitted provided that 
 * the following conditions are met:
 *
 * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 *
 * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in
 * the documentation and/or other materials provided with the distribution.
 *
 * Neither the name of the copyright holders nor the names of its contributors may be used to endorse or promote products derived
 * from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,
 * BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
 * SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
- (BOOL)validateReceipt:(NSData *)receiptData forTransaction:(SKPaymentTransaction *)transaction {
    
    NSParameterAssert(nil != receiptData);
    
    BOOL valid = NO;
    NSMutableDictionary *result = nil;
    X509 *appleRootCertificate = NULL;
    PKCS7 *receipt = NULL;
    
    ERR_load_PKCS7_strings();
	ERR_load_X509_strings();
	OpenSSL_add_all_digests();
    
    while (true) {
        
        //Load PKCS7
        const unsigned char *receiptBytes = receiptData.bytes;
        receipt = d2i_PKCS7(NULL, &receiptBytes, receiptData.length);
        if (!receipt)
            break;
        
        if (!PKCS7_type_is_signed(receipt))
            break;
        
        if (!PKCS7_type_is_data(receipt->d.sign->contents))
            break;
        
        //Load Apple's root certificate
        NSString *certPath = [[NSBundle mainBundle] pathForResource:@"AppleIncRootCertificate" ofType:@"cer"];
        NSData *certData = [NSData dataWithContentsOfFile:certPath];
        const uint8_t *certBytes = (uint8_t *)(certData.bytes);
        appleRootCertificate = d2i_X509(NULL, &certBytes, (long)certData.length);
        if (!appleRootCertificate)
            break;
        
        //Verify PKCS7
        int verifyReturnValue = 0;
        X509_STORE *store = X509_STORE_new();
        if (store) {
            
            BIO *payload = BIO_new(BIO_s_mem());
            X509_STORE_add_cert(store, appleRootCertificate);
            
            if (payload) {
                
                verifyReturnValue = PKCS7_verify(receipt, NULL, store, NULL, payload, 0);
                BIO_free(payload);
            }
            
            X509_STORE_free(store);
        }
        
        EVP_cleanup();
        
        if (0 == verifyReturnValue)
            break;
        
        //Check for payload structure. It should be a set of attributes
        ASN1_OCTET_STRING *octets = receipt->d.sign->contents->d.data;
        const uint8_t *p = octets->data;
        const uint8_t *end = p + octets->length;
        
        int type = 0;
        int xclass = 0;
        long length = 0;
        
        ASN1_get_object(&p, &length, &type, &xclass, end - p);
        if (type != V_ASN1_SET)
            break;
        
        result = [@{} mutableCopy];
        
        while (p < end) {
            
            ASN1_get_object(&p, &length, &type, &xclass, end - p);
            if (type != V_ASN1_SEQUENCE)
                break;
            
            const uint8_t *seq_end = p + length;
            
            int attr_type = 0;
            int attr_version = 0;
            
            // Attribute type
            ASN1_get_object(&p, &length, &type, &xclass, seq_end - p);
            if (type == V_ASN1_INTEGER && length == 1) {
                attr_type = p[0];
            }
            p += length;
            
            // Attribute version
            ASN1_get_object(&p, &length, &type, &xclass, seq_end - p);
            if (type == V_ASN1_INTEGER && length == 1) {
                attr_version = p[0];
                attr_version = attr_version;
            }
            p += length;
            
            // Only parse attributes we're interested in
            if ((attr_type > ATTR_START && attr_type < ATTR_END) || attr_type == INAPP_PURCHASE || attr_type == ORIG_VERSION || attr_type == EXPIRE_DATE) {
                NSString *key = nil;
                
                ASN1_get_object(&p, &length, &type, &xclass, seq_end - p);
                if (type == V_ASN1_OCTET_STRING) {
                    NSData *data = [NSData dataWithBytes:p length:(NSUInteger)length];
                    
                    // Bytes
                    if (attr_type == BUNDLE_ID || attr_type == OPAQUE_VALUE || attr_type == HASH) {
                        
                        switch (attr_type) {
                                
                            case BUNDLE_ID:
                                // This is included for hash generation
                                key = kReceiptBundleIdentifierData;
                                break;
                            case OPAQUE_VALUE:
                                key = kReceiptOpaqueValue;
                                break;
                            case HASH:
                                key = kReceiptHash;
                                break;
                        }
                        if (key) {
                            
                            result[key] = data;
                        }
                    }
                    
                    // Strings
                    if (attr_type == BUNDLE_ID || attr_type == VERSION || attr_type == ORIG_VERSION) {
                        
                        int str_type = 0;
                        long str_length = 0;
                        const uint8_t *str_p = p;
                        ASN1_get_object(&str_p, &str_length, &str_type, &xclass, seq_end - str_p);
                        if (str_type == V_ASN1_UTF8STRING) {
                            
                            switch (attr_type) {
                                    
                                case BUNDLE_ID:
                                    key = kReceiptBundleIdentifier;
                                    break;
                                case VERSION:
                                    key = kReceiptVersion;
                                    break;
                                case ORIG_VERSION:
                                    key = kReceiptOriginalVersion;
                                    break;
                            }
                            
                            if (key) {
                                
                                NSString *string = [[NSString alloc] initWithBytes:str_p
                                                                            length:(NSUInteger)str_length
                                                                          encoding:NSUTF8StringEncoding];
                                if (string) {
                                    
                                    result[key] = string;
                                }
                            }
                        }
                    }
                    
                    // In-App purchases
                    if (attr_type == INAPP_PURCHASE) {
                        
                        NSArray *inApp = [self parseInAppPurchasesData:data];
                        NSArray *current = result[kReceiptInApp];
                        if (current) {
                            
                            result[kReceiptInApp] = [current arrayByAddingObjectsFromArray:inApp];
                        } else {
                            
                            result[kReceiptInApp] = inApp;
                        }
                    }
                }
                p += length;
            }
            
            // Skip any remaining fields in this SEQUENCE
            while (p < seq_end) {
                
                ASN1_get_object(&p, &length, &type, &xclass, seq_end - p);
                p += length;
            }
        }
        
        unsigned char uuidBytes[16];
        NSUUID *vendorUUID = [[UIDevice currentDevice] identifierForVendor];
        [vendorUUID getUUIDBytes:uuidBytes];
        
        NSMutableData *input = [NSMutableData new];
        [input appendBytes:uuidBytes length:sizeof(uuidBytes)];
        [input appendData:result[kReceiptOpaqueValue]];
        [input appendData:result[kReceiptBundleIdentifierData]];
        
        NSMutableData *hash = [NSMutableData dataWithLength:SHA_DIGEST_LENGTH];
        SHA1([input bytes], [input length], [hash mutableBytes]);
        
        valid = [hash isEqualToData:result[kReceiptHash]];
        if (valid) {
            
            BOOL found = NO;
            NSArray *purchases = result[kReceiptInApp];
            for (NSDictionary *purchase in purchases) {
                
                NSString *productId = purchase[kReceiptInAppProductIdentifier];
                if ([productId isEqualToString:transaction.payment.productIdentifier]) {
                    
                    found = YES;
                    break;
                }
            }
            
            valid &= found;
            if (valid) {
                
                valid &= [result[kReceiptBundleIdentifier] isEqualToString:self.bundleId];
                valid &= [result[kReceiptVersion] isEqualToString:self.versionString];
            }
        }
        
#if DEBUG
        NSLog(@"Receipt: %@", result);
#endif
        break;
    }

    if (receipt) {
        
        PKCS7_free(receipt);
        receipt = NULL;
    }

    if (appleRootCertificate) {
        
        X509_free(appleRootCertificate);
        appleRootCertificate = NULL;
    }

    return valid;
}

- (NSArray *)parseInAppPurchasesData:(NSData *)inappData {
    
    NSParameterAssert(nil != inappData);
    
	int type = 0;
	int xclass = 0;
	long length = 0;
    
	NSUInteger dataLenght = inappData.length;
	const uint8_t *p = inappData.bytes;
	const uint8_t *end = p + dataLenght;
    
	NSMutableArray *resultArray = [NSMutableArray new];
    
	while (p < end) {
        
		ASN1_get_object(&p, &length, &type, &xclass, end - p);
        
		const uint8_t *set_end = p + length;
        
		if(type != V_ASN1_SET) {
			break;
		}
        
		NSMutableDictionary *item = [[NSMutableDictionary alloc] initWithCapacity:6];
        
		while (p < set_end) {
			ASN1_get_object(&p, &length, &type, &xclass, set_end - p);
			if (type != V_ASN1_SEQUENCE) {
				break;
            }
            
			const uint8_t *seq_end = p + length;
            
			int attr_type = 0;
			int attr_version = 0;
            
			// Attribute type
			ASN1_get_object(&p, &length, &type, &xclass, seq_end - p);
			if (type == V_ASN1_INTEGER) {
				if(length == 1) {
					attr_type = p[0];
				}
				else if(length == 2) {
					attr_type = p[0] * 0x100 + p[1]
					;
				}
			}
			p += length;
            
			// Attribute version
			ASN1_get_object(&p, &length, &type, &xclass, seq_end - p);
			if (type == V_ASN1_INTEGER && length == 1) {
                // clang analyser hit (wontfix at the moment, since the code might come in handy later)
                // But if someone has a convincing case throwing that out, I might do so, Roddi
				attr_version = p[0];
			}
			p += length;
            
			// Only parse attributes we're interested in
			if ((attr_type > INAPP_ATTR_START && attr_type < INAPP_ATTR_END) || attr_type == INAPP_SUBEXP_DATE || attr_type == INAPP_WEBORDER || attr_type == INAPP_CANCEL_DATE) {
                
				NSString *key = nil;
                
				ASN1_get_object(&p, &length, &type, &xclass, seq_end - p);
				if (type == V_ASN1_OCTET_STRING) {
                    
					// Integers
					if (attr_type == INAPP_QUANTITY || attr_type == INAPP_WEBORDER) {
                        
						int num_type = 0;
						long num_length = 0;
						const uint8_t *num_p = p;
						ASN1_get_object(&num_p, &num_length, &num_type, &xclass, seq_end - num_p);
						if (num_type == V_ASN1_INTEGER) {
                            
							NSUInteger quantity = 0;
							if (num_length) {
								quantity += num_p[0];
								if (num_length > 1) {
									quantity += num_p[1] * 0x100;
									if (num_length > 2) {
										quantity += num_p[2] * 0x10000;
										if (num_length > 3) {
											quantity += num_p[3] * 0x1000000;
										}
									}
								}
							}
                            
							NSNumber *num = [[NSNumber alloc] initWithUnsignedInteger:quantity];
                            if (attr_type == INAPP_QUANTITY) {
                                
                                item[kReceiptInAppQuantity] = num;
                            } else if (attr_type == INAPP_WEBORDER) {
                                
                                item[kReceiptInAppWebOrderLineItemID] = num;
                            }
						}
					}
                    
					// Strings
					if (attr_type == INAPP_PRODID ||
                        attr_type == INAPP_TRANSID ||
                        attr_type == INAPP_ORIGTRANSID ||
                        attr_type == INAPP_PURCHDATE ||
                        attr_type == INAPP_ORIGPURCHDATE ||
                        attr_type == INAPP_SUBEXP_DATE ||
                        attr_type == INAPP_CANCEL_DATE) {
                        
						int str_type = 0;
						long str_length = 0;
						const uint8_t *str_p = p;
						ASN1_get_object(&str_p, &str_length, &str_type, &xclass, seq_end - str_p);
						if (str_type == V_ASN1_UTF8STRING) {
                            
							switch (attr_type) {
                                    
								case INAPP_PRODID:
									key = kReceiptInAppProductIdentifier;
									break;
								case INAPP_TRANSID:
									key = kReceiptInAppTransactionIdentifier;
									break;
								case INAPP_ORIGTRANSID:
									key = kReceiptInAppOriginalTransactionIdentifier;
									break;
							}
                            
							if (key) {
                                
								NSString *string = [[NSString alloc] initWithBytes:str_p
																			length:(NSUInteger)str_length
																		  encoding:NSUTF8StringEncoding];
                                if (string) {
                                    
                                    item[key] = string;
                                }
							}
						}
						if (str_type == V_ASN1_IA5STRING) {
                            
							switch (attr_type) {
                                    
								case INAPP_PURCHDATE:
									key = kReceiptInAppPurchaseDate;
									break;
								case INAPP_ORIGPURCHDATE:
									key = kReceiptInAppOriginalPurchaseDate;
									break;
								case INAPP_SUBEXP_DATE:
									key = kReceiptInAppSubscriptionExpirationDate;
									break;
								case INAPP_CANCEL_DATE:
									key = kReceiptInAppCancellationDate;
									break;
							}
                            
							if (key) {
                                
								NSString *string = [[NSString alloc] initWithBytes:str_p
																			length:(NSUInteger)str_length
																		  encoding:NSASCIIStringEncoding];
                                if (key) {
                                    
                                    item[key] = string;
                                }
							}
						}
					}
				}
                
				p += length;
			}
            
			// Skip any remaining fields in this SEQUENCE
			while (p < seq_end) {
                
				ASN1_get_object(&p, &length, &type, &xclass, seq_end - p);
				p += length;
			}
		}
        
		// Skip any remaining fields in this SET
		while (p < set_end) {
            
			ASN1_get_object(&p, &length, &type, &xclass, set_end - p);
			p += length;
		}
        
		[resultArray addObject:item];
	}
    
	return resultArray;
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
        self.invalidProductIds = response.invalidProductIdentifiers;
    }
    
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1) {

        // Load resources for iOS 7 or later
        NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
        if (![[NSFileManager defaultManager] fileExistsAtPath:receiptURL.path]) {
            
            //request for receipt if it is not available
            SKReceiptRefreshRequest *request = [[SKReceiptRefreshRequest alloc] initWithReceiptProperties:nil];
            request.delegate = self;
            [request start];
        } else {
            
            @synchronized(self) {
             
                if (self.loadStoreCompletionBlock) {
                    
                    self.loadStoreCompletionBlock(self.validProducts, self.invalidProductIds);
                }
            }
        }
    } else {
        
        @synchronized(self) {
            
            if (self.loadStoreCompletionBlock) {
                
                self.loadStoreCompletionBlock(self.validProducts, self.invalidProductIds);
            }
        }
    }
}

#pragma mark -
#pragma mark Purchase helpers
#pragma mark -

- (void)finishTransaction:(SKPaymentTransaction *)transaction wasSuccessful:(BOOL)wasSuccessful {
    
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
    
    __block IAPurchase *purchase = nil;
    @synchronized(self) {
    
        purchase = [self.products objectForKey:transaction.payment.productIdentifier];
        NSAssert(nil != purchase, @"Invalid configuration. No accosiated records for transaction with productId=%@", transaction.payment.productIdentifier);
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        @synchronized(self) {
         
            if (wasSuccessful) {
                
                NSString *bundleId = [[NSBundle mainBundle] objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleIdentifierKey];
                NSString *versionString = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
                
                BOOL valid = [self.bundleId isEqualToString:bundleId];
                valid &= [self.versionString isEqualToString:versionString];
                if (valid) {
                    
                    NSData *receipt = nil;
                    if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_6_1) {
                        
                        //Get receipt from transaction if iOS <= 6.1
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"
                        receipt = transaction.transactionReceipt;
#pragma clang diagnostic pop
                    } else {
                        
                        //Get receipt from bundle if iOS >= 7.0
                        NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
                        receipt = [NSData dataWithContentsOfURL:receiptURL];
                    }
                    
                    valid &= (nil != receipt);
                    if (valid) {
                        
                        valid = [self validateReceipt:receipt forTransaction:transaction];
                    }
                }
                
                for (IAPObserver *observer in purchase.observers) {
                    
                    if (valid) {
                        
                        if (observer.onSuccessPurchaseBlock) {
                            
                            observer.onSuccessPurchaseBlock(transaction);
                        }
                    } else {
                        
                        if (observer.onFailPurchaseBlock) {
                            
                            observer.onFailPurchaseBlock(transaction, NO);
                        }
                    }
                }

            } else {
                
                for (IAPObserver *observer in purchase.observers) {
                    
                    if (observer.onFailPurchaseBlock) {
                        
                        observer.onFailPurchaseBlock(transaction, (SKErrorPaymentCancelled == transaction.error.code));
                    }
                }
            }
        }
    });
}

#pragma mark -
#pragma mark SKPaymentTransactionObserver methods
#pragma mark -

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions {
    
    for (SKPaymentTransaction *transaction in transactions) {
        
        switch (transaction.transactionState) {
                
            case SKPaymentTransactionStatePurchased:
                [self finishTransaction:transaction wasSuccessful:YES];
                break;
                
            case SKPaymentTransactionStateFailed:
                [self finishTransaction:transaction wasSuccessful:NO];
                break;
                
            case SKPaymentTransactionStateRestored:
                [self finishTransaction:transaction wasSuccessful:YES];
                break;
                
            default:
                break;
        }
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedDownloads:(NSArray *)downloads {

#warning NOT IMPLEMENTED
//    for (SKDownload *download in downloads) {
//        
//        if (download.error) {
//#if DEBUG
//            NSLog(@"Download failed for %@", download.transaction.payment.productIdentifier);
//#endif
//        }
//        
//        switch (download.downloadState) {
//            case SKDownloadStateFinished: {
//                
//                NSURL *contentURL = download.contentURL;
//                break;
//            }
//            default:
//                break;
//        }
//    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
    
#if DEBUG
    NSLog(@"Restore completed transactions failed with error: %@", error);
#endif
    
    if (self.retoreCompletionBlock) {
        
        self.retoreCompletionBlock(error, (SKErrorPaymentCancelled == error.code));
    }
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
    
    if (self.retoreCompletionBlock) {
        
        self.retoreCompletionBlock(nil, NO);
    }
}

#pragma mark -
#pragma mark SKRequestDelegate methods
#pragma mark -

- (void)requestDidFinish:(SKRequest *)request {
    
    Class requestClass = NSClassFromString(@"SKReceiptRefreshRequest");
    if (requestClass && [request isKindOfClass:requestClass]) {
     
        NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
        if (![[NSFileManager defaultManager] fileExistsAtPath:receiptURL.path]) {
            
#if DEBUG
            NSLog(@"Unable to refresh appStoreReceipt at this time. Any purchase will be failed");
#endif
        } else {
            
            @synchronized(self) {
                
                if (self.loadStoreCompletionBlock) {
                    
                    self.loadStoreCompletionBlock(self.validProducts, self.invalidProductIds);
                }
            }
        }
    }
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    
    Class requestClass = NSClassFromString(@"SKReceiptRefreshRequest");
    if (requestClass && [request isKindOfClass:requestClass]) {
        
#if DEBUG
        NSLog(@"Unable to refresh appStoreReceipt at this time. Any purchase will be failed");
#endif
        
        @synchronized(self) {
            
            if (self.loadStoreCompletionBlock) {
                
                self.loadStoreCompletionBlock(self.validProducts, self.invalidProductIds);
            }
        }
    }
}

@end
