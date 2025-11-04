# StepOut App Store Submission - Quick Start

**Your step-by-step guide to submitting StepOut to the App Store**

---

## 🚀 Quick Steps (Follow in Order)

### Step 1: Host Privacy Policy (10 min)

**Option A: GitHub Pages** (Recommended)
1. Create free GitHub account: https://github.com/signup
2. Create new **public** repository: `stepout-privacy`
3. Upload `PRIVACY_POLICY.md` from this folder
4. Settings → Pages → Enable from `main` branch
5. Your URL: `https://[username].github.io/stepout-privacy/PRIVACY_POLICY`

**Option B: Google Docs** (Fastest)
1. Open `PRIVACY_POLICY.md` and copy content
2. Create new Google Doc: https://docs.google.com
3. Paste content
4. Share → "Anyone with link" → Copy link

✅ **Save the URL** - you'll need it later!

---

### Step 2: Create Demo Account (5 min)

1. Go to: https://console.firebase.google.com
2. Select project: `stepout-3db1a`
3. **Authentication** → **Users** → **Add User**
4. Enter:
   ```
   Email: demo@stepout.app
   Password: StepOut2025!
   ```
5. Click **Add User**
6. Find user → three dots (⋮) → **Verify email**

✅ **Test it** - Sign in to your app with these credentials!

---

### Step 3: Take Screenshots (20 min)

1. **Open simulator**:
   ```bash
   open -a Simulator
   ```

2. **In Simulator**: Hardware → Device → iPhone 16 Pro Max

3. **Build app in Xcode**:
   - Select destination: iPhone 16 Pro Max
   - Click Run (▶) or press Cmd+R

4. **Sign in**: demo@stepout.app / StepOut2025!

5. **Take 5 screenshots** (Press **Cmd+S**):
   - Screenshot 1: **Events Feed** - Home screen
   - Screenshot 2: **Event Details** - Tap event
   - Screenshot 3: **Create Event** - Tap + button
   - Screenshot 4: **Search** - Show filters
   - Screenshot 5: **Profile** - Calendar view

6. **Find screenshots**: Saved to Desktop at 1290 x 2796 pixels

✅ Create folder `StepOut-Screenshots` and move them there

---

### Step 4: Configure Xcode Signing (5 min)

1. Open Xcode
2. Click StepOut project (left sidebar)
3. Select "StepOut" target
4. Click "Signing & Capabilities" tab
5. Configure:
   - Team: Your Apple Developer team
   - ✓ Automatically manage signing
   - Bundle Identifier: com.stepout2.app

✅ **No errors?** Ready to archive!

---

### Step 5: Archive for App Store (30 min)

1. **In Xcode**:
   - Change destination to: **"Any iOS Device (arm64)"**
   - Product → **Archive**
   - Wait 5-10 minutes

2. **Organizer opens** → Click **"Distribute App"**

3. **Select**:
   - App Store Connect → Upload → Next
   - Automatically manage signing → Next
   - Review & **Upload**

4. **Wait** 15-30 minutes for processing

✅ **Email confirmation** when done

---

### Step 6: App Store Connect Listing (30 min)

1. **Go to**: https://appstoreconnect.apple.com

2. **Create App**:
   - My Apps → "+" → New App
   - Platform: iOS
   - Name: **StepOut**
   - Language: English (U.S.)
   - Bundle ID: com.stepout2.app
   - SKU: stepout-ios-001

3. **App Information**:
   - Name: `StepOut - Events & Friends`
   - Subtitle: `Organize and discover events with friends`
   - Privacy Policy URL: [Your URL from Step 1]

4. **Categories**:
   - Primary: Social Networking
   - Secondary: Lifestyle

5. **Pricing**: Free

6. **Screenshots**: Upload 5 screenshots for "6.7-inch Display"

7. **Description**:
```
StepOut makes it easy to create, discover, and attend events with your friends.

KEY FEATURES:
• Create Events - Quick event creation with photos and categories
• Smart Discovery - Find events by category or search
• Friend Network - See what friends are attending
• Real-Time Updates - Get notified instantly
• Event Categories - Sports, Food, Study, Party, Gaming, Outdoor, Music
• Privacy Controls - Private or public events
• Calendar Integration - Track attended events

PERFECT FOR:
• College students organizing study groups
• Friend groups planning activities
• Sports teams coordinating games
• Anyone wanting quality time with friends

Download StepOut and start making memories!
```

8. **Keywords**:
```
events,friends,social,hangout,meetup,party,study,sports,food,calendar,organize
```

9. **Demo Account**:
```
Username: demo@stepout.app
Password: StepOut2025!

TESTING INSTRUCTIONS:
1. Sign in with demo account
2. View Events tab
3. Create test event with + button
4. Search and filter events
5. View Profile calendar

Note: Uses Firebase. All features work with demo account.
```

10. **Age Rating**: Complete questionnaire → 12+

11. **Add Build**: Click "+" → Select uploaded build → Export compliance: YES, YES to exempt

---

### Step 7: Submit for Review

1. Review all required fields filled
2. Click **"Add for Review"** (top right)
3. Click **"Submit to App Review"**
4. Wait for email confirmation

✅ **Review time**: 24-48 hours typically

---

## 📞 Important Info

**Demo Account**:
```
Email: demo@stepout.app
Password: StepOut2025!
```

**Bundle ID**: `com.stepout2.app`

**Privacy Policy URL**: [Add after hosting]

---

## ⏱ Time Estimate

- Privacy policy: 10 min
- Demo account: 5 min
- Screenshots: 20 min
- Xcode setup: 5 min
- Archive: 30 min
- App Store listing: 30 min

**Total**: ~2 hours

---

## 🆘 Common Issues

**"No signing identity"**
→ Xcode → Preferences → Accounts → Download Manual Profiles

**"Archive grayed out"**
→ Select "Any iOS Device (arm64)", not simulator

**"Upload failed"**
→ Check version/build number

---

## ✅ Pre-Submit Checklist

- [ ] Privacy policy URL public and accessible
- [ ] Demo account created and tested
- [ ] 5 screenshots uploaded
- [ ] App description filled
- [ ] Keywords added
- [ ] Categories selected
- [ ] Age rating completed
- [ ] Build selected
- [ ] Demo credentials in "Notes for Review"

---

**You've got this! 🚀**
