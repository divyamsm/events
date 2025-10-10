# Firebase Setup

This guide walks through configuring Firebase as the backend for the StepOut apps (main app and widget) and keeping secrets out of source control.

## 1. Create a Firebase project

1. Visit the [Firebase console](https://console.firebase.google.com/) and create a new project (for example, `stepout-prod`).
2. Disable Google Analytics for now unless you already have a measurement plan. You can re-enable it later.

## 2. Register the iOS apps

For each target you plan to connect to Firebase, register its bundle identifier.

### Main app

- **Bundle ID:** `com.stepout.app`
- **App nickname:** `StepOut` (optional)

### Widget (optional for now)

- **Bundle ID:** `com.stepout.app.widget`
- **App nickname:** `StepOutWidget`
- You can add the widget later once the main app is verified.

After registering the main app, download the generated `GoogleService-Info.plist`. Do **not** commit this file; keep it in a safe location.

## 3. Store the config file locally

Place the downloaded `GoogleService-Info.plist` at:

```
StepOut/Support/Firebase/GoogleService-Info.plist
```

The directory `StepOut/Support/Firebase` is ignored by Git; create it locally if it does not exist and drag the plist into Xcode (select the `StepOut` target only, leave the widget unchecked for now).

If you keep multiple Firebase environments (Dev/Prod), store the additional plists in the same folder with names such as `GoogleService-Info-Dev.plist` and switch them with a build configuration or run script.

## 4. Add Firebase SDKs via Swift Package Manager

1. In Xcode, open **File ▸ Add Packages…**.
2. Enter the URL `https://github.com/firebase/firebase-ios-sdk`.
3. Choose **Up to Next Major Version** and keep the latest stable version.
4. Add the following products to the `StepOut` target (add more later as needed):
   - `FirebaseAnalytics`
   - `FirebaseAuth`
   - `FirebaseFirestore`
   - `FirebaseStorage` (optional for image hosting)
   - `FirebaseMessaging` (optional for push notifications)
5. Repeat for the widget target only if it will talk to Firebase (usually unnecessary).

Swift Package Manager writes dependency metadata to the Xcode project; commit those updates as usual.

## 5. Initialize Firebase in the app

`StepOutApp` calls `FirebaseApp.configure()` when the Firebase SDK is present. Once the Swift packages are added and the plist is included in the project, Firebase will finish initializing during launch.

## 6. Enable Phone Authentication

1. In the Firebase console open **Build ▸ Authentication**, go to the **Sign-in method** tab, and enable **Phone**.
2. Download a fresh copy of `GoogleService-Info.plist`—it should include a `REVERSED_CLIENT_ID` entry. (If you don’t see one, re-download; Firebase generates it for every project.)
3. In Xcode, make sure the file is added to the **StepOut** target and that `REVERSED_CLIENT_ID` is also registered as a URL scheme under **Target ▸ Info ▸ URL Types** (paste the exact value, e.g. `app-1-xxxxxxxx-ios-…`).
4. Add at least one **Test phone number** in the Firebase console so you can exercise the flow on simulator without APNs. The app also ships with a local simulator shortcut—when running in the sim you’ll see a hint to enter `123456`, which signs you in anonymously so you can continue exploring the UI.
5. For real devices you must upload an APNs key or certificate in the Authentication settings so that silent APNs notifications can complete automatic verification on iOS.
6. The project automatically sets `Auth.auth().settings?.isAppVerificationDisabledForTesting = true` when running in DEBUG or on the simulator. Remove this flag (or wrap it in a build flag) before shipping.

Sims do not receive real SMS messages. If you use the simulator, rely on test numbers or temporarily set `Auth.auth().settings?.isAppVerificationDisabledForTesting = true` during development.

## 7. Prepare Firestore

1. In the Firebase console open **Build ▸ Firestore Database** and create a database in **Production mode**.
2. Choose a region close to your users, e.g. `us-central1`.
3. Add preliminary security rules so only authenticated users can read/write. Adjust once the final data model is ready:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /events/{eventId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == request.resource.data.hostId;
    }
  }
}
```

## 8. Optional: Set up the Firebase CLI

Install the CLI if you want to manage rules, indexes, or hosting from source control:

```
npm install -g firebase-tools
firebase login
firebase init firestore
```

This repository ignores the generated `.firebaserc` and `firebase.json` files by default. Remove the patterns from `.gitignore` if you decide to check them in.

## 9. Verify locally

1. Clean and build the project in Xcode.
2. Run the app on a simulator or device; startup logs should show Firebase initialization.
3. The Analytics dashboard should report the first launch within a few minutes.

You are now ready to model Firestore collections for events and sync RSVP updates with the backend.
