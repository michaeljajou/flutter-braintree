import Flutter
import UIKit
import Braintree
import BraintreeDropIn
import PassKit

func makePaymentSummaryItems(from: Dictionary<String, Any>) -> [PKPaymentSummaryItem]? {
    guard let paymentSummaryItems = from["paymentSummaryItems"] as? [Dictionary<String, Any>] else {
        return nil;
    }

    var outList: [PKPaymentSummaryItem] = []
    for paymentSummaryItem in paymentSummaryItems {
        guard let label = paymentSummaryItem["label"] as? String else {
            return nil;
        }
        guard let amount = paymentSummaryItem["amount"] as? Double else {
            return nil;
        }
        guard let type = paymentSummaryItem["type"] as? UInt else {
            return nil;
        }
        guard let pkType = PKPaymentSummaryItemType.init(rawValue: type) else {
            return nil;
        }
        outList.append(PKPaymentSummaryItem(label: label, amount: NSDecimalNumber(value: amount), type: pkType));
    }

    return outList;
}

public class FlutterBraintreeDropInPlugin: BaseFlutterBraintreePlugin, FlutterPlugin, BTThreeDSecureRequestDelegate {
    
    private var completionBlock: FlutterResult!
    private var applePayInfo = [String : Any]()
    private var authorization: String!
    
    public func onLookupComplete(_ request: BTThreeDSecureRequest, lookupResult result: BTThreeDSecureResult, next: @escaping () -> Void) {
        next();
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_braintree.drop_in", binaryMessenger: registrar.messenger())
        
        let instance = FlutterBraintreeDropInPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        completionBlock = result

        if call.method == "start" {
            print("✅ [Braintree] Starting Drop-In flow...")

            guard !isHandlingResult else {
                print("⚠️ [Braintree] Drop-In already presented, aborting.")
                returnAlreadyOpenError(result: result)
                return
            }

            isHandlingResult = true

            let threeDSecureRequest = BTThreeDSecureRequest()
            print("✅ [Braintree] Initialized 3D Secure request.")

            if let email = string(for: "email", in: call) {
                threeDSecureRequest.email = email
                print("📧 [Braintree] Email set for 3DS: \(email)")
            }
            threeDSecureRequest.versionRequested = .version2

            if let billingAddress = dict(for: "billingAddress", in: call) {
                print("📦 [Braintree] Billing address received: \(billingAddress)")
                let address = BTThreeDSecurePostalAddress()
                address.givenName = billingAddress["givenName"] as? String
                address.surname = billingAddress["surname"] as? String
                address.phoneNumber = billingAddress["phoneNumber"] as? String
                address.streetAddress = billingAddress["streetAddress"] as? String
                address.extendedAddress = billingAddress["extendedAddress"] as? String
                address.locality = billingAddress["locality"] as? String
                address.region = billingAddress["region"] as? String
                address.postalCode = billingAddress["postalCode"] as? String
                address.countryCodeAlpha2 = billingAddress["countryCodeAlpha2"] as? String

                print("📦 [Braintree] Parsed billing address: \(address)")

                threeDSecureRequest.billingAddress = address

                let info = BTThreeDSecureAdditionalInformation()
                info.shippingAddress = address
                threeDSecureRequest.additionalInformation = info
            } else {
                print("⚠️ [Braintree] No billing address provided.")
            }

            let dropInRequest = BTDropInRequest()

            if let amount = string(for: "amount", in: call) {
                threeDSecureRequest.threeDSecureRequestDelegate = self
                threeDSecureRequest.amount = NSDecimalNumber(string: amount)
                dropInRequest.threeDSecureRequest = threeDSecureRequest
                print("💰 [Braintree] Amount set for 3DS: \(amount)")
            } else {
                print("❌ [Braintree] Missing 'amount' in request.")
            }

            var deviceData: String?
            if let collectDeviceData = bool(for: "collectDeviceData", in: call), collectDeviceData {
                deviceData = PPDataCollector.collectPayPalDeviceData()
                print("📲 [Braintree] Collected device data.")
            }

            if let vaultManagerEnabled = bool(for: "vaultManagerEnabled", in: call) {
                dropInRequest.vaultManager = vaultManagerEnabled
                print("🔐 [Braintree] Vault manager enabled: \(vaultManagerEnabled)")
            }

            if let cardEnabled = bool(for: "cardEnabled", in: call) {
                dropInRequest.cardDisabled = !cardEnabled
                print("💳 [Braintree] Card enabled: \(cardEnabled)")
            }

            if let paypalEnabled = bool(for: "paypalEnabled", in: call) {
                dropInRequest.paypalDisabled = !paypalEnabled
                print("🅿️ [Braintree] PayPal enabled: \(paypalEnabled)")
            }

            if let paypalInfo = dict(for: "paypalRequest", in: call) {
                print("🅿️ [Braintree] PayPal info received.")
                if let amount = paypalInfo["amount"] as? String {
                    let paypalRequest = BTPayPalCheckoutRequest(amount: amount)
                    paypalRequest.currencyCode = paypalInfo["currencyCode"] as? String
                    paypalRequest.displayName = paypalInfo["displayName"] as? String
                    paypalRequest.billingAgreementDescription = paypalInfo["billingAgreementDescription"] as? String
                    dropInRequest.payPalRequest = paypalRequest
                    print("🅿️ [Braintree] Set up BTPayPalCheckoutRequest.")
                } else {
                    let paypalRequest = BTPayPalVaultRequest()
                    paypalRequest.displayName = paypalInfo["displayName"] as? String
                    paypalRequest.billingAgreementDescription = paypalInfo["billingAgreementDescription"] as? String
                    dropInRequest.payPalRequest = paypalRequest
                    print("🅿️ [Braintree] Set up BTPayPalVaultRequest.")
                }
            } else {
                dropInRequest.paypalDisabled = true
                print("❌ [Braintree] PayPal request disabled.")
            }

            if let applePayInfo = dict(for: "applePayRequest", in: call) {
                self.applePayInfo = applePayInfo
                print("🍎 [Braintree] Apple Pay request received.")
            } else {
                dropInRequest.applePayDisabled = true
                print("🍎 [Braintree] Apple Pay disabled.")
            }

            guard let authorization = getAuthorization(call: call) else {
                print("❌ [Braintree] Authorization missing.")
                returnAuthorizationMissingError(result: result)
                isHandlingResult = false
                return
            }

            self.authorization = authorization
            print("🔑 [Braintree] Authorization obtained.")

            let dropInController = BTDropInController(authorization: authorization, request: dropInRequest) { (controller, braintreeResult, error) in
                print("📥 [Braintree] DropInController completed.")
                controller.dismiss(animated: true, completion: nil)

                if let error = error {
                    print("❌ [Braintree] Error in DropInController: \(error.localizedDescription)")
                } else if let result = braintreeResult {
                    print("✅ [Braintree] DropInResult received: \(result)")
                } else {
                    print("⚠️ [Braintree] DropInResult is nil.")
                }

                self.handleResult(result: braintreeResult, error: error, flutterResult: result, deviceData: deviceData)
                self.isHandlingResult = false
            }

            guard let existingDropInController = dropInController else {
                print("❌ [Braintree] BTDropInController not initialized.")
                result(FlutterError(code: "braintree_error", message: "BTDropInController not initialized", details: nil))
                isHandlingResult = false
                return
            }

            print("🎬 [Braintree] Presenting DropInController...")
            UIApplication.shared.keyWindow?.rootViewController?.present(existingDropInController, animated: true, completion: nil)
        }
    }

    
    private func setupApplePay(flutterResult: FlutterResult) {
        let paymentRequest = PKPaymentRequest()
        if let supportedNetworksValueArray = applePayInfo["supportedNetworks"] as? [Int] {
            paymentRequest.supportedNetworks = supportedNetworksValueArray.compactMap({ value in
                return PKPaymentNetwork.mapRequestedNetwork(rawValue: value)
            })
        }
        paymentRequest.merchantCapabilities = .capability3DS
        paymentRequest.countryCode = applePayInfo["countryCode"] as! String
        paymentRequest.currencyCode = applePayInfo["currencyCode"] as! String
        paymentRequest.merchantIdentifier = applePayInfo["merchantIdentifier"] as! String
        
        guard let paymentSummaryItems = makePaymentSummaryItems(from: applePayInfo) else {
            return;
        }
        paymentRequest.paymentSummaryItems = paymentSummaryItems;

        guard let applePayController = PKPaymentAuthorizationViewController(paymentRequest: paymentRequest) else {
            return
        }
        
        applePayController.delegate = self
        
        UIApplication.shared.keyWindow?.rootViewController?.present(applePayController, animated: true, completion: nil)
    }
    
    private func handleResult(result: BTDropInResult?, error: Error?, flutterResult: FlutterResult, deviceData: String?) {
        if error != nil {
            returnBraintreeError(result: flutterResult, error: error!)
        } else if result?.isCanceled ?? false {
            flutterResult(nil)
        } else {
            if let result = result, result.paymentMethodType == .applePay {
                setupApplePay(flutterResult: flutterResult)
            } else {
                flutterResult(["paymentMethodNonce": buildPaymentNonceDict(nonce: result?.paymentMethod), "deviceData": deviceData])
            }
        }
    }
    
    private func handleApplePayResult(_ result: BTPaymentMethodNonce, flutterResult: FlutterResult) {
        flutterResult(["paymentMethodNonce": buildPaymentNonceDict(nonce: result)])
    }
}

// MARK: PKPaymentAuthorizationViewControllerDelegate
extension FlutterBraintreeDropInPlugin: PKPaymentAuthorizationViewControllerDelegate {
    public func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
        controller.dismiss(animated: true, completion: nil)
    }
    
    @available(iOS 11.0, *)
    public func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        guard let apiClient = BTAPIClient(authorization: authorization) else { return }
        let applePayClient = BTApplePayClient(apiClient: apiClient)
        
        applePayClient.tokenizeApplePay(payment) { (tokenizedPaymentMethod, error) in
            guard let paymentMethod = tokenizedPaymentMethod, error == nil else {
                completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                return
            }
            
            print(paymentMethod.nonce)
            self.handleApplePayResult(paymentMethod, flutterResult: self.completionBlock)
            completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
        }
    }

    public func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didAuthorizePayment payment: PKPayment, completion: @escaping (PKPaymentAuthorizationStatus) -> Void) {
        guard let apiClient = BTAPIClient(authorization: authorization) else { return }
        let applePayClient = BTApplePayClient(apiClient: apiClient)
        
        applePayClient.tokenizeApplePay(payment) { (tokenizedPaymentMethod, error) in
            guard let paymentMethod = tokenizedPaymentMethod, error == nil else {
                completion(.failure)
                return
            }
            
            print(paymentMethod.nonce)
            self.handleApplePayResult(paymentMethod, flutterResult: self.completionBlock)
            completion(.success)
        }
    }
}
