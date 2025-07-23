(define-constant ERR-INVALID-PRINCIPAL u404)
(define-constant ERR-INVALID-AMOUNT u405)
(define-constant ERR-ZERO-BALANCE u406)
(define-constant ERR-POOL-OVERFLOW u408)
(define-constant ERR-INVALID-TIER u701)
(define-constant ERR-REWARD-CALCULATION-FAILED u700)
(define-constant ERR-REWARD-DISTRIBUTION-FAILED u701)
(define-constant ERR-INVALID-INPUT u702)
(define-constant ERR-BATCH-VALIDATION-FAILED u703)

(define-constant MIN-STAKE-AMOUNT u1000)
(define-constant MAX-STAKE-AMOUNT u1000000000000)
(define-constant MAX-MULTIPLIER u200)
(define-constant PRECISION u1000000)
(define-constant REWARD-CYCLE u144)  ;; Daily rewards

(define-trait ft-trait
    (
        (transfer (principal principal uint) (response bool uint))
        (get-balance (principal) (response uint uint))
    )
)

;; Contract state variables
(define-data-var outcome (optional bool) none)
(define-map stakes {user: principal, prediction: bool} {amount: uint})
(define-data-var contract-owner principal tx-sender)
(define-data-var staking-rewards uint u0)
(define-data-var platform-fee uint u10) ;; 1% represented as 10/1000
(define-data-var treasury principal tx-sender)
(define-data-var total-true-pool uint u0)
(define-data-var total-false-pool uint u0)
(define-data-var contract-paused bool false)
(define-data-var prediction-deadline uint u0)
(define-data-var next-category-id uint u0)
(define-data-var next-batch-id uint u0)

;; Maps
(define-map categories
    { category-id: uint }
    { name: (string-ascii 64), active: bool })

(define-map category-outcomes
    { category-id: uint }
    { outcome: (optional bool), deadline: uint })

(define-map staking-tiers
    { tier: uint }
    { minimum-stake: uint, reward-multiplier: uint })

(define-map user-statistics
    { user: principal }
    { total-staked: uint,
      total-won: uint,
      predictions-made: uint,
      successful-predictions: uint })

(define-map unique-users { user: principal } { exists: bool })

(define-map market-analytics
    { day: uint }
    { total-volume: uint,
      unique-users: uint,
      true-predictions: uint,
      false-predictions: uint,
      average-stake: uint })

(define-map batch-operations 
    { batch-id: uint }
    { predictions: (list 200 {choice: bool, amount: uint}), status: bool })

;; Enhanced input validation functions
(define-private (validate-principal (address principal))
    (begin
        (asserts! (is-standard address) (err ERR-INVALID-PRINCIPAL))
        (asserts! (not (is-eq contract-caller address)) (err ERR-INVALID-PRINCIPAL))
        (ok true)))

(define-private (validate-amount (amount uint))
    (begin
        (asserts! (>= amount MIN-STAKE-AMOUNT) (err ERR-INVALID-AMOUNT))
        (asserts! (<= amount MAX-STAKE-AMOUNT) (err ERR-INVALID-AMOUNT))
        (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
        (ok true)))

(define-private (validate-pool-update (current-pool uint) (amount uint))
    (begin
        (asserts! (<= (+ current-pool amount) MAX-STAKE-AMOUNT) (err ERR-POOL-OVERFLOW))
        (asserts! (>= current-pool u0) (err ERR-INVALID-AMOUNT))
        (ok true)))

(define-private (validate-amount-safe (amount uint))
    (begin
        (try! (validate-amount amount))
        (ok amount)))

(define-private (validate-pool-safe (pool uint) (amount uint))
    (begin
        (try! (validate-pool-update pool amount))
        (ok (+ pool amount))))

(define-private (validate-transfer (amount uint) (sender principal) (recipient principal))
    (begin
        (asserts! (not (is-eq sender recipient)) (err ERR-INVALID-PRINCIPAL))
        (try! (validate-amount-safe amount))
        (try! (validate-principal sender))
        (try! (validate-principal recipient))
        (ok true)))

(define-private (safe-transfer (amount uint) (sender principal) (recipient principal))
    (begin
        (try! (validate-transfer amount sender recipient))
        (try! (stx-transfer? amount sender recipient))
        (ok true)))

;; Secure prediction validation that validates individual components
(define-private (validate-prediction-components (choice bool) (amount uint))
    (begin
        ;; Validate amount is within bounds
        (asserts! (>= amount MIN-STAKE-AMOUNT) (err ERR-INVALID-AMOUNT))
        (asserts! (<= amount MAX-STAKE-AMOUNT) (err ERR-INVALID-AMOUNT))
        (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
        ;; Return validated components
        (ok {choice: choice, amount: amount})))

;; Secure prediction validation for batch operations
(define-private (validate-prediction-secure (pred {choice: bool, amount: uint}))
    (validate-prediction-components (get choice pred) (get amount pred)))

(define-private (validate-prediction-fold-secure (pred {choice: bool, amount: uint}) (previous (response bool uint)))
    (begin
        (try! previous) ;; Ensure previous validation passed
        (try! (validate-prediction-secure pred))
        (ok true)))

(define-private (validate-batch-secure (predictions (list 200 {choice: bool, amount: uint})))
    (let ((prediction-count (len predictions)))
        (begin
            (asserts! (> prediction-count u0) (err ERR-INVALID-INPUT))
            (asserts! (<= prediction-count u200) (err ERR-INVALID-INPUT))
            ;; Validate each prediction in the batch
            (try! (fold validate-prediction-fold-secure predictions (ok true)))
            (ok predictions))))

;; Main prediction function with enhanced security
(define-public (predict (choice bool) (amount uint))
    (begin
        (asserts! (not (var-get contract-paused)) (err u8))
        (asserts! (< stacks-block-height (var-get prediction-deadline)) (err u9))
        
        ;; Validate inputs
        (let ((validated-amount (try! (validate-amount-safe amount))))
        
            (let (
                (fee (/ (* validated-amount (var-get platform-fee)) u1000))
                (stake-amount (- validated-amount fee))
            )
            (begin
                ;; Validate stake amount after fee deduction
                (asserts! (>= stake-amount MIN-STAKE-AMOUNT) (err ERR-INVALID-AMOUNT))
                
                (try! (validate-pool-update 
                    (if choice 
                        (var-get total-true-pool) 
                        (var-get total-false-pool)) 
                    stake-amount))
                
                (if choice
                    (var-set total-true-pool (+ (var-get total-true-pool) stake-amount))
                    (var-set total-false-pool (+ (var-get total-false-pool) stake-amount)))
                
                (try! (stx-transfer? validated-amount tx-sender (as-contract tx-sender)))
                (try! (stx-transfer? fee (as-contract tx-sender) (var-get treasury)))
                
                (map-set stakes 
                    {user: tx-sender, prediction: choice} 
                    {amount: stake-amount})
                
                ;; Update analytics securely
                (try! (update-analytics-secure choice stake-amount))
                
                (ok true))))))

;; Fixed batch prediction function with proper validation flow
(define-public (batch-predict (predictions (list 200 {choice: bool, amount: uint})))
    (begin
        (asserts! (not (var-get contract-paused)) (err u8))
        (asserts! (< stacks-block-height (var-get prediction-deadline)) (err u9))
        
        ;; Validate batch first, then process with validated data only
        (let ((validated-predictions (try! (validate-batch-secure predictions))))
            (let ((batch-id (var-get next-batch-id)))
                
                ;; Process each validated prediction securely
                (begin
                    (try! (process-batch-predictions-secure validated-predictions))
                    
                    (map-set batch-operations
                        { batch-id: batch-id }
                        { predictions: validated-predictions, status: true })
                    
                    (var-set next-batch-id (+ batch-id u1))
                    (ok batch-id))))))

;; Fixed batch processing helper with proper data flow
(define-private (process-batch-predictions-secure (validated-predictions (list 200 {choice: bool, amount: uint})))
    (fold process-single-prediction-secure validated-predictions (ok u0)))

;; Fixed function with proper validation flow to address LSP warnings
(define-private (process-single-prediction-secure (pred {choice: bool, amount: uint}) (previous (response uint uint)))
    (begin
        (try! previous) ;; Ensure previous operations succeeded
        
        ;; Extract and immediately validate the components to satisfy LSP data flow analysis
        (let ((validated-pred (try! (validate-prediction-secure pred))))
            (let ((choice (get choice validated-pred))
                  (amount (get amount validated-pred)))
                
                ;; Now use the validated data
                (let (
                    (fee (/ (* amount (var-get platform-fee)) u1000))
                    (stake-amount (- amount fee))
                )
                    (begin
                        (asserts! (>= stake-amount MIN-STAKE-AMOUNT) (err ERR-INVALID-AMOUNT))
                        
                        (try! (validate-pool-update 
                            (if choice 
                                (var-get total-true-pool) 
                                (var-get total-false-pool)) 
                            stake-amount))
                        
                        (if choice
                            (var-set total-true-pool (+ (var-get total-true-pool) stake-amount))
                            (var-set total-false-pool (+ (var-get total-false-pool) stake-amount)))
                        
                        (ok stake-amount)))))))

;; Secure analytics update
(define-private (update-analytics-secure (choice bool) (amount uint))
    (let ((current-day (/ stacks-block-height u144)))
        (begin
            ;; Validate inputs
            (let ((validated-amount (try! (validate-amount-safe amount))))
            
                (match (map-get? market-analytics {day: current-day})
                    analytics (merge-analytics-secure current-day analytics choice validated-amount)
                    (default-analytics-secure current-day choice validated-amount))))))

(define-private (merge-analytics-secure (current-day uint) (current-analytics {total-volume: uint, unique-users: uint, true-predictions: uint, false-predictions: uint, average-stake: uint}) (choice bool) (validated-amount uint))
    (let ((new-total-volume (+ (get total-volume current-analytics) validated-amount))
          (new-predictions (+ (+ (get true-predictions current-analytics) (get false-predictions current-analytics)) u1)))
        (begin
            ;; Validate calculations don't overflow
            (asserts! (>= new-total-volume (get total-volume current-analytics)) (err ERR-INVALID-AMOUNT))
            (asserts! (> new-predictions u0) (err ERR-INVALID-AMOUNT))
            
            (map-set market-analytics {day: current-day}
                {
                    total-volume: new-total-volume,
                    unique-users: (get unique-users current-analytics),
                    true-predictions: (+ (get true-predictions current-analytics) (if choice u1 u0)),
                    false-predictions: (+ (get false-predictions current-analytics) (if choice u0 u1)),
                    average-stake: (/ new-total-volume new-predictions)
                })
            (ok true))))

(define-private (default-analytics-secure (current-day uint) (choice bool) (validated-amount uint))
    (begin
        (map-set market-analytics {day: current-day}
            {
                total-volume: validated-amount,
                unique-users: u1,
                true-predictions: (if choice u1 u0),
                false-predictions: (if choice u0 u1),
                average-stake: validated-amount
            })
        (ok true)))

;; Contract management functions
(define-public (set-contract-owner (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403))
        (try! (validate-principal new-owner))
        (asserts! (not (is-eq new-owner (as-contract tx-sender))) (err ERR-INVALID-PRINCIPAL))
        (var-set contract-owner new-owner)
        (ok true)))

(define-public (resolve (result bool))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403))
        (asserts! (is-none (var-get outcome)) (err u2))
        (var-set outcome (some result))
        (ok true)))

(define-public (set-platform-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403))
        (asserts! (<= new-fee u100) (err u4)) ;; Max 10% fee
        (var-set platform-fee new-fee)
        (ok true)))

(define-public (claim)
    (let (
        (result (unwrap! (var-get outcome) (err u6)))
        (winning-prediction (is-eq true result))
        (stake (unwrap! (map-get? stakes 
            {user: tx-sender, prediction: winning-prediction}) (err u7))))
        (begin
            (let (
                (user-stake (get amount stake))
                (winning-pool (if winning-prediction
                                (var-get total-true-pool)
                                (var-get total-false-pool)))
                (losing-pool (if winning-prediction
                               (var-get total-false-pool)
                               (var-get total-true-pool))))
                (asserts! (> winning-pool u0) (err ERR-ZERO-BALANCE))
                (let (
                    (reward-share (/ (* user-stake PRECISION) winning-pool))
                    (total-reward (/ (* losing-pool reward-share) PRECISION)))
                    (begin
                        (map-delete stakes 
                            {user: tx-sender, prediction: winning-prediction})
                        (try! (stx-transfer? (+ user-stake total-reward) 
                                           (as-contract tx-sender) 
                                           tx-sender))
                        (ok total-reward)))))))

;; Emergency and admin functions
(define-public (set-contract-pause (pause-state bool))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403))
        (var-set contract-paused pause-state)
        (ok true)))

(define-public (set-prediction-deadline (target-block-height uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403))
        (asserts! (> target-block-height stacks-block-height) (err u404))
        (var-set prediction-deadline target-block-height)
        (ok true)))

(define-public (create-category (name (string-ascii 64)) (deadline uint))
    (let ((category-id (var-get next-category-id)))
        (begin
            (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403))
            (asserts! (> (len name) u0) (err u404))
            (asserts! (> deadline stacks-block-height) (err u404))
            (map-set categories
                { category-id: category-id }
                { name: name, active: true })
            (map-set category-outcomes
                { category-id: category-id }
                { outcome: none, deadline: deadline })
            (var-set next-category-id (+ category-id u1))
            (ok category-id))))

;; Fixed set-staking-tier with proper validation flow to address LSP warnings
(define-public (set-staking-tier (tier uint) (minimum-stake uint) (multiplier uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403))
        (asserts! (<= multiplier u200) (err u10)) ;; Max 2x multiplier
        (asserts! (< tier u100) (err ERR-INVALID-TIER)) ;; Limit tier to reasonable range
        
        ;; Validate all inputs immediately and use validated values
        (let ((validated-minimum-stake (try! (validate-amount-safe minimum-stake))))
            (let ((validated-multiplier (begin
                    (asserts! (<= multiplier MAX-MULTIPLIER) (err ERR-INVALID-INPUT))
                    (asserts! (> multiplier u0) (err ERR-INVALID-INPUT))
                    multiplier)))
                (begin
                    (map-set staking-tiers
                        { tier: tier }
                        { minimum-stake: validated-minimum-stake, reward-multiplier: validated-multiplier })
                    (ok true))))))

(define-public (emergency-withdraw (token <ft-trait>))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403))
        (asserts! (var-get contract-paused) (err u11))
        (let ((token-balance (try! (contract-call? token get-balance (as-contract tx-sender)))))
            (asserts! (> token-balance u0) (err u12))
            (try! (contract-call? token transfer
                (as-contract tx-sender)
                (var-get treasury)
                token-balance)))
        (ok true)))

(define-public (distribute-staking-rewards)
    (let ((current-cycle (/ stacks-block-height REWARD-CYCLE)))
        (begin
            (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403))
            (match (calculate-and-distribute-rewards current-cycle)
                success (ok success)
                error (err error)))))

;; Helper functions
(define-private (calculate-and-distribute-rewards (cycle uint))
    (let ((total-rewards (* cycle u1000))
          (active-stakers (get-active-stakers)))
        (begin
            (asserts! (> total-rewards u0) (err ERR-REWARD-CALCULATION-FAILED))
            (var-set staking-rewards (+ (var-get staking-rewards) total-rewards))
            (if (> active-stakers u0)
                (ok total-rewards)
                (err ERR-REWARD-DISTRIBUTION-FAILED)))))

(define-private (get-active-stakers)
    (var-get total-true-pool))

;; Read-only functions
(define-read-only (get-pools)
    {
        true-pool: (var-get total-true-pool),
        false-pool: (var-get total-false-pool)
    })

(define-read-only (get-user-stake (user principal) (prediction bool))
    (map-get? stakes {user: user, prediction: prediction}))

(define-read-only (get-contract-status)
    (ok {
        paused: (var-get contract-paused),
        deadline: (var-get prediction-deadline),
        fee: (var-get platform-fee),
        resolved: (is-some (var-get outcome))
    }))

(define-read-only (get-user-stats (user principal))
    (default-to
        { total-staked: u0, total-won: u0, 
          predictions-made: u0, successful-predictions: u0 }
        (map-get? user-statistics { user: user })))