# 🧪 Testing Guide: 3 New APIs with Seed Data

## ⚠️ IMPORTANT: Hardcoded User Information

**The iOS app currently uses a hardcoded user ID for Bharath.** This means:
- The app always operates as Bharath Raghunath (ID: `B2A4A608-1D12-4AC3-8C6C-5C9F0A2F9942`)
- There is NO user authentication or login system
- All API calls use this hardcoded userId

### Where the hardcoding exists:

1. **[EventData.swift:23](/Users/bharath/Desktop/events/StepOut/Shared/EventData.swift#L23)** - `UserSession.sample` hardcodes Bharath's ID
2. **[ContentView.swift:43](/Users/bharath/Desktop/events/StepOut/StepOut/ContentView.swift#L43)** - Main app uses `UserSession.sample`
3. **[ProfileView.swift:274](/Users/bharath/Desktop/events/StepOut/StepOut/ProfileView.swift#L274)** - Profile defaults to `UserSession.sample.user.id`

**To support multiple users in the future:**
- Implement Firebase Authentication
- Replace `UserSession.sample` with a dynamically created session from the authenticated user
- Update ContentView to create UserSession from the logged-in Firebase user

---

## ✅ What's Been Set Up

### 1. **Seed Data Created**
Your database now has:
- **6 test users** (including you as Bharath)
- **3 confirmed friends** for Bharath (Alice, Bob, David)
- **3 sent invites** from Bharath (to Carol, +14155551099, newuser@example.com)
- **1 received invite** for Bharath (from Emma)
- Additional friendships between other users for comprehensive testing

### 2. **APIs Integrated**
All 3 APIs are now callable from your iOS app:
- `listFriends` - [ProfileBackend.swift:193-224](StepOut/Shared/ProfileBackend.swift)
- `sendFriendInvite` - [ProfileBackend.swift:227-238](StepOut/Shared/ProfileBackend.swift)
- `shareEvent` - [FirebaseEventBackend.swift:175-185](StepOut/Shared/FirebaseEventBackend.swift)

---

## 🎯 Your Test Account

```
Name:  Bharath Raghunath
ID:    B2A4A608-1D12-4AC3-8C6C-5C9F0A2F9942
Phone: +14155551001
Email: bharath@stepout.app
```

### Your Friends (3):
- ✅ **Alice Johnson** - A1B2C3D4-E5F6-7890-ABCD-EF1234567890
- ✅ **Bob Smith** - F1E2D3C4-B5A6-9870-FEDC-BA9876543210
- ✅ **David Chen** - AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE

### Your Sent Invites (3):
- 📤 To **Carol Davis** (existing user) - 12345678-90AB-CDEF-1234-567890ABCDEF
- 📤 To **+14155551099** (new user)
- 📤 To **newuser@example.com** (new user)

### Your Received Invites (1):
- 📥 From **Emma Wilson** - 11111111-2222-3333-4444-555555555555

---

## 🧪 Test in iOS App

### **Method 1: Test via Profile View** (Recommended)

Add this code to `ProfileView.swift` inside `FriendsSheetView`:

```swift
Section("🧪 Test New APIs") {
    Button("Test listFriends") {
        Task {
            let backend = FirebaseProfileBackend()
            do {
                let userId = UUID(uuidString: "B2A4A608-1D12-4AC3-8C6C-5C9F0A2F9942")!
                let (friends, invites) = try await backend.listFriends(
                    userId: userId,
                    includeInvites: true
                )
                print("✅ listFriends SUCCESS")
                print("   Friends: \(friends.count)")
                print("   Invites: \(invites.count)")
                friends.forEach { print("   - \($0.displayName)") }
            } catch {
                print("❌ Error: \(error)")
            }
        }
    }

    Button("Test sendFriendInvite") {
        Task {
            let backend = FirebaseProfileBackend()
            do {
                let userId = UUID(uuidString: "B2A4A608-1D12-4AC3-8C6C-5C9F0A2F9942")!
                let inviteId = try await backend.sendFriendInvite(
                    senderId: userId,
                    recipientPhone: "+14155559999",
                    recipientEmail: nil
                )
                print("✅ sendFriendInvite SUCCESS: \(inviteId)")
            } catch {
                print("❌ Error: \(error)")
            }
        }
    }
}
```

### **Method 2: Test via Terminal** (Quick verification)

```bash
# Test listFriends
curl -s -X POST https://us-central1-stepout-3db1a.cloudfunctions.net/listFriends \
  -H 'Content-Type: application/json' \
  -d '{"data":{"userId":"B2A4A608-1D12-4AC3-8C6C-5C9F0A2F9942","includeInvites":true}}' \
  | python3 -m json.tool

# Test sendFriendInvite
curl -s -X POST https://us-central1-stepout-3db1a.cloudfunctions.net/sendFriendInvite \
  -H 'Content-Type: application/json' \
  -d '{"data":{"senderId":"B2A4A608-1D12-4AC3-8C6C-5C9F0A2F9942","recipientPhone":"+14155559999"}}' \
  | python3 -m json.tool

# Test shareEvent (need an event ID first)
curl -s -X POST https://us-central1-stepout-3db1a.cloudfunctions.net/shareEvent \
  -H 'Content-Type: application/json' \
  -d '{"data":{"eventId":"YOUR_EVENT_ID","recipientIds":["12345678-90AB-CDEF-1234-567890ABCDEF"]}}' \
  | python3 -m json.tool
```

---

## 📱 Expected Results in iOS App

### **When you test `listFriends`:**

**Console Output:**
```
[Backend] calling listFriends
✅ listFriends SUCCESS
   Friends: 3
   Invites: 4
   - Alice Johnson
   - Bob Smith
   - David Chen
```

**What the API returns:**
- 3 confirmed friends (Alice, Bob, David)
- 4 pending invites (3 sent by you, 1 received from Emma)

### **When you test `sendFriendInvite`:**

**Console Output:**
```
[Backend] calling sendFriendInvite
✅ sendFriendInvite SUCCESS: <new-invite-id>
```

**Verification:**
- Open [Firestore Console](https://console.firebase.google.com/project/stepout-3db1a/firestore)
- Check `friendInvites` collection
- You'll see a new invite document

### **When you test `shareEvent`:**

**Console Output:**
```
[Backend] calling shareEvent
✅ shareEvent SUCCESS
```

**Verification:**
- Open event in Firestore
- Check `sharedInviteFriendIds` array
- Should contain Carol's ID: `12345678-90AB-CDEF-1234-567890ABCDEF`

---

## 🎬 Complete Test Flow

### **Step 1: Run the app**
```bash
open StepOut/StepOut.xcodeproj
# Press Cmd+R to run
```

### **Step 2: Navigate to Profile**
- Tap **Profile** tab at the bottom
- Tap **"Friends"** button

### **Step 3: You should see:**
- **Friends section:** Alice Johnson, Bob Smith, David Chen
- **Pending invites section:**
  - "Invite sent" × 3 (Carol, phone, email)
  - "Awaiting your response" × 1 (from Emma)

### **Step 4: Test the APIs**
- Add the test buttons from Method 1 above
- Tap each button and watch Xcode console

### **Step 5: Monitor Firebase Logs** (optional)
```bash
cd StepOut/backend
firebase functions:log --only listFriends,sendFriendInvite,shareEvent
```

---

## 🔍 Verify in Firestore Console

Check your data at: https://console.firebase.google.com/project/stepout-3db1a/firestore

### Collections to inspect:
- **users** - All 6 test users
- **friends** - Friendship relationships
- **friendInvites** - Pending invites (should have 5 total)
- **events** - Your events (for shareEvent testing)

---

## 🐛 Troubleshooting

### "No friends showing up"
- Check if `getProfile` is being called (it already loads friends)
- Try calling `listFriends` directly to compare results

### "Function not found"
- Verify functions are deployed: `firebase functions:list`
- All 3 functions should show in the list

### "Network error"
- Check simulator has internet
- Try the curl commands to verify APIs work

### "Duplicates in friend list"
- This is expected if testing multiple times
- The seed script can be run again: `node tools/seedFriendsAndInvites.cjs`

---

## 🎉 Success Criteria

You'll know everything works when:

✅ **listFriends** returns 3 friends + 4 invites
✅ **sendFriendInvite** creates a new invite in Firestore
✅ **shareEvent** adds friend IDs to event's `sharedInviteFriendIds`
✅ Profile view shows your 3 friends
✅ Profile view shows 4 pending invites

---

## 📝 Notes

- The seed script can be run multiple times (it uses `merge: true`)
- All test users have the pattern: +1415555100X
- Carol is NOT your friend yet, but has received an invite
- Emma sent you an invite but you haven't accepted yet
- Alice and Bob are confirmed friends who can see your events

**Ready to test!** 🚀
