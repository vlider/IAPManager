IAPManager
==========

Easy to use util for integrating InApp Purchases into iOS projects.
At the moment only local receipt verification implemented.

Additional thanks for Ruotger Skupin who shared receipt parsing and validation code here https://github.com/roddi/ValidateStoreReceipt

How it works:
First of all clone the project. OpenSSL-Xcode submodule project used for building openssl lib, prodived by ZETETIC LLC(https://github.com/sqlcipher/openssl-xcode).

IAPManager have 2 targets, one for fast testing of InApp Purchases, another one for using within your project.
For testing simple do following:
- In STAppDelegate.m replace ```<#HARDCODED_BUNDLEI_ID#>``` and ```<#HARDCODED_VERSION#>``` with values from your project
- In STAppDelegate.m replace ```<#IAP prductId#>``` with porductId that you want to test
- In STAppDelegate.m add following line into ```loadStoreWithCompletion:``` block to place your purchase: ```[[IAPManager sharedInstanse] placePaymentForProductWithId:@"<#IAP prductId#>"];```. Do not forget to use the same ```<#IAP prductId#>``` that was used in ```addObserver:forProductWithId:performOnSuccessfulPurchase:performOnFailedPurchase``` call
- In IAPManager-Info.plist change ```Bundle version string, short``` and ```Bundle identifier``` to your own project values. Also change ```Provisioning Profile``` in IAPManager target ```Build Settings``` to your profile
- Run IAPManager target. Do not forget to use test iTunes account. After fetching products you will see purchase confirmation alert.

###Intergration into your project
Drag IAPManager.xcodeproj into project tree, then open Project settings->Build Phases and add into Target Dependencies iapmanger. Then Open Link Binary With Libraries and add libiapmanager.a here.
Now you are ready to use IAPManager!

Include header
```
#import "IAPManager.h"
```

Do not forget to add ```AppleIncRootCertificate.cer``` file into ```Copy Bundle Resources```

Specify bundleId and versionString. Hardcode them instead of reading values from Info.plist file:
```
[IAPManager sharedInstanse].bundleId = @"com.companyname.productname";
[IAPManager sharedInstanse].versionString = @"1.0";
```
Specify list of porductIds by using followed methods:
```
addObserver:forProductWithId:performOnSuccessfulPurchase:performOnFailedPurchase:
addObserver:forProductsWithIds:performOnSuccessfulPurchase:performOnFailedPurchase:
```
Example:
```
[[IAPManager sharedInstanse] addObserver:self forProductWithId:@"remove_advertisement" performOnSuccessfulPurchase:^(SKPaymentTransaction *transaction) {
        //Handle successful purchase here
    } performOnFailedPurchase:^(SKPaymentTransaction *transaction) {
        //Handle failed purchase here
    }];
```    
```
[[IAPManager sharedInstanse] addObserver:self forProductsWithIds:@[@"remove_advertisement", @"get_10_skins"] performOnSuccessfulPurchase:^(SKPaymentTransaction *transaction) {
        //Handle successful purchase here
    } performOnFailedPurchase:^(SKPaymentTransaction *transaction) {
        //Handle failed purchase here
    }];
```
After setting bundleId, versionString, adding blocks for observing call ```loadStoreWithCompletion``` to fetch available products. As a result compeltion block will be called with list of requested products and invalid products ids:
```
[[IAPManager sharedInstanse] loadStoreWithCompletion:^(NSArray *validProducts, NSArray *invalidProductIds) {
    }];
```
###IMPORTANT
Place
```[IAPManager sharedInstanse].bundleId = …```
```[IAPManager sharedInstanse].versionString = …```
and all purchase observers before calling ```loadStoreWithCompletion```

Placing purchase:
```
[[IAPManager sharedInstanse] placePaymentForProductWithId:@"remove_advertisement"];
```
On success or failure one of the blocks specified in ```addObserver:forProductWithId:performOnSuccessfulPurchase:performOnFailedPurchase:``` will be called.

If you requested for productId that you did not specify in one of ```addObserver:…``` methods, or for some reason ```loadStoreWithCompletion``` return not empty ```invalidProductIds``` then calling ```placePaymentForProductWithId:``` with one of the values from that list will return ```NO```. Payment will not be queued, so ```…performOnFailedPurchase:``` block also not called.
Please check return value from ```placePaymentForProductWithId:```, or call ```canPlacePaymentForProductWithId:``` to make sure that specified product can be purchased.
