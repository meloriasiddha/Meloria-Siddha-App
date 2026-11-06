# Meloria Siddha — Clinic App

Clinic management app for **Meloria Siddha and Varma Clinic**, Tirunelveli.
Built with **Flutter** (one codebase → Android, Windows/PC, web) and **Supabase** (database + login).

**Phase 1 (this version): Staff & Doctor app**
- Staff / doctor login
- Patient registration with auto ID (`MEL1-0001`), referred-by, search by name / phone / ID / referrer
- Visit intake: visit type, in-clinic / online, vitals (BMI auto), main complaint
- Allergies and current medications (Siddha / Allopathy) — staff or doctor can enter
- Today screen: waiting list that refreshes every 20 seconds
- Doctor consultation: complaints + duration, history, family & personal history,
  diet plan (with templates), medicines from stock (earliest-expiry batch picked automatically),
  treatment advice, next visit date
- Medicine stock with batches, expiry and low-stock alerts (stock reduces automatically when prescribed)
- Feedable treatment advice list

Coming next: Phase 2 billing & PDF · Phase 3 patient app · Phase 4 diabetes tracker · Phase 5 PC version.

---

## Setup (one time, about 15 minutes)

### 1. Create the database
1. Sign up at **supabase.com** (use the clinic Gmail) → **New project**
   - Name: `meloria-siddha` · Region: **Mumbai (ap-south-1)** · set a strong database password and keep it safe.
2. Open **SQL Editor → New query**, paste everything from [`supabase/schema.sql`](supabase/schema.sql), press **Run**.

### 2. Connect the app
In Supabase go to **Project Settings → API** and copy:
- **Project URL**
- **anon / public key** (never the `service_role` key)

Paste them into [`lib/config.dart`](lib/config.dart) (`defaultValue: '...'`),
**or** add them as GitHub secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY`
(repo → Settings → Secrets and variables → Actions) so the automatic build uses them.

### 3. Create the logins
Supabase → **Authentication → Users → Add user** (email + password, tick *Auto confirm*).
Create one for the doctor and one for the staff member.

### 4. Register them as doctor / staff
SQL Editor → run (change the emails and names):

```sql
insert into staff_profiles (id, full_name, role)
select id, 'Dr. Your Name', 'doctor' from auth.users where email = 'doctor@example.com';

insert into staff_profiles (id, full_name, role)
select id, 'Staff Name', 'staff' from auth.users where email = 'staff@example.com';
```

### 5. Forgot password email (one time)
Supabase → **Authentication → Emails → Reset Password** → replace the message body with:

```html
<h2>Meloria Siddha – reset your password</h2>
<p>Your reset code is:</p>
<h1>{{ .Token }}</h1>
<p>Enter this code in the app. It expires in 1 hour.</p>
```
→ **Save**. The app's *Forgot password?* screen asks for this code.

### 6. Get the app on your phone
- **Automatic:** every push to GitHub builds the app. Open the repo → **Actions** → latest run →
  download **meloria-siddha-apk** → unzip → install `app-release.apk` on the phone
  (allow "Install unknown apps" once).
- **On a computer with Flutter:** `flutter pub get` then `flutter run` or `flutter build apk --release`.

---

## App signing key (important)
Every update must be signed with the same **Meloria signing key** (`meloria-release.jks`),
otherwise Android will not install it over the old version.
- The key is **not** in this repository (never commit it). Keep the backup copy safe (Google Drive + one offline copy).
- Local build: create `android/key.properties` with `storeFile`, `storePassword`, `keyAlias=meloria`, `keyPassword`.
- GitHub build: add repo secrets `MELORIA_KEYSTORE_BASE64`, `MELORIA_KEYSTORE_PASSWORD`, `MELORIA_KEY_PASSWORD`.
- App ID: `com.meloriasiddha.staff` (the patient app will be `com.meloriasiddha.patient`).

## Where to change things

| You want to change | File |
| --- | --- |
| Colours, fonts, button style | `lib/theme.dart` |
| Supabase keys, app name, clinic name | `lib/config.dart` |
| Database tables, patient ID format, starter lists | `supabase/schema.sql` |
| All database calls | `lib/services/db.dart` |
| Login screen | `lib/screens/login_screen.dart` |
| Today / waiting list | `lib/screens/today_screen.dart` |
| Patient search / registration / details | `lib/screens/patients_screen.dart`, `patient_form_screen.dart`, `patient_detail_screen.dart` |
| Vitals & intake | `lib/screens/intake_screen.dart` |
| Doctor case sheet | `lib/screens/consultation_screen.dart` |
| Stock & batches | `lib/screens/stock_screen.dart`, `medicine_form_screen.dart` |
| Advice list, sign out | `lib/screens/more_screen.dart` |
| Allergies & current meds card | `lib/widgets/allergies_meds.dart` |
| Logo & icon | `assets/images/`, `assets/icon/` (then run `dart run flutter_launcher_icons`) |

## Project layout

```
lib/
  main.dart            app start, login check
  config.dart          keys and names
  theme.dart           Meloria colours and fonts
  services/db.dart     every database call
  screens/             one file per screen
  widgets/             shared pieces (cards, fields, brand mark)
supabase/schema.sql    database tables + security rules
assets/                logo and app icon
```

## Security notes
- Patient data lives only in Supabase; the code holds no patient data.
- Every table has row-level security: only logged-in doctor/staff accounts can read or write.
- Keep this GitHub repository **private**.
