;; LocationEvents Contract - Temporary events at verified locations with RSVP and attendance rewards
;; Enables location owners to create events and community members to participate with incentives

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u500))
(define-constant ERR_NOT_FOUND (err u501))
(define-constant ERR_ALREADY_EXISTS (err u502))
(define-constant ERR_INVALID_INPUT (err u503))
(define-constant ERR_EVENT_FULL (err u504))
(define-constant ERR_EVENT_EXPIRED (err u505))
(define-constant ERR_ALREADY_RSVP (err u506))
(define-constant ERR_NOT_RSVP (err u507))
(define-constant ERR_EVENT_NOT_STARTED (err u508))
(define-constant ERR_INSUFFICIENT_STAKE (err u509))

;; Reference to main Geogrid contract
(define-constant GEOGRID_CONTRACT .Geogrid)

;; Event constants
(define-constant EVENT_CREATION_STAKE u200000) ;; 0.2 STX
(define-constant RSVP_STAKE u50000) ;; 0.05 STX
(define-constant ATTENDANCE_REWARD u75000) ;; 0.075 STX
(define-constant MAX_EVENT_DURATION u1440) ;; ~10 days in blocks
(define-constant MIN_EVENT_DURATION u144) ;; ~1 day in blocks

;; Data variables
(define-data-var contract-admin principal CONTRACT_OWNER)
(define-data-var next-event-id uint u1)
(define-data-var total-events uint u0)
(define-data-var event-reward-pool uint u0)

;; Location events
(define-map location-events uint {
    organizer: principal,
    location-id: uint,
    title: (string-ascii 100),
    description: (string-ascii 300),
    event-type: (string-ascii 32), ;; meetup, sale, demo, celebration, etc.
    start-time: uint, ;; block height
    end-time: uint, ;; block height
    max-attendees: uint,
    current-rsvps: uint,
    actual-attendance: uint,
    stake: uint,
    reward-per-attendee: uint,
    created-at: uint,
    active: bool
})

;; User RSVPs for events
(define-map event-rsvps { event-id: uint, user: principal } {
    rsvp-time: uint,
    attended: bool,
    reward-claimed: bool,
    stake: uint
})

;; Event attendance tracking
(define-map event-attendance uint {
    total-rsvps: uint,
    confirmed-attendance: uint,
    rewards-distributed: uint,
    event-completed: bool
})

;; User event statistics
(define-map user-event-stats principal {
    events-created: uint,
    events-attended: uint,
    total-event-rewards: uint,
    event-reputation: uint
})

;; Admin functions
(define-public (set-admin (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-admin)) ERR_UNAUTHORIZED)
        (var-set contract-admin new-admin)
        (ok true)
    )
)

;; Create event at verified location
(define-public (create-event 
    (location-id uint)
    (title (string-ascii 100))
    (description (string-ascii 300))
    (event-type (string-ascii 32))
    (start-time uint)
    (end-time uint)
    (max-attendees uint)
    (reward-per-attendee uint))
    (let (
        (event-id (var-get next-event-id))
        (location-data (unwrap! (contract-call? GEOGRID_CONTRACT get-location location-id) ERR_NOT_FOUND))
        (total-cost (+ EVENT_CREATION_STAKE (* reward-per-attendee max-attendees)))
    )
        ;; Validate location and permissions
        (asserts! (is-eq tx-sender (get creator location-data)) ERR_UNAUTHORIZED)
        (asserts! (get verified location-data) ERR_UNAUTHORIZED)
        
        ;; Validate event parameters
        (asserts! (> start-time stacks-block-height) ERR_INVALID_INPUT)
        (asserts! (> end-time start-time) ERR_INVALID_INPUT)
        (asserts! (<= (- end-time start-time) MAX_EVENT_DURATION) ERR_INVALID_INPUT)
        (asserts! (>= (- end-time start-time) MIN_EVENT_DURATION) ERR_INVALID_INPUT)
        (asserts! (> max-attendees u0) ERR_INVALID_INPUT)
        (asserts! (>= (stx-get-balance tx-sender) total-cost) ERR_INSUFFICIENT_STAKE)
        
        ;; Transfer stake and reward pool
        (try! (stx-transfer? total-cost tx-sender (as-contract tx-sender)))
        
        ;; Create event
        (map-set location-events event-id {
            organizer: tx-sender,
            location-id: location-id,
            title: title,
            description: description,
            event-type: event-type,
            start-time: start-time,
            end-time: end-time,
            max-attendees: max-attendees,
            current-rsvps: u0,
            actual-attendance: u0,
            stake: EVENT_CREATION_STAKE,
            reward-per-attendee: reward-per-attendee,
            created-at: stacks-block-height,
            active: true
        })
        
        ;; Initialize attendance tracking
        (map-set event-attendance event-id {
            total-rsvps: u0,
            confirmed-attendance: u0,
            rewards-distributed: u0,
            event-completed: false
        })
        
        ;; Update user stats
        (update-organizer-stats tx-sender)
        
        (var-set next-event-id (+ event-id u1))
        (var-set total-events (+ (var-get total-events) u1))
        (var-set event-reward-pool (+ (var-get event-reward-pool) (* reward-per-attendee max-attendees)))
        
        (ok event-id)
    )
)

;; RSVP to an event
(define-public (rsvp-event (event-id uint))
    (let (
        (event-data (unwrap! (map-get? location-events event-id) ERR_NOT_FOUND))
        (attendance-data (unwrap! (map-get? event-attendance event-id) ERR_NOT_FOUND))
        (rsvp-key { event-id: event-id, user: tx-sender })
    )
        ;; Validate event and user eligibility
        (asserts! (get active event-data) ERR_EVENT_EXPIRED)
        (asserts! (< stacks-block-height (get start-time event-data)) ERR_EVENT_NOT_STARTED)
        (asserts! (< (get current-rsvps event-data) (get max-attendees event-data)) ERR_EVENT_FULL)
        (asserts! (not (is-eq tx-sender (get organizer event-data))) ERR_UNAUTHORIZED)
        (asserts! (is-none (map-get? event-rsvps rsvp-key)) ERR_ALREADY_RSVP)
        (asserts! (>= (stx-get-balance tx-sender) RSVP_STAKE) ERR_INSUFFICIENT_STAKE)
        
        ;; Take RSVP stake
        (try! (stx-transfer? RSVP_STAKE tx-sender (as-contract tx-sender)))
        
        ;; Record RSVP
        (map-set event-rsvps rsvp-key {
            rsvp-time: stacks-block-height,
            attended: false,
            reward-claimed: false,
            stake: RSVP_STAKE
        })
        
        ;; Update event stats
        (map-set location-events event-id 
            (merge event-data { current-rsvps: (+ (get current-rsvps event-data) u1) }))
        
        (map-set event-attendance event-id 
            (merge attendance-data { total-rsvps: (+ (get total-rsvps attendance-data) u1) }))
        
        (ok true)
    )
)

;; Verify attendance and distribute rewards (organizer only)
(define-public (verify-attendance (event-id uint) (attendee principal))
    (let (
        (event-data (unwrap! (map-get? location-events event-id) ERR_NOT_FOUND))
        (attendance-data (unwrap! (map-get? event-attendance event-id) ERR_NOT_FOUND))
        (rsvp-key { event-id: event-id, user: attendee })
        (rsvp-data (unwrap! (map-get? event-rsvps rsvp-key) ERR_NOT_RSVP))
    )
        ;; Validate permissions and timing
        (asserts! (is-eq tx-sender (get organizer event-data)) ERR_UNAUTHORIZED)
        (asserts! (>= stacks-block-height (get start-time event-data)) ERR_EVENT_NOT_STARTED)
        (asserts! (not (get attended rsvp-data)) ERR_ALREADY_EXISTS)
        
        ;; Mark attendance and distribute reward
        (map-set event-rsvps rsvp-key 
            (merge rsvp-data { attended: true, reward-claimed: true }))
        
        ;; Transfer attendance reward + return stake
        (let ((total-reward (+ (get reward-per-attendee event-data) RSVP_STAKE)))
            (try! (as-contract (stx-transfer? total-reward tx-sender attendee)))
            (var-set event-reward-pool (- (var-get event-reward-pool) (get reward-per-attendee event-data)))
        )
        
        ;; Update event statistics
        (map-set location-events event-id 
            (merge event-data { actual-attendance: (+ (get actual-attendance event-data) u1) }))
        
        (map-set event-attendance event-id 
            (merge attendance-data { 
                confirmed-attendance: (+ (get confirmed-attendance attendance-data) u1),
                rewards-distributed: (+ (get rewards-distributed attendance-data) (get reward-per-attendee event-data))
            }))
        
        ;; Update user stats
        (update-attendee-stats attendee (get reward-per-attendee event-data))
        
        (ok true)
    )
)

;; Complete event and return unused rewards (organizer only)
(define-public (complete-event (event-id uint))
    (let (
        (event-data (unwrap! (map-get? location-events event-id) ERR_NOT_FOUND))
        (attendance-data (unwrap! (map-get? event-attendance event-id) ERR_NOT_FOUND))
    )
        (asserts! (is-eq tx-sender (get organizer event-data)) ERR_UNAUTHORIZED)
        (asserts! (>= stacks-block-height (get end-time event-data)) ERR_INVALID_INPUT)
        (asserts! (not (get event-completed attendance-data)) ERR_ALREADY_EXISTS)
        
        ;; Calculate unused rewards
        (let ((unused-rewards (* (get reward-per-attendee event-data) 
                                (- (get max-attendees event-data) (get actual-attendance event-data))))
              (organizer-stake-return (get stake event-data)))
            
            ;; Return unused rewards and stake to organizer
            (if (> unused-rewards u0)
                (try! (as-contract (stx-transfer? unused-rewards tx-sender (get organizer event-data))))
                true
            )
            
            (try! (as-contract (stx-transfer? organizer-stake-return tx-sender (get organizer event-data))))
            
            ;; Mark event as completed
            (map-set event-attendance event-id 
                (merge attendance-data { event-completed: true }))
            
            (map-set location-events event-id 
                (merge event-data { active: false }))
            
            (ok true)
        )
    )
)

;; Cancel event before start time
(define-public (cancel-event (event-id uint))
    (let ((event-data (unwrap! (map-get? location-events event-id) ERR_NOT_FOUND)))
        (asserts! (is-eq tx-sender (get organizer event-data)) ERR_UNAUTHORIZED)
        (asserts! (< stacks-block-height (get start-time event-data)) ERR_EVENT_NOT_STARTED)
        (asserts! (get active event-data) ERR_EVENT_EXPIRED)
        
        ;; Deactivate event
        (map-set location-events event-id 
            (merge event-data { active: false }))
        
        ;; Return organizer stake and reward pool
        (let ((total-return (+ (get stake event-data) 
                              (* (get reward-per-attendee event-data) (get max-attendees event-data)))))
            (try! (as-contract (stx-transfer? total-return tx-sender (get organizer event-data))))
            (var-set event-reward-pool (- (var-get event-reward-pool) 
                                        (* (get reward-per-attendee event-data) (get max-attendees event-data))))
        )
        
        (ok true)
    )
)

;; Private helper functions
(define-private (update-organizer-stats (organizer principal))
    (let ((current-stats (default-to 
            { events-created: u0, events-attended: u0, total-event-rewards: u0, event-reputation: u0 }
            (map-get? user-event-stats organizer))))
        (map-set user-event-stats organizer {
            events-created: (+ (get events-created current-stats) u1),
            events-attended: (get events-attended current-stats),
            total-event-rewards: (get total-event-rewards current-stats),
            event-reputation: (+ (get event-reputation current-stats) u10)
        })
        true
    )
)

(define-private (update-attendee-stats (attendee principal) (reward uint))
    (let ((current-stats (default-to 
            { events-created: u0, events-attended: u0, total-event-rewards: u0, event-reputation: u0 }
            (map-get? user-event-stats attendee))))
        (map-set user-event-stats attendee {
            events-created: (get events-created current-stats),
            events-attended: (+ (get events-attended current-stats) u1),
            total-event-rewards: (+ (get total-event-rewards current-stats) reward),
            event-reputation: (+ (get event-reputation current-stats) u5)
        })
        true
    )
)

;; Read-only functions
(define-read-only (get-event (event-id uint))
    (map-get? location-events event-id)
)

(define-read-only (get-event-rsvp (event-id uint) (user principal))
    (map-get? event-rsvps { event-id: event-id, user: user })
)

(define-read-only (get-event-attendance-stats (event-id uint))
    (map-get? event-attendance event-id)
)

(define-read-only (get-user-event-stats (user principal))
    (map-get? user-event-stats user)
)

(define-read-only (is-event-active (event-id uint))
    (match (map-get? location-events event-id)
        event-data (and 
            (get active event-data)
            (< stacks-block-height (get end-time event-data))
        )
        false
    )
)

(define-read-only (can-rsvp-event (event-id uint) (user principal))
    (match (map-get? location-events event-id)
        event-data (and
            (get active event-data)
            (< stacks-block-height (get start-time event-data))
            (< (get current-rsvps event-data) (get max-attendees event-data))
            (not (is-eq user (get organizer event-data)))
            (is-none (map-get? event-rsvps { event-id: event-id, user: user }))
        )
        false
    )
)

(define-read-only (get-upcoming-events-at-location (location-id uint))
    ;; Simplified - in production would maintain location-to-events index
    ;; Returns event IDs for events at specific location that are still upcoming
    (list)
)

(define-read-only (get-event-summary (event-id uint))
    (match (map-get? location-events event-id)
        event-data (match (map-get? event-attendance event-id)
            attendance-data (some {
                title: (get title event-data),
                location-id: (get location-id event-data),
                organizer: (get organizer event-data),
                start-time: (get start-time event-data),
                end-time: (get end-time event-data),
                max-attendees: (get max-attendees event-data),
                current-rsvps: (get current-rsvps event-data),
                actual-attendance: (get actual-attendance event-data),
                active: (get active event-data),
                completed: (get event-completed attendance-data)
            })
            none
        )
        none
    )
)

(define-read-only (get-contract-stats)
    {
        contract-admin: (var-get contract-admin),
        total-events: (var-get total-events),
        next-event-id: (var-get next-event-id),
        event-reward-pool: (var-get event-reward-pool),
        event-creation-stake: EVENT_CREATION_STAKE,
        rsvp-stake: RSVP_STAKE,
        attendance-reward: ATTENDANCE_REWARD
    }
)