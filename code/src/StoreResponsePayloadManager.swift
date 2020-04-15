//
// ADOBE CONFIDENTIAL
//
// Copyright 2020 Adobe
// All Rights Reserved.
//
// NOTICE: All information contained herein is, and remains
// the property of Adobe and its suppliers, if any. The intellectual
// and technical concepts contained herein are proprietary to Adobe
// and its suppliers and are protected by all applicable intellectual
// property laws, including trade secret and copyright laws.
// Dissemination of this information or reproduction of this material
// is strictly forbidden unless prior written permission is obtained
// from Adobe.
//


import Foundation
import ACPCore

class StoreResponsePayloadManager {
    private let TAG: String = "StoreResponsePayloadManager"
    private let dataStore: KeyValueStore
    private let keyName: String = ExperiencePlatformConstants.DataStoreKeys.storePayloads
    
    init(_ store: KeyValueStore) {
        dataStore = store
    }
    
    /// Reads all the active saved store payloads from the data store.
    /// Any store payload that has expired is not included and is evicted from the data store.
    /// - Returns: a map of `StoreResponsePayload` objects keyed by `StoreResponsePayload.key`
    func getActiveStores() -> [String : StoreResponsePayload] {
        
        guard let serializedPayloads = dataStore.getDictionary(key: keyName, fallback: nil) else {
            ACPCore.log(ACPMobileLogLevel.debug, tag: TAG, message: "No active payloads were found in the data store.")
            return [:]
        }
        
        // list of expired payloads to be deleted
        var expiredList: [String] = []
        
        // list of valid decoded payloads
        var payloads: [String : StoreResponsePayload] = [:]
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        for (_, codedPayload) in serializedPayloads {
            
            guard let data = codedPayload.data(using: .utf8) else {
                ACPCore.log(ACPMobileLogLevel.warning, tag: TAG, message: "Failed to convert store response payload string to data.")
                continue
            }
            
            let payload: StoreResponsePayload
            do {
                payload = try decoder.decode(StoreResponsePayload.self, from: data)
                if payload.isExpired {
                    expiredList.append(payload.key)
                } else {
                    payloads[payload.key] = payload
                }
            } catch {
                ACPCore.log(ACPMobileLogLevel.warning, tag: TAG, message: "Failed to decode store response payload with: \(error.localizedDescription)")
            }
        }
        
        deleteStoredResponses(keys: expiredList)
        return payloads
    }
    
    /// Saves a list of `StoreResponsePayload` objects to the data store. Payloads with `maxAge <= 0` are deleted.
    /// - Parameter payloads: a list of `StoreResponsePayload` to be saved to the data store
    func saveStorePayloads(_ payloads: [StoreResponsePayload]) {
        if payloads.isEmpty {
            return
        }
        
        guard var serializedPayloads = dataStore.getDictionary(key: keyName, fallback: [:]) else {
            return
        }
        
        // list of expired payloads to be deleted
        var expiredList: [String] = []
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        for payload in payloads {
            // The Experience Edge server (Konductor) defines state values with 0 or -1 max age as to be deleted on the client.
            if (payload.payload.maxAge <= 0) {
                expiredList.append(payload.key)
                continue
            }
            
            do {
                let payloadData = try encoder.encode(payload)
                guard let serializedPayload = String(data: payloadData, encoding: .utf8) else {
                    continue
                }
                
                serializedPayloads[payload.key] = serializedPayload
            } catch {
                ACPCore.log(ACPMobileLogLevel.debug, tag: TAG, message: "Failed to encode store response payload: \(error.localizedDescription)")
                continue
            }
        }
        
        dataStore.setDictionary(key: keyName, value: serializedPayloads)
        deleteStoredResponses(keys: expiredList)
        
    }
    
    /// Deletes a list of stores from the data store
    /// - Parameter keys: a list of `StoreResponsePayload.key`
    private func deleteStoredResponses(keys: [String]) {
        guard var codedPayloads = dataStore.getDictionary(key: keyName, fallback: nil) else {
            return
        }
        
        for key in keys {
            codedPayloads.removeValue(forKey: key)
        }
        
        dataStore.setDictionary(key: keyName, value: codedPayloads)
    }
}
