//
//  STAppDelegate.m
//  IAPManager
//
//  Created by Valerii Lider on 3/6/14.
//  Copyright (c) 2014 Spire LLC. All rights reserved.
//
//  It is appreciated but not required that you give credit to Valerii Lider,
//  as the original author of this code. You can give credit in a blog post, a tweet or on
//  a info page of your app. Also, the original author appreciate letting them know if you use this code.
//
//  This code is licensed under the APPACHE license that is available at: http://www.apache.org/licenses/LICENSE-2.0
//

#import "STAppDelegate.h"

@import StoreKit;
#import "IAPManager/IAPManager.h"

@implementation STAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    // Override point for customization after application launch.
    self.window.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];
    
    /*
     * Here is an example of IAPManager usage
     */
    
    /* Set bundleId and versionString same as specified in info.plist file. 
     * IMPORTANT: Hard code this two values(@"com.companyname.productname", @"1.0", etc)
     * IMPORTANT: do not use [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifierKey"];
     * IMPORTANT: do not use [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
     */
    [IAPManager sharedInstanse].bundleId = @"<#HARDCODED_BUNDLEI_ID#>";
    [IAPManager sharedInstanse].versionString = @"<#HARDCODED_VERSION#>";
    
    /*
     * Call this method to observe purchases for specific productId.
     * If purchase succeeds then first block will be performed.
     * If purchase fails or validation fails then failure block will be called
     */
    [[IAPManager sharedInstanse] addObserver:self forProductWithId:@"<#IAP prductId#>" performOnSuccessfulPurchase:^(SKPaymentTransaction *transaction) {
        
        //Handle successful purchase here
    } performOnFailedPurchase:^(SKPaymentTransaction *transaction, BOOL cancelled) {
        
        //Handle failed purchase here
    }];
    
    /*
     * Request for products
     * IMPORTANT: call this method only after adding observers for purchases.
     */
    [[IAPManager sharedInstanse] loadStoreWithCompletion:^(NSArray *validProducts, NSArray *invalidProductIds) {
        
        /*
         * After successful loading store, if all products are valid you can make purchases.
         * To place order use placePaymentForProductWithId method like followed:
         * [[IAPManager sharedInstanse] placePaymentForProductWithId:@"<#IAP prductId#>"];
         */        
    }];

    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end
