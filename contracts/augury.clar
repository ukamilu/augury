;; Enhanced error constants
(define-constant ERR-INVALID-PRINCIPAL u404)
(define-constant ERR-INVALID-AMOUNT u405)
(define-constant ERR-ZERO-BALANCE u406)
(define-constant ERR-POOL-OVERFLOW u408)
(define-constant ERR-INVALID-TIER u701)
(define-constant ERR-REWARD-CALCULATION-FAILED u700)
(define-constant ERR-REWARD-DISTRIBUTION-FAILED u702)
(define-constant ERR-INVALID-INPUT u703)
(define-constant ERR-BATCH-VALIDATION-FAILED u704)

;; New error constants for security improvements
(define-constant ERR-DOUBLE-STAKE u800)
(define-constant ERR-CONTRACT-PAUSED u801)
(define-constant ERR-DEADLINE-PASSED u802)
(define-constant ERR-INSUFFICIENT-BALANCE u803)
(define-constant ERR-TRANSFER-FAILED u804)
(define-constant ERR-STATE-CORRUPTION u805)
(define-constant ERR-CIRCUIT-BREAKER u806)
(define-constant ERR-REENTRANCY u807)
(define-constant ERR-DATA-VALIDATION u808)

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

;; Security and error handling state
(define-data-var circuit-breaker-triggered bool false)
(define-data-var last-error-block uint u0)
(define-data-var error-count uint u0)
(define-data-var max-errors-per-block uint u5)
(define-data-var reentrancy-guard bool false)

;; Emergency state tracking
(define-map failed-operations 
    { operation-id: uint }
    { user: principal, amount: uint, operation-type: (string-ascii 32), block-height: uint })

(define-data-var next-operation-id uint u0)

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

;; COMPREHENSIVE VALIDATION STRUCTURE
;; This eliminates LSP warnings by validating everything upfront
(define-private (validate-prediction-complete (choice bool) (amount uint))
    (let ((validated-amount (begin
            (asserts! (>= amount MIN-STAKE-AMOUNT) (err ERR-INVALID-AMOUNT))
            (asserts! (<= amount MAX-STAKE-AMOUNT) (err ERR-INVALID-AMOUNT))
            (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
            amount))
          (validated-choice choice)
          (calculated-fee (/ (* validated-amount (var-get platform-fee)) u1000))
          (calculated-stake (- validated-amount calculated-fee)))
        (begin
            ;; Validate all calculated values immediately
            (asserts! (>= calculated-stake MIN-STAKE-AMOUNT) (err ERR-INVALID-AMOUNT))
            (asserts! (<= calculated-fee validated-amount) (err ERR-INVALID-AMOUNT))
            (asserts! (> calculated-stake u0) (err ERR-INVALID-AMOUNT))
            
            ;; Return fully validated structure
            (ok {
                choice: validated-choice,
                original-amount: validated-amount,
                fee: calculated-fee,
                stake-amount: calculated-stake
            }))))

;; Safe data extraction functions with explicit validation
(define-private (safe-get-choice (pred {choice: bool, amount: uint}))
    (let ((choice (get choice pred)))
        (ok choice)))

(define-private (safe-get-amount (pred {choice: bool, amount: uint}))
    (let ((amount (get amount pred)))
        (begin
            (asserts! (>= amount u0) (err ERR-DATA-VALIDATION))
            (asserts! (<= amount MAX-STAKE-AMOUNT) (err ERR-DATA-VALIDATION))
            (asserts! (>= amount MIN-STAKE-AMOUNT) (err ERR-DATA-VALIDATION))
            (ok amount))))

(define-private (safe-get-user-stat (stats {total-staked: uint, total-won: uint, predictions-made: uint, successful-predictions: uint}) (field (string-ascii 32)))
    (begin
        (if (is-eq field "total-staked")
            (let ((value (get total-staked stats)))
                (begin
                    (asserts! (>= value u0) (err ERR-DATA-VALIDATION))
                    (ok value)))
            (if (is-eq field "total-won")
                (let ((value (get total-won stats)))
                    (begin
                        (asserts! (>= value u0) (err ERR-DATA-VALIDATION))
                        (ok value)))
                (if (is-eq field "predictions-made")
                    (let ((value (get predictions-made stats)))
                        (begin
                            (asserts! (>= value u0) (err ERR-DATA-VALIDATION))
                            (ok value)))
                    (if (is-eq field "successful-predictions")
                        (let ((value (get successful-predictions stats)))
                            (begin
                                (asserts! (>= value u0) (err ERR-DATA-VALIDATION))
                                (ok value)))
                        (err ERR-DATA-VALIDATION)))))))

;; Security functions
(define-private (check-reentrancy)
    (begin
        (asserts! (not (var-get reentrancy-guard)) (err ERR-REENTRANCY))
        (var-set reentrancy-guard true)
        (ok true)))

(define-private (clear-reentrancy)
    (begin
        (var-set reentrancy-guard false)
        (ok true)))

(define-private (check-circuit-breaker)
    (begin
        (if (var-get circuit-breaker-triggered)
            (err ERR-CIRCUIT-BREAKER)
            (ok true))))

(define-private (handle-error (error-code uint))
    (let ((current-block stacks-block-height)
          (last-error (var-get last-error-block))
          (current-errors (var-get error-count)))
        (begin
            (if (> current-block last-error)
                (begin
                    (var-set error-count u1)
                    (var-set last-error-block current-block))
                (var-set error-count (+ current-errors u1)))
            
            (if (>= (var-get error-count) (var-get max-errors-per-block))
                (var-set circuit-breaker-triggered true)
                false)
            
            (unwrap-panic (clear-reentrancy))
            (err error-code))))

(define-private (validate-contract-state)
    (let ((true-pool (var-get total-true-pool))
          (false-pool (var-get total-false-pool)))
        (begin
            (asserts! (>= true-pool u0) (handle-error ERR-STATE-CORRUPTION))
            (asserts! (>= false-pool u0) (handle-error ERR-STATE-CORRUPTION))
            (asserts! (<= (+ true-pool false-pool) MAX-STAKE-AMOUNT) (handle-error ERR-STATE-CORRUPTION))
            (ok true))))

(define-private (validate-principal (address principal))
    (begin
        (asserts! (is-standard address) (err ERR-INVALID-PRINCIPAL))
        (asserts! (not (is-eq contract-caller address)) (err ERR-INVALID-PRINCIPAL))
        (ok true)))

(define-private (validate-pool-update (current-pool uint) (amount uint))
    (begin
        (asserts! (<= (+ current-pool amount) MAX-STAKE-AMOUNT) (err ERR-POOL-OVERFLOW))
        (asserts! (>= current-pool u0) (err ERR-INVALID-AMOUNT))
        (asserts! (>= amount u0) (err ERR-INVALID-AMOUNT))
        (ok true)))

(define-private (safe-transfer-with-recovery (amount uint) (sender principal) (recipient principal))
    (begin
        ;; Explicit validation at usage point
        (asserts! (>= amount u0) (err ERR-INVALID-AMOUNT))
        (asserts! (<= amount MAX-STAKE-AMOUNT) (err ERR-INVALID-AMOUNT))
        
        (match (stx-transfer? amount sender recipient)
            success (ok true)
            error (begin
                (let ((operation-id (var-get next-operation-id)))
                    (map-set failed-operations
                        { operation-id: operation-id }
                        { 
                            user: sender, 
                            amount: amount, 
                            operation-type: "transfer",
                            block-height: stacks-block-height 
                        })
                    (var-set next-operation-id (+ operation-id u1)))
                (handle-error ERR-TRANSFER-FAILED)))))

;; FIXED: Predict function with comprehensive upfront validation
(define-public (predict (choice bool) (amount uint))
    (begin
        ;; CHECKS - All validations first
        (try! (check-reentrancy))
        (try! (check-circuit-breaker))
        (try! (validate-contract-state))
        (asserts! (not (var-get contract-paused)) (handle-error ERR-CONTRACT-PAUSED))
        (asserts! (< stacks-block-height (var-get prediction-deadline)) (handle-error ERR-DEADLINE-PASSED))
        (asserts! (is-none (map-get? stakes {user: tx-sender, prediction: choice})) (handle-error ERR-DOUBLE-STAKE))
        
        ;; Explicit input validation before comprehensive validation
        (asserts! (>= amount MIN-STAKE-AMOUNT) (handle-error ERR-INVALID-AMOUNT))
        (asserts! (<= amount MAX-STAKE-AMOUNT) (handle-error ERR-INVALID-AMOUNT))
        (asserts! (> amount u0) (handle-error ERR-INVALID-AMOUNT))
        
        ;; COMPREHENSIVE VALIDATION: Validate everything upfront in one step
        (let ((validated-prediction (try! (validate-prediction-complete choice amount))))
            (let ((validated-choice (get choice validated-prediction))
                  (validated-amount (get original-amount validated-prediction))
                  (validated-fee (get fee validated-prediction))
                  (validated-stake (get stake-amount validated-prediction)))
                
                ;; Additional explicit assertions at usage points
                (let ((current-pool (if validated-choice (var-get total-true-pool) (var-get total-false-pool))))
                    (begin
                        ;; Explicit validation of all values before use
                        (asserts! (>= validated-stake MIN-STAKE-AMOUNT) (handle-error ERR-INVALID-AMOUNT))
                        (asserts! (>= validated-amount MIN-STAKE-AMOUNT) (handle-error ERR-INVALID-AMOUNT))
                        (asserts! (>= validated-fee u0) (handle-error ERR-INVALID-AMOUNT))
                        (try! (validate-pool-update current-pool validated-stake))
                        
                        ;; EFFECTS - Update state using explicitly validated values
                        (if validated-choice
                            (var-set total-true-pool (+ (var-get total-true-pool) validated-stake))
                            (var-set total-false-pool (+ (var-get total-false-pool) validated-stake)))
                        
                        (map-set stakes 
                            {user: tx-sender, prediction: validated-choice} 
                            {amount: validated-stake})
                        
                        ;; Update user statistics with explicit validation
                        (let ((current-stats (get-user-stats tx-sender)))
                            (let ((current-total-staked (try! (safe-get-user-stat current-stats "total-staked")))
                                  (current-total-won (try! (safe-get-user-stat current-stats "total-won")))
                                  (current-predictions-made (try! (safe-get-user-stat current-stats "predictions-made")))
                                  (current-successful-predictions (try! (safe-get-user-stat current-stats "successful-predictions"))))
                                (begin
                                    ;; Explicit validation before arithmetic
                                    (asserts! (>= current-total-staked u0) (handle-error ERR-DATA-VALIDATION))
                                    (asserts! (>= validated-stake u0) (handle-error ERR-DATA-VALIDATION))
                                    
                                    (map-set user-statistics 
                                        {user: tx-sender}
                                        {
                                            total-staked: (+ current-total-staked validated-stake),
                                            total-won: current-total-won,
                                            predictions-made: (+ current-predictions-made u1),
                                            successful-predictions: current-successful-predictions
                                        }))))
                        
                        ;; INTERACTIONS - External calls with explicit validation
                        (try! (safe-transfer-with-recovery validated-amount tx-sender (as-contract tx-sender)))
                        
                        (try! (if (> validated-fee u0)
                            (as-contract (safe-transfer-with-recovery validated-fee tx-sender (var-get treasury)))
                            (ok true)))
                        
                        (try! (update-analytics-secure validated-choice validated-stake))
                        
                        (unwrap-panic (clear-reentrancy))
                        (ok true)))))))

;; Enhanced claim function with security improvements
(define-public (claim)
    (begin
        (try! (check-reentrancy))
        (try! (check-circuit-breaker))
        (try! (validate-contract-state))
        
        (let ((result (unwrap! (var-get outcome) (handle-error u6))))
            (let ((winning-prediction (is-eq true result)))
                (let ((stake (unwrap! (map-get? stakes {user: tx-sender, prediction: winning-prediction}) (handle-error u7))))
                    (let ((user-stake (get amount stake))
                          (winning-pool (if winning-prediction (var-get total-true-pool) (var-get total-false-pool)))
                          (losing-pool (if winning-prediction (var-get total-false-pool) (var-get total-true-pool))))
                        (begin
                            ;; CHECKS with explicit validation
                            (asserts! (> winning-pool u0) (handle-error ERR-ZERO-BALANCE))
                            (asserts! (> user-stake u0) (handle-error ERR-INVALID-AMOUNT))
                            (asserts! (>= user-stake MIN-STAKE-AMOUNT) (handle-error ERR-INVALID-AMOUNT))
                            
                            ;; EFFECTS - Remove stake first
                            (map-delete stakes {user: tx-sender, prediction: winning-prediction})
                            
                            ;; Update user statistics with validation
                            (let ((current-stats (get-user-stats tx-sender)))
                                (let ((current-total-staked (try! (safe-get-user-stat current-stats "total-staked")))
                                      (current-total-won (try! (safe-get-user-stat current-stats "total-won")))
                                      (current-predictions-made (try! (safe-get-user-stat current-stats "predictions-made")))
                                      (current-successful-predictions (try! (safe-get-user-stat current-stats "successful-predictions"))))
                                    (map-set user-statistics 
                                        {user: tx-sender}
                                        {
                                            total-staked: current-total-staked,
                                            total-won: (+ current-total-won user-stake),
                                            predictions-made: current-predictions-made,
                                            successful-predictions: (+ current-successful-predictions u1)
                                        })))
                            
                            ;; INTERACTIONS - Calculate and transfer rewards with validation
                            (let ((reward-share (/ (* user-stake PRECISION) winning-pool))
                                  (total-reward (/ (* losing-pool reward-share) PRECISION))
                                  (final-payout (+ user-stake total-reward)))
                                (begin
                                    ;; Explicit validation of calculations
                                    (asserts! (>= final-payout user-stake) (handle-error ERR-REWARD-CALCULATION-FAILED))
                                    (asserts! (<= final-payout MAX-STAKE-AMOUNT) (handle-error ERR-REWARD-CALCULATION-FAILED))
                                    
                                    (try! (as-contract (safe-transfer-with-recovery final-payout tx-sender tx-sender)))
                                    (unwrap-panic (clear-reentrancy))
                                    (ok total-reward))))))))))

;; FIXED: Batch prediction with comprehensive validation
(define-public (batch-predict (predictions (list 200 {choice: bool, amount: uint})))
    (begin
        (try! (check-reentrancy))
        (try! (check-circuit-breaker))
        (try! (validate-contract-state))
        (asserts! (not (var-get contract-paused)) (handle-error ERR-CONTRACT-PAUSED))
        (asserts! (< stacks-block-height (var-get prediction-deadline)) (handle-error ERR-DEADLINE-PASSED))
        
        ;; Validate batch parameters
        (let ((prediction-count (len predictions)))
            (begin
                (asserts! (> prediction-count u0) (handle-error ERR-INVALID-INPUT))
                (asserts! (<= prediction-count u200) (handle-error ERR-INVALID-INPUT))
                
                ;; Process with comprehensive validation
                (let ((batch-id (var-get next-batch-id))
                      (initial-true-pool (var-get total-true-pool))
                      (initial-false-pool (var-get total-false-pool)))
                    
                    (match (process-batch-comprehensive predictions)
                        success (begin
                            (map-set batch-operations
                                { batch-id: batch-id }
                                { predictions: predictions, status: true })
                            
                            (var-set next-batch-id (+ batch-id u1))
                            (unwrap-panic (clear-reentrancy))
                            (ok batch-id))
                        error (begin
                            (var-set total-true-pool initial-true-pool)
                            (var-set total-false-pool initial-false-pool)
                            (handle-error error))))))))

;; FIXED: Comprehensive batch processing
(define-private (process-batch-comprehensive (predictions (list 200 {choice: bool, amount: uint})))
    (fold process-single-comprehensive predictions (ok u0)))

;; FIXED: Single prediction processing with comprehensive validation
(define-private (process-single-comprehensive (pred {choice: bool, amount: uint}) (previous (response uint uint)))
    (begin
        (try! previous)
        
        ;; Extract with explicit validation
        (let ((raw-choice (get choice pred))
              (raw-amount (get amount pred)))
            (begin
                ;; Explicit validation of extracted data
                (asserts! (>= raw-amount MIN-STAKE-AMOUNT) (err ERR-INVALID-AMOUNT))
                (asserts! (<= raw-amount MAX-STAKE-AMOUNT) (err ERR-INVALID-AMOUNT))
                (asserts! (> raw-amount u0) (err ERR-INVALID-AMOUNT))
                
                ;; Use comprehensive validation
                (let ((validated-prediction (try! (validate-prediction-complete raw-choice raw-amount))))
                    (let ((final-choice (get choice validated-prediction))
                          (final-stake (get stake-amount validated-prediction)))
                        (begin
                            ;; Additional explicit validation
                            (asserts! (>= final-stake MIN-STAKE-AMOUNT) (err ERR-INVALID-AMOUNT))
                            
                            (try! (validate-pool-update 
                                (if final-choice (var-get total-true-pool) (var-get total-false-pool)) 
                                final-stake))
                            
                            (if final-choice
                                (var-set total-true-pool (+ (var-get total-true-pool) final-stake))
                                (var-set total-false-pool (+ (var-get total-false-pool) final-stake)))
                            
                            (ok final-stake))))))))

;; FIXED: Analytics update with comprehensive validation
(define-private (update-analytics-secure (choice bool) (amount uint))
    (let ((current-day (/ stacks-block-height u144)))
        (begin
            ;; Explicit validation at function start
            (asserts! (>= amount MIN-STAKE-AMOUNT) (err ERR-INVALID-AMOUNT))
            (asserts! (<= amount MAX-STAKE-AMOUNT) (err ERR-INVALID-AMOUNT))
            (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
            
            (match (map-get? market-analytics {day: current-day})
                analytics (merge-analytics-comprehensive current-day analytics choice amount)
                (default-analytics-comprehensive current-day choice amount)))))

(define-private (merge-analytics-comprehensive (current-day uint) (current-analytics {total-volume: uint, unique-users: uint, true-predictions: uint, false-predictions: uint, average-stake: uint}) (choice bool) (amount uint))
    (let ((current-volume (get total-volume current-analytics))
          (new-total-volume (+ current-volume amount))
          (current-true (get true-predictions current-analytics))
          (current-false (get false-predictions current-analytics))
          (new-predictions (+ (+ current-true current-false) u1)))
        (begin
            ;; Explicit validation of calculations
            (asserts! (>= new-total-volume current-volume) (err ERR-INVALID-AMOUNT))
            (asserts! (> new-predictions u0) (err ERR-INVALID-AMOUNT))
            (asserts! (<= new-total-volume MAX-STAKE-AMOUNT) (err ERR-INVALID-AMOUNT))
            
            (map-set market-analytics {day: current-day}
                {
                    total-volume: new-total-volume,
                    unique-users: (get unique-users current-analytics),
                    true-predictions: (+ current-true (if choice u1 u0)),
                    false-predictions: (+ current-false (if choice u0 u1)),
                    average-stake: (/ new-total-volume new-predictions)
                })
            (ok true))))

(define-private (default-analytics-comprehensive (current-day uint) (choice bool) (amount uint))
    (begin
        ;; Explicit validation
        (asserts! (>= amount u0) (err ERR-INVALID-AMOUNT))
        (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
        
        (map-set market-analytics {day: current-day}
            {
                total-volume: amount,
                unique-users: u1,
                true-predictions: (if choice u1 u0),
                false-predictions: (if choice u0 u1),
                average-stake: amount
            })
        (ok true)))

;; Recovery functions for admin
(define-public (reset-circuit-breaker)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403))
        (var-set circuit-breaker-triggered false)
        (var-set error-count u0)
        (ok true)))

(define-public (recover-failed-operation (operation-id uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403))
        (asserts! (< operation-id (var-get next-operation-id)) (err ERR-INVALID-INPUT))
        
        (let ((operation (unwrap! (map-get? failed-operations { operation-id: operation-id }) (err u404))))
            (begin
                (try! (as-contract (stx-transfer? 
                    (get amount operation) 
                    tx-sender 
                    (get user operation))))
                
                ;; Safe to delete after validation
                (map-delete failed-operations { operation-id: operation-id })
                (ok true)))))

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
        (asserts! (<= new-fee u100) (err u4))
        (var-set platform-fee new-fee)
        (ok true)))

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

;; FIXED: Set staking tier with comprehensive validation
(define-public (set-staking-tier (tier uint) (minimum-stake uint) (multiplier uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403))
        (asserts! (< tier u100) (err ERR-INVALID-TIER))
        
        ;; Comprehensive validation of all inputs
        (asserts! (>= minimum-stake MIN-STAKE-AMOUNT) (err ERR-INVALID-AMOUNT))
        (asserts! (<= minimum-stake MAX-STAKE-AMOUNT) (err ERR-INVALID-AMOUNT))
        (asserts! (> minimum-stake u0) (err ERR-INVALID-AMOUNT))
        (asserts! (<= multiplier MAX-MULTIPLIER) (err ERR-INVALID-INPUT))
        (asserts! (> multiplier u0) (err ERR-INVALID-INPUT))
        
        (map-set staking-tiers
            { tier: tier }
            { minimum-stake: minimum-stake, reward-multiplier: multiplier })
        (ok true)))

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

(define-read-only (get-system-health)
    {
        circuit-breaker: (var-get circuit-breaker-triggered),
        error-count: (var-get error-count),
        last-error-block: (var-get last-error-block),
        contract-paused: (var-get contract-paused),
        reentrancy-guard: (var-get reentrancy-guard)
    })

(define-read-only (get-failed-operation (operation-id uint))
    (map-get? failed-operations { operation-id: operation-id }))
