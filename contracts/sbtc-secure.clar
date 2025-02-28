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