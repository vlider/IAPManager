IAPManager
==========

Easy to use util for integrating InApp Purchases into iOS projects.
At the moment only local receipt verification implemented.

Additional thanks for Ruotger Skupin who shared receipt parsing and validation code here https://github.com/roddi/ValidateStoreReceipt

How it works:
First of all clone the project. Do git submodule init && git submodule update to fetch submodules. OpenSSL-Xcode prodived by ZETETIC LLC(https://github.com/sqlcipher/openssl-xcode) used by IAPManager. So please follow instructions for successful build openssl.
IAPManager have 2 targets, one for fast testing of InApp Purchases, another one for using within your project.
Drag IAPManager.xcodeproj into project tree, then open Project settings->Build Phases and add into Target Dependencies iapmanger. Then Open Link Binary With Libraries and add libiapmanager.a here.
Now you are ready to use IAPManager!

Include header
#import "IAPManager/IAPManager.h"

Specify bundleId and versionNumber. Hardcode them instead of using values from Info.plist file
[IAPManager sharedInstanse].bundleId = @"com.companyname.productname";
[IAPManager sharedInstanse].versionString = @"1.0";

Specify list of porductIds by using followed method:
addObserver:forProductWithId:performOnSuccessfulPurchase:performOnFailedPurchase:

Example:
[[IAPManager sharedInstanse] addObserver:self forProductWithId:@"remove_advertisement" performOnSuccessfulPurchase:^(SKPaymentTransaction *transaction) {
        
        //Handle successful purchase here
    } performOnFailedPurchase:^(SKPaymentTransaction *transaction) {
        
        //Handle failed purchase here
    }];
    
After setting bundleId, versionString, adding blocks for observing call loadStoreWithCompletion to fetch available products. As a result compeltion block will be called with list of requested products.

Placing purchase:
[[IAPManager sharedInstanse] placePaymentForProductWithId:@"remove_advertisement"];
