**3D Print Queue App Design**

**1. Overview**
A cross-platform Flutter application (macOS, iOS, Android) that manages a 3D print queue. The app is purely a front-end interface, connecting over HTTP/GraphQL to a standalone backend service hosted on your home server. This decoupling ensures the database (SQL or graph) remains independent and accessible to additional clients if needed.

---

**2. Key Requirements**

* **Data model**: Projects (BambuLab `.bambu` or sliced files), name, priority (integer or enum), scheduled date, description, and (optional) a custom `orderIndex` for drag‑and‑drop ordering.
* **Operations**: Add new job, edit existing, delete, reorder.
* **Views**: List of jobs with sort options (by priority, date, name, custom order). Buttons on each list item for edit/delete. Drag‑and‑drop enabled only when custom ordering is active.
* **Authentication**: Single global password prompt, no user roles.

---

**3. Architecture**

**3.1 Backend Service**

* **Runtime Stack**: Dart-based server using `shelf`, or Python Flask—no Node.js required.
* **Database**: SQLite or PostgreSQL installed directly in the container (CT) filesystem—no Docker.
* **Service Layer**: A standalone REST or GraphQL server running as a `systemd` service.
* **Endpoints / Queries**:

    * `GET /jobs` (with optional sort query)
    * `POST /jobs`
    * `PUT /jobs/{id}`
    * `DELETE /jobs/{id}`
    * `POST /auth/login` (password auth)
    * `PUT /jobs/reorder` (batch update of `orderIndex`)

**3.2 Flutter Frontend**

* **Platforms**: Targets macOS, iOS, and Android from a single codebase.
* **State management**: `Riverpod` for authentication and job list state (preferred for Dart consistency).
* **Routing**: `go_router` for declarative routing.
* **Build & Deployment**:

    * **macOS**: `flutter config --enable-macos-desktop` → `flutter build macos`.
    * **iOS**: `flutter build ios`.
    * **Android**: `flutter build apk` or `appbundle`.
* **Platforms**: Targets macOS, iOS, and Android from a single codebase.
* **State management**: `Provider` or `Riverpod` for authentication and job list state.
* **Routing**: `go_router` or `Navigator` for Login → MainFlow → Add/Edit.
* **Build & Deployment**:

    * **macOS**: Enable desktop support (`flutter config --enable-macos-desktop`) and package as a standalone `.app` via `flutter build macos`.
    * **iOS/Android**: Standard mobile build using `flutter build ios` and `flutter build apk`/`appbundle`.

---

**4. Database Schema**

```sql
CREATE TABLE print_jobs (
  id SERIAL PRIMARY KEY,
  file_url TEXT NOT NULL,
  name TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 0,
  scheduled_at TIMESTAMP NOT NULL,
  description TEXT,
  order_index INTEGER DEFAULT NULL
);
```

* `order_index` is `NULL` when custom ordering is inactive.

---

**5. Flutter App Structure**

```text
lib/
  main.dart             # App entrypoint + auth check
  src/
    models/             # Data classes (PrintJob)
    services/           # API client, auth service
    providers/          # Providers (AuthProvider, JobProvider)
    screens/
      login_screen.dart
      job_list_screen.dart
      job_edit_screen.dart
    widgets/
      job_item.dart     # ListTile with edit/delete
```

---

**6. UI Components**

1. **LoginScreen**

    * Single `TextField` for password + `ElevatedButton`.
    * On success, navigate to `JobListScreen`.

2. **JobListScreen**

    * AppBar with `PopupMenuButton` for sort mode: priority, date, name, custom.
    * When sort==custom: use `ReorderableListView`; otherwise, `ListView.builder`.
    * List items: custom `JobItem` showing name, date, priority, description excerpt, `IconButton`s for edit/delete.
    * FloatingActionButton to add new job.

3. **JobEditScreen**

    * `TextFormField`s for name, date picker, priority dropdown, description, file URL picker.
    * `Save`/`Cancel` buttons.

---

**7. Drag & Drop Custom Ordering**

* Use Flutter's `ReorderableListView` when in "Custom Order" mode.
* On reorder, capture new index map and send batch `PUT /jobs/reorder` with list of `{id, order_index}`.

---

**8. Authentication**

* Store single password in app (e.g., in `SharedPreferences` after first set).
* On launch, if no password set: prompt to create. Else: prompt to enter.
* On logout or incorrect entry, clear session and return to login.

---
