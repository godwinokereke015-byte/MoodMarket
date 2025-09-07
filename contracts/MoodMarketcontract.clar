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

;; public functions

;; Initialize the contract with an oracle
(define-public (initialize (oracle principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (is-none (var-get authorized-oracle)) ERR-UNAUTHORIZED)
    (var-set authorized-oracle (some oracle))
    (ok true)
  )
)

;; Create a new mood prediction market
(define-public (create-market 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (mood-threshold uint)
  (resolution-source (string-ascii 50)))
  (let
    (
      (market-id (var-get next-market-id))
      (current-block (get-block))
    )
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
    (asserts! (and (>= mood-threshold u0) (<= mood-threshold MOOD-SCALE-MAX)) ERR-INVALID-PREDICTION)
    
    (map-set markets
      { market-id: market-id }
      {
        title: title,
        description: description,
        creator: tx-sender,
        created-at: current-block,
        closes-at: (+ current-block MARKET-DURATION),
        resolves-at: (+ current-block MARKET-DURATION RESOLUTION-WINDOW),
        mood-threshold: mood-threshold,
        total-pool: u0,
        positive-pool: u0,
        negative-pool: u0,
        resolved: false,
        actual-mood-score: none,
        resolution-source: resolution-source
      }
    )
    
    (var-set next-market-id (+ market-id u1))
    (ok market-id)
  )
)

;; Place a bet on a market
(define-public (place-bet (market-id uint) (prediction bool) (amount uint))
  (let
    (
      (market (unwrap! (map-get? markets { market-id: market-id }) ERR-INVALID-MARKET))
      (current-position (default-to 
        { positive-amount: u0, negative-amount: u0, claimed: false }
        (map-get? user-positions { market-id: market-id, user: tx-sender })))
      (mental-health-fee (/ (* amount MENTAL-HEALTH-FEE-RATE) u1000))
      (bet-amount (- amount mental-health-fee))
    )
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
    (asserts! (>= amount MINIMUM-BET) ERR-INVALID-AMOUNT)
    (asserts! (< (get-block) (get closes-at market)) ERR-MARKET-CLOSED)
    (asserts! (not (get resolved market)) ERR-ALREADY-RESOLVED)
    
    ;; Transfer STX from user
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update mental health fund
    (var-set mental-health-fund (+ (var-get mental-health-fund) mental-health-fee))
    
    ;; Update market pools and user position
    (if prediction
      (begin
        (map-set markets
          { market-id: market-id }
          (merge market {
            total-pool: (+ (get total-pool market) bet-amount),
            positive-pool: (+ (get positive-pool market) bet-amount)
          })
        )
        (map-set user-positions
          { market-id: market-id, user: tx-sender }
          (merge current-position {
            positive-amount: (+ (get positive-amount current-position) bet-amount)
          })
        )
      )
      (begin
        (map-set markets
          { market-id: market-id }
          (merge market {
            total-pool: (+ (get total-pool market) bet-amount),
            negative-pool: (+ (get negative-pool market) bet-amount)
          })
        )
        (map-set user-positions
          { market-id: market-id, user: tx-sender }
          (merge current-position {
            negative-amount: (+ (get negative-amount current-position) bet-amount)
          })
        )
      )
    )
    
    ;; Update user stats
    (update-user-stats tx-sender bet-amount mental-health-fee)
    
    (ok true)
  )
)

;; Resolve a market using oracle data
(define-public (resolve-market (market-id uint))
  (let
    (
      (market (unwrap! (map-get? markets { market-id: market-id }) ERR-INVALID-MARKET))
      (oracle (unwrap! (var-get authorized-oracle) ERR-ORACLE-ERROR))
    )
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-eq tx-sender oracle)) ERR-UNAUTHORIZED)
    (asserts! (>= (get-block) (get closes-at market)) ERR-MARKET-NOT-EXPIRED)
    (asserts! (< (get-block) (get resolves-at market)) ERR-MARKET-EXPIRED)
    (asserts! (not (get resolved market)) ERR-ALREADY-RESOLVED)
    
    ;; Get mood score from oracle or composite calculation
    (let
      (
        (mood-score (try! (get-composite-mood-score (get closes-at market))))
      )
      (map-set markets
        { market-id: market-id }
        (merge market {
          resolved: true,
          actual-mood-score: (some mood-score)
        })
      )
      (ok mood-score)
    )
  )
)

;; Claim winnings from a resolved market
(define-public (claim-winnings (market-id uint))
  (let
    (
      (market (unwrap! (map-get? markets { market-id: market-id }) ERR-INVALID-MARKET))
      (position (unwrap! (map-get? user-positions { market-id: market-id, user: tx-sender }) ERR-INVALID-MARKET))
      (actual-score (unwrap! (get actual-mood-score market) ERR-MARKET-NOT-RESOLVED))
    )
    (asserts! (get resolved market) ERR-MARKET-NOT-RESOLVED)
    (asserts! (not (get claimed position)) ERR-ALREADY-CLAIMED)
    
    (let
      (
        (prediction-correct (>= actual-score (get mood-threshold market)))
        (winning-pool (if prediction-correct (get positive-pool market) (get negative-pool market)))
        (user-winning-amount (if prediction-correct (get positive-amount position) (get negative-amount position)))
        (total-pool (get total-pool market))
        (payout (if (> winning-pool u0)
          (/ (* user-winning-amount total-pool) winning-pool)
          u0))
      )
      (asserts! (> payout u0) ERR-INSUFFICIENT-BALANCE)
      
      ;; Mark as claimed
      (map-set user-positions
        { market-id: market-id, user: tx-sender }
        (merge position { claimed: true })
      )
      
      ;; Transfer winnings
      (try! (as-contract (stx-transfer? payout tx-sender tx-sender)))
      
      ;; Update user stats
      (update-user-winnings tx-sender payout prediction-correct)
      
      (ok payout)
    )
  )
)

;; Submit mood data (oracle function)
(define-public (submit-mood-data
  (timestamp uint)
  (biometric-score uint)
  (sentiment-score uint)
  (weather-impact int)
  (event-impact int))
  (let
    (
      (oracle (unwrap! (var-get authorized-oracle) ERR-ORACLE-ERROR))
      (composite-score (calculate-composite-mood biometric-score sentiment-score weather-impact event-impact))
    )
    (asserts! (is-eq tx-sender oracle) ERR-UNAUTHORIZED)
    (asserts! (and (<= biometric-score MOOD-SCALE-MAX) (<= sentiment-score MOOD-SCALE-MAX)) ERR-INVALID-PREDICTION)
    
    (map-set mood-data
      { timestamp: timestamp }
      {
        biometric-score: biometric-score,
        sentiment-score: sentiment-score,
        weather-impact: weather-impact,
        event-impact: event-impact,
        composite-score: composite-score,
        data-sources: u15 ;; all sources available
      }
    )
    (ok composite-score)
  )
)

;; Withdraw from mental health fund (authorized personnel only)
(define-public (withdraw-mental-health-fund (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (<= amount (var-get mental-health-fund)) ERR-INSUFFICIENT-BALANCE)
    
    (var-set mental-health-fund (- (var-get mental-health-fund) amount))
    (try! (as-contract (stx-transfer? amount tx-sender recipient)))
    (ok amount)
  )
)

;; Emergency pause/unpause
(define-public (toggle-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set contract-paused (not (var-get contract-paused)))
    (ok (var-get contract-paused))
  )
)

;; read only functions

;; Get market information
(define-read-only (get-market (market-id uint))
  (map-get? markets { market-id: market-id })
)

;; Get user position in a market
(define-read-only (get-user-position (market-id uint) (user principal))
  (map-get? user-positions { market-id: market-id, user: user })
)

;; Get user statistics
(define-read-only (get-user-stats (user principal))
  (map-get? user-stats { user: user })
)

;; Get mood data for a timestamp
(define-read-only (get-mood-data (timestamp uint))
  (map-get? mood-data { timestamp: timestamp })
)

;; Get mental health fund balance
(define-read-only (get-mental-health-fund)
  (var-get mental-health-fund)
)

;; Get current market odds
(define-read-only (get-market-odds (market-id uint))
  (match (map-get? markets { market-id: market-id })
    market (let
      (
        (positive-pool (get positive-pool market))
        (negative-pool (get negative-pool market))
        (total-pool (get total-pool market))
      )
      (if (> total-pool u0)
        (ok {
          positive-odds: (/ (* positive-pool u100) total-pool),
          negative-odds: (/ (* negative-pool u100) total-pool)
        })
        (ok { positive-odds: u50, negative-odds: u50 })
      )
    )
    ERR-INVALID-MARKET
  )
)

;; Check if market can be resolved
(define-read-only (can-resolve-market (market-id uint))
  (match (map-get? markets { market-id: market-id })
    market (ok (and 
      (>= (get-block) (get closes-at market))
      (< (get-block) (get resolves-at market))
      (not (get resolved market))
    ))
    ERR-INVALID-MARKET
  )
)

;; Get composite mood score for a time range
(define-read-only (get-composite-mood-score (end-timestamp uint))
  (let
    (
      (recent-data (map-get? mood-data { timestamp: end-timestamp }))
    )
    (match recent-data
      data (ok (get composite-score data))
      ERR-ORACLE-ERROR
    )
  )
)

;; private functions

;; Calculate composite mood score
(define-private (calculate-composite-mood (biometric uint) (sentiment uint) (weather int) (events int))
  (let
    (
      (base-score (/ (+ biometric sentiment) u2))
      (weather-adjusted (if (>= weather 0)
        (let ((candidate (+ base-score (to-uint weather))))
          (if (<= candidate MOOD-SCALE-MAX) candidate MOOD-SCALE-MAX))
        (if (>= base-score (to-uint (- 0 weather)))
          (- base-score (to-uint (- 0 weather)))
          u0)))
      (final-score (if (>= events 0)
        (let ((candidate2 (+ weather-adjusted (to-uint events))))
          (if (<= candidate2 MOOD-SCALE-MAX) candidate2 MOOD-SCALE-MAX))
        (if (>= weather-adjusted (to-uint (- 0 events)))
          (- weather-adjusted (to-uint (- 0 events)))
          u0)))
    )
    final-score
  )
)

;; Temporary helper for block height to satisfy Clarinet environment
(define-private (get-block)
  (+ u0 u0)
)

;; Update user statistics
(define-private (update-user-stats (user principal) (bet-amount uint) (contribution uint))
  (let
    (
      (current-stats (default-to 
        { total-bets: u0, successful-predictions: u0, total-winnings: u0, mental-health-contributions: u0 }
        (map-get? user-stats { user: user })))
    )
    (map-set user-stats
      { user: user }
      (merge current-stats {
        total-bets: (+ (get total-bets current-stats) u1),
        mental-health-contributions: (+ (get mental-health-contributions current-stats) contribution)
      })
    )
  )
)

;; Update user winnings
(define-private (update-user-winnings (user principal) (winnings uint) (correct bool))
  (let
    (
      (current-stats (unwrap-panic (map-get? user-stats { user: user })))
    )
    (map-set user-stats
      { user: user }
      (merge current-stats {
        successful-predictions: (if correct 
          (+ (get successful-predictions current-stats) u1)
          (get successful-predictions current-stats)),
        total-winnings: (+ (get total-winnings current-stats) winnings)
      })
    )
  )
)