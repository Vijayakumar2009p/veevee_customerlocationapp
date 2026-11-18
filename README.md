# VeeVee Field Locator

An Android app for VeeVee Infotech field staff. At a customer's site, the staff member opens the customer, taps **Set location**, and the GPS latitude/longitude is saved in Odoo 19 under **Contacts → Partner Assignment → Geolocation**.

| Folder | What it is |
|---|---|
| `app/` | Flutter source of the Android app (`VeeVee Field Locator`, package `com.veeveeinfotech.fieldlocator`) |
| `.github/workflows/build-apk.yml` | Optional: build the APK on GitHub instead of your PC |

Applies to: **Odoo 19** (Enterprise or Community: the geolocation fields come from the free `base_geolocalize` module) and **Android 8.0+**.

---

## 0. Test first with Odoo on your own PC

1. Start your local Odoo 19 listening on the network (`--http-interface=0.0.0.0`), install **Partners Geolocation** and create the field user (section 1).
2. Find the PC's address: `hostname -I` (e.g. `192.168.1.10`). Allow the port: `sudo ufw allow 8069/tcp`.
3. On the phone (same Wi-Fi), open `http://192.168.1.10:8069` in Chrome to be sure it loads.
4. Build a **debug** APK (`flutter build apk --debug`) or run over USB (`flutter run`). Only the TEST (debug) build allows `http://`; the RELEASE build needs `https://`.
5. In the app, page 1 **Odoo server**: choose `http://` in the dropdown, type `192.168.1.10:8069` and tap **Find**; page 2: choose the database; page 3: login and password.

`localhost` does not work from the phone: on the phone, "localhost" is the phone itself.

## 1. Odoo setup

### 1.1 Odoo apps needed

No custom Odoo module is needed: the app works with standard Odoo 19 (Enterprise or Community, on-premise, Odoo.sh or Odoo Online).

- Install **Partners Geolocation** (`base_geolocalize`, free): **Apps** → remove the *Apps* filter → search *geolocation* → **Activate**. It adds *Contacts → Partner Assignment → Geolocation* (Latitude, Longitude), where the app saves locations.
- Tell office users: do **not** click *Refresh / Compute based on address* on that tab (it replaces the GPS pin with an address estimate), and after editing a customer's address in Odoo, set the location again from the app (standard Odoo resets the pin to 0 when the address changes).

### 1.2 Create the field login(s)

**Settings → Users & Companies → Users → New**

| Field | Value |
|---|---|
| Name | Field Team |
| Login | e.g. `field@veeveeinfotech.com` |
| User type | Internal User |
| Contacts | **Creation** |
| Password | set one, e.g. `[PASSWORD]` (share it only with the field staff) |

Do **not** switch on two-factor authentication for this login; the app cannot use it.

### 1.3 What the app writes in Odoo

| Odoo field (`res.partner`) | Value |
|---|---|
| `partner_latitude`, `partner_longitude` | GPS position of the pin, 7 decimals |
| `date_localization` | date captured |
| `image_1920` | profile picture, from the photo starred in the app |
| Chatter (log note) | "Location set on site with VeeVee Field Locator by Ravi on 05-11-2026, 10:42. Lat …, Long …. GPS accuracy 8 m." |

New customers are created with: name, company/individual, phone, email, GSTIN (companies only), address and (for individuals) the company they work at. **Add contact** (under Mobile) adds any number of contact persons with name and mobile; each is created in Odoo as a contact under the new customer (company or individual). Up to 5 optional photos (camera or gallery) are attached to the "Customer created…" log note in the contact's chatter; the starred one (the first by default) becomes the contact's profile picture and is not repeated in the log note. On an existing customer, **Add photos** does the same (profile picture only if switched on).

Note: Odoo 19 has no separate *Mobile* field on contacts, so the mobile number is saved in **Phone**. If a module adds a `mobile` field, the app uses it automatically.

---

### 1.4 Field visits

Create the activity type once in each Odoo: **Settings → Technical → Activity Types → New** (developer mode), **Name** `Field Visit`, **Icon** `fa-map-marker`, Model *Contact* or empty, Sequence `26`. The app recognises it by the map-pin icon.

- **Office:** open a contact → *Activities* → **Field Visit**, write the job in *Summary* (e.g. "Calendar distribution 2027"), set the date and **Assigned to** = the staff member. For many customers at once: select them in the Contacts list → ⚙ *Actions* → *Schedule Activity*.
- **App:** each staff member logs in with **their own Odoo login** and sees only the visits assigned to them (*Field visits* in the menu and a banner on the home screen; *Overdue / Today / Upcoming*). Staff can also plan a visit from a customer page (*Plan field visit*).
- **Mark done:** the app takes the GPS position and shows the distance from the customer's saved location. Farther than 300 m only **warns** and asks for a reason. Remark and photos are optional. If the customer has no location yet, the app offers to save this place as its location.
- **In Odoo** the activity is marked done with a note like: *"Done on site by Ravi on 16-11-2026, 16:00. 40 m from the customer's saved location. Lat …, Long … (GPS ±6 m). Remark: Gave 2 calendars"*, with the photos attached.

Each field user needs their own Odoo login (one user licence each).

### 1.4b App layout (1.3.0)

Three tabs at the bottom: **Contacts · My Activities · Profile**. The ☰ menu on Contacts has Settings, Check for updates, Help & support, About and Log out.

**Profile** shows the Odoo user's photo (camera button changes it in Odoo), name, login, company and database; **My work** this month vs last month (customers added, locations set, activities done, field visits; counted in Odoo); **My customers**; **My history** (latest notes and done activities); **Sync**; **Phone check** (location permission, precise GPS, GPS on, battery saver, Odoo reachable, with "Fix this" buttons); **Large text**; **Report a problem** (note on your contact plus a To-Do for user 2, the main administrator); app version and Log out.

### 1.5 My Activities (any Odoo, no module needed)

Every activity assigned to the logged-in user in Odoo shows in the app under **My Activities** (home banner and menu): To-Do, Email, Call, Meeting, Document, Field Visit and custom types, on contacts and on other records (quotation, lead, invoice…).

| Type | Main button in the app |
|---|---|
| Call | **Call** (dialler), then "Call finished?" with a quick result (Spoke to customer / No answer / Call back later) |
| Email | **Email** (mail app), then Mark done |
| Meeting, To-Do, others | **Mark done** with an optional note and photos |
| Document | **Upload**: photo of the document, attached to the done message |
| Field Visit | **Mark done** with GPS distance check, plus **Set / Update location** |

Each activity also has **Reschedule** (Tomorrow / Next week / pick a date). *Mark done* can **plan the next activity** straight away. From a customer page, **Plan activity** creates any type for yourself. Everything works offline and is sent to Odoo later. In Odoo the activity is marked done the normal way, with the note in the chatter.

## 2. Before building: set your server

Edit `app/lib/config.dart`:

```dart
static const String defaultServerUrl = 'https://www.veeveeinfotech.com';
static const String defaultDatabase = '';   // put your database name here
```

The database list is fetched automatically when the server allows it. If your server hides it (common), the name typed here is used, so staff only enter login and password. The login is three pages: **1. Odoo server** (choose `https://` or `http://`, type the rest of the address, then *Next*) → **2. Database** (pick from the list, or type the name if the server hides it) → **3. Login** (login and password).

Other settings in the same file: GPS accuracy needed (20 m), "Save anyway" wait (45 s), sync interval.

---

## 3. Build the APK (Ubuntu)

### 3.1 One-time tools

1. **Flutter 3.47 or newer (stable)**: https://docs.flutter.dev/get-started/install/linux/android
2. **Android SDK** via Android Studio (or command-line tools), with Android SDK Platform 36 and Build-Tools.
3. **JDK 21** (`sudo apt install openjdk-21-jdk`).
4. Run `flutter doctor --android-licenses` and accept, then `flutter doctor` until Android shows a tick.

### 3.2 Create your signing key (once, keep it safe)

All updates must be signed with the **same key**, otherwise phones refuse to install them over the old app.

```bash
keytool -genkey -v -keystore ~/veevee-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias veevee
```

Create `app/android/key.properties` (never share or commit this file):

```properties
storePassword=[KEYSTORE PASSWORD]
keyPassword=[KEY PASSWORD]
keyAlias=veevee
storeFile=/home/<you>/veevee-upload.jks
```

Back up the `.jks` file and passwords. If they are lost, staff must uninstall and reinstall the app.

### 3.3 Build

```bash
cd app
flutter pub get
flutter build apk --release
```

The APK is at `app/build/app/outputs/flutter-apk/app-release.apk`.

If Gradle complains about versions (for example because your Flutter is a different version), let Flutter regenerate the Android folder and keep our settings:

```bash
cd app
mv android android_veevee
flutter create --platforms=android --org com.veeveeinfotech --project-name veevee_field_locator .
cp android_veevee/app/src/main/AndroidManifest.xml android/app/src/main/
cp -r android_veevee/app/src/main/res/* android/app/src/main/res/
# then copy the signing block and minSdk = 26 from android_veevee/app/build.gradle.kts
```

### 3.4 Install on phones

Share the APK (WhatsApp, Drive, email). On the phone: open it → allow **Install unknown apps** for that app → Install. On first use, allow **Location: While using the app** (choose *Precise*).

---

### 3.5 Customer TRIAL APK

GitHub builds a third file, **field-locator-TRIAL-apk** (about 10-12 MB), for customers who try the app on their own Odoo:

- allows `http://` servers (the normal release APK needs `https://`),
- shows **only contacts created by the logged-in Odoo user** (the list starts empty; staff add customers with *New customer*),
- 64-bit phones only (practically every Android 8+ phone from the last 6-7 years).

Build it yourself with:

```bash
ORG_GRADLE_PROJECT_allowHttp=true flutter build apk --release --target-platform android-arm64 --dart-define=OWN_CONTACTS_ONLY=true --dart-define=ALLOW_HTTP=true --dart-define=SHARED_LOGIN=true
```

### 3.6 Final APK for a customer (GitHub)

**GitHub → Actions → "Build customer APK" → Run workflow**, fill in:

| Field | Example |
|---|---|
| customer | `kalaimagal` (file name only) |
| server_url | `http://189.72.144.148:8069` (built in; staff only pick the database and log in) |
| database | empty = choose at login |
| own_contacts_only | ticked = each login sees only the customers it created |
| shared_login | ticked = all staff share one login (app asks each person's name) |

The APK appears under the run's *Artifacts* as `field-locator-<customer>-<version>`. It needs the signing key secrets (3.7) and stops with an error without them.

### 3.7 Signing key in GitHub (once)

1. Create the key (section 3.2).
2. `base64 -w0 ~/veevee-upload.jks > ~/veevee-upload.b64`
3. GitHub → repository → **Settings → Secrets and variables → Actions → New repository secret**, add:
   `KEYSTORE_BASE64` (contents of `veevee-upload.b64`), `KEYSTORE_PASSWORD`, `KEY_ALIAS` (`veevee`), `KEY_PASSWORD`.
4. Back up `veevee-upload.jks` and the passwords in two safe places. Then delete `veevee-upload.b64`.

## 4. Releasing an update

1. Raise the version in **both** `app/pubspec.yaml` (`version: 1.1.0+2`) and `app/lib/config.dart` (`appVersion = '1.1.0'`).
2. Build with the same signing key and upload the APK somewhere staff can download it (for example your website).
3. Send the APK to staff (WhatsApp, Drive). Optional: build with `--dart-define=UPDATE_URL=https://your-site/latest.json`, a small file like `{"latest_version": "1.4.1", "apk_url": "https://your-site/field-locator.apk"}`; phones then show "New version available".

---

## 5. How the app works

- **Login**: three pages (server → database → login and password). Username/password over Odoo's standard web session (`/web/session/authenticate`). With *Keep me logged in*, the password is kept in Android's encrypted storage so the app can log in again by itself when the Odoo session expires.
- **Your name**: asked once per phone. Everyone shares one Odoo login, so this name goes into each chatter note.
- **Customers**: all contacts (companies and individuals, except your own staff users and invoice/delivery addresses) are downloaded to the phone, so search works offline. One search box matches name, mobile, GSTIN and city.
- **Set location**: after location permission is allowed, the app takes the phone's current location by itself. The **Save location** button is ready as soon as the first reading arrives; GPS keeps improving the reading in the background until Save is tapped. *Find again* takes a fresh reading. Fake-GPS apps are blocked. The customer's address is not changed.
- **Existing location**: the app shows saved vs new point and distance, and asks before replacing.
- **Duplicates**: a new customer with the same mobile or GSTIN as an existing one shows a warning with the match.
- **Offline**: everything is saved on the phone first and sent to Odoo when the network is back (automatically every minute, on app open, or with *Sync now*). Entries Odoo refuses are shown in Settings with the reason, *Try again* and *Delete*.

---

## 6. Test checklist (first phone)

- [ ] Page 1 server URL → Find → page 2 database → page 3 login with the field login
- [ ] New individual → no GSTIN field; New company → GSTIN shown
- [ ] New customer with 3 photos, star the 2nd → Odoo picture = 2nd photo, log note has the other 2 photos
- [ ] Existing customer → Add photos → photos in log note
- [ ] New customer → Add contact (name + mobile) for a company and for an individual → both appear in Odoo under the customer's Contacts tab
- [ ] Enter your name; customer list loads; search by name, mobile, GSTIN, city
- [ ] Open a customer → Set location → location is taken by itself → Save location → Odoo contact shows Lat/Long in Partner Assignment, plus a chatter note
- [ ] Set location again for the same customer → "Replace saved location?" appears
- [ ] New customer with an existing mobile → duplicate warning
- [ ] Wrong GSTIN → error; valid GSTIN → state shown
- [ ] Airplane mode → save a location → "Saved on this phone" → turn network on → entry syncs

---

## 7. Troubleshooting

| Message | Fix |
|---|---|
| "Wrong login or password." | Check login/password in Odoo Users |
| "This Odoo user has two-factor authentication…" | Turn off 2FA for the field login |
| "Database … was not found" | Go back to page 2 and choose or type the correct database |
| "This address is not an Odoo server (404)" | Use the base address, e.g. `https://www.veeveeinfotech.com` |
| "This login can only set customer locations…" | Expected for the shared login; change other details in Odoo |
| "Fake GPS detected" | Developer options → Select mock location app → Nothing |

---

VeeVee Infotech · info@veeveeinfotech.com | +91 99657 82269
