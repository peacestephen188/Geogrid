(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_LOCATION_NOT_FOUND (err u101))
(define-constant ERR_INVALID_COORDINATES (err u102))
(define-constant ERR_LOCATION_EXISTS (err u103))
(define-constant ERR_INVALID_CATEGORY (err u104))
(define-constant ERR_INSUFFICIENT_STAKE (err u105))
(define-constant ERR_ALREADY_VOTED (err u106))
(define-constant ERR_CANNOT_VOTE_OWN_LOCATION (err u107))

(define-constant MIN_STAKE u1000000)
(define-constant REWARD_AMOUNT u500000)
(define-constant MAX_LATITUDE 90000000)
(define-constant MIN_LATITUDE -90000000)
(define-constant MAX_LONGITUDE 180000000)
(define-constant MIN_LONGITUDE -180000000)

(define-data-var location-counter uint u0)
(define-data-var total-locations uint u0)
(define-data-var contract-balance uint u0)

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