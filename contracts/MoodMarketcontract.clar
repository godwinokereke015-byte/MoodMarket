;; title: MoodMarket - Prediction Markets for Collective Emotional States
;; version: 1.0.0
;; summary: A decentralized prediction market platform for betting on societal mood shifts and happiness indices
;; description: This contract enables users to create and participate in prediction markets based on collective emotional states,
;;              using aggregated data from biometric sensors, social media sentiment, weather patterns, and significant events.
;;              It includes mechanisms for market creation, betting, resolution, and mental health fund allocation.

;; traits
(define-trait mood-oracle-trait
  (
    (get-mood-score (uint uint) (response uint uint))
    (is-authorized () (response bool uint))
  )
)

;; token definitions
(define-fungible-token mood-token)

;; constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-MARKET (err u101))
(define-constant ERR-MARKET-CLOSED (err u102))
(define-constant ERR-MARKET-NOT-RESOLVED (err u103))
(define-constant ERR-ALREADY-RESOLVED (err u104))
(define-constant ERR-INSUFFICIENT-BALANCE (err u105))
(define-constant ERR-INVALID-AMOUNT (err u106))
(define-constant ERR-INVALID-PREDICTION (err u107))
(define-constant ERR-MARKET-EXPIRED (err u108))
(define-constant ERR-MARKET-NOT-EXPIRED (err u109))
(define-constant ERR-ORACLE-ERROR (err u110))
(define-constant ERR-ALREADY-CLAIMED (err u111))

(define-constant CONTRACT-OWNER tx-sender)
(define-constant MARKET-DURATION u144) ;; blocks (~24 hours)
(define-constant RESOLUTION-WINDOW u288) ;; blocks (~48 hours after market close)
(define-constant MINIMUM-BET u1000000) ;; 1 STX in microSTX
(define-constant MENTAL-HEALTH-FEE-RATE u50) ;; 5% fee for mental health fund
(define-constant MOOD-SCALE-MAX u100) ;; 0-100 mood scale

;; data vars
(define-data-var next-market-id uint u1)
(define-data-var mental-health-fund uint u0)
(define-data-var authorized-oracle (optional principal) none)
(define-data-var contract-paused bool false)

;; data maps
(define-map markets
  { market-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    creator: principal,
    created-at: uint,
    closes-at: uint,
    resolves-at: uint,
    mood-threshold: uint, ;; predicted mood score threshold
    total-pool: uint,
    positive-pool: uint, ;; betting mood will be above threshold
    negative-pool: uint, ;; betting mood will be below threshold
    resolved: bool,
    actual-mood-score: (optional uint),
    resolution-source: (string-ascii 50)
  }
)

(define-map user-positions
  { market-id: uint, user: principal }
  {
    positive-amount: uint,
    negative-amount: uint,
    claimed: bool
  }
)

(define-map mood-data
  { timestamp: uint }
  {
    biometric-score: uint,
    sentiment-score: uint,
    weather-impact: int,
    event-impact: int,
    composite-score: uint,
    data-sources: uint ;; bitmask for available data sources
  }
)

(define-map user-stats
  { user: principal }
  {
    total-bets: uint,
    successful-predictions: uint,
    total-winnings: uint,
    mental-health-contributions: uint
  }
)
