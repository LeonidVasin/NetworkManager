//
//  NetworkManager.swift
//  Locals
//
//  Created by Vitaliy Kuzmenko on 01/08/16.
//  Copyright © 2016 Locals. All rights reserved.
//

import ObjectMapper
import Alamofire
import ReachabilitySwift

public enum NetworkManagerError: String {
    case unknown = "UNKNOWN"
    case internetConnection = "INTERNET_CONNECTION"
}

public class NetworkManager: NSObject {
    
    var reachability = Reachability()
    
    var isReachable: Bool { return reachability?.isReachable ?? false }
    
    let logRequest = true
    
    public enum POSTDataType {
        case json, formData, multipart
    }
    
    public var prefferedPostDataType: POSTDataType = .json
    
    public static let sharedInstance = NetworkManager()
    
    public var authHttpHeaderFields: [String: String] = [:]
    
    override init() {
        super.init()
        
        initReachibility()
    }

    @discardableResult public class func simpleRequest<T: MappableModel>(_ url: String, method: HTTPMethod = .get, getParameters: [String: Any?]? = nil, parameters: [String: Any]? = nil, postDataType: POSTDataType? = nil, httpHeaderFields: [String: String]? = nil, httpBody: Data? = nil, uploadProgress: ((Float) -> Void)? = nil, downloadProgress: ((Float) -> Void)? = nil, mapArrayPath: String? = nil, complete: (([T]?, ResponseError?) -> Void)? = nil) -> NetworkRequest? {
        return sharedInstance.request(url, method: method, getParameters: getParameters, parameters: parameters, postDataType: postDataType, httpHeaderFields: httpHeaderFields, httpBody: httpBody, uploadProgress: uploadProgress, downloadProgress: downloadProgress) { respose in
            complete?(respose.mapArray(path: mapArrayPath), respose.error)
        }
    }
    
    @discardableResult public class func simpleRequest<T: MappableModel>(_ url: String, method: HTTPMethod = .get, getParameters: [String: Any?]? = nil, parameters: [String: Any]? = nil, postDataType: POSTDataType? = nil, httpHeaderFields: [String: String]? = nil, httpBody: Data? = nil, uploadProgress: ((Float) -> Void)? = nil, downloadProgress: ((Float) -> Void)? = nil, complete: ((T?, ResponseError?) -> Void)? = nil) -> NetworkRequest? {
        return sharedInstance.request(url, method: method, getParameters: getParameters, parameters: parameters, postDataType: postDataType, httpHeaderFields: httpHeaderFields, httpBody: httpBody, uploadProgress: uploadProgress, downloadProgress: downloadProgress) { respose in
            complete?(respose.map(), respose.error)
        }
    }
    
    @discardableResult public class func simpleRequest(_ url: String, method: HTTPMethod = .get, getParameters: [String: Any?]? = nil, parameters: [String: Any]? = nil, postDataType: POSTDataType? = nil, httpHeaderFields: [String: String]? = nil, httpBody: Data? = nil, uploadProgress: ((Float) -> Void)? = nil, downloadProgress: ((Float) -> Void)? = nil, complete: ((ResponseError?) -> Void)? = nil) -> NetworkRequest? {
        return sharedInstance.request(url, method: method, getParameters: getParameters, parameters: parameters, postDataType: postDataType, httpHeaderFields: httpHeaderFields, httpBody: httpBody, uploadProgress: uploadProgress, downloadProgress: downloadProgress) { respose in
            complete?(respose.error)
        }
    }
    
    @discardableResult public class func request(_ url: String, method: HTTPMethod = .get, getParameters: [String: Any?]? = nil, parameters: [String: Any]? = nil, postDataType: POSTDataType? = nil, httpHeaderFields: [String: String]? = nil, httpBody: Data? = nil, uploadProgress: ((Float) -> Void)? = nil, downloadProgress: ((Float) -> Void)? = nil, complete: ((Response) -> Void)? = nil) -> NetworkRequest? {
        return sharedInstance.request(url, method: method, getParameters: getParameters, parameters: parameters, postDataType: postDataType, httpHeaderFields: httpHeaderFields, httpBody: httpBody, uploadProgress: uploadProgress, downloadProgress: downloadProgress, complete: complete)
    }
    
    /**
     Perform request with error detection
     
     - parameter method:     HTTP Method
     - parameter url:        Request URL
     - parameter parameters: Request Body parameters
     - parameter complete:   completion closure
     */
    func request(_ url: String, method: HTTPMethod = .get, getParameters: [String: Any?]? = nil, parameters: [String: Any]? = nil, postDataType: POSTDataType? = nil, httpHeaderFields: [String: String]? = nil, httpBody: Data? = nil, uploadProgress: ((Float) -> Void)? = nil, downloadProgress: ((Float) -> Void)? = nil, complete: ((Response) -> Void)? = nil) -> NetworkRequest? {
        
        if !isReachable {
            complete?(noInternetConnectionResponse)
            return nil
        }
        
        startTimeForCheckQualityOfInternetConnection()
        
        let request = constructRequestForMethod(
            method,
            url: url,
            getParameters: getParameters,
            parameters: parameters,
            postDataType: postDataType,
            httpHeaderFields: httpHeaderFields,
            httpBody: httpBody
        )
        
        let req: DataRequest
        
        if postDataType == .multipart {
            let uploading = Alamofire.upload(request.httpBody!, with: request)
            uploading.uploadProgress { p in
                uploadProgress?(Float(p.fractionCompleted))
            }
            req = uploading
        } else {
            req = Alamofire.request(request)
        }
        
        req.downloadProgress { (p) in
            downloadProgress?(Float(p.fractionCompleted))
        }
        req.responseJSON { (response) in
            self.stopTimeForCheckQualityOfInternetConnection()
            let resp = self.complete(request, response: response.response, JSON: response.result.value, error: response.result.error)
            complete?(resp)
        }
        
        return NetworkRequest(_request: req)
    }
    
    fileprivate var noInternetConnectionResponse: Response {
        let resp = Response(URLRequest: nil, response: nil)
        resp.error = ResponseError(
            error: NetworkManagerError.internetConnection.rawValue,
            localizedDescription: "No Internet Connection"
        )
        return resp
    }
    
    /**
     Request complete processor
     
     - parameter request:  URLRequest
     - parameter response: NSHTTPURLResponse
     - parameter JSON:     Response object
     - parameter error:    NSError
     - parameter complete: closure
     */
    fileprivate func complete(_ request: URLRequest?, response: HTTPURLResponse?, JSON: Any?, error: Error?) -> Response {
        
        let _response = Response(URLRequest: request, response: response)
        
        if let status = response?.statusCode {
            
            _response.statusCode = status
            
            switch status {
            case 200...226 :
                _response.JSON = JSON
                return _response
            case 400, 404, 500, 401, 403:
                _response.error = self.getError(JSON)
                return _response
            default:
                break
            }
        }
        
        if let _nsError = error {
            _response.error = ResponseError(
                error: _nsError.localizedDescription,
                localizedDescription: _nsError.localizedDescription
            )
        } else if _response.error == nil {
            _response.error = ResponseError(
                error: NetworkManagerError.unknown.rawValue,
                localizedDescription: "Unknown \(response!.statusCode)"
            )
        }
        
        return _response
    }
    
    /**
     Construct URLRequest for perform request
     
     - parameter method:     HTTP Method
     - parameter url:        Request URL
     - parameter parameters: Request Body parameters
     
     - returns: URLRequest object
     */
    fileprivate func constructRequestForMethod(_ method: HTTPMethod, url: String, getParameters: [String: Any?]? = nil, parameters: [String: Any]? = nil, postDataType: POSTDataType? = nil, httpHeaderFields: [String: String]? = nil, httpBody: Data? = nil) -> URLRequest {
        
        var completeURL = url
        
        completeURL = url + "?"
        
        if let getParameters = getParameters {
            let safegetParameters = removeNilValues(dictionary: getParameters)
            let serializer = DictionarySerializer(dict: safegetParameters)
            completeURL += serializer.getParametersInFormEncodedString()
        }
        
        completeURL = completeURL.trimmingCharacters(in: CharacterSet(charactersIn: "&?"))
        
        let url = URL(string: completeURL)!
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        
        if let httpBody = httpBody {
            request.httpBody = httpBody
        } else {
            fill(parameters, withPostDataType: postDataType ?? prefferedPostDataType, toRequest: &request)
        }
        
        buildhttpHeaderFields(
            &request,
            httpHeaderFields: httpHeaderFields
        )
        
        if logRequest {
            log(request)
        }
        
        request.cachePolicy = .reloadIgnoringCacheData
        
        return request
    }
    
    fileprivate func fill(_ parameters: [String: Any]?, withPostDataType postDataType: POSTDataType, toRequest request: inout URLRequest) {
        switch postDataType {
        case .json:
            fillParametersForJSONDataType(parameters, toRequest: &request)
        case .formData:
            fillParametersForFormDataType(parameters, toRequest: &request)
        case .multipart:
            fillParametersForMultipartDataType(parameters, toRequest: &request)
            break
        }
    }
    
    fileprivate func fillParametersForJSONDataType(_ parameters: [String: Any]?, toRequest request: inout URLRequest) {
        guard let parameters = parameters else { return }
        do {
            request.httpBody = try JSONSerialization.data(
                withJSONObject: parameters,
                options: [.prettyPrinted]
            )
        } catch _ {
            request.httpBody = nil
        }
    }
    
    fileprivate func fillParametersForFormDataType(_ parameters: [String: Any]?, toRequest request: inout URLRequest) {
        guard let parameters = parameters else { return }
        let serializer = DictionarySerializer(dict: parameters)
        let string = serializer.getParametersInFormEncodedString()
        request.httpBody = string.data(using: .utf8)
    }
    
    fileprivate func fillParametersForMultipartDataType(_ parameters: [String: Any]?, toRequest request: inout URLRequest) {
        guard let parameters = parameters else { return }
        let multipart = MultipartFormData()
        
        for (key, value) in parameters {
            if let data = value as? Data {
                multipart.append(data, withName: key)
            } else if let string = value as? String, let data = string.data(using: .utf8) {
                multipart.append(data, withName: key)
            }
        }
        do {
            let data = try multipart.encode()
            request.httpBody = data
        } catch _ {
            
        }
    }
    
    fileprivate func log(_ request: URLRequest) {
        print("")
        print("--- NEW REQUEST ---")
        print(" \(request.httpMethod!) \(request.url!) ")
//        print("--- HEADER ---")
//        print(request.allHTTPHeaderFields!)
        if let body = request.httpBody {
            print("--- BODY ---")
            if let string = String(data: body, encoding: .utf8) {
                print(string)
            }
        }
    }
    
    /**
     Build HTTP header fields for mutable url request
     
     - parameter mutableURLRequest: URLRequest
     - parameter httpHeaderFields:  HTTP Header Fields
     - parameter tokenPolicy:       case of NetworkManagerTokenPolicy enum
     */
    fileprivate func buildhttpHeaderFields(_ request: inout URLRequest, httpHeaderFields: [String: String]?) {
        
        if let httpHeaderFields = httpHeaderFields {
            for item in httpHeaderFields {
                request.setValue(item.1, forHTTPHeaderField: item.0)
            }
        }
        
        let lang = NSLocalizedString("lang", comment: "")
        
        request.setValue(lang, forHTTPHeaderField: "Accept-Language")
        
        for (key, value) in authHttpHeaderFields {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        request.timeoutInterval = 30
    }
    
    /**
     Get Error object from server response object
     
     - parameter JSON: server response object
     
     - returns: Error object with NetworkManagerError and localized description
     */
    fileprivate func getError(_ json: Any?) -> ResponseError? {
        
        var error = "", errorDescription = ""
        
        if let json = json as? [String: Any] {
            if let rawError = json["Error"] as? String {
                error = rawError
            } else if let rawErrorCode = json["ErrorCode"] as? String {
                error = rawErrorCode
            }
            
            if let rawErrorDescription = json["ErrorDescription"] as? String {
                errorDescription = rawErrorDescription
            } else if let rawErrorMessage = json["ErrorMessage"] as? String {
                errorDescription = rawErrorMessage
            }
            
        }
        
        return ResponseError(error: error, localizedDescription: errorDescription)
    }
    
    // MARK: - Timer
    
    /// Timer for check quality of internet connection
    fileprivate var timer: Timer?
    
    fileprivate var canStartSimerForCheckQualityOfInternetConnection = true
    
    fileprivate func startTimeForCheckQualityOfInternetConnection() {
        if canStartSimerForCheckQualityOfInternetConnection {
            timer = Timer.scheduledTimer(
                timeInterval: 15,
                target: self,
                selector: #selector(NetworkManager.postPoorInternetConnectionNotification(timer:)),
                userInfo: nil,
                repeats: false
            )
            canStartSimerForCheckQualityOfInternetConnection = false
        }
    }
    
    @objc fileprivate func postPoorInternetConnectionNotification(timer: Timer) {
        //NSNotificationCenter.post(name: kWOSDKNCPoorInternetConnection)
    }
    
    fileprivate func stopTimeForCheckQualityOfInternetConnection() {
        canStartSimerForCheckQualityOfInternetConnection = true
        timer?.invalidate()
        timer = nil
    }
    
    func initReachibility() {
        
        guard let reachability = Reachability() else { return }
        
        reachability.whenReachable = { reachability in
            DispatchQueue.main.sync {
                if reachability.isReachableViaWiFi {
                    print("Reachable via WiFi")
                } else {
                    print("Reachable via Cellular")
                }
            }
        }
        
        reachability.whenUnreachable = { reachability in
            DispatchQueue.main.sync {
                print("Not reachable")
            }
        }
        
        do {
            try reachability.startNotifier()
        } catch {
            print("Unable to start notifier")
        }
    }
    
    public class func setAuthHeader(value: String, key: String) {
        sharedInstance.authHttpHeaderFields[key] = value
    }
    
    public class func clearAuthHeaderFields() {
        sharedInstance.authHttpHeaderFields = [:]
    }
}
