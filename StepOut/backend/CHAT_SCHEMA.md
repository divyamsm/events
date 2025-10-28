# Chat Feature - Firestore Schema Design

## Collections Structure

### `/chats/{chatId}`
Main collection for event-based group chats.

**Fields:**
- `chatId` (string): Unique identifier (same as event ID for simplicity)
- `eventId` (string): Reference to the event this chat belongs to
- `eventTitle` (string): Denormalized event title for quick display
- `participantIds` (array<string>): Array of user IDs who can access this chat
- `createdAt` (timestamp): When the chat was created
- `lastMessageAt` (timestamp): Timestamp of most recent message
- `lastMessageText` (string): Preview of last message (max 100 chars)
- `lastMessageSenderId` (string): User ID of last message sender
- `lastMessageSenderName` (string): Display name of last message sender
- `unreadCounts` (map<string, number>): Map of userId -> unread message count

**Example:**
```json
{
  "chatId": "ABC123-EVENT-ID",
  "eventId": "ABC123-EVENT-ID",
  "eventTitle": "NYC Hackathon",
  "participantIds": ["user1", "user2", "user3"],
  "createdAt": "2025-10-24T10:00:00Z",
  "lastMessageAt": "2025-10-24T15:30:00Z",
  "lastMessageText": "See you all there!",
  "lastMessageSenderId": "user1",
  "lastMessageSenderName": "John",
  "unreadCounts": {
    "user2": 3,
    "user3": 1
  }
}
```

### `/chats/{chatId}/messages/{messageId}`
Subcollection containing all messages for a chat.

**Fields:**
- `messageId` (string): Auto-generated unique ID
- `senderId` (string): User ID of message sender
- `senderName` (string): Display name of sender
- `senderPhotoURL` (string, optional): Profile photo URL
- `text` (string): Message content
- `createdAt` (timestamp): When message was sent
- `type` (string): Message type - "text", "system" (for announcements like "User joined")

**Example:**
```json
{
  "messageId": "MSG-001",
  "senderId": "user1",
  "senderName": "John",
  "senderPhotoURL": "https://...",
  "text": "Hey everyone!",
  "createdAt": "2025-10-24T15:30:00Z",
  "type": "text"
}
```

## Firestore Indexes Required

```json
{
  "indexes": [
    {
      "collectionGroup": "chats",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "participantIds", "arrayConfig": "CONTAINS" },
        { "fieldPath": "lastMessageAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "messages",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        { "fieldPath": "createdAt", "order": "ASCENDING" }
      ]
    }
  ]
}
```

## Security Rules

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Chat access rules
    match /chats/{chatId} {
      allow read: if request.auth != null &&
                     resource.data.participantIds.hasAny([request.auth.uid]);
      allow write: if false; // Only Cloud Functions can create/update chats
    }

    // Message access rules
    match /chats/{chatId}/messages/{messageId} {
      allow read: if request.auth != null &&
                     get(/databases/$(database)/documents/chats/$(chatId)).data.participantIds.hasAny([request.auth.uid]);
      allow create: if request.auth != null &&
                       get(/databases/$(database)/documents/chats/$(chatId)).data.participantIds.hasAny([request.auth.uid]) &&
                       request.resource.data.senderId == request.auth.uid;
      allow update, delete: if false; // Messages are immutable
    }
  }
}
```

## Cloud Functions API

### 1. `createChat` (Called when event is created)
**Trigger:** Called from `createEvent` function
**Parameters:**
- `eventId` (string)
- `eventTitle` (string)
- `ownerId` (string) - Auto-added as first participant

**Action:**
- Creates `/chats/{eventId}` document
- Adds owner to `participantIds`
- Sends system message: "Chat created"

### 2. `addUserToChat` (Called when user RSVPs "going")
**Trigger:** Called from `rsvpEvent` function when status = "going"
**Parameters:**
- `eventId` (string)
- `userId` (string)
- `userName` (string)

**Action:**
- Adds userId to chat's `participantIds` array
- Sends system message: "{userName} joined the event"

### 3. `sendMessage` (Callable function)
**Parameters:**
- `chatId` (string)
- `text` (string)

**Authentication:** Required
**Action:**
- Validates user is in `participantIds`
- Creates message in `/chats/{chatId}/messages/`
- Updates chat's `lastMessageAt`, `lastMessageText`, etc.
- Increments `unreadCounts` for all other participants

**Returns:**
```json
{
  "success": true,
  "messageId": "MSG-001"
}
```

### 4. `listChats` (Callable function)
**Parameters:** None
**Authentication:** Required
**Action:**
- Queries chats where `participantIds` contains current user
- Orders by `lastMessageAt` descending
- Returns list of chats

**Returns:**
```json
{
  "chats": [
    {
      "chatId": "...",
      "eventId": "...",
      "eventTitle": "NYC Hackathon",
      "lastMessageAt": "...",
      "lastMessageText": "...",
      "unreadCount": 3
    }
  ]
}
```

### 5. `getMessages` (Callable function)
**Parameters:**
- `chatId` (string)
- `limit` (number, optional, default 50)
- `before` (timestamp, optional) - For pagination

**Authentication:** Required
**Action:**
- Validates user is in chat's `participantIds`
- Queries messages, ordered by `createdAt` ascending
- Resets user's unread count to 0

**Returns:**
```json
{
  "messages": [
    {
      "messageId": "...",
      "senderId": "...",
      "senderName": "...",
      "text": "...",
      "createdAt": "...",
      "type": "text"
    }
  ]
}
```

## iOS Real-time Listener Implementation

```swift
// Listen to messages in real-time
db.collection("chats").document(chatId).collection("messages")
  .order(by: "createdAt", descending: false)
  .addSnapshotListener { snapshot, error in
    guard let snapshot = snapshot else { return }

    for change in snapshot.documentChanges {
      if change.type == .added {
        let message = parseMessage(change.document)
        self.messages.append(message)
      }
    }
  }
```
