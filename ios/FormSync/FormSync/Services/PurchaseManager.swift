import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let proProductID = "formsync.pro.lifetime"

    @Published private(set) var products: [Product] = []
    @Published private(set) var entitlementState: EntitlementState
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var hasRecentPurchaseFailure = false
    @Published private(set) var trialState: TrialState
    @Published var statusMessage: String?

    private var updatesTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let trialUsageStore: any TrialUsageStoring

    init(
        defaults: UserDefaults = .standard,
        trialUsageStore: any TrialUsageStoring = TrialUsageStore()
    ) {
        self.defaults = defaults
        self.trialUsageStore = trialUsageStore
        self.entitlementState = defaults.bool(forKey: Self.proCacheKey) ? .pro : .free
        let cachedUsedUses = defaults.integer(forKey: Self.trialUsedUsesCacheKey)
        let storedUsedUses = max(trialUsageStore.loadUsedUses() ?? 0, cachedUsedUses)
        self.trialState = TrialState(
            usedUses: min(max(storedUsedUses, 0), TrialState.totalUses)
        )
        updatesTask = observeTransactionUpdates()

        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    var isProUnlocked: Bool {
        entitlementState == .pro
    }

    var proProduct: Product? {
        products.first { $0.id == Self.proProductID }
    }

    var displayPrice: String {
        proProduct?.displayPrice ?? String(localized: "Loading Price")
    }

    var remainingTrialUses: Int {
        trialState.remainingUses
    }

    var hasRemainingTrialUses: Bool {
        trialState.hasRemainingUses
    }

    var hasExpandedHistoryAccess: Bool {
        isProUnlocked || hasRemainingTrialUses
    }

    func accessLevel(hasTrialAccess: Bool = false) -> AccessLevel {
        if isProUnlocked {
            return .pro
        }

        return hasTrialAccess ? .fullTrial : .limited
    }

    func canUse(_ feature: ProFeature, hasTrialAccess: Bool = false) -> Bool {
        accessLevel(hasTrialAccess: hasTrialAccess) != .limited
    }

    func consumeTrialUse() -> Bool {
        guard !isProUnlocked, trialState.hasRemainingUses else {
            return false
        }

        let usedUses = trialState.usedUses + 1
        trialState = TrialState(usedUses: usedUses)
        defaults.set(usedUses, forKey: Self.trialUsedUsesCacheKey)
        trialUsageStore.saveUsedUses(usedUses)
        return true
    }

    func beginFullFeatureComparison(isSample: Bool) -> Bool {
        guard !isSample else {
            return true
        }

        return consumeTrialUse()
    }

    #if DEBUG
    func resetTrialForTesting() {
        trialState = TrialState(usedUses: 0)
        defaults.set(0, forKey: Self.trialUsedUsesCacheKey)
        trialUsageStore.saveUsedUses(0)
        statusMessage = String(localized: "The three full-feature trial uses were restored.")
    }
    #endif

    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else {
            return
        }

        isLoadingProducts = true
        defer {
            isLoadingProducts = false
        }

        do {
            products = try await Product.products(for: [Self.proProductID])
            if products.isEmpty {
                statusMessage = String(localized: "KinePair PRO is currently unavailable. Try again later.")
            }
        } catch {
            statusMessage = String(localized: "KinePair PRO is currently unavailable. Try again later.")
        }
    }

    func purchasePro() async {
        guard !isPurchasing else {
            return
        }

        hasRecentPurchaseFailure = false

        if products.isEmpty {
            await loadProducts()
        }

        guard let product = proProduct else {
            statusMessage = String(localized: "KinePair PRO is currently unavailable. Try again later.")
            hasRecentPurchaseFailure = true
            return
        }

        isPurchasing = true
        defer {
            isPurchasing = false
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verifiedTransaction(from: verification)
                await transaction.finish()
                await refreshEntitlements()
                statusMessage = String(localized: "KinePair PRO is now unlocked.")
            case .userCancelled:
                statusMessage = String(localized: "The purchase was cancelled.")
            case .pending:
                statusMessage = String(localized: "The purchase is awaiting approval.")
            @unknown default:
                statusMessage = String(localized: "The purchase could not be completed. Try again later.")
                hasRecentPurchaseFailure = true
            }
        } catch StoreKitError.userCancelled {
            statusMessage = String(localized: "The purchase was cancelled.")
        } catch {
            statusMessage = String(localized: "The purchase could not be completed. Try again later.")
            hasRecentPurchaseFailure = true
        }
    }

    func restorePurchases() async {
        hasRecentPurchaseFailure = false
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            statusMessage = isProUnlocked
                ? String(localized: "Your purchase was restored.")
                : String(localized: "No purchase was found to restore.")
        } catch {
            statusMessage = String(localized: "The purchase could not be restored. Try again later.")
            hasRecentPurchaseFailure = true
        }
    }

    func refreshEntitlements() async {
        var hasProEntitlement = false

        for await verification in Transaction.currentEntitlements {
            guard let transaction = try? verifiedTransaction(from: verification) else {
                continue
            }

            if transaction.productID == Self.proProductID {
                hasProEntitlement = true
                break
            }
        }

        entitlementState = hasProEntitlement ? .pro : .free
        defaults.set(hasProEntitlement, forKey: Self.proCacheKey)
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await verification in Transaction.updates {
                guard let self else {
                    return
                }

                if let transaction = try? self.verifiedTransaction(from: verification) {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }
    }

    private func verifiedTransaction(
        from verification: VerificationResult<Transaction>
    ) throws -> Transaction {
        switch verification {
        case .verified(let transaction):
            return transaction
        case .unverified:
            throw PurchaseManagerError.unverifiedTransaction
        }
    }

    private static let proCacheKey = "purchase.isProUnlocked"
    private static let trialUsedUsesCacheKey = "trial.usedUses.cache"
}

private enum PurchaseManagerError: Error {
    case unverifiedTransaction
}
