# Backend TODOs

- [ ] Restore authentication enforcement once all APIs are wired to the app.
- [ ] Disable public read access to `events` and `members` before release.
- [ ] Replace debug auto sign-in with real auth flow when ready.

- [ ] Remove debug logging once auth is re-enabled.

- [ ] Implement friend graph APIs (`listFriends`, `sendFriendInvite`, `respondToInvite`, `removeFriend`).
- [ ] Implement event sharing callable that persists `sharedInviteFriendIds`.
- [ ] Expose profile endpoints (`getProfile`, `updateProfile`, `listAttendedEvents`).
