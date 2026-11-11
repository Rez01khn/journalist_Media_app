# Laravel REST API Contract Specification (`/api/v1`) (TASK 06.1)

> **Document Status:** Approved REST API Specification (TASK 06.1 — Design-Only)  
> **Base URL:** `https://api.newsdesk.example.com/api/v1`  
> **Content-Type:** `application/json; charset=utf-8`  
> **Authentication:** `Authorization: Bearer <sanctum_personal_access_token>`  
> **API Versioning:** URI-versioned (`/api/v1/...`) to allow non-breaking evolution for field mobile clients.

---

## 1. Global API Conventions

### 1.1 Standard Request Headers
| Header | Required | Description |
| :--- | :---: | :--- |
| `Accept` | Yes | Must be `application/json`. |
| `Content-Type` | Yes (Body) | `application/json; charset=utf-8` (or `multipart/form-data` for editor derivative upload). |
| `Authorization` | Yes (Protected) | `Bearer <plain_text_sanctum_token>`. |
| `Idempotency-Key` | Yes (Mutations) | Required on `POST /news/submissions` and `PUT /news/{uuid}/resubmit` (16–64 ASCII chars, e.g., SHA-256 hex). |
| `X-Client-Version` | Recommended | E.g., `flutter-android/1.0.0+5`. |
| `If-Match` | Optional | Optimistic concurrency header, e.g., `"v2"` (can also be passed in body as `expected_version`). |

### 1.2 Standardized Success Envelope
```json
{
  "success": true,
  "message": "Human-readable status message.",
  "data": { },
  "meta": {
    "timestamp": "2026-11-11T09:30:00Z",
    "request_id": "req_01JCD9X8M4N6P8Q2R4S6T8V0W2"
  }
}
```

### 1.3 Standardized Pagination Envelope (`meta.pagination`)
All list endpoints support `page` (default `1`), `per_page` (default `20`, max `100`), `sort_by`, and `sort_dir` (`asc` | `desc`).
```json
{
  "success": true,
  "data": [ ],
  "meta": {
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 142,
      "total_pages": 8,
      "has_more": true
    },
    "timestamp": "2026-11-11T09:30:00Z"
  }
}
```

### 1.4 Standardized Error Envelope & Error Codes
```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "The given data was invalid.",
    "details": {
      "headline": ["The headline field is required."],
      "media_attachments.0.drive_file_id": ["Drive file accessibility could not be verified."]
    }
  },
  "meta": {
    "timestamp": "2026-11-11T09:30:00Z",
    "request_id": "req_01JCD9X8M4N6P8Q2R4S6T8V0W2"
  }
}
```

| HTTP Status | Standard `error.code` | Meaning |
| :---: | :--- | :--- |
| `400` | `BAD_REQUEST` | Malformed JSON or missing required `Idempotency-Key` header. |
| `401` | `UNAUTHENTICATED` | Missing, expired, or revoked Sanctum Bearer token. |
| `403` | `ACCOUNT_SUSPENDED` / `FORBIDDEN_ROLE` / `NOT_OWNER` | Reporter account is suspended, role lacks permission, or reporter does not own the story. |
| `404` | `RESOURCE_NOT_FOUND` | Requested `uuid` does not exist. |
| `409` | `VERSION_CONFLICT` / `INVALID_STATE_TRANSITION` / `IDEMPOTENCY_CONFLICT` | Optimistic lock mismatch (`version`), illegal workflow transition (e.g., editing a `published` story), or concurrent duplicate request. |
| `422` | `VALIDATION_ERROR` / `MEDIA_ACCESS_UNVERIFIED` | Field validation failed or Google Drive media file is inaccessible/trashed. |
| `429` | `RATE_LIMIT_EXCEEDED` | Too many requests; inspect `Retry-After` header. |
| `500` | `INTERNAL_SERVER_ERROR` | Unexpected server fault (safe for client exponential-backoff retry). |

---

## 2. Endpoint Summary Table

| # | Category | Method | URI | Authorized Roles | Purpose |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **1.1** | Auth | `POST` | `/api/v1/auth/login` | Public | Authenticate reporter/editor & issue Sanctum token. |
| **1.2** | Auth | `POST` | `/api/v1/auth/logout` | Any Authenticated | Revoke current device Sanctum token. |
| **2.1** | Profile | `GET` | `/api/v1/reporter/profile` | Any Authenticated | Fetch current user profile, role, status, and linked Google email. |
| **2.2** | Profile | `PATCH` | `/api/v1/reporter/google-account` | `reporter` | Register/update the reporter's connected Google Drive email & FCM token. |
| **3.1** | Submission | `POST` | `/api/v1/news/submissions` | `reporter` | Explicitly submit a validated draft to the editorial queue (`draft -> submitted`). |
| **4.1** | Reporter News | `GET` | `/api/v1/news` | `reporter` | List the authenticated reporter's submitted news (supports `updated_since` delta sync). |
| **4.2** | Reporter News | `GET` | `/api/v1/news/{uuid}` | `reporter` (Own), `editor`, `senior_editor`, `admin` | Get full details, active revision, media list, and visible editorial comments. |
| **5.1** | Status Tracking | `GET` | `/api/v1/news/{uuid}/status-history` | `reporter` (Own), `editor`, `senior_editor`, `admin` | Get immutable timeline of all status changes for a news item. |
| **6.1** | Resubmission | `PUT` | `/api/v1/news/{uuid}/resubmit` | `reporter` (Own) | Submit corrected revision when story is in `correction_requested` (`-> resubmitted`). |
| **7.1** | Editorial Queue | `GET` | `/api/v1/editorial/news` | `editor`, `senior_editor`, `admin` | Paginated, filterable queue of all submitted/under-review/approved stories. |
| **8.1** | Editor Action | `POST` | `/api/v1/editorial/news/{uuid}/claim` | `editor`, `senior_editor`, `admin` | Claim a story for review (`submitted`/`resubmitted` -> `under_review`). |
| **8.2** | Editor Action | `PATCH` | `/api/v1/editorial/news/{uuid}/content` | `editor`, `senior_editor` | Edit headline/body/category/location (creates new `editor_modification` revision). |
| **8.3** | Editor Action | `POST` | `/api/v1/editorial/news/{uuid}/request-correction` | `editor`, `senior_editor`, `admin` | Return story to reporter with structured comments (`under_review -> correction_requested`). |
| **8.4** | Editor Action | `POST` | `/api/v1/editorial/news/{uuid}/reject` | `editor`, `senior_editor`, `admin` | Reject a story with mandatory reason (`under_review -> rejected`). |
| **8.5** | Editor Action | `POST` | `/api/v1/editorial/news/{uuid}/approve` | `editor`, `senior_editor`, `admin` | Approve story after fact & media verification (`under_review -> approved`). |
| **8.6** | Editor Action | `POST` | `/api/v1/editorial/news/{uuid}/publish` | `senior_editor`, `admin` | Publish an `approved` story to the live Laravel News Website (`approved -> published`). |
| **9.1** | Revisions | `GET` | `/api/v1/news/{uuid}/revisions` | `reporter` (Own), `editor`, `senior_editor`, `admin` | List all immutable text revisions (`Revision #1..#N`) for diffing and audit. |
| **10.1** | Media Access | `GET` | `/api/v1/editorial/media/{media_uuid}/stream` | `reporter` (Own), `editor`, `senior_editor`, `admin` | Stream original photo/video/voice from reporter's Drive via Service Account proxy. |
| **10.2** | Media Access | `POST` | `/api/v1/editorial/media/{media_uuid}/derivative` | `editor`, `senior_editor` | Upload editor-cropped/processed media to Website-Controlled Storage (never to reporter Drive). |
| **11.1** | Notifications | `GET` | `/api/v1/notifications` | Any Authenticated | List in-app notifications (`unread_only` filter supported). |
| **11.2** | Notifications | `POST` | `/api/v1/notifications/{uuid}/read` | Any Authenticated | Mark a notification as read. |

---

## 3. Detailed Endpoint Specifications

### 3.1 Authentication & Reporter Profile

#### `POST /api/v1/auth/login`
- **Authorized Roles:** Public (Rate limited: 5 req/min per IP+email)
- **Validation Rules:**
  - `email`: `required|email|max:191`
  - `password`: `required|string|min:8|max:128`
  - `device_id`: `required|string|max:100`
  - `device_name`: `required|string|max:150`
  - `fcm_device_token`: `nullable|string|max:255`
  - `google_account_email`: `nullable|email|max:191`
- **Request JSON:**
  ```json
  {
    "email": "rezwan.reporter@newsdesk.bd",
    "password": "StrongReporterPassword!2026",
    "device_id": "android_e4f8a2b1c9d0",
    "device_name": "Google Pixel 7 (Android 15)",
    "fcm_device_token": "fcm_token_xyz123...",
    "google_account_email": "rezwan.field.media@gmail.com"
  }
  ```
- **Response JSON (`200 OK`):**
  ```json
  {
    "success": true,
    "message": "Authenticated successfully.",
    "data": {
      "access_token": "14|9kLmN2pQrStUvWxYz0123456789abcdef...",
      "token_type": "Bearer",
      "expires_at": "2026-12-11T09:30:00Z",
      "editorial_service_principal": "editorial-vault@newsdesk-prod.iam.gserviceaccount.com",
      "reporter": {
        "uuid": "550e8400-e29b-41d4-a716-446655440000",
        "reporter_code": "REP-2026-084",
        "full_name": "Rezwan Ahmed",
        "email": "rezwan.reporter@newsdesk.bd",
        "phone_number": "+8801711000000",
        "designation": "Staff Reporter",
        "assigned_area": "Dhaka Metro",
        "role": "reporter",
        "status": "active",
        "is_verified": true,
        "google_account_email": "rezwan.field.media@gmail.com"
      }
    }
  }
  ```
- **HTTP Status Codes:** `200 OK`, `401 Unauthorized` (invalid credentials), `403 Forbidden` (`ACCOUNT_SUSPENDED` or `ACCOUNT_LOCKED`), `422 Unprocessable Entity`, `429 Too Many Requests`.

---

#### `GET /api/v1/reporter/profile`
- **Authorized Roles:** `reporter`, `editor`, `senior_editor`, `admin`
- **Response JSON (`200 OK`):** Returns the `reporter` object and `editorial_service_principal` shown above so the Flutter app always knows which Google Service Account email to grant `reader` permissions to upon news submission.

---

### 3.2 News Submission (Explicit Reporter Action)

#### `POST /api/v1/news/submissions`
- **Authorized Roles:** `reporter` (Active & Verified only)
- **Required Header:** `Idempotency-Key: <sha256_string>`
- **Validation Rules:**
  - `client_draft_uuid`: `required|uuid`
  - `headline`: `required|string|min:5|max:300`
  - `category`: `required|string|max:100`
  - `location`: `nullable|string|max:200`
  - `body`: `required|string|min:20|max:100000`
  - `is_ai_assisted`: `required|boolean`
  - `ai_assisted_headline`: `nullable|string|max:300`
  - `ai_assisted_body`: `nullable|string|max:100000`
  - `drive_folder_id`: `required|string|max:191`
  - `drive_draft_json_file_id`: `nullable|string|max:191`
  - `reporter_google_email`: `required|email|max:191`
  - `client_created_at`: `required|date`
  - `media_attachments`: `present|array|max:20`
  - `media_attachments.*.client_media_uuid`: `required|uuid|distinct`
  - `media_attachments.*.media_type`: `required|in:image,video,audio,thumbnail,document`
  - `media_attachments.*.attachment_role`: `required|in:gallery_attachment,voice_dispatch,thumbnail`
  - `media_attachments.*.original_filename`: `required|string|max:255`
  - `media_attachments.*.mime_type`: `required|string|max:100`
  - `media_attachments.*.file_size_bytes`: `required|integer|min:1|max:104857600` (25MB max for image/audio, 100MB max for video enforced by custom rule)
  - `media_attachments.*.duration_seconds`: `nullable|integer|min:1|max:900` (max 900s for `voice_dispatch`)
  - `media_attachments.*.drive_file_id`: `required|string|max:191|distinct`
  - `media_attachments.*.drive_permission_id`: `nullable|string|max:191`
  - `media_attachments.*.reporter_google_email`: `required|email|max:191`
- **Request JSON:**
  ```json
  {
    "client_draft_uuid": "d9b2d63d-a233-4123-847a-768389241221",
    "headline": "Heavy Rainfall Causes Waterlogging in Mirpur-10",
    "category": "National",
    "location": "Mirpur-10, Dhaka",
    "body": "Continuous downpour since early Tuesday morning has submerged major intersections in Mirpur-10, disrupting commuter traffic for over four hours...",
    "is_ai_assisted": false,
    "ai_assisted_headline": null,
    "ai_assisted_body": null,
    "drive_folder_id": "1Fldr_MirpurWaterlogging_998877",
    "drive_draft_json_file_id": "1Json_DraftBackup_112233",
    "reporter_google_email": "rezwan.field.media@gmail.com",
    "client_created_at": "2026-11-11T08:15:00Z",
    "media_attachments": [
      {
        "client_media_uuid": "m1a11111-b222-4c33-8d44-e55555555551",
        "media_type": "image",
        "attachment_role": "gallery_attachment",
        "display_order": 0,
        "original_filename": "mirpur_road_1.jpg",
        "mime_type": "image/jpeg",
        "file_size_bytes": 2458112,
        "duration_seconds": null,
        "checksum_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "drive_file_id": "1DrvImg_MirpurRoad_AbCdEfG",
        "drive_folder_id": "1Fldr_MirpurWaterlogging_998877",
        "drive_web_view_link": "https://drive.google.com/file/d/1DrvImg_MirpurRoad_AbCdEfG/view",
        "drive_permission_id": "09876543211234567890",
        "reporter_google_email": "rezwan.field.media@gmail.com",
        "captured_at": "2026-11-11T08:16:30Z"
      },
      {
        "client_media_uuid": "m2b22222-c333-4d44-9e55-f66666666662",
        "media_type": "audio",
        "attachment_role": "voice_dispatch",
        "display_order": 1,
        "original_filename": "voice_1731313000.m4a",
        "mime_type": "audio/mp4",
        "file_size_bytes": 842150,
        "duration_seconds": 48,
        "checksum_sha256": "8f434346648f6b96df89dda901c5176b10a6d83961dd3c1ac88b59b2dc327aa4",
        "drive_file_id": "1DrvAud_VoiceDispatch_HijKlMn",
        "drive_folder_id": "1Fldr_MirpurWaterlogging_998877",
        "drive_web_view_link": "https://drive.google.com/file/d/1DrvAud_VoiceDispatch_HijKlMn/view",
        "drive_permission_id": "09876543211234567891",
        "reporter_google_email": "rezwan.field.media@gmail.com",
        "captured_at": "2026-11-11T08:20:00Z"
      }
    ]
  }
  ```
- **Response JSON (`201 Created` — or `200 OK` on idempotent replay):**
  ```json
  {
    "success": true,
    "message": "News submitted successfully for editorial review.",
    "data": {
      "server_news_id": 1042,
      "uuid": "d9b2d63d-a233-4123-847a-768389241221",
      "tracking_code": "NWS-20261111-0042",
      "status": "submitted",
      "is_locked_for_reporter": true,
      "version": 1,
      "current_revision_number": 1,
      "submitted_at": "2026-11-11T09:31:12Z",
      "media_verification_status": "pending_verification"
    }
  }
  ```
- **HTTP Status Codes:** `201 Created`, `200 OK` (Idempotent replay), `400 Bad Request` (Missing `Idempotency-Key`), `401 Unauthorized`, `403 Forbidden`, `409 Conflict` (`IDEMPOTENCY_CONFLICT` if same key used with different payload), `422 Unprocessable Entity`.

---

### 3.3 Reporter News Listing, Details & Status Synchronization

#### `GET /api/v1/news`
- **Authorized Roles:** `reporter` (Returns only stories owned by `Auth::id()`)
- **Query Parameters:**
  - `status`: Optional (`submitted`, `under_review`, `correction_requested`, `resubmitted`, `rejected`, `approved`, `published`)
  - `updated_since`: Optional ISO-8601 timestamp (e.g., `2026-11-11T08:00:00Z`) for lightweight delta sync back to Flutter SQLite.
  - `page`, `per_page`: Pagination controls.
- **Response JSON (`200 OK`):**
  ```json
  {
    "success": true,
    "data": [
      {
        "uuid": "d9b2d63d-a233-4123-847a-768389241221",
        "tracking_code": "NWS-20261111-0042",
        "headline": "Heavy Rainfall Causes Waterlogging in Mirpur-10",
        "category": "National",
        "location": "Mirpur-10, Dhaka",
        "status": "correction_requested",
        "is_locked_for_reporter": false,
        "version": 3,
        "current_revision_number": 1,
        "unresolved_comments_count": 2,
        "latest_editorial_note": "Please clarify the exact water depth near Mirpur-10 roundabout and re-verify the second photo.",
        "submitted_at": "2026-11-11T09:31:12Z",
        "updated_at": "2026-11-11T10:05:00Z",
        "published_website_url": null
      }
    ],
    "meta": {
      "pagination": {
        "current_page": 1,
        "per_page": 20,
        "total_items": 1,
        "total_pages": 1,
        "has_more": false
      }
    }
  }
  ```

---

#### `GET /api/v1/news/{uuid}`
- **Authorized Roles:** `reporter` (Own story only), `editor`, `senior_editor`, `admin`
- **Response JSON (`200 OK`):**
  ```json
  {
    "success": true,
    "data": {
      "uuid": "d9b2d63d-a233-4123-847a-768389241221",
      "tracking_code": "NWS-20261111-0042",
      "status": "correction_requested",
      "priority": "normal",
      "is_locked_for_reporter": false,
      "version": 3,
      "reporter": {
        "uuid": "550e8400-e29b-41d4-a716-446655440000",
        "reporter_code": "REP-2026-084",
        "full_name": "Rezwan Ahmed"
      },
      "assigned_editor": {
        "uuid": "770e8400-e29b-41d4-a716-446655440999",
        "full_name": "Farhana Karim (Desk Editor)"
      },
      "current_revision": {
        "revision_number": 1,
        "source_type": "reporter_initial",
        "headline": "Heavy Rainfall Causes Waterlogging in Mirpur-10",
        "category": "National",
        "location": "Mirpur-10, Dhaka",
        "body": "Continuous downpour since early Tuesday morning...",
        "is_ai_assisted": false,
        "created_at": "2026-11-11T09:31:12Z"
      },
      "media_attachments": [
        {
          "uuid": "m1a11111-b222-4c33-8d44-e55555555551",
          "media_type": "image",
          "attachment_role": "gallery_attachment",
          "original_filename": "mirpur_road_1.jpg",
          "mime_type": "image/jpeg",
          "file_size_bytes": 2458112,
          "drive_file_id": "1DrvImg_MirpurRoad_AbCdEfG",
          "upload_status": "verified",
          "stream_url": "/api/v1/editorial/media/m1a11111-b222-4c33-8d44-e55555555551/stream"
        }
      ],
      "editorial_comments": [
        {
          "uuid": "c9911111-d222-4e33-8f44-a55555555559",
          "target_section": "body",
          "target_media_uuid": null,
          "author_name": "Farhana Karim",
          "comment_text": "Please add a quote from WASA or traffic police regarding drainage operations.",
          "is_resolved": false,
          "created_at": "2026-11-11T10:04:45Z"
        }
      ],
      "submitted_at": "2026-11-11T09:31:12Z",
      "published_at": null,
      "published_website_url": null
    }
  }
  ```

---

### 3.4 Correction Resubmission (Reporter Action)

#### `PUT /api/v1/news/{uuid}/resubmit`
- **Authorized Roles:** `reporter` (Must be owning reporter; `news.status` **must** be `correction_requested`)
- **Required Header:** `Idempotency-Key: <sha256_string>`
- **Validation Rules:**
  - `expected_version`: `required|integer` (must match `news.version`)
  - `headline`: `required|string|min:5|max:300`
  - `category`: `required|string|max:100`
  - `location`: `nullable|string|max:200`
  - `body`: `required|string|min:20|max:100000`
  - `change_summary`: `required|string|min:5|max:500`
  - `resolved_comment_uuids`: `nullable|array`
  - `media_attachments`: `present|array|max:20` (full list of active attachments for the new revision)
- **Request JSON:**
  ```json
  {
    "expected_version": 3,
    "headline": "Heavy Rainfall Submerges Mirpur-10; WASA Deploys Emergency Pumps",
    "category": "National",
    "location": "Mirpur-10, Dhaka",
    "body": "Continuous downpour since early Tuesday morning has submerged major intersections in Mirpur-10... Dhaka WASA Executive Engineer confirmed three mobile pumps are operating...",
    "change_summary": "Added official WASA statement and updated water depth figures as requested.",
    "resolved_comment_uuids": [
      "c9911111-d222-4e33-8f44-a55555555559"
    ],
    "media_attachments": [
      {
        "client_media_uuid": "m1a11111-b222-4c33-8d44-e55555555551",
        "media_type": "image",
        "attachment_role": "gallery_attachment",
        "display_order": 0,
        "original_filename": "mirpur_road_1.jpg",
        "mime_type": "image/jpeg",
        "file_size_bytes": 2458112,
        "drive_file_id": "1DrvImg_MirpurRoad_AbCdEfG",
        "reporter_google_email": "rezwan.field.media@gmail.com"
      }
    ]
  }
  ```
- **Response JSON (`200 OK`):**
  ```json
  {
    "success": true,
    "message": "Corrected news resubmitted to the editorial desk.",
    "data": {
      "uuid": "d9b2d63d-a233-4123-847a-768389241221",
      "tracking_code": "NWS-20261111-0042",
      "status": "resubmitted",
      "is_locked_for_reporter": true,
      "version": 4,
      "current_revision_number": 2,
      "last_resubmitted_at": "2026-11-11T10:25:00Z"
    }
  }
  ```
- **HTTP Status Codes:** `200 OK`, `403 Forbidden` (Not owner), `409 Conflict` (`INVALID_STATE_TRANSITION` if status != `correction_requested`, or `VERSION_CONFLICT` if `expected_version != news.version`), `422 Unprocessable Entity`.

---

### 3.5 Editorial Review Queue & Editor Actions

#### `GET /api/v1/editorial/news`
- **Authorized Roles:** `editor`, `senior_editor`, `admin`
- **Query Filters:** `status` (comma-separated, e.g., `submitted,resubmitted,under_review`), `priority`, `category`, `reporter_id`, `assigned_editor_id`, `search` (headline/tracking_code), `page`, `per_page`.
- **Response JSON (`200 OK`):** Paginated list of news items with reporter details, attachment counts (`images_count`, `videos_count`, `has_voice_dispatch`), `media_verification_status`, and `submitted_at`.

---

#### `POST /api/v1/editorial/news/{uuid}/claim`
- **Authorized Roles:** `editor`, `senior_editor`, `admin`
- **Guard:** Allowed when `status IN ('submitted', 'resubmitted')`.
- **Request JSON:**
  ```json
  {
    "expected_version": 1
  }
  ```
- **Response JSON (`200 OK`):**
  ```json
  {
    "success": true,
    "message": "News story claimed for editorial review.",
    "data": {
      "uuid": "d9b2d63d-a233-4123-847a-768389241221",
      "status": "under_review",
      "version": 2,
      "assigned_editor_id": 12,
      "review_cycle": 1,
      "review_started_at": "2026-11-11T09:45:00Z"
    }
  }
  ```

---

#### `PATCH /api/v1/editorial/news/{uuid}/content`
- **Authorized Roles:** `editor`, `senior_editor`
- **Guard:** Allowed only when `status == 'under_review'`. Inserts a new immutable row in `news_revisions` (`source_type = 'editor_modification'`) without overwriting the reporter's earlier revision.
- **Validation Rules:**
  - `expected_version`: `required|integer`
  - `headline`: `required|string|min:5|max:300`
  - `category`: `required|string|max:100`
  - `location`: `nullable|string|max:200`
  - `body`: `required|string|min:20|max:100000`
  - `change_summary`: `required|string|min:5|max:500`
- **Request JSON:**
  ```json
  {
    "expected_version": 2,
    "headline": "Mirpur-10 Submerged After Morning Downpour; Commuters Stranded",
    "category": "National",
    "location": "Mirpur-10, Dhaka",
    "body": "Edited newsroom copy with standardized style...",
    "change_summary": "Tightened headline and fixed paragraph structure for print/web style."
  }
  ```
- **Response JSON (`200 OK`):**
  ```json
  {
    "success": true,
    "message": "New editorial revision (#2) saved.",
    "data": {
      "uuid": "d9b2d63d-a233-4123-847a-768389241221",
      "status": "under_review",
      "version": 3,
      "current_revision_number": 2
    }
  }
  ```

---

#### `POST /api/v1/editorial/news/{uuid}/request-correction`
- **Authorized Roles:** `editor`, `senior_editor`, `admin`
- **Guard:** Allowed when `status == 'under_review'`. Transitions story to `correction_requested` and sets `is_locked_for_reporter = false`.
- **Validation Rules:**
  - `expected_version`: `required|integer`
  - `summary_note`: `required|string|min:10|max:2000`
  - `comments`: `required|array|min:1`
  - `comments.*.target_section`: `required|in:general,headline,body,category,location,media,voice_dispatch`
  - `comments.*.target_media_uuid`: `nullable|uuid`
  - `comments.*.comment_text`: `required|string|min:5|max:2000`
- **Request JSON:**
  ```json
  {
    "expected_version": 2,
    "summary_note": "Please add an official statement from WASA and clarify water depth.",
    "comments": [
      {
        "target_section": "body",
        "target_media_uuid": null,
        "comment_text": "Please add a quote from WASA or traffic police regarding drainage operations."
      }
    ]
  }
  ```
- **Response JSON (`200 OK`):**
  ```json
  {
    "success": true,
    "message": "Correction requested from reporter.",
    "data": {
      "uuid": "d9b2d63d-a233-4123-847a-768389241221",
      "status": "correction_requested",
      "is_locked_for_reporter": false,
      "version": 3
    }
  }
  ```

---

#### `POST /api/v1/editorial/news/{uuid}/reject`
- **Authorized Roles:** `editor`, `senior_editor`, `admin`
- **Guard:** Allowed when `status == 'under_review'`.
- **Validation Rules:** `expected_version`: `required|integer`, `reason`: `required|string|min:10|max:2000`.
- **Request JSON:**
  ```json
  {
    "expected_version": 2,
    "reason": "Duplicate dispatch already covered by District Bureau desk (NWS-20261111-0031)."
  }
  ```
- **Response JSON (`200 OK`):** Returns `"status": "rejected"`, `"is_locked_for_reporter": true`, `"version": 3`.

---

#### `POST /api/v1/editorial/news/{uuid}/approve`
- **Authorized Roles:** `editor`, `senior_editor`, `admin`
- **Guard:** Allowed when `status == 'under_review'` and all active `news_media` rows have `upload_status == 'verified'`.
- **Validation Rules:** `expected_version`: `required|integer`, `summary_note`: `nullable|string|max:2000`.
- **Request JSON:**
  ```json
  {
    "expected_version": 4,
    "summary_note": "Facts and WASA quote verified. Approved for publication."
  }
  ```
- **Response JSON (`200 OK`):**
  ```json
  {
    "success": true,
    "message": "News story approved. Ready for website publication.",
    "data": {
      "uuid": "d9b2d63d-a233-4123-847a-768389241221",
      "status": "approved",
      "version": 5,
      "approved_at": "2026-11-11T10:40:00Z"
    }
  }
  ```

---

#### `POST /api/v1/editorial/news/{uuid}/publish`
- **Authorized Roles:** `senior_editor`, `admin`
- **Guard:** Allowed **only** when `status == 'approved'`. Copies final approved media to Website CDN storage and exports the article to the existing Laravel News Website.
- **Validation Rules:**
  - `expected_version`: `required|integer`
  - `website_category_slug`: `required|string|max:100`
  - `is_featured`: `boolean`
  - `publish_note`: `nullable|string|max:500`
- **Request JSON:**
  ```json
  {
    "expected_version": 5,
    "website_category_slug": "national",
    "is_featured": true,
    "publish_note": "Published to main national lead slot."
  }
  ```
- **Response JSON (`200 OK`):**
  ```json
  {
    "success": true,
    "message": "News story published to live website.",
    "data": {
      "uuid": "d9b2d63d-a233-4123-847a-768389241221",
      "status": "published",
      "version": 6,
      "published_website_article_id": 88412,
      "published_website_url": "https://www.newsdesk.bd/national/2026/11/11/mirpur-10-submerged-after-morning-downpour",
      "published_at": "2026-11-11T10:45:00Z"
    }
  }
  ```

---

### 3.6 Revision History, Status History, Media Access & Notifications

#### `GET /api/v1/news/{uuid}/revisions`
- **Authorized Roles:** `reporter` (Own), `editor`, `senior_editor`, `admin`
- **Response JSON (`200 OK`):** Returns ordered array of all `news_revisions` (`revision_number`, `source_type`, `created_by_role`, `author_name`, `headline`, `category`, `location`, `body`, `change_summary`, `content_sha256`, `created_at`).

#### `GET /api/v1/news/{uuid}/status-history`
- **Authorized Roles:** `reporter` (Own), `editor`, `senior_editor`, `admin`
- **Response JSON (`200 OK`):** Returns chronological array of `news_status_history` (`from_status`, `to_status`, `actor_role`, `actor_name`, `revision_number`, `reason`, `created_at`).

#### `GET /api/v1/editorial/media/{media_uuid}/stream`
- **Authorized Roles:** `reporter` (Own), `editor`, `senior_editor`, `admin`
- **Behavior:** Validates role/ownership, logs access in `audit_logs`, and streams binary bytes (`200 OK` or `206 Partial Content` with `Accept-Ranges: bytes`) from either the editor derivative (`editor_storage_path` if `?variant=derivative`) or the reporter's Google Drive via the Editorial Service Account (`?variant=original`, default).

#### `POST /api/v1/editorial/media/{media_uuid}/derivative`
- **Authorized Roles:** `editor`, `senior_editor`
- **Request:** `multipart/form-data` containing `file` (cropped image/edited video) and `note`.
- **Behavior:** Stores file in Website-Controlled Storage (`EditorialStorage`), increments `news_media.media_version`, and updates `editor_storage_path` **without** touching the reporter's Google Drive.
- **Response JSON (`200 OK`):** Returns updated `news_media` object with `editor_storage_path` and `media_version`.

