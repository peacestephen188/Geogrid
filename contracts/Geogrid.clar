(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_LOCATION_NOT_FOUND (err u101))
(define-constant ERR_INVALID_COORDINATES (err u102))
(define-constant ERR_LOCATION_EXISTS (err u103))
(define-constant ERR_INVALID_CATEGORY (err u104))
(define-constant ERR_INSUFFICIENT_STAKE (err u105))
(define-constant ERR_ALREADY_VOTED (err u106))
(define-constant ERR_CANNOT_VOTE_OWN_LOCATION (err u107))
(define-constant ERR_REVIEW_NOT_FOUND (err u108))
(define-constant ERR_ALREADY_REVIEWED (err u109))
(define-constant ERR_CANNOT_REVIEW_OWN_LOCATION (err u110))
(define-constant ERR_INVALID_RATING (err u111))
(define-constant ERR_REVIEW_TOO_LONG (err u112))
(define-constant ERR_INSUFFICIENT_REVIEW_STAKE (err u113))
(define-constant ERR_REVIEW_ALREADY_MODERATED (err u114))
(define-constant ERR_CANNOT_MODERATE_OWN_REVIEW (err u115))

(define-constant MIN_STAKE u1000000)
(define-constant REVIEW_STAKE u100000)
(define-constant REVIEW_REWARD u50000)
(define-constant MODERATION_REWARD u25000)
(define-constant MAX_REVIEW_LENGTH u500)
(define-constant REWARD_AMOUNT u500000)
(define-constant MAX_LATITUDE 90000000)
(define-constant MIN_LATITUDE -90000000)
(define-constant MAX_LONGITUDE 180000000)
(define-constant MIN_LONGITUDE -180000000)

(define-data-var location-counter uint u0)
(define-data-var total-locations uint u0)
(define-data-var contract-balance uint u0)
(define-data-var review-counter uint u0)
(define-data-var total-reviews uint u0)
(define-data-var moderation-pool uint u0)

(define-map locations
  { location-id: uint }
  {
    creator: principal,
    latitude: int,
    longitude: int,
    category: (string-ascii 20),
    name: (string-ascii 50),
    description: (string-ascii 200),
    stake: uint,
    upvotes: uint,
    downvotes: uint,
    verified: bool,
    created-at: uint
  }
)

(define-map user-votes
  { voter: principal, location-id: uint }
  { vote-type: (string-ascii 10) }
)

(define-map user-contributions
  { user: principal }
  { 
    locations-added: uint,
    total-votes: uint,
    reputation: uint
  }
)

(define-map location-categories
  { category: (string-ascii 20) }
  { active: bool }
)

(define-map coordinate-index
  { lat-grid: int, lon-grid: int }
  { location-ids: (list 100 uint) }
)

(define-map location-reviews
  { review-id: uint }
  {
    location-id: uint,
    reviewer: principal,
    overall-rating: uint,
    cleanliness-rating: uint,
    service-rating: uint,
    value-rating: uint,
    review-text: (string-ascii 500),
    photo-hashes: (list 5 (string-ascii 64)),
    helpful-votes: uint,
    spam-reports: uint,
    created-at: uint,
    stake: uint,
    reward-earned: uint,
    moderated: bool,
    moderation-result: (string-ascii 20)
  }
)

(define-map location-review-stats
  { location-id: uint }
  {
    total-reviews: uint,
    average-rating: uint,
    rating-sum: uint,
    review-ids: (list 50 uint)
  }
)

(define-map user-review-history
  { reviewer: principal, location-id: uint }
  { review-id: uint }
)

(define-map review-moderation
  { review-id: uint, moderator: principal }
  {
    decision: (string-ascii 20),
    reason: (string-ascii 100),
    reward-claimed: bool,
    created-at: uint
  }
)

(define-map user-review-stats
  { user: principal }
  {
    total-reviews: uint,
    average-rating-given: uint,
    helpful-votes-received: uint,
    spam-reports-received: uint,
    review-reputation: uint
  }
)

(define-public (initialize-categories)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (map-set location-categories { category: "restaurant" } { active: true })
    (map-set location-categories { category: "shop" } { active: true })
    (map-set location-categories { category: "park" } { active: true })
    (map-set location-categories { category: "hospital" } { active: true })
    (map-set location-categories { category: "school" } { active: true })
    (map-set location-categories { category: "gas-station" } { active: true })
    (map-set location-categories { category: "atm" } { active: true })
    (map-set location-categories { category: "parking" } { active: true })
    (map-set location-categories { category: "other" } { active: true })
    (ok true)
  )
)

(define-private (is-valid-coordinates (lat int) (lon int))
  (and 
    (>= lat MIN_LATITUDE)
    (<= lat MAX_LATITUDE)
    (>= lon MIN_LONGITUDE)
    (<= lon MAX_LONGITUDE)
  )
)

(define-private (is-valid-category (category (string-ascii 20)))
  (match (map-get? location-categories { category: category })
    category-data (get active category-data)
    false
  )
)

(define-private (get-grid-coordinates (lat int) (lon int))
  {
    lat-grid: (/ lat 1000000),
    lon-grid: (/ lon 1000000)
  }
)

(define-private (update-coordinate-index (location-id uint) (lat int) (lon int))
  (let (
    (grid-coords (get-grid-coordinates lat lon))
    (current-list (default-to (list) (get location-ids (map-get? coordinate-index grid-coords))))
  )
    (ok (map-set coordinate-index 
      grid-coords
      { location-ids: (unwrap! (as-max-len? (append current-list location-id) u100) (err u999)) }
    ))
  )
)

(define-public (add-location 
  (latitude int) 
  (longitude int) 
  (category (string-ascii 20)) 
  (name (string-ascii 50)) 
  (description (string-ascii 200))
)
  (let (
    (location-id (+ (var-get location-counter) u1))
    (stake-amount MIN_STAKE)
  )
    (asserts! (is-valid-coordinates latitude longitude) ERR_INVALID_COORDINATES)
    (asserts! (is-valid-category category) ERR_INVALID_CATEGORY)
    (asserts! (>= (stx-get-balance tx-sender) stake-amount) ERR_INSUFFICIENT_STAKE)
    
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    (map-set locations
      { location-id: location-id }
      {
        creator: tx-sender,
        latitude: latitude,
        longitude: longitude,
        category: category,
        name: name,
        description: description,
        stake: stake-amount,
        upvotes: u0,
        downvotes: u0,
        verified: false,
        created-at: stacks-block-height
      }
    )
    
    (unwrap-panic (update-coordinate-index location-id latitude longitude))
    
    (let (
      (current-contributions (default-to { locations-added: u0, total-votes: u0, reputation: u0 } 
                                        (map-get? user-contributions { user: tx-sender })))
    )
      (map-set user-contributions
        { user: tx-sender }
        {
          locations-added: (+ (get locations-added current-contributions) u1),
          total-votes: (get total-votes current-contributions),
          reputation: (+ (get reputation current-contributions) u10)
        }
      )
    )
    
    (var-set location-counter location-id)
    (var-set total-locations (+ (var-get total-locations) u1))
    (var-set contract-balance (+ (var-get contract-balance) stake-amount))
    
    (ok location-id)
  )
)

(define-public (vote-location (location-id uint) (vote-type (string-ascii 10)))
  (let (
    (location-data (unwrap! (map-get? locations { location-id: location-id }) ERR_LOCATION_NOT_FOUND))
    (voter tx-sender)
  )
    (asserts! (not (is-eq voter (get creator location-data))) ERR_CANNOT_VOTE_OWN_LOCATION)
    (asserts! (is-none (map-get? user-votes { voter: voter, location-id: location-id })) ERR_ALREADY_VOTED)
    (asserts! (or (is-eq vote-type "upvote") (is-eq vote-type "downvote")) (err u108))
    
    (map-set user-votes
      { voter: voter, location-id: location-id }
      { vote-type: vote-type }
    )
    
    (let (
      (new-upvotes (if (is-eq vote-type "upvote") 
                      (+ (get upvotes location-data) u1) 
                      (get upvotes location-data)))
      (new-downvotes (if (is-eq vote-type "downvote") 
                        (+ (get downvotes location-data) u1) 
                        (get downvotes location-data)))
      (new-verified (>= new-upvotes u3))
    )
      (map-set locations
        { location-id: location-id }
        (merge location-data {
          upvotes: new-upvotes,
          downvotes: new-downvotes,
          verified: new-verified
        })
      )
      
      (let (
        (current-contributions (default-to { locations-added: u0, total-votes: u0, reputation: u0 } 
                                          (map-get? user-contributions { user: voter })))
      )
        (map-set user-contributions
          { user: voter }
          {
            locations-added: (get locations-added current-contributions),
            total-votes: (+ (get total-votes current-contributions) u1),
            reputation: (+ (get reputation current-contributions) u1)
          }
        )
      )
      
      (if (and new-verified (not (get verified location-data)))
        (begin
          (try! (as-contract (stx-transfer? REWARD_AMOUNT tx-sender (get creator location-data))))
          (var-set contract-balance (- (var-get contract-balance) REWARD_AMOUNT))
          (ok "location-verified-reward-sent")
        )
        (ok "vote-recorded")
      )
    )
  )
)

(define-read-only (get-location (location-id uint))
  (map-get? locations { location-id: location-id })
)

(define-read-only (get-locations-in-area (lat-center int) (lon-center int) (radius int))
  (let (
    (grid-coords (get-grid-coordinates lat-center lon-center))
  )
    (match (map-get? coordinate-index grid-coords)
      location-data (get location-ids location-data)
      (list)
    )
  )
)

(define-read-only (get-user-contributions (user principal))
  (map-get? user-contributions { user: user })
)

(define-read-only (get-user-vote (voter principal) (location-id uint))
  (map-get? user-votes { voter: voter, location-id: location-id })
)

(define-read-only (get-total-locations)
  (var-get total-locations)
)

(define-read-only (get-contract-stats)
  {
    total-locations: (var-get total-locations),
    contract-balance: (var-get contract-balance),
    min-stake: MIN_STAKE,
    reward-amount: REWARD_AMOUNT
  }
)

(define-read-only (is-location-verified (location-id uint))
  (match (map-get? locations { location-id: location-id })
    location-data (get verified location-data)
    false
  )
)

(define-public (add-category (category (string-ascii 20)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (map-set location-categories { category: category } { active: true })
    (ok true)
  )
)

(define-public (deactivate-category (category (string-ascii 20)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (map-set location-categories { category: category } { active: false })
    (ok true)
  )
)

(define-read-only (get-category-status (category (string-ascii 20)))
  (map-get? location-categories { category: category })
)

(define-private (is-valid-rating (rating uint))
  (and (>= rating u1) (<= rating u5))
)

(define-private (calculate-average-rating (current-sum uint) (current-count uint) (new-rating uint))
  (/ (+ current-sum new-rating) (+ current-count u1))
)

(define-private (update-location-review-stats (location-id uint) (review-id uint) (rating uint))
  (let (
    (current-stats (default-to 
      { total-reviews: u0, average-rating: u0, rating-sum: u0, review-ids: (list) }
      (map-get? location-review-stats { location-id: location-id })
    ))
    (new-rating-sum (+ (get rating-sum current-stats) rating))
    (new-total-reviews (+ (get total-reviews current-stats) u1))
    (new-review-ids (unwrap! (as-max-len? (append (get review-ids current-stats) review-id) u50) (err u999)))
  )
    (map-set location-review-stats
      { location-id: location-id }
      {
        total-reviews: new-total-reviews,
        average-rating: (/ new-rating-sum new-total-reviews),
        rating-sum: new-rating-sum,
        review-ids: new-review-ids
      }
    )
    (ok true)
  )
)

(define-private (update-user-review-stats (user principal) (rating uint))
  (let (
    (current-stats (default-to 
      { total-reviews: u0, average-rating-given: u0, helpful-votes-received: u0, spam-reports-received: u0, review-reputation: u0 }
      (map-get? user-review-stats { user: user })
    ))
    (new-total-reviews (+ (get total-reviews current-stats) u1))
    (new-rating-sum (+ (* (get average-rating-given current-stats) (get total-reviews current-stats)) rating))
  )
    (map-set user-review-stats
      { user: user }
      {
        total-reviews: new-total-reviews,
        average-rating-given: (/ new-rating-sum new-total-reviews),
        helpful-votes-received: (get helpful-votes-received current-stats),
        spam-reports-received: (get spam-reports-received current-stats),
        review-reputation: (+ (get review-reputation current-stats) u5)
      }
    )
    (ok true)
  )
)

(define-public (submit-review 
  (location-id uint) 
  (overall-rating uint) 
  (cleanliness-rating uint) 
  (service-rating uint) 
  (value-rating uint) 
  (review-text (string-ascii 500)) 
  (photo-hashes (list 5 (string-ascii 64)))
)
  (let (
    (review-id (+ (var-get review-counter) u1))
    (reviewer tx-sender)
    (location-data (unwrap! (map-get? locations { location-id: location-id }) ERR_LOCATION_NOT_FOUND))
  )
    (asserts! (is-none (map-get? user-review-history { reviewer: reviewer, location-id: location-id })) ERR_ALREADY_REVIEWED)
    (asserts! (not (is-eq reviewer (get creator location-data))) ERR_CANNOT_REVIEW_OWN_LOCATION)
    (asserts! (is-valid-rating overall-rating) ERR_INVALID_RATING)
    (asserts! (is-valid-rating cleanliness-rating) ERR_INVALID_RATING)
    (asserts! (is-valid-rating service-rating) ERR_INVALID_RATING)
    (asserts! (is-valid-rating value-rating) ERR_INVALID_RATING)
    (asserts! (<= (len review-text) MAX_REVIEW_LENGTH) ERR_REVIEW_TOO_LONG)
    (asserts! (>= (stx-get-balance reviewer) REVIEW_STAKE) ERR_INSUFFICIENT_REVIEW_STAKE)
    
    (try! (stx-transfer? REVIEW_STAKE reviewer (as-contract tx-sender)))
    
    (map-set location-reviews
      { review-id: review-id }
      {
        location-id: location-id,
        reviewer: reviewer,
        overall-rating: overall-rating,
        cleanliness-rating: cleanliness-rating,
        service-rating: service-rating,
        value-rating: value-rating,
        review-text: review-text,
        photo-hashes: photo-hashes,
        helpful-votes: u0,
        spam-reports: u0,
        created-at: stacks-block-height,
        stake: REVIEW_STAKE,
        reward-earned: u0,
        moderated: false,
        moderation-result: ""
      }
    )
    
    (map-set user-review-history
      { reviewer: reviewer, location-id: location-id }
      { review-id: review-id }
    )
    
    (unwrap-panic (update-location-review-stats location-id review-id overall-rating))
    (unwrap-panic (update-user-review-stats reviewer overall-rating))
    
    (var-set review-counter review-id)
    (var-set total-reviews (+ (var-get total-reviews) u1))
    (var-set contract-balance (+ (var-get contract-balance) REVIEW_STAKE))
    
    (ok review-id)
  )
)

(define-public (moderate-review (review-id uint) (decision (string-ascii 20)) (reason (string-ascii 100)))
  (let (
    (review-data (unwrap! (map-get? location-reviews { review-id: review-id }) ERR_REVIEW_NOT_FOUND))
    (moderator tx-sender)
  )
    (asserts! (not (is-eq moderator (get reviewer review-data))) ERR_CANNOT_MODERATE_OWN_REVIEW)
    (asserts! (not (get moderated review-data)) ERR_REVIEW_ALREADY_MODERATED)
    (asserts! (or (is-eq decision "approved") (is-eq decision "spam") (is-eq decision "inappropriate")) (err u999))
    
    (map-set review-moderation
      { review-id: review-id, moderator: moderator }
      {
        decision: decision,
        reason: reason,
        reward-claimed: false,
        created-at: stacks-block-height
      }
    )
    
    (map-set location-reviews
      { review-id: review-id }
      (merge review-data {
        moderated: true,
        moderation-result: decision
      })
    )
    
    (if (is-eq decision "approved")
      (begin
        (try! (as-contract (stx-transfer? REVIEW_REWARD tx-sender (get reviewer review-data))))
        (try! (as-contract (stx-transfer? MODERATION_REWARD tx-sender moderator)))
        (var-set contract-balance (- (var-get contract-balance) (+ REVIEW_REWARD MODERATION_REWARD)))
        (var-set moderation-pool (+ (var-get moderation-pool) MODERATION_REWARD))
        (map-set location-reviews
          { review-id: review-id }
          (merge (unwrap-panic (map-get? location-reviews { review-id: review-id })) {
            reward-earned: REVIEW_REWARD
          })
        )
        (ok "review-approved-rewards-distributed")
      )
      (if (is-eq decision "spam")
        (begin
          (var-set moderation-pool (+ (var-get moderation-pool) (get stake review-data)))
          (try! (as-contract (stx-transfer? MODERATION_REWARD tx-sender moderator)))
          (ok "review-marked-spam-stake-forfeited")
        )
        (ok "review-moderated")
      )
    )
  )
)

(define-public (vote-review-helpful (review-id uint))
  (let (
    (review-data (unwrap! (map-get? location-reviews { review-id: review-id }) ERR_REVIEW_NOT_FOUND))
    (voter tx-sender)
  )
    (asserts! (not (is-eq voter (get reviewer review-data))) ERR_CANNOT_VOTE_OWN_LOCATION)
    
    (map-set location-reviews
      { review-id: review-id }
      (merge review-data {
        helpful-votes: (+ (get helpful-votes review-data) u1)
      })
    )
    
    (let (
      (reviewer-stats (default-to 
        { total-reviews: u0, average-rating-given: u0, helpful-votes-received: u0, spam-reports-received: u0, review-reputation: u0 }
        (map-get? user-review-stats { user: (get reviewer review-data) })
      ))
    )
      (map-set user-review-stats
        { user: (get reviewer review-data) }
        (merge reviewer-stats {
          helpful-votes-received: (+ (get helpful-votes-received reviewer-stats) u1),
          review-reputation: (+ (get review-reputation reviewer-stats) u2)
        })
      )
    )
    
    (ok true)
  )
)

(define-public (report-review-spam (review-id uint))
  (let (
    (review-data (unwrap! (map-get? location-reviews { review-id: review-id }) ERR_REVIEW_NOT_FOUND))
    (reporter tx-sender)
  )
    (asserts! (not (is-eq reporter (get reviewer review-data))) ERR_CANNOT_VOTE_OWN_LOCATION)
    
    (map-set location-reviews
      { review-id: review-id }
      (merge review-data {
        spam-reports: (+ (get spam-reports review-data) u1)
      })
    )
    
    (let (
      (reviewer-stats (default-to 
        { total-reviews: u0, average-rating-given: u0, helpful-votes-received: u0, spam-reports-received: u0, review-reputation: u0 }
        (map-get? user-review-stats { user: (get reviewer review-data) })
      ))
    )
      (map-set user-review-stats
        { user: (get reviewer review-data) }
        (merge reviewer-stats {
          spam-reports-received: (+ (get spam-reports-received reviewer-stats) u1),
          review-reputation: (if (>= (get review-reputation reviewer-stats) u1) 
                                (- (get review-reputation reviewer-stats) u1) 
                                u0)
        })
      )
    )
    
    (ok true)
  )
)

(define-read-only (get-review (review-id uint))
  (map-get? location-reviews { review-id: review-id })
)

(define-read-only (get-location-reviews (location-id uint))
  (match (map-get? location-review-stats { location-id: location-id })
    stats (get review-ids stats)
    (list)
  )
)

(define-read-only (get-location-review-stats (location-id uint))
  (map-get? location-review-stats { location-id: location-id })
)

(define-read-only (get-user-review-stats (user principal))
  (map-get? user-review-stats { user: user })
)

(define-read-only (get-user-review-for-location (user principal) (location-id uint))
  (map-get? user-review-history { reviewer: user, location-id: location-id })
)

(define-read-only (get-review-moderation (review-id uint) (moderator principal))
  (map-get? review-moderation { review-id: review-id, moderator: moderator })
)

(define-read-only (get-review-system-stats)
  {
    total-reviews: (var-get total-reviews),
    review-stake: REVIEW_STAKE,
    review-reward: REVIEW_REWARD,
    moderation-reward: MODERATION_REWARD,
    moderation-pool: (var-get moderation-pool)
  }
)