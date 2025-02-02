/*
 Copyright (c) 2015-present, salesforce.com, inc. All rights reserved.
 
 Redistribution and use of this software in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright notice, this list of conditions
 and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of
 conditions and the following disclaimer in the documentation and/or other materials provided
 with the distribution.
 * Neither the name of salesforce.com, inc. nor the names of its contributors may be used to
 endorse or promote products derived from this software without specific prior written
 permission of salesforce.com, inc.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "SFCrypto.h"
#import "SFCrypto+Internal.h"
#import "NSString+SFAdditions.h"
#import "NSData+SFAdditions.h"
#import <SalesforceSDKCommon/NSUserDefaults+SFAdditions.h>
#import <SalesforceSDKCommon/SalesforceSDKCommon-Swift.h>
static NSString * const kKeychainIdentifierPasscode = @"com.salesforce.security.passcode";
static NSString * const kKeychainIdentifierIV = @"com.salesforce.security.IV";

NSString * const kKeychainIdentifierBaseAppId = @"com.salesforce.security.baseappid";
static NSString * const kKeychainIdentifierSimulatorBaseAppId = @"com.salesforce.security.baseappid.sim";

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
@implementation SFCrypto
#pragma clang diagnostic pop

@synthesize status = _status;
@synthesize outputStream = _outputStream;
@synthesize file = _file;
@synthesize dataBuffer = _dataBuffer;
@synthesize mode = _mode;

#pragma mark - Object Lifecycle

- (id)initWithOperation:(SFCryptoOperation)operation key:(NSData *)key iv:(NSData*)iv mode:(SFCryptoMode)mode {
    if (self = [super init]) {
        char keyPtr[kCCKeySizeAES256 + 1];
        bzero(keyPtr, sizeof(keyPtr)); // fill with zeroes (for padding)

        // Fetch key data
        [key getBytes:keyPtr length:sizeof(keyPtr)];
        if (!iv) {
            iv = [self initializationVector];
        }
        CCOperation cryptoOperation = (operation == SFCryptoOperationEncrypt) ? kCCEncrypt : kCCDecrypt;
        CCCryptorStatus cryptStatus = CCCryptorCreate(cryptoOperation, kCCAlgorithmAES128, kCCOptionPKCS7Padding,
                                                      keyPtr, kCCKeySizeAES256,
                                                      [iv bytes],
                                                      &_cryptor);
        if (cryptStatus != kCCSuccess) {
            [SFSDKCoreLogger e:[self class] format:@"cryptor creation failure (%d)", cryptStatus];
            return nil;
        }
        
        _mode = mode;
        if (mode == SFCryptoModeInMemory) {
            _dataBuffer = [[NSMutableData alloc] init];
        }
    }
    return self;
}

- (id)initWithOperation:(SFCryptoOperation)operation key:(NSData *)key mode:(SFCryptoMode)mode{
    return [self initWithOperation:operation key:key iv:nil mode:mode];
}

- (void)setFile:(NSString *)file {
    if (file && file != _file) {
        [self willChangeValueForKey:@"file"];
        _file = [file copy];
        if (_outputStream) {
            [_outputStream close];
        }
        _outputStream = [NSOutputStream outputStreamToFileAtPath:_file append:YES];
        [_outputStream open];
        [self didChangeValueForKey:@"file"];
    }
}

- (void)dealloc {
    if (_outputStream) {
        [_outputStream close];
    }
}

#pragma mark - Implementation

+ (BOOL)hasInitializationVector {
    SFSDKKeychainResult *result = [SFSDKKeychainHelper createIfNotPresentWithService:kKeychainIdentifierIV account:nil];
    return result.success && result.data != nil;
}

- (NSData *)initializationVector {
    SFSDKKeychainResult *result = [SFSDKKeychainHelper createIfNotPresentWithService:kKeychainIdentifierIV account:nil];
    
    if (result.success && result.data) {
        return result.data;
    }
    //item was not found, create it.
    NSMutableData *data = [NSMutableData dataWithLength:kCCBlockSizeAES128];
    NSData *iv = [data randomDataOfLength:kCCBlockSizeAES128];
    result = [SFSDKKeychainHelper writeWithService:kKeychainIdentifierIV data:iv account:nil];
    if (!result.success) {
       [SFSDKCoreLogger e:[SFCrypto self] format:@"Error writing iv to keychain %@", result.error];
    }
    return iv;
    
}

+ (NSData *)secretWithKey:(NSString *)key {
    SFSDKKeychainResult *result = [SFSDKKeychainHelper createIfNotPresentWithService:kKeychainIdentifierPasscode account:nil];
    if (!result.success) {
        [SFSDKCoreLogger e:[SFCrypto self] format:@"Error reading %@ from keychain %@", kKeychainIdentifierPasscode, result.error];
        return nil;
    }
    
    NSString *passcode = [[NSString alloc] initWithData:result.data encoding:NSUTF8StringEncoding];
    
    NSString *baseAppId = [self baseAppIdentifier];
    NSString *strSecret = [baseAppId stringByAppendingString:key];
    if (passcode) {
        strSecret = [strSecret stringByAppendingString:passcode];
    }
    
    NSData *secretData = [strSecret sha256]; 
    return secretData;
}

+ (BOOL)baseAppIdentifierIsConfigured {
    return [[NSUserDefaults msdkUserDefaults] boolForKey:kKeychainIdentifierBaseAppId];
}

+ (void)setBaseAppIdentifierIsConfigured:(BOOL)isConfigured {
    [[NSUserDefaults msdkUserDefaults] setBool:isConfigured forKey:kKeychainIdentifierBaseAppId];
    [[NSUserDefaults msdkUserDefaults] synchronize];
}

static BOOL sBaseAppIdConfiguredThisLaunch = NO;
+ (BOOL)baseAppIdentifierConfiguredThisLaunch {
    return sBaseAppIdConfiguredThisLaunch;
}
+ (void)setBaseAppIdentifierConfiguredThisLaunch:(BOOL)configuredThisLaunch {
    sBaseAppIdConfiguredThisLaunch = configuredThisLaunch;
}

+ (NSString *)baseAppIdentifier {
#if TARGET_IPHONE_SIMULATOR
    return [self simulatorBaseAppIdentifier];
#else
    return [self deviceBaseAppIdentifier];
#endif
}

+ (BOOL)setBaseAppIdentifier:(NSString *)appId {
#if TARGET_IPHONE_SIMULATOR
    return [self setSimulatorBaseAppIdentifier:appId];
#else
    return [self setDeviceBaseAppIdentifier:appId];
#endif
}

+ (NSString *)simulatorBaseAppIdentifier {
    NSString *baseAppId = nil;
    BOOL hasBaseAppId = [self baseAppIdentifierIsConfigured];
    if (!hasBaseAppId) {
        baseAppId = [[NSUUID UUID] UUIDString];
        [self setSimulatorBaseAppIdentifier:baseAppId];
        [self setBaseAppIdentifierIsConfigured:YES];
        [self setBaseAppIdentifierConfiguredThisLaunch:YES];
    } else {
        baseAppId = [[NSUserDefaults standardUserDefaults] objectForKey:kKeychainIdentifierSimulatorBaseAppId];
    }
    return baseAppId;
}

+ (BOOL)setSimulatorBaseAppIdentifier:(NSString *)appId {
    [[NSUserDefaults standardUserDefaults] setObject:appId forKey:kKeychainIdentifierSimulatorBaseAppId];
    return [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSString *)deviceBaseAppIdentifier {
    static NSString *baseAppId = nil;
    
    @synchronized (self) {
        BOOL hasBaseAppId = [self baseAppIdentifierIsConfigured];
        if (!hasBaseAppId) {
            // Value hasn't yet been (successfully) persisted to the keychain.
            [SFSDKCoreLogger i:[self class] format:@"Base app identifier not configured.  Creating a new value."];
            if (baseAppId == nil)
                baseAppId = [[NSUUID UUID] UUIDString];
            BOOL creationSuccess = [self setDeviceBaseAppIdentifier:baseAppId];
            if (!creationSuccess) {
                [SFSDKCoreLogger e:[self class] format:@"Could not persist the base app identifier.  Returning in-memory value."];
            } else {
                [self setBaseAppIdentifierIsConfigured:YES];
                [self setBaseAppIdentifierConfiguredThisLaunch:YES];
            }
        } else {
            SFSDKKeychainResult *result =  [SFSDKKeychainHelper readWithService:kKeychainIdentifierBaseAppId account:nil];
            NSData *keychainAppIdData = result.data;
            NSString *keychainAppId = [[NSString alloc] initWithData:keychainAppIdData encoding:NSUTF8StringEncoding];
            if (result.error || keychainAppIdData == nil || keychainAppId == nil) {
                // Something went wrong either storing or retrieving the value from the keychain.  Try to rewrite the value.
                [SFSDKCoreLogger e:[self class] format:@"App id keychain data missing or corrupted.  Attempting to reset."];
                [self setBaseAppIdentifierIsConfigured:NO];
                [self setBaseAppIdentifierConfiguredThisLaunch:NO];
                if (baseAppId == nil)
                    baseAppId = [[NSUUID UUID] UUIDString];
                BOOL creationSuccess = [self setDeviceBaseAppIdentifier:baseAppId];
                if (!creationSuccess) {
                    [SFSDKCoreLogger e:[self class] format:@"Could not persist the base app identifier.  Returning in-memory value."];
                } else {
                    [self setBaseAppIdentifierIsConfigured:YES];
                    [self setBaseAppIdentifierConfiguredThisLaunch:YES];
                }
            } else {
                // Successfully retrieved the value.  Set the baseAppId accordingly.
                baseAppId = keychainAppId;
            }
        }
        
        return baseAppId;
    }
}

+ (BOOL)setDeviceBaseAppIdentifier:(NSString *)appId {
    static NSUInteger maxRetries = 3;
    
    // Store the app ID value in the keychain.
    NSError *error = nil;
    [SFSDKCoreLogger i:[self class] format:@"Saving the new base app identifier to the keychain."];
    SFSDKKeychainResult *result = [SFSDKKeychainHelper createIfNotPresentWithService:kKeychainIdentifierBaseAppId account:nil];
    NSData *appIdData = result.data;
    NSUInteger currentRetries = 0;
    OSStatus keychainResult = -1;
    while (currentRetries < maxRetries && keychainResult != noErr) {
        result = [SFSDKKeychainHelper writeWithService:kKeychainIdentifierBaseAppId data:appIdData account:nil];
        keychainResult  = result.status;
        if (!result.success) {
            [SFSDKCoreLogger w:[self class] format:@"Could not save the base app identifier to the keychain (result: %@).  Retrying.", [error localizedDescription]];
        }
        currentRetries++;
    }
    if (keychainResult != noErr) {
        [SFSDKCoreLogger e:[self class] format:@"Giving up on saving the base app identifier to the keychain (result: %@).", [error localizedDescription]];
        return NO;
    }
    
    [SFSDKCoreLogger i:[self class] format:@"Successfully created a new base app identifier and stored it in the keychain."];
    return YES;
}

- (void)cryptData:(NSData *)inData {
    if (inData) {
        size_t outLength = CCCryptorGetOutputLength(_cryptor, (size_t)[inData length], TRUE); // TRUE == final, i.e. include pad bytes
        uint8_t *outBuffer = calloc(outLength, sizeof(uint8_t));
        size_t dataOutMoved = 0;
        
        CCCryptorStatus status = CCCryptorUpdate(_cryptor, [inData bytes], (size_t)[inData length], outBuffer, outLength, &dataOutMoved);
        if (status == kCCSuccess) {
            [self appendToBuffer:[NSData dataWithBytesNoCopy:outBuffer length:dataOutMoved freeWhenDone:NO]]; // we free outBuffer explicity below
        } else {
            [SFSDKCoreLogger e:[self class] format:@"cryptor update failure (%d) - no data written", status];
        }
        free(outBuffer); outBuffer = NULL;
    }
}

- (BOOL)finalizeCipher {
    size_t outLength = kCCBlockSizeAES128; // worst case max buffer size for finalization is 1 full block
    uint8_t *outBuffer = calloc(outLength, sizeof(uint8_t));
    size_t dataOutMoved = 0;
    
    CCCryptorStatus status = CCCryptorFinal(_cryptor, outBuffer, outLength, &dataOutMoved);
    if (kCCSuccess == status) {
        [self appendToBuffer:[NSData dataWithBytesNoCopy:outBuffer length:dataOutMoved freeWhenDone:NO]]; // we free outBuffer explicity below
    } else {
        [SFSDKCoreLogger e:[self class] format:@"cryptor finalization failure (%d) - final data not written", status];
    }
    
    free(outBuffer); outBuffer = NULL;
    CCCryptorRelease(_cryptor); _cryptor = NULL;
    [self.outputStream close];
    return (kCCSuccess == status);
}


- (void)appendToBuffer:(NSData *)data {
    if (![data length]) return;
    
    if (SFCryptoModeInMemory == self.mode) {
        [self.dataBuffer appendData:data];
    } else { // CHCryptoModeDisk
        NSInteger result = [self.outputStream write:[data bytes] maxLength:[data length]];
        if (!result) {
            [SFSDKCoreLogger e:[self class] format:@"failed to write crypted data to output stream (%d)", result];
        }
    }
}

- (NSData *)decryptDataInMemory:(NSData *)data {
    NSData *decryptedData = nil;
    if (data) {
        [self cryptData:data];
        [self finalizeCipher];
        decryptedData = [NSData dataWithData:self.dataBuffer];
    }
    return decryptedData;
}

- (NSData *)encryptDataInMemory:(NSData *)data {
    NSData *encryptedData = nil;
    if (data) {
        [self cryptData:data];
        [self finalizeCipher];
        encryptedData = [NSData dataWithData:self.dataBuffer];
    }
    return encryptedData;
}

-(BOOL) decrypt:(NSString *)inputFile to:(NSString *)outputFile {
    FILE *source = fopen([inputFile UTF8String], "rb");
    if (!source) {
        [SFSDKCoreLogger e:[self class] format:@"failed to read input file"];
        return NO;
    }
    
    FILE *destination = fopen([outputFile UTF8String], "wb");
    if (!destination) {
        [SFSDKCoreLogger e:[self class] format:@"failed to write output file"];
        fclose(source);
        return NO;
    }
    
    const size_t bufferSize = 256*1024; // block size to read
    unsigned char buffer[bufferSize];
    const size_t decryptBufferSize = bufferSize + 16;
    uint8_t *outBuffer = calloc(decryptBufferSize, sizeof(uint8_t));
    size_t bytesToWrite = 0;
    size_t outLength;
    CCCryptorStatus status = -1;
    
    size_t bytesRead;
    while ((bytesRead = fread(buffer, 1, bufferSize, source)) > 0) {
        outLength = CCCryptorGetOutputLength(_cryptor, bytesRead, TRUE); // TRUE == final, i.e. include pad bytes
        status = CCCryptorUpdate(_cryptor, buffer, bytesRead, outBuffer, outLength, &bytesToWrite);
        if (status == kCCSuccess) {
            fwrite(outBuffer, 1, bytesToWrite, destination);
        } else {
            [SFSDKCoreLogger e:[self class] format:@"decrypt failure (%d) - no data written", status];
            break;
        }
        memset(outBuffer, 0, decryptBufferSize);
    }
    
    if (status == kCCSuccess) {
        outLength = kCCBlockSizeAES128; // worst case max buffer size for finalization is 1 full block
        bytesToWrite = 0;
        memset(outBuffer, 0, decryptBufferSize);
    
        CCCryptorStatus status = CCCryptorFinal(_cryptor, outBuffer, outLength, &bytesToWrite);
        if (kCCSuccess == status) {
            fwrite(outBuffer, 1, bytesToWrite, destination);
        } else {
            [SFSDKCoreLogger e:[self class] format:@"decrypt finalization failure (%d) - final data not written", status];
        }
    }
    
    free(outBuffer);
    outBuffer = NULL;
    CCCryptorRelease(_cryptor);
    _cryptor = NULL;

    fclose(source);
    fclose(destination);

    return (kCCSuccess == status);
}

@end
