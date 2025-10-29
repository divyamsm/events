# Claude Development Guide for StepOut

## Important Commands & Setup

### Firebase Deployment
**CRITICAL**: Firebase CLI requires Node v20+. Always use the nvm version:

```bash
# Deploy functions (ALWAYS use this command)
cd /Users/bharath/Desktop/events/StepOut/backend
PATH="$HOME/.nvm/versions/node/v20.18.1/bin:$PATH" firebase deploy --only functions --project stepout-3db1a

# Deploy firestore rules
PATH="$HOME/.nvm/versions/node/v20.18.1/bin:$PATH" firebase deploy --only firestore:rules --project stepout-3db1a

# Deploy firestore indexes
PATH="$HOME/.nvm/versions/node/v20.18.1/bin:$PATH" firebase deploy --only firestore:indexes --project stepout-3db1a
```

**Why**: The system default Node.js is v16.14.0, but Firebase CLI needs >=20.0.0. The correct Node is at `~/.nvm/versions/node/v20.18.1/bin/node`.

### Building Backend Functions
```bash
cd /Users/bharath/Desktop/events/StepOut/backend/functions
npm run build
```

### Building iOS App
```bash
cd /Users/bharath/Desktop/events/StepOut
xcodebuild -project StepOut.xcodeproj -scheme StepOut -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

## Project Structure

### Backend (Firebase Cloud Functions)
- **Location**: `/Users/bharath/Desktop/events/StepOut/backend/functions/src/index.ts`
- **Language**: TypeScript (Node.js 18 runtime)
- **Schemas**: `/Users/bharath/Desktop/events/StepOut/backend/functions/src/schema.ts`
- **Firestore Rules**: `/Users/bharath/Desktop/events/StepOut/backend/firestore.rules`

### iOS App
- **Location**: `/Users/bharath/Desktop/events/StepOut/StepOut/`
- **Language**: SwiftUI
- **Target iOS**: 16.0+
- **Shared Models**: `/Users/bharath/Desktop/events/StepOut/Shared/`

## Key Architecture Decisions

### Profile Data Flow
1. **Backend** (`index.ts`): `buildProfilePayload()` function constructs the profile response
   - Fetches user data from Firestore `users` collection
   - Includes: `displayName`, `username`, `bio`, `phoneNumber`, `photoURL`, `joinDate`, `primaryLocation`, `stats`
2. **iOS Parsing** (`ProfileBackend.swift`): `RemoteProfileResponse` struct parses backend response
3. **iOS Model** (`ProfileData.swift`): `UserProfile` struct is the app's internal model
4. **UI** (`ProfileView.swift`): SwiftUI views display and edit profile data

### Friend Request System
- **Collections**:
  - `invites`: Legacy system for contact-based invites
  - `friendInvites`: New system for app-to-app friend requests
  - `friends`: Bidirectional friendship records
- **Real-time**: Uses Firestore snapshot listeners for live updates
- **UI**: `UnifiedFriendsView.swift` with 3 tabs (Requests, Friends, Find Friends)

## Common Issues & Solutions

### Issue: Backend changes not reflecting in app
**Solution**: ALWAYS deploy functions after backend changes:
```bash
cd /Users/bharath/Desktop/events/StepOut/backend
PATH="$HOME/.nvm/versions/node/v20.18.1/bin:$PATH" firebase deploy --only functions --project stepout-3db1a
```

### Issue: Phone number not showing in UI
**Root Cause**: Backend wasn't returning `phoneNumber` field in response
**Fixed**:
- Added `phoneNumber` to `buildProfilePayload()` return object (lines 141, 204, 121)
- Added `phoneNumber` field to `RemoteProfile` struct (line 13)
- Added parsing in `RemoteProfileResponse.init` (line 61)

### Issue: Firestore permissions error
**Common Fix**: Check if using `resource.data` (for reads) vs `request.resource.data` (for writes) in firestore.rules

### Issue: "firebase: command not found"
**Solution**: Use the full path with Node v20 from nvm (see deployment commands above)

### Issue: SwiftUI onChange errors with iOS 16
**Solution**: Use single-parameter onChange syntax:
```swift
// ❌ Wrong (iOS 17+ only)
.onChange(of: value) { oldValue, newValue in }

// ✅ Correct (iOS 16+)
.onChange(of: value) { newValue in }
```

## Important Files Reference

### Backend Files
- `/Users/bharath/Desktop/events/StepOut/backend/functions/src/index.ts` - All Cloud Functions
- `/Users/bharath/Desktop/events/StepOut/backend/functions/src/schema.ts` - Request/response schemas (Zod)
- `/Users/bharath/Desktop/events/StepOut/backend/firestore.rules` - Security rules
- `/Users/bharath/Desktop/events/StepOut/backend/firestore.indexes.json` - Database indexes

### iOS Files
- `/Users/bharath/Desktop/events/StepOut/StepOut/ProfileView.swift` - Profile screen & edit UI
- `/Users/bharath/Desktop/events/StepOut/StepOut/UnifiedFriendsView.swift` - Friends/requests screen
- `/Users/bharath/Desktop/events/StepOut/StepOut/EmailAuthView.swift` - Sign-up flow
- `/Users/bharath/Desktop/events/StepOut/Shared/ProfileBackend.swift` - Backend API client
- `/Users/bharath/Desktop/events/StepOut/Shared/ProfileData.swift` - Data models

## Recent Changes (Oct 27, 2025)

### Phone Number Feature
- Added phone number collection during sign-up with E.164 format validation
- Created modern phone input UI with country code picker (15 countries)
- Added prompt for existing users without phone numbers
- Fixed backend to return phoneNumber in profile responses
- Auto-parsing of existing phone numbers to extract country code

### Friend Request System Improvements
- Unified friends UI with 3 tabs (Requests, Friends, Find Friends)
- Real-time Firestore listeners for incoming requests
- Toast notifications when sending friend requests
- Notification badge on Friends box showing pending request count
- Auto-fetch contacts when permission already granted

## Testing

### Firebase Project
- **Project ID**: `stepout-3db1a`
- **Region**: `us-central1`

### Test Data
User can create test friend requests via Node.js script:
```javascript
const admin = require('firebase-admin');
admin.initializeApp({ projectId: 'stepout-3db1a' });
const db = admin.firestore();
// Create test data...
```

## Git & Version Control
- **Main Branch**: `master`
- **Current Branch**: `master`
- User prefers clean, focused commits with descriptive messages

## Development Workflow
1. Make code changes
2. Build backend: `cd backend/functions && npm run build`
3. Deploy if backend changed: Use PATH with nvm Node v20
4. Build iOS app: Use xcodebuild command
5. Test on simulator/device
6. Commit when feature is complete

## Notes
- User is building a social events app called "StepOut"
- Focus on Instagram/LinkedIn-style UX patterns
- Prioritize modern, clean UI with gradients and smooth animations
- Always test with real data flow: backend → iOS → UI
- Deploy functions after EVERY backend change - this is critical!
