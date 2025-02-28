# sBTC Secure Lend Protocol - Smart Contract Documentation

## Overview

A decentralized lending/borrowing protocol on Stacks blockchain enabling users to:

- Deposit sBTC as collateral
- Borrow STX, stablecoins, or other tokens
- Automatic interest rate calculations
- Liquidation mechanisms for under-collateralized positions
- Real-time collateral health monitoring

## Key Features

### Core Functionality

- Collateral Management (Deposit/Withdraw sBTC)
- Borrowing with Dynamic Interest Rates
- Automated Loan Liquidation System
- Utilization-Based Interest Model
- Real-Time Health Factor Monitoring
- Protocol Administration Controls

## Technical Specification

### Protocol Parameters

| Parameter               | Value          | Description                          |
| ----------------------- | -------------- | ------------------------------------ |
| `COLLATERAL-RATIO`      | 150%           | Minimum collateralization ratio      |
| `LIQUIDATION-THRESHOLD` | 130%           | Collateral threshold for liquidation |
| `LIQUIDATION-PENALTY`   | 10%            | Penalty applied during liquidation   |
| `MINIMUM-COLLATERAL`    | 1,000,000 uBTC | ~0.01 BTC                            |
| `ORACLE_PRICE_EXPIRY`   | 1 hour         | Price feed validity duration         |

### Interest Rate Model

```javascript
Interest Rate = Base Rate + (Utilization Rate * Slope)
Where:
- Base Rate = 5%
- Slope = 15%
- Utilization = (Total Borrowed / Total Collateral Value) * 100
```

### Critical Data Structures

```clarity
(define-map loans {
  collateral-amount: uint,
  borrowed-amount: uint,
  interest-accumulated: uint,
  last-update-block: uint,
  liquidation-price: uint,
  active: bool
})

(define-data-var total-collateral uint)
(define-data-var total-borrowed uint)
```

## Core Functions

### 1. Collateral Management

**Deposit Collateral**

```clarity
(define-public (deposit-collateral (amount uint))
```

- Requires minimum 1,000,000 uBTC (0.01 BTC)
- Transfers sBTC from user to contract
- Updates collateral records

**Withdraw Collateral**

```clarity
(define-public (withdraw-collateral (amount uint))
```

- Maintains required collateralization ratio
- Prohibited if withdrawal creates under-collateralization

### 2. Borrowing Mechanism

```clarity
(define-public (borrow (amount uint))
```

Requirements:

- Active oracle price feed
- Minimum borrow: 500,000 uSTX
- Sufficient collateral coverage
- Mints protocol stablecoin to borrower

### 3. Loan Repayment

```clarity
(define-public (repay (amount uint))
```

- Processes interest first, then principal
- Automatically closes loan when fully repaid
- Burns repaid stablecoin tokens

### 4. Liquidation System

```clarity
(define-public (liquidate (borrower principal))
```

Triggers when:

```math
Collateral Value < (Borrowed Amount + Interest) × 130%
```

Liquidator receives:

```math
Collateral Amount = (Debt × 110%) / Oracle Price
```

## Security Architecture

### Critical Safeguards

1. **Oracle Validation**

   - Price updates require admin privileges
   - Strict timestamp validation (1hr expiry)
   - Reverts operations with stale prices

2. **Protocol Controls**

   - Emergency pause functionality
   - Admin role management
   - Minimum operation thresholds

3. **Collateral Verification**
   - Real-time health factor checks
   - Automated interest accrual
   - Multi-step withdrawal validation

## Development Guide

### Contract Interactions

**Sample Deposit & Borrow Flow**

```bash
# Deposit 0.05 BTC
clarinet contract call sbtc-lend deposit-collateral 5000000

# Borrow 750,000 uSTX
clarinet contract call sbtc-lend borrow 750000
```

**Liquidation Execution**

```bash
# Check loan status
clarinet contract call sbtc-lend is-loan-liquidatable $BORROWER

# Execute liquidation
clarinet contract call sbtc-lend liquidate $BORROWER
```

## Audit Considerations

### Critical Review Areas

1. Oracle price feed implementation
2. Interest calculation accuracy
3. Collateral withdrawal safeguards
4. Liquidation incentive alignment
5. Reentrancy protection mechanisms

### Recommended Audits

- Formal verification of interest math
- Time manipulation testing
- Stress testing under volatile market conditions
- Role-based access control validation
