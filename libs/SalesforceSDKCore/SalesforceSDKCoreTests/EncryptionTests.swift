//
//  EncryptionTests.swift
//  SalesforceSDKCore
//
//  Created by Brianna Birman on 2/9/21.
//  Copyright (c) 2021-present, salesforce.com, inc. All rights reserved.
// 
//  Redistribution and use of this software in source and binary forms, with or without modification,
//  are permitted provided that the following conditions are met:
//  * Redistributions of source code must retain the above copyright notice, this list of conditions
//  and the following disclaimer.
//  * Redistributions in binary form must reproduce the above copyright notice, this list of
//  conditions and the following disclaimer in the documentation and/or other materials provided
//  with the distribution.
//  * Neither the name of salesforce.com, inc. nor the names of its contributors may be used to
//  endorse or promote products derived from this software without specific prior written
//  permission of salesforce.com, inc.
// 
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
//  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
//  FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
//  CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
//  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
//  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
//  WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import XCTest
@testable import SalesforceSDKCore
import CryptoKit

class EncryptionTests: XCTestCase {

    override func setUpWithError() throws {
        _ = KeychainHelper.removeAll()
    }
    
    func testEncryptDecrypt() throws {
        let key = try KeyGenerator.encryptionKey(for: "test1")
        XCTAssertNotNil(key)
        let sensitiveInfo = "My sensitive info"
        let sensitiveData = try XCTUnwrap(sensitiveInfo.data(using: .utf8))
        let encryptedData = try Encryptor.encrypt(data: sensitiveData, using: key)
        XCTAssertNotEqual(sensitiveData, encryptedData)
        
        let keyAgain = try KeyGenerator.encryptionKey(for: "test1")
        XCTAssertEqual(key, keyAgain)
        
        let decryptedData = try Encryptor.decrypt(data: encryptedData, using: keyAgain)
        let decryptedString = String(data: decryptedData, encoding: .utf8)
        
        XCTAssertEqual(decryptedString, sensitiveInfo)
    }
    
    func testEncryptDecryptWrongKey() throws {
        let key = try KeyGenerator.encryptionKey(for: "test1")
        XCTAssertNotNil(key)
        let sensitiveInfo = "My sensitive info"
        let sensitiveData = try XCTUnwrap(sensitiveInfo.data(using: .utf8))
        let encryptedData = try Encryptor.encrypt(data: sensitiveData, using: key)
        XCTAssertNotEqual(sensitiveData, encryptedData)
        
        let differentKey = try KeyGenerator.encryptionKey(for: "test2")
        XCTAssertNotEqual(key, differentKey)
        
        XCTAssertThrowsError(try Encryptor.decrypt(data: encryptedData, using: differentKey))
    }
    
    func testKeyRetrieval() throws {
        let key = try KeyGenerator.encryptionKey(for: "test1")
        XCTAssertNotNil(key)
        let keyAgain = try KeyGenerator.encryptionKey(for: "test1")
        XCTAssertEqual(key, keyAgain)
        
        let differentKey = try KeyGenerator.encryptionKey(for: "test2")
        XCTAssertNotNil(differentKey)
        XCTAssertNotEqual(key, differentKey)
    }
    
    func testConcurrency() throws {
        let result = SafeMutableArray()
        DispatchQueue.concurrentPerform(iterations: 1000) { index in
            if let symmetricKey = try? KeyGenerator.encryptionKey(for: "singleLabel") {
                result.add(symmetricKey.dataRepresentation as NSData)
            }
        }
        
        XCTAssertEqual(1000, result.count)
        let firstItem = try XCTUnwrap(result.object(atIndexed: 0) as? NSData)
        XCTAssertTrue(result.asArray().allSatisfy { item in
            return item as? NSData == firstItem
        })
    }
}
