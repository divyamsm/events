# Chat Feature Implementation Status

## ✅ COMPLETED - Frontend UI

### 1. Tab Bar Navigation (Instagram-style)
**Files Created:**
- `MainTabView.swift` - Main tab container with 3 tabs
- Tab structure: Home | Chats | Profile

**Status:** ✅ UI Complete, added to Xcode project

### 2. Swipeable Home Tab
**Location:** `MainTabView.swift` (lines 74-182)
**Features:**
- Custom animated tab bar for Upcoming/Past
- Swipe left/right gesture support
- Smooth spring animations
- `TabView` with `.page` style for native swipe

**Status:** ✅ Complete

### 3. Chats Tab UI
**File:** `ChatsTabView.swift`
**Features:**
- List of all event group chats
- Chat row with event title, last message, timestamp
- Empty state with message
- Navigation to individual chat views

**Status:** ✅ UI Complete, backend integration pending

### 4. Individual Chat View
**File:** `ChatView.swift`
**Features:**
- iMessage-style chat bubbles (blue for sent, gray for received)
- Message input bar with send button
- ScrollView with auto-scroll to latest message
- Sender name display for other users

**Status:** ✅ UI Complete, backend integration pending

### 5. Event List View
**File:** `EventListView.swift`
**Features:**
- Reusable event card component
- Event image/placeholder
- Date, time, location display
- Action buttons (RSVP, Edit, Delete, Share)
- Privacy badge (Public/Private)

**Status:** ⚠️ Needs minor fixes (imageURL vs coverImageURL)

---

## 🚧 IN PROGRESS - Backend Integration

### Firestore Schema Design

#### Collections Structure:
```
/chats/{chatId}
  - eventId: string
  - eventTitle: string
  - participants: string[] (user IDs who accepted event)
  - lastMessage: {
      text: string
      senderId: string
      senderName: string
      timestamp: timestamp
    }
  - createdAt: timestamp
  - updatedAt: timestamp

/chats/{chatId}/messages (subcollection)
  /{messageId}
    - senderId: string
    - senderName: string
    - senderPhotoURL: string?
    - text: string
    - timestamp: timestamp
    - type: "text" | "system"
```

**Access Rules:**
- Only users in `participants` array can read/write
- Automatically add user to participants when they accept event RSVP
- Create chat when event is created

---

## ⏳ TODO - Backend Implementation

### Cloud Functions to Create

1. **createChat** (automatic, called when event created)
   ```typescript
   Input: { eventId, eventTitle, ownerId }
   Output: { chatId }
   - Creates chat document
   - Adds owner to participants
   ```

2. **sendMessage**
   ```typescript
   Input: { chatId, text }
   Output: { messageId }
   - Validates user is in participants
   - Creates message in subcollection
   - Updates lastMessage in chat document
   ```

3. **getMessages**
   ```typescript
   Input: { chatId, limit?, cursor? }
   Output: { messages: Message[], nextCursor? }
   - Fetches paginated message history
   - Validates user access
   ```

4. **listChats**
   ```typescript
   Input: { userId }
   Output: { chats: ChatInfo[] }
   - Returns all chats where user is in participants
   - Sorted by lastMessage.timestamp desc
   ```

5. **getChatInfo**
   ```typescript
   Input: { chatId }
   Output: { chat: ChatInfo }
   - Returns chat metadata
   - Validates user access
   ```

6. **updateEventParticipants** (modify existing RSVP function)
   - When user accepts event → add to chat.participants
   - When user declines → remove from chat.participants

### Firestore Security Rules
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /chats/{chatId} {
      allow read: if request.auth != null &&
                     request.auth.uid in resource.data.participants;
      allow write: if false; // Only via Cloud Functions

      match /messages/{messageId} {
        allow read: if request.auth != null &&
                       request.auth.uid in get(/databases/$(database)/documents/chats/$(chatId)).data.participants;
        allow create: if request.auth != null &&
                         request.auth.uid in get(/databases/$(database)/documents/chats/$(chatId)).data.participants;
      }
    }
  }
}
```

### iOS Real-time Listeners
**Location:** `ChatViewModel` in `ChatView.swift`

Need to implement:
```swift
import FirebaseFirestore

func startListeningForMessages() {
    let db = Firestore.firestore()
    listener = db.collection("chats")
        .document(chatId)
        .collection("messages")
        .order(by: "timestamp", descending: false)
        .addSnapshotListener { snapshot, error in
            guard let documents = snapshot?.documents else { return }
            self.messages = documents.compactMap { /* parse */ }
        }
}
```

### Indexes Required
```json
{
  "indexes": [
    {
      "collectionGroup": "messages",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "timestamp", "order": "ASCENDING" }
      ]
    }
  ]
}
```

---

## 🎯 NEXT STEPS

### Phase 1: Fix Build (5 min)
1. Fix `EventListView.swift` - change `coverImageURL` to `imageURL`
2. Build and verify tabs work

### Phase 2: Backend Setup (30 min)
1. Create Firestore schema
2. Implement Cloud Functions (sendMessage, getMessages, listChats)
3. Deploy functions
4. Deploy security rules

### Phase 3: iOS Integration (20 min)
1. Add Firestore listeners to `ChatViewModel`
2. Wire up `ChatsViewModel.loadChats()` to call backend
3. Test real-time messaging

### Phase 4: Event Integration (15 min)
1. Auto-create chat when event is created
2. Add "Chat" button to event details
3. Update RSVP flow to add user to chat participants

### Phase 5: Testing (10 min)
1. Create event → verify chat created
2. Accept RSVP → verify added to chat
3. Send messages → verify real-time updates
4. Decline event → verify removed from chat

---

## 🐛 KNOWN ISSUES

1. **EventListView build error** - `coverImageURL` should be `imageURL`
2. **Xcode project** - New files added but may need clean build
3. **CreateEventView** - Needs update to call createChat function
4. **AttendanceSheet** - Placeholder, needs actual implementation

---

## 📝 TESTING CHECKLIST

Once complete, test these flows:

- [ ] App launches with 3 tabs visible
- [ ] Can swipe between Upcoming/Past events
- [ ] Can tap between Upcoming/Past tabs
- [ ] Chats tab shows empty state initially
- [ ] Create event → chat automatically created
- [ ] Accept event RSVP → added to chat
- [ ] Can open chat from Chats tab
- [ ] Can send message in chat
- [ ] Message appears immediately for sender
- [ ] Other user sees message in real-time
- [ ] Last message shows in chat list
- [ ] Chat list sorted by recent activity
- [ ] Can swipe back from chat to list
- [ ] Profile tab works as before

---

## 💾 FILES MODIFIED

### New Files:
- `StepOut/MainTabView.swift`
- `StepOut/ChatsTabView.swift`
- `StepOut/ChatView.swift`
- `StepOut/EventListView.swift`

### Modified Files:
- `StepOut/ContentView.swift` - Now uses `MainTabView` instead of `MainAppContentView`

### Backend Files (To Create):
- `backend/functions/src/chat.ts` - Chat-related Cloud Functions
- `backend/firestore.rules` - Add chat security rules
- `backend/firestore.indexes.json` - Add message indexes

---

## 🚀 ESTIMATED TIME TO COMPLETE

- Backend implementation: ~45 minutes
- iOS integration: ~20 minutes
- Testing & bug fixes: ~15 minutes
- **Total: ~80 minutes**

---

Last Updated: 2025-10-22
Status: Frontend UI complete, ready for backend implementation
