**3D Print Queue App Design**

**1. Overview**
A cross-platform Flutter application (macOS, iOS, Android, Web) that manages a 3D print queue. The app follows a client-server architecture, with a Flutter front-end connecting over HTTP to a standalone Dart-based API server. The server advertises itself on the local network using mDNS, allowing clients to automatically discover it. Clients can also manually configure a custom server URL for remote access. This decoupling ensures the database remains independent and accessible to multiple clients simultaneously.

---

**2. Key Requirements**

* **Data model**: Projects (BambuLab `.bambu` or sliced files), name, priority (integer or enum), scheduled date, description, and (optional) a custom `orderIndex` for drag‑and‑drop ordering.
* **Operations**: Add new job, edit existing, delete, reorder.
* **Views**: List of jobs with sort options (by priority, date, name, custom order). Buttons on each list item for edit/delete. Drag‑and‑drop enabled only when custom ordering is active.
* **Authentication**: Single global password prompt, no user roles.
* **Refresh**: Manual refresh button and pull-to-refresh functionality to update the job list.
* **Server Discovery**: Automatic discovery of the API server on the local network using mDNS.
* **Server Configuration**: Settings screen to configure a custom server URL for remote access.

---

**3. Architecture**

**3.1 Backend Service**

* **Runtime Stack**: Dart-based server using `shelf` for HTTP handling and routing.
* **Database**: SQLite database stored in the filesystem.
* **Service Layer**: A standalone REST server running as a service.
* **Service Discovery**: Uses mDNS (Multicast DNS) to advertise itself on the local network as "_printqueue._tcp".
* **CORS Support**: Includes CORS middleware to allow cross-origin requests from web browsers.
* **Network Binding**: Binds to all network interfaces (0.0.0.0) to allow connections from any device on the network.
* **Endpoints**:

    * `GET /jobs` (with optional sort query)
    * `POST /jobs`
    * `PUT /jobs/{id}`
    * `DELETE /jobs/{id}`
    * `POST /auth/login` (password auth)
    * `PUT /jobs/reorder` (batch update of `orderIndex`)

**3.2 Flutter Frontend**

* **Platforms**: Targets macOS, iOS, Android, and Web from a single codebase.
* **State management**: `Riverpod` for authentication, job list state, and server discovery.
* **Routing**: `go_router` for declarative routing between screens.
* **Server Discovery**:
    * Uses mDNS to discover API servers on non-Android platforms.
    * Uses network scanning on Android platforms (as mDNS reusePort is not supported).
    * Provides a Quick Scan feature on Android to scan specific IP ranges.
    * Includes verbose logging option for troubleshooting discovery issues.
* **Server Configuration**: Allows manual configuration of a custom server URL for remote access.
* **Refresh Functionality**: Includes a refresh button in the app bar and pull-to-refresh support.
* **Settings Screen**: Provides UI for server configuration and discovery.
* **Build & Deployment**:

    * **macOS**: `flutter config --enable-macos-desktop` → `flutter build macos`.
    * **iOS**: `flutter build ios`.
    * **Android**: `flutter build apk` or `appbundle`.
    * **Web**: `flutter build web`.

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
  main.dart             # App entrypoint + routing
  src/
    models/             # Data classes (PrintJob)
    services/           
      api_service.dart         # API client for server communication
      auth_service.dart        # Authentication service
      server_discovery_service.dart  # mDNS server discovery
    providers/          
      providers.dart    # Providers (Auth, Jobs, ServerDiscovery)
    screens/
      login_screen.dart        # Password authentication
      job_list_screen.dart     # Main job list with refresh
      job_edit_screen.dart     # Add/edit job form
      settings_screen.dart     # Server configuration
    widgets/
      job_item.dart     # ListTile with edit/delete
```

---

**6. UI Components**

1. **LoginScreen**

    * Single `TextField` for password + `ElevatedButton`.
    * On success, navigate to `JobListScreen`.

2. **JobListScreen**

    * AppBar with refresh button, settings button, sort menu, and logout button.
    * `RefreshIndicator` for pull-to-refresh functionality.
    * When sort==custom: use `ReorderableListView`; otherwise, `ListView.builder`.
    * List items: custom `JobItem` showing name, date, priority, description excerpt, `IconButton`s for edit/delete.
    * FloatingActionButton to add new job.

3. **JobEditScreen**

    * `TextFormField`s for name, date picker, priority dropdown, description, file URL picker.
    * `Save`/`Cancel` buttons.

4. **SettingsScreen**

    * Displays current server URL and connection status.
    * Form for entering and saving a custom server URL.
    * Button to clear custom URL and use automatic discovery.
    * List of discovered servers on the local network.
    * Refresh button to update the list of discovered servers.
   * On Android: Quick Scan feature to scan specific IP ranges.
   * Debug settings with verbose logging option for troubleshooting.
   * Default server URL configuration for fallback when discovery fails.

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

**9. Implemented Features**

* Login on Enter key press - Press Enter in the password field to submit login
* Back button in Settings screen - Easy navigation back to the main screen
* Back button in Job Edit screen - Ability to abort job creation/editing
* File chooser for selecting 3D model files - Platform-specific file picking with proper error handling
* Cross-platform file access - macOS entitlements for file access

**10. Planned Features**

* 3D preview image generation (stretch goal)
* Real-time list updates on external changes
* Improved server discovery for Android devices
* Store file instead of path

---
