;; Digital Publishing Content Manager Contract
;; Manages digital content metadata, ownership, and versioning

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-CONTENT-NOT-FOUND (err u101))
(define-constant ERR-INVALID-INPUT (err u102))
(define-constant ERR-CONTENT-ALREADY-EXISTS (err u103))
(define-constant ERR-INSUFFICIENT-BALANCE (err u104))

;; Data Variables
(define-data-var next-content-id uint u1)
(define-data-var platform-fee-percentage uint u250) ;; 2.5%

;; Data Maps
(define-map content-registry uint {
  creator: principal,
  title: (string-ascii 100),
  description: (string-ascii 500),
  content-hash: (buff 32),
  price: uint,
  category: (string-ascii 50),
  created-at: uint,
  updated-at: uint,
  is-active: bool,
  version: uint,
  total-sales: uint,
  rating-sum: uint,
  rating-count: uint
})

(define-map creator-content principal (list 100 uint))
(define-map content-purchases {content-id: uint, buyer: principal} {
  purchased-at: uint,
  price-paid: uint,
  access-expires: (optional uint)
})

(define-map content-ratings {content-id: uint, rater: principal} {
  rating: uint,
  review: (optional (string-ascii 200)),
  created-at: uint
})

(define-map creator-stats principal {
  total-content: uint,
  total-revenue: uint,
  average-rating: uint,
  total-sales: uint
})

;; Private Functions
(define-private (is-valid-rating (rating uint))
  (and (>= rating u1) (<= rating u5))
)

(define-private (calculate-average-rating (rating-sum uint) (rating-count uint))
  (if (> rating-count u0)
    (/ rating-sum rating-count)
    u0
  )
)

;; Read-only Functions
(define-read-only (get-content (content-id uint))
  (map-get? content-registry content-id)
)

(define-read-only (get-creator-content (creator principal))
  (default-to (list) (map-get? creator-content creator))
)

(define-read-only (has-purchased (content-id uint) (buyer principal))
  (is-some (map-get? content-purchases {content-id: content-id, buyer: buyer}))
)

(define-read-only (get-purchase-info (content-id uint) (buyer principal))
  (map-get? content-purchases {content-id: content-id, buyer: buyer})
)

(define-read-only (get-content-rating (content-id uint) (rater principal))
  (map-get? content-ratings {content-id: content-id, rater: rater})
)

(define-read-only (get-creator-stats (creator principal))
  (map-get? creator-stats creator)
)

(define-read-only (get-next-content-id)
  (var-get next-content-id)
)

(define-read-only (get-platform-fee-percentage)
  (var-get platform-fee-percentage)
)

;; Public Functions
(define-public (publish-content
  (title (string-ascii 100))
  (description (string-ascii 500))
  (content-hash (buff 32))
  (price uint)
  (category (string-ascii 50))
)
  (let (
    (content-id (var-get next-content-id))
    (creator tx-sender)
    (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
  )
    ;; Validate inputs
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)
    (asserts! (> (len description) u0) ERR-INVALID-INPUT)
    (asserts! (> (len content-hash) u0) ERR-INVALID-INPUT)
    (asserts! (> (len category) u0) ERR-INVALID-INPUT)

    ;; Create content entry
    (map-set content-registry content-id {
      creator: creator,
      title: title,
      description: description,
      content-hash: content-hash,
      price: price,
      category: category,
      created-at: current-time,
      updated-at: current-time,
      is-active: true,
      version: u1,
      total-sales: u0,
      rating-sum: u0,
      rating-count: u0
    })

    ;; Update creator's content list
    (let ((current-list (default-to (list) (map-get? creator-content creator))))
      (map-set creator-content creator (unwrap-panic (as-max-len? (append current-list content-id) u100)))
    )

    ;; Update creator stats
    (let ((current-stats (default-to {total-content: u0, total-revenue: u0, average-rating: u0, total-sales: u0}
                                   (map-get? creator-stats creator))))
      (map-set creator-stats creator {
        total-content: (+ (get total-content current-stats) u1),
        total-revenue: (get total-revenue current-stats),
        average-rating: (get average-rating current-stats),
        total-sales: (get total-sales current-stats)
      })
    )

    ;; Increment next content ID
    (var-set next-content-id (+ content-id u1))

    (ok content-id)
  )
)

(define-public (update-content
  (content-id uint)
  (title (string-ascii 100))
  (description (string-ascii 500))
  (price uint)
)
  (let (
    (content-data (unwrap! (map-get? content-registry content-id) ERR-CONTENT-NOT-FOUND))
    (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
  )
    ;; Check authorization
    (asserts! (is-eq tx-sender (get creator content-data)) ERR-NOT-AUTHORIZED)

    ;; Validate inputs
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)
    (asserts! (> (len description) u0) ERR-INVALID-INPUT)

    ;; Update content
    (map-set content-registry content-id (merge content-data {
      title: title,
      description: description,
      price: price,
      updated-at: current-time,
      version: (+ (get version content-data) u1)
    }))

    (ok true)
  )
)

(define-public (toggle-content-status (content-id uint))
  (let (
    (content-data (unwrap! (map-get? content-registry content-id) ERR-CONTENT-NOT-FOUND))
    (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
  )
    ;; Check authorization
    (asserts! (is-eq tx-sender (get creator content-data)) ERR-NOT-AUTHORIZED)

    ;; Toggle status
    (map-set content-registry content-id (merge content-data {
      is-active: (not (get is-active content-data)),
      updated-at: current-time
    }))

    (ok (not (get is-active content-data)))
  )
)

(define-public (record-purchase
  (content-id uint)
  (buyer principal)
  (price-paid uint)
  (access-duration (optional uint))
)
  (let (
    (content-data (unwrap! (map-get? content-registry content-id) ERR-CONTENT-NOT-FOUND))
    (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    (access-expires (match access-duration
      duration (some (+ current-time duration))
      none
    ))
  )
    ;; Validate content is active
    (asserts! (get is-active content-data) ERR-INVALID-INPUT)

    ;; Record purchase
    (map-set content-purchases {content-id: content-id, buyer: buyer} {
      purchased-at: current-time,
      price-paid: price-paid,
      access-expires: access-expires
    })

    ;; Update content sales count
    (map-set content-registry content-id (merge content-data {
      total-sales: (+ (get total-sales content-data) u1)
    }))

    ;; Update creator stats
    (let (
      (creator (get creator content-data))
      (current-stats (default-to {total-content: u0, total-revenue: u0, average-rating: u0, total-sales: u0}
                                 (map-get? creator-stats creator)))
    )
      (map-set creator-stats creator {
        total-content: (get total-content current-stats),
        total-revenue: (+ (get total-revenue current-stats) price-paid),
        average-rating: (get average-rating current-stats),
        total-sales: (+ (get total-sales current-stats) u1)
      })
    )

    (ok true)
  )
)

(define-public (rate-content
  (content-id uint)
  (rating uint)
  (review (optional (string-ascii 200)))
)
  (let (
    (content-data (unwrap! (map-get? content-registry content-id) ERR-CONTENT-NOT-FOUND))
    (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    (rater tx-sender)
  )
    ;; Validate rating
    (asserts! (is-valid-rating rating) ERR-INVALID-INPUT)

    ;; Check if user has purchased content
    (asserts! (has-purchased content-id rater) ERR-NOT-AUTHORIZED)

    ;; Get existing rating if any
    (let (
      (existing-rating (map-get? content-ratings {content-id: content-id, rater: rater}))
      (rating-adjustment (match existing-rating
        existing-data (- rating (get rating existing-data))
        rating
      ))
      (count-adjustment (if (is-some existing-rating) u0 u1))
    )
      ;; Update rating
      (map-set content-ratings {content-id: content-id, rater: rater} {
        rating: rating,
        review: review,
        created-at: current-time
      })

      ;; Update content rating stats
      (let (
        (new-rating-sum (+ (get rating-sum content-data) rating-adjustment))
        (new-rating-count (+ (get rating-count content-data) count-adjustment))
      )
        (map-set content-registry content-id (merge content-data {
          rating-sum: new-rating-sum,
          rating-count: new-rating-count
        }))

        ;; Update creator average rating
        (let (
          (creator (get creator content-data))
          (current-stats (default-to {total-content: u0, total-revenue: u0, average-rating: u0, total-sales: u0}
                                     (map-get? creator-stats creator)))
        )
          (map-set creator-stats creator (merge current-stats {
            average-rating: (calculate-average-rating new-rating-sum new-rating-count)
          }))
        )
      )
    )

    (ok true)
  )
)

(define-public (set-platform-fee-percentage (new-percentage uint))
  (begin
    ;; Only contract owner can set platform fee
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-percentage u1000) ERR-INVALID-INPUT) ;; Max 10%

    (var-set platform-fee-percentage new-percentage)
    (ok true)
  )
)
