# IskoLinic — Clinic Desktop App

A **Flutter Windows desktop application** for managing a school clinic's patient records, visitations, inventory, and analytics. Built with offline-first CRDT sync for multi-device support.

**Package name:** `iskolinic`
**Target platform:** Windows (uses `sqflite_common_ffi`)
**Database:** Local SQLite via `sqflite_common_ffi`, stored at `%APPDATA%/com.iskolinic/IskoLinic/clinic.db`
**Database version:** 11

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Project Structure](#project-structure)
- [Startup / Wiring (main.dart)](#startup--wiring-maindart)
- [Models](#models)
- [Database Schema & Migrations](#database-schema--migrations)
- [Providers (State Management)](#providers-state-management)
- [CRDT Sync System](#crdt-sync-system)
- [Screens](#screens)
- [Constants](#constants)
- [Formatters](#formatters)
- [Theme](#theme)
- [Key Dependencies](#key-dependencies)
- [Text Field Constraints](#text-field-constraints)
- [Conventions & Patterns](#conventions--patterns)

---

## Architecture Overview

```
                         (Desktop)
┌──────────────────────────────────────────────────────────┐
│                    Flutter UI (Screens)                  │
└──────────▲─────────────────────────────▲─────────────────┘
           │ reads/writes via            │ notifies via
┌──────────▼─────────────────────────────┴─────────────────┐
│               Providers (ChangeNotifier)                 │
└──────────▲─────────────────────────────▲─────────────────┘
           │                             │
           │ (Tablet)                    │ (Sync)
           ▼                             ▼
┌──────────────────────────┐    ┌──────────────────────────┐
│  Local Server (HTTP)     │    │      Relay Server        │
│  (Shelf)                 │    │      (WebSocket)         │
│  Port 8080               │    │      Render.com          │
└──────────────────────────┘    └──────────────────────────┘
```

The app follows a **Provider + Repository** pattern:
- **Screens** consume providers via `context.read<T>()` / `context.watch<T>()`
- **Providers** (`ChangeNotifier`) hold all business logic, pagination state, and CRDT clock management
- **DatabaseHelper** is a singleton that handles all raw SQLite operations
- **CRDT layer** handles distributed sync via WebSocket relay

---

## Project Structure

```
lib/
├── main.dart                     # App entry, provider wiring
├── constants/
│   └── symptoms.dart             # Predefined symptom lists (Traumatic, Medical, Behavioral)
├── crdt/
│   ├── hlc.dart                  # Hybrid Logical Clock implementation
│   ├── node_id.dart              # Persistent unique node identifier
│   ├── sync_client.dart          # WebSocket sync client with heartbeat & reconnect
│   ├── sync_isolate.dart         # Background CRDT merge processing
│   └── data_compactor.dart       # Tombstone cleanup (90-day threshold)
├── formatters/
│   └── uppercase_text.dart       # TextInputFormatter that uppercases input
├── models/
│   ├── patient.dart              # Patient data model with CRDT fields
│   ├── visitation.dart           # Visitation data model with CRDT fields
│   └── inventory_item.dart       # Tabular inventory item model
├── providers/
│   ├── patient_provider.dart     # Core provider: patients, visitations, pagination, CRDT writes
│   ├── inventory_provider.dart   # Inventory CRUD, ROP calculations
│   ├── analytics_provider.dart   # Monthly symptom/supply analytics (dynamic inventory)
│   ├── sync_provider.dart        # Sync lifecycle management, connection state
│   └── local_server_provider.dart# Tablet server state & connection monitoring
├── screens/
│   ├── dashboard_screen.dart     # Main dashboard with summary cards, quick actions, today's visits
│   ├── patient_list_screen.dart  # Paginated patient table with search
│   ├── patient_detail_screen.dart# Full patient detail dialog with medical history & permissions tabs
│   ├── patient_form_screen.dart  # Tabbed add/edit patient dialog (Personal, Medical, Permissions)
│   ├── visitation_form_screen.dart # Add/edit visitation dialog
│   ├── inventory_screen.dart     # Stock management UI
│   ├── analytics_screen.dart     # Monthly charts (symptoms, supplies, visits)
│   └── connection_screen.dart    # Tablet pairing UI (QR code, Auth Token, IP)
├── services/
│   ├── database_helper.dart      # SQLite singleton with all queries
│   ├── local_server_service.dart # Embedded Shelf HTTP server for tablet integration
│   └── mock_data_generator.dart  # Test data seeder (disabled in prod)
└── theme/
    └── app_theme.dart            # App-wide theme, colors, gradients, glass card style
```

---

## Startup / Wiring (main.dart)

The app initializes in this order:

1. `sqfliteFfiInit()` — Initialize FFI for Windows SQLite
2. `PatientProvider.initCrdt()` — Load/generate the node ID and HLC clock
3. `PatientProvider.loadPatients()` — Load the first page of patients
4. `SyncProvider.init(...)` — **(Non-blocking)** Start background WebSocket connection to relay server
5. `patientProvider.setOnLocalWrite(() => syncProvider.pushChanges())` — Wire auto-push
6. `InventoryProvider.loadInventory()` — Load inventory items
7. `patientProvider.setInventoryProvider(inventoryProvider)` — Wire auto-deduct/check stock
8. `LocalServerProvider.startServer()` — Start embedded HTTP server for tablet pairing
9. `localServerProvider.setOnDataChanged(() => patientProvider.refreshAll())` — Wire UI refresh for tablet submissions

All providers are registered via `MultiProvider`:
- `PatientProvider` — `.value()` (pre-initialized)
- `AnalyticsProvider` — `.create()` (lazy)
- `SyncProvider` — `.value()` (pre-initialized)
- `InventoryProvider` — `.value()` (pre-initialized)

---

## Models

### Patient (`models/patient.dart`)

| Field            | Type       | Notes                                      |
|------------------|------------|--------------------------------------------|
| `id`             | `String`   | UUID v4, primary key                       |
| `firstName`      | `String`   | Required, max 30 chars                     |
| `lastName`       | `String`   | Required, max 30 chars                     |
| `middleName`     | `String`   | Optional, max 30 chars                     |
| `extension`      | `String`   | Name suffix (Jr., Sr., I-III, or custom max 5 chars) |
| `patientName`    | `String`   | Computed: `"lastName, firstName middleName ext"` |
| `idNumber`       | `String`   | Student/employee ID, max 16 chars          |
| `address`        | `String`   | Optional, max 150 chars                    |
| `guardianName`   | `String`   | Optional, max 65 chars                     |
| `guardianContact`| `String`   | Optional, max 20 chars                     |
| `createdAt`      | `DateTime` | ISO 8601 string in DB                      |
| `updatedAt`      | `DateTime` | ISO 8601 string in DB                      |
| `hlc`            | `String`   | Packed HLC for CRDT ordering               |
| `nodeId`         | `String`   | Origin node ID                             |
| `isDeleted`      | `bool`     | Soft-delete flag (stored as `INTEGER 0/1`) |
| `pastMedicalHistory` | `List<Map>`| JSON List of `{"disease": String, "past": bool, "present": bool}` |
| `vaccinationHistory` | `List<Map>`| JSON List of `{"name": String, "dateGiven": ISO8601String}` |
| `allergicTo`     | `String`   | Free-text allergies list                   |
| `patientRemarks` | `String`   | General medical notes                      |
| `permissions`    | `Map`      | JSON Map of granted school health permissions|

Methods: `toMap()`, `fromMap()`, `copyWith()`, `toSyncMap()`, `fromSyncMap()`

### Visitation (`models/visitation.dart`)

| Field          | Type           | Notes                                        |
|----------------|----------------|----------------------------------------------|
| `id`           | `String`       | UUID v4, primary key                         |
| `patientId`    | `String`       | FK → `patients.id`                           |
| `dateTime`     | `DateTime`     | Visit timestamp                              |
| `symptoms`     | `List<String>` | Stored as `\|`-delimited string in DB        |
| `suppliesUsed` | `List<String>` | Stored as `\|`-delimited string in DB        |
| `treatment`    | `String`       | Free-text "Other Intervention Details", max 150 chars |
| `remarks`      | `String`       | Free-text notes, max 150 chars               |
| `hlc`          | `String`       | Packed HLC                                   |
| `nodeId`       | `String`       | Origin node ID                               |
| `isDeleted`    | `bool`         | Soft-delete flag                             |

Methods: `toMap()`, `fromMap()`, `copyWith()`, `toSyncMap()`, `fromSyncMap()`

### InventoryItem (`models/inventory_item.dart`)

| Field            | Type       | Notes                         |
|------------------|------------|-------------------------------|
| `id`             | `String`   | UUID v4, primary key          |
| `itemName`       | `String`   | Supply name                   |
| `quantity`       | `int`      | Total units in stock          |
| `averageDailyUse`| `int`      | Used for ROP calculation      |
| `leadTime`       | `int`      | Procurement days              |
| `safetyStock`    | `int`      | Minimum reserve               |
| `createdAt`      | `DateTime` | When item was created         |

Methods: `toMap()`, `fromMap()`, `copyWith()`, `reorderPoint` (getter)
**Note:** Inventory is local-only (for now).

---

## Database Schema & Migrations

**File:** `services/database_helper.dart`
**Current version:** 11

### Tables

#### `patients`
```sql
CREATE TABLE patients (
  id TEXT PRIMARY KEY,
  firstName TEXT NOT NULL,
  lastName TEXT NOT NULL,
  middleName TEXT NOT NULL DEFAULT '',
  extension TEXT NOT NULL DEFAULT '',
  patientName TEXT NOT NULL,
  idNumber TEXT NOT NULL,
  address TEXT,
  guardianName TEXT,
  guardianContact TEXT,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL,
  hlc TEXT NOT NULL DEFAULT '',
  nodeId TEXT NOT NULL DEFAULT '',
  isDeleted INTEGER NOT NULL DEFAULT 0,
  medicalHistory TEXT NOT NULL DEFAULT '[]',
  vaccinationHistory TEXT NOT NULL DEFAULT '[]',
  allergicTo TEXT NOT NULL DEFAULT '',
  patientRemarks TEXT NOT NULL DEFAULT '',
  permissions TEXT NOT NULL DEFAULT '{}'
)
-- Index: idx_patients_hlc ON patients (hlc)
```

#### `visitations`
```sql
CREATE TABLE visitations (
  id TEXT PRIMARY KEY,
  patientId TEXT NOT NULL,
  dateTime TEXT NOT NULL,
  symptoms TEXT,
  suppliesUsed TEXT,
  treatment TEXT,
  remarks TEXT,
  hlc TEXT NOT NULL DEFAULT '',
  nodeId TEXT NOT NULL DEFAULT '',
  isDeleted INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (patientId) REFERENCES patients (id)
)
-- Index: idx_visitations_hlc ON visitations (hlc)
```

#### `stock_batches`
```sql
CREATE TABLE stock_batches (
  id TEXT PRIMARY KEY,
  itemName TEXT NOT NULL,
  quantity INTEGER NOT NULL DEFAULT 0,
  expirationDate TEXT NOT NULL,
  createdAt TEXT NOT NULL
)
-- Index: idx_stock_item ON stock_batches (itemName, expirationDate)
```

#### `meta`
```sql
CREATE TABLE meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)
```
Used for: `nodeId` (persistent node identity), `lastSyncHlc` (sync watermark).

### Migration History

| Version | Changes |
|---------|---------|
| 1 | Initial schema: `patients`, `visitations` |
| 2 | Added `suppliesUsed` column to visitations; dropped `emergency_alerts` |
| 3 | Added CRDT columns (`hlc`, `nodeId`, `isDeleted`) to patients & visitations; created `meta` table and HLC indexes |
| 4 | Created `stock_batches` table for inventory |
| 5 | Added `firstName`, `lastName`, `middleName`, `extension` columns to patients; migrated existing `patientName` to `firstName` |
| 6 | Added `birthdate` (TEXT), `sex`, `contactNumber`, `guardian2Name`, `guardian2Contact` to patients |
| 7 | Added `medicalHistory` (JSON) and `vaccinationHistory` (JSON) to patients |
| 8 | (Legacy) Added `"allergic to"` and `"patient remarks"` columns (spaced names) |
| 9 | (Corrected) Added `allergicTo` and `patientRemarks` columns (camelCase) |
| 10 | Added `permissions` (JSON Map) column to patients |

### Key DB Methods

**Patient CRUD:** `insertPatient`, `getPatients`, `getPatientsPaginated`, `getPatientCount`, `searchPatientsPaginated`, `searchPatientCount`, `getPatient(id)`, `updatePatient`, `deletePatient` (soft-delete with HLC), `searchPatients`

**Visitation CRUD:** `insertVisitation`, `updateVisitation`, `getVisitationsForPatient`, `getVisitationsPaginated`, `getVisitationCountForPatient`, `getVisitationsForMonth`, `getTodayVisitCount`, `getTodayVisitationsPaginated` (JOIN with patient name)

**CRDT Sync:** `getPatientChangesSince(hlc)`, `getVisitationChangesSince(hlc)`, `upsertPatientFromRemote`, `upsertVisitationFromRemote`

**Inventory:** `insertInventoryItem`, `getAllInventory`, `updateInventoryItem`, `deleteInventoryItem`, `deductStock`, `addStock`

**Maintenance:** `compactTombstones(daysThreshold)`, `clearAllData`

---

## Providers (State Management)

### PatientProvider (`providers/patient_provider.dart`)

The **central provider** managing patients, visitations, pagination, and CRDT clock.

**State:**
- `_patients` — current page of patients (`List<Patient>`)
- `_totalPatients` — total patient count
- `_currentPage` / `_pageSize` (10) — patient list pagination
- `_searchQuery` — active search filter
- `_selectedPatient` — currently viewed patient
- `_visitations` — current page of selected patient's visits
- `_currentVisitPage` / `_visitPageSize` (10) — visit pagination
- `_todayVisits` — count of today's visits
- `_dashboardVisitPage` / `_dashboardVisitPageSize` (3) — dashboard visit pagination
- `_dashboardVisits` — paginated today's visits with patient names (`List<Map>`)
- `_clock` / `_nodeId` — HLC state
- `_onLocalWrite` — callback to trigger sync push after writes
- `_inventoryProvider` — reference for auto-deducting supplies

**Key Methods:**
- `initCrdt()` — Initialize HLC clock and node ID
- `loadPatients()` — Load current page (respects search query)
- `setSearchQuery(query)` — Filter + reset to page 0
- `refreshAll()` — Reload patients, today's visits, and selected patient's visits
- `addPatient(patient)` — Insert with HLC, reload, auto-push
- `updatePatient(patient)` — Update with HLC, reload, auto-push
- `deletePatient(id)` — Soft-delete with HLC, clamp page, reload, auto-push
- `selectPatient(patient)` — Set selected patient, load visits
- `addVisitation(...)` — Insert with HLC, auto-deduct supplies from inventory, reload today's visits, auto-push
- `updateVisitation(visit)` — Update with HLC, reload
- `deleteVisitation(visit)` — Soft-delete with HLC
- `loadTodayVisits()` — Count + load paginated dashboard visits
- `onSyncComplete(changedIds)` — Granular refresh after sync merge
- Pagination: `goToPage`, `nextPage`, `previousPage`, `firstPage`, `lastPage`
- Visit pagination: `goToVisitPage`, `nextVisitPage`, `prevVisitPage`, `firstVisitPage`, `lastVisitPage`
- Dashboard visit pagination: `goToDashboardVisitPage`, `nextDashboardVisitPage`, etc.

**Auto-push pattern:** Every write method calls `_autoPush()` which debounces (200ms) and then calls `_onLocalWrite?.call()` which triggers `SyncProvider.pushChanges()`.

### SyncProvider (`providers/sync_provider.dart`)

Manages the WebSocket sync lifecycle.

**State:** `_connectionState` (`SyncConnectionState`: disconnected/connecting/connected)

**Key Methods:**
- `init(patientProvider, {wsUrl})` — Create SyncClient, wire callbacks, run DataCompactor, auto-connect **(fire-and-forget: does not block app launch)**
- `connect()` / `disconnect()` — Manual connection control
- `forceSync()` — Disconnect + reconnect (manual refresh trigger)
- `pushChanges()` — Delegate to SyncClient

### InventoryProvider (`providers/inventory_provider.dart`)

Manages the clinic's inventory using the ROP model.

**State:**
- `_inventory` — `List<InventoryItem>` all supplies
- `_searchQuery` — filter for inventory table

**Key Methods:**
- `loadInventory()` — Reload from database
- `addStock(itemName, qty)` — Deduct/Add stock manually
- `addInventoryItem(item)` — Create a custom supply item
- `updateInventoryItem(item)` — Update ROP variables or details
- `deleteInventoryItem(id)` — Remove item record

### AnalyticsProvider (`providers/analytics_provider.dart`)

Monthly analytics for symptoms and supplies used.

**State:** `_selectedYear`, `_selectedMonth`, `_symptomCounts`, `_supplyCounts`, `_totalVisits`

**Key Methods:**
- `loadAnalytics()` — Count symptom/supply occurrences for selected month
- `setMonth(year, month)` / `previousMonth()` / `nextMonth()` — Navigation

### LocalServerProvider (`providers/local_server_provider.dart`)

Manages the embedded HTTP server used for connecting tablets (Clinic Input App).

**State:** `isRunning`, `localIp`, `port`, `authToken`, `connectedDevices` (Set of IPs)

**Key Methods:**
- `startServer()` — Spin up the Shelf server on port 8080 (or 8081 fallback)
- `stopServer()` — Shutdown
- `regenerateToken()` — Invalidate existing tablet sessions
- `setOnDataChanged(callback)` — Callback for desktop UI refresh when tablet submits data

---

## Local Tablet Server

**File:** `services/local_server_service.dart`

To allow students/employees to fill out forms on a tablet, the desktop app hosts a private REST API.

### Authentication & Security
- **Bearer Token**: A UUID v4 token is required in the `Authorization: Bearer <token>` header.
- **Private LAN**: The server binds to `0.0.0.0` but expects connections from the local network.
- **Auto-Discovery**: Encodes Host IP, Port, and Token into a JSON QR Code for tablet pairing.

### Endpoints
| Method | Route | Description |
|--------|-------|-------------|
| GET | `/api/health` | Server status and heartbeat |
| GET | `/api/patients` | Fetch all non-deleted patient records |
| GET | `/api/patients/search?idNumber=...` | Search for a specific patient by ID |
| POST | `/api/patients` | Submit a new patient entry + optional visitation record (symptoms) |

**Note:** Post data from the tablet is automatically stamped with the Desktop's current CRDT NodeId and wrapped in a new HLC to ensure correct multi-device sync later.

## CRDT Sync System

### Hybrid Logical Clock (`crdt/hlc.dart`)

Packed format: `<timestamp_hex_13>:<counter_hex_4>:<nodeId>`
Example: `018e1a2b3c4d5:0000:a1b2c3d4-...`

- `send()` — Increment for local write: `max(wall-clock, timestamp)` with counter bump
- `receive(remote)` — Merge with remote clock: result > both
- `pack()` / `unpack()` — Serialize to lexically orderable string
- Comparison operators: `>`, `<`, `>=`, `<=`, `==`

### Node ID (`crdt/node_id.dart`)

UUID v4 generated once on first launch, persisted in `meta` table as key `nodeId`.

### Sync Client (`crdt/sync_client.dart`)

WebSocket client connecting to relay server at `wss://iskolinic.onrender.com/ws`.

**Features:**
- **Heartbeat:** Ping every 3 minutes (prevents Render timeout)
- **Exponential backoff reconnect:** 1s → 2s → 4s → ... → max 30s
- **Chunked sync:** Batches of 50 records
- **Auto-push:** Triggered after every local write (debounced 200ms)

**Protocol messages:**
| Type | Direction | Purpose |
|------|-----------|---------|
| `ping` | Client → Server | Heartbeat |
| `pong` | Server → Client | Heartbeat ack |
| `sync_request` | Client → Server | Request changes since HLC |
| `sync_response` | Server → Client | Historical data (batched, with `hasMore` flag) |
| `sync_ack` | Client → Server | Acknowledge batch, request next |
| `sync_push` | Both | Push local changes, broadcast to peers |

**Flow:**
1. On connect → `_requestSync()` sends `sync_request` with `sinceHlc`, then `pushChanges()`
2. Server responds with `sync_response` batches → merged via `SyncIsolate`
3. Each batch ack'd with `sync_ack` until `hasMore: false`
4. On local write → `pushChanges()` sends `sync_push` for patients then visitations
5. Remote `sync_push` received → ignore own echoes → merge via `SyncIsolate`

### Sync Isolate (`crdt/sync_isolate.dart`)

Processes CRDT merges on the main isolate but with microtask-friendly batching (yields every 10 records).

**Merge logic:** For each remote record, calls `DatabaseHelper.upsertPatientFromRemote` / `upsertVisitationFromRemote` which only applies the change if `remoteHlc > localHlc`.

Returns `SyncResult` with sets of changed patient/visitation IDs → triggers `PatientProvider.onSyncComplete()`.

### Data Compactor (`crdt/data_compactor.dart`)

Runs on startup. Permanently removes tombstoned records (`isDeleted = 1`) older than 90 days.

---

## Screens

### DashboardScreen (`screens/dashboard_screen.dart`)
- **Main app screen** with sidebar navigation to all other screens
- **Quick Actions:** Record Visitation, Add Patient, Search Patients, **Connect Tablet**, Analytics, Refresh (calls `refreshAll()` + `forceSync()`)
  - **Search Patients:** Switches to Patients tab and immediately focuses the search bar.
  - **Connect Tablet:** Opens `ConnectionScreen` for pairing.
- **Today's Visits list:** Paginated (3 per page), shows patient name, time, symptoms, treatment
  - Clicking a visit opens `PatientDetailScreen`
  - Shows **"Add Missing Treatment Details"** `TextButton.icon` if both `treatment` and `suppliesUsed` are empty, which opens `VisitationFormScreen` in edit mode
- **Sidebar navigation:** Dashboard, Patients, Analytics, Inventory
- **Header:** Live digital clock synced to OS time.

### PatientListScreen (`screens/patient_list_screen.dart`)
- **Paginated table** of all patients (10 per page)
- **Search bar** filters by name or ID number; supports **auto-focus** when navigating via Quick Actions
- **Refresh button** (IconButton) beside "Add Patient" — calls `refreshAll()` + `forceSync()`
- Clicking a patient opens `PatientDetailScreen`

### PatientDetailScreen (`screens/patient_detail_screen.dart`)
- **Fullscreen dialog** with sidebar-based navigation
  - **Basic Info**: Personal demographics and age
  - **Visitation History**: All past visits, paginated, editable/deletable
  - **Medical Information**: Displays Allergies, Remarks, and the **Past Medical History Table** (listing diseases with Past/Present status) and Vaccination list
  - **Permissions**: Visual checklist of granted health permissions (Emergency transport, medications, etc.)
- Treatment display format: `"Treatment: Supply1, Supply2, Treatment Text"`

### PatientFormScreen (`screens/patient_form_screen.dart`)
- **Dialog** with Tabbed Layout:
  - **Personal Information**: Names, ID, demographics (original fields)
  - **Medical Information**: Allergies field, Past Medical History checklist (Chicken Pox, Measles, etc.), Vaccination list, and Patient Remarks
  - **Permissions**: Structured checklist for legal/school healthcare permissions with hospital selection logic
- All text fields use `UpperCaseTextFormatter`
- Extension dropdown options: None, JR., SR., I, II, III, Others (shows custom text field)

### VisitationFormScreen (`screens/visitation_form_screen.dart`)
- **Dialog** for creating/editing visitations
- **Patient autocomplete** (searches DB, top 10 results) — auto-fills when `patientId` or `visitation` is passed
  - Falls back to async DB lookup if patient not found in memory (shows loading spinner)
  - When `patientId != null`, the patient name field is read-only
- **Symptom chips:** Grouped into Traumatic, Medical, Behavioral sections with show/hide toggle
- **Supply chips:** Clinic supplies with show/hide toggle
- **Free text:** Other Intervention Details, Remarks
- **Edit mode:** Pre-fills all fields from existing `Visitation`

### AnalyticsScreen (`screens/analytics_screen.dart`)
- Monthly symptom frequency chart and supply usage chart
- Month navigation (prev/next)

### ConnectionScreen (`screens/connection_screen.dart`)
- **QR Code Pairing**: Encodes pairing JSON for the Clinic Input App
- **Pairing Details**: Displays Local IP, Port, and active Auth Token
- **Real-time Monitoring**: Lists IPs of currently active/recently seen tablet devices
- **Regenerate Token**: Button to reset security credentials instantly

### InventoryScreen (`screens/inventory_screen.dart`)
- Stock batch management with add/deduct functionality
- FEFO (First-Expired, First-Out) deduction strategy

---

## Constants

### Symptoms (`constants/symptoms.dart`)

```dart
kTraumaticSymptoms = ['Wound', 'Sprain', 'Burn', 'Sunburn', 'Nose Bleed', 'Callus', 'Deltoid']
kMedicalSymptoms = ['Headache', 'Abdominal Pain', 'General Pain', 'NFW/Dizzy', 'Menstrual Pain',
  'Fever', 'Asthma', 'LBM', 'Toothache/Oral Pain', 'Nasal', 'Cough', 'Cold', 'Vomit',
  'Sore Throat', 'Eczema', 'Hypogastric Pain', 'Allergy', 'Rashes', 'Acidic', 'Due Meds Given']
kBehavioralSymptoms = ['Panic Attacks']
kSymptomsList = [...kTraumaticSymptoms, ...kMedicalSymptoms, ...kBehavioralSymptoms]
```

### Supplies

Supply lists are now managed dynamically via the **Inventory** screen and stored in the database. There is no longer a static `kSuppliesList` constant. Usage is recorded in visitations and reflected in analytics based on the items currently in the `inventory` table.

---

## Formatters

### UpperCaseTextFormatter (`formatters/uppercase_text.dart`)

A `TextInputFormatter` that converts all input to uppercase. Applied to all patient form text fields (names, ID, address, guardian info).

---

## Theme

### AppTheme (`theme/app_theme.dart`)

- Uses `google_fonts` (likely Inter or similar)
- Dark-mode-ready design with glass card effects
- Key colors: `AppTheme.accent`, `AppTheme.danger`, `AppTheme.textPrimary`, `AppTheme.textSecondary`, `AppTheme.textMuted`, `AppTheme.dividerColor`, `AppTheme.cardLight`
- Key styles: `AppTheme.accentGradient`, `AppTheme.glassCard()`, `AppTheme.lightTheme`

---

## Key Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `provider` | ^6.1.2 | State management |
| `sqflite_common_ffi` | ^2.3.4+4 | SQLite for Windows desktop |
| `path_provider` | ^2.1.5 | App data directory |
| `path` | ^1.9.1 | Path manipulation |
| `fl_chart` | ^0.70.2 | Charts in analytics screen |
| `google_fonts` | ^6.2.1 | Typography |
| `intl` | ^0.20.2 | Date formatting |
| `uuid` | ^4.5.1 | ID generation |
| `audioplayers` | ^6.1.0 | Sound effects (if any) |
| `qr_flutter` | ^4.1.0 | QR code generation |
| `web_socket_channel` | ^3.0.2 | WebSocket for CRDT sync |
| `shelf` | ^1.4.1 | Embedded HTTP server engine |
| `shelf_router` | ^1.1.4 | REST routing for tablet API |
| `shelf_io` | ^1.0.4 | IO adapter for shelf |

---

## Text Field Constraints

| Field | Max Length | Screen |
|-------|-----------|--------|
| First Name | 30 | PatientFormScreen |
| Last Name | 30 | PatientFormScreen |
| Middle Name | 30 | PatientFormScreen |
| Extension (Others) | 5 | PatientFormScreen |
| ID Number | 16 | PatientFormScreen |
| Address | 150 | PatientFormScreen |
| Guardian Name | 65 | PatientFormScreen |
| Guardian Contact | 20 | PatientFormScreen |
| Other Intervention Details | 150 | VisitationFormScreen |
| Remarks | 150 | VisitationFormScreen |

All enforced via both `maxLength` property and `LengthLimitingTextInputFormatter`. Character counters are hidden (`counterText: ''`).

---

## Conventions & Patterns

1. **Soft Deletes:** All patient and visitation records use `isDeleted` flag (0/1). Queries always filter `WHERE isDeleted = 0`. Tombstones are compacted after 90 days.

2. **CRDT Writes:** Every write (add/update/delete) stamps the record with a new HLC via `_tick()` and the local `_nodeId`. This enables last-writer-wins conflict resolution during sync.

3. **Auto-Push:** After every local write, `_autoPush()` debounces (200ms) then calls `SyncProvider.pushChanges()` which sends changes to the relay server.

4. **Auto-Deduct:** When a visitation is added with supplies, each supply is auto-deducted (1 unit, FEFO) from `InventoryProvider`.

5. **Pagination:** All list views are paginated. Patient list: 10/page. Dashboard visits: 3/page. Patient detail visits: 10/page.

6. **Uppercase Input:** All patient text fields use `UpperCaseTextFormatter` to normalize text to uppercase.

7. **Treatment Display:** Treatment and supplies are shown inline: `"Treatment: Supply1, Supply2, Treatment Text"` (supplies first, then treatment text if non-empty).

8. **Patient Name Format:** Computed as `"lastName, firstName middleName extension"` trimmed of extra whitespace.

9. **List Serialization:** `symptoms` and `suppliesUsed` are stored in SQLite as pipe-delimited strings (`|`), parsed on read via `split('|')`.

10. **Sync Relay:** The WebSocket relay server is hosted on Render at `wss://iskolinic.onrender.com/ws`. The protocol supports chunked sync, heartbeats, and bidirectional push.

11. **Database Path:** `%APPDATA%/com.iskolinic/IskoLinic/clinic.db` (via `getApplicationSupportDirectory()`)

12. **Assets:** `assets/app-icon-white.png`, `assets/app-icon-colored.png`
13. **Tablet Integration:** The desktop app acts as a **Local Server**. The `clinic_input_app` (Tablet app) connects via QR pairing to the desktop's IP:8080. It uses an `Authorization: Bearer` token generated by the desktop.
14. **CORS Support:** The local server identifies with `Access-Control-Allow-Origin: *` to simplify tablet web/mobile client development.

---

## 🛠 Build & Deployment Guide

### Prerequisites

- [Flutter SDK](https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.29.0-stable.zip) (^3.29.0 or compatible Dart SDK ^3.9.2)
- Visual Studio 2022 with **Desktop development with C++** workload
- [Inno Setup 6](https://jrsoftware.org/isdl.php) (optional, for creating setup executable installers)

### 1. Build Production Executable

```powershell
# Fetch pub dependencies
flutter pub get

# Build production Windows executable
flutter build windows --release
```

Output binary location: `build/windows/x64/runner/Release/iskolinic.exe`

### 2. Build Development / Staging Executable

```powershell
# Build dev executable (connects to dev relay server)
flutter build windows --release --dart-define=ENV=dev
```

### 3. Packaging Installer with Inno Setup

To create an installer package (`IskoLinic-Setup.exe`):
1. Copy all contents of `build/windows/x64/runner/Release/` to an installer staging folder.
2. Compile the Inno Setup script to package `iskolinic.exe` along with all required `.dll` files and data folders into `dist/IskoLinic-Setup.exe`.

