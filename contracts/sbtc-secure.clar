;; sBTC Secure Lend Protocol
;; A decentralized lending/borrowing platform where users can lock sBTC as collateral
;; to borrow STX, stablecoins, or other tokens on the Stacks blockchain.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED u100)
(define-constant ERR-INSUFFICIENT-BALANCE u101)
(define-constant ERR-INSUFFICIENT-COLLATERAL u102)
(define-constant ERR-MINIMUM-DEPOSIT u103)
(define-constant ERR-LOAN-NOT-FOUND u104)
(define-constant ERR-LOAN-NOT-LIQUIDATABLE u105)
(define-constant ERR-REPAYMENT-AMOUNT-TOO-LOW u106)
(define-constant ERR-PRICE-EXPIRED u107)
(define-constant ERR-PROTOCOL-PAUSED u108)
(define-constant ERR-BELOW-MINIMUM-BORROW u109)
(define-constant ERR-ORACLE-INVALID u110)

;; Constants for the protocol parameters
(define-constant COLLATERAL-RATIO u150) ;; 150% collateralization ratio (scaled by 100)
(define-constant LIQUIDATION-THRESHOLD u130) ;; 130% liquidation threshold (scaled by 100)
(define-constant LIQUIDATION-PENALTY u10) ;; 10% liquidation penalty (scaled by 100)
(define-constant MINIMUM-COLLATERAL u1000000) ;; Minimum collateral in uBTC (1 BTC = 100,000,000 uBTC)
(define-constant MINIMUM_BORROW u500000) ;; Minimum borrow amount in uSTX
(define-constant ORACLE_PRICE_EXPIRY u3600) ;; Oracle price validity in seconds (1 hour)
(define-constant INTEREST_RATE_BASE u5) ;; Base interest rate of 5% annually (scaled by 100)
(define-constant INTEREST_RATE_SLOPE u15) ;; Interest rate slope of 15% (scaled by 100)
(define-constant BLOCKS_PER_YEAR u52560) ;; Approximate number of blocks per year on Stacks

;; Data maps and variables
(define-map loans 
  { borrower: principal } 
  {
    collateral-amount: uint,    ;; Amount of sBTC collateral in uBTC
    borrowed-amount: uint,      ;; Amount of STX borrowed in uSTX
    interest-accumulated: uint, ;; Accumulated interest in uSTX
    last-update-block: uint,    ;; Block height of last interest update
    liquidation-price: uint,    ;; sBTC/STX price at which loan becomes liquidatable
    active: bool                ;; Whether the loan is currently active
  }
)

(define-map user-collateral { user: principal } { amount: uint })
(define-map user-borrows { user: principal } { amount: uint })

(define-data-var total-collateral uint u0)
(define-data-var total-borrowed uint u0)
(define-data-var last-oracle-price uint u0)
(define-data-var last-oracle-timestamp uint u0)
(define-data-var protocol-paused bool false)
(define-data-var protocol-admin principal tx-sender)
(define-data-var utilization-rate uint u0) ;; Current utilization rate (scaled by 100)
(define-data-var current-interest-rate uint u0) ;; Current interest rate (scaled by 100)

;; Asset contract references
(define-constant sBTC-asset 'ST000000000000000000002AMW42H.sbtc-token.sbtc) ;; Example sBTC token
(define-fungible-token stablecoin) ;; Internal representation of the stablecoin for borrowing

;; Implement SIP-010 trait for the stablecoin
(impl-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)

(define-read-only (get-name)
  (ok "sBTC Secure Lend Stablecoin")
)

(define-read-only (get-symbol)
  (ok "SBTCSL")
)

(define-read-only (get-decimals)
  (ok u6)
)

(define-read-only (get-balance (account principal))
  (ok (default-to u0 (get amount (map-get? user-borrows { user: account }))))
)

(define-read-only (get-total-supply)
  (ok (var-get total-borrowed))
)

(define-read-only (get-token-uri)
  (ok none)
)

;; Protocol admin functions
(define-public (set-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get protocol-admin)) (err ERR-NOT-AUTHORIZED))
    (ok (var-set protocol-admin new-admin))
  )
)

(define-public (pause-protocol (paused bool))
  (begin
    (asserts! (is-eq tx-sender (var-get protocol-admin)) (err ERR-NOT-AUTHORIZED))
    (ok (var-set protocol-paused paused))
  )
)

(define-public (update-oracle-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender (var-get protocol-admin)) (err ERR-NOT-AUTHORIZED))
    (var-set last-oracle-price new-price)
    (var-set last-oracle-timestamp (unwrap-panic (get-block-info? time (- block-height u1))))
    (ok true)
  )
)

;; Helper functions
(define-read-only (calculate-required-collateral (borrow-amount uint))
  (let (
    (price (var-get last-oracle-price))
  )
    ;; Formula: (borrow-amount * COLLATERAL_RATIO) / (price * 100)
    (/ (* borrow-amount COLLATERAL-RATIO) (* price u100))
  )
)

(define-read-only (calculate-max-borrow (collateral-amount uint))
  (let (
    (price (var-get last-oracle-price))
  )
    ;; Formula: (collateral-amount * price * 100) / COLLATERAL_RATIO
    (/ (* (* collateral-amount price) u100) COLLATERAL-RATIO)
  )
)

(define-read-only (calculate-liquidation-price (collateral-amount uint) (borrowed-amount uint))
  (let (
    ;; Formula: (borrowed-amount * 100) / (collateral-amount * LIQUIDATION_THRESHOLD / 100)
    (liquidation-price (/ (* borrowed-amount u10000) (* collateral-amount LIQUIDATION-THRESHOLD)))
  )
    liquidation-price
  )
)

(define-read-only (is-loan-liquidatable (borrower principal))
  (let (
    (loan (unwrap! (map-get? loans { borrower: borrower }) (err ERR-LOAN-NOT-FOUND)))
    (current-price (var-get last-oracle-price))
    (timestamp (unwrap-panic (get-block-info? time (- block-height u1))))
  )
    ;; Check if oracle price is not expired
    (asserts! (< (- timestamp (var-get last-oracle-timestamp)) ORACLE_PRICE_EXPIRY) (err ERR-PRICE-EXPIRED))
    
    ;; Check if loan is active
    (asserts! (get active loan) (err ERR-LOAN-NOT-FOUND))
    
    ;; Check if current price is below liquidation price
    (ok (< current-price (get liquidation-price loan)))
  )
)

(define-read-only (get-current-interest-rate)
  (let (
    (utilization (var-get utilization-rate))
    (base-rate INTEREST_RATE_BASE)
    (slope INTEREST_RATE_SLOPE)
  )
    ;; Formula: base-rate + (utilization * slope / 100)
    (+ base-rate (/ (* utilization slope) u100))
  )
)

(define-read-only (get-loan-details (borrower principal))
  (map-get? loans { borrower: borrower })
)

(define-read-only (get-collateral-value (amount uint))
  (let (
    (price (var-get last-oracle-price))
    (timestamp (unwrap-panic (get-block-info? time (- block-height u1))))
  )
    ;; Check if oracle price is not expired
    (asserts! (< (- timestamp (var-get last-oracle-timestamp)) ORACLE_PRICE_EXPIRY) (err ERR-PRICE-EXPIRED))
    
    ;; Calculate the value: amount * price
    (* amount price)
  )
)

(define-read-only (get-health-factor (borrower principal))
  (let (
    (loan (unwrap! (map-get? loans { borrower: borrower }) (err ERR-LOAN-NOT-FOUND)))
    (collateral-amount (get collateral-amount loan))
    (borrowed-amount (get borrowed-amount loan))
    (interest-accumulated (get interest-accumulated loan))
    (total-debt (+ borrowed-amount interest-accumulated))
    (collateral-value (get-collateral-value collateral-amount))
  )
    ;; Health factor = (collateral-value * 100) / (total-debt * COLLATERAL_RATIO)
    (/ (* collateral-value u100) (* total-debt COLLATERAL-RATIO))
  )
)

;; Update the interest rate based on the current utilization
(define-private (update-interest-rate)
  (let (
    (total-collateral-value (get-collateral-value (var-get total-collateral)))
    (total-borrowed-amount (var-get total-borrowed))
  )
    ;; Update utilization rate: (total-borrowed * 100) / total-collateral-value
    (if (> total-collateral-value u0)
      (begin
        (var-set utilization-rate (/ (* total-borrowed-amount u100) total-collateral-value))
        (var-set current-interest-rate (get-current-interest-rate))
      )
      (begin
        (var-set utilization-rate u0)
        (var-set current-interest-rate INTEREST_RATE_BASE)
      )
    )
  )
)

;; Calculate interest for a specific loan
(define-private (calculate-interest (borrowed-amount uint) (last-update-block uint))
  (let (
    (blocks-passed (- block-height last-update-block))
    (interest-rate (var-get current-interest-rate))
    ;; Daily interest = (borrowed-amount * interest-rate) / (BLOCKS_PER_YEAR * 100)
    (interest-per-block (/ (* borrowed-amount interest-rate) (* BLOCKS_PER_YEAR u100)))
  )
    (* interest-per-block blocks-passed)
  )
)

;; Update loan's accumulated interest
(define-private (update-loan-interest (borrower principal))
  (let (
    (loan (unwrap! (map-get? loans { borrower: borrower }) (err ERR-LOAN-NOT-FOUND)))
    (active (get active loan))
    (borrowed-amount (get borrowed-amount loan))
    (last-update-block (get last-update-block loan))
    (current-interest (get interest-accumulated loan))
    (new-interest (if active 
                     (+ current-interest (calculate-interest borrowed-amount last-update-block))
                     current-interest))
  )
    (map-set loans 
      { borrower: borrower } 
      (merge loan {
        interest-accumulated: new-interest,
        last-update-block: block-height
      })
    )
  )
)

;; Core protocol functions
(define-public (deposit-collateral (amount uint))
  (let (
    (sender tx-sender)
    (current-collateral (default-to { amount: u0 } (map-get? user-collateral { user: sender })))
  )
    ;; Check if protocol is not paused
    (asserts! (not (var-get protocol-paused)) (err ERR-PROTOCOL-PAUSED))
    
    ;; Check minimum deposit
    (asserts! (>= amount MINIMUM-COLLATERAL) (err ERR-MINIMUM-DEPOSIT))
    
    ;; Transfer sBTC from user to the contract
    (asserts! (is-ok (contract-call? sBTC-asset transfer amount sender (as-contract tx-sender) none)) 
              (err ERR-INSUFFICIENT-BALANCE))
    
    ;; Update user's collateral
    (map-set user-collateral 
      { user: sender } 
      { amount: (+ (get amount current-collateral) amount) })
    
    ;; Update total collateral
    (var-set total-collateral (+ (var-get total-collateral) amount))
    
    ;; Update interest rate
    (update-interest-rate)
    
    (ok amount)
  )
)

(define-public (withdraw-collateral (amount uint))
  (let (
    (sender tx-sender)
    (current-collateral (default-to { amount: u0 } (map-get? user-collateral { user: sender })))
    (user-collateral-amount (get amount current-collateral))
    (loan (default-to { 
              collateral-amount: u0, 
              borrowed-amount: u0, 
              interest-accumulated: u0,
              last-update-block: block-height,
              liquidation-price: u0,
              active: false
            } 
            (map-get? loans { borrower: sender })))
    (has-active-loan (get active loan))
  )
    ;; Check if protocol is not paused
    (asserts! (not (var-get protocol-paused)) (err ERR-PROTOCOL-PAUSED))
    
    ;; Check if user has enough collateral
    (asserts! (<= amount user-collateral-amount) (err ERR-INSUFFICIENT-BALANCE))
    
    ;; If user has an active loan, ensure they maintain sufficient collateral
    (if has-active-loan
      (begin
        ;; Update loan interest first
        (update-loan-interest sender)
        
        ;; Get the updated loan
        (let (
          (updated-loan (unwrap! (map-get? loans { borrower: sender }) (err ERR-LOAN-NOT-FOUND)))
          (borrowed-amount (get borrowed-amount updated-loan))
          (interest-accumulated (get interest-accumulated updated-loan))
          (total-debt (+ borrowed-amount interest-accumulated))
          (remaining-collateral (- user-collateral-amount amount))
          (required-collateral (calculate-required-collateral total-debt))
        )
          ;; Ensure remaining collateral is sufficient
          (asserts! (>= remaining-collateral required-collateral) (err ERR-INSUFFICIENT-COLLATERAL))
          
          ;; Update loan collateral and liquidation price
          (map-set loans 
            { borrower: sender } 
            (merge updated-loan {
              collateral-amount: remaining-collateral,
              liquidation-price: (calculate-liquidation-price remaining-collateral total-debt)
            })
          )
        )
      )
      true
    )
    
    ;; Update user's collateral
    (map-set user-collateral 
      { user: sender } 
      { amount: (- user-collateral-amount amount) })
    
    ;; Update total collateral
    (var-set total-collateral (- (var-get total-collateral) amount))
    
    ;; Transfer sBTC from contract to user
    (as-contract 
      (contract-call? sBTC-asset transfer amount tx-sender sender none))
    
    ;; Update interest rate
    (update-interest-rate)
    
    (ok amount)
  )
)

(define-public (borrow (amount uint))
  (let (
    (sender tx-sender)
    (current-collateral (default-to { amount: u0 } (map-get? user-collateral { user: sender })))
    (user-collateral-amount (get amount current-collateral))
    (loan (default-to { 
              collateral-amount: u0, 
              borrowed-amount: u0, 
              interest-accumulated: u0,
              last-update-block: block-height,
              liquidation-price: u0,
              active: false
            } 
            (map-get? loans { borrower: sender })))
    (has-active-loan (get active loan))
    (borrowed-amount (get borrowed-amount loan))
    (interest-accumulated (get interest-accumulated loan))
    (timestamp (unwrap-panic (get-block-info? time (- block-height u1))))
  )
    ;; Check if protocol is not paused
    (asserts! (not (var-get protocol-paused)) (err ERR-PROTOCOL-PAUSED))
    
    ;; Check if oracle price is not expired
    (asserts! (< (- timestamp (var-get last-oracle-timestamp)) ORACLE_PRICE_EXPIRY) (err ERR-ORACLE-INVALID))
    
    ;; Check minimum borrow
    (asserts! (>= amount MINIMUM_BORROW) (err ERR-BELOW-MINIMUM-BORROW))
    
    ;; Update loan interest if active loan exists
    (if has-active-loan
      (update-loan-interest sender)
      true
    )
    
    ;; Get total debt (existing borrowed amount + accumulated interest + new borrow)
    (let (
      (updated-loan (if has-active-loan 
                      (unwrap! (map-get? loans { borrower: sender }) (err ERR-LOAN-NOT-FOUND)) 
                      loan))
      (total-existing-debt (+ (get borrowed-amount updated-loan) (get interest-accumulated updated-loan)))
      (total-new-debt (+ total-existing-debt amount))
      (required-collateral (calculate-required-collateral total-new-debt))
    )
      ;; Check if user has sufficient collateral
      (asserts! (>= user-collateral-amount required-collateral) (err ERR-INSUFFICIENT-COLLATERAL))
      
      ;; Mint stablecoin tokens to the borrower
      (ft-mint? stablecoin amount sender)
      
      ;; Update or create loan
      (map-set loans 
        { borrower: sender } 
        {
          collateral-amount: user-collateral-amount,
          borrowed-amount: (+ borrowed-amount amount),
          interest-accumulated: interest-accumulated,
          last-update-block: block-height,
          liquidation-price: (calculate-liquidation-price user-collateral-amount total-new-debt),
          active: true
        }
      )
      
      ;; Update user's borrow amount
      (map-set user-borrows 
        { user: sender } 
        { amount: (+ (default-to u0 (get amount (map-get? user-borrows { user: sender }))) amount) })
      
      ;; Update total borrowed
      (var-set total-borrowed (+ (var-get total-borrowed) amount))
      
      ;; Update interest rate
      (update-interest-rate)
      
      (ok amount)
    )
  )
)

(define-public (repay (amount uint))
  (let (
    (sender tx-sender)
    (loan (unwrap! (map-get? loans { borrower: sender }) (err ERR-LOAN-NOT-FOUND)))
    (active (get active loan))
  )
    ;; Check if loan is active
    (asserts! active (err ERR-LOAN-NOT-FOUND))
    
    ;; Update loan interest first
    (update-loan-interest sender)
    
    ;; Get updated loan
    (let (
      (updated-loan (unwrap! (map-get? loans { borrower: sender }) (err ERR-LOAN-NOT-FOUND)))
      (borrowed-amount (get borrowed-amount updated-loan))
      (interest-accumulated (get interest-accumulated updated-loan))
      (total-debt (+ borrowed-amount interest-accumulated))
    )
      ;; Ensure repayment amount is not larger than the debt
      (let (
        (repay-amount (if (> amount total-debt) total-debt amount))
        (interest-repaid (if (> repay-amount interest-accumulated) 
                             interest-accumulated
                             repay-amount))
        (principal-repaid (- repay-amount interest-repaid))
        (remaining-borrowed (- borrowed-amount principal-repaid))
        (remaining-interest (- interest-accumulated interest-repaid))
      )
        ;; Burn stablecoin tokens from the borrower
        (ft-burn? stablecoin repay-amount sender)
        
        ;; Update total borrowed
        (var-set total-borrowed (- (var-get total-borrowed) principal-repaid))
        
        ;; Update user's borrow amount
        (map-set user-borrows 
          { user: sender } 
          { amount: (- (unwrap! (get amount (map-get? user-borrows { user: sender })) (err ERR-LOAN-NOT-FOUND)) principal-repaid) })
        
        ;; Update loan status
        (if (and (is-eq remaining-borrowed u0) (is-eq remaining-interest u0))
          ;; Loan fully repaid
          (map-set loans 
            { borrower: sender } 
            (merge updated-loan {
              borrowed-amount: u0,
              interest-accumulated: u0,
              active: false
            })
          )
          ;; Partial repayment
          (map-set loans 
            { borrower: sender } 
            (merge updated-loan {
              borrowed-amount: remaining-borrowed,
              interest-accumulated: remaining-interest,
              liquidation-price: (calculate-liquidation-price 
                                   (get collateral-amount updated-loan) 
                                   (+ remaining-borrowed remaining-interest))
            })
          )
        )
        
        ;; Update interest rate
        (update-interest-rate)
        
        (ok repay-amount)
      )
    )
  )
)

(define-public (liquidate (borrower principal))
  (let (
    (liquidator tx-sender)
    (liquidatable (unwrap! (is-loan-liquidatable borrower) (err ERR-LOAN-NOT-LIQUIDATABLE)))
    (loan (unwrap! (map-get? loans { borrower: borrower }) (err ERR-LOAN-NOT-FOUND)))
    (collateral-amount (get collateral-amount loan))
    (borrowed-amount (get borrowed-amount loan))
    (interest-accumulated (get interest-accumulated loan))
    (total-debt (+ borrowed-amount interest-accumulated))
    (price (var-get last-oracle-price))
    (timestamp (unwrap-panic (get-block-info? time (- block-height u1))))
  )
    ;; Check if protocol is not paused
    (asserts! (not (var-get protocol-paused)) (err ERR-PROTOCOL-PAUSED))
    
    ;; Check if oracle price is not expired
    (asserts! (< (- timestamp (var-get last-oracle-timestamp)) ORACLE_PRICE_EXPIRY) (err ERR-ORACLE-INVALID))
    
    ;; Check if loan is actually liquidatable
    (asserts! liquidatable (err ERR-LOAN-NOT-LIQUIDATABLE))
    
    ;; Calculate collateral to liquidate (debt + liquidation penalty)
    (let (
      (liquidation-bonus (/ (* total-debt LIQUIDATION-PENALTY) u100))
      (debt-with-bonus (+ total-debt liquidation-bonus))
      (collateral-to-liquidate (/ (* debt-with-bonus u100) (* price u100)))
    )
      ;; Ensure liquidator has enough stablecoins to repay the debt
      (asserts! (>= (ft-get-balance stablecoin liquidator) total-debt) (err ERR-INSUFFICIENT-BALANCE))
      
      ;; Burn stablecoin tokens from the liquidator to repay the debt
      (ft-burn? stablecoin total-debt liquidator)
      
      ;; Transfer sBTC collateral to liquidator
      (as-contract 
        (contract-call? sBTC-asset transfer collateral-to-liquidate tx-sender liquidator none))
      
      ;; Update borrower's collateral
      (let (
        (remaining-collateral (- collateral-amount collateral-to-liquidate))
        (borrower-collateral (unwrap! (map-get? user-collateral { user: borrower }) (err ERR-LOAN-NOT-FOUND)))
      )
        (map-set user-collateral 
          { user: borrower } 
          { amount: (- (get amount borrower-collateral) collateral-to-liquidate) })
        
        ;; Mark loan as inactive
        (map-set loans 
          { borrower: borrower } 
          (merge loan {
            collateral-amount: remaining-collateral,
            borrowed-amount: u0,
            interest-accumulated: u0,
            active: false
          })
        )
        
        ;; Update user's borrow amount
        (map-set user-borrows { user: borrower } { amount: u0 })
        
        ;; Update total borrowed and collateral
        (var-set total-borrowed (- (var-get total-borrowed) borrowed-amount))
        (var-set total-collateral (- (var-get total-collateral) collateral-to-liquidate))
        
        ;; Update interest rate
        (update-interest-rate)
        
        (ok collateral-to-liquidate)
      )
    )
  )
)

;; Initialize contract
(begin
  ;; Initialize interest rate
  (var-set current-interest-rate INTEREST_RATE_BASE)
)