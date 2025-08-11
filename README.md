# Augury - Decentralized Prediction Market

A robust, secure prediction market smart contract built on the Stacks blockchain using Clarity. Augury allows users to stake STX tokens on binary outcomes and earn rewards based on prediction accuracy.

## 🚀 Features

- **Binary Prediction Markets**: Stake on true/false outcomes
- **Proportional Rewards**: Winners share the losing pool proportionally
- **Batch Operations**: Process up to 200 predictions in a single transaction
- **Comprehensive Analytics**: Track market volume, user statistics, and daily metrics
- **Staking Tiers**: Different reward multipliers based on stake amounts
- **Security First**: Extensive input validation and overflow protection
- **Emergency Controls**: Pause mechanism and emergency withdrawal capabilities
- **Category Management**: Organize predictions into categories with deadlines

## 🔄 Recent Changes

### Security Enhancements
- Added circuit breaker mechanism to prevent cascading failures
- Implemented reentrancy protection across all state-changing functions
- Added comprehensive error tracking and monitoring system
- Enhanced input validation with safe data extraction functions

### New Features
- **Failed Operations Recovery**: Added tracking and recovery of failed transactions
- **Batch Operations**: New secure batch prediction processing with rollback capability
- **Enhanced Analytics**: Daily market metrics including volume, users, and prediction counts
- **User Statistics**: Expanded tracking of user performance and staking history

### Technical Improvements
- Implemented checks-effects-interactions pattern in state-changing functions
- Added safe data extraction functions for all input processing
- Enhanced pool validation with overflow protection
- Added atomic state updates for user statistics

### Administrative Functions
- Added `reset-circuit-breaker` for recovery from emergency stops
- Added `recover-failed-operation` to handle failed transfers
- Enhanced contract management functions with stricter validation
- Added emergency withdrawal capabilities for contract owner

### Analytics & Monitoring
- Added system health monitoring functions
- Enhanced daily analytics tracking with secure updates
- Added comprehensive user statistics tracking
- Implemented failed operation tracking and recovery

### Constants & Error Handling
```clarity
;; New error constants
ERR-DOUBLE-STAKE       u800
ERR-CONTRACT-PAUSED    u801
ERR-DEADLINE-PASSED    u802
ERR-CIRCUIT-BREAKER    u806
ERR-REENTRANCY        u807
ERR-DATA-VALIDATION    u808
```

### Security State Variables
```clarity
circuit-breaker-triggered    bool
reentrancy-guard            bool
error-count                 uint
max-errors-per-block        uint
```

## 📋 Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Contract Architecture](#contract-architecture)
- [API Reference](#api-reference)
- [Security Features](#security-features)
- [Usage Examples](#usage-examples)
- [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)

## 🛠 Installation

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) - Clarity development environment
- [Node.js](https://nodejs.org/) (v16 or higher)
- [Stacks CLI](https://docs.stacks.co/docs/write-smart-contracts/clarinet)

### Setup

1. Clone the repository:
```bash
git clone https://github.com/your-username/augury.git
cd augury
```

2. Install dependencies:
```bash
clarinet install
```

3. Run tests:
```bash
clarinet test
```

## 🚀 Quick Start

### Deploy the Contract

```bash
clarinet deploy --testnet
```

### Basic Usage

1. **Make a Prediction**:
```clarity
(contract-call? .augury predict true u10000) ;; Predict true with 10,000 microSTX
```

2. **Check Pool Status**:
```clarity
(contract-call? .augury get-pools)
```

3. **Claim Rewards** (after resolution):
```clarity
(contract-call? .augury claim)
```

## 🏗 Contract Architecture

### Core Components

- **Prediction Engine**: Handles individual and batch predictions
- **Reward System**: Calculates and distributes winnings proportionally
- **Analytics Module**: Tracks market metrics and user statistics
- **Security Layer**: Comprehensive validation and overflow protection
- **Admin Controls**: Owner functions for market management

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `outcome` | `(optional bool)` | Resolved market outcome |
| `total-true-pool` | `uint` | Total STX staked on true |
| `total-false-pool` | `uint` | Total STX staked on false |
| `platform-fee` | `uint` | Platform fee (basis points) |
| `contract-paused` | `bool` | Emergency pause state |

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `MIN-STAKE-AMOUNT` | 1,000 | Minimum stake in microSTX |
| `MAX-STAKE-AMOUNT` | 1,000,000,000,000 | Maximum stake in microSTX |
| `PRECISION` | 1,000,000 | Calculation precision |
| `REWARD-CYCLE` | 144 | Blocks per reward cycle |

## 📚 API Reference

### Public Functions

#### `predict(choice: bool, amount: uint)`
Make a single prediction on the market outcome.

**Parameters:**
- `choice`: Prediction (true/false)
- `amount`: Stake amount in microSTX

**Returns:** `(response bool uint)`

#### `batch-predict(predictions: (list 200 {choice: bool, amount: uint}))`
Process multiple predictions in a single transaction.

**Parameters:**
- `predictions`: List of prediction objects (max 200)

**Returns:** `(response uint uint)` - Batch ID

#### `claim()`
Claim rewards after market resolution (winners only).

**Returns:** `(response uint uint)` - Reward amount

#### `resolve(result: bool)`
Resolve the market outcome (owner only).

**Parameters:**
- `result`: Market outcome (true/false)

**Returns:** `(response bool uint)`

### Administrative Functions

#### `set-platform-fee(new-fee: uint)`
Update platform fee (owner only, max 10%).

#### `set-contract-pause(pause-state: bool)`
Pause/unpause contract operations (owner only).

#### `create-category(name: string-ascii, deadline: uint)`
Create a new prediction category with deadline.

#### `set-staking-tier(tier: uint, minimum-stake: uint, multiplier: uint)`
Configure staking tiers with reward multipliers.

#### `reset-circuit-breaker()`
Reset the circuit breaker in case of a false positive trigger (owner only).

#### `recover-failed-operation(batch-id: uint)`
Recover from a failed batch operation (owner only).

### Read-Only Functions

#### `get-pools()`
Returns current pool balances.

```clarity
{
  true-pool: uint,
  false-pool: uint
}
```

#### `get-user-stake(user: principal, prediction: bool)`
Get user's stake for a specific prediction.

#### `get-contract-status()`
Returns contract operational status.

#### `get-user-stats(user: principal)`
Get comprehensive user statistics.

## 🔒 Security Features

### Input Validation
- **Amount Validation**: Min/max stake limits
- **Principal Validation**: Standard address checks
- **Pool Overflow Protection**: Prevents arithmetic overflow
- **Batch Validation**: Validates entire batch before processing

### Access Controls
- **Owner-Only Functions**: Critical operations restricted
- **Emergency Pause**: Immediate contract suspension capability
- **Safe Transfers**: Validated STX transfers

### Error Handling
- **Comprehensive Error Codes**: Detailed error reporting
- **Graceful Failures**: Safe failure modes
- **Validation Chains**: Multi-layer input validation

## 💡 Usage Examples

### Single Prediction
```clarity
;; Predict true outcome with 50,000 microSTX
(contract-call? .augury predict true u50000)
```

### Batch Predictions
```clarity
;; Multiple predictions in one transaction
(contract-call? .augury batch-predict 
  (list 
    {choice: true, amount: u10000}
    {choice: false, amount: u20000}
    {choice: true, amount: u15000}))
```

### Market Management
```clarity
;; Create a new category
(contract-call? .augury create-category "Sports Outcome" u1000000)

;; Set prediction deadline
(contract-call? .augury set-prediction-deadline u1000000)

;; Resolve market
(contract-call? .augury resolve true)
```

### Analytics Queries
```clarity
;; Check pool status
(contract-call? .augury get-pools)

;; Get user statistics
(contract-call? .augury get-user-stats 'SP1234...)

;; Check contract status
(contract-call? .augury get-contract-status)
```

## 🧪 Testing

Run the test suite:
```bash
clarinet test
```

Run specific test file:
```bash
clarinet test tests/augury_test.ts
```

### Test Coverage
- ✅ Prediction functionality
- ✅ Batch operations
- ✅ Reward calculations
- ✅ Security validations
- ✅ Administrative functions
- ✅ Error handling

## 📊 Analytics & Monitoring

The contract provides comprehensive analytics:

- **Daily Market Data**: Volume, users, prediction counts
- **User Statistics**: Total staked, wins, accuracy rates
- **Pool Metrics**: Real-time pool balances
- **Batch Operation Tracking**: Batch processing history

## 🚨 Emergency Procedures

### Contract Pause
```clarity
(contract-call? .augury set-contract-pause true)
```

### Emergency Withdrawal
```clarity
(contract-call? .augury emergency-withdraw .token-contract)
```

