# Investment Thesis Launchpad

## MVP Product Requirements Document

### 1. Product

**Investment Thesis Launchpad**

A social platform where users turn an investment thesis into a structured strategy using tokenized stocks.

**Core idea:**

> **Turn what you believe into something others can discover and follow.**

---

# 2. MVP Goal

Prove one simple product loop:

```text
CREATE THESIS
      ↓
BUILD STRATEGY
      ↓
PUBLISH
      ↓
DISCOVER
      ↓
FOLLOW / PARTICIPATE
      ↓
TRACK
```

The MVP should make this loop understandable within a few minutes.

---

# 3. Target Users

### Strategy Creators

People who have investment ideas and want to package them into a public strategy.

Examples:

* Finance creators
* Stock researchers
* Crypto/Web3 creators
* Investment communities

### Strategy Explorers

People who want to discover investment ideas without manually researching every stock.

They browse themes such as:

* AI
* Robotics
* Space
* Energy
* Semiconductors
* Technology

---

# 4. Core MVP Features

## Feature 1 — Explore

The homepage is the main discovery surface.

### Sections

**Trending Strategies**

Strategies gaining attention.

**New Strategies**

Recently created strategies.

**Categories**

* AI
* Robotics
* Space
* Energy
* Technology

### Strategy Card

Each card shows:

```text
AI WILL WIN
$AIWIN

AI infrastructure will define
the next decade.

NVDA  40%
AMD   25%
TSMC  20%
MSFT  15%

1,284 followers

[ View Strategy ]
```

---

# 5. Feature 2 — Strategy Detail

The strategy page is the main object of the platform.

### Header

```text
AI WILL WIN
$AIWIN

Created by @alex

[ Follow ] [ Participate ]
```

### Thesis

Short explanation of the creator's investment idea.

### Allocation

Visual breakdown of the underlying tokenized stocks.

```text
NVDA ████████████ 40%
AMD  ███████      25%
TSMC ██████       20%
MSFT ████         15%
```

### Strategy Information

* Creator
* Category
* Creation date
* Followers
* Allocation
* Strategy description

### Activity

Recent updates and community activity.

---

# 6. Feature 3 — Create Strategy

Users can create their own investment thesis.

### Step 1 — Name

Example:

**AI Will Win**

Ticker:

**AIWIN**

---

### Step 2 — Thesis

Example:

> AI infrastructure will define the next decade.

---

### Step 3 — Select Stocks

Users select supported tokenized stocks.

Example:

| Stock     | Allocation |
| --------- | ---------: |
| NVIDIA    |        40% |
| AMD       |        25% |
| TSMC      |        20% |
| Microsoft |        15% |

Allocation must equal **100%**.

---

### Step 4 — Preview

Show:

```text
AI WILL WIN

AI infrastructure will define
the next decade.

NVDA 40%
AMD  25%
TSMC 20%
MSFT 15%

[ Publish Strategy ]
```

---

### Step 5 — Publish

After publishing:

* Strategy gets a public page.
* Strategy appears in Explore.
* Creator becomes associated with the strategy.
* Other users can follow it.

---

# 7. Feature 4 — Follow

Users can follow a strategy without participating immediately.

### Follow button

```text
[ + Follow ]
```

After following:

```text
[ ✓ Following ]
```

Users can later see their followed strategies in their portfolio/dashboard.

---

# 8. Feature 5 — Participate

Users can enter the strategy through one simple action.

```text
AI WILL WIN

NVDA 40%
AMD  25%
TSMC 20%
MSFT 15%

Amount

$ [ 1,000 ]

[ Participate ]
```

For the MVP, this can use a **demo/testnet flow** rather than real-money execution.

After confirmation:

```text
✓ Strategy participation confirmed

AI WILL WIN
Amount: $1,000

[ View Portfolio ]
```

The UI must clearly indicate whether the transaction is simulated, testnet, or real.

---

# 9. Feature 6 — My Portfolio

Users can see the strategies they follow or participate in.

```text
MY STRATEGIES

AI WILL WIN
$AIWIN

Amount
$1,000

Allocation

NVDA 40%
AMD  25%
TSMC 20%
MSFT 15%

[ View Strategy ]
```

The portfolio is strategy-first rather than requiring users to manage every underlying stock individually.

---

# 10. Creator Profile

A minimal creator profile is required because strategies are social objects.

```text
@alex

AI & Technology Research

Followers: 1,284

Strategies

AI WILL WIN
$AIWIN

SEMICONDUCTOR BOOM
$CHIPS

ROBOTICS FUTURE
$ROBOT
```

Users can discover all strategies created by a creator.

---

# 11. MVP Navigation

Only four primary navigation items are needed:

```text
┌────────────────────────────────────┐
│ LOGO                               │
│                                    │
│ Explore     Create     Portfolio   │
│                         Profile    │
└────────────────────────────────────┘
```

### Pages

1. **Explore**
2. **Strategy Detail**
3. **Create Strategy**
4. **Portfolio**
5. **Creator Profile**

---

# 12. Complete MVP User Flow

## Creator Flow

```text
EXPLORE
   ↓
CREATE
   ↓
NAME THESIS
   ↓
WRITE THESIS
   ↓
SELECT STOCKS
   ↓
SET ALLOCATION
   ↓
PREVIEW
   ↓
PUBLISH
   ↓
STRATEGY PAGE
```

## Investor Flow

```text
EXPLORE
   ↓
TRENDING STRATEGY
   ↓
STRATEGY PAGE
   ↓
READ THESIS
   ↓
CHECK ALLOCATION
   ↓
FOLLOW
   ↓
PARTICIPATE
   ↓
PORTFOLIO
```

---

# 13. MVP Example

A creator believes:

> **AI will dominate the next decade.**

They create:

### AI Will Win

**$AIWIN**

```text
NVIDIA       40%
AMD          25%
TSMC         20%
Microsoft    15%
```

They publish it.

Another user discovers it on the Explore page.

The user:

1. Reads the thesis.
2. Reviews the allocation.
3. Follows the strategy.
4. Participates with $1,000 in the demo flow.
5. Tracks it from Portfolio.

This single scenario demonstrates the entire product.

---

# 14. MVP Success Criteria

The MVP is successful if a new user can understand and complete the following without explanation:

### Creator

**Idea → Strategy → Publish**

### Explorer

**Discover → Understand → Follow**

### Participant

**Strategy → Participate → Track**

The entire product should communicate one simple concept:

> **Investment ideas can become discoverable strategies.**

---

# 15. Explicitly Out of Scope

Do **not** build these for the MVP:

* Automated trading
* AI trading agents
* Leverage
* Perpetuals
* Lending
* Complex rebalancing
* Advanced analytics
* Comments
* Governance
* DAO
* Copy trading
* Cross-chain support
* Complex creator economics
* Real-world brokerage infrastructure

The goal is to make the **thesis → strategy → discovery → participation** experience excellent rather than building a full financial platform.

---

# 16. MVP Positioning

### One-liner

> **A social launchpad for tokenized investment strategies.**

### User-facing message

> **Have a thesis? Turn it into a strategy.**

### Core loop

```text
        ┌─────────────┐
        │    IDEA     │
        └──────┬──────┘
               ↓
        ┌─────────────┐
        │   THESIS    │
        └──────┬──────┘
               ↓
        ┌─────────────┐
        │  STRATEGY   │
        └──────┬──────┘
               ↓
        ┌─────────────┐
        │  DISCOVERY  │
        └──────┬──────┘
               ↓
        ┌─────────────┐
        │  FOLLOW /   │
        │ PARTICIPATE │
        └──────┬──────┘
               ↓
        ┌─────────────┐
        │  PORTFOLIO  │
        └─────────────┘
```

**MVP = one compelling loop, not a full brokerage.**
