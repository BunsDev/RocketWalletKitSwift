//
//  BRCryptoWalletManager.swift
//  WalletKit
//
//  Created by Ed Gamble on 3/27/19.
//  Copyright © 2019 Breadwallet AG. All rights reserved.
//
//  See the LICENSE file at the project root for license information.
//  See the CONTRIBUTORS file at the project root for a list of contributors.
//
import Foundation // Data
import WalletKitCore

///
/// A WallettManager manages one or more wallets one of which is designated the `primaryWallet`.
/// (For example, an EthereumWalletManager will manage an ETH wallet and one wallet for each
/// ERC20Token; the ETH wallet will be the primaryWallet.  A BitcoinWalletManager manages one
/// and only one wallet holding BTC.).
///
/// At least conceptually, a WalletManager is an 'Active Object' (whereas Transfer and Wallet are
/// 'Passive Objects'
///
public final class WalletManager: Equatable, CustomStringConvertible {

    /// The Core representation
    internal private(set) var core: BRCryptoWalletManager! = nil

    internal let callbackCoordinator: SystemCallbackCoordinator

    /// The owning system
    public unowned let system: System

    /// The account
    public let account: Account

    /// The network
    public let network: Network

    /// The client
    internal let client: SystemClient

    /// The default unit - as the networks default unit
    internal let unit: Unit

    /// The mode determines how the manager manages the account and wallets on network
    public var mode: WalletManagerMode {
        get { return WalletManagerMode (core: cryptoWalletManagerGetMode (core)) }
        set {
            assert (network.supportsMode(newValue))
            cryptoWalletManagerSetMode (core, newValue.core)
        }
    }

    /// The file-system path to use for persistent storage.
    public let path: String

    /// The current state
    public var state: WalletManagerState {
        return WalletManagerState (core: cryptoWalletManagerGetState (core))
    }

    /// The current network block height
    internal var height: UInt64 {
        return network.height
    }

    /// The primaryWallet - holds the network's currency - this is typically the wallet where
    /// fees are applied which may or may not differ from the specific wallet used for a
    /// transfer (like BRD transfer => ETH fee)
    public lazy var primaryWallet: Wallet = {
        // Find a preexisting wallet (unlikely) or create one.
        let coreWallet = cryptoWalletManagerGetWallet(core)!
        return Wallet (core: coreWallet,
                       manager: self,
                       callbackCoordinator: callbackCoordinator,
                       take: false)
    }()

    ///
    /// Ensure that a wallet for currency exists.  If the wallet already exists, it is returned.
    /// If the wallet needs to be created then `nil` is returned and a series of events will
    /// occur - notably WalletEvent.created and WalletManagerEvent.walletAdded if the wallet is
    /// created
    ///
    /// - Note: There is a precondition on `currency` being one in the managers' network
    ///
    /// - Parameter currency:
    /// - Returns: The wallet for currency if it already exists, othersise `nil`
    ///
    public func registerWalletFor (currency: Currency) -> Wallet? {
        precondition (network.hasCurrency(currency))
        return cryptoWalletManagerCreateWallet (core, currency.core)
            .map { Wallet (core: $0,
                           manager: self,
                           callbackCoordinator: callbackCoordinator,
                           take: false)
        }
    }

    //    public func unregisterWalletFor (currency: Currency) {
    //        wallets
    //            .first { $0.currency == currency }
    //            .map { unregisterWallet($0) }
    //    }
    //
    //    public func unregisterWallet (_ wallet: Wallet) {
    //    }

    /// The managed wallets - often will just be [primaryWallet]
    public var wallets: [Wallet] {
        let _ = system.listener

        var walletsCount: size_t = 0
        let walletsPtr = cryptoWalletManagerGetWallets(core, &walletsCount);
        defer { if let ptr = walletsPtr { free (ptr) } }

        let wallets: [BRCryptoWallet] = walletsPtr?.withMemoryRebound(to: BRCryptoWallet.self, capacity: walletsCount) {
            Array(UnsafeBufferPointer (start: $0, count: walletsCount))
            } ?? []

        return wallets
            .map { Wallet (core: $0,
                           manager: self,
                           callbackCoordinator: callbackCoordinator,
                           take: false) }
    }

    ///
    /// Find a wallet by `impl`
    ///
    /// - Parameter impl: the impl
    /// - Returns: The wallet, if found
    ///
    internal func walletBy (core: BRCryptoWallet) -> Wallet? {
        return (CRYPTO_FALSE == cryptoWalletManagerHasWallet (self.core, core)
            ? nil
            : Wallet (core: core,
                      manager: self,
                      callbackCoordinator: callbackCoordinator,
                      take: true))
    }

    internal func walletByCoreOrCreate (_ core: BRCryptoWallet,
                                        create: Bool = false) -> Wallet? {
        return walletBy (core: core) ??
            (!create
                ? nil
                : Wallet (core: core,
                          manager: self,
                          callbackCoordinator: callbackCoordinator,
                          take: true))
    }

    /// The default network fee.
    public var defaultNetworkFee: NetworkFee

    /// The address scheme to use
    public var addressScheme: AddressScheme {
        get { return AddressScheme (core: cryptoWalletManagerGetAddressScheme (core)) }
        set {
            assert (network.supportsAddressScheme(newValue))
            cryptoWalletManagerSetAddressScheme (core, newValue.core)
        }
    }

    ///
    /// Connect to the network and begin managing wallets.
    ///
    /// - Parameter peer: An optional NetworkPeer to use on the P2P network.  It is unusual to
    ///     provide a peer as P2P networks will dynamically discover suitable peers.
    ///
    /// - Note: If peer is provided, there is a precondition on the networks matching.
    ///
    public func connect (using peer: NetworkPeer? = nil) {
        precondition (peer == nil || peer!.network == network)
        cryptoWalletManagerConnect (core, peer?.core)
    }

    /// Disconnect from the network.
    public func disconnect () {
        cryptoWalletManagerDisconnect (core)
    }

    internal func stop () {
        cryptoWalletManagerStop (core);
    }
    
    public func sync () {
        cryptoWalletManagerSync (core)
    }

    public func syncToDepth (depth: WalletManagerSyncDepth) {
        cryptoWalletManagerSyncToDepth (core, depth.core)
    }

    internal func sign (transfer: Transfer, paperKey: String) -> Bool {
        return CRYPTO_TRUE == cryptoWalletManagerSign (core,
                                                       transfer.wallet.core,
                                                       transfer.core,
                                                       paperKey)
    }

    public func submit (transfer: Transfer, paperKey: String) {
        cryptoWalletManagerSubmit (core,
                                   transfer.wallet.core,
                                   transfer.core,
                                   paperKey)
    }

    internal func submit (transfer: Transfer, key: Key) {
        cryptoWalletManagerSubmitForKey(core,
                                        transfer.wallet.core,
                                        transfer.core,
                                        key.core)
    }

    internal func submit (transfer: Transfer) {
        cryptoWalletManagerSubmitSigned (core,
                                         transfer.wallet.core,
                                         transfer.core)
    }

    internal func setNetworkReachable (_ isNetworkReachable: Bool) {
        cryptoWalletManagerSetNetworkReachable (core,
                                                isNetworkReachable ? CRYPTO_TRUE : CRYPTO_FALSE)
    }

    public func createSweeper (wallet: Wallet,
                               key: Key,
                               completion: @escaping (Result<WalletSweeper, WalletSweeperError>) -> Void) {
        WalletSweeper.create(wallet: wallet, key: key, client: client, completion: completion)
    }
    
    public func createExportablePaperWallet () -> Result<ExportablePaperWallet, ExportablePaperWalletError> {
        return ExportablePaperWallet.create(manager: self)
    }

    internal init (core: BRCryptoWalletManager,
                   system: System,
                   callbackCoordinator: SystemCallbackCoordinator,
                   take: Bool) {

        self.core   = take ? cryptoWalletManagerTake(core) : core
        self.system = system
        self.callbackCoordinator = callbackCoordinator

        self.account = Account (core: cryptoWalletManagerGetAccount(core), take: false)
        self.network = Network (core: cryptoWalletManagerGetNetwork (core), take: false)
        self.unit    = self.network.defaultUnitFor (currency: self.network.currency)!
        self.path    = asUTF8String (cryptoWalletManagerGetPath(core))
        self.client  = system.client

        self.defaultNetworkFee = self.network.minimumFee
    }

    deinit {
        cryptoWalletManagerGive (core)
    }

    // Equatable
    public static func == (lhs: WalletManager, rhs: WalletManager) -> Bool {
        return lhs === rhs || lhs.core == rhs.core
    }

    public var description: String {
        return name
    }
}

extension WalletManager {
    ///
    /// Create a wallet for `currency`.  Invokdes the manager's `walletFactory` to create the
    /// wallet.  Generates events: Wallet.created, WalletManager.walletAdded(wallet), perhaps
    /// others.
    ///
    /// - Parameter currency: the wallet's currency
    ///
    /// - Returns: a new wallet.
    ///
    //    func createWallet (currency: Currency) -> Wallet {
    //        return walletFactory.createWallet (manager: self,
    //                                           currency: currency)
    //    }

    /// The network's/primaryWallet's currency.  This is the currency used for transfer fees.
    var currency: Currency {
        return network.currency // don't reference `primaryWallet`; infinitely recurses
    }

    /// The name is simply the network currency's code - e.g. BTC, ETH
    public var name: String {
        return currency.code
    }

    /// The baseUnit for the network's currency.
    var baseUnit: Unit {
        return network.baseUnitFor(currency: network.currency)!
    }

    /// The defaultUnit for the network's currency.
    var defaultUnit: Unit {
        return network.defaultUnitFor(currency: network.currency)!
    }

    /// A manager `isActive` if connected or syncing
    var isActive: Bool {
        return state == .connected || state == .syncing
    }
}

///
/// The WalletSweeper
///
public enum WalletSweeperError: Error {
    case unsupportedCurrency
    case invalidKey
    case invalidSourceWallet
    case insufficientFunds
    case unableToSweep
    case noTransfersFound
    case unexpectedError
    case clientError(SystemClientError)

    internal init? (_ core: BRCryptoWalletSweeperStatus) {
        switch core {
        case CRYPTO_WALLET_SWEEPER_SUCCESS:                 return nil
        case CRYPTO_WALLET_SWEEPER_UNSUPPORTED_CURRENCY:    self = .unsupportedCurrency
        case CRYPTO_WALLET_SWEEPER_INVALID_KEY:             self = .invalidKey
        case CRYPTO_WALLET_SWEEPER_INVALID_SOURCE_WALLET:   self = .invalidSourceWallet
        case CRYPTO_WALLET_SWEEPER_INSUFFICIENT_FUNDS:      self = .insufficientFunds
        case CRYPTO_WALLET_SWEEPER_UNABLE_TO_SWEEP:         self = .unableToSweep
        case CRYPTO_WALLET_SWEEPER_NO_TRANSFERS_FOUND:      self = .noTransfersFound
        case CRYPTO_WALLET_SWEEPER_INVALID_ARGUMENTS:       self = .unexpectedError
        case CRYPTO_WALLET_SWEEPER_INVALID_TRANSACTION:     self = .unexpectedError
        case CRYPTO_WALLET_SWEEPER_ILLEGAL_OPERATION:       self = .unexpectedError
        default: self = .unexpectedError; preconditionFailure()
        }
    }
}

public final class WalletSweeper {

    internal static func create(wallet: Wallet,
                                key: Key,
                                client: SystemClient,
                                completion: @escaping (Result<WalletSweeper, WalletSweeperError>) -> Void) {
        // check that requested combination of manager, wallet, key can be used for sweeping
        if let e = WalletSweeperError(cryptoWalletManagerWalletSweeperValidateSupported(wallet.manager.core,
                                                                                        wallet.core,
                                                                                        key.core)) {
            completion(Result.failure(e))
            return
        }

        switch cryptoNetworkGetType (wallet.manager.network.core) {
        case CRYPTO_NETWORK_TYPE_BTC, CRYPTO_NETWORK_TYPE_BCH, CRYPTO_NETWORK_TYPE_BSV:
            // handle as BTC, creating the underlying BRCryptoWalletSweeper and initializing it
            // using the BlockchainDB
            createAsBtc(wallet: wallet,
                        key: key)
                .initAsBTC(client: client,
                           completion: completion)
        default:
            preconditionFailure()
        }
    }

    private static func createAsBtc(wallet: Wallet,
                                    key: Key) -> WalletSweeper {
        return WalletSweeper(core: cryptoWalletManagerCreateWalletSweeper(wallet.manager.core,
                                                                          wallet.core,
                                                                          key.core),
                             wallet: wallet,
                             key: key)
    }

    internal let core: BRCryptoWalletSweeper
    private let manager: WalletManager
    private let wallet: Wallet
    private let key: Key

    private init (core: BRCryptoWalletSweeper,
                  wallet: Wallet,
                  key: Key) {
        self.core = core
        self.manager = wallet.manager
        self.wallet = wallet
        self.key = key
    }

    public var balance: Amount? {
        return cryptoWalletSweeperGetBalance (self.core)
            .map { Amount (core: $0, take: false) }
    }

    public func estimate(fee: NetworkFee,
                         completion: @escaping (Result<TransferFeeBasis, Wallet.FeeEstimationError>) -> Void) {
        wallet.estimateFee(sweeper: self, fee: fee, completion: completion)
    }

    public func submit(estimatedFeeBasis: TransferFeeBasis) -> Transfer? {
        guard let transfer = wallet.createTransfer(sweeper: self, estimatedFeeBasis: estimatedFeeBasis)
            else { return nil }

        manager.submit(transfer: transfer, key: key)
        return transfer
    }

    private func initAsBTC(client: SystemClient,
                           completion: @escaping (Result<WalletSweeper, WalletSweeperError>) -> Void) {
        let network = manager.network
        let address = Address (core: cryptoWalletSweeperGetAddress(core)!).description

        client.getTransactions(blockchainId: network.uids,
                               addresses: [address],
                               begBlockNumber: 0,
                               endBlockNumber: network.height,
                               includeRaw: true,
                               includeTransfers: false) {
                                (res: Result<[SystemClient.Transaction], SystemClientError>) in
                                res.resolve(
                                    success: {
//                                        let bundles: [BRCryptoClientTransactionBundle?] = $0.map { System.makeTransactionBundle ($0) }
//                                        // populate the underlying BRCryptoWalletSweeper with BTC transaction data
//                                        for bundle in bundles {
//                                            if let e = WalletSweeperError(cryptoWalletSweeperAddTransactionFromBundle(self.core, bundle)) {
//                                                completion(Result.failure(e))
//                                                return
//                                            }
//                                        }
//
//                                        // validate that the sweeper has the necessary info
//                                        if let e = WalletSweeperError(cryptoWalletSweeperValidate(self.core)) {
//                                            completion(Result.failure(e))
//                                            return
//                                        }
                                        completion(Result.failure(.clientError($0))
                                        
                                        // return the sweeper for use in estimation/submission
                                        completion(Result.success(self))},
                                    failure: { completion(Result.failure(.clientError($0))) })
        }
    }

    deinit {
        cryptoWalletSweeperRelease(core)
    }
}

///
/// Exportable Paper Wallet
///

public enum ExportablePaperWalletError: Error {
    case unsupportedCurrency
    case unexpectedError

    internal init? (_ core: BRCryptoExportablePaperWalletStatus) {
        switch core {
        case CRYPTO_EXPORTABLE_PAPER_WALLET_SUCCESS:                 return nil
        case CRYPTO_EXPORTABLE_PAPER_WALLET_UNSUPPORTED_CURRENCY:    self = .unsupportedCurrency
        case CRYPTO_EXPORTABLE_PAPER_WALLET_INVALID_ARGUMENTS:       self = .unexpectedError
        default: self = .unexpectedError; preconditionFailure()
        }
    }
}

public final class ExportablePaperWallet {
    internal static func create(manager: WalletManager) -> Result<ExportablePaperWallet, ExportablePaperWalletError> {
        // check that requested wallet supports generating exportable paper wallets
        if let error =  ExportablePaperWalletError (cryptoExportablePaperWalletValidateSupported (manager.network.core,
                                                                                                  manager.currency.core)) {
            return Result.failure (error)
        }

        return cryptoExportablePaperWalletCreate (manager.network.core, manager.currency.core)
            .map { Result.success (ExportablePaperWallet (core: $0)) }
            ?? Result.failure(.unexpectedError)
    }

    internal let core: BRCryptoWalletSweeper

    private init (core: BRCryptoWalletSweeper) {
        self.core = core
    }

    public var privateKey: Key? {
        return cryptoExportablePaperWalletGetKey (self.core)
            .map { Key (core: $0) }
    }

    public var address: Address? {
        return cryptoExportablePaperWalletGetAddress (self.core)
            .map { Address (core: $0, take: false) }
    }

    deinit {
        cryptoExportablePaperWalletRelease(core)
    }
}

public enum WalletManagerDisconnectReason: Equatable {
    case requested
    case unknown
    case posix(errno: Int32, message: String?)

    internal init (core: BRCryptoWalletManagerDisconnectReason) {
        switch core.type {
        case CRYPTO_WALLET_MANAGER_DISCONNECT_REASON_REQUESTED:
            self = .requested
        case CRYPTO_WALLET_MANAGER_DISCONNECT_REASON_UNKNOWN:
            self = .unknown
        case CRYPTO_WALLET_MANAGER_DISCONNECT_REASON_POSIX:
            var c = core
            self = .posix(errno: core.u.posix.errnum,
                          message: cryptoWalletManagerDisconnectReasonGetMessage(&c).map{ asUTF8String($0, true) })
        default: self = .unknown; preconditionFailure()
        }
    }
}

///
/// The WalletManager state.
///
public enum WalletManagerState: Equatable {
    case created
    case disconnected(reason: WalletManagerDisconnectReason)
    case connected
    case syncing
    case deleted

    internal init (core: BRCryptoWalletManagerState) {
        switch core.type {
        case CRYPTO_WALLET_MANAGER_STATE_CREATED:      self = .created
        case CRYPTO_WALLET_MANAGER_STATE_DISCONNECTED: self = .disconnected(reason: WalletManagerDisconnectReason(core: core.u.disconnected.reason))
        case CRYPTO_WALLET_MANAGER_STATE_CONNECTED:    self = .connected
        case CRYPTO_WALLET_MANAGER_STATE_SYNCING:      self = .syncing
        case CRYPTO_WALLET_MANAGER_STATE_DELETED:      self = .deleted
        default: self = .created; preconditionFailure()
        }
    }
}

///
/// The WalletManager's mode determines how the account and associated wallets are managed.
///
/// - api_only: Use only the defined 'Cloud-Based API' to synchronize the account's transfers.
///
/// - api_with_p2p_submit: Use the defined 'Cloud-Based API' to synchronize the account's transfers
///      but submit transfers using the network's Peer-to-Peer protocol.
///
/// - p2p_with_api_sync: Use the network's Peer-to-Peer protocol to synchronize the account's
///      recents transfers but use the 'Cloud-Based API' to synchronize older transfers.
///
/// - p2p_only: Use the network's Peer-to-Peer protocol to synchronize the account's transfers.
///
public enum WalletManagerMode: Equatable {
    case api_only
    case api_with_p2p_submit
    case p2p_with_api_sync
    case p2p_only

    /// Allow WalletMangerMode to be saved
    public var serialization: UInt8 {
        switch self {
        case .api_only:            return 0xf0
        case .api_with_p2p_submit: return 0xf1
        case .p2p_with_api_sync:   return 0xf2
        case .p2p_only:            return 0xf3
        }
    }

    /// Initialize WalletMangerMode from serialization
    public init? (serialization: UInt8) {
        switch serialization {
        case 0xf0: self = .api_only
        case 0xf1: self = .api_with_p2p_submit
        case 0xf2: self = .p2p_with_api_sync
        case 0xf3: self = .p2p_only
        default: return nil
        }
    }

    internal init (core: BRCryptoSyncMode) {
        switch core {
        case CRYPTO_SYNC_MODE_API_ONLY: self = .api_only
        case CRYPTO_SYNC_MODE_API_WITH_P2P_SEND: self = .api_with_p2p_submit
        case CRYPTO_SYNC_MODE_P2P_WITH_API_SYNC: self = .p2p_with_api_sync
        case CRYPTO_SYNC_MODE_P2P_ONLY: self = .p2p_only
        default: self = .api_only; preconditionFailure()
        }
    }

    internal var core: BRCryptoSyncMode {
        switch self {
        case .api_only: return CRYPTO_SYNC_MODE_API_ONLY
        case .api_with_p2p_submit: return CRYPTO_SYNC_MODE_API_WITH_P2P_SEND
        case .p2p_with_api_sync: return CRYPTO_SYNC_MODE_P2P_WITH_API_SYNC
        case .p2p_only: return CRYPTO_SYNC_MODE_P2P_ONLY
        }
    }

    public static let all = [WalletManagerMode.api_only,
                             WalletManagerMode.api_with_p2p_submit,
                             WalletManagerMode.p2p_with_api_sync,
                             WalletManagerMode.p2p_only]
    
    // Equatable: [Swift-generated]
}

///
/// The WalletManager's sync depth determines the range that a sync is performed on.
///
/// - fromLastConfirmedSend: Sync from the block height of the last confirmed send transaction.
///
/// - fromLastTrustedBlock: Sync from the block height of the last trusted block; this is
///      dependent on the blockchain and mode as to how it determines trust.
///
/// - fromCreation: Sync from the block height of the point in time when the account was created.
///
public enum WalletManagerSyncDepth: Equatable {
    case fromLastConfirmedSend
    case fromLastTrustedBlock
    case fromCreation

    /// Allow WalletMangerMode to be saved
    public var serialization: UInt8 {
        switch self {
        case .fromLastConfirmedSend: return 0xa0
        case .fromLastTrustedBlock:  return 0xb0
        case .fromCreation:          return 0xc0
        }
    }

    /// Initialize WalletMangerMode from serialization
    public init? (serialization: UInt8) {
        switch serialization {
        case 0xa0: self = .fromLastConfirmedSend
        case 0xb0: self = .fromLastTrustedBlock
        case 0xc0: self = .fromCreation
        default: return nil
        }
    }

    internal init (core: BRCryptoSyncDepth) {
        switch core {
        case CRYPTO_SYNC_DEPTH_FROM_LAST_CONFIRMED_SEND: self = .fromLastConfirmedSend
        case CRYPTO_SYNC_DEPTH_FROM_LAST_TRUSTED_BLOCK: self = .fromLastTrustedBlock
        case CRYPTO_SYNC_DEPTH_FROM_CREATION: self = .fromCreation
        default: self = .fromCreation; preconditionFailure()
        }
    }

    internal var core: BRCryptoSyncDepth {
        switch self {
        case .fromLastConfirmedSend: return CRYPTO_SYNC_DEPTH_FROM_LAST_CONFIRMED_SEND
        case .fromLastTrustedBlock: return CRYPTO_SYNC_DEPTH_FROM_LAST_TRUSTED_BLOCK
        case .fromCreation: return CRYPTO_SYNC_DEPTH_FROM_CREATION
        }
    }

    public var shallower: WalletManagerSyncDepth? {
        switch self {
        case .fromCreation: return .fromLastTrustedBlock
        case .fromLastTrustedBlock: return .fromLastConfirmedSend
        default: return nil
        }
    }

    public var deeper: WalletManagerSyncDepth? {
        switch self {
        case .fromLastConfirmedSend: return .fromLastTrustedBlock
        case .fromLastTrustedBlock: return .fromCreation
        default: return nil
        }
    }

    // Equatable: [Swift-generated]
}

public enum WalletManagerSyncStoppedReason: Equatable {
    case complete
    case requested
    case unknown
    case posix(errno: Int32, message: String?)

    internal init (core: BRCryptoSyncStoppedReason) {
        switch core.type {
        case CRYPTO_SYNC_STOPPED_REASON_COMPLETE:
            self = .complete
        case CRYPTO_SYNC_STOPPED_REASON_REQUESTED:
            self = .requested
        case CRYPTO_SYNC_STOPPED_REASON_UNKNOWN:
            self = .unknown
        case CRYPTO_SYNC_STOPPED_REASON_POSIX:
            var c = core
            self = .posix(errno: core.u.posix.errnum,
                          message: cryptoSyncStoppedReasonGetMessage(&c).map{ asUTF8String($0, true) })
        default: self = .unknown; preconditionFailure()
        }
    }
}

///
/// A WalletManager Event represents a asynchronous announcment of a managera's state change.
///
public enum WalletManagerEvent {
    case created
    case changed (oldState: WalletManagerState, newState: WalletManagerState)
    case deleted

    case walletAdded   (wallet: Wallet)
    case walletChanged (wallet: Wallet)
    case walletDeleted (wallet: Wallet)

    case syncStarted
    case syncProgress (timestamp: Date?, percentComplete: Float)
    case syncEnded (reason: WalletManagerSyncStoppedReason)
    case syncRecommended (depth: WalletManagerSyncDepth)

    /// An event capturing a change in the block height of the network associated with a
    /// WalletManager. Developers should listen for this event when making use of
    /// Transfer::confirmations, as that value is calculated based on the associated network's
    /// block height. Displays or caches of that confirmation count should be updated when this
    /// event occurs.
    case blockUpdated (height: UInt64)

    init (manager: WalletManager, core: BRCryptoWalletManagerEvent) {
        switch core.type {
        case CRYPTO_WALLET_MANAGER_EVENT_CREATED:
            self = .created

        case CRYPTO_WALLET_MANAGER_EVENT_CHANGED:
            self = .changed(oldState: WalletManagerState(core: core.u.state.old),
                            newState: WalletManagerState(core: core.u.state.new))

        case CRYPTO_WALLET_MANAGER_EVENT_DELETED:
            self = .deleted

        case CRYPTO_WALLET_MANAGER_EVENT_WALLET_ADDED:
            self = .walletAdded (wallet: Wallet (core: core.u.wallet,
                                                 manager: manager,
                                                 callbackCoordinator: manager.callbackCoordinator,
                                                 take: false))

        case CRYPTO_WALLET_MANAGER_EVENT_WALLET_CHANGED:
            self = .walletChanged (wallet: Wallet (core: core.u.wallet,
                                                   manager: manager,
                                                   callbackCoordinator: manager.callbackCoordinator,
                                                   take: false))

        case CRYPTO_WALLET_MANAGER_EVENT_WALLET_DELETED:
            self = .walletDeleted (wallet: Wallet (core: core.u.wallet,
                                                   manager: manager,
                                                   callbackCoordinator: manager.callbackCoordinator,
                                                   take: false))

        // wallet: added: ...
        case CRYPTO_WALLET_MANAGER_EVENT_SYNC_STARTED:
            self = .syncStarted
            
        case CRYPTO_WALLET_MANAGER_EVENT_SYNC_CONTINUES:
            let timestamp: Date? = (0 == core.u.syncContinues.timestamp // NO_CRYPTO_TIMESTAMP
                ? nil
                : Date (timeIntervalSince1970: TimeInterval(core.u.syncContinues.timestamp)))

            self = .syncProgress (timestamp: timestamp,
                                  percentComplete: core.u.syncContinues.percentComplete)

        case CRYPTO_WALLET_MANAGER_EVENT_SYNC_STOPPED:
            let reason = WalletManagerSyncStoppedReason(core: core.u.syncStopped.reason)
            self = .syncEnded(reason: reason)

        case CRYPTO_WALLET_MANAGER_EVENT_SYNC_RECOMMENDED:
            let depth = WalletManagerSyncDepth(core: core.u.syncRecommended.depth)
            self = .syncRecommended(depth: depth)

        case CRYPTO_WALLET_MANAGER_EVENT_BLOCK_HEIGHT_UPDATED:
            self = .blockUpdated(height: core.u.blockHeight)

        default:
            preconditionFailure()

        }
    }
}

///
/// Listener For WalletManagerEvent
///
public protocol WalletManagerListener: AnyObject {
    ///
    /// Handle a WalletManagerEvent.
    ///
    /// - Parameters:
    ///   - system: the system
    ///   - manager: the manager
    ///   - event: the event
    ///
    func handleManagerEvent (system: System,
                             manager: WalletManager,
                             event: WalletManagerEvent)
}

/// A Functional Interface for a Handler
public typealias WalletManagerEventHandler = (System, WalletManager, WalletManagerEvent) -> Void

public protocol WalletManagerFactory { }
